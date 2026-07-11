# Tapt — Verified Build-Out State + Brewery/Bar Value Proposition (2026-07-10)

A ground-truth audit (queried live against Supabase `qfwiizvqxrhjlthbjosz`, not from
memory), the honest gap map, and a deep partner value proposition. Complements docs
13 (partner workflow), 14 (status/roadmap), 16 (data moat). Standing rules unchanged:
**zero fabricated data, free to drinkers forever, real/cited only, blank beats invented.**

---

## 1. Verified reality (what's actually in the database, today)

| Asset | Live count | Note |
|---|---|---|
| Breweries | **11,894** | Open Brewery DB import — real |
| Catalog beers | **11,062** | OFF ingest (doc 14's "187" is stale) |
| Beers with a label image | **10,523 (95%)** | doc 14's "68 photos" is stale; coverage is solved, *quality* is not |
| Venues | **8,694** | 25+ countries |
| BJCP style references | **61** | + 38 style aliases |
| Region beer guides | **54** | |
| **Beer awards** | **1** | ← thin; "verified awards layer" is a stub |
| **Featured partners** | **0** | monetization surface unexercised |
| **Venue claims / tap items / snapshots** | **0 / 0 / 0** | partner system built, never used |
| **Partner inquiries** | **0** | |
| **Newsletter subscribers** | **0** | doc says "collecting"; form may not be reaching the table |
| **Beer-of-the-Week winners** | **0** | never locked (no votes yet) |
| Check-ins / pours / votes / follows / crews | **0** | expected pre-launch (no users) |
| User profiles | **2** | test accounts only |

**Backend RPCs that already exist** (verified): `claim_venue`, `publish_tap_list`,
`set_venue_logo`, `set_venue_events`, `venue_analytics`, `venue_menu`, `venue_brand`,
`venue_events`, `featured_partner_feed`, `submit_partner_inquiry`, `admin_claims`,
`set_claim_status`, `my_venue_claims`, `search_venues`, `subscribe_newsletter`,
`newsletter_status`, `unsubscribe_newsletter`, `territory_report`,
`refresh_aggregate_cells`, plus the full social/catalog set.

**Takeaway:** the backbone (content, brewery/venue map, catalog, styles), the partner
system, and even the Phase-E data-product RPCs are **built**. What's missing is
execution *around* them, not the core.

---

## 2. The honest gap map

### A. Built but empty (need real content / demo, not code)
- `beer_award` (1 row) — seed **real, citable** medals (GABF, World Beer Cup, GBBF)
  matched to catalog beers/breweries. Enriches beer pages **and** is a brewery benefit.
- `featured_partner` / `venue_claim` / `venue_tap_item` — no live partner; and no way
  to *demonstrate* value to a prospect pre-density.
- `beer_of_week_winner` — needs real votes; do **not** fake a winner. Editorial
  "Tapt's Favorite" is the legitimate pre-vote pick.

### B. Missing app-side surfaces (backend exists, no UI or web-only)
- **In-app "claim your venue"** entry (Phase A [build]) — currently web-portal only.
- **Brewery/partner analytics view in-app** — `venue_analytics` RPC exists; no
  claimed-owner dashboard surface in the app.
- **Tapt's Favorite admin surface** — currently a SQL insert.
- **"On Tap Now" website embed** + shareable menu social card (doc 16 "free next").

### C. Owner-gated (I cannot create accounts / incur cost; these are yours)
- **Resend** (free tier) → partner approval/inquiry emails + newsletter *sending*.
- **Custom SMTP** (Resend) → fixes the sign-in email rate-limit (hit repeatedly today).
- **Stripe** → Featured/Spotlight + Pro invoicing (Wave 3).
- **APNs .p8** → push notifications (retention lever).
- **Apple auth + App Store submission** (docs/09) — the launch gate.

### D. Polish
- Games: Pong / Flip Cup / Quarters still elementary (Darts-grade rework pending).
- Image *quality*: OFF photos are user-shot; premium comes from partner uploads (Phase D).
- Sim auth testability — fixed in PR #1 (simulator-only UserDefaults session store).

### E. Big builds (high payoff, later phases)
- **Crew / Live Session** — real-time shared group check-in + live leaderboard + photo
  wall. The flagship social differentiator (Phase D).
- **Aggregate rollup job + named indices** (`aggregate_cell`, Style Demand / Momentum /
  Flavor Sentiment) — the literal B2B product (Phase E, needs density first).
- **Android** (native Kotlin, same backend) — if demand pulls.

### F. Verification debt (honesty rule)
- No flow is currently confirmed end-to-end in a running build this session — email OTP
  is rate-limited and Google PKCE is erroring. Every "works" claim stays *pending* until
  clicked through in the app.

---

## 3. The brewery & bar value proposition (the two-sided engine)

### The wedge
Untappd for Business charges **~$1,199/yr** for menu hosting + basic analytics and
**locks the venue's own data inside their walled garden**. Tapt gives the exact working
tools away **free**, removing the only real objection at the door, and earns later on
"be louder" (placement) and "know your market" (demand data) — never on the tools a
venue needs to operate. Free is the distribution weapon the incumbent's paywall can't match.

### What a partner actually gets, mapped to their real jobs-to-be-done
| Their job (pain) | Tapt gives them | Tier |
|---|---|---|
| Keep the menu current without reprinting | Hosted live tap list + editor, 14-day freshness | **Free** |
| Put a menu on every table/door | Auto-generated printable QR → hosted `/menu` | **Free** |
| Be findable when drinkers pick where to go | Claimed profile on the map | **Free** |
| Own their brand look | Logo/branding upload | **Free** |
| Promote a release / happy hour / event | Events & specials, pushed to nearby drinkers | **Free → Featured** |
| Know if it's working | Real local activity: pours, top beers, drinker signal | **Free basic → Pro** |
| Stand out over the bar down the street | Featured rail + event pushes | **$29/mo** |
| Top slot + Dispatch newsletter feature | Spotlight | **$79/mo** |
| Decide what to brew/stock next | **Territory demand intelligence**: "hazy IPA share +30% in your DMA; your brand indexes 120 locally" | **Data tier** |

### Why they partner (the pull, not the push)
1. **Zero cost, zero risk, 10-minute setup.** Claim → publish taps → print QR. No
   subscription to justify to an owner.
2. **The drinker flywheel brings them feet.** Drinkers scan a table QR or open the app,
   see the live list, log a pour → that pour feeds the venue's local heat *and* the
   "Tonight" board that pulls other drinkers in. The tool that operates their menu is the
   same tool that markets them.
3. **They finally see their own demand.** Incumbents lock it; Tapt shows the claimed
   owner their real signal for free, then sells the *territory* view (what the whole DMA
   is drinking, how their brand indexes) — the attitudinal/occasion/intent layer that
   Circana/NIQ scanner data doesn't have.
4. **Freshness that markets itself.** A menu that's provably live (14-day expiry, "updated
   2h ago") beats a laminated card and a dead Untappd page.

### The tiers, and why each price is fair
- **Free (land + retain):** menu, QR, profile, events, logo, basic analytics. The venue
  comes to *depend* on these weekly — that dependence is the moat.
- **Featured $29 / Spotlight $79 (be louder):** placement + pushes to nearby drinkers.
  Priced below one keg of lost demand; it's advertising, not tooling.
- **Pro Analytics $49–99 (know your market):** time-series, style demand vs. local
  benchmark, competitor-anon comparison, export. The first data-priced SKU.
- **Territory / sentiment data (the margin engine):** aggregated, k≥10, consent-clean
  demand + flavor indices sold to breweries/distributors/CPG. Named, citable.

### Objection handling
- *"We already use Untappd."* → Keep it; add Tapt free, print our QR, see which your
  drinkers actually use. Ours is live and free; theirs is $1,199 and stale.
- *"We don't have time."* → Claim + first tap list is under 10 minutes; menus expire so
  you only touch it when something changes; we'll nudge you.
- *"Another subscription?"* → No. The tools are free forever. You only ever pay to be
  louder or to see the market — and only once you already rely on the free basics.

### A partner's day-in-the-life (the loop we're building toward)
> A brewery taproom claims their venue in the portal, publishes 12 taps, prints the QR,
> and drops it on the tables. Friday night, 40 drinkers scan and log pours. Saturday the
> owner opens Tapt and sees "312 pours this week, your Hazy IPA is #1, up 22% — and hazy
> demand in your DMA is up 30%." They tap "Feature this weekend's release," it pushes to
> 600 nearby drinkers, and they upgrade to Pro to watch the trend. **The tool that runs
> their menu is the tool that grows their business — and every pour makes the data we
> sell more valuable.** That's the flywheel.

---

## 4. The drinker side (why the free side stays strong — it has to)
Free forever. Scan any beer on Earth → real style science, nutrition, awards, brewery
story, where-to-find. Log the pour → stamp the Passport, feed honest boards (Beer of the
Week, leaderboards, No/Low lens), see friends' activity, play a round. The drinker's trust
is what makes the consented data legal and the sentiment honest — **so drinker delight is
not charity, it's the input to the whole business.** Every scan/log/vote is the atomic,
consent-stamped, sellable unit.

---

## 5. Prioritized wave plan (what gets built, in order)

Constraints honored: real data only, **no parallel agent/build fleets** (sequential),
no unprompted cost, **verify in the running app** before claiming done.

**Wave 1 — Content + brewery value made real (buildable now, no cost, verifiable):**
1. This doc (done).
2. Seed **real, citable beer awards** (GABF/World Beer Cup/GBBF) matched to catalog
   beers/breweries — verify each match, insert only confident ones. Enriches beer pages
   + brewery benefit. *(fetch real results; no fabrication)*
3. **In-app "For Breweries & Bars" surface + claim/inquiry entry** — make the partner
   value tangible inside the product (Phase A [build]).
4. **In-app brewery analytics view** for a claimed owner (surfaces the existing
   `venue_analytics` RPC) — the retention hook, honest empty-state pre-density.

**Wave 2 — Polish + verification (once sim auth is unblocked):**
5. End-to-end walkthrough of every flow in the sim; fix runtime bugs live.
6. Game rework: Pong / Flip Cup / Quarters to Darts-grade.
7. Tapt's Favorite admin surface (retire the SQL insert).

**Wave 3 — Owner-gated integrations (I build the code; you supply the account/key):**
8. Resend wiring: partner approval/inquiry emails + newsletter send + custom SMTP.
9. Stripe: Featured/Spotlight/Pro invoicing.
10. APNs push: "friends out now", BOW results, a claimed venue's new release.

**Wave 4 — Flagship + data product:**
11. Crew / Live Session (real-time group check-in).
12. Aggregate rollup job + named indices RPCs (needs density).

**Wave 5 — Launch gate (owner):** Apple auth, App Store submission, legal pass, handles.

---

## The one-line answer
The engine is built. Win now by making the **brewery value tangible in-app**, filling the
**real content** gaps, **verifying every flow live**, then turning on the **owner-gated
revenue rails** — and the Crew build + territory data are the depth that follows density.
