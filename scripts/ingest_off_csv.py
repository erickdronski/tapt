#!/usr/bin/env python3
"""Complete the beer catalog in one pass from the Open Food Facts BULK CSV export.

This is OFF's recommended way to get the full dataset (their search API rate-limits
page-by-page pulls). We stream the gzipped CSV, cheaply skip every non-beer line,
map the beer rows, and upsert them through `admin_ingest_beers` (idempotent by
GTIN). No search API, no throttling — it just finishes.

Env:
  SUPABASE_URL               default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_SERVICE_ROLE_KEY  REQUIRED
  BATCH                      rows per RPC call (default 300)
  CSV_URL                    override the export URL

Real data only. OFF's own (sometimes messy) tags flow through as-is.
"""
import gzip, io, json, os, ssl, sys, time, urllib.request, urllib.error

SUPA = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co")
KEY  = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
BATCH = int(os.environ.get("BATCH", "300"))
CSV_URL = os.environ.get("CSV_URL", "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz")
UA = {"User-Agent": "TaptBeerApp/1.0 (esdronski@gmail.com) beer-catalog-bulk"}
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

SKIP_TAGS = {"en:beverages-and-beverages-preparations", "en:beverages",
             "en:alcoholic-beverages", "en:beers", "en:beers-and-ciders"}


def rpc_ingest(payload, tries=3):
    body = json.dumps({"p_payload": payload}).encode()
    url = f"{SUPA}/rest/v1/rpc/admin_ingest_beers"
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=body, method="POST", headers={
                **UA, "Content-Type": "application/json",
                "apikey": KEY, "Authorization": f"Bearer {KEY}"})
            with urllib.request.urlopen(req, context=CTX, timeout=120) as r:
                return json.loads(r.read().decode())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as e:
            if i == tries - 1:
                print(f"  RPC error (batch dropped): {e}")
                return {}
            time.sleep(3 * (i + 1))


def style_from(tags):
    subs = [t.split(":", 1)[-1].replace("-", " ").title()
            for t in tags if t.startswith("en:") and t not in SKIP_TAGS]
    return subs[-1] if subs else None


def country_from(tags):
    for t in tags:
        if t.startswith("en:"):
            return t.split(":", 1)[-1].replace("-", " ").title()
    return None


def main():
    if not KEY:
        raise SystemExit("SUPABASE_SERVICE_ROLE_KEY is required")

    req = urllib.request.Request(CSV_URL, headers=UA)
    resp = urllib.request.urlopen(req, context=CTX, timeout=180)  # follows the S3 302
    gz = gzip.GzipFile(fileobj=resp)

    header = gz.readline().decode("utf-8", "replace").rstrip("\n").split("\t")
    col = {name: header.index(name) for name in
           ("code", "product_name", "brands", "categories_tags",
            "countries_tags", "image_url", "alcohol_100g") if name in header}

    def field(parts, name):
        i = col.get(name)
        return parts[i].strip() if (i is not None and i < len(parts)) else ""

    tot_ins = tot_upd = tot_skip = matched = 0
    batch, seen = [], set()
    t0 = time.time()

    for raw in gz:
        if b"en:beers" not in raw:            # cheap gate: skip ~all non-beer rows
            continue
        parts = raw.decode("utf-8", "replace").rstrip("\n").split("\t")
        cats = [c for c in field(parts, "categories_tags").split(",") if c]
        if "en:beers" not in cats:            # must actually be categorized as beer
            continue
        code = field(parts, "code")
        name = field(parts, "product_name")
        if not code or len(name) < 2 or code in seen:
            continue
        seen.add(code)
        matched += 1
        row = {
            "gtin": code,
            "name": name[:160],
            "brand": (field(parts, "brands").split(",")[0].strip() or None),
            "country": country_from([c for c in field(parts, "countries_tags").split(",") if c]),
            "style": style_from(cats),
            "image_url": field(parts, "image_url") or None,
        }
        alc = field(parts, "alcohol_100g")
        if alc:
            try: row["abv"] = round(float(alc), 1)
            except ValueError: pass
        batch.append(row)

        if len(batch) >= BATCH:
            res = rpc_ingest(batch)
            tot_ins += res.get("inserted", 0); tot_upd += res.get("updated", 0); tot_skip += res.get("skipped", 0)
            print(f"{matched} beers seen | +{tot_ins} new, {tot_upd} refreshed "
                  f"({int(time.time()-t0)}s)", flush=True)
            batch = []

    if batch:
        res = rpc_ingest(batch)
        tot_ins += res.get("inserted", 0); tot_upd += res.get("updated", 0); tot_skip += res.get("skipped", 0)

    print(f"DONE. {matched} beer rows in export → inserted {tot_ins}, "
          f"updated {tot_upd}, skipped {tot_skip}, in {int(time.time()-t0)}s.")


if __name__ == "__main__":
    main()
