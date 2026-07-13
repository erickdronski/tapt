# Edge functions — deployed state mirror

Every function deployed to the Supabase project (`qfwiizvqxrhjlthbjosz`) lives
here, byte-for-byte. If you change a function, deploy it AND update this mirror
in the same commit — the repo is the source of truth for takeover/audit.

| Function | verify_jwt | Notes |
| --- | --- | --- |
| `dispatch-weekly` | false | Weekly Dispatch content generator. Cron-invoked; requires `CRON_SECRET` header check inside the function. |
| `dispatch-signup` | false | Public landing-page newsletter signup. Own guards: honeypot, per-IP throttle, email validation, never resurrects an unsubscribed address. |
| `resend-send` | false | Partner welcome email + admin Dispatch blast. Does its own auth (caller JWT via Authorization header; admin check for blasts). No-ops without `RESEND_API_KEY`. Dispatch blasts hard-require `MAIL_POSTAL_ADDRESS` (CAN-SPAM) and send per-recipient unsubscribe links + RFC 8058 one-click headers. |
| `newsletter-unsubscribe` | false | Token-gated unsubscribe (the token is the secret). GET redirects humans to `/unsubscribe`; POST is the one-click/page action. Generic responses, never confirms address existence. |
| `obdb-sync` | true | Retired (410). One-shot Open Brewery DB import, completed 2026-07-09. |
| `verify-barcode-beer` | true | Re-fetches the barcode from Open Food Facts, requires a beer category, sanitizes source fields, and calls the service-role-only catalog insert. Client payloads cannot write canonical product metadata. |

Secrets the functions read (owner-set in Supabase dashboard, never in repo):
`RESEND_API_KEY`, `RESEND_FROM` (optional), `MAIL_POSTAL_ADDRESS` (CAN-SPAM
postal address, required before any newsletter blast), `CRON_SECRET`.
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform.
