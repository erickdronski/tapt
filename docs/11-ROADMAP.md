# Tapt — Roadmap & positioning (2026-07)

Where Tapt is headed, in sequence. The moat stays the same at every phase:
**honest first-party data + free-for-drinkers + supply-side revenue.**

## Now live (the foundation)
Scan-anything loop (catalog + Open Food Facts fallback) · 8.6k+ venue world map
· beer pages with cited style science, nutrition, awards · honest beer market +
Beer of the Week + leaderboards (incl. No/Low board) · friends/feed/moderation
· Passport (50 states + 47 countries) · games + Beer School · The Tapt Dispatch
(collecting) · partner inquiries + featured rail · landing page · 5 languages.

## Phase 1 — density & trust (now → first 1k users)
- **Awards ingest cadence:** World Beer Cup (spring), World Beer Awards
  (August), GABF (fall). Facts with citations into `beer_award`; "Decorated"
  section already renders them. One scripted run each.
- **Owner unblocks:** Apple provider save (secret field EMPTY), redirect
  allowlist, `{{ .Token }}` in the email template, custom SMTP when ready.
- **Image coverage:** OFF backfill re-runs with slower pacing (SLEEP=10+);
  every user scan adds real label photos automatically.
- **Metro seeding playbook** (from docs/02): pick 1–2 launch metros (NJ/NYC is
  home turf), first-check-in incentives, campus/golf/taproom clusters.

## Phase 2 — Tapt's Favorite (the "we were here" program)
The schema is live (`beer_award.medal='tapt_favorite'`, scope global|local,
per-region). The program:
- **What it is:** Tapt's own public, first-party accolade. We visit, we pour,
  we vote as a business — then stamp it. Beer pages show "🍺 Tapt's Favorite —
  we were here, we poured it, we loved it," with region and date.
- **Why it works:** it's an award nobody can buy (explicitly not tied to
  featured placement — tied-house rules and our own no-pay-to-bury promise),
  it generates partnership conversations ("come get your stamp"), local press
  hooks, and a repeatable content series (one pick per metro per month).
- **Mechanics:** owner grants via one SQL insert (or a future admin surface);
  announcement in the Dispatch + share card; annual "Tapt's Favorites of the
  Year" roundup voted from the year's picks + community BOW winners.

## Phase 3 — creators & influencers (Tapt Voices)
- **Principle:** real voices with permission — never scraped quotes, never
  implied endorsements. A creator's pick appears only under an agreement.
- **Product shape:** `curated_list` (creator, title, beers[], blurb, links) —
  the shareable themed-list pattern the incumbents have, but attributed and
  revenue-relevant (creators drive partner traffic; partners fund the program).
- **Sequence:** local beer writers/podcasters in launch metros first (they
  need reach, we need credibility), national creators after density.
- **Tie-in:** creators can co-sign Tapt's Favorite visits ("picked with ___").

## Phase 4 — the No/Low market (already first-class, deepen it)
NA is the fastest-growing segment (cite Beer Institute/BA numbers in pitch
decks). Already: NA beers count fully, No/Low lens, zero-proof leaderboard,
NA styles in reference. Next: NA-only Flights expansion, NA Beer of the Week
lane, partner filter ("pours great NA options"), Dry January campaign each
December/January — our wedge with drinkers the incumbents treat as an
afterthought.

## Phase 5 — business surfaces (consume the $1,199/yr model)
- Free forever: claimed profile, tap-list publishing, local scene activity.
- Paid (fraction of four figures): featured/spotlight placement, event pushes,
  release announcements to nearby matched drinkers, richer analytics.
- Partner asset uploads = the legal path to official high-res imagery.
- Later: self-serve portal; until then the in-app inquiry + owner curation is
  the pipeline.
- **Distributor channel:** regional distributors (e.g. Manhattan Beer in
  NYC/NJ — home turf) touch hundreds of accounts each; one distributor
  relationship can seed venue claims at fleet scale and is a natural buyer of
  the Phase-6 territory data. Producer lists (VinePair top-40, Thomasnet) are
  reference-only for target mapping — never data sources. Compliance rail:
  keep manufacturer/distributor money in separate lanes from retailer
  placement (tied-house rules, per docs/01).

## Phase 6 — data authority (the sellable layer, per docs/02)
Aggregate-only territory intelligence once density exists (k≥10, consent-gated
— the rails are already in the schema). Named indices (Style Demand, Momentum)
published with sample sizes. The awards + Tapt's Favorite layers add editorial
authority on top of the quantitative layer.

## Standing rules at every phase
1. Zero fabricated data — blank beats invented, boards move only on real
   activity, every fact cites its source.
2. Free to drinkers forever — every monetization idea is supply-side.
3. Curiosity over capacity — no volume-glorifying mechanics, NA first-class,
   responsible-drinking rails stay.
4. License-clean only — if we can't own it or cite it, we don't ship it.
