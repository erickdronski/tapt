# Tapt — End-to-End Loop Audit (does every capability actually *close*?) 2026-07-11

Prompted by the right question: is Featured/Spotlight actually wired, localized, and
does the partner see value? It wasn't (now fixed, PR #12). This applies that same
"does the loop close" scrutiny to every major capability. Verified = checked live
against the DB/code this session. Gap = built-but-incomplete. Broken = does not work.
Owner = needs an account/key/click only you can do.

Legend: ✅ works · ⚠️ gap · ⛔ broken/blocker · 🔑 owner-gated

---

## 1. Auth + onboarding (the front door)
- ✅ Email OTP sign-in + verify (works; rate-limited on Supabase's default sender).
- ✅ Onboarding save (was RLS/keychain; fixed — signed app persists session, RPC grant present).
- ✅ Sim testing (UserDefaults shim; signed release uses Keychain).
- ⛔ **Google sign-in**: PKCE exchange errors in logs (`code verifier should be non-empty`, `OAuth state parameter missing`). Likely the same keychain-persistence issue on unsigned sim + a redirect/verifier config detail. Verify on a signed build; fix the config.
- ⚠️ **Apple Sign In**: entitlement is in the app but the provider isn't enabled in Supabase. **App Store Guideline 4.8 requires Apple Sign In if Google/Facebook are offered.** Launch-blocker for review. 🔑 (enable in Supabase, 10 min).
- ⚠️ Facebook: not configured (same external-app setup as Google).
- 🔑 **Custom SMTP (Resend)** so OTP isn't rate-limited/spammy at launch. Owner.
- ⚠️ Empty states: first-run has no friends/pours/votes; copy is honest but audit each screen's zero-state before launch.

## 2. Beer market + voting (the signature loop)
- ✅ Voting RLS correct: insert/update/select/delete all gated to `user_id = auth.uid()`; one vote per user (PK); vote change = upsert; a user only reads their own vote (aggregates via RPC).
- ✅ Scale: per-write full-rebuild trigger removed; market + score materialized on a 5-min cron; leaderboard read ~0.09ms flat (PRs #6/#10).
- ✅ Ties: deterministic (`order by net desc, name`).
- ⚠️ Lone-voter / low-density: the market is honestly empty until real votes arrive. Make sure the UI's empty/low-N state reads as "be the first," not "broken."
- ⚠️ Abuse: one vote per user caps ballot-stuffing, but nothing rate-limits rapid up/down flipping or flags coordinated brigading. Low risk pre-scale; add a per-user flip rate-limit + anomaly flag before it matters.
- ⚠️ Beer of the Week: lock cron exists but needs real votes; the winner display is empty until then (correct).

## 3. Partners: claim → menu → featured (the revenue loop)
- ✅ Claim (search → claim → human approve via /admin), tap list, logo, events, hosted menu + QR. Payloads match RPC contracts (verified).
- ✅ Featured/Spotlight: NOW localized + reach-tracked + measurable + auto-expiring (PR #12). `grant_featured` is the activation the Stripe webhook calls.
- ⚠️ Auto-approve by email-domain match (planned in docs/13, not built) — reduces approval latency.
- ⚠️ **Claim disputes / transfers / ownership change**: no flow. What if two people claim the same venue? Current: human approves one; there's no transfer or dispute path. Build before scale.
- ⚠️ Multi-location groups: one claim = one venue; no group/roll-up management.
- ⚠️ Inquiry → auto-email on approval: needs Resend (the `resend-send` fn is built). 🔑
- 🔑 **Stripe**: self-serve Featured checkout → webhook → `grant_featured`. Not built (owner account + the webhook fn).

## 4. Partner analytics (the "see the value" loop)
- ✅ `venue_analytics`: pours, drinkers, avg rating, top beers + (new) Featured reach (impressions/taps/CTR/reached).
- ⚠️ Depends on venue-tagged check-ins, which are sparse until drinkers log with venue location. Ensure the scan/log flow captures `venue_id` reliably (via QR scan at the venue). This is the input that makes analytics non-empty.

## 5. Privacy + data (the trust + legal loop, and the moat)
- ✅ Consent ledger append-only; two-plane design; RLS on all sensitive tables.
- ⛔/⚠️ **Account deletion**: `account_deletion_request` + `requestAccountDeletion` exist, but is a *request*, not a delete. **App Store Guideline 5.1.1(v) requires in-app account deletion that actually deletes.** If nothing processes the request, this is a review blocker and a trust problem. Needs a verified deletion path (edge fn or admin flow that hard-deletes the user's personal-plane rows + auth user). HIGH priority.
- ⚠️ Consent actually gating the sellable layer: verify `aggregate_cell` / `territory_report` exclude users with `sale_optin=false` / `gpc_flag` / EU, with k≥10 + sensitive-location suppression, before any data is ever shown/sold.
- ⚠️ EU separation (`is_eu_user`) enforced in the aggregate plane.

## 6. Moderation / safety (App Store 1.2 UGC)
- ✅ `block_user`, `report_content`, moderation_status on check-ins, sensitive-location suppression. The four UGC-safety pieces shipped.
- ⚠️ Verify the report/block flows are reachable from every UGC surface (feed, #sayNAH-equivalent, profiles) and that reports create an actionable admin queue.

## 7. Content + catalog
- ✅ 11K beers @95% imaged, 11.9K breweries, 8.7K venues, 60 BJCP styles, real awards (Allagash 19-medal, cited).
- ⚠️ Image *quality* ceiling (OFF user photos); premium comes from partner uploads.
- ⚠️ Awards depth: only Allagash seeded richly; a verified-source award ingestion (Brewers Association published winners) would populate more, carefully matched.

## 8. Newsletter (the retention loop)
- ✅ Full pipeline: subscribe → real content generator → branded issue → weekly send cron. 🔑 owner sets `RESEND_API_KEY` + `CRON_SECRET`.

## 9. Landing / portal / web (the acquisition surface)
- ✅ Redesigned landing, portal (claim→menu→reach analytics). Vercel auto-deploys on merge.
- ⚠️ **App↔web sync is manual**: real counts (11K/108 countries), feature list, and support email must be kept in step with the app. Single source of truth for stats would help.
- ⚠️ Support email is a personal Gmail; a dedicated business address is needed (owner creates; I wire it).

## 10. Owner-gated activation (nothing ships without these)
🔑 Apple Sign In · App Store submission · Resend (SMTP + newsletter) · Stripe · APNs push · a business support email · legal (privacy/terms + partner ToS).

---

## Priority order (what actually gates launch + revenue)
1. ⛔ **Account deletion that deletes** (App Store 5.1.1(v)).
2. ⛔ **Apple Sign In enabled** + Google PKCE fixed (App Store 4.8; sign-in reliability). 🔑+build.
3. 🔑 **Resend SMTP** (sign-in email reliability) + newsletter secrets.
4. **Consent gating verified** on the aggregate plane before any data surfaces.
5. **Stripe → grant_featured** to make Featured self-serve (revenue).
6. **Claim disputes/transfers** + auto-approve; **venue_id capture** in the scan/log flow (analytics input).
7. Voting abuse rate-limit; empty-state polish; awards depth; app↔web stat sync.

The engine and the loops are largely real now. The remaining launch gates are (1)-(3);
the remaining *business* completeness is (4)-(7). I'll work these top-down.
