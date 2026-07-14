#!/usr/bin/env python3
"""Tapt - backfill the remaining missing beer label images from Open Food Facts.

The app renders image_url = COALESCE(cutout_url, label_image_url) from the
beer_trend_feed view. This script fills the raw source column,
beer_catalog.label_image_url, for listable beers (name_ok = true) that currently
have neither a cutout nor a label image.

Two honest, rate-limited phases against OFF's free API (ODbL):

  1. Barcode rows (have a gtin): GET /api/v2/product/<gtin>.json and accept the
     product's FRONT image if one exists. The barcode identifies the exact
     product, so no fuzzy name match is needed - the front photo IS this beer.

  2. No-barcode rows: full-text search OFF by brand + product name and accept a
     match ONLY when every significant token of our name appears in the OFF
     product name (plus a brand-token check). Strict by design: a wrong image is
     worse than no image. US craft has a low OFF hit rate; blank beats invented.

Every accepted image URL is HEAD-validated (200 + image/*) so we never write a
dead link. Real data only - the imageless tail with no OFF source stays blank.

Reads through the public REST API (publishable key, RLS read-only). Writes only
when SUPABASE_SERVICE_ROLE_KEY is available (env or a gitignored .env/.env.local
in the repo root); otherwise runs resolve-only and records matches to OUT for a
later apply. curl-backed HTTP (python.org builds lack local SSL roots).

Env:
  SUPABASE_URL               default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_KEY               default publishable key (read-only under RLS)
  SUPABASE_SERVICE_ROLE_KEY  optional; required to write label_image_url
  OUT                        default ./beer_image_backfill.json
  SLEEP_BARCODE              seconds between product-API calls (default 1.0)
  SLEEP_SEARCH               seconds between search-API calls (default 6.5)
  LIMIT_BARCODE / LIMIT_SEARCH   cap rows per phase (0 = all; default all)
  DRY_RUN                    "true" to resolve without writing even if key present
  APPLY_FROM                 path to a prior OUT json; skip OFF resolution and
                             just PATCH every recorded match (needs service key)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
import unicodedata
import urllib.parse

SUPA = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co").rstrip("/")
READ_KEY = os.environ.get("SUPABASE_KEY", "sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF")
OUT = os.environ.get("OUT", os.path.join(os.path.dirname(__file__), "..", "beer_image_backfill.json"))
SLEEP_BARCODE = float(os.environ.get("SLEEP_BARCODE", "1.0"))
SLEEP_SEARCH = float(os.environ.get("SLEEP_SEARCH", "6.5"))
LIMIT_BARCODE = int(os.environ.get("LIMIT_BARCODE", "0"))
LIMIT_SEARCH = int(os.environ.get("LIMIT_SEARCH", "0"))
SKIP_BARCODE = os.environ.get("SKIP_BARCODE", "").lower() == "true"
SKIP_SEARCH = os.environ.get("SKIP_SEARCH", "").lower() == "true"
STATE_FILE = os.environ.get("STATE_FILE",
                            os.path.join(os.path.dirname(__file__), ".image_backfill_state.json"))
DRY_RUN = os.environ.get("DRY_RUN", "").lower() == "true"
UA = "Tapt/1.0 (THE Beer Superapp; image backfill; contact esdronski@gmail.com)"
LICENSE = "Open Food Facts (ODbL)"


def load_service_key() -> str:
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if key:
        return key
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    for name in (".env.local", ".env"):
        path = os.path.join(root, name)
        if not os.path.exists(path):
            continue
        try:
            for line in open(path):
                line = line.strip()
                if line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
        except OSError:
            pass
    return ""


SERVICE_KEY = load_service_key()


def http_get(url: str, headers: dict | None = None) -> str:
    cmd = ["curl", "-s", "--max-time", "45", "-H", f"User-Agent: {UA}"]
    for k, v in (headers or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=70)
    if out.returncode != 0 or not out.stdout:
        raise RuntimeError(f"curl GET failed ({out.returncode})")
    return out.stdout


def off_get(url: str, tries: int = 6) -> tuple[str, str]:
    """OFF GET -> (http_status, body). Retries 429/5xx with a long backoff that
    lets the rate window reset (hammering only deepens the block). Returns
    ("429", "") if still throttled after `tries` so callers never mistake a
    throttle for a genuine miss."""
    for i in range(tries):
        out = subprocess.run(
            ["curl", "-s", "-w", "\n%{http_code}", "--max-time", "45",
             "-H", f"User-Agent: {UA}", url],
            capture_output=True, text=True, timeout=70,
        )
        if out.returncode != 0:
            time.sleep(8 * (i + 1))
            continue
        body, _, code = out.stdout.rpartition("\n")
        code = code.strip()
        if code == "429" or code[:1] == "5" or (not body and code != "404"):
            time.sleep(25 + 20 * i)  # respect the throttle window
            continue
        return code, body
    return "429", ""


def head_ok(url: str) -> bool:
    """True only if the image URL resolves to a reachable 200 image/* resource."""
    if not url or not url.startswith("https://"):
        return False
    out = subprocess.run(
        ["curl", "-s", "-L", "-I", "--max-time", "30", "-H", f"User-Agent: {UA}", url],
        capture_output=True, text=True, timeout=45,
    )
    if out.returncode != 0:
        return False
    status_ok = bool(re.search(r"HTTP/\S+\s+200", out.stdout))
    is_image = bool(re.search(r"(?i)content-type:\s*image/", out.stdout))
    return status_ok and is_image


# ---- REST catalog access -------------------------------------------------

def rest_get(path: str, params: dict, want_count: bool = False):
    query = urllib.parse.urlencode(params, safe="().,*:")
    cmd = ["curl", "-s", "--max-time", "45",
           "-H", f"User-Agent: {UA}", "-H", f"apikey: {READ_KEY}"]
    if want_count:
        cmd += ["-D", "-", "-H", "Prefer: count=exact", "-H", "Range: 0-0"]
    cmd.append(f"{SUPA}/rest/v1/{path}?{query}")
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=70)
    if out.returncode != 0:
        raise RuntimeError(f"curl REST failed ({out.returncode})")
    if want_count:
        m = re.search(r"(?i)content-range:\s*\S+/(\d+)", out.stdout)
        return int(m.group(1)) if m else None
    return json.loads(out.stdout)


IMAGELESS = {
    "name_ok": "is.true",
    "cutout_url": "is.null",
    "label_image_url": "is.null",
}


def coverage() -> tuple[int, int]:
    total = rest_get("beer_catalog", {"select": "id", "name_ok": "is.true"}, want_count=True)
    with_img = rest_get("beer_catalog", {
        "select": "id", "name_ok": "is.true",
        "or": "(cutout_url.not.is.null,label_image_url.not.is.null)",
    }, want_count=True)
    return with_img, total


def fetch_rows(with_gtin: bool, limit: int) -> list[dict]:
    rows: list[dict] = []
    page_size = 1000
    offset = 0
    while True:
        params = {
            "select": "id,name,gtin,brewery(name)",
            "order": "id.asc",
            "limit": str(page_size),
            "offset": str(offset),
            **IMAGELESS,
            "gtin": "not.is.null" if with_gtin else "is.null",
        }
        page = rest_get("beer_catalog", params)
        rows.extend(page)
        if len(page) < page_size:
            break
        offset += page_size
    return rows[:limit] if limit else rows


def patch_image(beer_id: str, image_url: str) -> None:
    body = json.dumps({
        "label_image_url": image_url,
        "label_image_license": LICENSE,
    })
    out = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "45",
         "-X", "PATCH",
         "-H", f"User-Agent: {UA}",
         "-H", f"apikey: {SERVICE_KEY}",
         "-H", f"Authorization: Bearer {SERVICE_KEY}",
         "-H", "Content-Type: application/json",
         "-H", "Prefer: return=minimal",
         "--data", body,
         f"{SUPA}/rest/v1/beer_catalog?id=eq.{beer_id}"],
        capture_output=True, text=True, timeout=70,
    )
    code = out.stdout.strip()
    if code not in ("200", "204"):
        raise RuntimeError(f"PATCH {beer_id} -> HTTP {code}")


# ---- OFF resolution ------------------------------------------------------

def off_product_front(gtin: str) -> tuple[str, str | None]:
    """Return (state, image_url). state in {found, none, notfound, throttled}."""
    url = (f"https://world.openfoodfacts.org/api/v2/product/"
           f"{urllib.parse.quote(gtin)}.json"
           "?fields=code,product_name,image_front_url")
    code, body = off_get(url)
    if code == "429":
        return "throttled", None
    if code == "404":
        return "notfound", None
    try:
        d = json.loads(body)
    except Exception:
        return "throttled", None
    if d.get("status") != 1:
        return "notfound", None
    img = (d.get("product") or {}).get("image_front_url") or None
    return ("found", img) if img else ("none", None)


GENERIC = {"beer", "bier", "biere", "biere", "cerveza", "birra", "pivo", "ol",
           "the", "of", "and", "de", "la", "le", "el", "no", "n",
           "original", "premium", "ale", "lager"}


def norm(s: str) -> list[str]:
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).split()


def off_search(term: str) -> tuple[bool, list[dict]]:
    """Return (got_valid_response, products). got_valid_response is False on a
    throttle/error so callers can retry rather than record a false blank."""
    q = urllib.parse.quote(term)
    url = ("https://world.openfoodfacts.org/cgi/search.pl?"
           f"search_terms={q}&search_simple=1&action=process&json=1&page_size=12"
           "&fields=code,product_name,brands,image_front_url,categories_tags")
    code, body = off_get(url)
    if code != "200" or not body:
        return False, []
    try:
        return True, json.loads(body).get("products", [])
    except Exception:
        return False, []


def pick(beer_name: str, brewery: str, products: list[dict]) -> dict | None:
    beer_tokens = set(norm(beer_name))
    brand_tokens = set(norm(brewery))
    sig = beer_tokens - brand_tokens - GENERIC
    for p in products:
        cats = p.get("categories_tags") or []
        if not any("beer" in c for c in cats):
            continue
        if not p.get("image_front_url"):
            continue
        pn = set(norm(p.get("product_name", ""))) | set(norm(p.get("brands", "")))
        if sig:
            if not sig.issubset(pn):
                continue
            if brand_tokens and not (brand_tokens & pn):
                continue
        else:
            if not (pn <= (brand_tokens | GENERIC) and (brand_tokens & pn)):
                continue
        return p
    return None


# ---- main ----------------------------------------------------------------

def apply_from(path: str) -> int:
    """Resolution already done: PATCH every recorded match. Needs the service key."""
    if not SERVICE_KEY:
        print("APPLY_FROM needs SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        return 2
    data = json.load(open(path))
    matches = data.get("matches", data) if isinstance(data, dict) else data
    with_img_before, total = coverage()
    print(f"apply-from: {path}  ({len(matches)} recorded matches)")
    print(f"before: {with_img_before}/{total} ({100*with_img_before/total:.2f}%)", flush=True)
    written = 0
    for i, m in enumerate(matches, 1):
        if not m.get("image"):
            continue
        try:
            patch_image(m["id"], m["image"])
            written += 1
            print(f"[{i}/{len(matches)}] set {m.get('beer')}", flush=True)
        except Exception as e:
            print(f"[{i}/{len(matches)}] FAILED {m.get('beer')}: {e}", flush=True)
    with_img_after, total_after = coverage()
    print(f"written: {written}")
    print(f"after: {with_img_after}/{total_after} ({100*with_img_after/total_after:.2f}%)", flush=True)
    return 0


def load_state() -> set[str]:
    try:
        return set(json.load(open(STATE_FILE)).get("done", []))
    except Exception:
        return set()


def save_state(done: set[str]) -> None:
    try:
        json.dump({"done": sorted(done)}, open(STATE_FILE, "w"))
    except OSError:
        pass


def main() -> int:
    apply_path = os.environ.get("APPLY_FROM", "").strip()
    if apply_path:
        return apply_from(apply_path)
    write = bool(SERVICE_KEY) and not DRY_RUN
    mode = "WRITE" if write else ("DRY_RUN (no writes)" if DRY_RUN else "RESOLVE-ONLY (no service key)")
    with_img_before, total = coverage()
    print(f"mode: {mode}")
    print(f"before: {with_img_before}/{total} listable have an image "
          f"({100*with_img_before/total:.2f}%)", flush=True)

    done = load_state()  # ids with a definitive answer (match or confirmed blank)
    barcode_rows = [] if SKIP_BARCODE else fetch_rows(with_gtin=True, limit=LIMIT_BARCODE)
    search_rows = [] if SKIP_SEARCH else fetch_rows(with_gtin=False, limit=LIMIT_SEARCH)
    print(f"worklist: {len(barcode_rows)} barcode, {len(search_rows)} no-barcode "
          f"({len(done)} already resolved in a prior run)", flush=True)

    out_path = os.path.abspath(OUT)
    matches: list[dict] = []
    throttled: list[dict] = []
    written = 0

    def flush_out():
        with open(out_path, "w") as f:
            json.dump({"matches": matches, "throttled": throttled,
                       "written": written, "mode": mode}, f, indent=1)

    def record_match(rec):
        nonlocal written
        matches.append(rec)
        done.add(rec["id"])
        if write:
            try:
                patch_image(rec["id"], rec["image"])
                written += 1
            except Exception as e:
                print(f"    write failed: {e}", flush=True)
        flush_out()
        save_state(done)

    # Phase 1 - barcode lookups
    print("\n== phase 1: barcode -> OFF product front image ==", flush=True)
    for i, b in enumerate(barcode_rows, 1):
        if b["id"] in done:
            continue
        state, img = off_product_front(b["gtin"])
        if state == "found" and head_ok(img):
            record_match({"id": b["id"], "phase": "barcode", "beer": b["name"],
                          "gtin": b["gtin"], "off_code": b["gtin"], "image": img})
            print(f"[b {i}/{len(barcode_rows)}] MATCH {b['name']} -> {img}", flush=True)
        elif state == "throttled":
            throttled.append({"id": b["id"], "gtin": b["gtin"], "beer": b["name"]})
            print(f"[b {i}/{len(barcode_rows)}] throttled {b['name']}", flush=True)
        else:  # none / notfound / dead-link -> confirmed no image
            done.add(b["id"]); save_state(done)
            print(f"[b {i}/{len(barcode_rows)}] blank ({state}) {b['name']}", flush=True)
        time.sleep(SLEEP_BARCODE)

    # Phase 2 - name search (strict)
    print("\n== phase 2: brand+name -> OFF search (strict match) ==", flush=True)
    for i, b in enumerate(search_rows, 1):
        if b["id"] in done:
            continue
        brewery = (b.get("brewery") or {}).get("name") or ""
        term = f"{brewery} {b['name']}".strip()
        ok_resp, products = off_search(term)
        if not ok_resp:  # throttle/error - retry on a later run, do NOT blank
            throttled.append({"id": b["id"], "beer": b["name"]})
            print(f"[s {i}/{len(search_rows)}] throttled {b['name']}", flush=True)
            time.sleep(SLEEP_SEARCH)
            continue
        p = pick(b["name"], brewery, products)
        img = p.get("image_front_url") if p else None
        if img and head_ok(img):
            record_match({"id": b["id"], "phase": "search", "beer": b["name"],
                          "gtin": None, "off_code": p.get("code"),
                          "off_name": p.get("product_name"), "image": img})
            print(f"[s {i}/{len(search_rows)}] MATCH {b['name']} -> {p.get('product_name')}", flush=True)
        else:  # confirmed: OFF has no strict-matching front image
            done.add(b["id"]); save_state(done)
            print(f"[s {i}/{len(search_rows)}] blank {b['name']}", flush=True)
        time.sleep(SLEEP_SEARCH)

    flush_out()
    b_hits = sum(1 for m in matches if m["phase"] == "barcode")
    s_hits = sum(1 for m in matches if m["phase"] == "search")
    print(f"\nresolved this run: {b_hits} barcode, {s_hits} search ({len(matches)} total)", flush=True)
    if throttled:
        print(f"throttled (retry next run): {len(throttled)}", flush=True)
    print(f"written to DB: {written}", flush=True)
    print(f"matches -> {out_path}", flush=True)

    with_img_after, total_after = coverage()
    print(f"after: {with_img_after}/{total_after} listable have an image "
          f"({100*with_img_after/total_after:.2f}%)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
