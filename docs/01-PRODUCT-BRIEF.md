# Tapt — Product Brief

**The Beer Superapp. A free, global, scan-first beer passport. Untappd's fun, without the tax.**

---

## 1. Hero Concept

**Tapt is The Beer Superapp: a free, global, scan-first beer passport where you point your camera at any label, tap list, or barcode and instantly get a personalized, style-fair match score, log the pour to your Cellar, play beer-night games, and see what's actually good near you.** Every capability the incumbents lock behind a paywall — rating precision, discovery, an ad-free feed, venue menus — Tapt gives away for life and earns instead on the supply side, so drinkers pay nothing and breweries, pubs, bars, taprooms, beer gardens, and events fund the party.

One-line pitch: **Vivino's scan-and-go, rebuilt for beer, on data we own — trustworthy where Untappd is distrusted, generous where it gouges, and global and no/low-first where it's defensive.**

---

## 2. The Wedge (why this wins now)

- **RateBeer is dead** (AB InBev shut it Feb 2025). **BeerAdvocate** is consolidated under Untappd's parent (Next Glass) and stagnant — the encyclopedic niche is depleted and its users are loose.
- **Untappd** is 2.3/5 on Trustpilot: ad-heavy, buggy, paywalls precision (Insiders $5.99/mo), doubled business price to $1,199/yr with no grandfathering, and made a resented late-2025 land-grab beyond beer. Its ratings are structurally distrusted — raters are <1% of drinkers who 1-star beers for being the *wrong style*.
- **Vivino** proved the model (70M downloads, 2.7B scans, ~$489M GMV, ~15% take) but only for wine.
- Long-tail apps each do **one** job (BeerMenus = tap lists, Tavour = drops, Pintley = taste recs). **No single app unifies trustworthy taste-match + discovery + where-to-get-it + purchase, for free, globally.** That gap is the wedge.

---

## 3. Name

**Recommendation: `Tapt`** — the cleanest name in verification (the only "low" collision risk in the set: no app, brewery, brand, or trademark hit). Coined, ownable, warm, beer-evocative, easy worldwide. The one caveat — "pils" leans lager — is a *marketing* problem, not a legal one, solved by style-neutral positioning ("your whole beer world, one passport"). Clean clearance means fastest, safest path to an App Store title and a filed mark.

### Shortlist (ranked by verification cleanliness)

| Name | Risk | Why it's on the list / caveat |
|---|---|---|
| **Tapt** | Low | Cleanest overall; coined + ownable. Neutralize the lager read in brand copy. |
| **Steiny** | Medium | Best *brand* fit — style-neutral, stein = native gamification currency. Caveat: Steinlager nickname; avoid Steinlager-adjacent visuals. **Primary fallback.** |
| **Hoply** | Medium | Clearly beer (hops), exact string free. Caveat: one letter off live "Hoppy"; distance it. |
| **Brewt** | Medium | Invented, ownable. Caveat: real "Brewt's" cocktail-mixer brand in the same channel. |

**Dropped** (high risk): Clink, Tappr, Nectar, Pinta, Cheerz, Froth, Suds.

> **Before commit:** formal USPTO/EUIPO clearance (Nice classes 9 + 42) + domain checks (`tapt.app`, `tapt.com`, `getpilsy.com`).

---

## 4. Tech Stack

**Recommendation: native Swift 6 / SwiftUI (iOS 18+), Supabase backend.** No separate app server at MVP.

### Swift vs Expo

Every differentiator lands where native wins in 2026, and the account already ships native Swift (Lore, Nalee) with an Apple Developer account and **no Android deadline** — so cross-platform is premature optimization.

| Differentiator | Why native Swift wins |
|---|---|
| **Label / barcode scan** (hero) | VisionKit DataScanner + AVFoundation ship day-one at WWDC; RN wrappers lag 3–12 months. Decisive. |
| **Fluid social feed** | SwiftUI + ProMotion 120Hz on image-heavy lists. |
| **Premium feel** | Dynamic Island, Live Activities ("friends out now"), haptics. |
| **Location** | CoreLocation precise + geofence; MapKit (free) maps. |
| **Offline** | SwiftData local queue for the tailgate / back nine. |

RN's New Architecture closed the *CRUD-perf* gap, not the *platform/polish* gap. **Rule: keep 100% of business logic server-side (Postgres RPCs, RLS, Edge Functions) so a future Kotlin Android client — or RN only if forced — is a thin view layer over the identical backend.**

### Backend

- **Supabase** (Postgres + **PostGIS** + Auth + Storage + Realtime + Edge Functions) — Nalee/Lore muscle memory.
- **Auth**: Sign in with Apple + Google via `signInWithIdToken`. *Footgun to test early:* Apple needs the **SHA256 hash** of the nonce in the request; the **raw** nonce goes to Supabase.
- **Geo / "popular near me"**: `geography(Point,4326)` + GiST index; a `SECURITY DEFINER` RPC using `ST_DWithin` + `ST_Distance`, joined to a recent check-in count, ranked by `recent_checkins × recency-decay × avg_rating`.
- **Push**: APNs `.p8` JWT direct from an Edge Function on DB webhook — no Firebase.
- **Storage**: private bucket, RLS keyed to `auth.uid()`; on-device HEIC→JPEG compression; signed-URL thumbnails.

---

## 5. The Trust Fix (the moat)

Untappd's deepest flaw is a score nobody believes — a Kölsch punished against Double IPAs. Tapt's core differentiator:

- **Style-normalized score** — rate each beer *relative to its own style*.
- **Predicted-for-YOU match** — a flavor graph + taste model surfaces "you'll probably love this."
- **Untappd structurally cannot retrofit this** without invalidating 15 years of legacy numbers.

Guardrail: keep it explainable ("we normalized within *Pilsner*"), never a black box, or it inherits the exact distrust it's meant to solve.

---

## 6. MVP Feature Set (ruthlessly scoped)

| # | Feature | Notes |
|---|---|---|
| 1 | **Scan → identify → rate** | VisionKit/AVFoundation; `pg_trgm` fuzzy-match; manual fallback. The hero. |
| 2 | **Style-fair + personalized score** | The reason to trust Tapt. |
| 3 | **The Cellar** | Personal collection / wishlist. |
| 4 | **Log a Pour (check-in)** | Photo, flavor-tag chips, glassware, venue, rating. |
| 5 | **Tap List — "On Near You"** | Nearby POI (Foursquare + Apple) + popular beers from **our own** check-ins. |
| 6 | **The Passport** | Styles-explored map + **country stamps**. Breadth, never volume. |
| 7 | **Curiosity-weighted badges** | **No ABV / quantity / daily-streak / morning badges.** |
| 8 | **Friends + feed** | Follow + friend graph; badge unlocks drive discovery. |
| 9 | **No/Low lens** | App-wide toggle; NA & sub-3.5% count fully. Day-one, not bolted-on. |
| 10 | **Import my history** | One-tap Untappd/RateBeer *personal* history (portability, not scraping). |
| 11 | **Age gate + responsible design** | 17+, declared-age gate, disclaimer. |
| 12 | **UGC moderation (all four)** | Filter + report + block + contact. **Mandatory at first submission.** |

**NOT in MVP:** any buy/order/delivery button (Apple 1.4.3), venue tap-list ingestion, homebrew logging, brewery Pro portal, sponsored badges, merch, Android.

---

## 7. Later Features (post-PMF, sequenced)

1. **Flights** — curated guided tasting quests; completing one = badge + map progress.
2. **Crew / Live Session** — flagship social differentiator: real-time shared group check-in for a tailgate, party, or scramble with live leaderboard + photo wall.
3. **On-course mode** — hole/course tagging, "scramble scorecard + beer tally," offline sync.
4. **Brewery Pro portal** — verified profile, "On Tap Now," live analytics, event/release push. Durable revenue engine.
5. **Sponsored badges, challenges, passports/crawls** — platform-run.
6. **Real tap-list ingestion** via UTFB/POS *partnership*, not scraping.
7. **Where-to-buy / delivery affiliate** — commerce garnish.
8. **Brewery Bingo, bottle-share events, homebrew logging, merch.**
9. **Android** (native Kotlin) on the identical backend.

---

## 8. Per-Segment Hooks

| Segment | Killer hook | Retains / churns |
|---|---|---|
| **College / frat / tailgaters** | **Crew / Live Session** — shared party check-in with group leaderboard + photo wall; logging becomes a bonding ritual. | Retains: friends on it. Churns: signup/age-wall friction at a party; anything that reads as pushing binge. Lean light lagers, fruity, NA. |
| **Golfers** | **On-course mode** — hole/course tagging + "scramble scorecard + beer tally"; offline sync. Whitespace vs golf apps (18Birdies tracks games, not beer). | Churns without back-nine offline support. |
| **Enthusiasts / tickers / homebrewers** | **The Cellar + a deep, trustworthy DB** — style-fair scores, rare-release alerts, later homebrew logging. | Retains: data completeness + de-dup. Churns: shallow ratings; over-simplification. |
| **Casual drinkers** | **One-tap scan + "you liked X, try Y nearby"** + a real No/Low surface. Zero homework. | Retains: frictionlessness + friends' pours. Churns: ticker intimidation; feeling judged for NA. |
| **Breweries / taprooms** | **Free profile → Pro portal**: "On Tap Now," live analytics, event push to nearby matched drinkers — cheaper than Untappd, real data ownership. | Retains: local density. Churns: thin density, clunky tooling, fees. |

**Connective tissue:** friends graph + shared occasions. Enthusiasts build the trustworthy DB; casual/students consume recs via friends and Crew; golfers/tailgaters generate group occasions; breweries convert demand into events — closing the loop that funds "free."

---

## 9. Data: "Popular Beers Near Me" + Cold Start

**Non-negotiable truth: no compliant third-party API sells you "top beers pouring near this venue."** Untappd's API *forbids* the use case (Terms 5/13/14/15) and rate-limits it (100/hr). Google Places bans caching anything but `place_id`. **The hero metric must be a derived signal over first-party data we own.**

### How "popular near me" is powered

`(venue from Foursquare/Apple POI) + (beer from our catalog) + (rating from OUR users)`, ranked by
`recent check-in count × recency-decay × avg rating` within `ST_DWithin(location, radius)` — Untappd's mechanic rebuilt on data we own, zero ToS exposure.

### Cold-start in three moves

| Layer | Source | License / note |
|---|---|---|
| **POI (bars/breweries)** | **Foursquare OS Places** (100M+) + **Open Brewery DB** | **Apache 2.0** — owned & warehoused, no per-call fees. OBDB effectively public-domain. |
| **Beer catalog + labels** | **Open Food Facts** (barcode → beer + image) + **Punk API** (415-beer demo) | ODbL + CC-BY-SA — **attribute + segregate** so share-alike doesn't infect proprietary tables. |
| **Ratings** | **Start at zero — bootstrap it.** | Editorial "staff picks" empty states; incentivize first check-ins; seed density **metro-by-metro** (campus, golf club, brewery cluster). |

**Hard rules:** never persist Google content except `place_id`; never build a catalog from Untappd's API; keep provenance IDs (`fsq_id`, `obdb_id`, `off_barcode`, `google_place_id`); barcode/GTIN is the strongest natural key; budget engineering + a human merge queue for **beer-identity de-dup** — split spellings never trend and the hero feature silently dies.

**Live enrichment only** (never warehoused): Google Places / Apple MapKit for on-demand verification.

---

## 10. Monetization — free to users, forever

**Users never pay. Every dollar is supply-side.** Copy Vivino (monetize commerce), invert Untappd (don't paywall the community). Sequenced against density — the two best lines only sell once density exists.

| Phase | Line | Mechanics | Activates at |
|---|---|---|---|
| **1 (0–10k MAU/metro)** | Free profiles + **events ticketing affiliate** | Profiles build the check-in habit; in-app festival calendar with "Get Tickets" deep-links + promo-code splits. Cleanest legally. | Day one. |
| **2 (10–50k)** | **Brewery partnerships** (flagship) + **Pro tier** | Verified/"Featured"/self-updated "On Tap Now"; tiered ads (~$49–99 / ~$199–299) **under Untappd's $1,199/yr**. Pro adds analytics + menu mgmt (~$99–299/mo). | ~5k–25k MAU/metro. |
| **3 (50k+)** | **Sponsored badges** → **merch** + **affiliate** | Platform-run badges ($299–999/campaign). Affiliate ("Buy / Find delivery") is **garnish, not a pillar.** | Post-50k; affiliate negligible <100k. |

**Affiliate reality:** Drizly dead; Instacart excludes alcohol; DoorDash/Uber have no public deep-link. Only low-rate e-commerce pays (ReserveBar ~4%, Athletic ~3%, Beerwulf 6–12%). Volume play, never the main course.

**Compliance rulebook (day one):** 21+ gate before any purchase CTA · TTB mandatory-statement link allowance · **manufacturer $ and retailer $ in separate lanes** — neutral published-rate placement, never pay-to-bury (tied-house "thing of value" is the biggest legal risk) · geo-suppress commerce in ban states (Utah, Delaware) + dry counties · FTC disclosure.

---

## 11. Brand Direction

**Voice — the knowledgeable friend at the bar who's genuinely thrilled you're curious, never the snob quizzing you.** Fun, warm, worldly, a little witty. Frat-*friendly* but never frat-*exclusive* (never crude, never "bro," never gatekeeping). Celebrate **curiosity over capacity**. Global by default; NA drinkers first-class. Two registers: plain-language default with a toggle-on **"Beer-geek mode"** (Tick a Pour, The Cellar, Whales, Haul).

*Microcopy:* empty state → *"Your Cellar's looking thirsty."* · NA lens → *"Big flavor, zero proof. These count just as much."* · badge → *"New stamp! Beers from 12 countries. Where next?"*

### Palette

| Role | Hex | Use |
|---|---|---|
| **Pour Gold** (primary) | `#F2A900` | Brand core; CTAs, active states, stein/passport fill. |
| **Malt Black** (ink) | `#1A1206` | Text, dark surfaces, roasty backdrop. |
| **Foam** (surface) | `#FBF6EC` | Warm off-white background — the head on a pour. |
| **Fresh Hop** (secondary) | `#3F8F5B` | The No/Low lens, "fresh on tap," success. |
| **Copper Ale** (accent) | `#B4531F` | Amber accents, whales/rare finds, celebration. |
| **Slate** (muted) | `#6B6459` | Secondary text, dividers, disabled. |

Warm and appetizing — deliberately **not** the cold blue-grey of a data app.

### Type direction

- **Display / wordmark:** friendly, slightly-rounded geometric sans (Poppins / General-Sans register) — approachable, global-legible, no craft-blackletter cliché.
- **Body / UI:** clean neutral sans (Inter-class) for scannable feeds and dense beer data.
- **Numerals matter:** ratings, ABV, IBU, country counts everywhere — clear tabular figures.

### Logo concept

A **stein/pint silhouette whose foam head doubles as a passport stamp / location pin** — one mark fusing the three pillars (a beer, a place, a journey). Pour Gold on Foam; the foam-line animates as the app's progress/fill motif. Reads at 60×60 app-icon size, distinctive enough to own. A secondary "stamp" glyph (foam-pin alone) is the check-in/achievement mark.

---

## 12. Top Risks

1. **Cold-start / network effects (dominant).** POI + catalog + images seed the map, but "popular near me" starts at **zero ratings** and looks empty until density exists. Only metro-by-metro growth + first-check-in incentives fix it.
2. **Two-sided chicken-and-egg on revenue.** Partnerships and Pro both need pre-existing density; revenue is back-loaded — runway must cover a long free period.
3. **Apple rejection (1.4.3 + 1.2).** No purchase flow / "excessive consumption" read; ship social/logging-only + all four UGC-moderation pieces at first submission.
4. **Rating credibility cuts both ways.** The style-normalized score is the moat but must stay explainable and hard to game (location plausibility checks); breweries fear low scores.
5. **Big-beer / incumbent retaliation.** AB InBev killed RateBeer; Next Glass owns Untappd *and* BeerAdvocate. Moat = trust + UX + commerce rails, not just "free."
6. **Mindful-drinking trend cuts both ways.** The NA wave widens the TAM but shrinks the heavy-check-in core — design for breadth and NA-first.
7. **Commerce is regulated and thin.** State-by-state patchwork + low affiliate rates; treat commerce as a deliberate, geo-restricted, later decision.

---

*Weave check: this brief runs on the beer's own language — the **Passport** and its **stamps**, the **Cellar**, logging a **Pour** or a **Tick**, the **Tap List** and "**On Tap Now**," **Flights** as guided quests, **Whales** for rare finds, a **Haul**, **Crew** sessions, and "**kick the keg**." The vocabulary is the product's native tongue, not decoration.*
