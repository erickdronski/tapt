# Tapt — Founding Concept  *(name locked)*

> Generated from a 3-fleet research program (market, audience, data, monetization, culture, naming, tech + a sellability/M&A/maps/privacy supplement + a 74-source data-sourcing sweep). Raw agent outputs in `docs/RESEARCH-RAW/`.

## The concept
Tapt is a free, global, scan-first beer passport — point your camera at any label, tap list, or barcode and instantly get a personalized, style-fair match score, log the pour to your Cellar, and see what's actually good on tap near you. Every capability the incumbents lock behind a paywall — rating precision, discovery, an ad-free feed, brewery menus — Tapt gives away for life and earns instead on the supply side, so drinkers pay nothing and breweries fund the party.

## Name
- **Recommendation:** Tapt
- **Verified-cleanest ranking:** Tapt, Steiny, Hoply, Brewt, Froth, Suds, Cheerz, Nectar, Clink, Tappr
- **Shortlist w/ tradeoffs:**
- Tapt (low collision risk — verification's cleanest; coined + ownable; lager connotation is a marketing problem, not a legal one)
- Steiny (medium — strongest brand/gamification fit but Steinlager nickname collision; primary fallback)
- Hoply (medium — clearly beer, exact string free, but one letter off live 'Hoppy' app)
- Brewt (medium — invented + ownable, but real 'Brewt's' cocktail-mixer brand in the same channel)

## Stack decision
**Native Swift 6 / SwiftUI (iOS 18+) with a Supabase backend (Postgres + PostGIS + Auth + Storage + Realtime + Edge Functions). No separate app server at MVP.**

Every Tapt differentiator lands exactly where native wins in 2026: label/barcode scanning (the hero) uses VisionKit DataScanner + AVFoundation which ship day-one at WWDC while RN wrappers lag 3–12 months; a fluid image-heavy social feed benefits from SwiftUI + ProMotion 120Hz; premium feel comes from Dynamic Island / Live Activities / haptics; CoreLocation gives precise + background/geofence location and MapKit is free for venue maps; SwiftData handles offline check-ins at tailgates and the back nine. RN's New Architecture closed the CRUD-perf gap but not the platform-integration or polish gap. The account already ships native Swift (Lore, Nalee) with an Apple Developer account and no stated Android deadline, so cross-platform is premature optimization. Critical rule: keep 100% of business logic server-side (Postgres RPCs, RLS, Edge Functions) so a future Kotlin Android client — or RN only if team constraints force it — is a thin view layer over the identical backend. Supabase matches existing Nalee/Lore muscle memory; PostGIS powers 'popular near me' via geography(Point,4326) + GiST index + ST_DWithin/ST_Distance; auth is Sign in with Apple + Google via signInWithIdToken (test the nonce SHA256-hash footgun early); push is a direct APNs .p8 JWT from an Edge Function, no Firebase.

## MVP features (the hero loop first)
- Scan → identify → rate: VisionKit/AVFoundation reads label/barcode/tap-list, fuzzy-matches (pg_trgm) to catalog, manual-search fallback — the hero loop
- Style-normalized + personalized 'predicted-for-you' score — the reason to trust Tapt where Untappd is distrusted
- The Cellar — personal collection + wishlist where every pour is logged
- Log a Pour (check-in) with optional photo, flavor-tag chips, glassware, venue, rating — the atomic action
- Tap List / 'On Near You' — nearby breweries & bars (Foursquare + Apple POI) plus 'popular beers near me' from our own check-ins
- The Passport — styles-explored map + country stamps; breadth-based gamification, never volume
- Curiosity-weighted badges (explorer/style/country) — no ABV, quantity, daily-streak, or morning-drinking badges
- Friends + feed — follow/friend graph where badge unlocks and hauls drive discovery
- No/Low lens — togglable across the whole app; NA & sub-3.5% beers count fully toward the Passport; day-one, not bolted-on
- One-tap import of Untappd/RateBeer personal history (data-portability hook, not scraping their ratings graph)
- Age gate + responsible-drinking design: 17+, declared-age gate, disclaimer
- UGC moderation — all four required at first submission: content filter, report, block-user, published contact

## Later features
- Flights — curated guided tasting quests (IPA Journey, NA All-Stars, Around the Belgian Table); completing one = badge + map progress
- Crew / Live Session — flagship social differentiator: real-time shared group check-in for a tailgate, party, or golf scramble with live leaderboard + photo wall (Untappd has nothing like it)
- On-course mode for golfers — hole/course tagging, combined 'scramble scorecard + beer tally,' offline sync for dead zones
- Brewery Pro portal — verified profile, 'On Tap Now' manager, live check-in analytics, event/release push (the durable revenue engine)
- Sponsored badges, challenges, passports/crawls — platform-run
- Real tap-list ingestion via UTFB/POS partnership (not scraping)
- Where-to-buy / delivery affiliate — commerce garnish, geo-restricted
- Brewery Bingo, bottle-share events, homebrew recipe logging, merch
- Android (native Kotlin) reusing the identical Supabase backend

## Segment hooks
- **College / frat / tailgaters** — Crew / Live Session — a shared party or tailgate check-in with a group leaderboard and photo wall, turning logging into a bonding ritual instead of a solo diary. Retains via friends already on it; churns on any signup/age-wall friction at a party or anything that reads as pushing binge. Lean light lagers, fruity, and NA.
- **Golfers** — On-course mode — hole/course tagging plus a combined 'scramble scorecard + beer tally' for the foursome, with offline check-ins that sync. This is whitespace between beer apps and golf apps (18Birdies tracks games but no beer). Churns without offline support on the back nine.
- **Enthusiasts / tickers / homebrewers** — The Cellar plus a deep, trustworthy, style-fair database — rich collection, rare-release alerts, later homebrew logging. Retention hinges on data completeness and de-dup (bad data is their #1 churn driver); churns on shallow ratings or over-simplification that dilutes their serious tool.
- **Casual social drinkers** — One-tap scan plus 'you liked X, try Y nearby' and a genuinely useful No/Low surface — remember a good beer with zero homework. Retains via frictionlessness and friends' pours; churns on ticker-culture intimidation or feeling judged for drinking little or picking NA.
- **Breweries / taprooms** — Free claimed profile upgrading to a Pro portal — 'On Tap Now,' live check-in analytics, and event/release push to nearby matched drinkers, radically cheaper than Untappd with real data ownership. Retention needs local drinker density (no check-ins = no value); churns on thin density, clunky tooling, or fees a small taproom can't justify.

## Monetization (free to drinkers forever — supply side pays)
- Phase 1 (0–10k MAU/metro): free brewery profiles to build the check-in habit + events/festival ticketing affiliate (Eventbrite/DICE deep-links + promo-code splits) — the cleanest line legally
- Phase 2 (10–50k, flagship): brewery/taproom partnerships — verified profile, 'Featured' placement, self-updated 'On Tap Now'; tiered self-serve ads (~$49–99 Verified, ~$199–299 Premium) priced under Untappd's $1,199/yr
- Phase 2: B2B Pro tier sold only to breweries (~$99–299/mo) — analytics, menu/tap-list mgmt, review-response, campaign manager, competitor benchmarking; the durable, highest-LTV recurring engine
- Phase 3 (50k+): sponsored badges & challenges, platform-run ($299–999/campaign) — proven Untappd revenue line
- Phase 3: alcohol e-commerce/delivery affiliate as garnish, not a pillar (ReserveBar ~4%, Athletic ~3%, Beerwulf 6–12%; Drizly dead, Instacart excludes alcohol, DoorDash/Uber have no public consumer deep-link) — negligible under ~100k MAU
- Phase 3: merch via print-on-demand (breweries sell via profile for a platform cut) — legally cleanest since it's not alcohol
- Compliance rails: 21+ gate before any purchase CTA; TTB mandatory-statement link allowance; keep manufacturer $ and retailer $ in separate lanes (tied-house 'thing of value' is the biggest legal risk); geo-suppress commerce in ban states (Utah, Delaware) + dry counties; FTC affiliate disclosure

## Brand
**Voice:** The knowledgeable friend at the bar who's genuinely thrilled you're curious — never the snob quizzing you. Fun, warm, worldly, a little witty. Frat-friendly (playful, group energy) but never frat-exclusive (never crude, never 'bro,' never gatekeeping). Celebrates curiosity over capacity — hypes trying something new, not drinking a lot. Global by default, NA drinkers first-class. Two register levels: plain-language default with a toggle-on 'Beer-geek mode' that swaps in the lexicon (Tick a Pour, The Cellar, Whales, Haul). Sample microcopy: empty state 'Your Cellar's looking thirsty'; NA lens 'Big flavor, zero proof. These count just as much.'

**Palette:**
- #F2A900 Pour Gold — primary brand core (lager/pilsner gold), CTAs, active states, stein/passport progress fill
- #1A1206 Malt Black — text, dark surfaces, premium roasty backdrop
- #FBF6EC Foam — warm off-white background (the head on a pour, not clinical white)
- #3F8F5B Fresh Hop — the No/Low lens, 'fresh on tap,' success states; signals inclusivity not IPA
- #B4531F Copper Ale — amber/dark-style accents, whales/rare finds, celebration moments
- #6B6459 Slate — secondary text, dividers, disabled states

**Type direction:** Display/wordmark: friendly, slightly-rounded geometric sans with warmth and confidence (Poppins/General-Sans register) — approachable and global-legible, never craft-blackletter cliché. Body/UI: clean neutral sans (Inter-class) for scannable feeds and dense beer data. Pick faces with clear tabular figures — ratings, ABV, IBU, and country counts are everywhere.

**Logo concept:** A stein/pint silhouette whose foam head doubles as a passport stamp / location pin — one mark fusing the three pillars (a beer, a place, a journey). Pour Gold on Foam; the foam-line animates as the app's progress/fill motif (Passport filling, badge unlocking). Simple enough at 60×60 app-icon size, distinctive enough to own. A secondary 'stamp' glyph (the foam-pin alone) serves as the check-in/achievement mark.

## Data sources (headline)
- Foursquare OS Places (100M+ POIs, Apache 2.0 — owned & warehoused, no per-call fees) for the bar/brewery POI layer
- Open Brewery DB (free, no key, effectively public-domain) for brewery-specific enrichment
- Open Food Facts (barcode → beer + brand + label image, ODbL + CC-BY-SA — attribute & segregate) to seed the beer catalog and scan-to-add
- Punk API community rehost (415 beers) for demo/seed polish only
- First-party user check-ins — the ONLY compliant source of 'popular beers near me': (venue from Foursquare/Apple POI) + (beer from our catalog) + (rating from our users), ranked by recent check-in count × recency-decay × avg rating within ST_DWithin
- Apple MapKit (free, iOS-native) and Google Places (place_id only — no caching) for live venue enrichment/verification only, never warehoused
- Cold-start bootstrap: editorial staff-picks / style-default empty states + first-check-in incentives + metro-by-metro density seeding (campus, golf club, brewery cluster); NOT importing Untappd ratings (ToS violation + poisons provenance)

## Top risks
- Cold-start / network effects (dominant execution risk): POI + catalog + images seed the map but 'popular near me' starts at zero ratings and looks empty until local density exists — only metro-by-metro growth + first-check-in incentives fix it, not the data plan
- Two-sided chicken-and-egg on revenue: brewery partnerships and Pro both need pre-existing density to sell, so revenue is back-loaded and runway must cover a long free period (~10k MAU/metro before there's anything to monetize)
- Apple rejection under 1.4.3 (any purchase/order flow or 'encourages excessive consumption' read) and 1.2 (must ship filter+report+block+contact at first submission — the most likely non-alcohol rejection reason for a social app)
- Rating credibility cuts both ways: the style-normalized score is the moat but if it feels gameable or like a black box it inherits Untappd's exact distrust, and breweries fear low scores tanking sales — keep it explainable + add location plausibility checks
- Big-beer / incumbent retaliation: AB InBev killed RateBeer; Next Glass owns Untappd AND BeerAdvocate and could clone a free tier or cut business pricing — the moat must be trust + UX + commerce rails, not just 'free'
- Mindful-drinking trend cuts both ways: the NA wave that widens the TAM also shrinks the heavy-check-in, high-commission core — design for breadth and NA-first, not the shrinking hardcore ticker base
- Commerce is regulated and thin: alcohol e-commerce is a state-by-state patchwork (three-tier, DTC bans, age verification) and affiliate rates are low, so 'global + commission' earns nothing until conversion happens and 'global' multiplies the legal burden — treat commerce as a deliberate, geo-restricted, later decision
- Beer-identity de-dup is genuinely hard: if the same beer splits across 5 spellings it never trends and the hero feature silently dies — budget real engineering + a human merge queue with barcode/GTIN as the strongest key
