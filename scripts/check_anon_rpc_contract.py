#!/usr/bin/env python3
"""Fail CI if the live anon RPC surface drifts from supabase/anon_rpc_contract.json.

Why this exists: Postgres grants EXECUTE to PUBLIC on every CREATE FUNCTION, so a
new function is anon-callable unless you explicitly revoke it. Migration 0082 tried
to pin the surface with a one-shot `do $$ ... $$` assertion, but that runs once at
apply time and never again -- so the surface drifted from 12 functions to 24, and
the same gotcha recurred three separate times before anyone noticed.

This runs on every push instead, against real production.

Needs SUPABASE_SERVICE_ROLE_KEY. Without it the check SKIPS rather than fails, so
fork PRs (which get no secrets) are not blocked by an unrunnable check.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_URL = "https://qfwiizvqxrhjlthbjosz.supabase.co"
CONTRACT = Path(__file__).resolve().parent.parent / "supabase" / "anon_rpc_contract.json"
TIMEOUT = 30


def live_surface(service_key: str) -> list[str]:
    request = urllib.request.Request(
        f"{PROJECT_URL}/rest/v1/rpc/anon_rpc_contract",
        data=b"{}",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def _is_trusted_branch() -> bool:
    """True when running on main (or a manual/scheduled run), where secrets are
    always available. Fork pull requests get no secrets, and blocking them on an
    unrunnable check helps nobody."""
    if os.environ.get("GITHUB_REF") == "refs/heads/main":
        return True
    return os.environ.get("GITHUB_EVENT_NAME") in {"schedule", "workflow_dispatch"}


def main() -> int:
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not service_key:
        # Skipping quietly on main would mean a rotated or renamed secret turns
        # the guard off permanently with a green build and one grey log line.
        if _is_trusted_branch():
            print("anon-rpc-contract: FAILED — no SUPABASE_SERVICE_ROLE_KEY on a "
                  "trusted run. The guard cannot be silently disabled here; "
                  "restore the secret or remove the step deliberately.")
            return 1
        print("anon-rpc-contract: SKIPPED (no SUPABASE_SERVICE_ROLE_KEY; "
              "expected on fork pull requests)")
        return 0

    expected = sorted(json.loads(CONTRACT.read_text())["allowed"])

    try:
        actual = sorted(live_surface(service_key))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        print(f"anon-rpc-contract: FAILED to read live surface: HTTP {error.code} {detail}")
        return 1
    except Exception as error:  # network/DNS/timeout
        print(f"anon-rpc-contract: FAILED to read live surface: {error}")
        return 1

    added = [name for name in actual if name not in expected]
    removed = [name for name in expected if name not in actual]

    if not added and not removed:
        print(f"anon-rpc-contract: OK ({len(actual)} functions, matches the manifest)")
        return 0

    print("anon-rpc-contract: DRIFT DETECTED")
    for name in added:
        print(f"  + {name}  <- anon can execute this in prod, but it is NOT in the manifest")
    for name in removed:
        print(f"  - {name}  <- manifest allows it, but anon cannot execute it in prod")
    print()
    print("A '+' is usually the 0081 gotcha: CREATE FUNCTION grants EXECUTE to PUBLIC,")
    print("so anon inherits it. If the function is not meant to be public, fix it with")
    print("  revoke all on function public.<name>(<args>) from public;")
    print("If it IS meant to be public, add it to supabase/anon_rpc_contract.json with")
    print("a reason, in the same commit that grants it.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
