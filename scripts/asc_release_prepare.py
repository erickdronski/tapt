#!/usr/bin/env python3
"""Prepare Tapt's public App Store record without submitting it for review.

The script is idempotent and deliberately stops short of creating a review
submission. It may reuse an existing TestFlight review contact, but never logs
contact values or demo credentials.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, TARGET_BUILD_NUMBER,
ASC_REVIEW_FIRST_NAME, ASC_REVIEW_LAST_NAME, ASC_REVIEW_EMAIL,
ASC_REVIEW_PHONE, ASC_DEMO_ACCOUNT_NAME, ASC_DEMO_ACCOUNT_PASSWORD.
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
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"
TARGET_BUILD_NUMBER = os.environ.get("TARGET_BUILD_NUMBER", "").strip()
EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
}

DESCRIPTION = """Meet Tapt, THE Beer Superapp.

SCAN AND LEARN
Scan a barcode, beer label, tap list, or venue QR. Explore style science, tasting notes, ingredients, history, awards, and brewery information from sourced catalog data.

BUILD YOUR CELLAR
Log pours, add private notes, track styles, and turn each new state or country into Passport progress.

FIND BEER NEAR YOU
Browse real breweries, pubs, bars, taprooms, and beer gardens on the global Beer Radar. Tapt's venue map uses real coordinates and source provenance.

RIDE THE BEER MARKET
Vote beers up or down and watch rankings move from real community activity. No invented scores: empty boards stay empty until people vote or log pours.

LEARN AND PLAY
Use guided flights, Beer School, trivia, skill games, and zero-proof-friendly table tools to bring people together. Tapt games never require alcohol and never score alcohol use.

FOLLOW YOUR BEER CIRCLE
Find friends, follow public Passport progress, and see eligible check-ins on Tonight. Report and block controls are built in.

FOR BREWERIES AND BARS
Claim a venue, publish a live tap list, share a QR menu, and view real venue activity through Tapt for Business.

Tapt is free for drinkers. It is for people of legal drinking age and does not sell alcohol. Please drink responsibly and never drink and drive."""

PROMOTIONAL_TEXT = (
    "Scan a label or barcode, log a pour, stamp your Passport, browse nearby "
    "beer spots, vote on the Beer Market, and play table games. Free for drinkers."
)

KEYWORDS = "beer,brewery,bar,pub,taproom,cellar,passport,scanner,pong,trivia,craft"

REVIEW_NOTES = """Tapt is an informational and social beer app for legal-drinking-age adults. It does not sell alcohol.

PUBLIC REVIEW PATH
- Tap "Explore without an account" to inspect catalog search, the local MapKit beer-place map, Beer School, points-only table games, Discover, and partner information without providing credentials.
- Account-only actions clearly return the reviewer to sign-in.

ACCOUNT REVIEW PATH
- Tap "Sign in with password" and use the dedicated demo account supplied in the App Review fields. The account opens the full signed-in experience, including Discover and account-only social surfaces.
- Email link/code, Sign in with Apple, and Google are also available. All complete inside the signed app and return to Tapt.
- Delete account: You tab > Delete account > confirm. This revokes stored Sign in with Apple authorization, deletes avatar objects, the auth identity, and all personal-plane rows.
- Privacy controls: You tab > Privacy Choices. Optional aggregate and partner-insight sharing default off.
- UGC safety: profile text is filtered before publication; avatar uploads wait for approval; report/block actions are available from social feed items and public profiles; reports enter an authenticated admin moderation queue.
- Age rating: Tapt includes social-media capability through profile search, follows, and the Tonight feed, and includes frequent contests through trivia/rankings. We do not claim the under-13 social-media mitigation because Tapt does not use Apple's Declared Age Range API.
- Responsible play: games are skill, trivia, and scorekeeping experiences. They never require alcohol, include zero-proof play, and contain no volume, speed-drinking, or alcohol-consumption prompts. The prior visible game labels have been revised for App Review: Beer Olympics is now Table Olympics, Beer Night is now Game Night, Beer Pong is now Cup Pong, and Flip Cup is now Cup Flip.
- Passport badges reward distinct beers, styles, and places rather than repeat consumption volume.

LOCATION AND CAMERA
- Both permissions are optional and requested in context. The public catalog, learning, and games remain usable without either permission.
- The camera supports beer barcodes, printed label/tap-list text, and partner QR scanning.

DATA INTEGRITY
- Beer, brewery, and venue records are source-attributed. Community boards remain empty until real eligible activity exists; the production app contains no fabricated votes or check-ins."""


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
        with urllib.request.urlopen(request) as response:
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


def review_attributes_from_environment() -> tuple[dict, list[str]]:
    secret_fields = {
        "ASC_REVIEW_FIRST_NAME": "contactFirstName",
        "ASC_REVIEW_LAST_NAME": "contactLastName",
        "ASC_REVIEW_EMAIL": "contactEmail",
        "ASC_REVIEW_PHONE": "contactPhone",
        "ASC_DEMO_ACCOUNT_NAME": "demoAccountName",
        "ASC_DEMO_ACCOUNT_PASSWORD": "demoAccountPassword",
    }
    attributes = {
        field: os.environ[name]
        for name, field in secret_fields.items()
        if os.environ.get(name)
    }
    missing = [
        field for name, field in secret_fields.items() if not os.environ.get(name)
    ]
    return attributes, missing


def fill_review_attributes_from_beta(
    app_id: str, attributes: dict, missing: list[str]
) -> list[str]:
    """Fill review fields missing from secrets with the values already stored in
    the app's TestFlight review detail. This is an in-account, API-to-API copy;
    values are never printed or logged."""
    if not missing:
        return []
    status, body = api("GET", f"/v1/apps/{app_id}/betaAppReviewDetail")
    if status != 200 or not body.get("data"):
        return missing
    beta = body["data"].get("attributes", {})
    still_missing: list[str] = []
    for field in missing:
        value = beta.get(field)
        if value is not None and str(value).strip():
            attributes[field] = value
            print(f"review field {field}: reused from the TestFlight review detail")
        else:
            still_missing.append(field)
    return still_missing


SUPABASE_AUTH_ADMIN = "https://qfwiizvqxrhjlthbjosz.supabase.co/auth/v1/admin"


def supabase_admin(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"].strip()
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(SUPABASE_AUTH_ADMIN + path, data=data, method=method)
    request.add_header("apikey", service_key)
    request.add_header("Authorization", "Bearer " + service_key)
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            return error.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return error.code, {"raw": raw[:300]}


def ensure_demo_password(attributes: dict, missing: list[str]) -> list[str]:
    """Last-resort source for the demo password: mint a fresh one in-process and
    set it on the Supabase demo account, so Apple's stored value and the live
    account always match. The value is never printed or logged. Creates the
    account (email confirmed) if it does not exist yet."""
    if "demoAccountPassword" not in missing:
        return missing
    demo_email = str(attributes.get("demoAccountName", "")).strip().lower()
    if not demo_email or not os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip():
        return missing

    import secrets as _secrets

    password = "TaptRev-" + _secrets.token_urlsafe(12)

    user_id = None
    for page in range(1, 6):
        status, body = supabase_admin("GET", f"/users?page={page}&per_page=200")
        if status != 200:
            print(f"demo account lookup failed ({status}); leaving password unresolved")
            return missing
        users = body.get("users", [])
        user_id = next(
            (u["id"] for u in users if str(u.get("email", "")).lower() == demo_email),
            None,
        )
        if user_id or len(users) < 200:
            break

    if user_id:
        status, body = supabase_admin("PUT", f"/users/{user_id}", {"password": password})
        action = "rotated"
    else:
        status, body = supabase_admin(
            "POST",
            "/users",
            {"email": demo_email, "password": password, "email_confirm": True},
        )
        action = "created"
    if status not in (200, 201):
        detail = body.get("msg") or body.get("message") or body.get("raw") or status
        print(f"demo account {action} failed: {detail}; leaving password unresolved")
        return missing

    attributes["demoAccountPassword"] = password
    print(f"review field demoAccountPassword: {action} on the Supabase demo account")
    return [field for field in missing if field != "demoAccountPassword"]


def validate_public_legal_pages() -> None:
    blockers = (
        "draft for counsel review",
        "[company_legal_name",
        "[address",
        "to be completed",
        "tapt.app",
    )
    for label, url in (
        ("privacy policy", "https://taptbeer.com/privacy"),
        ("terms", "https://taptbeer.com/terms"),
    ):
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "Tapt release readiness audit"},
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                page = response.read().decode("utf-8", errors="replace").lower()
        except urllib.error.URLError as error:
            raise RuntimeError(f"{label} could not be verified: {error.reason}") from error
        matched = next((marker for marker in blockers if marker in page), None)
        if matched:
            raise RuntimeError(
                f"{label} is not publication-ready ({matched}); "
                "refusing to prepare App Store metadata"
            )
        print(f"{label}: publication-ready")


def main() -> int:
    if not TARGET_BUILD_NUMBER:
        raise RuntimeError(
            "TARGET_BUILD_NUMBER is required; refusing to attach a build by recency"
        )
    review_attributes, review_missing = review_attributes_from_environment()

    validate_public_legal_pages()

    encoded_bundle = urllib.parse.quote(BUNDLE_ID, safe="")
    status, body = api("GET", f"/v1/apps?filter[bundleId]={encoded_bundle}&limit=1")
    require("app lookup", status, body, (200,))
    app = first(body.get("data", []), "Tapt app")
    app_id = app["id"]

    review_missing = fill_review_attributes_from_beta(
        app_id, review_attributes, review_missing
    )
    review_missing = ensure_demo_password(review_attributes, review_missing)
    if review_missing:
        raise RuntimeError(
            "App Review fields are missing from both secrets and the TestFlight "
            "review detail: " + ", ".join(review_missing)
        )
    review_attributes.update({"demoAccountRequired": True, "notes": REVIEW_NOTES})

    status, body = api(
        "PATCH",
        f"/v1/apps/{app_id}",
        {
            "data": {
                "type": "apps",
                "id": app_id,
                "attributes": {
                    "contentRightsDeclaration": "USES_THIRD_PARTY_CONTENT"
                },
            }
        },
    )
    require("content rights", status, body, (200,))

    status, body = api("GET", f"/v1/apps/{app_id}/appInfos?limit=20")
    require("app info lookup", status, body, (200,))
    app_info = first(body.get("data", []), "App Info")
    app_info_id = app_info["id"]

    status, body = api(
        "PATCH",
        f"/v1/appInfos/{app_info_id}",
        {
            "data": {
                "type": "appInfos",
                "id": app_info_id,
                "relationships": {
                    "primaryCategory": {
                        "data": {"type": "appCategories", "id": "FOOD_AND_DRINK"}
                    },
                    "secondaryCategory": {
                        "data": {"type": "appCategories", "id": "SOCIAL_NETWORKING"}
                    },
                },
            }
        },
    )
    require("Food & Drink category", status, body, (200,))

    status, body = api("GET", f"/v1/appInfos/{app_info_id}/ageRatingDeclaration")
    require("age declaration lookup", status, body, (200,))
    rating_id = first([body.get("data")] if body.get("data") else [], "age declaration")["id"]
    rating_attributes = {
        "advertising": True,
        "ageAssurance": True,
        "alcoholTobaccoOrDrugUseOrReferences": "FREQUENT",
        "contests": "FREQUENT",
        "gambling": False,
        "gamblingSimulated": "NONE",
        "gunsOrOtherWeapons": "NONE",
        "healthOrWellnessTopics": False,
        "horrorOrFearThemes": "NONE",
        "lootBox": False,
        "matureOrSuggestiveThemes": "NONE",
        "medicalOrTreatmentInformation": "NONE",
        "messagingAndChat": False,
        "parentalControls": False,
        "profanityOrCrudeHumor": "NONE",
        "sexualContentGraphicAndNudity": "NONE",
        "sexualContentOrNudity": "NONE",
        "unrestrictedWebAccess": False,
        "userGeneratedContent": True,
        "violenceCartoonOrFantasy": "NONE",
        "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    }
    status, body = api(
        "PATCH",
        f"/v1/ageRatingDeclarations/{rating_id}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": rating_id,
                "attributes": rating_attributes,
            }
        },
    )
    require("age declaration", status, body, (200,))

    status, body = api(
        "GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations?limit=50"
    )
    require("app localization lookup", status, body, (200,))
    localizations = body.get("data", [])
    if not localizations:
        raise RuntimeError("No App Info localization exists")
    for localization in localizations:
        locale = localization.get("attributes", {}).get("locale")
        loc_id = localization["id"]
        status, body = api(
            "PATCH",
            f"/v1/appInfoLocalizations/{loc_id}",
            {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": loc_id,
                    "attributes": {
                        "subtitle": "THE Beer Superapp",
                        "privacyPolicyUrl": "https://taptbeer.com/privacy",
                        "privacyChoicesUrl": "https://taptbeer.com/privacy#choices",
                    },
                }
            },
        )
        require(f"app localization {locale}", status, body, (200,))

    status, body = api(
        "GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20"
    )
    require("App Store version lookup", status, body, (200,))
    versions = body.get("data", [])
    version = next(
        (
            item
            for item in versions
            if item.get("attributes", {}).get("versionString") == "1.0"
            and item.get("attributes", {}).get("appStoreState")
            in EDITABLE_VERSION_STATES
        ),
        None,
    )
    if not version:
        states = sorted(
            str(item.get("attributes", {}).get("appStoreState"))
            for item in versions
            if item.get("attributes", {}).get("versionString") == "1.0"
        )
        raise RuntimeError(
            "Editable iOS version 1.0 not found; observed states: "
            + (", ".join(states) if states else "none")
        )
    version_id = version["id"]

    status, body = api(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": {
                    "copyright": "2026 Erick Dronski",
                    "releaseType": "AFTER_APPROVAL",
                    "usesIdfa": False,
                },
            }
        },
    )
    require("version attributes", status, body, (200,))

    status, body = api(
        "GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50"
    )
    require("version localization lookup", status, body, (200,))
    version_localizations = body.get("data", [])
    if not version_localizations:
        raise RuntimeError("No App Store version localization exists")
    for localization in version_localizations:
        locale = localization.get("attributes", {}).get("locale")
        loc_id = localization["id"]
        status, body = api(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{loc_id}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc_id,
                    "attributes": {
                        "description": DESCRIPTION,
                        "keywords": KEYWORDS,
                        "marketingUrl": "https://taptbeer.com",
                        "promotionalText": PROMOTIONAL_TEXT,
                        "supportUrl": "https://taptbeer.com/support",
                    },
                }
            },
        )
        require(f"version localization {locale}", status, body, (200,))

    status, body = api(
        "GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=20"
    )
    require("build lookup", status, body, (200,))
    builds = [
        item
        for item in body.get("data", [])
        if item.get("attributes", {}).get("processingState") == "VALID"
    ]
    build = next(
        (
            item
            for item in builds
            if str(item.get("attributes", {}).get("version"))
            == TARGET_BUILD_NUMBER
        ),
        None,
    )
    if not build:
        raise RuntimeError(
            f"VALID build {TARGET_BUILD_NUMBER} not found; refusing to attach a different build"
        )
    status, body = api(
        "PATCH",
        f"/v1/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    require(
        f"select build {build.get('attributes', {}).get('version')}",
        status,
        body,
        (200, 204),
    )

    status, body = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    if status == 404 or (status == 200 and not body.get("data")):
        status, body = api(
            "POST",
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": review_attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {
                                "type": "appStoreVersions",
                                "id": version_id,
                            }
                        }
                    },
                }
            },
        )
        require("create App Review detail", status, body, (201,))
    elif status == 200 and body.get("data"):
        review = body["data"]
        status, body = api(
            "PATCH",
            f"/v1/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": review_attributes,
                }
            },
        )
        require("update App Review detail", status, body, (200,))
    else:
        require("App Review detail lookup", status, body, (200, 404))

    print("Release metadata prepared. No review submission was created.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"FATAL: {error}")
        sys.exit(1)
