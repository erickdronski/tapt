#!/usr/bin/env python3
"""Tapt - TestFlight metadata admin via the ASC API.

Run from CI (asc-admin.yml) where the ASC key lives in secrets.
Idempotent. Does three things and prints a report:
  1. Beta app localization: description -> "THE Beer Superapp" copy,
     feedbackEmail -> support address (required for tester feedback).
  2. Beta groups: feedbackEnabled -> true (screenshot feedback on the phone
     only appears when the tester's group has feedback enabled).
  3. The exact requested build: compliance, tester groups, and whatsNew.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, TARGET_BUILD_NUMBER,
FEEDBACK_EMAIL (optional).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
FEEDBACK_EMAIL = os.environ.get("FEEDBACK_EMAIL", "esdronski@gmail.com")
TARGET_BUILD_NUMBER = os.environ.get("TARGET_BUILD_NUMBER", "").strip()
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"

BETA_DESCRIPTION = (
    "Tapt - THE Beer Superapp. Scan beer labels and barcodes, explore sourced "
    "product details, log distinct beers to your Cellar, build a state-and-world "
    "Passport, vote on real community rankings, learn beer styles, play skill "
    "and table games with zero-proof play built in, and find breweries, pubs, "
    "bars, taprooms, and beer gardens near you. Free for drinkers."
)

WHATS_NEW = (
    "A fuller Beer Superapp: mapped beer spots, label and barcode "
    "scanning, real product photos, sourced beer details, Cellar and Passport "
    "progress, Beer Market voting, Beer of the Week, learning, skill games, "
    "friends, and free partner menus and QR tools for breweries and bars."
)


def token():
    with open(KEY_PATH) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
    )


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def require(status, expected, label, body):
    if status not in expected:
        print(f"FATAL: {label} failed ({status}): {json.dumps(body)[:500]}")
        sys.exit(1)


def main():
    if not TARGET_BUILD_NUMBER:
        print("FATAL: TARGET_BUILD_NUMBER is required; refusing to select a build by recency.")
        sys.exit(1)

    s, d = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    apps = d.get("data", [])
    if s != 200 or not apps:
        print(f"FATAL: app lookup failed ({s}): {json.dumps(d)[:400]}")
        sys.exit(1)
    app_id = apps[0]["id"]
    print(f"app: {BUNDLE_ID} -> {app_id}")

    # 1. Beta app localization (description + feedback email)
    s, d = api("GET", f"/v1/apps/{app_id}/betaAppLocalizations")
    locs = d.get("data", [])
    if not locs:
        s, d = api("POST", "/v1/betaAppLocalizations", {
            "data": {
                "type": "betaAppLocalizations",
                "attributes": {
                    "locale": "en-US",
                    "description": BETA_DESCRIPTION,
                    "feedbackEmail": FEEDBACK_EMAIL,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        print(f"betaAppLocalization CREATE en-US -> {s}")
        require(s, {201}, "beta app localization create", d)
    else:
        for loc in locs:
            loc_id = loc["id"]
            locale = loc["attributes"].get("locale")
            s, d = api("PATCH", f"/v1/betaAppLocalizations/{loc_id}", {
                "data": {
                    "type": "betaAppLocalizations",
                    "id": loc_id,
                    "attributes": {
                        "description": BETA_DESCRIPTION,
                        "feedbackEmail": FEEDBACK_EMAIL,
                    },
                }
            })
            print(f"betaAppLocalization PATCH {locale} -> {s}"
                  + ("" if s == 200 else f" {json.dumps(d)[:300]}"))
            require(s, {200}, f"beta app localization patch {locale}", d)

    # 2. Beta groups: make sure screenshot feedback is enabled
    s, d = api("GET", f"/v1/apps/{app_id}/betaGroups?fields[betaGroups]=name,feedbackEnabled,isInternalGroup,publicLinkEnabled")
    require(s, {200}, "beta group list", d)
    beta_groups = d.get("data", [])
    if not beta_groups:
        print("FATAL: no TestFlight beta groups exist; create a tester group before release.")
        sys.exit(1)
    for group in beta_groups:
        gid = group["id"]
        attrs = group["attributes"]
        print(f"betaGroup '{attrs.get('name')}' internal={attrs.get('isInternalGroup')} feedbackEnabled={attrs.get('feedbackEnabled')}")
        if attrs.get("feedbackEnabled") is not True:
            s2, d2 = api("PATCH", f"/v1/betaGroups/{gid}", {
                "data": {"type": "betaGroups", "id": gid,
                         "attributes": {"feedbackEnabled": True}}
            })
            print(f"  -> feedbackEnabled=true PATCH {s2}"
                  + ("" if s2 == 200 else f" {json.dumps(d2)[:300]}"))
            require(s2, {200}, f"enable feedback for group {gid}", d2)

    # 3. Exact build: distribution state, export compliance, group assignment
    s, d = api("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=50&include=buildBetaDetail&fields[buildBetaDetails]=internalBuildState,externalBuildState")
    require(s, {200}, "build list", d)
    builds = d.get("data", [])
    detail_states = {i["id"]: i["attributes"] for i in d.get("included", []) if i["type"] == "buildBetaDetails"}
    s2, groups = api("GET", f"/v1/apps/{app_id}/betaGroups?fields[betaGroups]=name,isInternalGroup")
    require(s2, {200}, "beta group assignment list", groups)
    group_ids = [g["id"] for g in groups.get("data", [])]
    matches = [b for b in builds if str(b["attributes"].get("version")) == TARGET_BUILD_NUMBER]
    if not matches:
        print(f"FATAL: requested build {TARGET_BUILD_NUMBER} was not found; refusing to administer an older build.")
        sys.exit(1)
    build = matches[0]
    attrs = build["attributes"]
    det_id = ((build.get("relationships", {}).get("buildBetaDetail", {}).get("data") or {}).get("id"))
    det = detail_states.get(det_id, {})
    print(f"BUILD {attrs.get('version')} state={attrs.get('processingState')} nonExemptEnc={attrs.get('usesNonExemptEncryption')} internal={det.get('internalBuildState')} external={det.get('externalBuildState')}")
    if attrs.get("processingState") != "VALID":
        print(f"FATAL: requested build {TARGET_BUILD_NUMBER} is not VALID yet.")
        sys.exit(1)
    build_id = build["id"]
    version = attrs.get("version")
    if attrs.get("usesNonExemptEncryption") is None:
        s3, d3 = api("PATCH", f"/v1/builds/{build_id}", {"data": {"type": "builds", "id": build_id,
            "attributes": {"usesNonExemptEncryption": False}}})
        print(f"  -> compliance PATCH {s3}")
        require(s3, {200}, f"export compliance for build {build_id}", d3)
    for gid in group_ids:
        s4, d4 = api("POST", f"/v1/betaGroups/{gid}/relationships/builds",
                     {"data": [{"type": "builds", "id": build_id}]})
        print(f"  -> group {gid[:8]} assign {s4}")
        require(s4, {204}, f"assign build {build_id} to group {gid}", d4)
    s, d = api("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")
    require(s, {200}, f"build localization list for {build_id}", d)
    localizations = d.get("data", [])
    if not localizations:
        s2, d2 = api("POST", "/v1/betaBuildLocalizations", {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"locale": "en-US", "whatsNew": WHATS_NEW},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }
        })
        print(f"build {version} whatsNew CREATE -> {s2}")
        require(s2, {201}, f"build localization create for {build_id}", d2)
    for bl in localizations:
        s2, d2 = api("PATCH", f"/v1/betaBuildLocalizations/{bl['id']}", {
            "data": {"type": "betaBuildLocalizations", "id": bl["id"],
                     "attributes": {"whatsNew": WHATS_NEW}}
        })
        print(f"build {version} whatsNew PATCH -> {s2}")
        require(s2, {200}, f"build localization patch {bl['id']}", d2)
    print("done")


if __name__ == "__main__":
    main()
