# Tapt — Expansion Masterplan (2026-07)

The coordinated path from "shipped superapp" to revenue and users. Extends
docs/11-ROADMAP.md with the GTM engine: waves, channels, outreach, pricing,
and the money loop. Standing rules apply to every wave: zero fabricated data,
free to drinkers forever, curiosity over capacity, license-clean only.

---
## Wave 0 — Launch-ready (now → App Store approval)
**Goal: nothing between us and a public "download Tapt."**
- Owner: 4 auth clicks (docs/09), legal counsel pass, App Store screenshots +
  metadata, submit for review (social/logging app, all four UGC moderation
  pieces already shipped — the 1.2/1.4.3 rails are in).
- Assets buttoned up: `brand/` is the canonical store (see brand/ASSETS.md),
  `marketing/` holds all GTM content, pitch deck lives at /pitch on the
  landing domain.
- Instrument the funnel honestly: signups, onboarding completion, first pour,
  D7 return — from our own Supabase, no third-party trackers to start.

## Wave 1 — Home-turf density (launch month, NJ/NYC metro)
**Goal: 500 real users + 25 claimed venues in ONE metro. Density beats DAU.**
- The playbook (docs/02): campus clusters, golf leagues, taproom regulars.
- Founder-led outreach: 10 venue conversations/week using the sequences in
  marketing/OUTREACH-PLAYBOOK.md (email first-touch → IG DM warm-up →
  in-person visit → Tapt's Favorite stamp as the closer).
- First 10 partners get **Founding Partner** status: free Featured placement
  for 6 months + landing-page logo row + launch-post shoutout. Costs us
  nothing, earns the case studies every later sale needs.
- Beer of the Week becomes the local hook: "Newark picks its beer of the
  week" is a story local media actually runs.

## Wave 2 — The content engine (parallel with Wave 1, ongoing)
**Goal: visibility without ad spend.**
- **Instagram = flagship** (see marketing/instagram/): 4 posts + 3 stories a
  week from the pillars — Passport stamps, Beer of the Week race, Beer School
  facts, venue spotlights, Dispatch teasers. Every post is real app data or
  real venues, screenshot-or-vector only.
- **The Tapt Dispatch** (subscribers already collecting): weekly, three
  blocks — what the world poured (real trend data), one venue story, one
  Beer School bite. The newsletter IS the retention channel until push
  notifications ship.
- **X/Threads**: clip the same content; beer Twitter is small but loud.
- **TikTok/Reels (later in wave)**: Beer Olympics nights + scan-anything demos
  film themselves.
- Push-to-social pipeline: share cards already render in-app; every BOW
  winner, new badge, and Tapt's Favorite stamp is a ready-made post.

## Wave 3 — Partner revenue on (metro 1 at ~2–5k users)
**Goal: first dollars without breaking "free to drinkers."**
Pricing (see the deck; anchored against Untappd for Business at $1,199/yr):
| Tier | Price | What they get |
|---|---|---|
| Claimed profile | **$0 forever** | On the map, publish taps, see local activity |
| Featured | **$29/mo or $290/yr** | Featured rail placement in their metro, event pushes |
| Spotlight | **$79/mo or $790/yr** | Top slot, Dispatch feature, quarterly performance recap |
| Festival/one-off | **$99–249 flat** | Event placement + BOW sponsorship-adjacent presence (never vote-buying) |
- Under half the incumbent's floor at the top tier. Positioning: "everything
  they charge $1,199 for, free — pay only to be *louder*, never to bury
  anyone."
- Partner elevation is product, not promises: Featured rail (built), Tapt's
  Favorite visits, Dispatch features, share-card co-branding, and (Wave 4)
  their uploaded press-kit imagery making their beers look best-in-app.
- Payments: Stripe invoices/payment links to start (no in-app purchase needed
  for B2B SaaS — keeps Apple's 30% out of it, same pattern as Nalee web).

## Wave 4 — Partner surfaces deepen (2+ metros)
- Partner asset uploads (official 4K imagery, the legal path to gorgeous).
- Self-serve claim + dashboard (until then: concierge onboarding by email).
- Distributor pilot (Manhattan Beer-type): one rep, fleet-claims their
  accounts' venues. Tied-house rail: distributor money NEVER buys retailer
  placement ranking.
- Tapt Voices launches (docs/11): 3 local creators per metro, permissioned
  lists, revenue-relevant.

## Wave 5 — Scale loops (10k+ users)
- Push notifications (APNs direct, already architected — no Firebase).
- Crew/Live Session ships (the flagship social differentiator from docs/00).
- Sponsored badges/challenges (platform-run, $299–999/campaign — the proven
  Untappd line, at our price).
- Newsletter sending goes pro (Resend paid tier only when subscriber count
  demands it — cost-gated owner decision).
- Metro expansion kit: repeat Waves 1–3 per metro with the same playbook.

## Wave 6 — The data authority era (per docs/02 + 11)
- Territory intelligence (k≥10, consent-gated) sold to breweries/distributors.
- Named indices published quarterly — the press hook AND the product demo.
- This is the valuation story: density × exclusivity × contracted B2B revenue.

---
## The money loop (why this compounds)
Users log pours → boards/BOW get lively → venues see real local heat → venues
claim + pay to be louder → featured venues bring their customers to Tapt →
more users log pours. Every wave feeds the next; nothing depends on paid ads.

## Channel map (all $0 to operate)
| Channel | Job | Cadence |
|---|---|---|
| Instagram | Discovery + brand | 4 posts/wk |
| Dispatch email | Retention + partner proof | Weekly |
| X/Threads | Beer-community presence | 3/wk (clips) |
| Landing + /pitch | Convert partners + press | Always on |
| In-app share cards | User-generated reach | Every pour/badge/BOW |
| Founder outreach | Partner pipeline | 10 touches/wk |

## KPIs per wave (honest numbers only, from our own DB)
- W1: 500 users, 25 claims, 40% onboarding→first-pour
- W2: 1k IG followers, 500 Dispatch subs, 20% weekly open-to-app rate
- W3: 10 paying partners = ~$500 MRR proof, churn <10%/qtr
- W4: 2 metros at W1 density, 1 distributor pilot signed
- W5: 10k users, $5k MRR, first sponsored campaign
- W6: first data contract

## Owner-action ledger (the only blockers)
1. Auth clicks (docs/09) → login pain gone.
2. App Store submission (screenshots + review).
3. Stripe account link for partner invoicing (Wave 3).
4. Instagram/TikTok handle registration (@tapt / @taptbeer — check + claim).
5. Legal counsel pass on privacy/terms + partner ToS before first invoice.
