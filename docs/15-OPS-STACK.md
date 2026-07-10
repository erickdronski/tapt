# Tapt, Operational Stack (all free tier)

Everything running Tapt as a business, on $0 tooling. This is the full
operational picture: what each tool does, what's automatic, and the few
owner setup actions.

## The free-tool stack
| Tool | Job | Tier | Status |
|---|---|---|---|
| **Supabase** | Postgres DB, Auth, Storage, Edge Functions, RLS | Free | Live (project qfwiizvqxrhjlthbjosz) |
| **Vercel** | Hosts landing, /portal, /admin, /menu, /pitch | Free | Live (tapt-landing-three.vercel.app) |
| **GitHub Actions** | CI compile-check + TestFlight upload + ASC admin | Free (public repo = unlimited macOS min) | Live |
| **Resend** | Transactional + newsletter email | Free (3k/mo, 100/day) | Wired, needs owner API key |
| **Open Brewery DB** | Venue/brewery data | Free/open | Ingested |
| **Open Food Facts** | Barcodes, label photos, nutrition | Free/open | Ingested + live scan |
| **BJCP 2021** | Beer style science | Free/reference | Ingested |
| **api.qrserver.com** | QR code generation (menus) | Free | Live |
| **App Store Connect** | TestFlight + App Store | Apple dev acct (owned) | Live |

## What runs automatically (no human)
- **CI + TestFlight**: every push compiles; TestFlight builds auto-assign to
  the tester group (asc-admin.yml on workflow_run).
- **Partner claims**: auto-approve when the claimant's email domain matches the
  venue's website domain (generic providers -> /admin queue).
- **Beer market**: recomputes on every vote/check-in; nightly trend refresh +
  Monday Beer of the Week lock (pg_cron).
- **Partner welcome email**: fires on approval (auto or admin) with the venue's
  QR/menu link. (Requires the Resend key, below.)
- **Menu freshness**: published tap lists expire after 14 days.

## The owner control panel: /admin
`tapt-landing-three.vercel.app/admin` (sign in with esdronski@gmail.com). One
page to run the business:
- **Ops dashboard**: real first-party metrics (drinkers, venues claimed, live
  menus, pours, votes, Dispatch subs, new inquiries, beers). All from our own
  DB, zero third-party trackers.
- **Partner inquiries** feed + **venue claim queue** (1-click Approve/Reject,
  approval auto-emails the owner their QR).
- **Send The Tapt Dispatch**: compose subject + body, blast all subscribers.

## Owner setup (the only actions to go fully operational)
1. **Resend** (5 min): create a free account at resend.com -> API Keys ->
   create key. In the Supabase dashboard: Edge Functions -> Manage secrets ->
   add `RESEND_API_KEY = re_...`. (Optional `RESEND_FROM` once you verify a
   sending domain; until then it sends from `onboarding@resend.dev`, which
   works on the free tier with no domain setup.)
   -> The moment this key is set, partner welcome emails + the Dispatch send
   work. Until then, everything else runs and email calls no-op gracefully.
2. **App Store**: submit for review (screenshots + metadata).
3. **Apple auth**: docs/09 dashboard clicks.
4. **Stripe**: create account -> use Payment Links for Featured/Spotlight
   invoicing when the first venue upgrades (no code needed).
5. **Social handles**: claim @taptbeer.

## Cost ceiling (honest)
$0 today. First real costs only appear at scale: Resend past 3k emails/mo
(then $20/mo), Supabase past the free tier (8GB DB / 5GB bandwidth), Vercel
past free bandwidth. All are usage-gated and far past first-metro traction, so
the business runs at $0 until it's clearly working.

## Verified working (2026-07-10)
- admin_stats() returns real metrics · resend-send deployed (graceful no-op
  without key) · portal auto-approve emails on domain match · admin approve
  emails owner · Dispatch send admin-gated · all pages live (200).
