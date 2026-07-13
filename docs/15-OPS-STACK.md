# Tapt Operational Stack

This is the operational picture: what each service does, what is automatic,
and which owner actions still gate production reliability.

## The free-tool stack
| Tool | Job | Tier | Status |
|---|---|---|---|
| **Supabase** | Postgres DB, Auth, Storage, Edge Functions, RLS | Account plan | Live; outstanding invoice warning |
| **Vercel** | Hosts landing, /portal, /admin, /menu, /pitch | Account plan | Live at taptbeer.com |
| **GitHub Actions** | CI compile-check + TestFlight upload + ASC admin | Account allocation | Live |
| **Resend** | Transactional + newsletter email | Account plan | Functions deployed; production sender/secret proof pending |
| **Open Brewery DB** | Venue/brewery data | Free/open | Ingested |
| **Open Food Facts** | Barcodes, label photos, nutrition | Free/open | Ingested + live scan |
| **BJCP 2021** | Beer style science | Free/reference | Ingested |
| **api.qrserver.com** | QR code generation (menus) | Free | Live |
| **App Store Connect** | TestFlight + App Store | Apple dev acct (owned) | Live |

## What runs automatically (no human)
- **CI**: app-touching pushes compile and test. TestFlight upload is manual;
  successful uploads trigger the App Store Connect administration workflow.
- **Partner claims**: auto-approve when the claimant's email domain matches the
  venue's website domain (generic providers -> /admin queue).
- **Beer market**: recomputes on every vote/check-in; nightly trend refresh +
  Monday Beer of the Week lock (pg_cron).
- **Partner welcome email**: the approval path calls the deployed sender with
  the venue's QR/menu link and reports success only on provider confirmation.
- **Menu persistence**: partner-published tap lists remain until replaced;
  short-lived crowd sightings expire separately.

## The owner control panel: /admin
`taptbeer.com/admin` (sign in with esdronski@gmail.com). One
page to run the business:
- **Ops dashboard**: real first-party metrics (drinkers, venues claimed, live
  menus, pours, votes, Dispatch subs, new inquiries, beers). All from our own
  DB, zero third-party trackers.
- **Partner inquiries** feed + **venue claim queue** (1-click Approve/Reject,
  approval auto-emails the owner their QR).
- **Send The Tapt Dispatch**: compose subject + body, blast all subscribers.

## Owner setup (the only actions to go fully operational)
1. **Supabase billing:** resolve the outstanding invoice warning before relying
   on the project for an App Store release.
2. **Resend:** verify `RESEND_API_KEY`, `RESEND_FROM`, the sender domain, postal
   address, and a real partner welcome/Dispatch delivery.
3. **App Store:** complete screenshots, metadata, privacy answers, agreements,
   tax/banking, territories, beta review settings, and signed-device auth tests.
4. **Apple auth:** finish the provider configuration in `docs/09-AUTH-SETUP.md`.
5. **Paid reach:** approve commercial terms before wiring Stripe or publishing
   self-service prices.

## Cost controls
No agent may add a paid service or change a plan without owner approval. Check
current provider billing pages instead of relying on hardcoded tier limits or
prices in this document. The existing Supabase invoice warning is not a future
scale cost; it is a current service-continuity risk.

## Verified working (2026-07-13)
- admin_stats() returns real metrics · resend-send deployed (graceful no-op
  without a working sender) · portal domain-match claims and owner approvals
  can request welcome mail · Dispatch send remains admin-gated · canonical
  public pages on taptbeer.com return 200.
