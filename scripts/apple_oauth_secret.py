#!/usr/bin/env python3
"""Generate the Apple OAuth client secret (a signed JWT) for Supabase.

ONLY needed for WEB Sign in with Apple (e.g. the landing page). The iOS app
uses the native flow, which needs no secret — just the bundle id in the
provider's Client IDs field.

Requires a "Sign in with Apple" key from developer.apple.com → Certificates,
Identifiers & Profiles → Keys (this is NOT the App Store Connect API key).
Apple caps validity at 6 months — re-run and re-paste twice a year.

Env:
  SIWA_KEY_PATH   path to the .p8 Sign in with Apple key (required)
  SIWA_KEY_ID     the key's ID (required)
  TEAM_ID         default J9DMDH4S58
  CLIENT_ID       the Services ID for web flow (e.g. app.tapt.web) (required)

Usage: python3 scripts/apple_oauth_secret.py --output /secure/path/apple-secret.txt
Copy the file directly to the password field, then securely delete it.
"""
import argparse
import os
import sys
import time
import jwt  # PyJWT + cryptography

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--output",
    required=True,
    help="Path for the generated JWT. The file is written with owner-only permissions.",
)
args = parser.parse_args()

KEY_PATH = os.environ.get("SIWA_KEY_PATH")
KEY_ID = os.environ.get("SIWA_KEY_ID")
TEAM_ID = os.environ.get("TEAM_ID", "J9DMDH4S58")
CLIENT_ID = os.environ.get("CLIENT_ID")

if not (KEY_PATH and KEY_ID and CLIENT_ID):
    print("Set SIWA_KEY_PATH, SIWA_KEY_ID, CLIENT_ID (and optionally TEAM_ID).")
    sys.exit(1)

with open(KEY_PATH) as f:
    key = f.read()

now = int(time.time())
secret = jwt.encode(
    {
        "iss": TEAM_ID,
        "iat": now,
        "exp": now + 86400 * 180,  # Apple max: 6 months
        "aud": "https://appleid.apple.com",
        "sub": CLIENT_ID,
    },
    key,
    algorithm="ES256",
    headers={"kid": KEY_ID},
)

output_path = os.path.abspath(os.path.expanduser(args.output))
fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w", encoding="utf-8") as output:
    output.write(secret)
    output.write("\n")
os.chmod(output_path, 0o600)
print(f"Apple client secret written to {output_path} with owner-only permissions.")
