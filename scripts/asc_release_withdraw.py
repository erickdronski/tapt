#!/usr/bin/env python3
"""Withdraw Tapt 1.0 from review only for a verified build replacement.

This intentionally destructive release operation is guarded by the exact
currently selected build, a newer VALID replacement build, a single-item
review submission, and an exact confirmation phrase.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH,
EXPECTED_CURRENT_BUILD_NUMBER, REPLACEMENT_BUILD_NUMBER,
CONFIRM_WITHDRAW="WITHDRAW TAPT 1.0 BUILD <current> FOR <replacement>".
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt


KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
EXPECTED_CURRENT_BUILD_NUMBER = os.environ.get(
    "EXPECTED_CURRENT_BUILD_NUMBER", ""
).strip()
REPLACEMENT_BUILD_NUMBER = os.environ.get("REPLACEMENT_BUILD_NUMBER", "").strip()
CONFIRM_WITHDRAW = os.environ.get("CONFIRM_WITHDRAW", "")
EXECUTE_WITHDRAWAL = os.environ.get("EXECUTE_WITHDRAWAL", "false").lower() == "true"
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"


def token() -> str:
    with open(KEY_PATH, encoding="utf-8") as handle:
        key = handle.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def api(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token())
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            return error.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return error.code, {"raw": raw[:500]}


def require(label: str, status: int, body: dict, expected: tuple[int, ...]) -> dict:
    if status not in expected:
        errors = body.get("errors", [])
        detail = errors[0].get("detail") if errors else body.get("raw")
        raise RuntimeError(f"{label} failed ({status}): {detail or 'unknown error'}")
    print(f"{label}: {status}")
    return body


def build_number(build: dict | None) -> str:
    return str((build or {}).get("attributes", {}).get("version") or "")


def main() -> int:
    if not EXPECTED_CURRENT_BUILD_NUMBER or not REPLACEMENT_BUILD_NUMBER:
        raise RuntimeError(
            "EXPECTED_CURRENT_BUILD_NUMBER and REPLACEMENT_BUILD_NUMBER are required"
        )
    if not (
        EXPECTED_CURRENT_BUILD_NUMBER.isdigit()
        and REPLACEMENT_BUILD_NUMBER.isdigit()
    ):
        raise RuntimeError("Current and replacement build numbers must be numeric")
    if int(REPLACEMENT_BUILD_NUMBER) <= int(EXPECTED_CURRENT_BUILD_NUMBER):
        raise RuntimeError("Replacement build number must be newer than current build")

    expected_confirmation = (
        f"WITHDRAW TAPT 1.0 BUILD {EXPECTED_CURRENT_BUILD_NUMBER} "
        f"FOR {REPLACEMENT_BUILD_NUMBER}"
    )
    if CONFIRM_WITHDRAW != expected_confirmation:
        raise RuntimeError(f"CONFIRM_WITHDRAW must exactly equal {expected_confirmation}")

    encoded_bundle = urllib.parse.quote(BUNDLE_ID, safe="")
    status, body = api("GET", f"/v1/apps?filter[bundleId]={encoded_bundle}&limit=1")
    require("app lookup", status, body, (200,))
    apps = body.get("data", [])
    if len(apps) != 1:
        raise RuntimeError(f"Expected exactly one Tapt app; found {len(apps)}")
    app_id = apps[0]["id"]

    status, body = api(
        "GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20"
    )
    require("version lookup", status, body, (200,))
    matching_versions = [
        item
        for item in body.get("data", [])
        if item.get("attributes", {}).get("versionString") == "1.0"
        and item.get("attributes", {}).get("appStoreState") == "WAITING_FOR_REVIEW"
    ]
    if len(matching_versions) != 1:
        raise RuntimeError(
            "Expected exactly one Tapt 1.0 version in WAITING_FOR_REVIEW; "
            f"found {len(matching_versions)}"
        )
    version = matching_versions[0]
    version_id = version["id"]

    status, body = api("GET", f"/v1/appStoreVersions/{version_id}/build")
    require("selected build lookup", status, body, (200,))
    selected_build = body.get("data")
    selected_number = build_number(selected_build)
    selected_processing = (selected_build or {}).get("attributes", {}).get(
        "processingState"
    )
    if (
        selected_number != EXPECTED_CURRENT_BUILD_NUMBER
        or selected_processing != "VALID"
    ):
        raise RuntimeError(
            f"Selected build is {selected_number or 'missing'} ({selected_processing}); "
            f"expected VALID build {EXPECTED_CURRENT_BUILD_NUMBER}"
        )

    status, body = api(
        "GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=50"
    )
    require("replacement build lookup", status, body, (200,))
    replacement_builds = [
        item
        for item in body.get("data", [])
        if build_number(item) == REPLACEMENT_BUILD_NUMBER
        and item.get("attributes", {}).get("processingState") == "VALID"
    ]
    if len(replacement_builds) != 1:
        raise RuntimeError(
            f"Expected exactly one VALID replacement build {REPLACEMENT_BUILD_NUMBER}; "
            f"found {len(replacement_builds)}"
        )

    status, body = api(
        "GET",
        f"/v1/apps/{app_id}/reviewSubmissions?filter[state]=WAITING_FOR_REVIEW&limit=20",
    )
    require("active submission lookup", status, body, (200,))
    submissions = body.get("data", [])
    if len(submissions) != 1:
        raise RuntimeError(
            "Expected exactly one review submission in WAITING_FOR_REVIEW; "
            f"found {len(submissions)}"
        )
    submission_id = submissions[0]["id"]

    status, body = api(
        "GET",
        f"/v1/reviewSubmissions/{submission_id}/items?include=appStoreVersion&limit=50",
    )
    require("submission item lookup", status, body, (200,))
    items = body.get("data", [])
    if len(items) != 1:
        raise RuntimeError(
            "Refusing to withdraw a review submission that does not contain exactly "
            f"one item; found {len(items)}"
        )
    relationship = items[0].get("relationships", {}).get("appStoreVersion", {}).get(
        "data"
    )
    if not isinstance(relationship, dict) or relationship.get("id") != version_id:
        raise RuntimeError("The only review item is not the expected Tapt 1.0 version")

    print(
        f"verified replacement: selected build {EXPECTED_CURRENT_BUILD_NUMBER}; "
        f"VALID replacement build {REPLACEMENT_BUILD_NUMBER}; "
        "single Tapt 1.0 review item"
    )
    if not EXECUTE_WITHDRAWAL:
        print(
            "DRY RUN: withdrawal preflight passed; the App Store review submission "
            "was not changed."
        )
        return 0

    status, body = api(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"canceled": True},
            }
        },
    )
    require("withdraw Tapt 1.0 from review", status, body, (200,))

    deadline = time.monotonic() + 120
    last_state = ""
    while time.monotonic() < deadline:
        status, body = api("GET", f"/v1/appStoreVersions/{version_id}")
        require("post-withdrawal version lookup", status, body, (200,))
        last_state = str(body.get("data", {}).get("attributes", {}).get("appStoreState"))
        if last_state == "DEVELOPER_REJECTED":
            print(
                "Tapt 1.0 withdrawal completed; version is DEVELOPER_REJECTED and "
                f"ready to prepare with build {REPLACEMENT_BUILD_NUMBER}."
            )
            return 0
        time.sleep(5)

    raise RuntimeError(
        "Withdrawal request was accepted, but Tapt 1.0 did not reach "
        f"DEVELOPER_REJECTED within 120 seconds (last state={last_state or 'unknown'})"
    )


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"FATAL: {error}")
        sys.exit(1)
