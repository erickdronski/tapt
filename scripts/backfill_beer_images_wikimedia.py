#!/usr/bin/env python3
"""Discover licensed Wikimedia product photos for imageless Wikidata beers.

Every source is tied to the beer's exact Wikidata QID and resolved through the
Wikimedia Commons API with per-file author and license metadata. Sources are
inserted into the private `beer_media_source_candidate` queue; they do not
become customer-visible until a generated cutout passes paired admin review.

Required for writes:
  SUPABASE_SERVICE_ROLE_KEY

Optional:
  SUPABASE_URL   Tapt production project URL
  SUPABASE_KEY   publishable key used for catalog reads
  MAX_ROWS       cap eligible Wikidata beers (0 means all)
  DRY_RUN        true to discover without database writes
"""

from __future__ import annotations

import html
import json
import os
import re
import subprocess
import time
import urllib.parse
from collections.abc import Iterable
from typing import Any


SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co"
).rstrip("/")
SUPABASE_KEY = os.environ.get(
    "SUPABASE_KEY", "sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF"
)
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
MAX_ROWS = max(0, int(os.environ.get("MAX_ROWS", "0")))
DRY_RUN = os.environ.get("DRY_RUN", "").lower() == "true"
USER_AGENT = "Tapt/1.0 (beer image provenance; https://taptbeer.com/support)"
ALLOWED_LICENSES = (
    "cc by ",
    "cc by-sa ",
    "cc0",
    "public domain",
    "public-domain",
)


class HTTPStatusError(RuntimeError):
    def __init__(self, code: int, body: str):
        super().__init__(f"HTTP {code}: {body[:300]}")
        self.code = code


def chunks(values: list[str], size: int) -> Iterable[list[str]]:
    for index in range(0, len(values), size):
        yield values[index:index + size]


def request_json(
    url: str,
    *,
    headers: dict[str, str] | None = None,
    method: str = "GET",
    payload: Any = None,
) -> Any:
    command = [
        "curl", "-sS", "-w", "\n%{http_code}", "--max-time", "60",
        "-X", method,
        "-H", f"User-Agent: {USER_AGENT}",
        "-H", "Accept: application/json",
    ]
    for name, value in (headers or {}).items():
        command.extend(("-H", f"{name}: {value}"))
    if payload is not None:
        command.extend(("--data", json.dumps(payload)))
    command.append(url)
    completed = subprocess.run(command, capture_output=True, text=True, timeout=75)
    if completed.returncode != 0:
        raise RuntimeError(f"curl failed ({completed.returncode}): {completed.stderr[:300]}")
    raw, separator, status_text = completed.stdout.rpartition("\n")
    if not separator or not status_text.isdigit():
        raise RuntimeError("curl response did not include an HTTP status")
    status = int(status_text)
    if status >= 400:
        raise HTTPStatusError(status, raw)
    return json.loads(raw) if raw else None


def rest_rows(path: str, params: dict[str, str], *, service: bool = False) -> list[dict[str, Any]]:
    key = SERVICE_KEY if service else SUPABASE_KEY
    query = urllib.parse.urlencode(params, safe="().,*:")
    return request_json(
        f"{SUPABASE_URL}/rest/v1/{path}?{query}",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )


def fetch_catalog() -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        page = rest_rows(
            "beer_catalog",
            {
                "select": "id,name,gtin,external_ids",
                "name_ok": "is.true",
                "cutout_url": "is.null",
                "label_image_url": "is.null",
                "order": "id.asc",
                "limit": "1000",
                "offset": str(offset),
            },
        )
        rows.extend(page)
        if len(page) < 1000:
            break
        offset += len(page)
    eligible = [
        row for row in rows
        if re.fullmatch(r"Q[1-9][0-9]*", str((row.get("external_ids") or {}).get("wikidata_qid", "")))
    ]
    return eligible[:MAX_ROWS] if MAX_ROWS else eligible


def existing_candidate_ids() -> set[str]:
    if not SERVICE_KEY:
        return set()
    rows: list[dict[str, Any]] = []
    offset = 0
    while True:
        page = rest_rows(
            "beer_media_source_candidate",
            {"select": "beer_id", "limit": "1000", "offset": str(offset)},
            service=True,
        )
        rows.extend(page)
        if len(page) < 1000:
            break
        offset += len(page)
    return {str(row["beer_id"]) for row in rows}


def preferred_p18_filename(entity: dict[str, Any]) -> str | None:
    claims = ((entity.get("claims") or {}).get("P18") or [])
    claims = sorted(claims, key=lambda claim: claim.get("rank") != "preferred")
    for claim in claims:
        value = (((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value"))
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def wikidata_p18(qids: list[str]) -> dict[str, str]:
    query = urllib.parse.urlencode({
        "action": "wbgetentities",
        "format": "json",
        "props": "claims",
        "ids": "|".join(qids),
    })
    payload = request_json(f"https://www.wikidata.org/w/api.php?{query}")
    result: dict[str, str] = {}
    for qid, entity in (payload.get("entities") or {}).items():
        filename = preferred_p18_filename(entity)
        if filename:
            result[qid] = filename
    return result


def clean_metadata_text(value: str | None) -> str:
    text = re.sub(r"<[^>]+>", " ", value or "")
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def metadata_field(metadata: dict[str, Any], name: str) -> str:
    return clean_metadata_text(((metadata.get(name) or {}).get("value")))


def allowed_license(value: str) -> bool:
    normalized = clean_metadata_text(value).lower()
    return any(normalized == prefix.rstrip() or normalized.startswith(prefix) for prefix in ALLOWED_LICENSES)


def build_attribution(metadata: dict[str, Any]) -> str | None:
    license_name = metadata_field(metadata, "LicenseShortName") or metadata_field(
        metadata, "UsageTerms"
    )
    if not allowed_license(license_name):
        return None
    author = metadata_field(metadata, "Artist") or metadata_field(metadata, "Credit")
    requires_author = license_name.lower().startswith(("cc by ", "cc by-sa "))
    if requires_author and not author:
        return None
    parts = [part for part in (author, license_name, "Wikimedia Commons") if part]
    return " - ".join(parts)[:500]


def normalize_filename(value: str) -> str:
    return value.replace("_", " ").strip().casefold()


def commons_sources(filenames: list[str]) -> dict[str, dict[str, Any]]:
    query = urllib.parse.urlencode({
        "action": "query",
        "format": "json",
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|sha1|timestamp|size|mime",
        "inprop": "url",
        "iiurlwidth": "1600",
        "titles": "|".join(f"File:{filename}" for filename in filenames),
    })
    payload = request_json(f"https://commons.wikimedia.org/w/api.php?{query}")
    result: dict[str, dict[str, Any]] = {}
    for page in ((payload.get("query") or {}).get("pages") or {}).values():
        info_rows = page.get("imageinfo") or []
        if not info_rows:
            continue
        info = info_rows[0]
        source_url = info.get("thumburl") or info.get("url") or ""
        parsed = urllib.parse.urlsplit(source_url)
        if parsed.scheme != "https" or parsed.hostname != "upload.wikimedia.org" or parsed.query:
            continue
        attribution = build_attribution(info.get("extmetadata") or {})
        if not attribution:
            continue
        metadata = info.get("extmetadata") or {}
        creator = metadata_field(metadata, "Artist") or metadata_field(metadata, "Credit")
        license_url = metadata_field(metadata, "LicenseUrl")
        if license_url.startswith("//"):
            license_url = f"https:{license_url}"
        if license_url and not license_url.startswith("https://"):
            license_url = ""
        title = str(page.get("title") or "").removeprefix("File:")
        result[normalize_filename(title)] = {
            "source_url": source_url,
            "source_license": attribution,
            "source_page_url": info.get("descriptionurl") or page.get("fullurl"),
            "source_license_url": license_url or None,
            "source_creator": creator or None,
            "source_revision": str(page.get("lastrevid") or info.get("timestamp") or ""),
            "source_sha1": info.get("sha1") or None,
            "source_width": info.get("width"),
            "source_height": info.get("height"),
            "source_metadata": {
                "wikimedia_file": title,
                "timestamp": info.get("timestamp"),
                "mime": info.get("mime"),
                "original_url": info.get("url"),
            },
        }
    return result


def insert_candidate(row: dict[str, Any]) -> bool:
    if DRY_RUN or not SERVICE_KEY:
        return False
    try:
        request_json(
            f"{SUPABASE_URL}/rest/v1/beer_media_source_candidate",
            method="POST",
            headers={
                "apikey": SERVICE_KEY,
                "Authorization": f"Bearer {SERVICE_KEY}",
                "Content-Type": "application/json",
                "Prefer": "return=minimal",
            },
            payload=row,
        )
        return True
    except HTTPStatusError as error:
        if error.code == 409:
            return False
        raise


def main() -> int:
    catalog = fetch_catalog()
    existing = existing_candidate_ids()
    rows = [row for row in catalog if str(row["id"]) not in existing]
    qid_to_row = {
        str((row.get("external_ids") or {})["wikidata_qid"]): row
        for row in rows
    }
    print(
        f"catalog: {len(catalog)} imageless Wikidata beers; "
        f"{len(existing)} already staged; {len(rows)} eligible"
    )
    discovered = licensed = written = 0
    for qid_batch in chunks(list(qid_to_row), 50):
        images = wikidata_p18(qid_batch)
        discovered += len(images)
        for file_batch in chunks(list(dict.fromkeys(images.values())), 50):
            sources = commons_sources(file_batch)
            for qid, filename in images.items():
                source = sources.get(normalize_filename(filename))
                if not source:
                    continue
                licensed += 1
                beer = qid_to_row[qid]
                source_gtin = str(beer.get("gtin") or "").strip()
                if insert_candidate({
                    "beer_id": beer["id"],
                    **source,
                    "source_kind": "wikimedia_commons",
                    "source_external_id": f"{qid}:P18:{filename}",
                    "source_gtin": (
                        source_gtin
                        if re.fullmatch(r"(?:[0-9]{8}|[0-9]{12,14})", source_gtin)
                        else None
                    ),
                    "status": "pending_cutout",
                }):
                    written += 1
        time.sleep(0.2)
    mode = "dry-run" if DRY_RUN or not SERVICE_KEY else "write"
    print(f"result: {discovered} P18 images, {licensed} licensed, {written} staged ({mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
