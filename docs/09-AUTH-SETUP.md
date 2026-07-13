# Tapt — Auth setup (owner runbook)

The app detects enabled providers at runtime (`/auth/v1/settings`) and only
shows working buttons. Current production state (checked 2026-07-13):

| Provider | Supabase | What's needed |
|---|---|---|
| Email magic link + 6-digit code | On, production-verified | See "email hardening" below |
| Google | On | Owner account linked; signed-device TestFlight callback proof remains |
| **Apple** | **Off** | Configure and enable before App Review while Google login is offered |
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

## 2. Enable Apple (native Sign in with Apple)
Dashboard → Authentication → Providers → Apple → Enable, then in
**Client IDs** add the app's bundle id:

```
app.tapt.tapt
```

**"Secret key should be a JWT" error:** do not paste a raw `.p8` key into the
Secret Key field. Web OAuth uses a signed JWT generated from the Apple key.
The native app uses `signInWithIdToken`; configure the native Client ID and
enable the provider only after a physical-device test succeeds. The capability
is already on the App ID and in `Tapt.entitlements`; the app's Apple button
appears automatically once the provider is enabled (runtime detection).

When the landing page later needs web Sign in with Apple: create a
"Sign in with Apple" key at developer.apple.com (NOT the ASC API key), then
generate the 6-month JWT with `scripts/apple_oauth_secret.py` and paste that.

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
