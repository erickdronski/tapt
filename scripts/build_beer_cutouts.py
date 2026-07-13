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
from urllib.parse import quote

import requests
from PIL import Image, ImageOps, UnidentifiedImageError


SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co"
).rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
USER_AGENT = "Tapt/1.0 (beer media quality pipeline; esdronski@gmail.com)"
OUTPUT_SIZE = 1024
MAX_SOURCE_BYTES = 16 * 1024 * 1024
MAX_SOURCE_PIXELS = 40_000_000
MAX_ATTEMPTS = 3

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
            rows = self.request(
                "GET",
                "/rest/v1/beer_catalog",
                params={
                    "select": "id,name,label_image_url,label_image_license,updated_at",
                    "label_image_url": "not.is.null",
                    "or": "(cutout_url.is.null,cutout_url.eq.)",
                    "order": "updated_at.asc,id.asc",
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
                        "select": "beer_id,status,attempts,source_url",
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
                terminal = status.get("status") in {"completed", "rejected"}
                if same_source and terminal and not retry_rejected:
                    continue
                if same_source and attempts >= MAX_ATTEMPTS and not retry_rejected:
                    continue
                result.append(Candidate(
                    id=row["id"],
                    name=(row.get("name") or "Unnamed beer").strip(),
                    source_url=source_url,
                    license=row.get("label_image_license"),
                    attempts=attempts if same_source else 0,
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

    def publish(self, candidate: Candidate, cutout: Cutout) -> str:
        object_name = f"{candidate.id}.png"
        if self.dry_run:
            return f"dry-run://beer-cutouts/{object_name}"
        self.request(
            "POST",
            f"/storage/v1/object/beer-cutouts/{quote(object_name)}",
            headers={"Content-Type": "image/png", "x-upsert": "true"},
            data=cutout.png,
        )
        public_url = f"{self.url}/storage/v1/object/public/beer-cutouts/{object_name}"
        self.request(
            "PATCH",
            f"/rest/v1/beer_catalog?id=eq.{candidate.id}",
            headers={"Content-Type": "application/json", "Prefer": "return=minimal"},
            json={"cutout_url": public_url},
        )
        return public_url


def download_source(session: requests.Session, candidate: Candidate) -> tuple[bytes, Image.Image]:
    try:
        response = session.get(
            candidate.source_url,
            headers={"User-Agent": USER_AGENT},
            timeout=(15, 60),
            stream=True,
        )
        response.raise_for_status()
    except requests.RequestException as error:
        raise PipelineError("source_download", str(error)) from error

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
        raise PipelineError("source_too_small", f"source is only {image.width}x{image.height}")
    if image.width * image.height > MAX_SOURCE_PIXELS:
        raise PipelineError("source_too_large", "source exceeds pixel limit")
    image.thumbnail((1800, 1800), Image.Resampling.LANCZOS)
    return source, image


def normalize_cutout(
    source: bytes,
    image: Image.Image,
    rembg_session: Any,
    product_name: str = "",
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

    # OFF occasionally stores a can/bottle photographed sideways. Very wide
    # single-object silhouettes are normalized upright; multipacks and wider
    # scenes below this threshold retain their authored orientation.
    multipack = bool(re.search(r"(?:\bpack\b|\bcase\b|\b\d+\s*[xX]\s*\d+)", product_name))
    if not multipack and crop.width > crop.height * 1.6:
        crop = crop.rotate(90, expand=True)

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

    output = io.BytesIO()
    canvas.save(output, format="PNG", optimize=True, compress_level=9)
    return Cutout(
        png=output.getvalue(),
        source_sha256=hashlib.sha256(source).hexdigest(),
        foreground_fraction=foreground_fraction,
    )


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
    completed = rejected = retry = 0
    for index, candidate in enumerate(candidates, 1):
        print(f"[{index}/{len(candidates)}] {candidate.name}", flush=True)
        api.mark(candidate, "processing", error_code=None)
        try:
            source, image = download_source(download_session, candidate)
            cutout = normalize_cutout(source, image, rembg_session, candidate.name)
            url = api.publish(candidate, cutout)
            api.mark(
                candidate,
                "completed",
                source_sha256=cutout.source_sha256,
                output_width=OUTPUT_SIZE,
                output_height=OUTPUT_SIZE,
                foreground_fraction=round(cutout.foreground_fraction, 5),
                error_code=None,
            )
            completed += 1
            print(f"  published {url}", flush=True)
        except PipelineError as error:
            terminal = candidate.attempts + 1 >= MAX_ATTEMPTS or error.code in {
                "source_not_image", "source_too_small", "source_too_large",
                "empty_mask", "mask_too_small", "mask_too_large",
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

    print(f"done: {completed} completed, {rejected} rejected, {retry} retry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
