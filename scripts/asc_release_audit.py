#!/usr/bin/env python3
"""Read-only App Store release audit for Tapt.

This runs in GitHub Actions, where the App Store Connect API key is available.
It never mutates App Store Connect and never prints review credentials or
contact values. The report is intentionally safe to keep in workflow logs.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
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


def api(path: str) -> tuple[int, dict]:
    url = path if path.startswith("https://") else BASE + path
    request = urllib.request.Request(url, method="GET")
    request.add_header("Authorization", "Bearer " + token())
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            body = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            body = {"raw": raw[:500]}
        return error.code, body


def relation_id(resource: dict, name: str) -> str | None:
    data = resource.get("relationships", {}).get(name, {}).get("data")
    return data.get("id") if isinstance(data, dict) else None


def is_present(value: object) -> bool:
    return value is not None and (not isinstance(value, str) or bool(value.strip()))


def api_error(label: str, status: int, body: dict) -> None:
    errors = body.get("errors", [])
    detail = errors[0].get("detail") if errors else body.get("raw")
    suffix = f": {detail}" if detail else ""
    print(f"  {label}: HTTP {status}{suffix}")


def main() -> int:
    blockers: list[str] = []
    manual: list[str] = []

    encoded_bundle = urllib.parse.quote(BUNDLE_ID, safe="")
    status, body = api(f"/v1/apps?filter[bundleId]={encoded_bundle}&limit=1")
    apps = body.get("data", [])
    if status != 200 or not apps:
        api_error("app lookup", status, body)
        return 1

    app = apps[0]
    app_id = app["id"]
    app_attrs = app.get("attributes", {})
    print("TAPT APP STORE RELEASE AUDIT")
    print(f"app: {app_attrs.get('name')} ({BUNDLE_ID}) id={app_id}")
    print(
        "record: "
        f"sku_present={is_present(app_attrs.get('sku'))} "
        f"primary_locale={app_attrs.get('primaryLocale')} "
        f"made_for_kids={app_attrs.get('isOrEverWasMadeForKids')} "
        f"content_rights={app_attrs.get('contentRightsDeclaration')}"
    )

    print("\nAPP INFORMATION")
    status, body = api(f"/v1/apps/{app_id}/appInfos?limit=20")
    app_infos = body.get("data", [])
    if status != 200:
        api_error("app infos", status, body)
    if not app_infos:
        blockers.append("No App Info record exists.")

    for info in app_infos:
        info_id = info["id"]
        attrs = info.get("attributes", {})
        print(
            f"appInfo {info_id}: state={attrs.get('appStoreState')} "
            f"kids={attrs.get('isOrEverWasMadeForKids')}"
        )

        for relationship, label in (
            ("primaryCategory", "primary category"),
            ("secondaryCategory", "secondary category"),
        ):
            rel_status, rel_body = api(
                f"/v1/appInfos/{info_id}/relationships/{relationship}"
            )
            rel_data = rel_body.get("data") if rel_status == 200 else None
            rel_value = rel_data.get("id") if isinstance(rel_data, dict) else None
            print(f"  {label}: {rel_value or 'MISSING'}")
            if relationship == "primaryCategory" and not rel_value:
                blockers.append("Primary App Store category is missing.")

        loc_status, loc_body = api(
            f"/v1/appInfos/{info_id}/appInfoLocalizations?limit=50"
        )
        localizations = loc_body.get("data", [])
        if loc_status != 200:
            api_error("app info localizations", loc_status, loc_body)
        if not localizations:
            blockers.append("No App Info localization exists.")
        for localization in localizations:
            loc = localization.get("attributes", {})
            privacy_url = loc.get("privacyPolicyUrl")
            print(
                f"  locale {loc.get('locale')}: "
                f"name={loc.get('name')!r} subtitle={loc.get('subtitle')!r} "
                f"privacy_url={privacy_url or 'MISSING'} "
                f"privacy_choices_url={loc.get('privacyChoicesUrl') or 'not set'}"
            )
            if not is_present(loc.get("name")):
                blockers.append(f"App name is missing for {loc.get('locale')}.")
            if not is_present(privacy_url):
                blockers.append(
                    f"Privacy policy URL is missing for {loc.get('locale')}."
                )

        rating_status, rating_body = api(
            f"/v1/appInfos/{info_id}/ageRatingDeclaration"
        )
        if rating_status == 200 and rating_body.get("data"):
            rating = rating_body["data"].get("attributes", {})
            print(
                "  age declaration: "
                f"alcohol={rating.get('alcoholTobaccoOrDrugUseOrReferences')} "
                f"UGC={rating.get('userGeneratedContent')} "
                f"messaging={rating.get('messagingAndChat')} "
                f"advertising={rating.get('advertising')} "
                f"contests={rating.get('contests')} "
                f"simulated_gambling={rating.get('gamblingSimulated')} "
                f"gambling={rating.get('gambling')}"
            )
        else:
            api_error("age declaration", rating_status, rating_body)
            blockers.append("Age-rating declaration could not be read.")

    print("\nAPP STORE VERSIONS")
    status, body = api(
        f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS"
        "&limit=10"
    )
    versions = body.get("data", [])
    versions.sort(
        key=lambda item: item.get("attributes", {}).get("createdDate") or "",
        reverse=True,
    )
    if status != 200:
        api_error("App Store versions", status, body)
    if not versions:
        blockers.append("No iOS App Store version exists.")

    editable_states = {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
    }
    candidate = next(
        (
            version
            for version in versions
            if version.get("attributes", {}).get("appStoreState") in editable_states
        ),
        versions[0] if versions else None,
    )

    for version in versions:
        attrs = version.get("attributes", {})
        print(
            f"version {attrs.get('versionString')} id={version['id']} "
            f"state={attrs.get('appStoreState')} "
            f"release={attrs.get('releaseType')} "
            f"copyright_present={is_present(attrs.get('copyright'))}"
        )

    if candidate:
        version_id = candidate["id"]
        version_attrs = candidate.get("attributes", {})
        version_label = version_attrs.get("versionString")
        print(f"\nRELEASE CANDIDATE {version_label} ({version_id})")

        build_status, build_body = api(f"/v1/appStoreVersions/{version_id}/build")
        build = build_body.get("data") if build_status == 200 else None
        if build:
            build_attrs = build.get("attributes", {})
            print(
                f"  selected build: {build_attrs.get('version')} "
                f"uploaded={build_attrs.get('uploadedDate')} "
                f"processing={build_attrs.get('processingState')}"
            )
        else:
            if build_status not in (200, 404):
                api_error("selected build", build_status, build_body)
            print("  selected build: MISSING")
            blockers.append(f"Version {version_label} has no selected build.")

        loc_status, loc_body = api(
            f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50"
        )
        version_localizations = loc_body.get("data", [])
        if loc_status != 200:
            api_error("version localizations", loc_status, loc_body)
        if not version_localizations:
            blockers.append(f"Version {version_label} has no localized metadata.")

        for localization in version_localizations:
            loc_id = localization["id"]
            loc = localization.get("attributes", {})
            missing = [
                field
                for field in ("description", "keywords", "supportUrl")
                if not is_present(loc.get(field))
            ]
            print(
                f"  locale {loc.get('locale')}: "
                f"description={len(loc.get('description') or '')} chars "
                f"keywords={len(loc.get('keywords') or '')} chars "
                f"support={loc.get('supportUrl') or 'MISSING'} "
                f"marketing={loc.get('marketingUrl') or 'not set'} "
                f"missing={','.join(missing) or 'none'}"
            )
            if os.environ.get("ASC_AUDIT_VERBOSE") == "1":
                print(f"    description: {loc.get('description') or ''}")
                print(f"    keywords: {loc.get('keywords') or ''}")
                print(f"    promotional text: {loc.get('promotionalText') or ''}")
            for field in missing:
                blockers.append(
                    f"Version {version_label} {loc.get('locale')} is missing {field}."
                )

            set_status, set_body = api(
                f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=50"
            )
            screenshot_sets = set_body.get("data", [])
            if set_status != 200:
                api_error("screenshot sets", set_status, set_body)
            if not screenshot_sets:
                blockers.append(
                    f"Version {version_label} {loc.get('locale')} has no screenshots."
                )
            for screenshot_set in screenshot_sets:
                set_attrs = screenshot_set.get("attributes", {})
                shots_status, shots_body = api(
                    f"/v1/appScreenshotSets/{screenshot_set['id']}/appScreenshots?limit=50"
                )
                shots = shots_body.get("data", [])
                ready = sum(
                    1
                    for shot in shots
                    if shot.get("attributes", {})
                    .get("assetDeliveryState", {})
                    .get("state")
                    == "COMPLETE"
                )
                print(
                    f"    screenshots {set_attrs.get('screenshotDisplayType')}: "
                    f"count={len(shots)} complete={ready}"
                )
                if shots_status != 200:
                    api_error("screenshots", shots_status, shots_body)
                if not shots:
                    blockers.append(
                        f"Screenshot set {set_attrs.get('screenshotDisplayType')} is empty."
                    )

        review_status, review_body = api(
            f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail"
        )
        review = review_body.get("data") if review_status == 200 else None
        if review:
            attrs = review.get("attributes", {})
            required = (
                "contactFirstName",
                "contactLastName",
                "contactPhone",
                "contactEmail",
            )
            missing = [field for field in required if not is_present(attrs.get(field))]
            demo_required = attrs.get("demoAccountRequired") is True
            demo_complete = (
                is_present(attrs.get("demoAccountName"))
                and is_present(attrs.get("demoAccountPassword"))
            )
            print(
                "  review detail: "
                f"contact_complete={not missing} "
                f"demo_required={demo_required} "
                f"demo_credentials_present={demo_complete} "
                f"notes_present={is_present(attrs.get('notes'))}"
            )
            if missing:
                blockers.append(
                    "App Review contact is incomplete: " + ", ".join(missing) + "."
                )
            if demo_required and not demo_complete:
                blockers.append("App Review demo credentials are incomplete.")
        else:
            if review_status not in (200, 404):
                api_error("review detail", review_status, review_body)
            print("  review detail: MISSING")
            blockers.append(f"Version {version_label} has no App Review detail.")

        if not is_present(version_attrs.get("copyright")):
            blockers.append(f"Version {version_label} is missing copyright.")

    print("\nREVIEW SUBMISSIONS")
    status, body = api(f"/v1/apps/{app_id}/reviewSubmissions?limit=10")
    if status == 200:
        submissions = body.get("data", [])
        submissions.sort(
            key=lambda item: item.get("attributes", {}).get("submittedDate") or "",
            reverse=True,
        )
        if not submissions:
            print("  none")
        for submission in submissions:
            attrs = submission.get("attributes", {})
            print(
                f"  id={submission['id']} state={attrs.get('state')} "
                f"submitted={attrs.get('submittedDate')}"
            )
    else:
        api_error("review submissions", status, body)

    print("\nRECENT BUILDS")
    status, body = api(
        f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5"
    )
    if status == 200:
        for build in body.get("data", []):
            attrs = build.get("attributes", {})
            print(
                f"  build={attrs.get('version')} uploaded={attrs.get('uploadedDate')} "
                f"processing={attrs.get('processingState')} "
                f"encryption={attrs.get('usesNonExemptEncryption')}"
            )
    else:
        api_error("builds", status, body)

    manual.extend(
        [
            "App Privacy data-use answers and their published state (not exposed by the public API).",
            "Agreements, tax, banking, DSA trader status, and territory availability.",
            "The public legal pages contain no draft text or unresolved placeholders.",
            "Sign in with Apple and each advertised third-party login work on a signed device.",
        ]
    )

    print("\nAUTOMATED BLOCKERS")
    if blockers:
        for blocker in dict.fromkeys(blockers):
            print(f"  BLOCKER: {blocker}")
    else:
        print("  none found by the API audit")

    print("\nMANUAL GATES")
    for item in manual:
        print(f"  CHECK: {item}")

    print(
        "\nRESULT: "
        + (
            f"NOT READY ({len(dict.fromkeys(blockers))} automated blockers)"
            if blockers
            else "API METADATA READY; manual gates remain"
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
