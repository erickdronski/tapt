# Tapt

**THE Beer Superapp. All of beer, one app.** Discover and search real beer products, scan supported labels and barcodes, log pours to your **Cellar**, build a location-aware **Passport**, follow the **Beer Market**, play table games, and find breweries, pubs, bars, taprooms, and beer gardens near you.

**Stack:** native Swift 6 / SwiftUI (iOS 18+), Supabase (Postgres, PostGIS, Auth, Storage, Edge Functions), MapKit, Open Brewery DB, Open Food Facts, and BJCP-sourced content.

## The honest-data rule
Nothing in Tapt is fabricated. Every venue has real coordinates and provenance (`ingestion_source`), every beer is a real product, and every popularity/momentum/rating number is computed **only** from first-party votes and check-ins (`refresh_beer_trend()`d on every signal). Boards are honestly empty until the community moves them. Blank beats invented, always.

## What's live (backend + app)
- **Beer radar:** Provenance-backed venues plus MapKit local search and a PostGIS nearby feed
- **Catalog:** Normalized beer identities, product media, style data, nutrition where sourced, and Open Food Facts barcode resolution
- **Beer Market:** Indexed standings built from season, cited awards, catalog context, and first-party votes and pours
- **Leaderboards:** Beer, taster, and style boards using first-party signals only
- **Social:** Follow graph, profile search, Tonight feed, reporting, and blocking
- **The Tapt Dispatch:** Explicit newsletter opt-in in onboarding, Discover, and You
- **Partner tools:** Venue claims, permanent hosted menus, QR pages, event submissions, and owner review
- **Beer School and Games:** Brewing, glossary, history, origin stories, trivia, Tapt Deck, SpriteKit beer pong, flip cup, quarters, and Beer Night mode
- **Cellar and Passport:** Distinct-beer progress across styles, states, and countries, with curiosity-weighted milestones instead of volume rewards

## Read first
1. `docs/00-CONCEPT.md` - the whole thing on one page
2. `docs/01-PRODUCT-BRIEF.md` - full product brief
3. `docs/02-SELLABLE-DATA-AND-MAPS.md` - data assets, Apple Maps, and privacy
4. `docs/04-SCHEMA-NOTES.md` - the data model
5. `docs/03-DATA-SOURCES.md` - source and commercial-license review

## CI
- `build.yml` - compile and unit-test on app-touching pull requests and `main` pushes (simulator, unsigned)
- `release-integrity.yml` - Python/workflow/admin-module validation plus Deno checks for release Edge Functions
- `testflight.yml` - manual signed archive and TestFlight upload
- `asc-release-prepare.yml` - exact-build metadata, screenshot upload, and read-only ASC audit
- `asc-release-submit.yml` - protected, attested zero-blocker audit and explicit App Review submission

## Status

Tapt 1.0 is submitted to the App Store. The landing page is live at [taptbeer.com](https://taptbeer.com).

Shipped: auth (email magic link and six-digit code), the scan loop, map, check-ins, the Passport, the honest market engine, leaderboards, newsletter signup, partner tools, and friends. Release-gate tracking lives in the internal docs.
