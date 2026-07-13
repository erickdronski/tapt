#!/usr/bin/env python3
"""Tapt - backfill real label photos + nutrition from Open Food Facts.

For each catalog beer, full-text search OFF and accept a match ONLY when every
significant token of our beer name appears in the OFF product name (plus a
brand token check). Strict by design: a wrong image is worse than no image.
Respects OFF's search rate guidance (~10 req/min).

Reads the catalog via the public REST API (RLS: read-only), writes matches to
a JSON file for review/apply — it never writes to the database itself.

Env:
  SUPABASE_URL   default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_KEY   default publishable key (read-only under RLS)
  OUT            default ./beer_media_matches.json
  SLEEP          default 6.5 (seconds between OFF search calls)
"""
import json, os, re, subprocess, sys, time, unicodedata, urllib.parse

SUPA = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co")
KEY = os.environ.get("SUPABASE_KEY", "sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF")
OUT = os.environ.get("OUT", "./beer_media_matches.json")
SLEEP = float(os.environ.get("SLEEP", "6.5"))
UA = "Tapt/1.0 (THE Beer Superapp; media backfill; contact esdronski@gmail.com)"


def http_get(url, headers=None):
    """curl-backed GET (python.org builds lack local SSL roots)."""
    cmd = ["curl", "-s", "--max-time", "40", "-H", f"User-Agent: {UA}"]
    for k, v in (headers or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if out.returncode != 0 or not out.stdout:
        raise RuntimeError(f"curl failed ({out.returncode})")
    return out.stdout

GENERIC = {"beer", "bier", "biere", "bière", "cerveza", "birra", "pivo", "øl", "ol",
           "the", "of", "and", "de", "la", "le", "el", "no", "n", "original", "premium"}


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9 ]+", " ", s.lower()).split()


def fetch_catalog():
    beers = []
    page_size = 1000
    offset = 0
    while True:
        url = (f"{SUPA}/rest/v1/beer_catalog?"
               "select=id,name,label_image_url,brewery(name)&order=id.asc"
               f"&limit={page_size}&offset={offset}")
        page = json.loads(http_get(url, {"apikey": KEY}))
        beers.extend(page)
        if len(page) < page_size:
            return beers
        offset += page_size


def off_search(term):
    q = urllib.parse.quote(term)
    url = ("https://world.openfoodfacts.org/cgi/search.pl?"
           f"search_terms={q}&search_simple=1&action=process&json=1&page_size=10"
           "&fields=code,product_name,brands,image_front_url,nutriments,categories_tags")
    try:
        return json.loads(http_get(url)).get("products", [])
    except Exception as e:
        print(f"  search error: {e}", flush=True)
        return []


def pick(beer_name, brewery, products):
    beer_tokens = set(norm(beer_name))
    brand_tokens = set(norm(brewery))
    sig = beer_tokens - brand_tokens - GENERIC
    for p in products:
        cats = p.get("categories_tags") or []
        if not any("beer" in c for c in cats):
            continue
        pn_tokens = set(norm(p.get("product_name", ""))) | set(norm(p.get("brands", "")))
        if not p.get("image_front_url"):
            continue
        if sig:
            if not sig.issubset(pn_tokens):
                continue
            # at least one brand token should also appear (or brand is empty)
            if brand_tokens and not (brand_tokens & pn_tokens):
                continue
        else:
            # One-word beers (name == brand): demand a near-exact product name.
            if not (pn_tokens <= (brand_tokens | GENERIC) and (brand_tokens & pn_tokens)):
                continue
        return p
    return None


def nutrition(p):
    n = p.get("nutriments") or {}
    out = {}
    for src, dst in [("energy-kcal_100g", "kcal_100ml"), ("carbohydrates_100g", "carbs_g_100ml"),
                     ("proteins_100g", "protein_g_100ml"), ("sugars_100g", "sugars_g_100ml"),
                     ("alcohol_100g", "alcohol_pct")]:
        v = n.get(src)
        if isinstance(v, (int, float)) and 0 <= v < 1000:
            out[dst] = round(float(v), 2)
    return out


def main():
    beers = fetch_catalog()
    todo = [b for b in beers if not b.get("label_image_url")]
    print(f"catalog: {len(beers)} beers, {len(todo)} without images", flush=True)
    matches = []
    for i, b in enumerate(todo):
        brewery = (b.get("brewery") or {}).get("name") or ""
        term = f"{brewery} {b['name']}".strip()
        products = off_search(term)
        p = pick(b["name"], brewery, products)
        if p:
            matches.append({
                "id": b["id"],
                "beer": b["name"],
                "off_name": p.get("product_name"),
                "off_code": p.get("code"),
                "image": p.get("image_front_url"),
                "nutrition": nutrition(p),
            })
            print(f"[{i+1}/{len(todo)}] MATCH  {b['name']} -> {p.get('product_name')}", flush=True)
        else:
            print(f"[{i+1}/{len(todo)}] blank  {b['name']}", flush=True)
        time.sleep(SLEEP)

    with open(OUT, "w") as f:
        json.dump(matches, f, indent=1)
    print(f"done: {len(matches)}/{len(todo)} matched -> {OUT}", flush=True)


if __name__ == "__main__":
    main()
