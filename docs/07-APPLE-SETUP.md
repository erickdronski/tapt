# Tapt - Apple setup

## Done (via App Store Connect API -> `scripts/asc_setup.py`)
- **App ID `app.tapt.tapt`** registered (internal id `56UVQ6YQLQ`), Team `J9DMDH4S58`.
- Capabilities enabled: **Sign in with Apple, Maps (MapKit), Push Notifications, Associated Domains**.
- App Store Connect app `6788529176` and editable iOS version `1.0` exist under the Tapt account.
- ASC API creds: Key ID `9NVVWFXZGD`, Issuer `c798b8c2-6181-42a4-ae66-34e30d3c1c5e`, key at `~/.config/tapt/AuthKey_9NVVWFXZGD.p8` (App Manager role).
- Idempotent, re-run any time: `python3 scripts/asc_setup.py`.

## Remaining release gates
1. **Apple revocation key**: create a dedicated Sign in with Apple `.p8` key and configure the four Edge Function secrets documented in `docs/09-AUTH-SETUP.md`. App Store Connect API keys are not interchangeable with this key.
2. **Signed-device auth matrix**: verify email code, Google, and Apple on the exact TestFlight candidate. Dashboard/provider configuration is not physical proof.
3. **App Store Connect manual answers**: publish App Privacy, answer the current Social Media age-rating question Yes, and finish account/compliance agreements before dispatching the protected submission workflow.

## Signing
Xcode automatic signing (Team `J9DMDH4S58`) provisions the dev cert + profile on first build. A distribution cert + TestFlight upload come once there is a build (scriptable via the same ASC API later).
