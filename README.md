# Tapt 🍺

**THE Beer Superapp.** Free, global, scan-first: point your camera at any label, tap list, or barcode — anywhere on Earth — log the pour to your **Cellar**, stamp your **Passport**, ride the **beer stock market**, climb the **leaderboards**, play beer-night games, and find what's actually good at breweries, pubs, bars, taprooms, and beer gardens near you. Free to drinkers forever; breweries fund the party.

**Stack:** native Swift 6 / SwiftUI (iOS 18+) · Supabase (Postgres + PostGIS + Auth + Edge Functions) · MapKit · Open Brewery DB + Open Food Facts + BJCP-sourced content.

## The honest-data rule
Nothing in Tapt is fabricated. Every venue has real coordinates and provenance (`ingestion_source`), every beer is a real product, and every popularity/momentum/rating number is computed **only** from first-party votes and check-ins (`refresh_beer_trend()`d on every signal). Boards are honestly empty until the community moves them. Blank beats invented, always.

## What's live (backend + app)
- **Global beer radar** — ~8,700 real venues across 25 countries (Open Brewery DB, coordinate-verified), daily-rotating world sample + PostGIS "near me" feed
- **Catalog** — ~190 world-classic beers across 47 countries + scan-to-catalog: any barcode on Earth resolves via Open Food Facts and joins the catalog GTIN-dedup'd
- **Beer stock market** — Explore board computed live from votes + pours (region-attributed, 7-day momentum, nightly decay)
- **Leaderboards** — beers / tasters / styles, all first-party signal
- **Social** — follow graph, profile search, Tonight live feed, report/block moderation
- **The Tapt Dispatch** — in-app newsletter signup (onboarding opt-in + Discover + You)
- **Partnerships** — inquiry flow for breweries/bars/pubs/taprooms + curated featured placements (real partners only; no pay-to-bury)
- **Beer School + Games** — brewing, glossary, history, origin stories; trivia, Tapt Deck, pong, flip cup, quarters, Beer Night mode
- **Passport** — 50 states + 47 countries, curiosity-weighted badges (never volume)

## Read first
1. `docs/00-CONCEPT.md` — the whole thing on one page
2. `docs/01-PRODUCT-BRIEF.md` — full product brief
3. `docs/02-SELLABLE-DATA-AND-MAPS.md` — M&A/data-asset, Apple Maps, privacy
4. `docs/04-SCHEMA-NOTES.md` — the data model
5. `docs/03-DATA-SOURCES.md` — 74 sources w/ commercial-license verdicts

## CI
- `build.yml` — compile-verify on every push (simulator, unsigned)
- `testflight.yml` — manual dispatch → signed archive → TestFlight

## Status
- [x] Research + synthesis · name locked (**Tapt**) · Supabase project + repo
- [x] Auth (email magic link, Google/Facebook/X OAuth) · scan loop · map · check-ins · Passport
- [x] Superapp layer: global content ingest, honest market engine, leaderboards, newsletter, partner featuring, friends
- [ ] Owner: enable Apple Sign-In provider (Supabase) + flip the button in `SignInView`
- [ ] Owner: first real featured partners (`featured_partner` rows) once inquiries land
- [ ] Newsletter sending pipeline (subscribers are collecting; sending is a later, cost-gated decision)
