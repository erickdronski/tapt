#!/usr/bin/env python3
"""Grow the Tapt beer catalog with notable global beers from Wikidata (CC0).

Open Food Facts' beer category is ~92% ingested, so the next honest, free source
of real breadth is Wikidata: ~16.7K beers that carry a named brewery (P176) --
the notable/iconic beers OFF's retail-barcode set lacks, with structured brewery
+ country + ABV. Data only, no images (per-image Wikimedia licensing varies).

WDQS times out on a single ordered/paginated query over the transitive beer-style
tree, so instead we enumerate the ~420 subclasses of beer once, then fetch each
class's beers in its own small, fast, UNORDERED query. Overlaps across classes are
free: admin_ingest_wikidata_beers dedups by QID and by name+brewery, so re-running
never duplicates and existing OFF beers are enriched in place. Resumable by class
index. Blank beats invented.

Env:
  SUPABASE_URL               default https://qfwiizvqxrhjlthbjosz.supabase.co
  SUPABASE_SERVICE_ROLE_KEY  REQUIRED (server-only key)
  MAX_CLASSES                classes to process this run (default 999 -> all)
  STATE_FILE                 default scripts/.wikidata_ingest_state.json
"""
import json, os, ssl, time, urllib.request, urllib.error, urllib.parse

SUPA = os.environ.get("SUPABASE_URL", "https://qfwiizvqxrhjlthbjosz.supabase.co")
KEY  = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
MAX_CLASSES = int(os.environ.get("MAX_CLASSES", "999"))
STATE_FILE = os.environ.get("STATE_FILE", os.path.join(os.path.dirname(__file__), ".wikidata_ingest_state.json"))
UA = {"User-Agent": "TaptBeerApp/1.0 (esdronski@gmail.com) beer-catalog-ingest"}
try:
    import certifi
    CTX = ssl.create_default_context(cafile=certifi.where())  # macOS Python has no system CA bundle
except Exception:
    CTX = ssl.create_default_context()
SPARQL = "https://query.wikidata.org/sparql"

CLASSES_Q = "SELECT ?t WHERE { ?t wdt:P279* wd:Q44 . }"

# All beers of one style class, with brewery + country + ABV. No ORDER BY so WDQS
# stays well under its 60s limit; LIMIT is just a safety cap (no class is bigger).
BEERS_Q = """
SELECT ?item ?itemLabel ?breweryLabel ?countryLabel ?abv WHERE {
  ?item wdt:P31 wd:%s ; wdt:P176 ?brewery .
  OPTIONAL { ?brewery wdt:P17 ?country . }
  OPTIONAL { ?item wdt:P2665 ?abv . }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". }
}
LIMIT 8000
"""


def wdqs(query, tries=4):
    data = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(SPARQL, data=data, method="POST", headers={
                **UA, "Accept": "application/sparql-results+json",
                "Content-Type": "application/x-www-form-urlencoded",
            })
            with urllib.request.urlopen(req, context=CTX, timeout=90) as r:
                return json.loads(r.read().decode())["results"]["bindings"]
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError, KeyError) as e:
            last = e
            if i < tries - 1:
                time.sleep(15 + 15 * i)
    print(f"  query failed ({last})")
    return None


def to_row(b):
    name = (b.get("itemLabel", {}).get("value") or "").strip()
    qid = (b.get("item", {}).get("value") or "").rsplit("/", 1)[-1]
    if not name or not qid or name == qid or len(name) < 2:
        return None  # bare Q-id label = no English name; skip
    row = {"qid": qid, "name": name[:160]}
    brand = (b.get("breweryLabel", {}).get("value") or "").strip()
    if brand and not brand.startswith("Q"):
        row["brand"] = brand[:120]
    country = (b.get("countryLabel", {}).get("value") or "").strip()
    if country and not country.startswith("Q"):
        row["country"] = country[:80]
    abv = b.get("abv", {}).get("value")
    if abv:
        try:
            row["abv"] = round(float(abv), 1)
        except ValueError:
            pass
    return row


def rpc_ingest(payload, tries=5):
    url = f"{SUPA}/rest/v1/rpc/admin_ingest_wikidata_beers"
    body = json.dumps({"p_payload": payload}).encode()
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, data=body, method="POST", headers={
                **UA, "Content-Type": "application/json",
                "apikey": KEY, "Authorization": f"Bearer {KEY}",
            })
            with urllib.request.urlopen(req, context=CTX, timeout=120) as r:
                return json.loads(r.read().decode())
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, ValueError) as e:
            last = e  # transient 500s / timeouts: back off and retry so one blip can't halt the run
            if i < tries - 1:
                time.sleep(6 + 6 * i)
    raise RuntimeError(f"rpc_ingest failed after {tries} tries: {last}")


def load_state():
    try:
        return json.load(open(STATE_FILE))
    except Exception:
        return {}


def save_state(s):
    json.dump(s, open(STATE_FILE, "w"))


def main():
    if not KEY:
        raise SystemExit("SUPABASE_SERVICE_ROLE_KEY is required")
    state = load_state()
    classes = state.get("classes")
    if not classes:
        raw = wdqs(CLASSES_Q)
        if raw is None:
            raise RuntimeError("could not fetch beer-style classes")
        classes = sorted({r["t"]["value"].rsplit("/", 1)[-1] for r in raw})
        state = {"classes": classes, "idx": 0}
        save_state(state)
    idx = int(os.environ.get("START_IDX", state.get("idx", 0)))
    print(f"{len(classes)} beer-style classes; starting at index {idx}.")

    tot_ins = tot_enr = tot_skip = 0
    processed = 0
    while idx < len(classes) and processed < MAX_CLASSES:
        cls = classes[idx]
        raw = wdqs(BEERS_Q % cls)
        if raw is None:
            raise RuntimeError(f"WDQS failed on class {cls} (idx {idx}); cursor not advanced")
        seen, payload = set(), []
        for b in raw:
            row = to_row(b)
            if row and row["qid"] not in seen:
                seen.add(row["qid"])
                payload.append(row)
        pins = penr = pskip = 0
        for i in range(0, len(payload), 500):
            res = rpc_ingest(payload[i:i + 500])
            pins += res.get("inserted", 0); penr += res.get("enriched", 0); pskip += res.get("skipped", 0)
        tot_ins += pins; tot_enr += penr; tot_skip += pskip
        if payload:
            print(f"[{idx+1}/{len(classes)}] {cls}: {len(raw)} rows -> +{pins} new, {penr} enriched")
        idx += 1
        processed += 1
        state["idx"] = idx
        save_state(state)
        time.sleep(2)

    done = idx >= len(classes)
    print(f"DONE{' (all classes)' if done else ''}. inserted {tot_ins}, enriched {tot_enr}, "
          f"skipped {tot_skip}. next index {idx}/{len(classes)}.")
    if done:
        state["complete"] = True
        save_state(state)


if __name__ == "__main__":
    main()
