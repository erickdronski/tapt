#!/usr/bin/env python3
"""Seed the `brewery` table from Open Brewery DB (MIT license, commercial-safe).

Inserts via PostgREST using the service-role key (bypasses RLS). Run once.

Env:
  SUPABASE_URL                default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_SERVICE_ROLE_KEY   REQUIRED (server-only key, from the Supabase dashboard)
  SEED_COUNT                  default 200
"""
import json, os, sys, urllib.request

SUPA  = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co")
KEY   = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
COUNT = int(os.environ.get("SEED_COUNT", "200"))
OBDB  = "https://api.openbrewerydb.org/v1/breweries"

def fetch(page, per=50):
    url = f"{OBDB}?per_page={per}&page={page}&by_country=united_states"
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read().decode())

def rows():
    out, page = [], 1
    while len(out) < COUNT:
        batch = fetch(page)
        if not batch:
            break
        for b in batch:
            if not b.get("name"):
                continue
            out.append({
                "name": b["name"],
                "country": b.get("country") or "United States",
                "website_url": b.get("website_url"),
                "external_ids": {
                    "open_brewery_db": b.get("id"),
                    "city": b.get("city"),
                    "state": b.get("state_province"),
                    "type": b.get("brewery_type"),
                },
            })
            if len(out) >= COUNT:
                break
        page += 1
    return out

def post(batch):
    req = urllib.request.Request(f"{SUPA}/rest/v1/brewery",
                                 data=json.dumps(batch).encode(), method="POST")
    req.add_header("apikey", KEY)
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("Content-Type", "application/json")
    req.add_header("Prefer", "return=minimal")
    with urllib.request.urlopen(req) as r:
        return r.status

def main():
    if not KEY:
        print("Set SUPABASE_SERVICE_ROLE_KEY (server-only, Supabase dashboard > Project Settings > API).")
        sys.exit(1)
    data = rows()
    print(f"fetched {len(data)} breweries from Open Brewery DB")
    for i in range(0, len(data), 100):
        print("insert", i, "->", post(data[i:i + 100]))
    print("done")

if __name__ == "__main__":
    main()
