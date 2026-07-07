# Addendum — Taste Graph, Territory Intelligence & Maps

*The sellable asset is not a user's list of liked beers — it is a live, geo/time-stamped consumption-event panel plus a proprietary SKU taxonomy, wrapped (eventually) in a contracted B2B analytics revenue stream. Untappd Insights and Vivino both monetize exactly this. Build to that shape from record one, and ship the transfer-enabling legal stack at launch — a dense dataset with the wrong consent architecture is legally unsellable.*

---

## 1. Design principle: event-first, not profile-first

Every strategic decision below flows from one rule: **the atomic unit is the check-in event, not the user.** One immutable row per consumption moment. The moat is (a) hard-to-replicate longitudinal *per-market density* and (b) a proprietary canonical SKU/brewery/style taxonomy competitors would have to rebuild. Raw DAU is a vanity metric; acquirers underwrite **data density × exclusivity × contracted recurring B2B revenue × refresh velocity.** Behavioral data decays ~22–28%/yr, so a live check-in flow — not a static dump — is what holds value.

Two hard architectural boundaries make this both sellable *and* legally clean:

- **Personal plane (never sold):** raw check-ins, exact venue, timestamp, friends, personal history — user-controlled. Coarse flavor-tag NLP runs on-device; only anonymized structured tags leave the phone, never raw review text.
- **Aggregate plane (the only thing sold):** server roll-ups keyed by `geo-bucket × style × rolling-window`, gated at query time by k-anonymity (k ≥ 10 distinct users *and* a minimum distinct-venue count), minimum-sample suppression (sparse geos/weeks auto-roll-up), and calibrated differential-privacy noise. Geo always snaps to metro/DMA/ZIP3/H3-hex — never raw lat/long.

---

## 2. Data collected from day one

Instrument the high-value CPG signals most apps skip — **daypart/season, on- vs off-premise, occasion, and pre-purchase intent** — because that attitudinal + occasion + intent layer is precisely what scanner-data buyers (Circana/NIQ) cannot derive from POS and will pay for.

| Field group | Concrete fields | Why it's collected (buyer value / product value) | Consent tier |
|---|---|---|---|
| **Beer identity (canonical)** | `beer_id`, `brewery_id`, `style`, `substyle`, `abv`, `ibu`, `srm`, `sku_canonical_id` | The SKU-mapping taxonomy is itself the moat — it makes our data joinable to CPG systems. | Functional (no sale needed) |
| **Rating & sentiment** | `rating` (0–5), `flavor_tags[]` (hoppy/malty/sour/fruity/roasty…), `aspect_scores` (appearance/aroma/palate/taste ABSA), `review_text` (personal plane only) | Drives recs flywheel + the Flavor Sentiment Score sold per region. | Functional; aggregate sold only de-identified |
| **Geo & venue** | `geo_bucket` (H3/ZIP3/DMA), `venue_id`, `on_off_premise` flag, `region_code` | Per-market density = the #1 valuation lever. On/off-premise split is high-value to distributors. | **Precise location = SPI → affirmative opt-in** |
| **Time** | `event_ts`, derived `day_of_week`, `daypart`, `season` | Daypart/season occasion signals command CPG premiums. | Functional |
| **Occasion / context** | `occasion` (home/bar/restaurant/event/sports), `companions_bucket` | The attitudinal layer POS data lacks. | Functional |
| **Purchase intent** | `saved`, `wishlisted`, `where_to_buy_clicks`, `price_paid`, `price_tier` | Pre-purchase intent — closed-loop "does buzz predict sell-through." | Functional; opt-in if tied to identity resale |
| **Derived user vectors** | `top_styles[]`, `abv_comfort_band`, `ibu_comfort_band`, `novelty_score`, `price_tier_pref` | Powers recs; never sold at individual level. | Personal plane only |
| **Consent metadata (every row)** | `consent_version`, `sale_optin`, `location_optin`, `gpc_flag` | Row-level provenance so the aggregate pipeline can exclude any opted-out user *before* roll-up. | — |

**Suppression list (day one, non-negotiable):** maintain a sensitive-location exclusion set (addiction-treatment/AA sites, medical, reproductive, religious, shelters). Those geopoints are the exact FTC hot-button for an alcohol app and must never enter the aggregate/sellable layer. Truncate/round precision and cap retention.

---

## 3. Maps: "breweries near you" (build native Swift/SwiftUI)

The map is the product's signature surface *and* the live demo that sells the B2B product. Three of its differentiators — dense clustering, a real check-in heatmap, and Apple's Place Card + Look Around wired to our own tap data — are exactly what expo-maps and react-native-maps cannot do today. **This is the decisive input to the Swift-vs-Expo stack decision: go native.** If cross-platform were mandated we'd end up writing a native module wrapping our own `MKMapView` anyway — so there is no cross-platform saving on the one surface that matters most. (This also matches the existing native-Swift/ARKit decision and the "Apple Maps as base, our card+detail as the IP layer" direction already locked for the iOS app.)

**Stack decision → native Swift/SwiftUI, iOS 18 minimum (iOS 26 preferred).** SwiftUI `Map` is the default; drop to a surgical `UIViewRepresentable(MKMapView)` only for the two things SwiftUI still can't do: high-density clustering and the true `MKOverlayRenderer` heatmap.

| Layer | Implementation |
|---|---|
| **Base map** | SwiftUI `Map(position:selection:)` with `.mapStyle(.standard(pointsOfInterest: .including([.brewery,.bar,.nightlife,.winery,.distillery])))` so even Apple's basemap POIs are constrained to beer venues. |
| **Nearby search** | `MKLocalPointsOfInterestRequest(center:radius:)` (≤ 25 km) + POI-category filter — purpose-built for "breweries near me," no natural-language query. `MKLocalSearch.Request` w/ `naturalLanguageQuery` is the search-bar fallback. |
| **Catalog ↔ Apple join** | Persist `MKMapItem.identifier` (iOS 18) on our brewery rows. When we only have address/coords, resolve via GeoToolbox `PlaceDescriptor` + `MKMapItemRequest` (iOS 26); fallback dedupe = proximity (<~30 m) + normalized name. |
| **Ownership split** | Apple owns geometry, hours, photos, Look Around, Place Card. **We** own taplist, styles/IBU, live check-in density, verified-partner flag, offers. |
| **Callout** | Native Place Card via `.mapItemDetailSelectionAccessory(.callout/.sheet)` (iOS 18) for hours/photos/directions, with an injected custom section: current taps, style/IBU chips, live check-in count, and a Look Around thumbnail **gated on a non-nil `MKLookAroundScene`** (coverage is city-limited — degrade gracefully). |
| **Clustering** | SwiftUI Map + an off-main-thread QuadTree pre-clusterer (ClusterMap-style) above a few hundred pins; UIKit escape hatch (`clusteringIdentifier` + `MKMarkerAnnotationView`) if we want Apple's native cluster animation. |
| **Heatmap ("hot now")** | Server pre-aggregates check-ins into H3 cells (H3 computed at the write layer — no `h3-pg` on Supabase, cells stored as `text`, matching house convention). SwiftUI path: one `MapCircle` per hot cell, opacity ∝ density. True-gradient path: UIKit `MKOverlay` + custom `MKOverlayRenderer`. |
| **Performance** | Debounce on `.onMapCameraChange(frequency:.onEnd)`; cache by region tile (Apple rate-limits `MKLocalSearch`); degrade to catalog-only pins when throttled. |

**Deprecations to avoid shipping on:** `CLGeocoder`/`CLPlacemark` (use `MKGeocodingRequest`/`MKReverseGeocodingRequest`) and the pre-iOS-17 `MapAnnotation`/`MapMarker`. Note: our catalog is the source of truth (Apple undercounts small taprooms and miscategorizes them as `.restaurant`/`.bar`); Apple is the enrichment layer, not vice versa.

**Cross-platform verdict (for the record):** `expo-maps` (AppleMaps) is SwiftUI-Map-based, iOS-only, alpha, with no clustering, no custom marker views, and no UIKit escape hatch. `react-native-maps` (`PROVIDER_DEFAULT`) has confirmed New-Architecture/Fabric custom-marker bugs on Apple Maps, does not expose `MKLocalPointsOfInterestRequest` category search, the iOS 18 Place Card, or Look Around, and offers no path to a custom heatmap. Neither reaches the UIKit `MKMapView` layer the flagship map requires.

---

## 4. B2B product — sell the roll-ups the map already computes

Build the aggregation engine once; the consumer maps and the sellable reports are the same pipeline at different privacy gates. Stand this up early — recurring contracted B2B revenue is the single biggest documented multiple-expansion lever at exit; you want to sell an **asset plus a revenue stream.**

- **Tier 1 — Regional Trend Reports** (self-serve dashboard + scheduled exports): style-share, momentum, sentiment by DMA/metro/state on rolling windows. Headline signals like "West Coast IPA check-in share +X% QoQ in Denver."
- **Tier 2 — Competitive & Distribution Intelligence:** over/under-index vs category and named competitors by region; "white-space" maps (high demand, low local supply) for taproom-siting and distribution.
- **Tier 3 — Custom / Clean-Room:** privacy-safe matching of our demand layer against a distributor's depletion or a brand's shipment data inside a data clean room — closed-loop "does regional buzz predict sell-through," no raw PII exposed.

Named, citable indices (always published with sample size *n* and window; sub-threshold cells suppressed): **Style Demand Index** (local share indexed to national = 100), **Momentum** (period-over-period Δ), **Flavor Sentiment Score** (ABSA net positivity per attribute per region), **Local Favorite Rank** (rating × local velocity, PII-safe).

Go dense in **2–4 launch metros** rather than thin nationally — a statistically meaningful single-market panel is more acquirable than shallow national breadth, and it de-risks the buyer's use case. Frame outputs as directional momentum/sentiment (not absolute market share): check-in users skew toward enthusiasts and hype styles, so calibrate against external anchors (Brewers Association production, distributor depletion) in clean-room engagements.

---

## 5. Privacy / consent architecture — the gating asset

The **company sale** (M&A) is the clean path; the **ongoing data sale** is the high-risk one. Both are enabled by the same day-one disclosures. The existential risk is the **FTC** (not the App Store or CCPA): an alcohol app selling precise location sits squarely in the 2024–2026 location-data-broker enforcement lane, and the FTC has *banned* companies from selling sensitive location outright.

**Legal stack shipped at launch (counsel-drafted):**
1. **Privacy Policy business-transfer clause** — personal data may be transferred as a business asset in a merger, acquisition, financing, reorganization, bankruptcy, or asset sale; the successor may continue processing under this policy.
2. **ToS assignment clause** — we may assign the agreement to a successor/acquirer without user consent.
3. **Dual disclosure** — data may be *sold/shared* with third parties for stated commercial purposes **and** *transferred* as an M&A asset. This dual disclosure is what keeps the company sale inside the CCPA business-transfer exemption.
4. **Purpose language** broad enough to cover aggregated/anonymized third-party analytics + data-clean-room use.
5. **Never** an absolute "we will never sell or transfer your data" line — it legally forecloses the exit and cannot be fixed retroactively on a churned user base.

**Consent capture (layered, unbundled, default-OFF):** neutral pre-permission explainer → iOS **When-In-Use** location prompt (request **Always** only with a genuine background feature) → a *separate* opt-in toggle for "share/sell my data with partners" and another for "use my precise location for [named purpose]" → the ATT system prompt with an honest `NSUserTrackingUsageDescription`. Selling to data brokers **is** "tracking" under Apple's definition, so ATT is mandatory; never gate features on ATT or bribe consent (5.1.2(i)).

**Durable consent + opt-out ledger (day one):** timestamped, versioned, per-purpose, storing the exact UI text shown, **exportable** to a buyer, including every CCPA do-not-sell/do-not-share and honored GPC signal. Under **AB 1824 (in force Jan 1 2025)** an acquirer inherits and must honor every pre-close opt-out (penalties $2,500–$7,500/violation) — a clean, exportable ledger is a diligence pass/fail that directly moves the price. (Model it append-only, mirroring the existing CLA-gate/provenance pattern already in the schema.)

**Apple compliance:** age-rate **18+** under the 2025 bands (the old 17+ no longer exists) + first-launch DOB gate (keep the DOB **out** of the saleable dataset). File Privacy Nutrition Labels declaring Location + Preferences/Purchases under **Data Linked to You** *and* **Data Used to Track You**; ship a `PrivacyInfo.xcprivacy` manifest (data types, tracking domains, required-reason APIs); audit every third-party SDK (their tracking is our violation).

**U.S. state law:** publish "Do Not Sell or Share" + "Limit the Use of My Sensitive PI" links, honor **GPC** automatically, classify precise geolocation as SPI, and **assume you are a California data broker** — calendar the Jan 1–31 CPPA registration (~$6,600), wire DROP bulk-deletion (live Aug 1 2026, 45-day cycle), and register in TX/OR/VT too. Run the CCPA risk assessment (required before selling/sharing or processing SPI as of Jan 1 2026).

**GDPR / EU:** selling data and monetizing location need freely-given, unbundled, withdrawable **opt-in** — legitimate interest will not hold; no tracking walls; fire no non-essential SDK before consent. GDPR anonymization must be *irreversible* (a higher bar than CCPA de-identification), and coarse/pseudonymized location often still counts as personal data. **Keep the EU dataset architecturally separable** (`region_code` / `is_eu_user`) so it can be excluded from a data sale a buyer isn't GDPR-comfortable with.

**Default commercial product = aggregated, anonymized layer via reports/dashboards/clean rooms, never raw PII** — the Untappd/Vivino model. It minimizes "sale of personal information" exposure, carries the highest margin, and is the format acquirers actually want.

---

## 6. Who buys, and what to track for the exit

**Three real acquirer classes, all with live rationales:** (1) vertical roll-ups / strategic operators — Next Glass bought Untappd (2016) + BeerAdvocate assets (2020), then took a Providence Strategic Growth investment; the thesis is owning the demand-side dataset + the B2B analytics product. (2) Big Beer / CPG for first-party data — AB InBev's BEES did $52.5B GMV in 2025 with a CDP holding ~100M records; brewery analytics is now competitive weaponry. (3) Loyalty / payments / martech — Mastercard bought SessionM (2019) to add a consumer-engagement data layer. A market-research buyer (Circana / NIQ) is plausible for the complementary attitudinal/occasion layer scanner data can't produce.

**M&A-readiness scorecard, tracked quarterly** (the numbers a Next-Glass- or Circana-type buyer underwrites): (1) check-ins/day + 90-day retention; (2) per-market density in target metros; (3) B2B ARR + logo count; (4) refresh velocity (data decays ~22–28%/yr); (5) consent-ledger completeness (an AB 1824 diligence pass/fail).
