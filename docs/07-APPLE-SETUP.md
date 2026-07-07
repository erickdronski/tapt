# Tapt - Apple setup

## Done (via App Store Connect API -> `scripts/asc_setup.py`)
- **App ID `app.tapt.tapt`** registered (internal id `56UVQ6YQLQ`), Team `J9DMDH4S58`.
- Capabilities enabled: **Sign in with Apple, Maps (MapKit), Push Notifications, Associated Domains**.
- ASC API creds: Key ID `9NVVWFXZGD`, Issuer `c798b8c2-6181-42a4-ae66-34e30d3c1c5e`, key at `~/.config/tapt/AuthKey_9NVVWFXZGD.p8` (App Manager role).
- Idempotent, re-run any time: `python3 scripts/asc_setup.py`.

## Remaining (quick dashboard steps, ~2 min total)
1. **App record** (App Store Connect UI): My Apps -> `+` -> New App -> iOS -> pick bundle `app.tapt.tapt` -> name **Tapt** -> primary language -> SKU `tapt` -> Create. Apple's API does not create app records, so this one is UI. Needed before TestFlight.
2. **Supabase Apple provider** (project `qfwiizvqxrhjlthbjosz`): Authentication -> Providers -> Apple -> enable -> add **`app.tapt.tapt`** to Authorized Client IDs. For native iOS Sign in with Apple that is all you need (no Services ID / secret; those are only for web / Android OAuth).
3. **Google Sign-In**: Google Cloud -> Credentials -> create OAuth clients (iOS + Web) -> Supabase -> Providers -> Google -> enable + paste the Web client id/secret. iOS also needs the reversed-client-id URL scheme in the app.

## Signing
Xcode automatic signing (Team `J9DMDH4S58`) provisions the dev cert + profile on first build. A distribution cert + TestFlight upload come once there is a build (scriptable via the same ASC API later).
