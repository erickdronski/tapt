#!/usr/bin/env python3
"""Tapt - TestFlight metadata admin via the ASC API.

Run from CI (asc-admin.yml) where the ASC key lives in secrets.
Idempotent. Does three things and prints a report:
  1. Beta app localization: description -> "THE Beer Superapp" copy,
     feedbackEmail -> support address (required for tester feedback).
  2. Beta groups: feedbackEnabled -> true (screenshot feedback on the phone
     only appears when the tester's group has feedback enabled).
  3. Latest build: whatsNew note.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, FEEDBACK_EMAIL (optional).
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
KEY_PATH = os.environ["ASC_KEY_PATH"]
FEEDBACK_EMAIL = os.environ.get("FEEDBACK_EMAIL", "esdronski@gmail.com")
BUNDLE_ID = "app.tapt.tapt"
BASE = "https://api.appstoreconnect.apple.com"

BETA_DESCRIPTION = (
    "Tapt - THE Beer Superapp. Free, global, scan-first: scan any label or "
    "barcode on Earth, log the pour to your Cellar, stamp your Passport "
    "(50 states + 47 countries), ride the live beer market, vote on Beer of "
    "the Week, climb leaderboards, play beer-night games, and find what's "
    "pouring at breweries, pubs, bars, taprooms, and beer gardens near you. "
    "Free to drinkers forever."
)

WHATS_NEW = (
    "The Superapp update: global brewery radar (8,700+ real venues, 25 "
    "countries), scan-to-catalog for any barcode on Earth, beer detail pages "
    "with style science and real label photos, Beer of the Week voting, "
    "leaderboards, friends, The Tapt Dispatch newsletter, and partner "
    "onboarding for breweries and bars."
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


def main():
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

    # 2. Beta groups: make sure screenshot feedback is enabled
    s, d = api("GET", f"/v1/apps/{app_id}/betaGroups?fields[betaGroups]=name,feedbackEnabled,isInternalGroup,publicLinkEnabled")
    for group in d.get("data", []):
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

    # 3. Latest build: whatsNew
    s, d = api("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=1")
    builds = d.get("data", [])
    if builds:
        build_id = builds[0]["id"]
        version = builds[0]["attributes"].get("version")
        s, d = api("GET", f"/v1/builds/{build_id}/betaBuildLocalizations")
        for bl in d.get("data", []):
            s2, d2 = api("PATCH", f"/v1/betaBuildLocalizations/{bl['id']}", {
                "data": {"type": "betaBuildLocalizations", "id": bl["id"],
                         "attributes": {"whatsNew": WHATS_NEW}}
            })
            print(f"build {version} whatsNew PATCH -> {s2}")
    print("done")


if __name__ == "__main__":
    main()
