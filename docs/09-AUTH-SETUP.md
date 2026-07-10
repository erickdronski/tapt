# Tapt — Auth setup (owner runbook)

The app now detects enabled providers at runtime (`/auth/v1/settings`) and only
shows working buttons. Current live state (checked 2026-07-09):

| Provider | Supabase | What's needed |
|---|---|---|
| Email magic link + 6-digit code | ✅ on | See "email hardening" below |
| Google | ✅ on | Verify redirect allowlist (below) |
| Facebook | ✅ on | Verify redirect allowlist (below) |
| **Apple** | ❌ **off** | Enable it (below) — App Store REQUIRES it (Guideline 4.8) when other social logins are offered |
| **X / Twitter** | ❌ **off** | Enable it or leave hidden (app auto-hides it) |

## 1. The redirect allowlist (why Google/Facebook "didn't work")
The app finishes OAuth at `tapt://auth-callback`. Supabase only redirects to
allowlisted URLs. In **Dashboard → Authentication → URL Configuration →
Additional Redirect URLs** add exactly:

```
tapt://auth-callback
```

Without this, Google/Facebook complete on supabase.co and never return to the
app — which matches the "hard time" symptom exactly.

## 2. Enable Apple (native Sign in with Apple)
Dashboard → Authentication → Providers → Apple → Enable, then in
**Client IDs** add the app's bundle id:

```
app.tapt.tapt
```

**"Secret key should be a JWT" error:** leave the Secret Key field EMPTY.
It's only for the WEB OAuth flow and must be a signed JWT, not a raw .p8 —
pasting anything else blocks Save. Native `signInWithIdToken` needs no secret
at all: Client IDs + toggle on is the whole setup. The capability is already
on the App ID and in `Tapt.entitlements`; the app's Apple button appears
automatically once the provider is on (runtime detection).

When the landing page later needs web Sign in with Apple: create a
"Sign in with Apple" key at developer.apple.com (NOT the ASC API key), then
generate the 6-month JWT with `scripts/apple_oauth_secret.py` and paste that.

## 3. Enable X (optional)
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

## 5. Google/Facebook credential sanity
Both show enabled, meaning credentials exist. If either still fails after the
redirect fix: Google Cloud Console → OAuth client → Authorized redirect URIs
must contain `https://qfwiizvqxrhjlthbjosz.supabase.co/auth/v1/callback`;
same URL in Meta app → Facebook Login → Valid OAuth Redirect URIs.
