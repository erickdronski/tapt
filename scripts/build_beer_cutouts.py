#!/usr/bin/env python3
"""Build transparent Tapt product cutouts from real catalog photographs.

The script reads beers that have an attributed source photo but no cutout,
removes the background locally with rembg, validates the foreground mask, and
uploads a normalized transparent PNG to the public `beer-cutouts` bucket.
Original source URLs and licenses remain untouched. Failed inputs are tracked
and bounded so one broken source cannot stall the catalog.

Required environment:
  SUPABASE_SERVICE_ROLE_KEY  server-only key used by GitHub Actions

Optional environment / flags:
  SUPABASE_URL  default Tapt production project URL
  BATCH         successful outputs per run (default 100, max 300)
  MODEL         rembg model (default isnet-general-use)
  DRY_RUN       true to process without database/storage writes
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

import numpy as np
import requests
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps, UnidentifiedImageError
from scipy import ndimage


SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co"
).rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
USER_AGENT = "Tapt/1.0 (beer media quality pipeline; esdronski@gmail.com)"
OUTPUT_SIZE = 1024
MAX_SOURCE_BYTES = 16 * 1024 * 1024
MAX_SOURCE_PIXELS = 40_000_000
MAX_ATTEMPTS = 3
MIN_OUTPUT_FOREGROUND_EDGE = 700
PIPELINE_VERSION = "v2"
MAX_PRODUCT_ASPECT = 0.72
MIN_SILHOUETTE_SYMMETRY = 0.84
MAX_CENTERLINE_DEVIATION = 0.10
MAX_BASE_FLARE = 1.10
MAX_SECONDARY_COMPONENT = 0.015
MAX_INTERNAL_HOLE_FRACTION = 0.004
PERMANENT_REJECTION_CODES = {
    "manual_quality_rejection",
    "visual_quality_review",
}
SOURCE_HOSTS = {
    "images.openfoodfacts.org",
    "qfwiizvqxrhjlthbjosz.supabase.co",
}
CUTOUT_PATH_PATTERN = re.compile(
    r"^/storage/v1/object/public/beer-cutouts/(?:v2/)?"
    r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}[.]png$"
)

Image.MAX_IMAGE_PIXELS = MAX_SOURCE_PIXELS


class PipelineError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Candidate:
    id: str
    name: str
    source_url: str
    license: str | None
    attempts: int = 0


@dataclass(frozen=True)
class Cutout:
    png: bytes
    source_sha256: str
    foreground_fraction: float
    effective_source_url: str
    source_width: int
    source_height: int


class SupabaseAPI:
    def __init__(self, url: str, key: str, dry_run: bool):
        self.url = url
        self.key = key
        self.dry_run = dry_run
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "User-Agent": USER_AGENT,
        })

    def request(self, method: str, path: str, **kwargs: Any) -> requests.Response:
        last_error: Exception | None = None
        for attempt in range(3):
            try:
                response = self.session.request(
                    method, f"{self.url}{path}", timeout=(15, 90), **kwargs
                )
                if response.status_code >= 500 and attempt < 2:
                    time.sleep(2 ** attempt)
                    continue
                response.raise_for_status()
                return response
            except requests.RequestException as error:
                last_error = error
                if attempt < 2:
                    time.sleep(2 ** attempt)
        raise PipelineError("supabase_request", str(last_error))

    def candidates(self, target_count: int, retry_rejected: bool) -> list[Candidate]:
        # Terminal failures keep cutout_url empty, so a fixed first-page query
        # eventually stalls behind rows that are correctly skipped. Page through
        # the catalog until this run has a full batch or reaches the real end.
        page_size = 500
        offset = 0
        result: list[Candidate] = []
        while len(result) < target_count:
            # cutout_queue orders the SAME candidates by live market standing
            # first, so the beers people actually see get real art first; the
            # long tail still drains oldest-first behind them.
            rows = self.request(
                "GET",
                "/rest/v1/cutout_queue",
                params={
                    "select": "id,name,label_image_url,label_image_license,updated_at",
                    "or": "(cutout_url.is.null,cutout_url.eq.)",
                    "order": "market_standing.desc.nullslast,updated_at.asc,id.asc",
                    "limit": str(page_size),
                    "offset": str(offset),
                },
            ).json()
            if not rows:
                break

            statuses: dict[str, dict[str, Any]] = {}
            for start in range(0, len(rows), 40):
                ids = ",".join(row["id"] for row in rows[start:start + 40])
                status_rows = self.request(
                    "GET",
                    "/rest/v1/beer_media_processing",
                    params={
                        "select": "beer_id,status,attempts,source_url,error_code,pipeline_version",
                        "beer_id": f"in.({ids})",
                    },
                ).json()
                statuses.update({row["beer_id"]: row for row in status_rows})

            for row in rows:
                source_url = (row.get("label_image_url") or "").strip()
                if not source_url.startswith("https://"):
                    continue
                status = statuses.get(row["id"], {})
                attempts = int(status.get("attempts") or 0)
                same_source = status.get("source_url") == source_url
                same_version = status.get("pipeline_version") == PIPELINE_VERSION
                permanent_rejection = status.get("error_code") in PERMANENT_REJECTION_CODES
                terminal = status.get("status") in {"completed", "pending_review", "rejected"}
                if same_source and permanent_rejection and not retry_rejected:
                    continue
                if same_source and same_version and terminal and not retry_rejected:
                    continue
                if same_source and same_version and attempts >= MAX_ATTEMPTS and not retry_rejected:
                    continue
                result.append(Candidate(
                    id=row["id"],
                    name=(row.get("name") or "Unnamed beer").strip(),
                    source_url=source_url,
                    license=row.get("label_image_license"),
                    attempts=attempts if same_source and same_version else 0,
                ))
                if len(result) >= target_count:
                    break

            offset += len(rows)
            if len(rows) < page_size:
                break
        print(f"catalog scan: {offset} rows inspected for {len(result)} candidates")
        return result

    def mark(self, candidate: Candidate, status: str, **values: Any) -> None:
        if self.dry_run:
            return
        row = {
            "beer_id": candidate.id,
            "source_url": candidate.source_url,
            "status": status,
            "pipeline_version": PIPELINE_VERSION,
            "attempts": candidate.attempts + (0 if status == "processing" else 1),
            "updated_at": datetime.now(timezone.utc).isoformat(),
            **values,
        }
        self.request(
            "POST",
            "/rest/v1/beer_media_processing?on_conflict=beer_id",
            headers={
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal",
            },
            json=row,
        )

    def stage(self, candidate: Candidate, cutout: Cutout) -> str:
        object_name = f"{PIPELINE_VERSION}/{candidate.id}.png"
        if self.dry_run:
            return f"dry-run://beer-cutouts/{object_name}"
        self.request(
            "POST",
            f"/storage/v1/object/beer-cutouts/{quote(object_name)}",
            headers={"Content-Type": "image/png", "x-upsert": "true"},
            data=cutout.png,
        )
        public_url = f"{self.url}/storage/v1/object/public/beer-cutouts/{object_name}"
        return public_url


def validate_candidate(candidate: Candidate) -> None:
    parsed = urlsplit(candidate.source_url)
    if (
        parsed.scheme != "https"
        or parsed.username
        or parsed.password
        or parsed.port is not None
        or parsed.hostname not in SOURCE_HOSTS
        or parsed.query
        or parsed.fragment
    ):
        raise PipelineError("source_not_allowed", "source host is not approved")
    if (
        parsed.hostname == "qfwiizvqxrhjlthbjosz.supabase.co"
        and CUTOUT_PATH_PATTERN.fullmatch(parsed.path) is None
    ):
        raise PipelineError("source_not_allowed", "Supabase source is not a recognized cutout object")
    if not (candidate.license or "").strip():
        raise PipelineError("source_license_missing", "source has no recorded image license")
    if is_multipack(candidate.name):
        raise PipelineError("multipack_source", "product name identifies a pack or case")


def preferred_source_urls(source_url: str) -> list[str]:
    """Prefer OFF's real full-resolution selected image, with thumbnail fallback."""
    parsed = urlsplit(source_url)
    urls: list[str] = []
    if parsed.hostname == "images.openfoodfacts.org":
        full_path = re.sub(r"\.(?:100|200|400)\.jpg$", ".full.jpg", parsed.path)
        if full_path != parsed.path:
            urls.append(urlunsplit(parsed._replace(path=full_path)))
    urls.append(source_url)
    return list(dict.fromkeys(urls))


def download_source(
    session: requests.Session,
    candidate: Candidate,
) -> tuple[bytes, Image.Image, str, tuple[int, int]]:
    errors: list[str] = []
    last_pipeline_code: str | None = None
    for source_url in preferred_source_urls(candidate.source_url):
        response: requests.Response | None = None
        try:
            response = session.get(
                source_url,
                headers={"User-Agent": USER_AGENT},
                timeout=(15, 60),
                stream=True,
            )
            response.raise_for_status()
            content_type = response.headers.get("Content-Type", "").split(";", 1)[0].lower()
            if content_type and not content_type.startswith("image/"):
                raise PipelineError("source_not_image", f"unexpected content type {content_type}")
            chunks: list[bytes] = []
            size = 0
            for chunk in response.iter_content(64 * 1024):
                size += len(chunk)
                if size > MAX_SOURCE_BYTES:
                    raise PipelineError("source_too_large", "source exceeds 16 MB")
                chunks.append(chunk)
            source = b"".join(chunks)
            if not source:
                raise PipelineError("source_empty", "source returned no bytes")
            try:
                image = Image.open(io.BytesIO(source))
                image.seek(0)
                image = ImageOps.exif_transpose(image).convert("RGB")
                image.load()
            except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as error:
                raise PipelineError("source_decode", str(error)) from error
            if min(image.size) < 160:
                raise PipelineError(
                    "source_too_small",
                    f"source is only {image.width}x{image.height}",
                )
            if image.width * image.height > MAX_SOURCE_PIXELS:
                raise PipelineError("source_too_large", "source exceeds pixel limit")
            source_dimensions = image.size
            image.thumbnail((1800, 1800), Image.Resampling.LANCZOS)
            return source, image, source_url, source_dimensions
        except PipelineError as error:
            last_pipeline_code = error.code
            errors.append(f"{source_url}: {error}")
        except (
            requests.RequestException,
            UnidentifiedImageError,
            OSError,
            Image.DecompressionBombError,
        ) as error:
            errors.append(f"{source_url}: {error}")
        finally:
            if response is not None:
                response.close()
    message = errors[-1] if errors else "source could not be downloaded"
    raise PipelineError(last_pipeline_code or "source_download", message)


def primary_component(mask: np.ndarray) -> np.ndarray:
    labels, count = ndimage.label(mask, structure=np.ones((3, 3), dtype=np.uint8))
    if count == 0:
        raise PipelineError("empty_mask", "background model found no foreground")
    areas = np.bincount(labels.ravel())[1:]
    order = np.argsort(areas)[::-1]
    largest_index = int(order[0])
    largest_area = int(areas[largest_index])
    if len(order) > 1:
        second_fraction = float(areas[int(order[1])] / largest_area)
        if second_fraction > MAX_SECONDARY_COMPONENT:
            raise PipelineError(
                "multiple_foregrounds",
                f"secondary foreground is {second_fraction:.3f} of primary",
            )
    return labels == largest_index + 1


def validate_source_mask(mask: np.ndarray) -> np.ndarray:
    primary = primary_component(mask)
    ys, xs = np.where(primary)
    margin = max(2, round(min(mask.shape) * 0.004))
    if (
        int(xs.min()) <= margin
        or int(ys.min()) <= margin
        or int(xs.max()) >= mask.shape[1] - margin - 1
        or int(ys.max()) >= mask.shape[0] - margin - 1
    ):
        raise PipelineError("foreground_cropped", "foreground touches the source edge")
    return primary


def normalize_cutout(
    source: bytes,
    image: Image.Image,
    rembg_session: Any,
    product_name: str = "",
    effective_source_url: str = "",
    source_dimensions: tuple[int, int] | None = None,
) -> Cutout:
    from rembg import remove

    result = remove(
        image,
        session=rembg_session,
        alpha_matting=True,
        alpha_matting_foreground_threshold=245,
        alpha_matting_background_threshold=8,
        alpha_matting_erode_size=8,
    ).convert("RGBA")
    alpha = result.getchannel("A")
    # A firmer threshold keeps low-alpha model noise from making the crop look
    # tiny on its transparent square canvas. The original feathered edge is
    # retained in the actual crop.
    mask = alpha.point(lambda value: 255 if value > 96 else 0)
    primary = validate_source_mask(np.asarray(mask) > 0)
    cleaned_alpha = np.asarray(alpha).copy()
    cleaned_alpha[~primary] = 0
    result.putalpha(Image.fromarray(cleaned_alpha.astype(np.uint8), mode="L"))
    mask = Image.fromarray((primary * 255).astype(np.uint8), mode="L")
    bbox = mask.getbbox()
    if bbox is None:
        raise PipelineError("empty_mask", "background model found no foreground")
    histogram = mask.histogram()
    foreground_fraction = histogram[255] / float(result.width * result.height)
    if foreground_fraction < 0.025:
        raise PipelineError("mask_too_small", f"foreground is {foreground_fraction:.3f} of image")
    if foreground_fraction > 0.92:
        raise PipelineError("mask_too_large", f"foreground is {foreground_fraction:.3f} of image")

    left, top, right, bottom = bbox
    width, height = right - left, bottom - top
    padding = max(12, int(max(width, height) * 0.045))
    crop = result.crop((
        max(0, left - padding),
        max(0, top - padding),
        min(result.width, right + padding),
        min(result.height, bottom + padding),
    ))

    max_edge = OUTPUT_SIZE - 128
    scale = min(max_edge / crop.width, max_edge / crop.height)
    # A bounded upscale gives common 400px OFF photos a premium app-ready size
    # without pretending a tiny source has detail it does not contain.
    scale = min(scale, 2.5)
    target = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    if target != crop.size:
        crop = crop.resize(target, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(crop, ((OUTPUT_SIZE - crop.width) // 2, (OUTPUT_SIZE - crop.height) // 2))
    validate_normalized_cutout(canvas, product_name)
    presentation = add_studio_depth(canvas)

    output = io.BytesIO()
    presentation.save(output, format="PNG", optimize=True, compress_level=9)
    return Cutout(
        png=output.getvalue(),
        source_sha256=hashlib.sha256(source).hexdigest(),
        foreground_fraction=foreground_fraction,
        effective_source_url=effective_source_url,
        source_width=(source_dimensions or image.size)[0],
        source_height=(source_dimensions or image.size)[1],
    )


def is_multipack(product_name: str) -> bool:
    return bool(re.search(
        r"(?:\bpack\b|\bcase\b|\bcarton\b|\bmultipack\b|"
        r"\b\d+\s*[xX]\s*\d+\b|\b\d+\s*(?:ct|count|cans?|bottles?)\b)",
        product_name,
        re.IGNORECASE,
    ))


def validate_normalized_cutout(image: Image.Image, product_name: str = "") -> None:
    """Reject visibly weak foregrounds before they become catalog defaults."""
    if is_multipack(product_name):
        raise PipelineError("multipack_source", "product name identifies a pack or case")
    rgba = np.asarray(image.convert("RGBA"))
    alpha = rgba[:, :, 3]
    mask = alpha > 96
    primary_component(mask)
    ys, xs = np.where(mask)
    if not len(xs):
        raise PipelineError("empty_mask", "normalized cutout has no foreground")

    left, top = int(xs.min()), int(ys.min())
    right, bottom = int(xs.max()) + 1, int(ys.max()) + 1
    width, height = right - left, bottom - top
    if max(width, height) < MIN_OUTPUT_FOREGROUND_EDGE:
        raise PipelineError(
            "output_too_small",
            f"foreground edge is only {max(width, height)}px",
        )

    crop_mask = mask[top:bottom, left:right]
    occupancy = float(crop_mask.mean())
    if occupancy < 0.48:
        raise PipelineError("mask_sparse", f"foreground occupancy is {occupancy:.3f}")

    holes = np.logical_and(ndimage.binary_fill_holes(crop_mask), ~crop_mask)
    hole_fraction = float(holes.sum() / max(1, crop_mask.sum()))
    if hole_fraction > MAX_INTERNAL_HOLE_FRACTION:
        raise PipelineError(
            "mask_internal_damage",
            f"transparent holes are {hole_fraction:.3f} of foreground",
        )

    aspect = width / height
    if aspect > MAX_PRODUCT_ASPECT:
        raise PipelineError(
            "mask_not_portrait",
            f"foreground width/height is {aspect:.3f}",
        )

    mirrored = np.fliplr(crop_mask)
    union = np.logical_or(crop_mask, mirrored).sum()
    symmetry = float(np.logical_and(crop_mask, mirrored).sum() / union)
    if symmetry < MIN_SILHOUETTE_SYMMETRY:
        raise PipelineError("mask_asymmetric", f"silhouette symmetry is {symmetry:.3f}")

    row_widths = crop_mask.sum(axis=1).astype(np.float32)
    row_centers = np.array([
        float(np.where(row)[0].mean()) if row.any() else np.nan
        for row in crop_mask
    ])
    centers = row_centers[~np.isnan(row_centers)]
    centerline_deviation = float(
        np.percentile(np.abs(centers - np.median(centers)), 95) / max(1, width)
    )
    if centerline_deviation > MAX_CENTERLINE_DEVIATION:
        raise PipelineError(
            "mask_centerline_drift",
            f"centerline deviation is {centerline_deviation:.3f}",
        )

    base = row_widths[round(height * 0.78):round(height * 0.97)]
    body = row_widths[round(height * 0.40):round(height * 0.72)]
    base = base[base > 0]
    body = body[body > 0]
    if len(base) and len(body):
        base_flare = float(np.median(base) / np.median(body))
        if base_flare > MAX_BASE_FLARE:
            raise PipelineError("mask_base_flare", f"base flare is {base_flare:.3f}")

    visible_alpha = alpha[mask]
    median_alpha = float(np.median(visible_alpha))
    if median_alpha < 224:
        raise PipelineError("alpha_too_soft", f"median alpha is {median_alpha:.0f}")

    rgb = rgba[:, :, :3].astype(np.float32)
    luminance = (
        rgb[:, :, 0] * 0.2126
        + rgb[:, :, 1] * 0.7152
        + rgb[:, :, 2] * 0.0722
    )[mask]
    median_luminance = float(np.median(luminance))
    if median_luminance < 24:
        raise PipelineError(
            "image_too_dark",
            f"median luminance is {median_luminance:.1f}",
        )
    contrast = float(np.percentile(luminance, 90) - np.percentile(luminance, 10))
    if contrast < 30:
        raise PipelineError("image_low_contrast", f"luminance range is {contrast:.1f}")


def add_studio_depth(image: Image.Image) -> Image.Image:
    """Ground the real transparent product with subtle, background-free depth."""
    product = image.convert("RGBA")
    alpha = product.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value > 96 else 0).getbbox()
    if bbox is None:
        return product
    left, top, right, bottom = bbox
    width, height = right - left, bottom - top

    ambient = alpha.filter(ImageFilter.GaussianBlur(radius=max(8, width * 0.035)))
    ambient = ambient.point(lambda value: round(value * 0.075))
    shifted = Image.new("L", product.size, 0)
    shifted.paste(ambient, (0, max(4, round(height * 0.012))))

    contact = Image.new("L", product.size, 0)
    draw = ImageDraw.Draw(contact)
    center_x = (left + right) / 2
    half_width = max(18, width * 0.38)
    shadow_height = max(10, height * 0.025)
    draw.ellipse(
        (
            center_x - half_width,
            bottom - shadow_height * 0.45,
            center_x + half_width,
            bottom + shadow_height,
        ),
        fill=92,
    )
    contact = contact.filter(ImageFilter.GaussianBlur(radius=max(10, width * 0.04)))
    shadow_alpha = ImageChops.lighter(shifted, contact)
    shadow = Image.new("RGBA", product.size, (16, 12, 8, 0))
    shadow.putalpha(shadow_alpha)
    return Image.alpha_composite(shadow, product)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch", type=int, default=int(os.environ.get("BATCH", "100")))
    parser.add_argument("--model", default=os.environ.get("MODEL", "isnet-general-use"))
    parser.add_argument("--dry-run", action="store_true", default=os.environ.get("DRY_RUN", "").lower() == "true")
    parser.add_argument("--retry-rejected", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    batch = max(1, min(args.batch, 300))
    if not SERVICE_KEY:
        print("SUPABASE_SERVICE_ROLE_KEY is required", file=sys.stderr)
        return 2

    from rembg import new_session

    api = SupabaseAPI(SUPABASE_URL, SERVICE_KEY, args.dry_run)
    candidates = api.candidates(target_count=batch, retry_rejected=args.retry_rejected)
    print(f"cutout batch: {len(candidates)} candidates, model={args.model}, dry_run={args.dry_run}")
    if not candidates:
        return 0

    rembg_session = new_session(args.model)
    download_session = requests.Session()
    staged = rejected = retry = 0
    for index, candidate in enumerate(candidates, 1):
        print(f"[{index}/{len(candidates)}] {candidate.name}", flush=True)
        api.mark(candidate, "processing", error_code=None)
        try:
            validate_candidate(candidate)
            source, image, effective_source_url, source_dimensions = download_source(
                download_session,
                candidate,
            )
            cutout = normalize_cutout(
                source,
                image,
                rembg_session,
                candidate.name,
                effective_source_url,
                source_dimensions,
            )
            url = api.stage(candidate, cutout)
            api.mark(
                candidate,
                "pending_review",
                source_sha256=cutout.source_sha256,
                effective_source_url=cutout.effective_source_url,
                source_width=cutout.source_width,
                source_height=cutout.source_height,
                output_width=OUTPUT_SIZE,
                output_height=OUTPUT_SIZE,
                foreground_fraction=round(cutout.foreground_fraction, 5),
                candidate_cutout_url=url,
                error_code=None,
            )
            staged += 1
            print(f"  staged for review {url}", flush=True)
        except PipelineError as error:
            terminal = candidate.attempts + 1 >= MAX_ATTEMPTS or error.code in {
                "source_not_image", "source_decode", "source_too_small", "source_too_large",
                "empty_mask", "mask_too_small", "mask_too_large",
                "output_too_small", "mask_sparse", "mask_not_portrait",
                "mask_internal_damage", "mask_asymmetric", "mask_centerline_drift", "mask_base_flare",
                "multiple_foregrounds", "foreground_cropped", "multipack_source",
                "source_not_allowed", "source_license_missing", "alpha_too_soft",
                "image_too_dark", "image_low_contrast",
            }
            api.mark(candidate, "rejected" if terminal else "retry", error_code=error.code)
            if terminal:
                rejected += 1
            else:
                retry += 1
            print(f"  {error.code}: {error}", flush=True)
        except Exception as error:  # one malformed product must not stop the batch
            api.mark(candidate, "retry", error_code=type(error).__name__[:80])
            retry += 1
            print(f"  unexpected: {error}", flush=True)

    print(f"done: {staged} pending review, {rejected} rejected, {retry} retry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
