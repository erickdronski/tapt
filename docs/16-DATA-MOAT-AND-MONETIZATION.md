# Tapt, Data Moat & Monetization Thesis

The answer to "how do we become profitable / what's the wave." Extends docs/02
(sellable data) with the concrete free-tool land-grab, the paid ladder, and the
architecture that captures the asset from record one.

---
## The thesis in one paragraph
Get in **free and everywhere** as the dependable, QR-friendly, bulletproof
menu + presence tool for every brewery, bar, pub, and taproom. Free removes the
only objection, so we win distribution the incumbent's $1,199/yr wall can't. As
venues publish and drinkers log, we accrue the **two datasets nobody else owns
cleanly**: (1) a consent-architected **consumption taste-graph** (who drinks
what, where, when, in what mood, at what price), and (2) a live **venue / tap-
list panel** (what's actually pouring, where, right now). Those two, at metro
density, are the product: sold as B2B territory intelligence, and ultimately the
M&A asset. We are, deliberately, collecting as much *clean, consented* data as
possible and building it to be sellable and acquirable from day one.

## The wave (how the money actually shows up), sequenced
1. **Free land-grab** (now): free menus/QR/profile/events -> distribution.
2. **Stickiness** (free tools that make leaving painful): analytics, events,
   updates the venue relies on weekly.
3. **Prosumer subscription** (first real revenue): Featured/Spotlight + a Pro
   analytics tier venues pay for once they depend on the free basics.
4. **Data / territory intelligence** (the margin engine): aggregated, k-anon,
   consented demand + sentiment sold to breweries, distributors, CPG.
5. **The exit**: a dense, consent-clean, contracted-revenue dataset is exactly
   what Next Glass (Untappd), a big-beer player, or a CPG-data firm (Circana/
   NIQ-adjacent) acquires. Business-transfer + assignment clauses already shipped
   (docs/02) make the company sale the clean path.

---
## Deep research: what a brewery / bar / pub actually needs
Mapped to what we give FREE (land + retain) vs what we can CHARGE later.

### Free now (the land-grab, all built or near-built)
| Need | Tapt tool | State |
|---|---|---|
| Current menu without reprinting | Hosted tap list + editor | ✅ live |
| QR for tables / door | Auto-generated printable QR | ✅ live |
| Be findable | Claimed profile on the map | ✅ live |
| Promote happy hours / events / releases | Events & specials | ✅ live |
| Own brand look | Logo/branding upload | ✅ live |
| Know if it's working | Basic analytics (pours, drinkers, top beers) | ✅ live |

### Free next (deepen stickiness, cheap to build)
- **Weekly "update your taps?" nudge** email (freshness).
- **Shareable menu link + social card** (venue posts their Tapt menu to IG).
- **"On Tap Now" embed** widget for their own website.
- **Basic review/response** surface (they see check-in notes, can thank).
- **Multi-location** support for small groups.

### Paid later (the ladder, once they depend on free)
| Tier | ~Price | Value |
|---|---|---|
| **Featured / Spotlight** | $29 / $79 mo | Placement, event pushes to nearby drinkers |
| **Pro Analytics** | $49-99 mo | Trends over time, demographics-lite, style demand vs local benchmark, competitor-anon comparison, export |
| **Campaigns** | $199-499 | Sponsored badge/challenge tied to their release |
| **Menu/POS sync** | partner | Auto-tap-list ingestion (UTFB/POS), enterprise |
| **Priority + white-glove** | tier add-on | Managed onboarding, dedicated support |

### The two things breweries pay real money for (the data buyers)
1. **Territory demand intelligence**: "hazy IPA share is up 30% in your DMA,
   pilsner rising, your brand indexes 120 locally." Circana/NIQ own POS scanner
   data; what they PAY for is the attitudinal + occasion + intent layer we own.
2. **Sentiment / flavor signal**: ABSA on de-identified reviews, per style, per
   region. Named, citable indices (Style Demand, Momentum, Flavor Sentiment).

---
## The moat: what we collect and why it compounds
Every check-in is the atomic sellable unit (docs/04) and is ALREADY instrumented
for the CPG signals competitors skip:
- beer + brewery + style/substyle, rating, flavor tags
- **occasion** (home/bar/restaurant/event/sports), **on/off-premise**
- **geo bucket** (H3, never raw lat/long in the sellable layer)
- **daypart / day-of-week / season** (generated), **price paid / price tier**
- **purchase-intent** flags, plus **row-level consent** (sale_optin,
  location_optin, gpc_flag, consent_version)

Two-plane architecture with a hard boundary: personal plane (never sold) vs
aggregate plane (the only thing sold), k>=10 + min-venue + differential-privacy
+ sensitive-location suppression. The consent ledger is exportable for M&A
diligence (AB 1824). This is what makes the data legally sellable AND the
company cleanly acquirable, the whole reason to build it this way from record one.

Network effect: more venues -> more menus -> more drinkers -> more check-ins ->
richer per-metro panel -> more valuable to breweries/distributors -> revenue to
seed more metros. Density x exclusivity x contracted B2B revenue x refresh
velocity are the valuation levers, not raw DAU.

---
## Architecture: how each system reflects the thesis
**Supabase (the asset lives here):**
- `checkin_event` is event-first, immutable, consent-stamped (record-one capture).
- Two-plane split enforced by RLS + column grants + `aggregate_cell` (k-anon).
- `venue_analytics` / territory RPCs read the aggregate plane only.
- Everything a partner touches (claim/publish/logo/events) is an RPC gated by an
  approved claim -> clean provenance + auditability.
- Consent ledger append-only + exportable. Region-scoping (`is_eu_user`) keeps
  the EU set separable from any data sale.
- **Instrument now, monetize later**: capture is already rich; the sellable
  layer is a query away, not a re-architecture.

**GitHub (the operational + reproducibility spine):**
- Migrations are the versioned source of truth for the asset's shape (diligence
  loves this). CI proves the client compiles; TestFlight ships; ASC admin
  automates release. All $0, all auditable history.

**Vercel (the acquisition surface):**
- Landing/portal/admin/menu are the free-tool front door (distribution) and the
  business dashboard (retention). The portal IS the top of the data funnel.

**The app (the consumer data pump):**
- Every scan/log/vote feeds the taste-graph. Honest boards keep engagement real
  so the signal is real. Partner menus/events pull drinkers to venues, closing
  the loop that generates the panel.

---
## What to build to maximize the asset (priority order)
1. ✅ Partner analytics (proves value, retains, seeds the aggregate layer).
2. ✅ Events/specials (more venue data, more stickiness).
3. **Aggregate rollup job** (`aggregate_cell` populated on a cron once density
   exists) + the named indices RPCs. The literal product to sell.
4. **Consent surfacing in the app** (the toggles exist; make them prominent so
   opt-in rates are high and the sellable set is large + defensible).
5. **Pro Analytics tier** (time-series + benchmark) as the first data-priced SKU.
6. **Data clean-room / report export** for the first B2B contract.

## Honest guardrails (non-negotiable, they protect the exit)
- Zero fabricated data: a padded dataset is worthless in diligence and illegal
  to sell as real. Every number stays first-party or cited.
- Sensitive-location suppression + k-anonymity from day one (FTC location-broker
  enforcement is the existential risk for an alcohol app).
- Never sell raw PII; the product is the aggregated layer only.
- Free to drinkers forever: their trust is what makes the consented data legal
  and the sentiment honest.

## The one-line answer to "how do we get profitable"
Win distribution with free tools -> retain with analytics/events -> charge
prosumer venues for the Pro layer -> sell the aggregate territory/sentiment data
to breweries & distributors -> and the whole consent-clean, dense, contracted
asset is the M&A exit. Build every table to be sellable and acquirable from
record one; we already are.
