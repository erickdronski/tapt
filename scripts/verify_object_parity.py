#!/usr/bin/env python3
"""Does the repo declare any object that production does not have?

This is the reproducibility question that matters. Textual ledger comparison is
noisy (repo files were edited after being applied), but object parity is exact:
if every function/table the repo creates and does not later drop exists in prod,
a replay converges."""
import json, os, re, subprocess

REPO = "/private/tmp/claude-502/-Users-Erick-Dronski-Desktop-Personal-Projects/3d7bf09b-4d0b-434b-a670-4625814a4f80/scratchpad/tapt-src/supabase/migrations"
PROJ = "qfwiizvqxrhjlthbjosz"
TOKEN = open(os.path.expanduser("~/.config/nalee/supabase.token")).read().strip()

def api_sql(q):
    out = subprocess.run(
        ["curl", "-s", "-X", "POST",
         f"https://api.supabase.com/v1/projects/{PROJ}/database/query",
         "-H", f"Authorization: Bearer {TOKEN}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps({"query": q})],
        capture_output=True, text=True).stdout
    return json.loads(out)

def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    return re.sub(r"--[^\n]*", " ", s)

CREATE_FN = re.compile(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?\"?([a-z_][a-z0-9_]*)\"?\s*\(", re.I)
DROP_FN   = re.compile(r"drop\s+function\s+(?:if\s+exists\s+)?(?:public\.)?\"?([a-z_][a-z0-9_]*)\"?", re.I)
CREATE_TB = re.compile(r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?\"?([a-z_][a-z0-9_]*)\"?", re.I)
DROP_TB   = re.compile(r"drop\s+table\s+(?:if\s+exists\s+)?(?:public\.)?\"?([a-z_][a-z0-9_]*)\"?", re.I)

created_fn, dropped_fn, created_tb, dropped_tb = set(), set(), set(), set()
for fn in sorted(os.listdir(REPO)):
    if not fn.endswith(".sql"): continue
    body = strip_comments(open(os.path.join(REPO, fn), encoding="utf-8").read())
    created_fn |= set(m.lower() for m in CREATE_FN.findall(body))
    dropped_fn |= set(m.lower() for m in DROP_FN.findall(body))
    created_tb |= set(m.lower() for m in CREATE_TB.findall(body))
    dropped_tb |= set(m.lower() for m in DROP_TB.findall(body))

live_fn = {r["proname"] for r in api_sql(
    "select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace "
    "where n.nspname='public'")}
live_tb = {r["tablename"] for r in api_sql(
    "select tablename from pg_tables where schemaname='public'")}

expected_fn = created_fn - dropped_fn
expected_tb = created_tb - dropped_tb

missing_fn = sorted(expected_fn - live_fn)
missing_tb = sorted(expected_tb - live_tb)

print(f"repo declares {len(expected_fn)} functions (after drops), {len(expected_tb)} tables")
print(f"prod has {len(live_fn)} public functions, {len(live_tb)} public tables\n")
print("=" * 68)
print(f"DECLARED BY REPO, MISSING IN PROD -- functions: {len(missing_fn)}")
for x in missing_fn: print("   -", x)
print(f"DECLARED BY REPO, MISSING IN PROD -- tables: {len(missing_tb)}")
for x in missing_tb: print("   -", x)
print()
print("A replay converges only if both lists are empty.")
