# Tapt — Auth setup (owner runbook)

The app detects enabled providers at runtime (`/auth/v1/settings`) and only
shows release-approved buttons. Current production state (checked 2026-07-14):

| Provider | Supabase | What's needed |
|---|---|---|
| Email magic link + 6-digit code | On, production-verified | See "email hardening" below |
| Google | On | Hosted callback succeeded; repeat on the exact release-candidate TestFlight build |
| **Apple** | **On** | Configure the account-deletion token-exchange secrets below, then verify the exact TestFlight build |
| Facebook | Off | Leave hidden until Meta credentials and callback are tested |
| X / Twitter | Off | Leave hidden until X credentials and callback are tested |
| Phone | Off | Leave hidden until SMS delivery, abuse controls, and cost are approved |

## 1. Redirect allowlist
Supabase only redirects to allowlisted URLs. The production allowlist currently
contains both supported callback destinations:

```
tapt://auth-callback
https://taptbeer.com/portal.html
https://taptbeer.com/admin.html
```

The custom scheme returns Google OAuth to the iOS app. The HTTPS callbacks
return email links to the production partner and admin surfaces. Keep all exact values in
**Dashboard → Authentication → URL Configuration → Additional Redirect URLs**.
Do not add wildcard production callbacks.

## 2. Apple (native Sign in with Apple)
The Supabase Apple provider is enabled and **Client IDs** contains the app's
bundle id:

```
app.tapt.tapt
```

The native app uses `signInWithIdToken`; the capability is on the App ID and in
`Tapt.entitlements`. For App Store account-deletion compliance, the app also
sends Apple's one-time authorization code to the authenticated `apple-token`
Edge Function. That function exchanges the code and stores the refresh token in
Supabase Vault. `delete-account` revokes that token before deleting the account.

Create a dedicated **Sign in with Apple** key at developer.apple.com (not an App
Store Connect API key) and set these production Edge Function secrets:

```
APPLE_TEAM_ID=J9DMDH4S58
APPLE_CLIENT_ID=app.tapt.tapt
APPLE_SIGN_IN_KEY_ID=<the Sign in with Apple key id>
APPLE_SIGN_IN_KEY=<the complete .p8 private key>
```

This key remains a release blocker until all four values are configured. Tapt
fails Apple sign-in closed when the authorization code cannot be exchanged and
stored, because shipping an account that cannot later revoke Apple authorization
would make in-app deletion incomplete.

Do not paste the raw `.p8` key into Supabase Auth's web OAuth Secret Key field;
that field expects a signed client-secret JWT. The native provider does not need
that web client secret.

When the landing page later needs web Sign in with Apple, generate the 6-month
JWT with `scripts/apple_oauth_secret.py` from the dedicated key and configure the
web Services ID separately.

## 3. Enable Facebook or X (optional)
Facebook needs a Meta app with the Supabase callback in **Facebook Login →
Valid OAuth Redirect URIs**. X needs a developer app with OAuth credentials.
Both use this provider callback:

```
https://qfwiizvqxrhjlthbjosz.supabase.co/auth/v1/callback
```

Do not enable either provider until its complete TestFlight return path has
been exercised. Runtime provider detection keeps unfinished buttons hidden.

### X details
Needs an X developer app (developer.x.com) with OAuth 1.0a/2.0 credentials →
paste API key + secret into Dashboard → Providers → Twitter. Callback URL on
the X side: `https://qfwiizvqxrhjlthbjosz.supabase.co/auth/v1/callback`.
Until then the app simply hides the X button.

## 4. Email hardening
- **Add the code to the template** so the in-app 6-digit entry works:
  Dashboard → Authentication → Email Templates → Magic Link — include
  `{{ .Token }}` in the body, e.g.
  `<p>Or enter this code in the app: <strong>{{ .Token }}</strong></p>`
- **Default SMTP is rate-limited (~2 emails/hour) and often lands in spam.**
  That is very likely the other half of the "hard time." For real launch,
  configure custom SMTP (Resend free tier: 3k emails/month, $0) under
  Dashboard → Project Settings → Auth → SMTP. Cost-gated: your call.

## 5. Google credential sanity
Google is enabled and the owner account is linked. Google Cloud Console → OAuth
client → Authorized redirect URIs must contain:

```
https://qfwiizvqxrhjlthbjosz.supabase.co/auth/v1/callback
```

The remaining release proof is a successful Google login and return to a
signed TestFlight build on a physical device. Dashboard configuration alone is
not sufficient evidence that the custom-scheme return path works.
