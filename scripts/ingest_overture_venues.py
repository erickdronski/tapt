#!/usr/bin/env python3
"""Ingest high-confidence beer-serving places from Overture Maps.

The job queries Overture's public monthly GeoParquet release with DuckDB,
keeps a geographically balanced slice, stages it through PostgREST, and asks
Postgres to conflate it with the existing Open Brewery DB venue layer.

Required for writes:
  SUPABASE_SERVICE_ROLE_KEY

Optional:
  SUPABASE_URL       defaults to the Tapt project
  OVERTURE_RELEASE   defaults to 2026-06-17.0

Use --dry-run to inspect source counts and samples without touching Supabase.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Iterable

try:
    import duckdb
    import h3
    import pycountry
except ImportError as exc:  # pragma: no cover - exercised by workflow setup
    raise SystemExit(
        "ingestion dependencies are required: "
        "python -m pip install duckdb==1.4.3 h3==4.3.1 pycountry==24.6.1"
    ) from exc


SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co"
).rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
DEFAULT_RELEASE = os.environ.get("OVERTURE_RELEASE", "2026-06-17.0")

# Selected explicitly from Overture's official taxonomy. Categories such as
# juice bars, hookah bars, wine bars, and private clubs are intentionally out.
BEER_PLACE_CATEGORIES = (
    "bar",
    "bar_and_grill_restaurant",
    "beach_bar",
    "beer_bar",
    "beer_garden",
    "brasserie",
    "brewery",
    "dive_bar",
    "gastropub",
    "hotel_bar",
    "irish_pub",
    "lounge",
    "piano_bar",
    "pub",
    "speakeasy",
    "sports_bar",
    "tiki_bar",
    "whiskey_bar",
)

ALLOWED_SOURCE_LICENSES = {
    "apache-2.0",
    "cdla-permissive-2.0",
    "cc0-1.0",
}

COUNTRY_NAME_OVERRIDES = {
    "BO": "Bolivia",
    "BN": "Brunei",
    "CD": "Democratic Republic of the Congo",
    "CG": "Republic of the Congo",
    "CI": "Cote d'Ivoire",
    "CZ": "Czechia",
    "GB": "United Kingdom",
    "IR": "Iran",
    "KR": "South Korea",
    "LA": "Laos",
    "MD": "Moldova",
    "PS": "Palestine",
    "RU": "Russia",
    "SY": "Syria",
    "TZ": "Tanzania",
    "US": "United States",
    "VE": "Venezuela",
    "VN": "Vietnam",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", default=DEFAULT_RELEASE)
    parser.add_argument("--confidence", type=float, default=0.86)
    parser.add_argument("--max-rows", type=int, default=120_000)
    parser.add_argument("--per-region", type=int, default=1_500)
    parser.add_argument("--batch-size", type=int, default=400)
    parser.add_argument(
        "--country",
        action="append",
        default=[],
        help="Optional ISO-2 country filter; repeat for multiple countries.",
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def source_path(release: str) -> str:
    return (
        "s3://overturemaps-us-west-2/release/"
        f"{release}/theme=places/type=place/*"
    )


def query_places(args: argparse.Namespace) -> list[dict[str, Any]]:
    if not 0 <= args.confidence <= 1:
        raise SystemExit("--confidence must be between 0 and 1")
    if not 1 <= args.max_rows <= 500_000:
        raise SystemExit("--max-rows must be between 1 and 500000")
    if not 1 <= args.per_region <= 10_000:
        raise SystemExit("--per-region must be between 1 and 10000")

    category_marks = ",".join("?" for _ in BEER_PLACE_CATEGORIES)
    country_filter = ""
    params: list[Any] = list(BEER_PLACE_CATEGORIES)
    params.append(args.confidence)
    if args.country:
        countries = sorted({country.upper() for country in args.country})
        country_filter = f"and upper(addresses[1].country) in ({','.join('?' for _ in countries)})"
        params.extend(countries)
    params.extend((args.per_region, args.max_rows))

    query = f"""
      with filtered as (
        select
          id,
          version,
          names.primary as name,
          categories.primary as category,
          bbox.ymin as latitude,
          bbox.xmin as longitude,
          addresses[1].freeform as address,
          addresses[1].locality as locality,
          addresses[1].region as region,
          addresses[1].postcode as postcode,
          upper(addresses[1].country) as country_code,
          websites[1] as website_url,
          phones[1] as phone,
          confidence,
          date_refreshed,
          cast(sources as json)::varchar as sources_json,
          row_number() over (
            partition by
              coalesce(upper(addresses[1].country), 'ZZ'),
              coalesce(addresses[1].region, addresses[1].locality, 'unknown')
            order by confidence desc, date_refreshed desc nulls last, id
          ) as region_rank
        from read_parquet('{source_path(args.release)}', union_by_name=true)
        where categories.primary in ({category_marks})
          and confidence >= ?
          and (operating_status is null or operating_status = 'open')
          and names.primary is not null
          and bbox.xmin between -180 and 180
          and bbox.ymin between -90 and 90
          {country_filter}
      )
      select * exclude(region_rank)
      from filtered
      where region_rank <= ?
      order by country_code nulls last, region nulls last, locality nulls last,
               confidence desc, id
      limit ?
    """

    connection = duckdb.connect()
    connection.execute("install httpfs")
    connection.execute("load httpfs")
    connection.execute("set s3_region='us-west-2'")
    rows = connection.execute(query, params).fetchall()
    columns = [item[0] for item in connection.description]
    connection.close()

    result: list[dict[str, Any]] = []
    for values in rows:
        raw = dict(zip(columns, values, strict=True))
        source_dataset, source_license = first_source(raw.pop("sources_json", None))
        country_code = clean_text(raw["country_code"], 2)
        country = country_name(country_code)
        source_license = normalize_license(source_license)
        if not country or source_license not in ALLOWED_SOURCE_LICENSES:
            continue
        latitude = float(raw["latitude"])
        longitude = float(raw["longitude"])
        result.append(
            {
                "overture_id": raw["id"],
                "release_id": args.release,
                "version": raw["version"],
                "name": clean_text(raw["name"], 180),
                "category": raw["category"],
                "latitude": latitude,
                "longitude": longitude,
                "h3_cell": h3.latlng_to_cell(latitude, longitude, 8),
                "address": clean_text(raw["address"], 300),
                "locality": clean_text(raw["locality"], 160),
                "region": clean_text(raw["region"], 160),
                "postcode": clean_text(raw["postcode"], 40),
                "country": country,
                "country_code": country_code,
                "website_url": clean_text(raw["website_url"], 500),
                "phone": clean_text(raw["phone"], 80),
                "confidence": round(float(raw["confidence"]), 3),
                "source_dataset": clean_text(source_dataset, 120),
                "source_license": source_license,
                "date_refreshed": raw["date_refreshed"].isoformat()
                if raw["date_refreshed"]
                else None,
            }
        )
    return result


def clean_text(value: Any, limit: int) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text[:limit] if text else None


def normalize_license(value: Any) -> str | None:
    text = clean_text(value, 80)
    return text.lower() if text else None


def country_name(code: str | None) -> str | None:
    if not code:
        return None
    if code in COUNTRY_NAME_OVERRIDES:
        return COUNTRY_NAME_OVERRIDES[code]
    country = pycountry.countries.get(alpha_2=code)
    return country.name if country else None


def first_source(raw: str | None) -> tuple[str | None, str | None]:
    try:
        sources = json.loads(raw or "[]")
    except (TypeError, ValueError):
        return None, None
    if not isinstance(sources, list):
        return None, None
    root = next(
        (
            item
            for item in sources
            if isinstance(item, dict) and not item.get("property")
        ),
        None,
    )
    source = root or next((item for item in sources if isinstance(item, dict)), {})
    return source.get("dataset"), source.get("license")


def request_json(
    path: str,
    *,
    method: str = "POST",
    payload: Any | None = None,
    prefer: str | None = None,
    attempts: int = 4,
) -> Any:
    if not SERVICE_KEY:
        raise RuntimeError("SUPABASE_SERVICE_ROLE_KEY is required for writes")
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "User-Agent": "Tapt/1.0 Overture venue ingestion",
    }
    if prefer:
        headers["Prefer"] = prefer
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(
                f"{SUPABASE_URL}{path}", data=body, method=method, headers=headers
            )
            with urllib.request.urlopen(request, timeout=180) as response:
                data = response.read()
                return json.loads(data) if data else None
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as error:
            last_error = error
            if attempt == attempts - 1:
                break
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"Supabase request failed for {path}: {last_error}")


def chunks(rows: list[dict[str, Any]], size: int) -> Iterable[list[dict[str, Any]]]:
    for start in range(0, len(rows), size):
        yield rows[start : start + size]


def start_run(args: argparse.Namespace) -> str:
    run_id = request_json(
        "/rest/v1/rpc/record_ingestion_run",
        payload={
            "p_source_id": "overture_places",
            "p_run_kind": "venue",
            "p_status": "running",
            "p_metadata": {
                "release": args.release,
                "confidence": args.confidence,
                "max_rows": args.max_rows,
                "per_region": args.per_region,
                "countries": args.country,
            },
        },
    )
    return str(run_id).strip('"')


def finish_run(run_id: str, status: str, **fields: Any) -> None:
    request_json(
        f"/rest/v1/ingestion_run?id=eq.{run_id}",
        method="PATCH",
        payload={
            "status": status,
            "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            **fields,
        },
        prefer="return=minimal",
    )


def upload(rows: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    run_id = start_run(args)
    try:
        uploaded = 0
        for batch in chunks(rows, args.batch_size):
            request_json(
                "/rest/v1/overture_place_import?on_conflict=overture_id",
                payload=batch,
                prefer="resolution=merge-duplicates,return=minimal",
            )
            uploaded += len(batch)
            print(f"staged {uploaded:,}/{len(rows):,}")
        result = request_json(
            "/rest/v1/rpc/apply_overture_place_import",
            payload={"p_release": args.release},
        )
        counts = (result or [{}])[0] if isinstance(result, list) else (result or {})
        finish_run(
            run_id,
            "succeeded",
            records_seen=len(rows),
            records_inserted=counts.get("venues_inserted", 0),
            records_updated=(
                counts.get("venues_updated", 0) + counts.get("venues_matched", 0)
            ),
            records_rejected=0,
            metadata={
                "release": args.release,
                "confidence": args.confidence,
                "source_links_written": counts.get("source_links_written", 0),
            },
        )
        return counts
    except Exception as error:
        try:
            finish_run(run_id, "failed", error_text=str(error)[:1_000])
        except Exception:
            pass
        raise


def print_summary(rows: list[dict[str, Any]], args: argparse.Namespace) -> None:
    by_category = collections.Counter(row["category"] for row in rows)
    by_country = collections.Counter(row.get("country") or "unknown" for row in rows)
    source_licenses = collections.Counter(
        row.get("source_license") or "unspecified" for row in rows
    )
    print(
        f"Overture {args.release}: selected {len(rows):,} places at "
        f"confidence >= {args.confidence:.2f}"
    )
    print("categories:", json.dumps(dict(by_category.most_common()), sort_keys=True))
    print("countries:", len(by_country), "top:", by_country.most_common(15))
    print("source licenses:", dict(source_licenses.most_common()))
    for row in rows[:5]:
        print(
            "sample:",
            row["name"],
            row["category"],
            row.get("locality"),
            row.get("region"),
            row.get("country"),
        )


def main() -> int:
    args = parse_args()
    rows = query_places(args)
    print_summary(rows, args)
    if args.dry_run:
        return 0
    if not SERVICE_KEY:
        raise SystemExit("SUPABASE_SERVICE_ROLE_KEY is required unless --dry-run is used")
    counts = upload(rows, args)
    print("applied:", json.dumps(counts, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
