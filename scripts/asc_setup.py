#!/usr/bin/env python3
"""Tapt - App Store Connect foundation via the ASC API.
Creates the App ID `app.tapt.tapt` and enables its capabilities.
Reads the private key from ~/.config/tapt (never committed). Idempotent.

Env (with sensible defaults):
  ASC_KEY_ID     default 9NVVWFXZGD
  ASC_ISSUER_ID  default c798b8c2-6181-42a4-ae66-34e30d3c1c5e
  ASC_KEY_PATH   default ~/.config/tapt/AuthKey_9NVVWFXZGD.p8
"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

KEY_ID   = os.environ.get("ASC_KEY_ID", "9NVVWFXZGD")
ISSUER   = os.environ.get("ASC_ISSUER_ID", "c798b8c2-6181-42a4-ae66-34e30d3c1c5e")
KEY_PATH = os.environ.get("ASC_KEY_PATH", os.path.expanduser("~/.config/tapt/AuthKey_9NVVWFXZGD.p8"))
BUNDLE_ID = "app.tapt.tapt"
APP_NAME  = "Tapt"
BASE = "https://api.appstoreconnect.apple.com"
# Sign in with Apple, MapKit, Push, Associated Domains (universal links)
CAPS = ["APPLE_ID_AUTH", "MAPS", "PUSH_NOTIFICATIONS", "ASSOCIATED_DOMAINS"]

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

def find_bundle():
    s, d = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=200")
    if s == 200:
        for b in d.get("data", []):
            if b["attributes"]["identifier"] == BUNDLE_ID:
                return b["id"]
    return None

def main():
    s, d = api("GET", "/v1/apps?limit=1")
    print("auth test:", s)
    if s != 200:
        print(json.dumps(d, indent=2)); sys.exit(1)

    bid = find_bundle()
    if bid:
        print("bundle exists:", BUNDLE_ID, bid)
    else:
        s, d = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds",
            "attributes": {"identifier": BUNDLE_ID, "name": APP_NAME, "platform": "IOS"}}})
        print("create bundle:", s)
        if s not in (200, 201):
            print(json.dumps(d, indent=2)); sys.exit(1)
        bid = d["data"]["id"]
        print("bundle id:", bid)

    for cap in CAPS:
        s, d = api("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities",
            "attributes": {"capabilityType": cap},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
        note = "(ok)" if s in (200, 201) else ("(already enabled)" if s == 409 else "(FAILED)")
        print(f"cap {cap}: {s} {note}")

    print(f"\nDONE. App ID {BUNDLE_ID} ({bid}) is ready.")

if __name__ == "__main__":
    main()
