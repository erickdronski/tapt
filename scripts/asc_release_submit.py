#!/usr/bin/env python3
"""Submit Tapt 1.0 to App Review after the audited release gates pass.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, EXPECTED_BUILD_NUMBER,
CONFIRM_SUBMIT="SUBMIT TAPT 1.0".
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
EXPECTED_BUILD_NUMBER = os.environ.get("EXPECTED_BUILD_NUMBER", "").strip()
CONFIRM_SUBMIT = os.environ.get("CONFIRM_SUBMIT", "")
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
}


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
        detail = "; ".join(
            str(error.get("detail") or error.get("title") or error)
            for error in errors
        ) if errors else body.get("raw")
        raise RuntimeError(f"{label} failed ({status}): {detail or 'unknown error'}")
    print(f"{label}: {status}")
    return body


def review_submission_items(submission_id: str) -> list[dict]:
    status, body = api(
        "GET",
        f"/v1/reviewSubmissions/{submission_id}/items?include=appStoreVersion&limit=50",
    )
    require("submission item lookup", status, body, (200,))
    return body.get("data", [])


def item_app_store_version_id(item: dict) -> str:
    relationship = item.get("relationships", {}).get("appStoreVersion", {}).get("data")
    if not isinstance(relationship, dict) or not relationship.get("id"):
        raise RuntimeError(
            f"Could not establish appStoreVersion for submission item {item.get('id')}"
        )
    return str(relationship["id"])


def find_submission_item_for_version(
    app_id: str, state: str, version_id: str
) -> tuple[dict, dict, list[dict]] | None:
    status, body = api(
        "GET",
        f"/v1/apps/{app_id}/reviewSubmissions?filter[state]={state}&limit=20",
    )
    require(f"{state.lower()} submission lookup", status, body, (200,))
    for submission in body.get("data", []):
        items = review_submission_items(submission["id"])
        for item in items:
            if item_app_store_version_id(item) == version_id:
                return submission, item, items
    return None


def mark_submission_item_resolved(item: dict) -> None:
    item_id = item["id"]
    status, body = api(
        "PATCH",
        f"/v1/reviewSubmissionItems/{item_id}",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "id": item_id,
                "attributes": {"resolved": True},
            }
        },
    )
    require("mark rejected item resolved", status, body, (200,))


def main() -> int:
    if CONFIRM_SUBMIT != "SUBMIT TAPT 1.0":
        raise RuntimeError("CONFIRM_SUBMIT must exactly equal SUBMIT TAPT 1.0")
    if not EXPECTED_BUILD_NUMBER:
        raise RuntimeError("EXPECTED_BUILD_NUMBER is required")

    encoded_bundle = urllib.parse.quote(BUNDLE_ID, safe="")
    status, body = api("GET", f"/v1/apps?filter[bundleId]={encoded_bundle}&limit=1")
    require("app lookup", status, body, (200,))
    apps = body.get("data", [])
    if not apps:
        raise RuntimeError("Tapt app not found")
    app_id = apps[0]["id"]

    status, body = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")
    require("version lookup", status, body, (200,))
    version = next(
        (
            item
            for item in body.get("data", [])
            if item.get("attributes", {}).get("versionString") == "1.0"
            and item.get("attributes", {}).get("appStoreState")
            in EDITABLE_VERSION_STATES
        ),
        None,
    )
    if not version:
        raise RuntimeError("Editable Tapt 1.0 version not found")
    version_id = version["id"]

    status, body = api("GET", f"/v1/appStoreVersions/{version_id}/build")
    require("selected build lookup", status, body, (200,))
    build = body.get("data")
    build_number = str((build or {}).get("attributes", {}).get("version") or "")
    processing = (build or {}).get("attributes", {}).get("processingState")
    if build_number != EXPECTED_BUILD_NUMBER or processing != "VALID":
        raise RuntimeError(
            f"Selected build is {build_number or 'missing'} ({processing}); "
            f"expected VALID build {EXPECTED_BUILD_NUMBER}"
        )

    submission_id: str | None = None
    attached_version_ids: set[str] = set()
    unresolved = find_submission_item_for_version(app_id, "UNRESOLVED_ISSUES", version_id)
    if unresolved:
        submission, item, items = unresolved
        submission_id = submission["id"]
        attached_version_ids = {item_app_store_version_id(existing) for existing in items}
        state = item.get("attributes", {}).get("state")
        print(f"reusing unresolved submission: {submission_id}; item state={state}")
        if state == "REJECTED":
            mark_submission_item_resolved(item)

    if submission_id is None:
        status, body = api(
            "GET",
            f"/v1/apps/{app_id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&limit=20",
        )
        require("ready submission lookup", status, body, (200,))
        submissions = body.get("data", [])
        if submissions:
            submission = submissions[0]
            submission_id = submission["id"]
            print(f"reusing ready submission: {submission_id}")
        else:
            status, body = api(
                "POST",
                "/v1/reviewSubmissions",
                {
                    "data": {
                        "type": "reviewSubmissions",
                        "attributes": {"platform": "IOS"},
                        "relationships": {
                            "app": {"data": {"type": "apps", "id": app_id}}
                        },
                    }
                },
            )
            require("create review submission", status, body, (201,))
            submission_id = body["data"]["id"]

        items = review_submission_items(submission_id)
        attached_version_ids = {item_app_store_version_id(item) for item in items}

    if version_id not in attached_version_ids:
        status, body = api(
            "POST",
            "/v1/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {
                            "data": {"type": "reviewSubmissions", "id": submission_id}
                        },
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        },
                    },
                }
            },
        )
        require("add Tapt 1.0 to submission", status, body, (201,))

    status, body = api(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    require("submit Tapt 1.0", status, body, (200,))
    state = body.get("data", {}).get("attributes", {}).get("state")
    print(f"Tapt 1.0 submitted with build {EXPECTED_BUILD_NUMBER}; state={state}.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"FATAL: {error}")
        sys.exit(1)
