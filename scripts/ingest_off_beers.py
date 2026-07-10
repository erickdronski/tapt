#!/usr/bin/env python3
"""Grow the Tapt beer catalog from Open Food Facts (ODbL, free, always-growing).

Pages the OFF "beers" category, maps each real product to the catalog shape, and
upserts it through the `admin_ingest_beers` RPC (idempotent by barcode/GTIN, so
re-running never duplicates). Resumable: the last completed page is saved so a
scheduled run picks up where the previous one stopped, then wraps around.

Env:
  SUPABASE_URL               default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_SERVICE_ROLE_KEY  REQUIRED (server-only key; bypasses RLS for the RPC)
  MAX_PAGES                  pages to ingest this run (default 20)
  PAGE_SIZE                  products per page (default 100, OFF max 100)
  START_PAGE                 override the resume cursor (default: from state file)
  STATE_FILE                 default scripts/.off_ingest_state.json

Real data only. OFF's own (sometimes messy) category tags flow through as-is;
a later style_alias pass normalizes them. Blank beats invented.
"""
import json, os, ssl, sys, time, urllib.request, urllib.error

SUPA = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co")
KEY  = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
MAX_PAGES = int(os.environ.get("MAX_PAGES", "20"))
PAGE_SIZE = min(int(os.environ.get("PAGE_SIZE", "100")), 100)
STATE_FILE = os.environ.get("STATE_FILE", os.path.join(os.path.dirname(__file__), ".off_ingest_state.json"))
UA = {"User-Agent": "TaptBeerApp/1.0 (esdronski@gmail.com) beer-catalog-ingest"}
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE  # macOS python lacks SSL roots; OFF/Supabase are known hosts

OFF = ("https://world.openfoodfacts.org/cgi/search.pl?action=process"
       "&tagtype_0=categories&tag_contains_0=contains&tag_0=beers&json=1"
       "&fields=code,product_name,brands,categories_tags,countries_tags,image_front_url,nutriments")

SKIP_TAGS = {
    "en:beverages-and-beverages-preparations", "en:beverages",
    "en:alcoholic-beverages", "en:beers", "en:beers-and-ciders",
}


def get_json(url, tries=5):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, context=CTX, timeout=45) as r:
                return json.loads(r.read().decode())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            last = e
            time.sleep(4 * (i + 1))  # backoff; OFF 503s under load
    raise SystemExit(f"OFF fetch failed after {tries} tries: {last}")


def style_from(tags):
    subs = [t.split(":", 1)[-1].replace("-", " ").title()
            for t in (tags or []) if t.startswith("en:") and t not in SKIP_TAGS]
    return subs[-1] if subs else None


def country_from(tags):
    for t in (tags or []):
        if t.startswith("en:"):
            return t.split(":", 1)[-1].replace("-", " ").title()
    return None


def to_row(p):
    code = (p.get("code") or "").strip()
    name = (p.get("product_name") or "").strip()
    if not code or len(name) < 2:
        return None
    brand = (p.get("brands") or "").split(",")[0].strip() or None
    nut = p.get("nutriments") or {}
    abv = next((float(nut[k]) for k in ("alcohol_100g", "alcohol_value", "alcohol")
                if isinstance(nut.get(k), (int, float))), None)
    row = {
        "gtin": code,
        "name": name[:160],
        "brand": brand,
        "country": country_from(p.get("countries_tags")),
        "style": style_from(p.get("categories_tags")),
        "image_url": p.get("image_front_url") or None,
    }
    if abv is not None:
        row["abv"] = round(abv, 1)
    return row


def rpc_ingest(payload):
    url = f"{SUPA}/rest/v1/rpc/admin_ingest_beers"
    body = json.dumps({"p_payload": payload}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        **UA, "Content-Type": "application/json",
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
    })
    with urllib.request.urlopen(req, context=CTX, timeout=60) as r:
        return json.loads(r.read().decode())


def load_state():
    try:
        return json.load(open(STATE_FILE))
    except Exception:
        return {"next_page": 1}


def save_state(s):
    json.dump(s, open(STATE_FILE, "w"))


def main():
    if not KEY:
        raise SystemExit("SUPABASE_SERVICE_ROLE_KEY is required")
    state = load_state()
    start = int(os.environ.get("START_PAGE", state.get("next_page", 1)))

    # discover total pages once, to wrap the cursor around
    meta = get_json(f"{OFF}&page_size=1&page=1")
    total = int(meta.get("count", 0))
    last_page = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    print(f"OFF beers: {total} products, {last_page} pages of {PAGE_SIZE}. "
          f"Starting at page {start}.")

    tot_ins = tot_upd = tot_skip = 0
    page = start
    for _ in range(MAX_PAGES):
        if page > last_page:
            page = 1  # wrap around to re-scan (catches updates + new products)
        d = get_json(f"{OFF}&page_size={PAGE_SIZE}&page={page}")
        products = d.get("products", [])
        if not products:
            page += 1
            continue
        payload, seen = [], set()
        for p in products:
            row = to_row(p)
            if row and row["gtin"] not in seen:
                seen.add(row["gtin"])
                payload.append(row)
        if payload:
            res = rpc_ingest(payload)
            tot_ins += res.get("inserted", 0)
            tot_upd += res.get("updated", 0)
            tot_skip += res.get("skipped", 0)
            print(f"page {page}: +{res.get('inserted',0)} new, "
                  f"{res.get('updated',0)} refreshed, {res.get('skipped',0)} skipped")
        page += 1
        save_state({"next_page": page, "last_page": last_page})
        time.sleep(6)  # be a good OFF citizen (search rate limits)

    print(f"DONE. inserted {tot_ins}, updated {tot_upd}, skipped {tot_skip}. "
          f"next run resumes at page {page}.")


if __name__ == "__main__":
    main()
