#!/usr/bin/env python3
"""Replace Tapt's iPhone 6.9-inch App Store screenshots.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
Optional: SCREENSHOT_DIR (defaults to social-assets/appstore).
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt


KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"
DISPLAY_TYPE = "APP_IPHONE_67"
MAX_SCREENSHOTS = 10
SCREENSHOT_DIR = Path(os.environ.get("SCREENSHOT_DIR", "social-assets/appstore"))


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


def first(items: list[dict], label: str) -> dict:
    if not items:
        raise RuntimeError(f"{label} not found")
    return items[0]


def validate_png(path: Path) -> None:
    raw = path.read_bytes()[:26]
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise RuntimeError(f"{path.name} is not a PNG")
    width, height = struct.unpack(">II", raw[16:24])
    color_type = raw[25]
    if (width, height) != (1290, 2796):
        raise RuntimeError(f"{path.name} is {width}x{height}; expected 1290x2796")
    if color_type in (4, 6):
        raise RuntimeError(f"{path.name} contains an alpha channel")


def upload_operations(path: Path, operations: list[dict]) -> None:
    contents = path.read_bytes()
    for operation in operations:
        offset = int(operation.get("offset", 0))
        length = int(operation.get("length", len(contents)))
        chunk = contents[offset : offset + length]
        if len(chunk) != length:
            raise RuntimeError(f"{path.name} upload operation exceeds the file size")
        request = urllib.request.Request(
            operation["url"],
            data=chunk,
            method=operation.get("method", "PUT"),
        )
        for header in operation.get("requestHeaders", []):
            request.add_header(header["name"], header["value"])
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                if response.status not in (200, 201, 204):
                    raise RuntimeError(f"asset upload returned {response.status}")
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"{path.name} asset upload failed ({error.code})") from error


def wait_until_complete(screenshot_id: str, filename: str) -> None:
    for _ in range(60):
        status, body = api("GET", f"/v1/appScreenshots/{screenshot_id}")
        require(f"poll {filename}", status, body, (200,))
        delivery = body["data"].get("attributes", {}).get("assetDeliveryState", {})
        state = delivery.get("state")
        if state == "COMPLETE":
            return
        if state in ("FAILED", "REJECTED"):
            errors = delivery.get("errors") or []
            raise RuntimeError(f"{filename} processing failed: {errors}")
        time.sleep(5)
    raise RuntimeError(f"{filename} did not finish processing in time")


def main() -> int:
    screenshots = sorted(SCREENSHOT_DIR.glob("[0-9][0-9]_*.png"))
    if not 1 <= len(screenshots) <= 10:
        raise RuntimeError(f"Expected 1-10 screenshots, found {len(screenshots)}")
    for screenshot in screenshots:
        validate_png(screenshot)

    encoded_bundle = urllib.parse.quote(BUNDLE_ID, safe="")
    status, body = api("GET", f"/v1/apps?filter[bundleId]={encoded_bundle}&limit=1")
    require("app lookup", status, body, (200,))
    app_id = first(body.get("data", []), "Tapt app")["id"]

    status, body = api("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")
    require("version lookup", status, body, (200,))
    version = next(
        (
            item
            for item in body.get("data", [])
            if item.get("attributes", {}).get("versionString") == "1.0"
            and item.get("attributes", {}).get("appStoreState") == "PREPARE_FOR_SUBMISSION"
        ),
        None,
    )
    if not version:
        raise RuntimeError("Editable iOS version 1.0 not found")

    status, body = api(
        "GET",
        f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50",
    )
    require("localization lookup", status, body, (200,))
    localizations = body.get("data", [])
    if len(localizations) != 1:
        raise RuntimeError(f"Expected one release localization, found {len(localizations)}")
    localization_id = localizations[0]["id"]

    status, body = api("GET", f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets?limit=50")
    require("screenshot set lookup", status, body, (200,))
    screenshot_set = next(
        (
            item
            for item in body.get("data", [])
            if item.get("attributes", {}).get("screenshotDisplayType") == DISPLAY_TYPE
        ),
        None,
    )
    if not screenshot_set:
        status, body = api(
            "POST",
            "/v1/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": localization_id,
                            }
                        }
                    },
                }
            },
        )
        require("create screenshot set", status, body, (201,))
        screenshot_set = body["data"]
    set_id = screenshot_set["id"]

    status, body = api("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    require("existing screenshot lookup", status, body, (200,))
    existing = body.get("data", [])
    # Preserve as much of the known-good set as App Store Connect's ten-asset
    # limit allows until every replacement has finished processing.
    predelete_count = max(0, len(existing) + len(screenshots) - MAX_SCREENSHOTS)
    predelete = existing[-predelete_count:] if predelete_count else []
    preserved = existing[:-predelete_count] if predelete_count else existing
    for item in predelete:
        status, delete_body = api("DELETE", f"/v1/appScreenshots/{item['id']}")
        require("make screenshot capacity", status, delete_body, (204,))

    uploaded: list[str] = []
    for path in screenshots:
        status, body = api(
            "POST",
            "/v1/appScreenshots",
            {
                "data": {
                    "type": "appScreenshots",
                    "attributes": {"fileName": path.name, "fileSize": path.stat().st_size},
                    "relationships": {
                        "appScreenshotSet": {
                            "data": {"type": "appScreenshotSets", "id": set_id}
                        }
                    },
                }
            },
        )
        require(f"reserve {path.name}", status, body, (201,))
        screenshot = body["data"]
        operations = screenshot.get("attributes", {}).get("uploadOperations") or []
        if not operations:
            raise RuntimeError(f"No upload operations returned for {path.name}")
        upload_operations(path, operations)
        status, update_body = api(
            "PATCH",
            f"/v1/appScreenshots/{screenshot['id']}",
            {
                "data": {
                    "type": "appScreenshots",
                    "id": screenshot["id"],
                    "attributes": {"uploaded": True},
                }
            },
        )
        require(f"commit {path.name}", status, update_body, (200,))
        wait_until_complete(screenshot["id"], path.name)
        uploaded.append(screenshot["id"])

    for item in preserved:
        status, delete_body = api("DELETE", f"/v1/appScreenshots/{item['id']}")
        require("delete replaced screenshot", status, delete_body, (204,))

    status, body = api(
        "PATCH",
        f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
        {"data": [{"type": "appScreenshots", "id": value} for value in uploaded]},
    )
    require("order screenshots", status, body, (200, 204))
    print(f"Uploaded {len(uploaded)} {DISPLAY_TYPE} screenshots.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"FATAL: {error}")
        sys.exit(1)
