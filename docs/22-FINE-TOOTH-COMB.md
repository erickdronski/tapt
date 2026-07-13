# Fine-tooth-comb master punch list (fleet wf_88fb4104, 2026-07-13)

Owner directive: the whole app has to be kickass, the leaderboard must make sense, beers per state and country must make sense.

How to read this: 128 deduplicated findings from 14 audit lenses over the repo AND the live database. Adversarial verification confirmed 7 of the top items before the overnight session cap; the rest carry finder evidence (file:line + live query output) and were re-checked by hand where fixed. Status reflects the state AFTER migrations 0069-0081, PR #45, and the July 13 fix round.

| Severity | Fixed this round | Still open |
| --- | --- | --- |
| P0 | 30 | 5 |
| P1 | 6 | 50 |
| P2 | 0 | 37 |


## P0

### [FIXED this round] Every US state board is empty and silently swaps in the Global feed under state-attributed headers
*Surface:* Explore state boards (all 50 US states)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:452`  ·  *Found by:* fleet

A user who taps New Jersey, California, Texas, or Wyoming sees a board headed 'Top in New Jersey' with a movers rail 'Biggest movers in New Jersey' and a hero reading '<brewery> is climbing in New Jersey.' None of it is state data: live query proves all 50 state region keys have ZERO rows in beer_trend_feed, so load() falls back to the Global feed while the section headers and hero subtitle keep the state name. With today's live data the hero beer on every state board is 'La saison du chasseur' - a French saison with exactly one vote from one user - presented as 'climbing in Wyoming'. The only disclosure is a small hero caption ('New Jersey guide + Global radar'). This is fabricated regional attribution on the app's first screen.

**Evidence:** Live: SELECT region,count(*) FROM beer_trend_feed for all 50 picker state names -> every state = 0 rows (Georgia = 1, see separate finding). beer_trend has only 2 rows total ('CA' and 'Global', both the French beer, popularity 1 / momentum 1), so the Global fallback list contains a nonzero row -> hasMarketActivity=true -> ExploreView.swift:320 renders 'Top in \(region)', :279 'Biggest movers in \(region)', :118 '\($0.brewery) is climbing in \(region).'. Fallback swap at :452-454. The 0016 fallback view only emits regions from brewery.country ('United States'), never state names, so state boards can never fill.

**Fix:** Stop attributing global data to a state. In load(), when the regional fetch is empty, keep the Global list but switch every region-labeled string to Global copy: header 'Explore worldwide beers', movers 'Biggest movers worldwide', hero '... is climbing worldwide', plus a first-class empty-state line 'No New Jersey beers on Tapt yet - your vote or check-in starts this board.' Longer term, populate state boards honestly by extending the 0016 fallback lateral to also emit (br.external_ids->>'region') as a region when br.country='United States' and that key is non-null, and ingest state-attributed US beers (only 16 exist today, so the copy fix is the launch-blocking part).

### [FIXED this round] US-state Georgia board shows a beer from the country Georgia (Caucasus)
*Surface:* Explore state board: Georgia  ·  *Anchor:* `supabase/migrations/0016_trend_feed_catalog_fallback.sql:22`  ·  *Found by:* fleet

Tapping the 'Georgia' chip (a US state, listed in BeerRegions.states) returns exactly one beer: 'Black Lion Craft Beer' by GBC (Georgian Beer Company), country = Georgia the country. Because the row exists, the app does NOT fall back to Global - a Georgia (US) user sees a single Caucasus beer under 'Explore beers from Georgia'. The fallback view keys regions by brewery.country, and the country name 'Georgia' collides with the state chip. Any future country/state name collision does the same.

**Evidence:** Live: SELECT * FROM beer_trend_feed WHERE region='Georgia' -> [{name:'Black Lion Craft Beer', brewery_name:'GBC', country:'Georgia', popularity:0, momentum:0}]. Picker source app/Tapt/Core/BeerModels.swift:50-61 lists 'Georgia' as a US state. View def (live) fallback branch: r.region = COALESCE(NULLIF(br.country,''),'Global').

**Fix:** Namespace the two axes so they can never collide: in the feed view emit country fallback rows under a key that the state picker never sends (e.g. keep country names but have the app query states via a separate 'state' column, or prefix state regions 'US-<State>' end to end - view, refresh_beer_trend, and BeerService). Minimal immediate patch: exclude country names that match US state names from the fallback branch ('Georgia' is the only live collision today) so the state chip gets the honest empty state instead of a foreign beer.

### [FIXED round 2] Placeholder and scrape-junk beer names pass the name gate onto live boards
*Surface:* Explore country boards (Belgium, Germany, Japan)  ·  *Anchor:* `supabase/migrations/0048_names_style_science_market_momentum.sql:5`  ·  *Found by:* fleet

The Belgium board contains a 'beer' literally named 'Chargement…' (French for 'Loading…' - a scraped placeholder string) and one named 'Belgium' (by Stella Artois). The Germany board contains 'Erdinger Brauhaus Helles 2,19 € 4,38 € pro zzgl. Pfand 0.08€' (a shelf-price + bottle-deposit string) and '2,5 Original Lemon'. Japan shows 'Sapporo @ chiller' and 'Asahi draft super dry beer ~ 68. Platinum 72075'. Belgium also has mangled fragments 'de 12 de Leffe blonde de' and 'de 4 Chimay'. These are lorem-grade placeholder/scrape artifacts on user-visible boards - an automatic P0 under the zero-placeholder law.

**Evidence:** Live top-40 queries on beer_trend_feed (name column is already COALESCE(display_name,name), i.e. exactly what users see): region='Belgium' -> 'Chargement…' (brewery 'Belgian'), 'Belgium' (Stella Artois), 'de 12 de Leffe blonde de'; region='Germany' -> 'Erdinger Brauhaus Helles 2,19 € 4,38 € pro zzgl. Pfand 0.08€', '2,5 Original Lemon'; region='Japan' -> 'Sapporo @ chiller', 'Asahi draft super dry beer ~ 68. Platinum 72075'. tapt_name_ok (0048:5-10) only requires 3 alpha chars, non-bare-style-word, no 'unknown' - all of these pass.

**Fix:** Harden tapt_name_ok in a new migration: reject names containing currency symbols or price patterns ([€$£]|\d+[.,]\d{2}\s*€), deposit/Pfand strings, loading placeholders (chargement|loading|cargando), names equal to a country name, names starting or ending with dangling stopwords (^de\s|\sde$), and leading quantity fragments (^\d+[.,]\d+\s). Then re-run the name_ok backfill and spot-check the four boards above. Keep the law: hide, never rewrite into invented names.

### [FIXED this round] Six functions beyond the allowed four are executable by anon, including clean_beer_name whose 0067 revoke did not take effect
*Surface:* Anon SQL surface (backend contract)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:194`  ·  *Found by:* fleet

The anon surface is contractually locked to exactly catalog_search, venue_brand, venue_events, venue_menu. Live pg_proc/ACL query shows anon can additionally execute: match_beers(text,integer) and region_guide_feed() (explicit 'anon=X' grants from migrations 0004/0005 and 0007), plus clean_beer_name(text), tapt_display_name(text), tapt_name_ok(text), tapt_ref_style_name(text,text) via the default PUBLIC execute grant ('=X/postgres'). All return RPC-exposable types, so any unauthenticated caller can POST /rest/v1/rpc/<fn>. Migration 0067's P0-18 loop only ran 'revoke execute ... from anon' on clean_beer_name; the PUBLIC grant remains, so anon still inherits execute — the fix shipped today is ineffective.

**Evidence:** Live: has_function_privilege('anon', oid, 'execute') over non-extension public functions returns 11 rows: catalog_search, venue_brand, venue_events, venue_menu (allowed) + clean_beer_name, match_beers, region_guide_feed, tapt_display_name, tapt_name_ok, tapt_ref_style_name (violations; set_updated_at is trigger-typed, not RPC-callable). ACLs: clean_beer_name = {=X/postgres,postgres=X,authenticated=X,service_role=X} — no anon entry but PUBLIC ('=X') remains; match_beers and region_guide_feed carry explicit anon=X/postgres. Grants originate at 0004:71 / 0005:76 ('grant execute on function match_beers(text,int) to anon, authenticated') and 0007:785 ('grant execute on function region_guide_feed() to anon, authenticated').

**Fix:** One migration: for each of the six functions run 'revoke execute on function <sig> from public, anon;' (revoking PUBLIC is the part 0067 missed), keep 'grant execute ... to authenticated' only where the app actually calls them, then re-verify live with the has_function_privilege query and add that query's expected 4-row result as a standing assertion (AGENTS.md check or CI script) so future function creations with default PUBLIC grants get caught.

### [FIXED this round] Market rows carry country-of-sale or junk provenance as the beer's country; the per-name dedup actively picks the wrong-country twin
*Surface:* Beer Market board + detail (country tag)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:129`  ·  *Found by:* fleet

The detail sheet's globe tag shows brewery.country, which for OFF-ingested rows is where the product was scanned, not origin. On today's default top-40: Singha shows 'Australia' (it is Boon Rawd, Thailand — the catalog's own correct Thailand row loses the dedup because the Australia row has a cutout), Stone IPA shows 'Germany' (a US row exists and loses), Sapporo shows brewery 'Flasche' ('bottle' in German) in France, Birra Moretti/Bavaria/Amstel Radler/Grimbergen all show France. 39 of the top 100 rows claim France. A real user opening Singha or Stone IPA sees a country the beer has no origin connection to, and the database itself contains the correct rows, so this is provably wrong, not merely unverifiable.

**Evidence:** beer_market('movers',40): SING/Singha country=Australia, STON/Stone IPA country=Germany, SAPP/Sapporo brewery=Flasche country=France, BIRR/Birra Moretti country=France, BAVA/Bavaria country=France. Catalog query: a second 'Singha' row has brewery=Boon Rawd country=Thailand (no cutout, loses distinct-on to the cutout row at standing 64); a second 'Stone IPA' row is United States; a Moretti/Italy row exists. Top-100 aggregate: 39/100 rows country='France'. Country renders at app/Tapt/Features/Market/MarketBeerDetailView.swift:169-172 (tag(country, "globe")).

**Fix:** Stop treating OFF brewery.country as origin on the market surface: in refresh_beer_market_standing, when multiple name_ok rows share a display name, prefer the row whose brewery/country is the cluster's modal (most frequent) value rather than whichever has a cutout, and null out the country when the cluster disagrees (blank beats invented — the app already hides empty country at MarketBeerDetailView contextCard). For the shipped board, a small curated origin table for the ~100 recognizable brands (Singha=Thailand, Sapporo=Japan, Moretti=Italy, etc.) that overrides brewery.country at refresh is a cheap honest stopgap.

### [FIXED this round] Anon can execute match_beers and region_guide_feed (plus 4 helper fns) - surface is not locked to the 4 allowed functions
*Surface:* Anon SQL surface (catalog search backend)  ·  *Anchor:* `supabase/migrations/0061_shrink_anon_rpc_surface.sql:11`  ·  *Found by:* fleet

Product law 4 locks the anon RPC surface to exactly catalog_search, venue_brand, venue_events, venue_menu. Verified live AFTER migration 0078: match_beers, region_guide_feed, clean_beer_name, tapt_display_name, tapt_name_ok, tapt_ref_style_name are all still anon-executable. match_beers (SECURITY INVOKER) selects from beer_catalog + brewery, both of which have public-read RLS policies and anon table SELECT, so any holder of the shipped anon key gets real rows back - including raw bc.name (it bypasses the tapt_name_ok gate and display_name normalization, so it serves exactly the junk names the catalog hides). region_guide_feed returns the full region_beer_guide table to anon. Migration 0061's revoke list simply missed them (they were granted to anon in 0004:71 and 0007:785). docs/21 P0-18 only tracked clean_beer_name and it is still not revoked either, despite P0s being marked done.

**Evidence:** Live pg_proc query post-0078: match_beers anon_exec=true, region_guide_feed anon_exec=true, clean_beer_name anon_exec=true, tapt_display_name/tapt_name_ok/tapt_ref_style_name anon_exec=true. beer_catalog policy read_beer applies to public with anon SELECT granted; region_beer_guide has region_beer_guide_public_read for anon,authenticated. match_beers def: 'select b.id, b.name, ... from beer_catalog b left join brewery br ...' with no name_ok filter. Grants originate in 0004_product_auth_privacy_foundations.sql:71 and 0007_backend_contract_and_content_pipeline.sql:785; 0061's foreach array omits all of them.

**Fix:** New migration mirroring 0061's pattern: revoke execute on public.match_beers(text,int), public.region_guide_feed(), public.clean_beer_name(text), public.tapt_display_name(text), public.tapt_name_ok(text), public.tapt_ref_style_name(text,text) from anon (keep authenticated - the app's CheckinService.swift:117 calls match_beers signed-in). Then update the AGENTS.md locked-anon list and re-verify with the same pg_proc + has_function_privilege query; also add that query as a CI/audit check so future migrations can't silently widen the surface.

### [FIXED round 2] Retail shelf strings with EUR deposit pricing and raw barcodes pass tapt_name_ok and render as beer names
*Surface:* Catalog search results + beer page titles  ·  *Anchor:* `supabase/migrations/0064_beer_name_normalize_v3_retail_strings.sql:51`  ·  *Found by:* fleet

Searching 'guinness' (top-30, an obvious first query) shows a beer named 'ALDI Guinness Draught Irisches Bier Zzgl. Pfand 4 x 0.25EUR = 1.00EUR Packung 2.84EUR' and another named 'Guinness Extra Stout 4053400211428 Schankbier Stout' (a 13-digit GTIN inside the name). These names also become the beer page navigation title and header if tapped. 9 such rows pass name_ok live (others include 'Erdinger Brauhaus Helles 2,19 EUR 4,38 EUR pro zzgl. Pfand 0.08EUR' and a Stoertebeker row carrying a full price breakdown). Product law 3 explicitly bans price fragments as names; this is the exact junk the v3 normalizer + name gate exist to stop, and these slip through because the gate has no currency/deposit ('Zzgl. Pfand', 'EUR', 'Basispreis', 'Packung') or long-digit-run patterns.

**Evidence:** Live: select ... from catalog_search('guinness',...) returned 'ALDI Guinness Draught Irisches Bier Zzgl. Pfand 4 x 0.25EUR = 1.00EUR Packung 2.84EUR' (brewery 'ALDI Guinness', Germany) and 'Guinness Extra Stout 4053400211428 Schankbier Stout' in the top 30. select ... where name_ok and (display_name ~ '[0-9]{7,}' or ilike '%zzgl%' or like '%EUR%' or ilike '%pfand%') = 9 rows. Also 'Bier "Irish Red Ale' (unbalanced quote) ranks #1 for 'guinness'.

**Fix:** Extend tapt_name_ok (or tapt_display_name stripping) with retail patterns: reject/strip names containing currency symbols or codes (EUR sign, 'zzgl', 'pfand', 'basispreis', 'packung', price-like '[0-9],[0-9]{2}'), digit runs of 7+ (GTINs), and unbalanced quotes. Because both are STORED generated columns, the migration must drop and re-add display_name/name_ok (per 0066's own note) to recompute, then spot-check the 9 rows disappear from catalog_search('guinness').

### [FIXED this round] Brewery country is the OFF sale-country, not the brewery's home - famous breweries listed under countries they have no connection to
*Surface:* Catalog rows, beer page Country fact + 'Where you'll find it' card, state/country boards  ·  *Anchor:* `scripts/ingest_off_csv.py:55`  ·  *Found by:* fleet

The ingestion takes the FIRST tag of OFF countries_tags (where the scanned product was purchased) as the brewery's country. Result, all live: Brewdog -> Australia, Founder's -> France, Daniel Thwaites -> France, 'Guiness' -> Puerto Rico, Guinness Hop House 13 -> France, plus Bavaria/Waterloo/Zichovec -> France. A user searching 'all day ipa' sees 'All Day IPA - Founders - United States' directly above 'All Day IPA - Founder's - France' (same beer, misspelled brewery, wrong country). On the beer page this wrong country renders three ways: the header subtitle, the 'Country' fact row, and the 'Home turf France, N beer spots there on the Tapt map' claim - a fabricated-looking geography statement built on wrong data. The same brewery.country feeds the country leaderboards, so the wrongness propagates to state/country boards. Law 3: no beer listed under a country it has no connection to.

**Evidence:** country_from(tags) returns the first en: tag of countries_tags (line 55-59, applied line 100) - OFF documents countries_tags as countries where the product is sold. Live brewery rows: ('Brewdog','Australia'), ('Daniel Thwaites','France'), ('Founder's','France'), ('Guiness','Puerto Rico'), ('Guinness Hop House 13','France'), ('ALDI Guinness','Germany'). catalog_search('all day ipa') returns both the US and 'France' Founders rows. BeerDetailView.swift:524 renders 'Home turf \(country), \(d.venuesInCountry) beer spots there'.

**Fix:** Stop deriving brewery homeland from countries_tags. Short term: null out brewery.country where it came from the OFF CSV lane (track via ingestion_source/external_ids) so rows show no country instead of a wrong one - blank beats invented; the app already hides country-dependent UI when null. Longer term: backfill homeland from the OBDB brewery seed (seed_breweries.py already carries real countries) by name-matching, and only trust OFF countries for 'where it is sold', never for 'Home turf'.

### [FIXED this round] venue table has RLS enabled with zero policies, so every pour's venue silently vanishes: states stat is permanently 0 and Tap Trail / state shelves can never unlock
*Surface:* Cellar / Passport (venue on logged pours)  ·  *Anchor:* `app/Tapt/Core/CheckinService.swift:170`  ·  *Found by:* fleet

LogPourView lets the user attach a brewery/taproom, log_checkin stores venue_id, and the celebration + share card show the place. But CheckinService.mine() reads the venue via a PostgREST embed (venue(name,external_ids)) as the authenticated role. The live venue table has relrowsecurity=true and NOT ONE policy, so the embed returns null for every checkin, always. Result a real user sees: the venue line under each Cellar pour never appears, placeSubtitle is always empty, visitedStates is always empty, the 'states' stat tile is 0 forever, the 'X states to tap trail' milestone and the Tap Trail badge (5 states) are unreachable, Passport's 'States 0 / 50' grid never lights, and no state shelf can ever unlock. The user watched the app accept their venue at log time and it is never reflected anywhere afterward.

**Evidence:** Live pg_policies for public.venue: no rows (checkin_event/beer_catalog/brewery/region_beer_guide all have policies; venue has none) while pg_class shows venue relrowsecurity=true and has_table_privilege('authenticated','public.venue','select')=true (grant without policy = silent empty result, so the embed nulls instead of erroring). mine() selects "...venue(name,external_ids)" (CheckinService.swift:170); CellarView.swift:20-22 derives visitedStates solely from venueRegion (venue.external_ids->>'region'); PassportView.swift:26 same. Map and venue picker still work only because brewery_map_feed is SECURITY DEFINER.

**Fix:** Ship a migration adding a read policy on venue (e.g. create policy venue_public_read on public.venue for select to authenticated using (true); venue is public map data with no PII, sourced from OBDB), or alternatively stop embedding venue in mine() and return venue name/city/region/country from a SECURITY DEFINER RPC. Then verify in the app that a pour logged with a venue shows the venue line and increments the states stat.

### [FIXED this round] Cellar shows the raw SKU dump name, not the clean display name the user picked: log '1664 Blanc', see '1664 25 cl 1664 Blanc Sans Alcool 0.4 DEGRE ALCOOL'
*Surface:* Cellar pour journal (row names)  ·  *Anchor:* `app/Tapt/Core/CheckinService.swift:170`  ·  *Found by:* fleet

The Log-a-pour picker and search use catalog_search, which returns the normalized display_name ('1664 Blanc'). But after logging, CheckinService.mine() re-fetches the beer via beer_catalog(name...) which is the RAW ingest name. For 18 of the 60 beers on the default picker's first screen the raw name differs from the display name, mostly pack-size barcode dumps. A user logs a beer with a clean name, then their journal (CellarView row, line 189 Text(c.beerName)) shows a lowercase SKU string with pack counts and 'DEGRE ALCOOL' in it. The journal looks broken and contradicts the screen they just used.

**Evidence:** Live query joining catalog_search(null,null,false,60,0) ids to beer_catalog: display '1664 Blanc' -> raw '1664 25 cl 1664 Blanc Sans Alcool 0.4 DEGRE ALCOOL'; '1664 Blonde' -> '1664 10x25cl 1664 blonde 5.5 degre alcool'; '1664 Gold' -> '1664 12x25cl 1664 gold 6.1 degre alcool'; '8.6 Original' -> '8.6 ORIGINAL'; 18/60 rows differ. beer_catalog.display_name exists as a stored generated column (migration 0066) but mine() selects name.

**Fix:** Change mine()'s select to alias the display name (PostgREST supports column aliasing in embeds: beer_catalog(name:display_name,brewery(name,country))) so the journal renders the same normalized name the picker showed; keep the raw-name fallback only if display_name is null. Same fix applies to any other surface still embedding beer_catalog(name).

### [FIXED this round] Scan flow pre-fills a 4-star rating the user never chose and writes it to their record; the rating also persists from the previous log
*Surface:* Scan (log from scan result)  ·  *Anchor:* `app/Tapt/Features/Scan/ScanView.swift:13`  ·  *Found by:* fleet

ScanView declares @State rating: Double = 4 and the Log button is enabled immediately (disabled only while saving). A user who scans a can and taps Log writes a 4.0 rating they never expressed into checkin_event, which feeds avg_rating aggregates and the market pipeline. LogPourView was explicitly fixed for exactly this ('Starts unrated on purpose: a default 4 stars records an opinion the user never expressed, and aggregates would skew up from day one', LogPourView.swift:15-17) but the scan path still ships the invented default. Worse, loadMatches() resets selected and offBeer but never resets rating, so after logging one beer at 5 stars the next scanned beer silently inherits 5 stars.

**Evidence:** ScanView.swift:13 '@State private var rating: Double = 4'; save button at 224-229 '.disabled(saving)' only; offCard log button 278-283 same; loadMatches 341-353 resets selected/offBeer but not rating. Contrast LogPourView.swift:17 'rating: Double = 0' and :178 '.disabled(saving || rating == 0)'. log_checkin accepts any 0-5 rating and inserts it (migration 0007).

**Fix:** Mirror the LogPourView contract in ScanView: initialize rating to 0, reset it in loadMatches()/matchRow selection, disable Log until rating > 0 with the same 'Tap a star to rate it' affordance, for both the catalog match row and the Open Food Facts card.

### [FIXED this round] State boards relabel Global data as 'Top in {state}' — beers shown under states they have no connection to
*Surface:* Explore state/country boards (the regional leaderboard)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:320`  ·  *Found by:* fleet

A US user who picks (or is auto-geocoded into) any state sees section headers 'Biggest movers in New Jersey' and 'Top in New Jersey' over purely global data. Chain proved end to end: (1) beer_trend_feed's catalog fallback only creates rows for region = brewery.country or 'Global', so no state region ever has fallback rows; (2) the only live regional vote row is stored under region 'CA' (from user_profile.region_code='CA') while BeerService.trends() queries the full name 'California', so even real state activity is unreachable; (3) ExploreView.load() silently swaps in the Global feed when the regional fetch is empty, but topSection/moversSection still title themselves with the state name because `region` is unchanged and hasMarketActivity is true (the Global feed contains the one voted beer, 'La saison du chasseur', France). The only disclosure is a small hero caption 'Texas guide + Global radar'. detectHomeState() auto-selects the user's real state on first launch with location consent, so this is the default first-screen experience for US users. Violates product law 3 (no beer listed under a state it has no connection to) and undermines the honesty positioning of the whole board system.

**Evidence:** ExploreView.swift:316-322 header(hasMarketActivity ? (region == "Global" ? "Trending worldwide" : "Top in \(region)") ...); :279 "Biggest movers in \(region)"; :450-458 load(): `if regional.isEmpty && region != "Global" { beers = try await BeerService.trends(region: "Global") ... }`. Live DB: `select region from beer_trend` → [{region:'CA'},{region:'Global'}]; `select region_code from user_profile` → 'CA'; beer_trend_feed viewdef fallback: `CROSS JOIN LATERAL (VALUES (COALESCE(NULLIF(br.country,''),'Global')), ('Global')) r(region)` — states never appear. BeerService.trends() filters `.eq("region", value: region)` with full names from BeerRegions.states ('California'), so the live 'CA' row matches no board.

**Fix:** Three coordinated changes: (a) normalize region keys once — decide on full state names, migrate the existing beer_trend/user_profile 'CA'-style values with a one-time UPDATE mapping, and add a normalization step in refresh_beer_trend (0055) so future region_code values are canonicalized; (b) in ExploreView.load(), when the regional feed is empty and Global is substituted, change the section headers to the honest Global wording ('Trending worldwide' / 'Explore worldwide beers') and show a one-line inline note 'Nothing on the {region} board yet — showing worldwide' instead of relabeling; (c) keep 'Top in {region}' only when the rows actually came from that region's partition.

### [FIXED this round] All 50 US state boards are mislabeled Global boards: 'Top in New Jersey' shows a French beer 'climbing in New Jersey'
*Surface:* Explore state/country boards (regionPicker + load fallback)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:452`  ·  *Found by:* fleet

Live beer_trend_feed contains ZERO state-named regions (only countries + 'Global' + one stray 'CA'), and the 0016 catalog fallback only assigns regions from brewery.country or 'Global' — so every state chip is guaranteed empty. load() then silently swaps in the Global feed but leaves `region` set to the state, so a user who taps New Jersey (or is auto-defaulted there by detectHomeState after granting location) sees: hero 'La saison du chasseur — Brasserie Thibord is climbing in New Jersey.' (a French saison with zero NJ connection, the only vote on the platform), section header 'Top in New Jersey · Tap to vote it up or down', and movers header 'Biggest movers in New Jersey' — all over worldwide catalog rows (French, German, UK beers). The only disclosure is the hero caption 'New Jersey guide + Global radar', which is cryptic, references a guide module that was removed from this screen (line 60 comment), and is 3 sections away from the mislabeled headers. This violates laws 1 and 3 on the app's first screen, in the default post-onboarding state for every US user.

**Evidence:** Live: `select region, count(*) from beer_trend_feed group by region` returns only countries + Global — no state names; the single active row is region Global/'CA': 'La saison du chasseur', Brasserie Thibord, France, popularity 1, momentum 1. Code: load() lines 452-455 `if regional.isEmpty && region != "Global" { beers = try await BeerService.trends(region: "Global"); feedNote = "\(region) guide + Global radar" }`; line 118 hero subtitle `"\($0.brewery) is \($0.momentum >= 0 ? "climbing" : "sliding") in \(region...)"`; line 320 `"Top in \(region)"`; line 279 `"Biggest movers in \(region)"`. Migration 0016 lines 22-24: fallback regions are only `coalesce(br.country,'Global')` and `'Global'` — states can never be populated from catalog.

**Fix:** When the fallback fires, stop interpolating the state into any market claim: set a mode flag and render the Global headers ('Trending worldwide' / 'Biggest movers worldwide'), hero subtitle without the region ('Brasserie Thibord is climbing worldwide.'), and one plain inline note directly above the list: 'No New Jersey activity yet. Showing worldwide beers — your vote starts the New Jersey board.' Alternatively (better long-term) populate state boards honestly by joining beers to state venue/checkin data, and until then keep state chips but with the honest empty-board copy already written for the no-activity case.

### [FIXED this round] Anon can execute match_beers() and region_guide_feed() (plus tapt_* helpers) — anon RPC surface is not locked to the contractual 4
*Surface:* Anon SQL surface (boards data path)  ·  *Anchor:* `supabase/migrations/0061_shrink_anon_rpc_surface.sql:11`  ·  *Found by:* fleet

Product law 4 and AGENTS.md:60 lock the anon RPC surface to exactly catalog_search, venue_brand, venue_events, venue_menu. Live pg_proc ACLs show anon also holds EXECUTE on match_beers(text,int) (granted 0005:76), region_guide_feed() (granted 0007:785, the boards' guide loader), tapt_display_name, tapt_name_ok, tapt_ref_style_name, and set_updated_at. The 0061 shrink migration and 0067's clean_beer_name revoke both used named lists that simply missed these. None expose PII (read-only catalog/editorial data; RLS on user tables verified deny-all for anon), so this is contract drift rather than a leak — but the AGENTS.md NOW-board claim 'anon surface 21→4' is false in the live database, and the drift mechanism (Supabase default privileges grant anon EXECUTE on every new public function) guarantees recurrence.

**Evidence:** Live query of pg_proc ACLs (explicit grants, grantee=anon) returns app functions: catalog_search, venue_brand, venue_events, venue_menu, match_beers, region_guide_feed, tapt_display_name, tapt_name_ok, tapt_ref_style_name, set_updated_at. 0061's revoke array (lines 11-18) lists 14 functions but not match_beers or region_guide_feed; 0005:76 `grant execute on function match_beers(text, int) to anon, authenticated;` and 0007:785 `grant execute on function region_guide_feed() to anon, authenticated;` were never revoked. RLS check: user_profile/beer_vote/consent_ledger/etc. have zero anon policies (rows denied).

**Fix:** One migration: revoke anon EXECUTE on match_beers(text,int), region_guide_feed(), tapt_display_name, tapt_name_ok, tapt_ref_style_name, set_updated_at (the app calls the first two authenticated; the rest are internal helpers). Then close the drift channel: `alter default privileges in schema public revoke execute on functions from anon;` so future functions start locked, and re-run the pg_proc ACL query as the verification step. Update AGENTS.md only after the live query confirms exactly 4.

### [FIXED this round] Styles leaderboard serves raw OFF retail categories as beer styles ('Craft Beers', '5 Beer', 'Beers From Germany', 'Wijn')
*Surface:* Leaderboards > Styles board  ·  *Anchor:* `supabase/migrations/0009_superapp_foundations.sql:469`  ·  *Found by:* fleet

leaderboard_styles groups and displays checkin_event.style verbatim, and log_checkin copies the raw beer_catalog.style into that column at checkin time. The raw column is Open Food Facts category junk, not styles: among the 10,288 name_ok beers, 'Craft Beers' (807), 'Lagers' (658), 'Beers From Germany' (277), 'Lithuanian Beers' (241), '5 Beer' (128), 'Sweetened Beverages' (41), 'Wijn' (Dutch for wine, 29), 'Industrial Beer' (35). The board is empty today only because prod checkins were cleared on 2026-07-11; the very first user checkin of any of these ~2,900 junk-style beers permanently puts a non-style like '5 Beer' or 'Beers From Germany' on the public Styles board, rendered verbatim at LeaderboardsView.swift:187. 0051 fixed exactly this vocabulary for the Beers board but the Styles board was never routed through the BJCP resolver.

**Evidence:** Live prosrc of leaderboard_styles: `select ce.style, count(*)... from checkin_event ce where coalesce(ce.style,'') <> '' group by ce.style`. log_checkin (0007:354ff) inserts `v_beer.style` raw. Live query of raw styles among name_ok beers returned: Craft Beers 807, Beers From Germany 277, 5 Beer 128, Sweetened Beverages 41, Wijn 29 — none present in beer_style_reference (is_bjcp=false for all top-40 values).

**Fix:** Resolve the style at read time the same way 0051 does for the Beers board: group leaderboard_styles by coalesce(sr.style_name, null) via `left join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(ce.style, '')` and drop rows that do not resolve to a BJCP style (blank beats junk, per product law 1/3). Alternatively resolve at write time in log_checkin (store the resolved style, keep raw in a separate column), which also fixes the tasters 'styles' distinct-count and profile top_styles that share this vocabulary.

### [FIXED this round] Anon can execute 7 functions beyond the locked 4-function contract; 0067 P0-18 revoke was ineffective
*Surface:* Anon SQL surface (PostgREST RPC, taptbeer.com + any unauthenticated client)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:193`  ·  *Found by:* fleet

Product law 4 locks the anon surface to exactly catalog_search, venue_brand, venue_events, venue_menu. Live, anon can additionally execute match_beers(p_query,p_limit), region_guide_feed(), clean_beer_name(text), tapt_display_name(text), tapt_name_ok(text), tapt_ref_style_name(text,text), and set_updated_at(). Today's 0067 P0-18 fix ran `revoke execute ... from anon` on clean_beer_name, but the function's ACL carries a PUBLIC grant (`=X/postgres`), which anon inherits, so the revoke changed nothing. match_beers and region_guide_feed return catalog data through named RPCs that the contract says do not exist for anon.

**Evidence:** Live pg_proc ACL query: clean_beer_name proacl={=X/postgres,postgres=X,authenticated=X,service_role=X}, has_function_privilege('anon',...)=true. Full anon-executable non-extension list: catalog_search, clean_beer_name, match_beers, region_guide_feed, set_updated_at, tapt_display_name, tapt_name_ok, tapt_ref_style_name, venue_brand, venue_events, venue_menu.

**Fix:** Ship a migration that, for each of the 7 extra functions, runs `revoke execute on function ... from public, anon;` (revoking from PUBLIC is the part 0067 missed). Add `alter default privileges in schema public revoke execute on functions from public, anon;` so future functions do not regain the grant, and re-run the 0061-style verification (expect anon 401 on match_beers/region_guide_feed, 200 only on the 4 contracted functions).

### [FIXED this round] Brewery country is systematically the country of sale, not the brewery's origin — beers listed under countries they have no connection to
*Surface:* Catalog browse/search, leaderboard subtitles, market detail country tag, country trend boards  ·  *Anchor:* `supabase/migrations/0007_backend_contract_and_content_pipeline.sql`  ·  *Found by:* fleet

brewery.country for OFF-ingested rows reflects where the product was scanned (mostly France), not where the brewery is. Users see Kloster Andechs (Bavaria) as France, Daniel Thwaites (Lancashire, England) as France, Rodinny pivovar Zichovec (Czech) as France, Pinkus (Munster, Germany) as Netherlands, Birra Moretti as France, Bavaria (NL) as France, Dalmacijavino (Split, Croatia) as France, Desperados as Belgium, Budweiser as France, and a 'Guiness' (misspelled) brewery in Puerto Rico. Three of these wrong countries appear on the DEFAULT first-30 browse screen. Country feeds the flag emoji, the leaderboard row subtitle, the market detail tag, AND the per-country trend boards (beer_trend_feed region = brewery country), so the France board is stuffed with English, Czech, and Dutch breweries' beers. Direct law-3 violation: beer listed under a country it has no connection to.

**Evidence:** Live rows: ('Kloster Andechs','France'), ('Daniel Thwaites','France' via catalog_search first page '13 Guns'), ('Rodinny pivovar Zichovec','France'), ('Pinkus','Netherlands'), ('Guiness','Puerto Rico'), ('Budweiser','France'), ('Dalmacijavino','France'), ('Desperados','Belgium'). Brewery country distribution: France=1,276 (2nd largest) vs venues in France=3 — the catalog is French-retail shaped, not French-brewery shaped.

**Fix:** Stop displaying and grouping by brewery.country for OFF-sourced breweries until it is verified: null out country where external_ids->>'source' is the OFF lane and no OBDB match confirms it (blank beats wrong, per house rule), and backfill from Open Brewery DB name matches where available. In the same pass, delete/merge the misspelled 'Guiness' brewery row. Rebuild beer_trend_feed regions and refresh_beer_market_standing afterward so country boards and flags only claim origins that are real.

### [FIXED round 2] Normalizer strips 'sans alcool' and leading brand numerals, so NA variants masquerade as the flagship beer (e.g. '1664 Blanc' shown at 0.4% ABV) and as generic names ('Blonde')
*Surface:* Catalog browse + No/Low filter + beer detail (ABV) for flagship brands  ·  *Anchor:* `supabase/migrations/0064_beer_name_normalize_v3_retail_strings.sql:35`  ·  *Found by:* fleet

tapt_display_name deliberately removes no-alcohol phrases (0064 s4) and strips a leading 4+ digit token when followed by a letter (s0). Result: '1664 Blanc Sans Alcool 0.4' rows display as '1664 Blanc', and '1664 Blonde sans alcool' displays as just 'Blonde' (brand deleted). Because catalog_search then keeps one row per (display_name, brewery), the NA row can be the row a user gets: the live default browse page shows '1664 Blanc' at ABV 0.40 with is_na_low=true — a real person reads that the well-known 5.0% witbier is a 0.4% beer, and the No/Low lens surfaces it as an NA beer under the regular beer's name. The identity of the product shown is wrong.

**Evidence:** Live: 7 rows collapse to display_name '1664 Blanc' — five at abv 5.00/is_na_low=false, two at 0.40/is_na_low=true (raw names contain 'blanc sans alcool 0.4 degre alcool'); catalog_search(null,...) first page returned {name:'1664 Blanc', abv:0.40}. Also live: name '1664 Blonde sans alcool' -> display_name 'Blonde'.

**Fix:** Change tapt_display_name to preserve the NA qualifier instead of deleting it (map 'sans alcool'/'alkoholfrei'/'alcohol free' to a canonical suffix like '0.0' rather than stripping to nothing), and guard the leading-digit strip so it never fires when the remaining name would drop a known numeric brand (simplest: only strip leading digits of length >= 6, i.e. barcodes, not 4-5 digit brand names like 1664). Because display_name/name_ok are stored generated columns, drop and re-add them (per 0066's note) and refresh the market standings after.

### [FIXED this round] Byte-identical duplicate rows on the first browse screen: live catalog_search dedupes per-brewery, so the same beer under brand-row vs brewery-row shows twice
*Surface:* Default catalog browse first page + search results (catalog_search)  ·  *Anchor:* `supabase/migrations/0066_materialize_display_names.sql:13`  ·  *Found by:* fleet

The live catalog_search (which has drifted from repo 0066 — it partitions by lower(display_name) PLUS brewery) returns two rows both literally named '3 Monts' on the DEFAULT first-30 screen, one attributed to brewery '3 Monts' (a brand-as-brewery junk row) and one to 'Brasserie de Saint-Sylvestre' (the actual brewer of the same beer). Searching 'beck' returns 'Beck's Pils' twice (Anheuser-Busch InBev/United States at 4.90 and Beck's/Germany at 16.20 — the same beer with two contradictory countries and one impossible ABV on the same screen). Law 3 names this exactly: duplicate rows that look identical, and stats that contradict each other on the same screen.

**Evidence:** catalog_search(null,null,false,30,0) rows 21-22: two '3 Monts' entries; hex of both display_names identical (33204d6f6e7473). catalog_search('beck',...) contains 'Beck's Pils' twice (US/4.90 and DE/16.20). Live pg_get_functiondef shows partition by (lower(display_name), coalesce(brewery_id::text, lower(b.name),'')) — not the repo 0066 one-row-per-name contract.

**Fix:** Collapse the dedupe back to one row per lower(display_name) when the competing rows' breweries are the same real-world producer: before that, merge brand-as-brewery rows into their true brewery via the existing canonical_merge_queue lane ('3 Monts' brewery -> Brasserie de Saint-Sylvestre, 'Beck's'/'Becks'/'Beck's(curly)' -> one row). Also commit the live catalog_search definition into a numbered migration so repo and prod stop diverging.

### [FIXED this round] Impossible ABVs presented as fact: beers at 68%, 39.6%, 37.7%, 23%, 16.2%
*Surface:* Beer detail pages, catalog search rows (ABV field)  ·  *Anchor:* `supabase/migrations/0037_clean_beer_names.sql:11`  ·  *Found by:* fleet

9 name_ok beers carry ABV above 15%, including 'Starkbier' at 68.00%, 'Peroni Chill Lemon' at 39.60%, 'Birra Radler Chinotto' at 37.70%, 'Desperados Original' at 23.00% (real product is 5.9%), and 'Beck's Pils' at 16.20% (real 4.9%) — that last one is returned by a plain 'beck' search today. These read as false facts on user-visible surfaces (catalog rows show abv, beer detail leads with it). The 0037 name cleaner already encodes the insight that beer ABV caps around 15%, but the abv column itself was never sanity-gated.

**Evidence:** Live: select where name_ok and abv>16 -> Starkbier 68.00 (Lemke Berlin), Peroni Chill Lemon 39.60, Birra Radler Chinotto 37.70, SAER BRAU EST. 1983 Radler 37.50, Pelinkovac 28.00, Desperados Original 23.00, Eierlikoer 20.00, Beck's Pils 16.20. Count: 9 rows >15%, max 68.00.

**Fix:** One migration: null out abv where abv > 15 for beer-styled rows (blank beats wrong; keep the raw value in external_ids if you want it for debugging), and add a check or ingest-side clamp so future OFF pulls can't write >15 into beer_catalog.abv. Rows that are actually liqueurs (Pelinkovac, Eierlikoer) belong to the non-beer purge instead.

### [FIXED this round] match_beers and region_guide_feed are executable by anon, outside the locked four-function surface
*Surface:* Anon SQL surface (live DB grants)  ·  *Anchor:* `supabase/migrations/0061_shrink_anon_rpc_surface.sql:11`  ·  *Found by:* fleet

The product law locks the anon SQL surface to exactly catalog_search, venue_brand, venue_events, venue_menu. On the live database, anon also holds EXECUTE on public.match_beers(text,integer) and public.region_guide_feed() (plus the text helpers clean_beer_name, tapt_display_name, tapt_name_ok, tapt_ref_style_name). Both are SECURITY INVOKER, but beer_catalog, brewery, and region_beer_guide each have an anon-facing RLS policy, so an unauthenticated caller of /rest/v1/rpc/match_beers or /rpc/region_guide_feed gets real rows back. Migration 0061 deliberately shrank the anon surface but its revoke list only covered SECURITY DEFINER functions and missed these two invoker functions, so the lock documented in 0061's own header comment ('The public web calls exactly: catalog_search, venue_brand, venue_events, venue_menu') is not true on the live project.

**Evidence:** Live query: has_function_privilege('anon','public.match_beers(text,integer)','EXECUTE') = true and has_function_privilege('anon','public.region_guide_feed()','EXECUTE') = true. Live RLS check: beer_catalog/brewery/region_beer_guide all have rls_enabled=true with 1 anon-role policy each, so the invoker functions return data to anon. 0061's revoke array lists 14 functions; match_beers and region_guide_feed are absent.

**Fix:** Ship a follow-up migration that revokes EXECUTE from anon (and PUBLIC) on public.match_beers(text,integer) and public.region_guide_feed(), and strips default PUBLIC execute from the tapt_* / clean_beer_name helpers (revoke from public, anon; grant to authenticated where the app needs them). Then re-verify with the same has_function_privilege query that the only public-schema app functions anon can execute are catalog_search, venue_brand, venue_events, venue_menu, and update AGENTS.md's locked anon list note if it enumerates the surface.

### [FIXED this round] 13 live venues have swapped or sign-flipped coordinates and pin on the wrong continent or in the ocean
*Surface:* Near You map (NearYouView) + venue detail sheet + landing pitch claim  ·  *Anchor:* `supabase/migrations/0008_open_brewery_db_breadth.sql`  ·  *Found by:* fleet

Ten Berlin venues (BrewDog Berlin Mitte, BRLO Brwhouse, Mikkeller Berlin, Prater Beer Garden, Golgatha Biergarten, Birgit, Berlin Craft Beer Experience) are stored with lat/lng swapped (lat 13.4, lng 52.5), which renders their map pins in the Arabian Sea off Yemen. Goat Island Brewing (Cullman, Alabama) and Labyrinth Brewing Company (Manchester, Connecticut) have swapped coords with negative latitude, pinning them in the Southern Ocean/Antarctica. Mescan Brewery (Kilsallagh, Ireland) has a flipped longitude sign (+9.73 instead of -9.73), pinning an Irish brewery near Hamburg, Germany. A user who taps one of these pins gets a detail sheet saying Berlin, Germany while the map camera sits over open ocean, and the Directions button routes them there. This also directly falsifies landing/pitch.html line 89, which sells these rows as 'coordinate-verified venues mapped'. All 13 rows are source_note 'Open Brewery DB' (known upstream OBDB data bugs imported without a sanity gate).

**Evidence:** Live SQL on venue (st_y/st_x of geo): Berlin Craft Beer Experience lat=13.4169 lng=52.4995 (x2 dup rows); Birgit 13.4123/52.5093; BrewDog Berlin Mitte 13.4132/52.5170 (x2); BRLO Brwhouse 13.4169/52.4995 (x2); Golgatha Biergarten 13.3792/52.4868; Mikkeller Berlin 13.3942/52.5286; Prater Beer Garden 13.3942/52.5286; Goat Island Brewing (Cullman, US) lat=-86.8209 lng=34.1409; Labyrinth Brewing Company (Manchester, US) lat=-72.5649 lng=41.7771; Mescan Brewery (Kilsallagh, Ireland) lat=53.7472 lng=+9.7305. All have source_note 'Open Brewery DB'. Country-bbox sweep found 0 other offenders across the 14 largest countries.

**Fix:** One data migration: for the 12 swapped rows, rebuild geo as st_makepoint(old_lat, old_lng) (the values are exactly transposed); for Mescan flip the longitude sign. Then add a permanent ingest guard to the OBDB import path: reject or null the coordinates (blank beats wrong) whenever the point falls outside a per-country bounding box for the row's stated country, and run that same check as a post-refresh assertion so upstream OBDB bugs can never reach the map again.

### [FIXED this round] Seven functions beyond the locked four are executable by anon in the live DB, and the shipped P0-18 fix is a no-op
*Surface:* Anon SQL surface (Supabase REST, taptbeer.com public web)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:194`  ·  *Found by:* fleet

The anon surface is contractually locked to exactly catalog_search, venue_brand, venue_events, venue_menu. Live pg_proc/ACL inspection shows anon can also execute match_beers, region_guide_feed, clean_beer_name, tapt_display_name, tapt_name_ok, tapt_ref_style_name, and holds EXECUTE on set_updated_at (a trigger function, not REST-callable, but still granted). match_beers and region_guide_feed are table-returning RPCs any unauthenticated caller can invoke via /rest/v1/rpc/. Worse, migration 0067's P0-18 block ('revoke execute on function clean_beer_name from anon') did not work: it revoked anon's direct grant but the function still carries the default EXECUTE grant to PUBLIC, which anon inherits, so clean_beer_name remains anon-callable today despite the P0 being marked done.

**Evidence:** has_function_privilege('anon', oid, 'EXECUTE') over public schema (extension functions excluded) returns true for: catalog_search, clean_beer_name, match_beers, region_guide_feed, set_updated_at, tapt_display_name, tapt_name_ok, tapt_ref_style_name, venue_brand, venue_events, venue_menu. aclexplode confirms mechanism: clean_beer_name has no direct anon grant but grantee 'unknown (OID=0)' = PUBLIC retains EXECUTE; match_beers/set_updated_at/tapt_* hold both direct anon and PUBLIC grants; region_guide_feed holds a direct anon grant.

**Fix:** New migration using the pattern 0067 line 190 already uses correctly: for each of the seven functions, `revoke all on function ... from public, anon;` then `grant execute ... to authenticated` (region_guide_feed is called by the signed-in app's Passport surface, so it needs the authenticated grant; the tapt_* helpers and set_updated_at need no client grants at all). Add a CI/live assertion that enumerates anon-executable public functions (including PUBLIC-inherited grants via has_function_privilege) and fails if the set is not exactly the locked four.

### [FIXED this round] Hardcoded '8,700+' venue count still live in two user-visible places, and it overstates the real count
*Surface:* Claim-venue flow (BreweriesHubView) + landing pitch page  ·  *Anchor:* `app/Tapt/Features/Partners/BreweriesHubView.swift:280`  ·  *Found by:* fleet

docs/21 P0-8 (marked done) removed the 8,700+ number-flex from the Claim action card, but two instances survived: the claim search screen tells venue owners 'We've already mapped 8,700+ breweries, bars, and taprooms', and pitch.html shows a stat card '8,700+ coordinate-verified venues mapped'. The live venue table has 8,694 rows, of which 49 are duplicate rows, so unique venues are about 8,645 — the claim is false today, it is a hardcoded stat that silently drifts, and 'coordinate-verified' is additionally false (13 rows have provably wrong coordinates). This is exactly the number-flexing the voice rule bans, aimed at the most trust-sensitive audience: a business owner deciding whether to claim.

**Evidence:** BreweriesHubView.swift:280: Text("Search for your venue by name or city. We've already mapped 8,700+ breweries, bars, and taprooms."); landing/pitch.html:89: '<b>8,700+</b><span>coordinate-verified venues mapped...'. Live SQL: SELECT count(*) FROM venue → 8694 total; 49 duplicate name+city groups (98 rows). docs/21 P0-8 fixed only BreweriesHubView.swift:141.

**Fix:** Finish P0-8 everywhere: change the claim-search line to the already-approved numberless copy ('Search for your venue by name or city.') and remove or live-source the pitch.html stat card — if the pitch needs a proof point, render the count at build time from a fresh SELECT count(*) and drop the word 'coordinate-verified' until the coordinate fixes and ingest guard from the swapped-coords finding are in.

### [FIXED this round] Weekly Dispatch sender still sends with NO unsubscribe link, no List-Unsubscribe headers, and no postal address, and its body number-flexes
*Surface:* Newsletter email lane (dispatch-weekly edge function, promised on index.html and dispatch.html)  ·  *Anchor:* `supabase/functions/dispatch-weekly/index.ts:97`  ·  *Found by:* fleet

Both public signup surfaces promise 'Unsubscribe in one tap' (index.html:394) and 'one-click in every issue' (dispatch.html:182). Today's CAN-SPAM fix covered only the resend-send function (admin manual sends). The deployed dispatch-weekly function, the one the owner is instructed to activate with RESEND_API_KEY + CRON_SECRET for the automated weekly send, still selects only `email` (not unsubscribe_token), sends via a bare sendOne() with no List-Unsubscribe/List-Unsubscribe-Post headers, and its footer has no unsubscribe link and no postal address. Every automated weekly issue would violate CAN-SPAM and the site's own promise. Its body also still contains the banned number-flex line ('Tapt now maps X beers from Y breweries and Z venues across N countries'), which docs/21 P0-9 ordered scrubbed.

**Evidence:** Live get_edge_function(dispatch-weekly) v2 matches the repo mirror: mode=send does `admin.from("newsletter_subscriber").select("email")` then `sendOne(to, subject, html)` with `body: JSON.stringify({ from: FROM, to, subject, html })` (no headers); issueHtml() footer is only 'Tapt, THE Beer Superapp. Enjoy responsibly... taptbeer.com'; line 59 renders 'Tapt now maps <b>${st.beers}</b> beers from <b>${st.breweries}</b> breweries...'. Compare resend-send kind=dispatch which does gate on POSTAL and sends per-recipient unsubscribe links + RFC 8058 headers.

**Fix:** Bring dispatch-weekly's send path onto the same CAN-SPAM lane as resend-send: require MAIL_POSTAL_ADDRESS (412 if missing), select email + unsubscribe_token, send individually with a per-recipient unsubscribe URL in the footer plus List-Unsubscribe and List-Unsubscribe-Post: One-Click headers, and replace the 'Tapt now maps N beers...' stats block with plain non-numeric copy per the voice rule. Simplest option: have dispatch-weekly build the HTML and delegate the actual blast to resend-send's compliant dispatch path, so there is exactly one send code path. Redeploy and mirror in the same commit.

### [FIXED this round] Six functions beyond the locked four are executable by anon; the 0067 clean_beer_name revoke was ineffective
*Surface:* Anon SQL surface (backs menu.html, portal.html, app-preview.html public pages)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:200`  ·  *Found by:* fleet

AGENTS.md and product law 4 lock the anon RPC surface to exactly catalog_search, venue_brand, venue_events, venue_menu. Live pg_proc shows anon can also execute clean_beer_name(text), match_beers(text,int), region_guide_feed(), tapt_display_name(text), tapt_name_ok(text), and tapt_ref_style_name(text,text). Migration 0067 (shipped today for P0-18) revoked clean_beer_name 'from anon' but the function carries a PUBLIC grant ('=X' ACL entry), so anon still inherits execute; the revoke did not do what it claims. match_beers and region_guide_feed expose catalog/region reads outside the contract; the tapt_* helpers leak the name-normalization logic. All are read-only (no PII observed), but the contract says anything beyond the four is a P0.

**Evidence:** Live query: functions in public schema (non-extension) where has_function_privilege('anon', oid, 'execute') returned: catalog_search, clean_beer_name, match_beers, region_guide_feed, set_updated_at (trigger fn, not RPC-invocable), tapt_display_name, tapt_name_ok, tapt_ref_style_name, venue_brand, venue_events, venue_menu. proacl for clean_beer_name = {=X/postgres, postgres=X/postgres, authenticated=X..., service_role=X...}: the '=X' PUBLIC entry survives 0067's `revoke execute ... from anon`.

**Fix:** Ship a migration that runs `revoke execute on function <fn> from public, anon` for clean_beer_name, match_beers, region_guide_feed, tapt_display_name, tapt_name_ok, tapt_ref_style_name (then grant back to authenticated/service_role as needed). Because Postgres grants EXECUTE to PUBLIC by default, every future 'revoke from anon' must also revoke from PUBLIC or it is a no-op; add that note to AGENTS.md next to the locked-four list, and re-run the pg_proc audit query after applying to confirm the surface is exactly four.

### [FIXED this round] '8,700+' venue count on the 'Zero fabricated data' slide is false; live count is 8,694
*Surface:* landing/pitch.html (public business pitch page, linked from HQ)  ·  *Anchor:* `landing/pitch.html:89`  ·  *Found by:* fleet

The moat slide leads with 'Every number is real or cited', then claims '8,700+ coordinate-verified venues mapped'. The live venue table has 8,694 rows, so '8,700+' asserts at least 8,700 and is literally untrue. docs/21 P0-8 flagged this exact number as wrong and it was fixed in the app (BreweriesHubView), but pitch.html still ships it. A wrong number on the slide whose whole argument is honesty is the most damaging possible place for one.

**Evidence:** pitch.html:89 `<div class="card"><b>8,700+</b><span>coordinate-verified venues mapped (Open Brewery DB, provenance kept)</span></div>` vs live SQL `select count(*) from venue` = 8694 (matches docs/21 P0-8: 'the number is wrong (prod venue count = 8,694)').

**Fix:** Replace the card value with an honest floor that stays true as data grows, e.g. '8,600+' or 'thousands', or bind the pitch to the number style already used on index.html (no counts at all: 'On the map, coordinate-verified, provenance kept'). Given the owner's no-number-flex rule, the safest fix is to drop the count and keep the provenance claim; if a number stays, it must be <= the live count and rechecked before every share.

### [FIXED this round] 'Download for iOS' primary CTA is a dead self-link; there is nothing to download
*Surface:* landing/index.html (live homepage, taptbeer.com)  ·  *Anchor:* `landing/index.html:222`  ·  *Found by:* fleet

The hero button 'Download for iOS' has href='#get', but id='get' is on the hero-ctas div that contains the button itself, so clicking it does nothing. The nav 'Get Tapt' button and the bottom contact section's 'Download for iOS' also point at the same #get anchor. There is no App Store, TestFlight, or waitlist destination anywhere on the site, and per pitch.html the app is TestFlight-only. A live page promising an iOS download that dead-ends on itself is both broken and untrue for every visitor today.

**Evidence:** index.html:221-222 `<div class="hero-ctas" id="get"><a class="btn btn-dark" href="#get">Download for iOS</a>`; index.html:210 `<a class="btn btn-gold" href="#get">Get Tapt</a>`; index.html:418 `<a class="btn btn-dark" href="#get">Download for iOS</a>`. No appstore.com/testflight/apps.apple.com URL exists anywhere in landing/. pitch.html:81 states 'iOS on TestFlight now'.

**Fix:** Until the App Store listing is live, change the CTA to something true and functional: either 'Join the beta' linking to a real TestFlight public link, or 'Get notified at launch' scrolling to the Dispatch signup form (#dispatch) which already exists and works. When the app ships, swap in the real apps.apple.com URL (id 6788529176) in all three places. Never ship a CTA whose promise cannot be fulfilled on click.

### [FIXED this round] Dispatch page claims a personalized newsletter that does not exist
*Surface:* Web · dispatch.html (live at taptbeer.com/dispatch.html)  ·  *Anchor:* `landing/dispatch.html:170`  ·  *Found by:* fleet

The public Dispatch page tells readers five separate times that the email is personalized: "One free email a week, tuned to your palate" (line 170), "Personalized from real check-ins and real votes" (line 171), "The real Dispatch is personalized to your palate" (line 201), "Your real Dispatch reads your check-ins and leads with beers your palate actually leans toward" (line 236), "Real issues are personalized to your palate" (line 273), plus both meta descriptions (lines 7, 9). The live deployed dispatch-weekly function (version 2, ACTIVE) builds exactly ONE issue via a single build_dispatch_content() RPC call and sends the identical HTML to every subscribed address. There is no per-user content, and web-only subscribers (dispatch-signup accepts any bare email) have no account and no check-ins to read. A subscriber is being promised a capability that is fabricated — the exact class of dishonesty the product bans.

**Evidence:** dispatch.html:236 'Your real Dispatch reads your check-ins and leads with beers your palate actually leans toward.' vs live dispatch-weekly v2 source: `const { data: content } = await admin.rpc("build_dispatch_content"); const html = issueHtml(content); ... for (const to of emails.slice(0, 100)) { if (await sendOne(to, subject, html)) ok++; }` — one `html`, sent verbatim to all subscribers.

**Fix:** Rewrite the five claims to what is true today: one weekly issue built from the community's real votes and check-ins, the same for everyone (e.g. 'One free email a week. The Beer of the Week the community crowned, style science, and what the world poured.'). Change the 'Tuned to your palate' sample block to describe the community angle, and fix the meta/og descriptions (lines 7, 9) the same way. If palate personalization ships later, restore the copy then.

### [FIXED this round] Deployed Dispatch email body still number-flexes and has no unsubscribe link, contradicting unsubscribe.html
*Surface:* Email · The Tapt Dispatch send template (deployed edge function)  ·  *Anchor:* `supabase/functions/dispatch-weekly/index.ts:59`  ·  *Found by:* fleet

The 'What the world is pouring' block in the sent email reads 'Tapt now maps N beers from N breweries and N venues across N countries, with N BJCP styles, all free to explore.' — pure count-flexing, which docs/21 P0-9 ordered scrubbed before any real send. It is still present in both the repo mirror and the LIVE deployed function (version 2). The same template also contains no unsubscribe link or List-Unsubscribe header anywhere in its footer, while the live unsubscribe.html:35 tells users to 'Use the unsubscribe link from the bottom of any Dispatch email' — a link that does not exist in the email that would be sent. The moment RESEND_API_KEY is set, every issue ships voice-violating copy and a broken unsubscribe promise.

**Evidence:** Live get_edge_function(dispatch-weekly) v2 source contains: 'Tapt now maps <b>${Number(st.beers ?? 0).toLocaleString()}</b> beers from ... across <b>${Number(st.countries ?? 0)}</b> countries...' and the footer ends at 'taptbeer.com' with no unsubscribe URL; sendOne() sets no List-Unsubscribe header. unsubscribe.html:35 references 'the unsubscribe link from the bottom of any Dispatch email'.

**Fix:** Replace the stats sentence with a non-numeric line ('See what the world poured this week, free in Tapt.') or drop the block, and add the tokenized unsubscribe footer (link to taptbeer.com/unsubscribe.html?token=…) plus a List-Unsubscribe header in sendOne(), then redeploy and mirror the same source in supabase/functions/. Keep sends blocked until both are in the deployed function.

### [FIXED this round] Second '8,700+ mapped' claim survived the P0-8 fix and is still live in-app — false and number-flexing
*Surface:* iOS app · Breweries & Bars → Claim your venue (search screen)  ·  *Anchor:* `app/Tapt/Features/Partners/BreweriesHubView.swift:280`  ·  *Found by:* fleet

P0-8 removed 'our map of 8,700+' from the hub card at line 141, but the claim-venue search screen still opens with 'Search for your venue by name or city. We've already mapped 8,700+ breweries, bars, and taprooms.' Live venue count is 8,694, so '8,700+' (a claim of at least 8,700) is literally false, and count-flexing is banned by the voice rule regardless. This is the screen a bar owner sees at the exact moment they decide whether to trust Tapt.

**Evidence:** Code: `Text("Search for your venue by name or city. We've already mapped 8,700+ breweries, bars, and taprooms.")`. Live DB: `SELECT count(*) FROM venue;` → 8694.

**Fix:** Replace with the same voice-safe copy used for the P0-8 fix, no number: 'Search for your venue by name or city. If it pours beer, it is probably already on the map.' (or simply 'Search for your venue by name or city.'). Grep the repo for '8,700' to catch any other stragglers in the same pass.

### [FIXED this round] App claims 'tap lists expire after 14 days' as an honesty guarantee — false since migration 0063
*Surface:* iOS app · Breweries & Bars hub footer  ·  *Anchor:* `app/Tapt/Features/Partners/BreweriesHubView.swift:161`  ·  *Found by:* fleet

The hub footer reads 'Menus stay honest: tap lists expire after 14 days so a stale list never masquerades as live.' Migration 0063 (live) deliberately made partner-published menus never expire (snapshots now get expires_at = now() + 3650 days) precisely so a printed QR never leads to a blank page. So the app is advertising an anti-staleness mechanism that was intentionally removed — the guarantee it promises is the opposite of how the system works. A partner or drinker who relies on '14 days' is being misled. (Tracked in docs/21 P1-15 as stale copy, but it is a user-visible false claim about data honesty, which is P0 territory.)

**Evidence:** Code: `Text("Menus stay honest: tap lists expire after 14 days so a stale list never masquerades as live...")` vs supabase/migrations/0063_partner_menus_never_expire.sql: `values (p_venue, auth.uid(), 'partner_portal', now(), now() + interval '3650 days')` with the header comment 'Partner-published menus must never silently vanish... The public menu page already shows an honest "Updated <date>" line, which is the correct freshness signal.'

**Fix:** Rewrite to the 0063 reality: 'Menus stay honest: every public menu shows the date it was last updated, and every edit is gated by an approved claim, so nobody can touch a venue they don't own.' One string change in BreweriesHubView.swift:161.

### [FIXED this round] Pitch page's 'Zero fabricated data' section leads with a fabricated number: '8,700+' venues
*Surface:* Web · pitch.html 'The moat' section (live at taptbeer.com/pitch.html)  ·  *Anchor:* `landing/pitch.html:89`  ·  *Found by:* fleet

The moat section is headlined 'Zero fabricated data. Every number is real or cited.' and its first stat card is '8,700+ coordinate-verified venues mapped'. Live count is 8,694, so the very section claiming every number is real contains a number that overstates reality. For the partner/investor audience this page targets, one checkable false stat undercuts the entire honesty positioning — the product's core differentiator.

**Evidence:** pitch.html:89 `<div class="card"><b>8,700+</b><span>coordinate-verified venues mapped (Open Brewery DB, provenance kept)</span></div>` directly under 'Zero fabricated data. Every number is real or cited.' Live DB: `SELECT count(*) FROM venue;` → 8694.

**Fix:** Change the stat to a number that is true and stays true: '8,600+' (safe floor under the live 8,694) or the plain '~8,700'. Better: make the card non-numeric ('Coordinate-verified venue map — Open Brewery DB, provenance kept') so the page never drifts false as data changes.

### [FIXED this round] tonight_feed manufactures "market heat" for beers with zero activity; honest empty state can never appear
*Surface:* Discover → Tonight ("Live beer heat") — app + SQL  ·  *Anchor:* `supabase/migrations/0006_social_ingestion_live_beer.sql:505`  ·  *Found by:* fleet

The Tonight screen (Discover → Community → Tonight, promising "Live beer heat") always renders a ranked list of ~12 beers labeled "market heat" with a flame score, even though the platform has exactly 1 real vote and 0 live tap lists. The live SQL floors heat at 1 (greatest(momentum, popularity, 1)) over beer_trend_feed, whose 0016 fallback UNION includes every raw catalog beer at popularity=0/momentum=0. So a real user opens Tonight and sees rank 1-12 beers each showing "1 🔥 market heat", the hero declares "Brasserie Thibord is showing heat from the live board" with big metric "1", and the well-written empty state ("No live beer heat yet") is dead code because trend_rows always returns 12 rows. The rows are also raw un-gated catalog junk: the same beer appears twice at ranks 1 and 2 (regions "Global" and "CA" — a state abbreviation rendered where a place name belongs), plus "bière Kwak" attributed to brewery "PerfectDraft", misspelled "Guiness Extra Stout" by "Guiness", and "IPA beer" — all bypassing the tapt_name_ok/display_name gate the rest of the app uses (laws 1 and 3). Secondary: tap_rows renders OCR match confidence (confidence*100) as the same "heat" number, so a 0.92-confidence menu match will display as "92 heat" once any tap list goes live.

**Evidence:** Live RPC output (select * from public.tonight_feed(null,12)): 12 rows, all heat_score=1, all source_label='market heat', incl. {venue_name:'Global', beer_name:'La saison du chasseur'} AND {venue_name:'CA', beer_name:'La saison du chasseur'} (same beer twice), {'bière Kwak' / 'PerfectDraft'}, {'Guiness Extra Stout' / 'Guiness'}, {'IPA beer'}. Live fn def: heat = greatest(momentum, popularity, 1) over beer_trend_feed (which unions ALL catalog beers at 0/0 per 0016), and tap_rows heat = greatest((i.confidence*100)::int,1). Live DB: beer_vote count = 1, live tap snapshots = 0, beer_trend rows = 2. Renderers: TonightView.swift:63 (hero metric = heatScore), :61 ("…is showing heat from …"), :196 (Label(heatScore, flame.fill)), :97-103 (unreachable empty state). docs/21 tracks only the locality framing (P1-11) and empty-state buttons (P1-10), not this fabrication.

**Fix:** Rewrite tonight_feed trend_rows to return only rows with real signal (where momentum > 0 or popularity > 0), delete the , 1 floor from greatest(), dedupe to one row per beer (keep the strongest region), map region codes to display names ('CA' → 'California') or drop the venue_name for market rows, and route beer/brewery names through the materialized display_name/name_ok columns like beer_market does. Change tap_rows to carry confidence in its own column (or drop sub-threshold matches) instead of presenting it as heat. With no real signal the RPC then returns 0-2 rows and TonightView's existing honest empty state finally renders.

### [FIXED this round] Anon can execute 6 functions beyond the contractual 4: match_beers, region_guide_feed, tapt_* helpers, and clean_beer_name (0067 revoke was ineffective)
*Surface:* Live database — anonymous RPC surface  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:200`  ·  *Found by:* fleet

The product contract locks the anon SQL surface to exactly catalog_search, venue_brand, venue_events, venue_menu. Live pg_proc ACLs show six additional app functions executable by anon via PostgREST /rest/v1/rpc/: match_beers(text,integer) (explicit anon grant from 0004/0005, missed by the 0061 shrink list), region_guide_feed() (explicit anon grant from 0007, also missed), tapt_display_name(text), tapt_name_ok(text), tapt_ref_style_name(text,text) (0048 helpers created without revoking the default PUBLIC execute), and clean_beer_name(text) — which yesterday's 0067 P0-18 fix revoked only 'from anon', leaving the '=X' PUBLIC grant in the ACL, so anon still passes has_function_privilege and the P0-18 fix did not actually take effect. match_beers runs trigram search over the full beer_catalog+brewery for unauthenticated callers (scrape/DoS surface at 11k rows), and region_guide_feed dumps the whole region_beer_guide table.

**Evidence:** Live query of pg_proc ACLs: match_beers(text,integer) acl {=X/postgres,…,anon=X/postgres,…}; region_guide_feed() acl {…,anon=X/postgres,…}; tapt_display_name/tapt_name_ok/tapt_ref_style_name all {=X/postgres,…,anon=X/postgres,…}; clean_beer_name(text) acl {=X/postgres,postgres=X,authenticated=X,service_role=X} — no direct anon entry but the =X PUBLIC grant means has_function_privilege('anon', oid, 'execute') = true. 0067:194-201 revokes only 'from anon'; 0061's revoke array omits match_beers and region_guide_feed entirely. Grant origins: 0004:71 and 0005:76 (match_beers → anon), 0007:785 (region_guide_feed → anon), 0048:5-30 (tapt_* created with default PUBLIC execute).

**Fix:** One migration: for each of clean_beer_name(text), match_beers(text,integer), region_guide_feed(), tapt_display_name(text), tapt_name_ok(text), tapt_ref_style_name(text,text) run revoke execute … from public, anon (keep authenticated where the app needs it — the app calls match_beers and region_guide_feed signed-in), then add alter default privileges in schema public revoke execute on functions from public so future create function statements stop leaking through PUBLIC, and re-verify with the has_function_privilege('anon', …) query that exactly the 4 contractual functions remain.


## P1

### [OPEN] Correct answer is always the first option in Pop Culture and Fun Facts, and options are never shuffled
*Surface:* Games / Trivia + Daily 5  ·  *Anchor:* `app/Tapt/Features/Games/TriviaData.swift:78`  ·  *Found by:* fleet

All 10 Pop Culture questions and all 10 Fun Facts questions store correct: 0, and 6 of 16 Beer questions do too (26 of 46 total). TriviaGame renders q.options in stored order with no per-question shuffle, so in Pop Culture or Fun Facts a player who taps the top answer every time scores 10/10. Players notice the pattern within 2-3 questions and the game reads as lazy. It also inflates Daily 5: on a typical daily set roughly 3 of the 5 shared questions have the right answer sitting first, which undercuts the water-cooler score comparison the daily seed was built for.

**Evidence:** TriviaData.swift popCulture block: every init has correct: 0 (lines 78-97), funFacts likewise (lines 102-121). Display side, GamesView.swift:205: ForEach(Array(q.options.enumerated()), id: \.offset) renders stored order; pickQuestions (GamesView.swift:288-299) shuffles question order only, never option order.

**Fix:** Shuffle each question's options at presentation time and remap the correct index: when building `order` in pickQuestions (and in the chooser path), map each TriviaQuestion to a copy whose options are shuffled with the correct index recomputed (for Daily 5, drive that shuffle from the same SplitMix64 daily seed so everyone still sees identical screens). This is a small change confined to GamesView.swift and keeps TriviaData untouched.

### [OPEN] 1,493 feed rows across 80 region keys are unreachable from the picker, including all 270 US beers and half of Czech data
*Surface:* Explore boards / region picker coverage  ·  *Anchor:* `app/Tapt/Core/BeerModels.swift:62`  ·  *Found by:* fleet

The fallback keys regions by brewery.country, but the picker never offers 'United States' (so all 270 US catalog beers appear on no board except Global - the product's home market is the one country without a country board, and states are empty per the P0). Czech beers are split across two keys: picker chip 'Czechia' shows 51 while 82 more sit under unreachable 'Czech Republic'. 'Unknown' holds 32 rows. Croatia (195), Lithuania (288), Switzerland (88), Norway (56) and ~70 more real countries have data but no chip. Real, already-ingested content is invisible or split in ways a user can see (a Czech user is shown 51 of 133 Czech beers).

**Evidence:** Live: rows in beer_trend_feed whose region is not one of the 74 picker values = 1,493 across 80 distinct keys. Per-key counts: 'United States' 270, 'Czech Republic' 82 vs 'Czechia' 51, 'Unknown' 32, 'Croatia' 195, 'Lithuania' 288, 'Switzerland' 88. BeerRegions.countries (BeerModels.swift:62-68) omits United States and lists 'Czechia' only.

**Fix:** One normalization migration: UPDATE brewery SET country='Czechia' WHERE country='Czech Republic' (and fold 'England'/'Scotland'/'Wales' into 'United Kingdom', 'Unknown' -> ''), then regenerate. Add a 'United States' chip to BeerRegions.countries so the 270 US beers have a home until state attribution exists. Optionally derive the country chip list from live data (distinct feed regions with >= N rows) so picker and data can never drift apart again.

### [OPEN] Foreign brands listed under countries they have no connection to, with the wrong flag
*Surface:* Explore country boards (Germany, Belgium, Brazil, Japan)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:434`  ·  *Found by:* fleet

The Germany board shows Chang (Thai macro lager), 'Ursus premium' (Romanian), and Fischer's 'Bière blonde d'Alsace' (French) - each rendered with a German flag by ExploreView.flag(). Belgium shows 'Cerveza Cruzcampo Especial' (Spanish brand, attached to brewery 'Cristal'). Brazil shows Kunstmann (Chilean) and 'Cerveja Puro Malte' by Spaten-Franziskaner-Bräu GmbH (Munich). Japan shows Peroni Nastro Azzurro (Italian) and Balter (Australian) - Asahi-owned but not Japanese beers to any real person. brewery.country appears to reflect where the OFF product was scanned/sold rather than where the beer is from, which is a direct violation of the 'no beer under a country it has no connection to' law.

**Evidence:** Live top-40 board queries: region='Germany' -> {'Chang Classic Beer', brewery 'Chang', country 'Germany'}, {'Ursus premium','Ursus','Germany'}, {'Bière blonde d'Alsace','Fischer','Germany'}; region='Belgium' -> {'Cerveza Cruzcampo Especial','Cristal','Belgium'}; region='Brazil' -> {'Cerveza Especial Arándano','Kunstmann','Brazil'}, {'Cerveja Puro Malte','Spaten-Franziskaner-Bräu GmbH','Brazil'}; region='Japan' -> {'Peroni Nastro Azzurro','Asahi','Japan'}, {'Balter','Asahi','Japan'}. flag() at ExploreView.swift:434-444 maps the stored country straight to an emoji flag.

**Fix:** Curation pass on brewery.country for the boards' visible rows: build a small mislabel worklist (well-known brand -> true country: Chang=Thailand, Ursus=Romania, Fischer=France, Cruzcampo=Spain, Kunstmann=Chile, Spaten=Germany, Peroni=Italy, Balter=Australia) and apply it as a reviewed migration; going forward, when ingesting OFF products prefer the brand's brewery country over the product's purchase-country tag, and where the true country is unknown leave country blank (row then only appears on Global) rather than inheriting the scan country.

### [OPEN] Same beer appears 3-5 times per board under spelling variants; client dedupe only collapses exact matches
*Surface:* Explore country boards (Japan, Belgium)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:36`  ·  *Found by:* fleet

Japan's 80 rows include 'Asahi Super Dry', 'Super Dry', 'Asahi Super "Dry"' (curly quotes), 'Пиво Asahi Super Dry' (Cyrillic) and 'Super Dry生啤酒' - at least four visibly-identical products survive the client's exact-lowercase dedupe and can render together in the top list. Belgium similarly carries 'Leffe Blonde', 'Blonde' (brewery Leffe), 'Leffe Blond bier blik', and 'Abbeye be Leffe Blond Beer'. To a real person this is the same beer listed repeatedly under typo'd names, on the two boards most likely to be checked at launch.

**Evidence:** Live: SELECT name FROM beer_trend_feed WHERE region='Japan' -> 'Super Dry' x4, 'Asahi Super Dry' x6, 'Asahi Super "Dry"', 'Пиво Asahi Super Dry', 'Super Dry生啤酒', plus 'Asahi' x9. ExploreView.swift:36-37 dedupes only on name.lowercased() exact match, so 'Super Dry' vs 'Asahi Super Dry' vs curly-quote/Cyrillic/CJK variants all remain. The 0065 catalog_search dedupe lane does not apply to beer_trend_feed.

**Fix:** Reuse the 0065 display-name dedupe approach on the trend feed: normalize a dedupe key (strip diacritics/quotes/non-ASCII wrappers, collapse whitespace, prepend brewery when the name omits it) and make the fallback branch DISTINCT ON that key per region, keeping the row with an image/display_name. Client-side stopgap: dedupe on (brewery.lowercased() + normalized name with brewery prefix stripped) instead of raw name.

### [OPEN] The only real vote in production is stranded under region key 'CA' that no board can ever query
*Surface:* Voting -> state boards pipeline  ·  *Anchor:* `supabase/migrations/0055_real_activity_consent_gates.sql:153`  ·  *Found by:* fleet

beer_trend holds exactly two rows, both for the one genuinely-voted beer, under regions 'CA' and 'Global'. Every board key the app can send is a full state name ('California'), so this real community activity is invisible on the California board (which then falls back to the mislabeled Global feed). Root cause: refresh_beer_trend regionalizes votes by user_profile.region_code verbatim, and the live profile row holds the abbreviation 'CA' while onboarding writes full names - two formats in one column with no normalization. Every future user whose region_code lands as an abbreviation will have their votes silently excluded from their state board.

**Evidence:** Live: beer_trend -> [{region:'CA', popularity:1, momentum:1, name:'La saison du chasseur'}, {region:'Global', ...}]; user_profile.region_code values -> {'CA':1, null:1}; beer_trend_feed rows WHERE region='California' -> 0. Picker sends full names (BeerModels.swift:50-61); vote_base at 0055:153-160 uses region_code verbatim. Venue check-in path stores full names ('California' 803 venues), so only the vote path mismatches.

**Fix:** Normalize in one place: inside refresh_beer_trend map 2-letter USPS codes to full state names (a 50-row VALUES lookup) before grouping, and add the same normalization to the profile-save RPC so region_code is stored canonically; backfill UPDATE user_profile SET region_code='California' WHERE region_code='CA'. Then the existing vote immediately surfaces on the California board and future geocoded abbreviations can't strand activity.

### [OPEN] Boards fetch an arbitrary, unstable 40 rows because ordering is momentum-only and every fallback row has momentum 0
*Surface:* Explore country boards (catalog fallback ordering)  ·  *Anchor:* `app/Tapt/Core/BeerService.swift:13`  ·  *Found by:* fleet

BeerService.trends orders by momentum desc with no secondary key and limits to 40. All catalog-fallback rows have momentum=0, so Postgres returns an arbitrary 40 of, e.g., Germany's 1,181 rows - which is exactly why obscure SKUs and the price-string junk surface while flagship beers may never appear, and why board contents can reshuffle between sessions or after any vacuum/plan change. A returning user sees a different 'Top in Germany' with no votes having occurred.

**Evidence:** BeerService.swift:13/:22 .order("momentum", ascending: false).limit(40) with no tiebreaker; live counts: Germany 1,181 / France 3,133 / Belgium 633 fallback rows all momentum=0, popularity=0. The returned German 40 included 'Old Fred Doppelbock' and the Pfand price string while Augustiner appears once and many major brands not at all.

**Fix:** Add deterministic, quality-first tiebreakers to the fetch: .order(momentum desc).order(popularity desc) then a stable quality key - simplest is to add a computed column or view ordering (has image first, then name asc) so the same honest 40 rows return every time and image-backed recognizable beers front the board. One-line client change plus an ORDER BY addition if done in the view.

### [OPEN] The board's 'Heineken' is the 0.0 non-alcoholic variant, labeled 'Sober-curious pick', because dedup rewards the cutout row
*Surface:* Beer Market board / In season tab  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:109`  ·  *Found by:* fleet

The catalog has 40+ name_ok rows display-named 'Heineken' (regular lager, blonde ale variants, NA variants). The per-name dedup picks the highest standing, and the only row with a cutout is the Non-Alcoholic Lager one (+8 notability), so the world's best-known lager appears on the board and ticker represented by its 0.0 variant: style tag 'Non-Alcoholic Lager', reason 'Sober-curious pick'. Any real user reads this as 'Tapt thinks Heineken is a non-alcoholic beer'. Same mechanism picked wrong-provenance Singha/Stone rows (see the country P0) — cutout presence is deciding identity, not correctness.

**Evidence:** Live movers rk17: {symbol HEIN, name Heineken, style 'Non-Alcoholic Lager', reason 'Sober-curious pick', season_fit 2, net 64}. Catalog query over lower(display_name)='heineken': ~45 rows, the only has_cutout=true row is the one with style='Non-Alcoholic Lager'; dozens of regular 'Blonde Ales'/'Lagers' rows at standing 56 lose the distinct-on at 0067 lines 109-119 (order by standing desc).

**Fix:** In the standings CTE, choose the name-cluster representative by identity sanity before presentation: exclude rows whose style matches the NA regex from representing a cluster where the majority of rows are non-NA (and generally prefer the modal style/brewery across the cluster), then apply the cutout preference only among identity-consistent candidates. Longer term this is the canonical merge queue's job, but the representative rule is a one-CTE change that fixes the flagship brands immediately.

### [OPEN] Sober-curious rows still land in the In-season tab (0067 P0-4 residual): NA styles earn season points via the keyword regex
*Surface:* Beer Market — In season tab + board row label  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:82`  ·  *Found by:* fleet

0067 gates season_fit on season_pts>0, but season_pts is computed from a style keyword regex, and 'Non-Alcoholic Lager' contains 'lager', so NA beers score 40 summer points and season_fit=2. Result live: the 'In season' tab ranks Heineken (reason 'Sober-curious pick') inside the in-season block — a tab named In season showing a row whose own label says it is there for sobriety. Compounding it, the app renders ANY reason with a sun icon (isSeasonal = reason != nil), so 'Sober-curious pick' gets a sun on the board row. The same regex coarseness also produces 'Summer beer, in season now' on Sierra Nevada Celebration Fresh Hop IPA — a famous November-January seasonal — via its 'Pale Ales' style tag.

**Evidence:** Live: HEIN row has reason='Sober-curious pick' AND season_fit=2, standing 64 → sorts inside the season block (season sort = season_fit*1000+standing). 0067:82 summer regex 'ipa|pale|wheat|...|lager|...' matches 'Non-Alcoholic Lager'; 0067:97 assigns the sober reason first but 0067:125 sets season_fit purely from season_pts. Sun icon for any reason: app/Tapt/Features/Market/BeerMarketView.swift:108-112 (Label(b.moveReason, systemImage: "sun.max.fill") gated only on isSeasonal). Celebration Fresh Hop IPA at movers rk38 with reason 'Summer beer, in season now'.

**Fix:** In the scored CTE, guard season_pts with the same NA regex used for the reason ('case when style ~* NA-pattern then 0 else <season match> end') so sober-curious rows get season_fit=0 and leave the In-season tab; in the app, pick the row-label icon by reason type (sun only for '...in season now', a leaf/zero icon for sober-curious). The Celebration case needs a small seasonal-brand exception list or a name-keyword check ('celebration|festive|christmas|winter' overrides the style regex) — cheap and honest.

### [OPEN] A voted beer can silently lose the per-name dedup to an unvoted twin, hiding the vote while the board twin says 'No votes yet'
*Surface:* Beer Market board (vote integrity)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:109`  ·  *Found by:* fleet

0067's contract states a beer with a real vote must ALWAYS be on the board, but the votes-exist clause only affects the base gate; the later distinct-on picks one row per display name by standing. A bare voted row scores 18-32 (10 base + 8/net-vote + notability) while a presentable twin with style+image scores 56-64, so votes 1 through roughly 5 on a duplicate-named beer vanish from the board entirely — and the surviving twin's detail sheet shows 'No votes yet. Be the first to weigh in.' to the very user who just voted. The reach path is proven live: today's real Starkbier vote is on beer bc5da975 while the board's 'Starkbier' is a different row (f264dba4, Feldschlösschen). This particular instance self-corrects at the next 30-min refresh because the incumbent's standing is only 16, but for any big-brand cluster (Heineken, Budweiser, Stella all have dozens of twins at 56-64) the vote would be swallowed indefinitely, breaking the market's core promise.

**Evidence:** Live: beer_vote has 2 rows; standing table shows only 1 voted beer. The 01:31:35Z Starkbier vote (beer bc5da975, style null) is not on the board; board Starkbier is f264dba4 (standing 16, votes 0). Math from 0067:109-119: distinct on (lower(dname)) order by standing desc — voted bare row max 10+8+8+6=32 loses to any style+image summer twin at 10+40+8+6=64 until net_votes*8 closes the gap (~5 votes). Detail copy 'No votes yet. Be the first to weigh in.' at app/Tapt/Features/Market/MarketBeerDetailView.swift:138.

**Fix:** Aggregate votes across the name cluster instead of per row: join vote_agg/vol_agg grouped by lower(display_name) (sum net_votes/votes/ups/downs across all catalog rows sharing the name) so every vote counts toward the board row regardless of which barcode variant the user voted on; keep distinct-on for presentation only. This also fixes the related identity-flip (the board row swapping brewery/style overnight when a voted twin overtakes the incumbent).

### [OPEN] Six sort tabs render essentially one list: Gaining/Sliding do not filter by sign and 'Top movers' sorts by standing, not movement
*Surface:* Beer Market sort tabs  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:178`  ·  *Found by:* fleet

With all 4,908 rows at change_24h=0 (verified live), the movers, gainers, and losers sorts return byte-identical top lists, and active/top differ only by the single voted beer at #1. A user flipping between 'Gaining' and 'Sliding' sees the exact same beers in the same order, every one marked 'steady' — opposite-named tabs with identical content read as broken. This persists by design even when data arrives: 'losers' is just change ascending (zero-change rows fill it whenever fewer than 40 beers declined), 'gainers' includes zero-change rows, 'top' (Top voted) fills with votes=0 rows, and the default 'Top movers' tab orders by standing (a level), so a +20 mover will rank below a static high-standing beer.

**Evidence:** Live: beer_market('gainers',10), ('losers',10), ('movers',10) return identical rows 1-10 (ALLA, BUDW, TIGE, SING, TSIN, MOSK, PILS, KRON, LAGU, DELI), all change=0; ('active',10) and ('top',10) are the same list with LASA prepended. Standing table: nonzero_change=0 of 4908. Sort SQL 0067:178-186: 'movers' falls to st.standing; no where-clause on change sign for gainers/losers, none on votes_count for top. Tab titles at app/Tapt/Core/MarketService.swift:60-68.

**Fix:** In beer_market(): for 'gainers' add 'and st.change_24h > 0', for 'losers' 'and st.change_24h < 0', for 'top' 'and st.votes_count > 0', for 'active' 'and st.vol24 > 0' (the app already has an honest empty state — 'The board is warming up' — that renders when a filtered tab returns nothing, though a tab-specific line like 'Nothing moved today yet' would be better); sort 'movers' by abs(st.change_24h) desc with standing as tiebreak, or rename the default chip from 'Top movers' to 'The Board' since it is the standing ranking.

### [OPEN] Generic retail strings and junk brewery names pass the listable gate onto the flagship board
*Surface:* Beer Market board (default top 40)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:42`  ·  *Found by:* fleet

The default top-40 board a first-time user sees includes: 'biere IPA' (lowercase generic), 'Bière spéciale' (Marque Repère is E.Leclerc's store label — the 'name' is a shelf descriptor, not a beer), bare 'Blond' and 'Blonde' as complete beer names on adjacent rows, 'Cerv Patagonia Lt , Ipa' (truncated retail string with a stray ' , '), 'Moska ipa' casing, and brewery strings 'Flasche' (German for 'bottle'), 'Acrobräu Moos' (typo of Arcobräu, contradicting its own beer name 'Arcobräu Moos' one field over), 'BIRRA MORATTI' (misspelled all-caps). These read as scraped junk and directly violate the data-must-make-sense law on the surface with the most eyeballs.

**Evidence:** Live movers top-40: rk27 'Arcobräu Moos'/brewery 'Acrobräu Moos'; rk30 'biere IPA' (La bellecombaise); rk32 'Bière spéciale' (Marque Repère); rk34 'Blond' (Affligem) and rk35 'Blonde' (Grimbergen) adjacent; rk39 'Cerv Patagonia Lt , Ipa'; rk14 Sapporo/brewery 'Flasche'; catalog row 'BIRRA MORETTI 33 CL' → brewery 'BIRRA MORATTI'. All name_ok=true, so tapt_name_ok admits them.

**Fix:** Add a market-listability tier above tapt_name_ok used only by refresh_beer_market_standing: reject names that are purely generic style/descriptor words (blond, blonde, biere/bière + style word, 'spéciale', cerveza/cerv fragments), strip dangling ' , ' and size tokens, and require display casing normalization; apply the same gate to the brewery string before storing it in beer_market_standing (null it when it fails — the app already hides empty brewery). Keep these rows in search/scan; just do not let them anchor the flagship board.

### [OPEN] 'Non Alcoholic Beers' style label sits next to 4.5-7.2% ABV on 11 full-strength beers
*Surface:* Catalog rows + beer page style chip  ·  *Anchor:* `scripts/ingest_off_csv.py:49`  ·  *Found by:* fleet

Carlsberg ELEPHANT shows style 'Non Alcoholic Beers' with 7.2% ABV; 1664 Gold 6.1%, Grimbergen Pale Ale 5.5%, 1664 Rose 4.5%, and 7 more. In the catalog row the style text and ABV chip sit side by side; on the beer page they render as adjacent chips in the header. That is a direct same-screen contradiction (law 3), and for anyone avoiding alcohol it is dangerous-looking misinformation. The is_na_low flags are correct (verified 0 rows with is_na_low and abv >= 1.0, so the No/Low filter is honest post-0077) - only the visible style STRING is wrong, inherited from an OFF category tag. Note the catalog dedupe prefers rows with a non-null style, so the wrong-labeled variant is exactly the one that wins visibility (verified: browse shows 1664 Gold with 'Non Alcoholic Beers' while its two style-null twins are hidden).

**Evidence:** Live: select display_name, style, abv, is_na_low from beer_catalog where name_ok and style ilike '%non alcoholic%' and abv >= 1.0 -> 11 rows, top: ('Carlsberg ELEPHANT','Non Alcoholic Beers',7.20,false), ('1664 Gold','Non Alcoholic Beers',6.10,false), ('Grimbergen Pale Ale','Non Alcoholic Beers',5.50,false). Re-verified after live migration 0077_no_low_consistency - still present.

**Fix:** One-off data fix plus ingest guard: update beer_catalog set style = null where style ilike '%non alcoholic%' and abv >= 1.0 (blank beats wrong), and in style_from()/the ingest upsert refuse an NA-family style tag whenever the row's ABV is >= 1.0. The catalog dedupe ordering then automatically promotes a sibling row with a sane style where one exists.

### [OPEN] Junk style strings render as style chips: '5 Beer' on 128 beers, a raw barcode, '105', 'Guiness'
*Surface:* Catalog rows + beer page style chip  ·  *Anchor:* `supabase/migrations/0053_beer_detail_sensory_fields.sql:19`  ·  *Found by:* fleet

The style column holds OFF category-tag artifacts that render verbatim wherever the BJCP resolver fails: '5 Beer' (128 beers), '5 5 Beer', '0 Beer', '4 Beers', '105', 'Guiness' (a misspelled brand as a style), and the style '8941189600266' - a raw 13-digit barcode shown as a beer style. A user saw 'Guinness draugt stout - 5 Beer' in the live 'guinness' search I ran. beer_detail falls back to this raw string for the header chip (coalesce(sr.style_name, nullif(btrim(b.style),''))), so beer pages show '5 Beer' as the style. Numbers-as-styles is the same class of junk the name gate (task 63) was built to hide, but styles have no equivalent gate.

**Evidence:** Live: select style, count(*) from beer_catalog where name_ok and (style ~ '^\s*[0-9]' or style ilike 'guiness' or length(btrim(style)) <= 2) group by 1 -> ('5 Beer',128), ('5 5 Beer',2), ('4 Beers',1), ('Guiness',1), ('0 Beer',1), ('8941189600266',1), ('105',1), ('2 8 Stout Beer Brewed In The Uk',1). catalog_search('guinness') visibly returned rows styled 'Guiness' and '5 Beer'.

**Fix:** Add a tapt_style_ok-style gate (mirror of tapt_name_ok): treat styles that are numeric-leading, digit runs, <= 2 chars, or known brand misspellings as null at read time in catalog_search and beer_detail (nullif via a small immutable fn), and null them in the data with a one-off update. 136 rows change; beers keep their BJCP-resolved style_name where the resolver already succeeds.

### [OPEN] catalog_search has zero query relevance - canonical beers rank behind junk for their own brand searches
*Surface:* Catalog search ranking  ·  *Anchor:* `supabase/migrations/0066_materialize_display_names.sql:39`  ·  *Found by:* fleet

Result order is (has image, has brewery, has abv, has style, alphabetical) with no text-match ranking at all. Searching 'guinness' ranks 'Bier "Irish Red Ale' (a mislabeled row with an unbalanced quote) #1 and the canonical 'Guinness Draught' (Irish Stout, 4.2%, imaged, BJCP-resolved) #8; the ALDI price-string row also makes the first screen. Searching 'ipa' returns an alphabetical wall of French grocery SKUs ('Biere blonde IPA' x3, 'Biere IPA', ...) with famous beers like All Day IPA buried mid-list; default browse opens on '11 Paralleli', '111 Zwickl', '13 Guns' because digits sort first. A search where the exact-brand match loses to alphabetical junk reads as broken to a real user. pg_trgm similarity() is already installed and used by match_beers, so a relevance term is cheap.

**Evidence:** Live catalog_search def (post-0078) orders by (image_url is null),(brewery_name is null),(abv is null),(style is null),lower(name) - p_query never influences rank. Live run: catalog_search('guinness') rows 1-7 are 'Bier "Irish Red Ale', 'Biere Brune Draught GUINNESS', 'Draught', 'Draught Stout', 'Foreign Extra Stout', 'Guiness Original', 'Guinness' - 'Guinness Draught' is 8th.

**Fix:** Prepend relevance terms to the ORDER BY when p_query is non-empty: exact display_name match first, then prefix match (display_name ilike p_query||'%'), then similarity(display_name, p_query) desc (pg_trgm already installed), keeping the completeness buckets as tie-breakers. Ship as a mirrored migration replacing the live definition; verify 'guinness' puts Guinness Draught in the top 3.

### [OPEN] Scan matches show the same beer up to five times at 100% plus garbled rows, because match_beers has no display-name normalization, no name_ok gate, and no dedupe
*Surface:* Scan result sheet (match list)  ·  *Anchor:* `supabase/migrations/0005_release_hardening.sql:30`  ·  *Found by:* fleet

match_beers returns raw beer_catalog.name with no tapt_name_ok filter and no dedupe, unlike every other catalog surface. Scanning a common beer shows a wall of near-identical rows differing only in letter case, each at '100%', plus corrupted catalog rows. A real user scanning a 1664 Blanc sees: '1664 blanc' three times, '1664 Blanc', '1664 BLANC' (no brewery), and a row literally named 'Wheat Beer' whose brewery is '1664 Blanc' and country Denmark (name/brewery swapped in the source row). Picking any of them logs a raw name that then renders in the Cellar. This is the hero scan loop looking broken on its most common path.

**Evidence:** Live select from match_beers('1664 blanc', 8): rows '1664 blanc' x3 (conf 1.00), '1664 Blanc' (1.00), '1664 BLANC' (1.00, brewery null), 'Wheat Beer' (brewery '1664 Blanc', country 'Denmark', conf 1.00), '1664 Blanc Rosé' (0.69), '1664 Blanc, hveteøl' (brewery 'RINGNES AS', country France, 0.58). Function body (0005:30-74) selects b.name raw, no name_ok/display_name, no distinct. ScanView.swift:346 displays this list verbatim.

**Fix:** Rewrite match_beers to select display_name, filter where name_ok, and dedupe with distinct on (lower(display_name), brewery normalization) keeping the best-equipped row (same pattern as live catalog_search), preserving the GTIN-exact fast path. Ship as a migration mirrored in supabase/migrations and re-test the scan sheet with a common barcode and name.

### [OPEN] Passport country stamps use brewery.country, which is the market where the product was scanned, not the beer's origin: logging a German Schlenkerla lights up France
*Surface:* Passport countries (Cellar + PassportView)  ·  *Anchor:* `app/Tapt/Core/CheckinService.swift:98`  ·  *Found by:* fleet

When no venue is attached (today: always, given the venue RLS bug), passportCountry falls back to the beer's brewery country. The OFF-ingested brewery.country is the sale market of the scanned product, so famous beers carry the wrong country: Schlenkerla (Bamberg) is France, Daniel Thwaites (UK) is France, Zichovec (Czech) is France, Waterloo (Belgian) is France, RINGNES (Norway) is France, a BrewDog SKU is Australia. A user logs a German rauchbier at home and watches the France flag light up in their Passport and the countries stat increment for a country the beer has no connection to. The stamp is wrong the moment it is earned.

**Evidence:** CheckinService.swift:98 'var passportCountry: String { venueCountry.isEmpty ? country : venueCountry }' where country = beer.brewery.country. Live catalog_search top-60 sample: '13 Guns'/Daniel Thwaites -> France; '17 Zhytnytsia Yevropy'/Zichovec -> France; 'Aecht Schlenkerla Rauchbier Märzen'/Brauerei Heller -> France; '7 Triple Blond'/Waterloo -> France; 'Aldipa Bier'/Brewdog -> Australia; match_beers sample: '1664 Blanc, hveteøl'/RINGNES AS -> France.

**Fix:** Stop counting brewery.country as a Passport 'country' unless the venue is absent AND the brewery country is trustworthy; short term, only stamp countries from venue.external_ids->>'country' (real place the pour happened) and label the beer-origin fallback separately or not at all; medium term, backfill brewery origin country from a real source (Catalog.beer / OBDB) before re-enabling the fallback. Blank beats invented stamps.

### [OPEN] Default beer list still surfaces junk SKU names, brand-as-brewery duplicates, and NA-style rows with 6%+ ABV
*Surface:* Log a pour (default picker list)  ·  *Anchor:* `app/Tapt/Features/Cellar/LogPourView.swift:70`  ·  *Found by:* fleet

The first screen of the log picker (catalog_search top 60) contains rows a real person immediately distrusts: '1664 Can 1664 Hd' (SKU fragment), '2,5 Original Lemon', '5,0 Original Pils' attributed to a brewery named '0 Original' (a parsing fragment of the product name), '7SUL BİERE ABBAYE LEFFE', and the same beer listed twice under two breweries because the live catalog_search dedupes per (display_name, brewery) and brand-as-brewery duplicate rows survive: '3 Monts' appears under 'Brasserie de Saint-Sylvestre' and again under brewery '3 Monts'; '8.6 Original' under 'Bavaria' and under '8.6 ORIGINAL'. Also mislabeled styles produce contradictions that reach the share card: '1664 Gold' is styled 'Non Alcoholic Beers' with abv 6.10 (and shows 6.1% next to that style on the PourCard). Note: the US-catalog thinness itself is already tracked (docs/21 P2-1) and excluded here; these are dedupe/name-gate defects visible on the default list regardless of market.

**Evidence:** Live catalog_search(null,null,false,60,0) output includes: {'1664 Can 1664 Hd'}, {'5,0 Original Pils', brewery '0 Original'}, {'7SUL BİERE ABBAYE LEFFE', brewery 'Inbev'}, {'2,5 Original Lemon', brewery 'Original'}, {'3 Monts'} twice (byte-identical display names, hex 33204d6f6e7473, different brewery_id), {'8.6 Original'} twice, {'1664 Gold', style 'Non Alcoholic Beers', abv 6.10}, {'1664 Rose', style 'Non Alcoholic Beers', abv 4.50}. Live function def partitions by (lower(display_name), coalesce(brewery_id, lower(brewery name))).

**Fix:** Two-part: (1) tighten tapt_name_ok/tapt_display_name for pack-fragment patterns ('Can ... Hd', leading 'N,N ' decimals, all-caps retailer strings) and recompute the generated columns; (2) collapse brand-as-brewery duplicates either by merging duplicate brewery rows via canonical_merge_queue (overlaps docs/21 P1-2) or by making catalog_search's partition key display-name-only when one of the colliding breweries' names is a substring of the display name; separately null the style on rows where style='Non Alcoholic Beers' and abv >= 1.0 so the contradiction cannot render.

### [OPEN] Venue search only covers a daily-rotating 800 of 8,694 venues, so most real breweries are unfindable at log time
*Surface:* Log a pour (brewery/taproom picker)  ·  *Anchor:* `app/Tapt/Features/Cellar/LogPourView.swift:76`  ·  *Found by:* fleet

LogPourView loads WorldBeerService.breweryMap(limit: 800) once and does client-side filtering over that array. brewery_map_feed orders by heat_score desc then md5(id || current_date), a daily shuffle, and with zero checkins and few taps nearly all 8,694 venues tie at heat 1, so the 800 the picker can search is essentially a random daily sample (~9%). A user typing their local taproom's exact name usually gets 'No brewery match yet. You can still log the pour.' even though the venue exists in Tapt, and the same search may work tomorrow and fail the day after. The search field promises search; it delivers a lottery.

**Evidence:** LogPourView.swift:76 'venues = (try? await WorldBeerService.breweryMap(limit: 800)) ?? []' and venueMatches() (279-299) filters only that array. Live: select count(*) from venue = 8,694 (5,491 US). Live brewery_map_feed def: 'order by 9 desc, md5(v.id::text || to_char(now(), ''YYYY-MM-DD'')) limit least(greatest(coalesce(p_limit,500),1),1000)' with heat = checkins*3 + taps + seed bonus (all ~1 today).

**Fix:** Use the existing search_venues RPC (or a new venue_search) driven by the venueSearch text with debounce, exactly like the beer picker's server search, keeping the 800-venue prefetch only as the empty-query suggestion list. This also honors the docs/21 P1-12 note about fetching venues on field focus.

### [OPEN] Menu matching at 0.3 similarity turns non-beer menu lines into confident-looking beer matches
*Surface:* Scan (Match menu mode)  ·  *Anchor:* `app/Tapt/Features/Scan/ScanView.swift:331`  ·  *Found by:* fleet

The 'Match menu' button batch-matches every visible camera text line and accepts the best hit at confidence >= 0.3. Ordinary menu section headers become matches: 'HAPPY HOUR' matches a beer named "Happy'A !" at 50%, 'DRAFT BEERS' matches a catalog row literally named 'draft' (brewery Tsingtao) at 50%, 'COCKTAILS' matches 'B-52 Cocktail Stout' at 36%. A user pointing the camera at a menu gets a result sheet asserting beers the menu never listed, each one tap away from being logged as a real pour with (per the other scan bug) a pre-filled 4-star rating.

**Evidence:** ScanView.swift:331 'if let hits = try? await CheckinService.matchScan(line), let best = hits.first, best.confidence >= 0.3'. Live: match_beers('HAPPY HOUR',1) -> "Happy'A !" conf 0.50; match_beers('DRAFT BEERS',1) -> 'draft' (Tsingtao) conf 0.50; match_beers('COCKTAILS',1) -> 'B-52 Cocktail Stout' conf 0.36.

**Fix:** Raise the menu-mode acceptance threshold to ~0.6, skip lines matching a stop-list of menu vocabulary (happy hour, cocktails, wings, draft, pitcher, food, prices with $), require at least two words or one brewery-name hit, and visually mark sub-0.8 matches as 'low confidence' in the sheet so the user confirms rather than trusts.

### [FIXED this round] No dedupe anywhere in the beers leaderboard path — 1,584 duplicate catalog rows can produce visually identical ranked entries
*Surface:* Leaderboards > Beers board  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:93`  ·  *Found by:* fleet

leaderboard_beers ranks per beer_id with no grouping by display name, and LeaderboardsView renders rows verbatim. The live catalog contains 558 (tapt_display_name, brewery_id) pairs with more than one row (1,584 rows total): 'Holsten Pilsener Premium' exists twice under the same Holsten brewery, 'Peroni' has 14 rows under brewery Peroni, 'Heineken' 46 rows, 'Punk IPA' 14 under Brewdog, 'Staropramen' 15. As soon as two SKU rows of the same beer each collect a vote or pour (Explore's vote list surfaces these same catalog rows), the podium shows two rows with identical name, brewery, style, and country — the exact duplicate-entries complaint the owner raised (task #57). ExploreView already acknowledges and fixes this for its own list ('The catalog has multiple SKUs per beer -- collapse to one row per name', visibleBeers dedupe), but the flagship leaderboard never got the same treatment. The board is clean today only because prod votes were cleared on 2026-07-11.

**Evidence:** Live query: `select count(*) dup_pairs, sum(n) dup_rows from (select tapt_display_name(name), brewery_id, count(*) n from beer_catalog where tapt_name_ok(name) group by 1,2 having count(*)>1) t` → dup_pairs=558, dup_rows=1584. Holsten query shows two rows named 'Holsten Pilsener Premium' (ids 86ab30a6… and ec76eb8b…) with the same brewery_id. supabase/migrations/0051_leaderboard_clean_names_styles.sql:8-22 has no GROUP BY on display name; LeaderboardsView.swift:93 ForEach renders rows 1:1. Contrast ExploreView.swift:35-38 which dedupes by lowercased name.

**Fix:** Dedupe in the SQL, not the client: in leaderboard_beers, aggregate beer_score by (tapt_display_name(b.name), b.brewery_id) — sum ups/downs/checkins, pick a canonical beer_id (e.g. the row with a cutout_url, else lowest id) for navigation and image — then rank the aggregates. That keeps every cast vote counted while showing one honest row per real-world beer, and fixes the board for all clients without an app release. Longer term, fold the SKU merge into the catalog normalization pipeline (task #55) so votes land on one canonical row.

### [OPEN] Styles board ranks raw OFF category strings — 'Craft Beers', '5 Beer', 'Beers From Germany' will appear as beer styles
*Surface:* Leaderboards > Styles board  ·  *Anchor:* `supabase/migrations/0009_superapp_foundations.sql:469`  ·  *Found by:* fleet

leaderboard_styles groups by the raw checkin_event.style snapshot, and the checkin RPC copies beer_catalog.style verbatim at pour time. The catalog's most common raw styles are Open Food Facts category junk, not styles: 'Craft Beers' (827 rows), 'Lagers' (705), 'Beers From Germany' (302), 'Lithuanian Beers' (256), 'Organic Beers' (253), 'Non Alcoholic Beers' (228), '5 Beer' (139), 'Sweetened Beverages' (42), 'Industrial Beer' (39). Migration 0051 routed the BEERS board through beer_style_reference/tapt_ref_style_name precisely to kill these ('no more Pale Ales/Craft Beers/Sodas' per its own comment) but the styles board was never given the same resolver — so the same pour that shows as 'Saison' on the beers board is tallied as 'Craft Beers' on the styles board, and a user's first pours will put '5 Beer' or 'Beers From Germany' on a board titled Styles. Board is empty today (prod checkins cleared), so this is a guaranteed first-use defect, not a current display.

**Evidence:** Live def of leaderboard_styles: `select ce.style, count(*)::int ... from checkin_event ce where coalesce(ce.style,'') <> '' group by ce.style` — no resolver. 0007_backend_contract_and_content_pipeline.sql:389 inserts `v_beer.style` raw into checkin_event.style. Live catalog styles: Craft Beers=827, Beers From Germany=302, 5 Beer=139, Sweetened Beverages=42, Industrial Beer=39. 0051:2 comment confirms these names were already deemed junk for the beers board.

**Fix:** Redefine leaderboard_styles to resolve through the same machinery as the beers board: group by coalesce(sr.style_name, ce.style) via `left join beer_style_reference sr on sr.style_name = tapt_ref_style_name(ce.style, '')`, and exclude rows whose resolved name is still a known category string (a small denylist: values ending in 'Beers', 'Beverages', matching '^[0-9]+ Beer$', etc.). Better still, resolve style at checkin-write time (store both raw and resolved) so the board and future features read clean data.

### [OPEN] Row subtitles surface junk metadata where style and country belong: '5 Beer', 'Lithuanian Beers', country 'Unknown'/'World', Czechia/Czech Republic split
*Surface:* Leaderboards > Beers board row subtitles  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:102`  ·  *Found by:* fleet

The beers-board subtitle renders brewery + style + country straight from the RPC. The style fallback `coalesce(sr.style_name, nullif(btrim(b.style),''))` still passes raw junk through whenever the resolver misses: live counts among name_ok beers show 'Craft Beers' unresolved for 486 rows, 'Lithuanian Beers' 228, 'Beers From Germany' 130, '5 Beer' 102, 'Sweetened Beverages' 32, 'Industrial Beer' 27 — so a voted beer can read 'Brasserie X  5 Beer  France', a nonsense phrase where a style belongs. Country comes from brewery.country raw, whose live values include 'Unknown' (32 name_ok beers), 'World' (2), and both 'Czech Republic' (82) and 'Czechia' (51) — the same country under two names also silently inflates the tasters board's 'countries' count for anyone who drinks beers from both labelings. Additionally 914 name_ok beers have neither brewery nor style, which renders an empty subtitle line under the beer name (ExploreView shows 'Community pick' in this case; LeaderboardsView has no fallback).

**Evidence:** LeaderboardsView.swift:102 `[beer.breweryName, beer.style, beer.country].compactMap{$0}.filter{!$0.isEmpty}.joined(separator: "  ")`. Live queries: unresolved-style counts (Craft Beers shown as 'Craft Beers' for 486 rows, '5 Beer'→'5 Beer' 102, Lithuanian Beers 228, Sweetened Beverages 32, Industrial Beer 27); brewery countries: Czech Republic=82 beers, Czechia=51, Unknown=32, World=2; orphan metadata: no_brewery_no_style=914 of 10,288 name_ok beers. 0051:10 is the fallback expression.

**Fix:** In leaderboard_beers, null out the style when the resolver misses AND the raw value matches the category-junk pattern (endswith 'Beers'/'Beverages', '^[0-9]+ Beer$', 'Industrial Beer'), and null out country when it is 'Unknown' or 'World'; run a one-time UPDATE normalizing brewery.country 'Czech Republic'→'Czechia' (or vice versa, one canonical value). In LeaderboardsView, add the same 'Community pick' fallback ExploreView uses when the subtitle would be empty, and join parts with ' · ' to match the rest of the app.

### [OPEN] Tasters empty-state copy claims 'Styles and countries count more than volume' but the ranking is pours-first
*Surface:* Leaderboards > Tasters board  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:137`  ·  *Found by:* fleet

The empty state tells users what earns rank: 'Log pours to claim the top spot. Styles and countries count more than volume.' The live leaderboard_tasters function orders by pours DESC first (order by 5 desc, 6 desc, 2) — raw volume is the primary key, styles only break ties, countries never factor into ordering at all. The board's big trailing number is also pours. A user who chases breadth because the copy told them to will be outranked by anyone who logs more total pours, and the numbers on screen (pours ranked top-to-bottom) visibly contradict the sentence that introduced the board. This is a stats-contradict-each-other violation of product law 3 on the exact surface that is supposed to explain itself.

**Evidence:** LeaderboardsView.swift:137 message: "Log pours to claim the top spot. Styles and countries count more than volume." Live def of leaderboard_tasters: `order by 5 desc, 6 desc, 2` where column 5 = pours, 6 = styles; countries (7) is absent from the ORDER BY.

**Fix:** Pick one and align both sides. Either change the copy to the truth ('Most pours logged takes the top spot; styles break ties') — one-line app change — or, if breadth-first is the intended product, change the ORDER BY to a breadth-weighted key (e.g. styles desc, countries desc, pours desc) and make the trailing metric match the primary sort so the displayed number explains the rank.

### [OPEN] Network failures render as dishonest 'The podium is open' empty states — errors are swallowed everywhere
*Surface:* Leaderboards (all three boards)  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:220`  ·  *Found by:* fleet

load() wraps all three RPCs in `(try? ...) ?? []`, and the No/Low toggle does the same inline. Any failure (offline, 401 after session loss, Supabase hiccup) produces empty arrays, and the view then asserts community facts that are false: 'The podium is open … Vote beers up or down on Explore', 'No tasters ranked yet', 'No style trends yet'. A user with real votes on the board who opens it in a dead spot is told the community has zero activity; toggling No/Low offline silently wipes a populated board and replaces it with 'The zero-proof podium is open'. The whole point of yesterday's market-honesty pass (0067) was that empty claims must be true; this view cannot distinguish 'no data' from 'failed to load'. The hero badge also permanently says 'LIVE' even when every fetch failed.

**Evidence:** LeaderboardsView.swift:223-225 `async let b: [LeaderBeer] = (try? LeaderboardService.beers(naOnly: naOnly)) ?? []` (same for tasters/styles); :71 `Task { beers = (try? await LeaderboardService.beers(naOnly: naOnly)) ?? [] }`; :83-91 empty state claims 'The podium is open … the first movers write the leaderboard'; :19 metric: "LIVE" is a constant.

**Fix:** Track a loadFailed flag per load: on thrown error, keep the previous rows if any and show a plain failure row with a Retry button ('Could not load the boards. Retry.') instead of the empty states; only show 'The podium is open' when the RPC actually returned zero rows. For the No/Low toggle, revert the toggle and show the same failure note on error rather than assigning []. Drop or condition the 'LIVE' hero badge on a successful load.

### [OPEN] Hidden rank formula (net + 2x pours) plus the net<>0 cutoff makes displayed stats look mis-sorted, vanishes contested beers, and can give gold to a downvoted beer
*Surface:* Leaderboards > Beers board ranking  ·  *Anchor:* `supabase/migrations/0051_leaderboard_clean_names_styles.sql:18`  ·  *Found by:* fleet

Rows display ups, downs, and pours, but rank order is the undisclosed score net + 2*checkins. Three user-visible oddities follow, matching the owner's 'stat cutoffs look wrong' complaint: (1) a beer showing 6 up / 3 pours (score 12) outranks one showing 10 up (score 10) — the visible thumbs count appears mis-sorted and nothing on screen explains the pour weighting; (2) the WHERE cutoff `s.net <> 0 or s.checkins > 0` deletes any beer whose votes cancel out — a beer with 3 up and 3 down and no pours (6 real community actions) disappears from the board entirely while a beer with a single up-vote ranks; (3) net<0 rows pass the same filter, so with today's sparse data a beer whose only signal is one thumbs-down would render at rank #1 with the gold badge and gold border (rank<=3 styling is positional, not merit-based). All three make the board's numbers look broken or dishonest to a careful reader.

**Evidence:** 0051:18 `where (s.net <> 0 or s.checkins > 0)`; :21 `order by (s.net + s.checkins * 2) desc, b.name`. LeaderboardsView.swift:212-218 rankBadge gives gold fill to ranks 1-3 unconditionally; :121 gold stroke for i==0; :106-116 shows ups/downs/pours with no explanation of weighting. Live board currently has 1 row (1 up / 0 down), so any second beer receiving only a downvote would immediately take rank #2 styling; a 3-up/3-down beer returns zero rows under the current WHERE (verified against the live function definition).

**Fix:** Change the visibility filter to `(s.ups + s.downs) > 0 or s.checkins > 0` so equally-contested beers stay on the board, and gate the gold podium styling on positive net (rank<=3 AND netVotes>0) so a downvoted beer can never wear the trophy look. Explain the rank in one honest caption under the board picker ('Ranked by net votes; each logged pour counts double') — one Text line — or simplify the formula to net votes only and show pours as pure context.

### [OPEN] Votes are attributed to user_profile.region_code, which never matches the board vocabulary — the platform's only real vote is stranded on an unreachable 'CA' board
*Surface:* Vote → state board pipeline (refresh_beer_trend + region_code)  ·  *Anchor:* `supabase/migrations/0055_real_activity_consent_gates.sql:153`  ·  *Found by:* fleet

refresh_beer_trend's vote_base attributes each vote to the voter's user_profile.region_code verbatim. Live, the only two profiles have region_code '' and 'CA' — neither matches any picker value (the app queries the full name 'California'), so the one real vote in production produced a beer_trend row region='CA' that no screen can ever display; it only surfaces via the Global rollup. Compounding it: onboarding preselects 'Global' as home base, and detectHomeState changes only the local @AppStorage homeRegion — it never syncs region_code — so a user auto-defaulted to the 'New Jersey' board votes there, watches the number bump (optimistic applyVoteDelta), and the vote vanishes from that board on the next load because it was attributed to 'Global' (or a legacy code). State boards can structurally never accumulate the votes cast on them.

**Evidence:** Live: `select region_code, count(*) from user_profile group by 1` → {'(empty)':1, 'CA':1}; `select * from beer_trend_feed where popularity<>0` → region 'CA' + 'Global' rows for 'La saison du chasseur'. Code: vote_base CTE `coalesce(nullif(up.region_code, ''), 'Global') as region`; app queries `.eq("region", value: region)` with full names (BeerService.swift:21); detectHomeState (ExploreView.swift:467-488) writes homeRegion only, never ProfileService.setRegion (which has zero callers — dead code at ProfileService.swift:13).

**Fix:** Normalize once at the pipeline seam: in refresh_beer_trend, map 2-letter region_code through region_beer_guide.state_code to the full state name (and pass anything already matching BeerRegions vocabulary through), so legacy codes stop stranding votes. In the app, call ProfileService.setRegion when detectHomeState resolves a state and when the user changes home region, so votes follow the board the user actually lives on. Backfill: update the existing 'CA' profile row to 'California'.

### [OPEN] Home-state detection silently fails for 14 states — region_beer_guide has only 36 of 50 state rows and detection depends on it
*Surface:* detectHomeState (Explore auto-region)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:477`  ·  *Found by:* fleet

CLGeocoder returns two-letter administrativeArea codes for US placemarks, so detectHomeState's primary full-name match rarely fires and detection falls through to `guides.first { $0.stateCode == area }`. region_beer_guide contains only 36 state rows; Pennsylvania, Ohio, Illinois, Florida, Georgia, North Carolina, Washington, Arizona, Missouri, Minnesota, Oklahoma, Alabama, Alaska, and Delaware are missing — users in those states (over a third of the US population, including major beer states like PA and NC) grant location and nothing happens, with no feedback. It also races loadGuides: both run as parallel .task blocks, so if location resolves before the guides fetch, the lookup runs against an empty array even for covered states.

**Evidence:** Live: `select name, state_code from region_beer_guide where scope='state'` returns 36 rows; missing AL, AK, AZ, DE, FL, GA, IL, MN, MO, NC, OH, OK, PA, WA. Code: lines 477-479 `detected = BeerRegions.states.first { $0 == area } ?? guides.first { $0.scope == "state" && $0.stateCode == area }?.name`; guides loaded independently in `.task { await loadGuides() }` (line 81) with no ordering guarantee versus `.task { await detectHomeState() }` (line 82).

**Fix:** Put a static 50-entry code→name dictionary in BeerRegions and resolve administrativeArea locally, removing the dependency on the fetched guides for detection (keep guides for editorial copy only). Await loadGuides() before the guide-based fallback if it stays. Separately seed the 14 missing state guide rows so guide-mode hero copy exists for every pickable state.

### [OPEN] Picker/data vocabulary mismatch: no 'United States' board despite 270 US rows, Czechia board misses the 82 beers filed under 'Czech Republic', and data-rich countries (Lithuania 288, Croatia 195, Switzerland 88) have no chip
*Surface:* Region picker vs live data coverage  ·  *Anchor:* `app/Tapt/Core/BeerModels.swift:62`  ·  *Found by:* fleet

BeerRegions.countries (23 entries) was hand-picked and does not match where the catalog actually has beers. (a) 'United States' is not a pickable region, yet 270 beers carry region 'United States' — combined with the empty state boards, a US user has NO honest way to browse American beers by region. (b) brewery.country is unnormalized free text: 82 beers sit under 'Czech Republic' while the picker only offers 'Czechia' (51 rows), so the Czech board silently shows less than half the Czech catalog. (c) Countries with real coverage — Lithuania (288 rows), Croatia (195), Switzerland (88), Norway (56), Sweden (39), Russia (39), Bulgaria (38) — have no chip at all while Singapore (4 rows) and South Korea (2 rows) do. The list a user scrolls does not correspond to what the catalog can actually show.

**Evidence:** Live region counts from beer_trend_feed: 'United States' 270, 'Czech Republic' 82 vs 'Czechia' 51, Lithuania 288, Croatia 195, Switzerland 88, Norway 56, Sweden 39, Russia 39 — none of these six pickable; BeerRegions.countries (BeerModels.swift:62-68) lists Australia..United Kingdom with no United States and only 'Czechia'. Singapore (4 rows) and South Korea (2 rows) are pickable.

**Fix:** Add 'United States' to the countries list (it already has 270 reachable rows). Normalize brewery.country synonyms in one data pass ('Czech Republic'→'Czechia'; audit for other splits) so each country is one board. Regenerate the picker country list from actual coverage (e.g. countries with ≥20 catalog rows), which adds Lithuania/Croatia/Switzerland/Norway and keeps the list honest as ingestion grows.

### [FIXED this round] Beers listed under countries they have no connection to: UK's Magic Rock 'Dark Arts' on the France board, Spain's Cruzcampo under United Kingdom
*Surface:* Country boards (row data)  ·  *Anchor:* `supabase/migrations/0016_trend_feed_catalog_fallback.sql:14`  ·  *Found by:* fleet

The country boards inherit brewery.country as ingested, and it is wrong on prominent rows: 'Dark Arts — Magic Rock Brewing' (a well-known Huddersfield, UK brewery) carries country 'France' and therefore appears on the France board with a 🇫🇷 flag; 'Cerveza Pilsen — Cruzcampo' (the Sevilla, Spain brand) carries country 'United Kingdom' and lands on the UK board with a 🇬🇧 flag. Both rows are in the current Global top-8 by momentum, so they are also among the first beers every user sees on the fallback boards. This is exactly law 3's 'no beer listed under a state/country it has no connection to.'

**Evidence:** Live: `select name, brewery_name, country from beer_trend_feed where region='Global' order by momentum desc limit 8` returns {'Dark Arts','Magic Rock Brewing','France'} and {'Cerveza Pilsen','Cruzcampo','United Kingdom'}. The feed joins `left join brewery br on br.id = b.brewery_id` and regionizes by `br.country` (0016 lines 14, 22-24), so the wrong country string is both the flag source and the board assignment.

**Fix:** Run a targeted brewery-country audit: cross-check breweries that exist in Open Brewery DB / have known homes against the stored country, starting with rows that appear in any board's top 40 (small set, high visibility). Correct Magic Rock→United Kingdom and Cruzcampo→Spain now via the existing correction lane. Longer term, prefer OBDB country over OFF-derived country when both exist, since OFF's country field reflects where the product was scanned, not brewed.

### [OPEN] Invented style names presented as regional fact: hero renders 'New Jersey leans shore ipa', 'Music City lager', 'Gem State pale ale'
*Surface:* Explore hero (guide mode) + region_beer_guide content  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:119`  ·  *Found by:* fleet

When a board has no market activity, the hero subtitle renders '\(name) leans \(heroStyle): notes.' Many state guide rows carry fabricated style names that exist in no style guide: 'Shore IPA' (NJ), 'Gem State pale ale' (ID), 'Music City lager' (TN), 'Supper-club lager' (WI), 'Front-porch golden ale' (MS), 'Bayou blonde ale' (LA), 'Empire hazy IPA' (NY), plus flavor notes like 'boardwalk crisp'. The 'leans' phrasing asserts a data-derived fact about a state's beer scene, but there is no data behind it and the style itself is invented — while the rest of the product carefully resolves styles against BJCP. This copy is reachable today: any state board whenever the Global fallback has zero active rows (true whenever the single test vote is cleared, as prod votes were on 2026-07-11), and on load errors.

**Evidence:** Code line 119: `activeGuide.map { "\($0.name) leans \($0.heroStyle.lowercased()): \($0.flavorNotes.prefix(3).joined(separator: ", "))." }`. Live: `select name, hero_style from region_beer_guide where scope='state'` includes 'Shore IPA', 'Gem State pale ale', 'Music City lager', 'Supper-club lager', 'Front-porch golden ale', 'Bayou blonde ale', 'Empire hazy IPA'; New Jersey flavor_notes = ['citrus','pine','boardwalk crisp'].

**Fix:** Re-seed state hero_style values with real, verifiable styles (the country rows mostly get this right: Helles, Dry stout, Biere de garde), e.g. NJ→'Hazy IPA', TN→'Lager', ID→'Pale ale', and soften the sentence to editorial rather than analytic: '\(name) guide: \(heroStyle)' or 'Known for \(heroStyle)' without 'leans'. Where no defensible style claim exists for a state, drop the line and use the neutral 'Browse real beers and cast the vote that starts the board.'

### [OPEN] One vote anywhere flips the whole board to market mode: 'Biggest movers' rail shows nine '0 ▲0' cards and ranked 'Top in X' rows over zero-signal beers; error path renders a header over nothing
*Surface:* Explore boards (movers rail, headers, empty/error states)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:309`  ·  *Found by:* fleet

hasMarketActivity is board-level: a single beer with momentum 1 (today: one French saison) switches every header to 'Top in X · Tap to vote it up or down' and shows the movers rail, where cards 2-10 display popularity 0 with a green up-arrow '0' (momentum(m) treats m >= 0 as up). Users see a 'On the come-up · Biggest movers' rail full of zeros — numbers that contradict the label on the same screen (law 3). On a load error, feedNote becomes the meaningless string 'Guide mode' (the guide card it referred to was removed from this screen) and topSection renders its header with an empty list and no message unless the No/Low lens is on. Parts of this (movers momentum!=0 gating, killing 'Guide mode', picker scroll-to-selection/Global-first) are already tracked as docs/21 P1-9 — included here because they sit directly on the state/country boards; the '▲0' up-arrow-on-zero and the header/empty-state hole are not in P1-9.

**Evidence:** Line 41-43 `hasMarketActivity: visibleBeers.contains { $0.popularity != 0 || $0.momentum != 0 }` gates lines 66 (moversSection) and 319-322 (header copy) for the whole board; line 309-314 `momentum(_ m: Int)` renders `arrow.up.right` for m >= 0, so 0 shows as a green up '0'; live Global feed has exactly one row with momentum 1 and 39 rows at 0 in the top 40. Lines 324-334: empty-list copy exists only for the noLowDefault case; the error path (beers=[], line 460-461, feedNote='Guide mode') renders header + nothing.

**Fix:** Gate market presentation per row and per section: movers rail only from rows with momentum != 0 and only when at least 3 exist (per P1-9); render a neutral dash instead of an up-arrow when momentum == 0; keep the 'Top in X' header only when the region itself (not one beer) has meaningful activity, e.g. >= 3 active rows, else keep the honest 'Explore beers from X' copy with vote CTAs. Replace 'Guide mode' with a visible failure state + retry button under the list header for the error path.

### [FIXED this round] Beers leaderboard style falls back to the same raw junk 0051 claims to have removed ('Craft Beers', '5 Beer', 'Lithuanian Beers')
*Surface:* Leaderboards > Beers board (row subcopy)  ·  *Anchor:* `supabase/migrations/0051_leaderboard_clean_names_styles.sql:10`  ·  *Found by:* fleet

leaderboard_beers returns `coalesce(sr.style_name, nullif(btrim(b.style),''))`. When the BJCP resolver fails, the raw OFF category is shown as the beer's style in the row subcopy (brewery · style · country). 2,864 of 10,288 name_ok beers (28%) fail resolution and fall back to raw values: Craft Beers 486, Lagers 241, Lithuanian Beers 228, Flavored Beers 220, 5 Beer 102, Beers From Germany 130. Any vote on one of these beers puts junk subcopy on the board, directly contradicting the migration's own header comment ('no more Pale Ales/Craft Beers/Sodas').

**Evidence:** Live query: resolved=4,676, falls_back_raw=2,864, no_style=3,675 among name_ok beers; top fallback values include 'Craft Beers' (486), '5 Beer' (102), 'Beers From Germany' (130). Deployed prosrc of leaderboard_beers matches 0051 exactly.

**Fix:** Change the coalesce to return NULL when the resolver fails and the raw value is not itself a BJCP style: `coalesce(sr.style_name, case when exists(select 1 from beer_style_reference r where r.style_name = btrim(b.style)) then btrim(b.style) end)`. The Swift row already compactMap-filters empty parts, so a null style renders cleanly as 'brewery · country'. Pair with docs/21 P1-2 (alias the top ~50 OFF tags onto BJCP refs) to shrink the null bucket.

### [OPEN] No dedup on the beers leaderboard: identical-looking rows and split votes (Heineken exists 38 times), inconsistent with the Market board
*Surface:* Leaderboards > Beers board  ·  *Anchor:* `supabase/migrations/0051_leaderboard_clean_names_styles.sql:8`  ·  *Found by:* fleet

leaderboard_beers ranks beer_score rows per catalog UUID with no display-name dedup. The catalog holds 1,380 name_ok beers in 492 groups that render pixel-identical rows (same display_name + same brewery + same country): Heineken x38, Desperados x22, Kronenbourg x17, Stella Artois x16, Carlsberg x15. Two users voting on two different Heineken SKUs produce two identical 'Heineken / Heineken / Netherlands' rows each showing 1 up-vote instead of one row with 2 — votes silently split and the board looks broken. Every sibling ranked surface dedupes: beer_market uses `distinct on (lower(dname))` (0067:110), catalog_search dedupes (0065/0066), ExploreView dedupes client-side by lowercased name; the Leaderboards screen renders the RPC rows raw (LeaderboardsView.swift:93).

**Evidence:** Live query: 492 identical-render groups covering 1,380 beers ('Heineken'/'Heineken'/'Netherlands' c=38, 'Stella Artois' c=16...). Deployed leaderboard_beers prosrc has no distinct-on. 0067 refresh_beer_market_standing dedups: `select distinct on (lower(dname)) ...`.

**Fix:** Mirror the 0067 rule inside leaderboard_beers: aggregate beer_score by lower(display_name) before ranking — sum net/ups/downs/checkins across same-name SKUs, pick the representative row the way 0065 does (image first, brewery first), and rank on the summed score. That both dedupes the rendering and un-splits votes, keeping Leaderboards consistent with Market and Search. (Tracked in docs/21 P1-2 for market/search; the leaderboard RPC is not covered there.)

### [OPEN] Vote-driven regional signal is keyed by region_code ('CA') while every shelf filters by full names ('California') — state boards can never show votes
*Surface:* Explore regional/state boards (beer_trend)  ·  *Anchor:* `supabase/migrations/0055_real_activity_consent_gates.sql:155`  ·  *Found by:* fleet

refresh_beer_trend buckets votes by raw user_profile.region_code and checkins by venue external_ids region. Live, the only real vote sits in beer_trend under region 'CA' (the voter's region_code), while venue-derived regions are full names ('California' 803 venues, 'New York' 234) and the app's shelf filter uses BeerRegions full names ('California', 'New Jersey', country names). A Californian picking the California shelf runs .eq("region","California") and will never see any vote-driven trend row keyed 'CA'; the signal is only reachable via Global, where the same beer appears as two rows (regions 'CA' + 'Global', both momentum 1) that burn 2 of the 40 fetched slots. One column carries three vocabularies (codes, US state names, country names) so state/country boards silently under-report forever.

**Evidence:** Live beer_trend: [{region:'CA', popularity:1, momentum:1}, {region:'Global', ...}] for the one real vote; live venue regions: California 803, Bayern 560, Washington 328 (full names); BeerModels.swift BeerRegions.all = full state + country names; live user_profile.region_code = 'CA'. The app's exact Global query returned the same beer twice as rows 1 and 2.

**Fix:** Normalize to one vocabulary at write time in refresh_beer_trend: map 2-letter US state codes in region_code to the full state name (a 50-row case or lookup table) and validate region_code against BeerRegions vocabulary in save_taste so 'CA' can never be stored again; also exclude the redundant per-region row from the Global fetch by making BeerService.trends("Global") filter .eq("region","Global"). Backfill the existing 'CA' profile row to 'California'.

### [FIXED this round] Downvote-only beers rank on the trophy board (with gold top-3 badges) while contested beers with real activity vanish — opposite of the Market's votes-exist rule
*Surface:* Leaderboards > Beers board  ·  *Anchor:* `supabase/migrations/0051_leaderboard_clean_names_styles.sql:18`  ·  *Found by:* fleet

The board gate is `(s.net <> 0 or s.checkins > 0)`. Two consequences a user can see: (1) a beer whose only signal is downvotes (net -1) qualifies, and on today's sparse board it would sit at rank #2 — LeaderboardsView gives every rank <= 3 a gold badge, so a beer nobody liked gets trophy treatment; (2) a genuinely contested beer (5 up / 5 down, net 0, no checkins) is dropped from the board entirely, while 0067's market gate ('ANY beer someone actually voted on') keeps it on the Market screen showing 10 votes. Same beer, same day: visible with activity on Market, missing from Leaderboards — stats that contradict each other across screens.

**Evidence:** Deployed prosrc: `where (s.net <> 0 or s.checkins > 0) ... order by (s.net + s.checkins * 2) desc`. LeaderboardsView.swift:212-218 rankBadge: gold background for rank <= 3 unconditionally. 0067:50: `or exists (select 1 from public.beer_vote v where v.beer_id = b.id) -- Real votes always count.`

**Fix:** Align the gate with 0067: include any beer with votes_count > 0 or checkins > 0 (so contested beers stay visible with their real ups/downs), and order by score with votes_count as tiebreak. In the UI, reserve the gold top-3 badge for rows whose net score is positive (a neutral badge otherwise), so a downvoted beer can appear honestly without podium styling.

### [FIXED this round] Tasters empty-state copy contradicts the actual ranking: says styles/countries beat volume, but SQL ranks by pour count first
*Surface:* Leaderboards > Tasters board  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:137`  ·  *Found by:* fleet

The empty state tells users 'Log pours to claim the top spot. Styles and countries count more than volume.' The deployed leaderboard_tasters orders by pours desc first, styles second; countries is not even a tiebreaker. A user who chases breadth per the copy will be out-ranked by anyone with more raw pours, and the row UI reinforces it (pours is the big number). On a screen whose hero panel promises honest first-party stats, the stated rule and the computed rule disagree.

**Evidence:** LeaderboardsView.swift:137: "Log pours to claim the top spot. Styles and countries count more than volume." Live prosrc: `order by 5 desc, 6 desc, 2` where column 5 = count(ce.id) pours, 6 = distinct styles.

**Fix:** Pick one truth and apply it to both sides: either change the copy to 'Most pours takes the top spot; styles break ties' (smallest change), or make the SQL match the promise by ranking on a breadth-weighted score, e.g. `order by (styles*3 + countries*5 + pours) desc`. Given launch timing, fix the copy now and revisit the formula later.

### [OPEN] Retail-string residue still passes name_ok: promo/pack/ABV fragments and comma debris in user-facing names, including 11 rows on the live market board
*Surface:* Catalog browse/search + live Beer Market board (names)  ·  *Anchor:* `supabase/migrations/0064_beer_name_normalize_v3_retail_strings.sql:47`  ·  *Found by:* fleet

After v3 normalization, name_ok=true rows still include '1664 + 6 Offerte' (retail promo: '+6 free'), '1664 Can 1664 Hd', '1664 Vr 1664 Blonde', '1664 Maxi Format', '1664 Format Special' (pack/format strings shown as beer names — two of these are on the default browse first page), 'Beer Licorne Black, Dark, , , Bottle', 'Radeberger Pilsner 0, , 6erPack', 'Panache <', 'Cerveza sin alcohol saer brau est. 1985 sin alc. <', 'Stout Hercule (9 deg . )', 'Biere blonde forte 8deg, de', 'KRONENBOURG,Bud, Kronenbourg 7deg2 Blonde', "Beck's Blue Beer Bottles 6 x" (returned by the beck search live), and 8 'Coffret cadeau' gift-box products listed as individual beers. Counts among name_ok rows: 25 contain a degree sign (a few are legit Czech-gravity names like '12deg APA'), 15 contain stray ' , ' debris, 2 end in < or |. The live beer_market_standing board carries 11 such junk display names.

**Evidence:** All example strings above pulled live from beer_catalog where name_ok=true; 'Beck's Blue Beer Bottles 6 x' observed in catalog_search('beck') output; select count from beer_market_standing where display_name has trailing <>| or ' , ' = 11.

**Fix:** Extend tapt_display_name with a final scrub pass (collapse ', ,' and trailing ' , x' fragments, strip trailing lone punctuation including < > |, strip 'N x' pack tails, strip promo tokens offerte/format special/maxi format) and extend tapt_name_ok to reject names still containing '<', '|', ', ,', or matching gift-set patterns (coffret|gift ?set|assortiment). Drop/re-add the generated columns to recompute and refresh market standings.

### [OPEN] Non-beer products live in the beer catalog: sodas, wines, spirits, liqueurs, hard seltzer
*Surface:* Catalog browse/search, style filters, market style field  ·  *Anchor:* `supabase/migrations/0050_catalog_clean_and_my_activity.sql`  ·  *Found by:* fleet

28+ name_ok rows carry explicitly non-beer styles straight from OFF categories: 'Artisanal Spirits' (8), 'Sodas' (6), 'Liqueurs' (2), 'Wines'/'Wines From Germany'/'White Wines' (5), 'Ciders' (4), 'Pelinkovac' (2, a 28% wormwood liqueur), 'Advocaat' (1, 'Eierlikoer' egg liqueur at 20%), 'Diet Sodas' (1); plus "Willie'superbrew Hard Seltzer Sparkling Mango and Passionfruit" surfaced in a random sample. In THE Beer Superapp, a browsing user hits wine and soda rows presented as beers.

**Evidence:** Live: select style,count(*) where name_ok and style ~* 'cider|wine|liqueur|spirit|soda|advocaat|pelinkovac' -> Artisanal Spirits 8, Sodas 6, Liqueurs 2, Wines From Germany 2, Ciders 2, Pelinkovac 2, Wines 2, Diet Sodas 1, Sweet Ciders 1, White Wines 1, Non Alcoholic Ciders 1, Advocaat 1.

**Fix:** Add a style blocklist to tapt_name_ok (or a dedicated listable gate): rows whose style matches soda|wine|liqueur|spirit|advocaat|pelinkovac|seltzer are never listable (ciders/radlers are a product call — radler/panache are beer-based and can stay, plain ciders should go). This hides ~30 rows immediately; the fuller purge via OFF category re-fetch is already noted internally, but the style field alone catches these today.

### [OPEN] Country naming splits fracture the country boards and break flags: Czech Republic vs Czechia, England/Scotland vs United Kingdom, and literal 'Unknown' shown to users
*Surface:* Country boards (Explore region picker), flags in Explore rows, leaderboard subtitles, market detail tag  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:434`  ·  *Found by:* fleet

brewery.country mixes synonym spellings, and every read surface treats them as different countries. beer_trend_feed has BOTH region 'Czech Republic' (82 beers) and 'Czechia' (51); the app picker (BeerModels.countries) only offers 'Czechia', so the 82 Czech-Republic-labeled beers can never appear on the Czechia board, and the 'Czech Republic' board is unreachable. England (62 breweries) and Scotland (9) are separate from United Kingdom (130) with no picker entry. ExploreView's flag map has 'Czechia' and 'United Kingdom' but not 'Czech Republic'/'England'/'Scotland', so those beers render the generic beer-mug fallback instead of a flag. 24 breweries have country='Unknown' -> 32 name_ok beers and 20 live market-board rows whose detail sheet renders a globe tag literally reading 'Unknown', and an unpickable 'Unknown' region (32 rows) exists in the trend feed.

**Evidence:** Live: brewery.country counts United Kingdom 130 / England 62 / Scotland 9 / Czech Republic 40 / Czechia 5 / Unknown 24 / 'Bosnia And Herzegovina' 3; beer_trend_feed regions: United Kingdom 252, Czech Republic 82, Czechia 51, Unknown 32; beer_market_standing country='Unknown' = 20; MarketBeerDetailView.swift:170-171 renders beer.country verbatim as a tag; ExploreView flag map keys lack Czech Republic/England/Scotland.

**Fix:** Normalize brewery.country to one canonical name set in a migration (Czech Republic->Czechia, England/Scotland->United Kingdom or add them as picker entries — pick one policy, apply to data + BeerModels + flag maps together), convert 'Unknown' to NULL so no surface prints it (rowSubtitle and the market tag already handle empty), and rebuild the trend feed/market standings. Derive flags from ISO codes instead of name-keyed switch tables (docs/21 P2-14 already suggests this for Passport).

### [OPEN] Case/punctuation variants of the same beer pass every dedupe: Beck's appears twice on the live market board with the same BECK ticker and two different countries
*Surface:* Beer Market board + Explore ticker + catalog search (duplicate near-identical names)  ·  *Anchor:* `supabase/migrations/0067_market_honesty_p0s.sql:128`  ·  *Found by:* fleet

70 groups of name_ok display names differ only by case/punctuation, so the exact-lower(name) dedupes in catalog_search, ExploreView.visibleBeers, and refresh_beer_market_standing all keep them. Live market board today: "Beck's" (brewery Anheuser-Busch InBev, country United States) AND "beck's" (curly apostrophe, lowercase, brewery Beck's, Germany) — same 4-char ticker symbol BECK, same standing, shown as two stocks; the lowercase one also dodges the ALL-ASCII initcap fix because of the curly quote. Likewise 'Carls berg' + 'Carlsberg' (both ticker CARL) and 'Carl's berg' in the catalog — misspelled brand names a user will screenshot. Search 'beck' additionally returns 'Beck-S'. Same beer under two countries on one board is a law-3 contradiction. (docs/21 P1-2/P1-16 track the broader merge; the market-board-visible duplicate-symbol pair with contradictory countries is what a launch user sees.)

**Evidence:** Live beer_market_standing: {Beck's, BECK, Anheuser-Busch InBev, United States, 16} and {beck's(curly), BECK, Beck's, Germany, 16}; {Carls berg, CARL} + {Carlsberg, CARL}; 70 punct-dupe groups counted among name_ok rows; catalog_search('beck') shows Beck's / beck's / Beck-S as separate rows.

**Fix:** Make every dedupe key punctuation/case-insensitive: key on lower(regexp_replace(display_name,'[^[:alnum:]]+','','g')) in catalog_search, the market refresh distinct-on, and the Swift visibleBeers Set. In tapt_display_name, normalize curly quotes to straight and title-case single-word all-lowercase brands even when a non-ASCII apostrophe is present. Then run the Beck's/Carlsberg brewery variants through canonical_merge_queue so countries stop contradicting.

### [OPEN] State boards can never match their data ('CA' written vs 'California' queried) and the Global fallback is labeled as local ('Top in New Jersey', '<brewery> is climbing in New Jersey')
*Surface:* Explore state/country board (region picker + hero + 'Top in <region>' list)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:118`  ·  *Found by:* fleet

The only real community trend row in beer_trend is keyed region='CA', but the app's picker and geo-detect send full state names ('California'), so the one genuine local signal is unreachable on any board — and beer_trend_feed's fallback only generates country-name regions, so every US-state query returns empty and silently falls back to Global. After the fallback, ExploreView still titles the list 'Top in <state>' and the hero says '<brewery> is climbing in <state>' with a momentum arrow — live data makes that 'Brasserie Thibord (France) is climbing in New Jersey', a locality claim the data does not support, directly contradicting the small 'guide + Global radar' caption on the same screen. (Task #57's 'drop state abbrevs' overlaps; included because it is the state-board surface, and the mislabel itself is untracked.)

**Evidence:** Live beer_trend: exactly 2 rows, regions 'CA' and 'Global' (same beer 'La saison du chasseur', Brasserie Thibord, France, popularity 1, momentum 1); BeerModels.swift:50-61 sends full state names; beer_trend_feed fallback regions contain no US states; ExploreView.swift:118 subtitle '"\($0.brewery) is climbing in \(region)"' and :320 header 'Top in \(region)' render over the Global fallback rows.

**Fix:** Pick one region vocabulary (full state names), migrate the existing 'CA' beer_trend row and the writer that produced it, and make the fallback honest in the UI: when load() falls back to Global, set a flag so topSection titles 'Trending worldwide' and the hero subtitle drops the 'in <region>' clause (or says 'climbing worldwide'). Never render a state name next to data that did not come from that state.

### [OPEN] Consent ledger records ui_text_shown the user never saw; server silently discards the app's uiText
*Surface:* Profile > Privacy Choices (consent ledger integrity)  ·  *Anchor:* `supabase/migrations/0007_backend_contract_and_content_pipeline.sql:576`  ·  *Found by:* fleet

When a user flips a Privacy Choices toggle, ProfileView passes the on-screen label ('Nearby beer spots', 'Anonymous trend reports', 'Partner insight aggregates') into record_privacy_choice as p_ui_text. The live function body never references p_ui_text: it inserts a hardcoded per-purpose sentence into consent_ledger.ui_text_shown. For the 'location' purpose that stored sentence — 'Use my location for nearby breweries and local recommendations.' — matches no string anywhere in the current app (the profile toggle says 'Nearby beer spots'; onboarding says 'Use my location for nearby pubs, bars, breweries, taprooms, and beer gardens.'). The column exists to prove what text the user consented to, and for every profile-screen location consent it now provably records text that was never shown. That is a false record in the exact artifact meant to demonstrate consent honesty (GDPR/CCPA evidence trail).

**Evidence:** Live pg_get_functiondef(record_privacy_choice): body inserts ui_text_shown from 'case v_purpose when location then Use my location for nearby breweries and local recommendations. ...' — p_ui_text appears only in the signature. ProfileView.swift:201 calls syncPrivacy("location", granted:, text: "Nearby beer spots"); grep of app/Tapt for 'nearby breweries and local recommendations' returns zero hits.

**Fix:** Replace the hardcoded case block with a server-side allowlist that accepts p_ui_text only when it exactly matches one of the known UI strings for that purpose (profile label or onboarding sentence), falling back to the canonical sentence plus a source marker if the client sends something unexpected — this keeps the anti-forgery intent while making ui_text_shown truthful. At minimum, update the canonical 'location' sentence to the string the app actually shows, and align ProfileView's toggle labels with the stored sentences so screen and ledger agree.

### [OPEN] Onboarding promises 'We will tune your feed' but the picked styles are read by nothing
*Surface:* Onboarding (styles step claim vs reality)  ·  *Anchor:* `app/Tapt/Features/Onboarding/OnboardingView.swift:79`  ·  *Found by:* fleet

The styles step tells every new user 'Pick your go-to styles. We will tune your feed.' The picks are written two places and consumed by zero: (1) taste_vector.top_styles on the server — a live scan of pg_proc shows the only functions referencing taste_vector are complete_profile_onboarding (write) and delete_account_data (delete); no feed, market, explore, or recommendation function reads it; (2) the favoriteStyles AppStorage key in the app — written in OnboardingView.complete() and read nowhere else in the codebase. The only pick with any effect is 'No / Low' (it sets noLowDefault). A user who carefully selects styles gets an identical feed to one who selects none, so the onboarding sentence is an unfulfilled product promise on the first screen sequence every user sees.

**Evidence:** Live query: select proname from pg_proc where prosrc ilike '%taste_vector%' returns only complete_profile_onboarding and delete_account_data. App grep: favoriteStyles appears only at OnboardingView.swift:11 (declaration) and :205 (write); no reader exists in app/Tapt.

**Fix:** Either wire the promise or soften it. Cheapest honest wiring: use taste_vector.top_styles to order the Explore board / catalog browse (boost matching styles) or preselect the style filter — a single ORDER BY boost in the existing read RPC. If that is post-launch, change the subtitle to what is true today, e.g. 'Pick your go-to styles. No / Low sets your lens.' or simply 'Pick your go-to styles.' — blank beats invented promises, same as data.

### [OPEN] One flaky first launch permanently skips onboarding — the code contradicts its own 'next launch re-checks' comment
*Surface:* Onboarding gate (TaptApp launch flow)  ·  *Anchor:* `app/Tapt/TaptApp.swift:63`  ·  *Found by:* fleet

When a signed-in user is not locally onboarded and the server check fails twice (isOnboarded returns nil on any network/server error), checkServerOnboarded's nil branch calls markLocallyOnboarded(id), which persists the user id into the onboardedUserIDs AppStorage set. The in-code comment says 'the next launch re-checks' — it never will: localOnboarded(id) is now true forever, so checkServerOnboarded is never called again for that account on that device. A brand-new user who signs in on a flaky connection permanently skips the legal-age step, all three consent captures, region, and styles: birth_verified stays false, consent_ledger gets zero rows, region_code stays null server-side. The sign-in caption's age attestation partially covers the age claim, but the account has no recorded consents and the profile shows all sharing off while the user was never asked.

**Evidence:** TaptApp.swift:58-64 — 'case nil: // Still unknown ... the next launch re-checks. markLocallyOnboarded(id)'; markLocallyOnboarded (lines 67-72) writes to the persistent @AppStorage("onboardedUserIDs") set that localOnboarded() (line 40) checks before ever reaching checkServerOnboarded.

**Fix:** In the nil case, set only the in-memory session flag (serverOnboarded[id] = true) instead of calling markLocallyOnboarded — that lets the user into the app for this launch exactly as intended while leaving the persistent flag unset, so the next cold launch genuinely re-checks the server and routes them into onboarding once the network is back. Keep markLocallyOnboarded for the confirmed true case only.

### [FIXED this round] 49 venues exist twice — identical name, city, and often identical coordinates — producing double pins and ambiguous claim targets
*Surface:* Near You map, radar list, and venue claim search  ·  *Anchor:* `app/Tapt/Features/Partners/BreweriesHubView.swift:310`  ·  *Found by:* fleet

49 duplicate groups (98 rows) of exact same-name venues in the same city: 10 Barrel Brewing Co (Bend), Ballast Point (San Diego), Deschutes (Bend), Dogfish Head (Milton), D. G. Yuengling and Son Inc (Pottsville), Great Lakes (Cleveland), Jester King (Austin), BrewDog Berlin Mitte, BRLO Brwhouse, Garage Project (Wellington), and 39 more. Users see two stacked pins and two identical rows in the radar list and search results. Worse, an owner using Claim your venue sees their business twice with no way to know which row is canonical — claims, tap lists, and analytics then attach to whichever row they happened to pick, splitting the venue's identity permanently.

**Evidence:** Live SQL: GROUP BY lower(name), city, country HAVING count(*)>1 → 49 groups, 98 rows, 49 excess. Sample: BrewDog Berlin Mitte x2 at identical coords 13.4132225/52.5170043; Deschutes Brewery x2 (Bend); Ballast Point Brewing Company x2 (San Diego); D. G. Yuengling and Son Inc x2 (Pottsville).

**Fix:** Dedupe migration: for each duplicate group keep the row with the richer external_ids (website, OBDB id) and no dependent claims/snapshots/checkins on the loser (there are currently 0 claims and 0 snapshots, so this is the cheapest it will ever be), repoint any stray FKs, delete the loser, and add a unique index on the OBDB external id (and a soft uniqueness check on lower(name)+city+country in the ingest upsert) so the planned monthly OBDB refresh can't reintroduce them.

### [OPEN] 'Local beer spotlight' promotes a venue that is usually not local — by default it is a rotating world-wide seed venue
*Surface:* Near You map spotlight card (NearYouView)  ·  *Anchor:* `app/Tapt/Features/NearYou/NearYouView.swift:55`  ·  *Found by:* fleet

The spotlight card is just visibleTaptVenues.first ?? taptVenues.first. locationConsent defaults to false, so out of the box the feed is the global brewery_map_feed ordering: heat desc, then a daily md5 rotation. With 0 check-ins and 0 live taps in prod, the top heat tier is exactly the 28 tapt_seed venues, which are spread across Bavaria, Brussels, Jalisco (Mexico), Ibaraki (Japan), Plzen, Dublin, Scotland and assorted US states. So a first-run user in New Jersey with location off sees 'Local beer spotlight' + a 'SPOT' badge on, say, a Guadalajara brewery — a wrong 'local' claim dressed in featured-placement styling while zero paid/featured partners exist. The fallback subtitle 'Fresh taps, events, and game nights nearby' additionally asserts taps and events for a venue with none on record (venue_event and venue_tap_snapshot are both empty).

**Evidence:** NearYouView.swift:55-57 spotlightVenue = visibleTaptVenues.first ?? taptVenues.first; :208 Text("Local beer spotlight"); :215 fallback 'Fresh taps, events, and game nights nearby'; :221 'SPOT' badge. Live SQL: 28 venues with external_ids ? 'tapt_seed' spanning 'Bavaria, Brussels, California, ... Ibaraki, Jalisco, ... Plzen, Scotland'; checkin_event count = 0; venue_event = 0; venue_tap_snapshot = 0. brewery_map_feed orders by heat desc (tapt_seed = 2, others = 1) then daily md5.

**Fix:** Only render the spotlight card when the venue is provably near the user: gate it on the brewery_map_feed_near result (or venue.region == homeRegion) and hide it otherwise, instead of falling back to the global list head. Retitle honestly if a non-near fallback is ever wanted ('From the Tapt map', no SPOT badge), and delete the fabricated 'Fresh taps, events, and game nights nearby' fallback line — show the real place line or nothing.

### [OPEN] Both deployed email functions hardcode tapt-landing-three.vercel.app instead of taptbeer.com
*Surface:* Live edge functions resend-send and newsletter-unsubscribe (partner emails + unsubscribe redirect)  ·  *Anchor:* `supabase/functions/resend-send/index.ts:17`  ·  *Found by:* fleet

Verified in the DEPLOYED code, not just the mirror: resend-send v2 has LANDING = 'https://tapt-landing-three.vercel.app', used for the partner welcome email's 'View menu + print QR' link, the portal link, and the footer brand link on every email it sends; newsletter-unsubscribe v1 has the same LANDING and 303-redirects the human (GET) unsubscribe path to tapt-landing-three.vercel.app/unsubscribe. dispatch-weekly correctly uses https://taptbeer.com, so emails from different functions brand two different domains. Both vercel URLs currently resolve (verified 200 with the real unsubscribe page), so nothing is broken today, but partners who open their menu from the welcome email will print table QR codes bearing the vercel URL, and the CAN-SPAM human unsubscribe path lives on a domain that dies if the Vercel alias is ever renamed.

**Evidence:** Live get_edge_function(resend-send): `const LANDING = "https://tapt-landing-three.vercel.app";` then `const menuUrl = \`${LANDING}/menu?v=${body.venue_id}\`` and footer `<a href="${LANDING}">tapt</a>`. Live get_edge_function(newsletter-unsubscribe): `const LANDING = "https://tapt-landing-three.vercel.app";` and GET returns 303 to `${LANDING}/unsubscribe?t=...`. dispatch-weekly (same project) uses `const LANDING = "https://taptbeer.com";`. Migration 0057 is literally named branded_web_domain but the fns were missed.

**Fix:** Change LANDING to https://taptbeer.com in supabase/functions/resend-send/index.ts:17 and supabase/functions/newsletter-unsubscribe/index.ts:13, redeploy both functions, and keep the repo mirror in the same commit. Optionally read the domain from a single LANDING_URL env/secret so all three email functions cannot drift again.

### [OPEN] No Privacy/Terms links on the portal, the public menu page, or the pitch page
*Surface:* landing/portal.html, landing/menu.html, landing/pitch.html  ·  *Anchor:* `landing/portal.html:137`  ·  *Found by:* fleet

The footer-legal rule is on every page: index, dispatch, and unsubscribe carry Privacy/Terms links, but portal.html (which collects business emails via OTP sign-in, venue claims, inquiry messages, and logo uploads) has no privacy policy or terms link anywhere, no link back to the main site, and ends on the paid-placement card. menu.html is the public page every table QR resolves to and has only a 'What is Tapt?' link. pitch.html is a public business page with no legal links. For the portal specifically, collecting personal/business data on a page with zero legal links is a trust and compliance gap in the exact flow where a bar owner decides whether Tapt is legitimate.

**Evidence:** portal.html body ends at the 'Want featured placement?' card (lines 128-137) with no footer; grep for privacy.html/terms.html in portal.html, menu.html, pitch.html returns nothing. menu.html:51 footer is 'Menus are published by the venue via Tapt. Enjoy responsibly, 21+/legal drinking age. <a href="index.html">What is Tapt?</a>' with no legal links. Compare dispatch.html:297-304 which has Home/Features/For business/Privacy/Terms/Contact.

**Fix:** Add a small shared footer line to portal.html, menu.html, and pitch.html: 'Privacy Policy · Terms of Service · hello@taptbeer.com' linking to /privacy and /terms (root-relative so it works from /menu?v=... too), plus a wordmark link back to /. On portal.html place it after the featured-placement card; on menu.html merge it into the existing .foot line so print CSS still hides the CTA but keeps legal links.

### [OPEN] Incumbent price framed as $1,199/yr when Untappd for Business publicly lists an $899/yr tier, and the pitch's '21% of Untappd's floor' math is wrong
*Surface:* landing/index.html business comparison + landing/pitch.html business model slide  ·  *Anchor:* `landing/pitch.html:107`  ·  *Found by:* fleet

The landing's 'The incumbent · $1,199/yr' card and the pitch's 'Thousands of US venues pay $1,199/yr' present Untappd's PREMIUM tier as the incumbent's price. Untappd for Business publicly lists two tiers: Essentials $899/yr and Premium $1,199/yr, and menu hosting (the feature Tapt's $0 comparison targets) is included in the $899 tier. Picking the top tier without disclosure overstates the wedge on a site whose brand is honesty. The pitch also claims 'Top tier ≈ 21% of Untappd's floor': Spotlight at $79/mo is $948/yr, which is 79% of $1,199 and 105% of the real $899 floor; no tier arithmetic produces 21%, so the stat contradicts the tier table two lines above it.

**Evidence:** index.html:350 `<div class="price">$1,199<span...>/yr</span></div>` under 'The incumbent'; pitch.html:67 'business pricing doubled to $1,199/yr'; pitch.html:107 'Top tier ≈ 21% of Untappd's floor'. Web sources: Untappd help center and BeerMenus report Essentials $899/yr and Premium $1,199/yr two-tier pricing (help.untappd.com 'What is Untappd for Business Premium?', beermenus.com/blog/312 'Untappd for Business price increase', utfb.untappd.com/get-pricing). $948/$1,199 = 79%, not 21%.

**Fix:** Anchor the comparison to the incumbent's real floor: label the card 'The incumbent · from $899/yr' (or '$899-1,199/yr') on index.html and pitch.html, and fix the derived stat to the true math, e.g. 'Top tier costs about a quarter of what the incumbent's cheapest plan charges per month' only if that is actually true after recomputation; with Spotlight $79/mo vs Essentials $74.92/mo it is not, so the honest line is 'Featured at $29/mo is about a third of the incumbent's floor'. Recompute every derived percentage from the published tier table before it ships.

### [OPEN] Catalog country and style counts on public pages do not match the live database
*Surface:* landing/pitch.html moat slide + landing/index.html data-promise section  ·  *Anchor:* `landing/pitch.html:90`  ·  *Found by:* fleet

The pitch's moat card claims '47 countries in a curated, source-attributed beer catalog', but the live catalog spans 105 distinct brewery countries (103 among listable beers); 47 is the app's Passport country list (PassportData.swift has 47 entries), a different thing. Both the pitch ('60 BJCP-cited style guides') and index.html's sources card ('vital-statistics ranges for 60 styles') say 60 styles while beer_style_reference has 61 rows and docs/21 itself says '61 baked style pages'. These are understatements rather than inflation, but they are still wrong numbers on pages that promise 'every number is real or cited', and the 47-as-catalog claim mislabels what the number measures.

**Evidence:** pitch.html:90-91 cards '47 · countries in a curated, source-attributed beer catalog' and '60 · BJCP-cited style guides'; index.html:409 'vital-statistics ranges for 60 styles'. Live SQL: distinct brewery countries among beer_catalog rows = 105 (listable view: 103); count(*) from beer_style_reference = 61. app/Tapt/Features/Cellar/PassportData.swift countries list = 47 entries.

**Fix:** On pitch.html, either relabel the 47 card to what it actually measures ('47-country Beer Passport to fill') or update it to the real catalog spread ('100+ countries represented in the catalog'), and change 60 to 61 in both pitch.html and index.html (or drop the digit: 'every BJCP 2021 style family, cited'). Add these two numbers to the same pre-share recheck as the venue count.

### [OPEN] Primary CTA 'Download for iOS' is a dead self-anchor — the app cannot be downloaded
*Surface:* Web · taptbeer.com homepage (hero + closing CTA + nav)  ·  *Anchor:* `landing/index.html:222`  ·  *Found by:* fleet

All three main CTAs — nav 'Get Tapt' (line 210) and both 'Download for iOS' buttons (lines 222, 418) — link to href="#get", which is the id of the hero div containing the first button itself. Clicking the hero button does nothing; clicking the footer one scrolls back to the hero, where the visitor finds… the same dead button. The app is TestFlight-only (pitch.html says 'iOS on TestFlight now'), so the label also promises an App Store download that does not exist. Every visitor's intended next step ends in a silent no-op on the live site.

**Evidence:** index.html:221-222 `<div class="hero-ctas" id="get"> <a class="btn btn-dark" href="#get">Download for iOS</a>`; index.html:418 `<a class="btn btn-dark" href="#get">Download for iOS</a>`; no script handles #get. pitch.html:81: 'iOS on TestFlight now'.

**Fix:** Until App Store approval, change the label and target to something true: 'Coming to the App Store — get notified' pointing at the newsletter signup section (href="#newsletter" or the dispatch form), or a TestFlight public link if the owner wants early access sign-ups. Swap in the real App Store URL at launch (Wave 6).

### [OPEN] '25 countries' claim in the data-promise section — the live OBDB venue layer spans 22
*Surface:* Web · taptbeer.com 'Our data promise' section  ·  *Anchor:* `landing/index.html:407`  ·  *Found by:* fleet

The Open Brewery DB source card says 'The global brewery & venue layer, thousands of coordinate-verified locations across 25 countries.' The live OBDB import that actually backs Tapt's venue layer spans 22 distinct countries. Sitting inside the section headlined 'Zero fabricated data. Open sources, cited.', a checkable overstated count is exactly the kind of number the promise forbids.

**Evidence:** index.html:407 '...thousands of coordinate-verified locations across 25 countries.' Live DB: `SELECT count(DISTINCT trim(country)) FROM open_brewery_db_seed_import;` → 22 (8,666 rows).

**Fix:** Change to the true figure ('across 22 countries') or drop the count entirely ('thousands of coordinate-verified locations worldwide') so the sentence cannot drift false as ingests change. One text edit plus redeploy.

### [OPEN] 'Check-in' and 'pour' used interchangeably — the consent toggle asks users to share a thing the app never defines
*Surface:* iOS app onboarding + Tonight + partner analytics + landing (cross-surface)  ·  *Anchor:* `app/Tapt/Features/Onboarding/OnboardingView.swift:91`  ·  *Found by:* fleet

The app's canonical verb is pour ('Log a pour', 'pours', Cellar, Passport), but 'check-in' leaks in on adjacent surfaces: the onboarding consent toggle says 'Use my check-ins for anonymous aggregate trend reports' before the app has ever used that word (every other onboarding string says pour); Tonight uses both in neighboring sections ('No social pours yet' vs 'As tap lists and check-ins build up…' and 'Private style signal from your check-ins'); the partner analytics empty state mixes 'weekly pours' with 'as people check in'; the homepage says both 'real votes and check-ins from drinkers worldwide' and 'Every pour you log stamps your Passport'. A new user granting a privacy consent should not have to guess whether a 'check-in' is the same thing as the 'pour' every other screen talks about.

**Evidence:** OnboardingView.swift:91 'Use my check-ins for anonymous aggregate trend reports.'; TonightView.swift:101 'As tap lists and check-ins build up…' vs :138 'No social pours yet'; BreweriesHubView.swift:587 '…weekly pours, and drinker signal fill in here as people check in.'; landing/index.html 'real votes and check-ins from drinkers worldwide' vs 'Every pour you log stamps your Passport'.

**Fix:** Pick 'pour' as the only user-facing noun/verb for logging (matching Log a pour, Cellar, Passport) and sweep the four surfaces: onboarding consent → 'Use my logged pours for anonymous aggregate trend reports', TonightView:101/155 → 'pours', BreweriesHubView:587 → 'as people log pours', landing hero feature → 'real votes and pours'. Keep 'check-in' only as the internal/DB term (checkin_event, privacy policy can say 'pours (check-ins)' once as a definition).

### [OPEN] Pilsner's birthplace rendered as broken text 'Plze' twice — and spelled a third way in Trivia
*Surface:* iOS app · Beer School (history timeline + The Legends)  ·  *Anchor:* `app/Tapt/Features/Learn/LearnData.swift:82`  ·  *Found by:* fleet

Beer School's history timeline says 'Pilsner Urquell is brewed in Plze.' and the Legends card shows the place line 'Plze, Czechia' with the story 'the townspeople of Plze built a new brewery'. 'Plze' is a mangled 'Plzeň' (the ň was dropped) — to any reader it looks like a typo or truncated data, in the exact feature that positions Tapt as the credible beer educator. Meanwhile Trivia spells the same city 'Plzen', so the app ships three spellings of one famous beer city (Plze / Plzen / and none correct as 'Plzeň').

**Evidence:** LearnData.swift:82 'Pilsner Urquell is brewed in Plze. The clear, golden pilsner is born…'; LearnData.swift:99 place: 'Plze, Czechia' + '…the townspeople of Plze built a new brewery…'; TriviaData.swift:47 'Pilsner Urquell was brewed in Plzen, Bohemia…'.

**Fix:** Use 'Plzeň' (Swift string literals handle it fine) in all three LearnData spots, and align TriviaData.swift:47 to 'Plzeň' for consistency. If diacritics are a concern for any rendering path, standardize on 'Pilsen' everywhere instead — one spelling, app-wide.

### [OPEN] Internal design rationale ships as user-facing copy — the app tells users what 'Tapt should' do and calls them 'casual drinkers'
*Surface:* iOS app · Flights (guided tasting quest detail)  ·  *Anchor:* `app/Tapt/Features/Flights/FlightsData.swift:70`  ·  *Found by:* fleet

Each flight's 'why' blurb is rendered verbatim in the quest detail (FlightsView.swift:108), but the strings read like PM notes, not copy written for the person holding the phone: 'Non-alcoholic beer is growing fast, and Tapt should treat mindful drinkers as first-class beer fans' (the app arguing product policy with itself), 'Great for casual drinkers because it teaches how different countries bend the clean lager family without making anyone drink heavy', 'This helps IPA-curious drinkers learn…', 'Sours are a huge discovery lane for casual drinkers because they map to citrus, fruit, and cocktails' ('discovery lane' is roadmap jargon). Users are described in third person as segments instead of being spoken to directly.

**Evidence:** FlightsData.swift:28, 42, 56, 70, 84 (the `why:` strings) rendered by FlightsView.swift:108 `Text(selected.why)`. E.g. line 70: 'Non-alcoholic beer is growing fast, and Tapt should treat mindful drinkers as first-class beer fans.'

**Fix:** Rewrite the five `why` strings in second person, plain voice: e.g. 'Learn how different countries bend the clean lager family, without anything heavy.' / 'Learn aroma, bitterness, haze, and balance as separate ideas.' / 'Dark beer, made approachable and flavor-first.' / 'Big flavor, zero pressure. These count just as much.' / 'Tart, fruity, salty, funky — one small step at a time.' (the subtitles already nail the register; match them).

### [OPEN] Explore hero says a beer "is climbing" and shows "▲ +0" when its momentum is zero
*Surface:* Explore (home) hero panel — app  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:118`  ·  *Found by:* fleet

ExploreView's hero picks movers.first once ANY visible beer has popularity or momentum != 0, then maps momentum >= 0 to the word "climbing" and renders the metric as "▲ +N" with a plus sign. A beer whose momentum is exactly 0 (e.g. the platform's single real vote once it ages past the 7-day momentum window: popularity stays 1, momentum drops to 0) will make the first screen of the app claim "Brasserie Thibord is climbing in New Jersey." with a green "▲ +0" badge — fabricated movement, the exact class of falsehood P0-4 removed from the market detail screen. Today's live data happens to render honestly (the one voted beer still has momentum 1), but the dishonest state is guaranteed to occur by simple time decay with no new activity. docs/21 P1-9 gates the movers rail on momentum != 0 but does not cover this hero string or its "▲ +" metric.

**Evidence:** ExploreView.swift:118 subtitle = "\($0.brewery) is \($0.momentum >= 0 ? "climbing" : "sliding") in …" and :121 metric = "\($0.momentum >= 0 ? "▲ +" : "▼ ")\(abs($0.momentum))" → momentum==0 yields "is climbing" + "▲ +0". Gate at :42-44: hasMarketActivity accepts popularity != 0 alone, and movers (:39) sorts by momentum so a 0-momentum beer can be movers.first. Live DB: beer_trend max(momentum)=1 from the single real vote — decays to 0 after 7 quiet days while popularity stays 1.

**Fix:** Make the hero three-state: momentum > 0 → "climbing" with "▲ +N"; momentum < 0 → "sliding" with "▼ N"; momentum == 0 → steady wording ("is holding steady in New Jersey") with a neutral metric (no arrow, no plus). Also pick heroBeer from beers with momentum != 0 first, falling back to the honest no-activity hero ("Your beer radar") rather than a zero-momentum row, matching the P1-9 rail gating.


## P2

### [OPEN] Any scene resize mid-round (device rotation) restores cleared cups while keeping score and balls
*Surface:* Games / Beer Pong  ·  *Anchor:* `app/Tapt/Features/Games/BeerPongGame.swift:99`  ·  *Found by:* fleet

PongScene.didChangeSize wipes the world and calls rackUp() + spawnBall() but does not reset score, streak, ballsLeft, or roundOver. Rotate the phone (no orientation lock is set in project.yml or Info.plist) after clearing 4 cups and the full 6-cup rack reappears while the HUD still shows your points, and any in-flight ball vanishes after ballsLeft was already decremented. The screen contradicts itself: score says cups fell, table says they never did.

**Evidence:** override func didChangeSize(_ oldSize: CGSize) { guard size.width > 0, children.contains(world) else { return }; world.removeAllChildren(); buildTable(); layoutHUD(); rackUp(); spawnBall() } (BeerPongGame.swift:99-106). rackUp() rebuilds all 6 cups unconditionally; score/streak/ballsLeft only reset in restart().

**Fix:** In didChangeSize, instead of re-racking blindly, remember how many cups were standing and rebuild only that many (or simplest honest option: treat a resize as a table reset by calling restart() so score and rack always agree). Also lock the games screens to portrait or keep the scene size fixed with .aspectFill so rotation cannot rebuild the world mid-round.

### [OPEN] One team can be awarded gold, silver, and bronze in the same event, double-counting points in the medal table
*Surface:* Games / Beer Olympics  ·  *Anchor:* `app/Tapt/Features/Games/BeerOlympicsView.swift:181`  ·  *Found by:* fleet

Each medal row in an event card is an independent picker over all teams with no exclusion, so tapping Team A on all three rows gives Team A 6 points from a single event. The medal table then shows standings that cannot happen in any real competition, which reads as broken scorekeeping on a multi-hour game night where this board is the source of truth for the champion.

**Evidence:** medalPicker(_:selection:) toggles selection.wrappedValue = on ? nil : team.id with no check against the event's other medal slots (BeerOlympicsView.swift:172-195); standings sums golds*3 + silvers*2 + bronzes per team with no dedupe (lines 18-26).

**Fix:** When a team is selected for one medal in an event, clear that team from the event's other two medal slots (in the Button action, before persist(): if event.silver == team.id set it nil, etc.), or filter already-medaled teams out of the other pickers' ForEach. Five lines inside eventCard/medalPicker.

### [OPEN] "Beer Trivia" tile opens the generic category chooser and advertises a pass-the-phone rule that does not exist
*Surface:* Games / Beer Night Mode  ·  *Anchor:* `app/Tapt/Features/Games/BreweryModeView.swift:40`  ·  *Found by:* fleet

The Beer Night Mode tile is titled "Beer Trivia" with subtitle "Miss one, pass the phone", but it opens TriviaGame() with no category, landing the user on the 5-way category chooser (Mixed, Beer, Pop Culture, Fun Facts, General) instead of beer trivia, and TriviaGame has no pass-the-phone or miss-one mechanic anywhere: it is a solo scored quiz. The tile promises a mode the app does not have.

**Evidence:** NavigationLink { TriviaGame() } label: { tile("Beer Trivia", "Miss one, pass the phone", ...) } (BreweryModeView.swift:40-42). TriviaGame's default init leaves category nil so body shows the chooser (GamesView.swift:117-131); no turn or player state exists in TriviaGame.

**Fix:** Open TriviaGame(title: "Beer Trivia", category: .beer) so the tile does what it says, and change the subtitle to describe the real game (for example "Quick-fire beer questions"), or keep the house-rule flavor by rewording to make clear pass-the-phone is a table convention, not an app mode.

### [OPEN] Daily 5 subtitle promises questions "from the beer world" but the run is mixed general knowledge; tiles say "wild facts" but the category is named "Fun Facts"
*Surface:* Games / hub + Trivia copy  ·  *Anchor:* `app/Tapt/Features/Games/GamesView.swift:17`  ·  *Found by:* fleet

The Daily 5 tile reads "A quick five-question run from the beer world." while the game is hard-wired to category .mixed, so a daily set routinely includes "What is the capital of Australia?" and "What is the largest planet in our solar system?", which contradicts the tile on the very next screen. Separately, both the Trivia tile subtitle and the in-game chooser copy call one category "wild facts" while the actual category button is labeled "Fun Facts", a small name mismatch on adjacent screens.

**Evidence:** GamesView.swift:16-17: TriviaGame(title: "Daily 5", questionLimit: 5, category: .mixed) with subtitle "A quick five-question run from the beer world."; pool(.mixed) returns all 46 questions including the general set (TriviaData.swift:34-38, 125-146). "wild facts" appears at GamesView.swift:21 and 144 vs rawValue "Fun Facts" at TriviaData.swift:19.

**Fix:** Either change the Daily 5 subtitle to match reality ("Five quick questions, beer and beyond, same set for everyone today.") or pass category: .beer if the beer-world promise should hold (mixed is the better product; fix the copy). Replace "wild facts" with "fun facts" in both strings so the tile, chooser, and category button use one name.

### [OPEN] Team flag is a hash-random country flag, so a team named after a real country shows the wrong flag
*Surface:* Games / Beer Olympics  ·  *Anchor:* `app/Tapt/Features/Games/BeerOlympicsView.swift:272`  ·  *Found by:* fleet

flagEmoji hashes the team name into an index over the Passport country flag list, so a team named "Germany" or "Team USA" will usually display an unrelated flag (for example a Japanese or Brazilian flag) beside its name in the roster and medal table. The Beer Olympics guide even tells players "names and countries mandatory", encouraging country names, while the input placeholder says "(country optional)". To a user this looks like a matching bug, not a cosmetic garnish.

**Evidence:** var flagEmoji: String { let flags = PassportData.countries.map(\.flag); var hash = 0; for scalar in name.unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) }; return flags[abs(hash) % flags.count] } (BeerOlympicsView.swift:271-277). Guide copy "names and countries mandatory" at GameGuidesData.swift:165 vs placeholder "Team name (country optional)" at BeerOlympicsView.swift:95.

**Fix:** Before falling back to the hash, check the team name against PassportData.countries (case-insensitive contains on country name) and use the real flag when it matches; keep the hash flag only for non-country names. Also align the two copy lines: pick either "country optional" everywhere or drop "mandatory" from the guide step.

### [OPEN] First-ever successful flip shows "1 in a row!" streak message
*Surface:* Games / Flip Cup  ·  *Anchor:* `app/Tapt/Features/Games/FlipCupGame.swift:169`  ·  *Found by:* fleet

After any landing where the current streak equals the best, the reset message becomes a fire-emoji streak call-out. On a player's first successful flip streak and best are both 1, so the screen celebrates "1 in a row!", which reads as a bug and cheapens the real streak moments. The same line also swaps the result flash text mid-fade because the flash Text reads the mutable message.

**Evidence:** if success && streak == best && best > 0 { message = "\u{1F525} \(best) in a row!" } (FlipCupGame.swift:169). streak=1, best=1 after the first success (lines 152-154). The flash at line 45 renders `message` while visible.

**Fix:** Require a real streak before the call-out: change the condition to streak >= 2 (keeping streak == best if the intent is only new bests), and capture the flash text into a separate let at result time so the later message change cannot rewrite the on-screen flash mid-animation.

### [OPEN] Inventory audit: all 11 advertised games are real implementations, zero stubs, no false multiplayer or persistence claims
*Surface:* Games / hub inventory  ·  *Anchor:* `app/Tapt/Features/Games/GamesView.swift:8`  ·  *Found by:* fleet

Requested inventory finding. Every tile in GamesView opens a functioning implementation: Darts (flick physics, 2P pass-and-play, 18-dart game with result panel), Connect 4 (full win/draw logic), Daily 5 (date-seeded shared set, verified deterministic via SplitMix64 over UTC yyyymmdd), Trivia (46 real, verifiable questions across 4 categories with honest per-category counts shown), Tapt Deck (22 house prompts), Beer Pong (real SpriteKit physics, honest trajectory preview matching the -14 gravity at 150 px/m, best score persisted in UserDefaults), Flip Cup, Quarters, Beer Night Mode (roulette + links), Beer Olympics (persisted local scoreboard), Game Night Guides (11 original guides). The GameTile "SOON" badge path is dead code since every tile passes ready: true. No game claims online multiplayer; all copy says pass-and-play or table play, which is accurate. Trivia facts spot-checked (Pilsner 1842 Plzen, India most populous, Reinheitsgebot 1516, London Beer Flood 1814, Scrantonicity, bride-ale etymology) and all hold.

**Evidence:** GamesView.swift:8-51 links all 11 destinations to the implementations read in full: DartsGame.swift, ConnectFourGame.swift, TriviaData.swift + TriviaGame (GamesView.swift:103-300), CardDeckGame.swift, BeerPongGame.swift (UserDefaults key pongBestScore at line 77), FlipCupGame.swift, QuartersGame.swift, BreweryModeView.swift, BeerOlympicsView.swift (@AppStorage beerOlympicsState), GameNightGuidesView.swift + GameGuidesData.swift. Daily 5 seed: GamesView.swift:288-299.

**Fix:** No action required for launch on this point; optionally delete the unused ready: false / SOON branch in GameTile (GamesView.swift:87-93) since every game ships ready.

### [OPEN] Eight picker countries have under one screen of beers; South Korea has 2 and Singapore 4
*Surface:* Explore country boards (coverage distribution)  ·  *Anchor:* `app/Tapt/Core/BeerModels.swift:62`  ·  *Found by:* fleet

Coverage is extremely lopsided: Global 10,288 / France 3,133 / Germany 1,181 / Belgium 633 / Netherlands 324 / Spain 299, but picker countries at the tail are nearly empty: South Korea 2, Singapore 4, New Zealand 11, South Africa 15, Mexico 16, Brazil 20, Portugal 30, Finland 37. Those boards render a 2-4 row 'Top in South Korea' that looks broken rather than young, while non-picker countries like Lithuania (288) and Croatia (195) hold far more data. The rows themselves are real (honest), so this is polish/coverage, not honesty.

**Evidence:** Live per-region counts from beer_trend_feed: {'South Korea':2,'Singapore':4,'New Zealand':11,'South Africa':15,'Mexico':16,'Brazil':20,'Portugal':30,'Finland':37} vs unlisted {'Lithuania':288,'Croatia':195,'Switzerland':88}. Picker list at BeerModels.swift:62-68.

**Fix:** Set a floor for chip inclusion (e.g. only show country chips with >= 25 feed rows, recomputed from data at guide-load time) and swap the thinnest chips for the well-covered unlisted countries, or keep the chips but give sub-floor boards a purpose-built copy line ('Only N beers from South Korea so far - scan one to grow it') so a 2-row board reads as an invitation instead of a bug.

### [OPEN] 'Votes 24h' stat actually counts votes plus check-ins (docs/21 P0-5c rename never landed in code)
*Surface:* Market detail sheet — stats grid  ·  *Anchor:* `app/Tapt/Features/Market/MarketBeerDetailView.swift:150`  ·  *Found by:* fleet

The third stat tile labels beer.volume as 'Votes 24h', but vol24 in the refresh unions beer_vote with checkin_event rows. The moment check-in logging is used, this tile will claim more votes than the 'Total votes' tile next to it — two stats contradicting each other on the same screen. docs/21 P0-5(c) prescribed renaming it to 'Activity 24h' and the P0 batch is marked done, but the shipped string is still 'Votes 24h'. Currently invisible (0 check-ins in the last 24h live), so P2 today; it becomes a same-screen contradiction on day one of real usage.

**Evidence:** MarketBeerDetailView.swift:150: stat("Votes 24h", "\(beer.volume)", ...). 0067:65-71 vol_agg: 'select beer_id ... from public.beer_vote UNION ALL select beer_id ... from public.checkin_event ... where ts > now() - interval 24 hours'. Live: checkins_24h = 0 (not yet user-visible). docs/21-EXECUTION-PLAN.md P0-5(c): 'rename Votes 24h → Activity 24h (it counts check-ins too)'.

**Fix:** One-word change: rename the tile label to 'Activity 24h' (and its icon already suits activity). No server change needed.

### [OPEN] Steady-state explanation omits votes, contradicting the sentiment card below it on the only voted beer
*Surface:* Market detail sheet — 'Why it's moving' card  ·  *Anchor:* `app/Tapt/Features/Market/MarketBeerDetailView.swift:92`  ·  *Found by:* fleet

For a flat, non-seasonal beer the card says 'Steady. Standing comes from season fit, real awards, and notability.' On the board's one genuinely voted beer (La saison du chasseur, standing 24 = 10 base + 6 notability + 8 vote points), a third of the number comes from the community vote, and the sentiment card directly below shows 'Buy 1'. The explanation names three inputs and skips the fourth — the one the product's whole footer says will dominate.

**Evidence:** MarketBeerDetailView.swift:91-94 fallback string omits votes. Live LASA row: net 24, votes 1, ups 1, change 0, reason null → renders this exact copy above a 'Buy 1' sentiment bar. Standing composition from 0067 scored CTE: 10 + notability 6 + vote_pts 8.

**Fix:** Change the string to 'Steady. Standing comes from season fit, real awards, notability, and community votes.' — matching the footer's own list of inputs.

### [OPEN] Misspelled query returns only misspelled rows - 'guiness' finds 11 junk entries and none of the real Guinness lineup
*Surface:* Catalog search (misspellings)  ·  *Anchor:* `supabase/migrations/0066_materialize_display_names.sql:26`  ·  *Found by:* fleet

catalog_search matches with ilike substring only, so the extremely common misspelling 'guiness' matches just the 11 rows whose stored name/brewery is ALSO misspelled ('Guiness Original', 'Guiness Foreign Ultra', brewery 'Guiness'/Puerto Rico) and none of the correctly spelled Guinness beers. The user's takeaway is a catalog of typo'd knockoffs. pg_trgm is installed and match_beers already uses the % operator, so a fuzzy fallback exists in the codebase but not on this surface.

**Evidence:** Live: select count(*) from catalog_search('guiness',...) = 11 (vs 30 for 'guinness'); the where clause is only ilike '%'||p_query||'%' on display_name/name/brewery. match_beers def uses b.name % q.value (trigram) one function away.

**Fix:** In catalog_search, when the ilike branch yields few/no rows (or unconditionally as an OR), add a trigram branch: display_name % p_query or brewery % p_query, ranked by similarity desc. Same migration as the relevance fix; verify 'guiness' returns the canonical Guinness beers first.

### [OPEN] 867 beers render a completely empty facts card on the beer page
*Surface:* Beer page (sparse beers)  ·  *Anchor:* `app/Tapt/Features/Beer/BeerDetailView.swift:30`  ·  *Found by:* fleet

factsCard(d) is the only unconditional section in BeerDetailView (line 30); every row inside it is conditional (abv, ibu, substyle, country, website). For beers with none of those - 867 name_ok beers live have no ABV, no brewery, no style, no IBU, no substyle - it renders an empty surface-colored rounded rectangle: a stray blank pill between the note card and the Beer School link. Verified against live beer d44f4ec6 ('Guinness draught': all facts null), whose page is title + image + votes + note + blank card. Blank beats invented, but a visibly empty card just looks broken.

**Evidence:** Live: beer_detail('d44f4ec6-...') returns style null, abv null, brewery_name null, brewery_country null - every factsCard row's `if let` fails, leaving .padding(.vertical, 6).background(Brand.surface) as an empty shape. Count query: 867 name_ok beers have abv, brewery_id, style, ibu, substyle all null.

**Fix:** Gate the card like every other section: compute hasFacts (abv ?? ibu ?? substyle ?? breweryCountry ?? breweryWebsite != nil) and only render factsCard when true - one-line condition at BeerDetailView.swift:30, consistent with the file's own 'sections with no real data simply don't render' contract.

### [OPEN] Live DB is at migration 0078 while the repo mirror ends at 0068 - live catalog_search exists in no repo file
*Surface:* Repo integrity (migrations mirror)  ·  *Anchor:* `supabase/migrations`  ·  *Found by:* fleet

The audit brief states live matches migrations through 0068, but supabase_migrations.schema_migrations shows 0069_overture_beer_places through 0078_advisor_cleanup applied live (timestamps 2026-07-13 UTC, i.e. within hours). The live catalog_search definition (row_number dedupe partitioned by display_name + brewery bucket) matches none of 0026/0028/0050/0054/0065/0066 in the repo. If the working repo also lacks 0069-0078, the mirrored-migration rule is broken and a future deploy of the repo files would regress the live dedupe back to 0066's name-only version (re-collapsing different breweries' same-named beers into one row). Flagging because I could only verify the snapshot I was given.

**Evidence:** Live: select version, name from supabase_migrations.schema_migrations order by version desc -> 0078_advisor_cleanup ... 0069_overture_beer_places above 0068 newsletter_canspam. grep for 'package_rank'/'row_number' across supabase/migrations/*.sql: no hits; ls shows the directory ends at 0068_newsletter_canspam.sql.

**Fix:** Confirm the working repo (not the audit snapshot) contains 0069-0078 mirrors; if not, export the live definitions (pg_get_functiondef) into numbered migration files in the same commit style as the rest of the lineage so repo == live holds before launch.

### [OPEN] All Cellar/Passport stats are computed from a fetch capped at 100 rows, so 'pours logged' can never exceed 100 and every derived stat silently undercounts
*Surface:* Cellar stats (hero + Passport)  ·  *Anchor:* `app/Tapt/Core/CheckinService.swift:172`  ·  *Found by:* fleet

CheckinService.mine() fetches limit(100), and CellarView/PassportView compute pours, styles, states, and countries from that array. Once a user passes 100 pours the hero reads '100 pours logged' forever, the Centurion badge (threshold 100) triggers exactly at the cap and nothing beyond it can move, and style/country counts freeze at whatever the last 100 rows contain. Numbers on screen stop being true precisely for the most engaged users. Not user-visible today (live checkin_event has 0 rows after the 2026-07-11 launch reset) but it is a wrong-number time bomb, and the docs/21 P1-12 Cellar pass does not cover it.

**Evidence:** CheckinService.swift:171-172 '.order("event_ts", ascending: false).limit(100)'; CellarView.swift:71 subtitle interpolates checkins.count; PassportData.swift:38 Centurion threshold 100; live 'select count(*) from checkin_event' = 0.

**Fix:** Compute the stats server-side (a small SECURITY DEFINER my_cellar_stats() returning pours/styles/states/countries from the full history, or reuse the existing profile stats RPC lineage) and keep the 100-row fetch purely for the visible journal list, with pagination for older pours.

### [OPEN] State shelf guides cover only 36 of 50 states and the missing 14 include the biggest beer states (Pennsylvania, Ohio, Washington, Florida, Illinois, North Carolina)
*Surface:* Cellar regional shelves / Passport state shelves  ·  *Anchor:* `app/Tapt/Features/Cellar/CellarView.swift:118`  ·  *Found by:* fleet

region_beer_guide has 36 state-scope rows. Pours in Pennsylvania, Ohio, Washington, Florida, Illinois, North Carolina, Georgia, Minnesota, Missouri, Arizona, Alabama, Alaska, Delaware, or Oklahoma can never unlock a state shelf, while North Dakota and Wyoming have shelves. The Cellar shelf rail and Passport 'State shelves' section present shelves as a collection tied to where you pour; a Philadelphia user (heavy craft market, 194 PA venues in the DB) does not have a shelf to unlock, which reads as the app not knowing their state exists.

**Evidence:** Live: select scope, count(*), state names from region_beer_guide -> 18 country guides, 36 state guides; state list lacks Alabama, Alaska, Arizona, Delaware, Florida, Georgia, Illinois, Minnesota, Missouri, North Carolina, Ohio, Oklahoma, Pennsylvania, Washington. Venue table has 194 Pennsylvania, 217 Ohio, 328 Washington, 167 Florida rows, so pours in those states are expected.

**Fix:** Author the 14 missing state guide rows with the same real style-history content standard as the existing 36 (hero style, cellar prompt, passport phrase), prioritizing PA/OH/WA/FL/IL/NC; until then, have the shelf UI show 'Shelf coming soon' for a visited state with no guide instead of nothing.

### [OPEN] Scan save and OFF add-to-catalog silently do nothing when the session is missing, while the same case in LogPourView shows an explanation
*Surface:* Scan (save/add flows)  ·  *Anchor:* `app/Tapt/Features/Scan/ScanView.swift:356`  ·  *Found by:* fleet

ScanView.save() and addAndLog() both start with 'guard let uid = session.user?.id else { return }'. If the session is nil (expired token, the known sim-auth persistence gap), tapping Log or 'Add to Tapt + log' does nothing at all: no error, no state change, button stays enabled. LogPourView handles the identical case with 'Your sign-in expired. Sign out and back in, then log the pour.' The scan path should not be the one flow where a tap can be swallowed silently.

**Evidence:** ScanView.swift:356 and :293 'guard let uid = session.user?.id else { return }' (bare return); contrast LogPourView.swift:350-353 which sets errorMessage. ScanView already has a saveError alert pipeline (lines 77-84) it could reuse.

**Fix:** In both guards set saveError to the same sign-in-expired copy used by LogPourView so the existing alert fires, instead of returning silently.

### [OPEN] Inventory: checkin_event is empty today (honest launch reset) but every pour writes 20+ real fields the current Cellar never shows; guides, venues, and display names are already in place for an expansive rebuild
*Surface:* Cellar rebuild inventory (data available today)  ·  *Anchor:* `supabase/migrations/0007_backend_contract_and_content_pipeline.sql:249`  ·  *Found by:* fleet

What exists for a rebuilt progressive Cellar, all verified live. Volume: checkin_event has 0 rows and 0 users (prod checkins cleared 2026-07-11 for the fresh-product rule), so any rebuild ships against empty state first. Schema: 33 columns; each log_checkin write snapshots beer_id, brewery_id, sku_canonical_id, style, substyle, abv, ibu, srm from the catalog plus rating, flavor_tags, glassware, venue_id, occasion, on_off_premise, and server-derived day_of_week, daypart (morning/afternoon/evening/late_night), season, event_ts, source, consent fields. Captured today but never displayed anywhere: flavor_tags, glassware, occasion, daypart, season, abv/ibu/srm snapshots. Plumbed in the RPC but never captured by any UI: photo_url, price_paid, price_tier, purchase_intent_flags, geo_bucket_h3. Supporting content: 36 state + 18 country region_beer_guide rows with hero_style, flavor_notes, signature_drinks, top_styles, cellar_prompt, passport_phrase; 8,694 venues (5,491 US) whose external_ids carry city/region/country with US regions as full state names matching the passport matching logic; beer_catalog display_name/name_ok generated columns ready for clean rendering. An honest rebuilt Cellar can therefore show per-style and per-ABV breakdowns, flavor-tag taste profiles, glassware and occasion habits, daypart/season rhythms, venue history and state/country maps, without inventing anything, but only after the venue RLS policy and raw-name fixes land.

**Evidence:** Live: select count(*), count(distinct user_id) from checkin_event = 0, 0. information_schema.columns for checkin_event lists the 33 columns named above. log_checkin body (0007:300-420) inserts style/substyle/abv/ibu/srm from v_beer and computes daypart/season/day_of_week server-side. region_beer_guide: 36 state + 18 country rows. venue: 8,694 rows, US regions are full names ('California' 803, 'Pennsylvania' 194) with country 'United States'. beer_catalog.display_name/name_ok stored generated columns (0066).

**Fix:** When rebuilding Cellar, read from what is already written: add sections for flavor-tag profile, glassware/occasion split, daypart and season rhythms, per-style ABV spread, and a venue timeline, all computed from checkin_event fields that log_checkin already populates; add UI capture for photo_url and price_tier only when the display exists; fix the venue policy (P0) and name aliasing (P0) first so the underlying joins are truthful.

### [OPEN] Board rows are context-thin and inconsistently interactive: two-space separator, truncation, unused avatars, dead taster/style rows, unexplained rating scale
*Surface:* Leaderboards > row context and interactions  ·  *Anchor:* `app/Tapt/Features/Community/LeaderboardsView.swift:102`  ·  *Found by:* fleet

A cluster of polish gaps that together make the flagship board feel unfinished: (a) the beers subtitle joins brewery/style/country with two literal spaces while every other list in the app uses ' · ', and lineLimit(1) truncates long OFF brewery names ('Brauerei C. & A. Veltins GmbH & Co. …') with no minimumScaleFactor; (b) tasters rows decode avatarUrl but always render an initial-in-a-circle, so real avatars never show; (c) beers rows navigate to BeerDetailView but tasters and styles rows are inert — tapping a person or a style goes nowhere (no public profile card, no style page), an inconsistency users read as broken; (d) the styles board's 'Average rating 4.20' never states the scale (out of 5); (e) a taster whose pours all lack style/brewery metadata shows '0 styles · 0 countries' beside a positive pours count, which reads as a bug. None of these are dishonest, but they are all on the screen the Explore tab advertises as a headline feature.

**Evidence:** LeaderboardsView.swift:102 `.joined(separator: "  ")` + `.lineLimit(1)`; :144-148 initial-only avatar (LeaderTaster.avatarUrl decoded at SuperappServices.swift:153 but never referenced in the view); :141-167 tasters ForEach has no NavigationLink (beers rows wrap in one at :94); :190-193 'Average rating %.1f' with no scale; :153 '\(taster.styles) styles · \(taster.countries) countries' renders zeros because the SQL count filters only null/empty (live def: `count(distinct ce.style) filter (where coalesce(ce.style,'') <> '')`).

**Fix:** One pass: switch the subtitle separator to ' · ' and add minimumScaleFactor(0.85); load avatarUrl via AsyncImage with the initial as fallback; wrap taster rows in a NavigationLink to the existing public profile card (public_profile RPC already ships it) and style rows in a link to CatalogView pre-filtered to that style; change the rating line to 'Average rating 4.2 / 5'; suppress the 'styles · countries' line when both are zero.

### [OPEN] Five pickable countries never get their flag: Finland, New Zealand, Portugal, Singapore, South Africa fall back to 🍺 while Germany gets 🇩🇪
*Surface:* Explore board rows (country flags)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:436`  ·  *Found by:* fleet

The row-subtitle flag map covers only 19 countries. Beers from five countries the picker itself offers — Finland, New Zealand, Portugal, Singapore, South Africa — plus any 'Czech Republic'-spelled rows render the generic beer-mug emoji next to a real brewery and style, which reads as missing data on boards where neighboring rows show proper flags. The dead displayFlag(_:)/guideCard code (lines 228-257, 398-421, unreferenced since the guide module was removed) has the same gap and is already slated for deletion in docs/21 P1-9.

**Evidence:** flag() dictionary (lines 436-443) keys: Australia, Austria, Belgium, Brazil, Canada, Czechia, Denmark, France, Germany, Ireland, Italy, Japan, Mexico, Netherlands, Poland, South Korea, Spain, United Kingdom, United States — no Finland/New Zealand/Portugal/Singapore/South Africa, all five present in BeerRegions.countries (BeerModels.swift:62-68) and all five have live rows (37/11/30/4/15).

**Fix:** Replace both hand-typed emoji tables with a computed flag from the ISO country code (regional-indicator scalar math over a country-name→ISO map, or store iso_code on brewery), which covers every present and future country in one place; docs/21 P2-14 already prescribes exactly this derivation for the Passport flags — reuse it here.

### [OPEN] Onboarding orders regions Global→countries→states while Explore orders states→Global→countries, and neither surfaces the selection consistently
*Surface:* Onboarding region step vs Explore picker  ·  *Anchor:* `app/Tapt/Features/Onboarding/OnboardingView.swift:111`  ·  *Found by:* fleet

The same 74-region vocabulary is presented in two different orders: onboarding's home-base list starts at Global then countries then states (OnboardingView regionStep), while the Explore picker starts at Alabama with the default-selected 'Global' chip 51 positions off-screen (no ScrollViewReader; the scroll-to-selection half is tracked in docs/21 P1-9). A user who picked their state during onboarding lands on Explore seeing an unrelated alphabetical state row with no visible indication of what is selected. Included for the ordering inconsistency between the two surfaces, which P1-9 does not cover.

**Evidence:** OnboardingView.swift:111 `ForEach(["Global"] + BeerRegions.countries + BeerRegions.states, ...)` vs ExploreView.swift:262 `ForEach(BeerRegions.all, ...)` where BeerRegions.all = states + ["Global"] + countries (BeerModels.swift:69).

**Fix:** Define one canonical presentation order in BeerRegions (Global first, then the user's country bucket — US states — then countries) and use it in both surfaces; add the P1-9 ScrollViewReader scroll-to-selection in the Explore picker so the active chip is always visible on entry.

### [OPEN] Styles board counts moderated-hidden checkins and shows single-pour 'Average rating' with no minimum sample
*Surface:* Leaderboards > Styles board  ·  *Anchor:* `supabase/migrations/0009_superapp_foundations.sql:481`  ·  *Found by:* fleet

leaderboard_styles has no moderation_status filter, unlike the live leaderboard_tasters (visible-only) and public_profile (visible-only): a checkin hidden by moderation still adds to a style's pour count and its rating still moves the displayed average. Separately, avg(ce.rating) is shown with n=1 — the first pour of a style prints 'Average rating 5.0' as if it were a community statistic. Task #57's 'stat cutoff' covers the sample-size half; the moderation gap is untracked.

**Evidence:** Live prosrc of leaderboard_styles: `from checkin_event ce where coalesce(ce.style,'') <> ''` — no moderation_status predicate; live leaderboard_tasters joins `on ce.user_id = up.id and ce.moderation_status = 'visible'`. LeaderboardsView.swift:190-193 renders avgRating whenever non-null.

**Fix:** Add `and ce.moderation_status = 'visible'` to leaderboard_styles, and either return avg_rating as null below a floor (e.g. fewer than 3 rated pours) or also return the rated-pour count so the app can suppress the 'Average rating' line under the floor.

### [OPEN] Ties are ordered by the raw catalog name while the cleaned display name is shown, so equal-score rows appear randomly ordered
*Surface:* Leaderboards > Beers board (tie ordering)  ·  *Anchor:* `supabase/migrations/0051_leaderboard_clean_names_styles.sql:21`  ·  *Found by:* fleet

leaderboard_beers orders ties by b.name (raw OFF string) but displays tapt_display_name(b.name). A beer stored as '6X25 CL LEFFE RUBY RUBY' sorts under '6' while rendering as 'Leffe Ruby', so two 1-vote beers can show as Leffe Ruby above Augustiner one day and the visual order looks arbitrary/unstable to users comparing rows with identical vote counts.

**Evidence:** Deployed prosrc: `order by (s.net + s.checkins * 2) desc, b.name` while the select returns `public.tapt_display_name(b.name)`. 0064 documents raw names like '6X25 CL LEFFE RUBY RUBY' that display-clean to 'Leffe Ruby'.

**Fix:** Order ties by the same string the user sees: `order by (s.net + s.checkins * 2) desc, lower(b.display_name)` (the materialized column from 0066, which also avoids re-running the normalizer per row).

### [OPEN] Generic descriptor names pass the junk-name gate: 54 brewery-less beers named 'Biere blonde' / 'Bière blonde' / 'Bière blanche' are rankable
*Surface:* Leaderboards > Beers board + catalog browse  ·  *Anchor:* `supabase/migrations/0064_beer_name_normalize_v3_retail_strings.sql:51`  ·  *Found by:* fleet

tapt_name_ok blocks single-word style names (biere, ipa, lager...) and NA-suffixed phrases, but two-word French generic descriptors pass: live catalog has 'Biere blonde' x20, 'Bière blonde' x18, 'Bière blanche' x16, all name_ok=true with no brewery and no country. One vote on any of them puts a row on the beers leaderboard whose name is literally 'blonde beer' with blank subcopy — a junk display name by product law 3, and the accent/no-accent pair also means the market/search dedup treats them as two different beers.

**Evidence:** Live query (name_ok rows grouped by display_name+brewery+country): {'Biere blonde','','',20}, {'Bière blonde','','',18}, {'Bière blanche','','',16}. tapt_name_ok regex `^(bi[eè]res?|...)\.?$` only matches single bare words; the second regex only matches when an NA suffix is present.

**Fix:** Extend the tapt_name_ok blocklist to bare '<biere/bier/beer/cerveza> + color/style word' combinations with no other token (blonde, blanche, brune, ambrée, rousse, forte), i.e. names that are wholly generic descriptors, and rebuild the 0066 generated columns (documented requirement when the fn changes). These rows have no brewery, so nothing legitimate is lost — blank beats generic.

### [OPEN] Live leaderboard_tasters has privacy filters (social_visible, moderation) that exist in no repo migration — drift that a future migration could silently regress
*Surface:* Repo migrations mirror vs live DB  ·  *Anchor:* `supabase/migrations/0009_superapp_foundations.sql:432`  ·  *Found by:* fleet

The only definition of leaderboard_tasters in the repo is 0009's, which has no social_visible gate and no moderation_status filter. The live function has both. Whoever hardened it live never landed the SQL in supabase/migrations, so the stated invariant 'live DB matches through 0068' is false for this function, and any future migration that edits leaderboard_tasters starting from the 0009 text would drop the privacy gates without anyone noticing — users who set their profile private would reappear on the public tasters board.

**Evidence:** Live prosrc contains `where up.social_visible` and `on ce.user_id = up.id and ce.moderation_status = 'visible'`; grep across all 68 migration files finds leaderboard_tasters defined only in 0009, whose body has neither predicate.

**Fix:** Add a migration (or amend the mirror) that captures the current live body of leaderboard_tasters verbatim, so the repo is the source of truth again and the social_visible/moderation gates are protected by review. Audit the mirror for other silently-patched functions the same way (compare pg_proc prosrc against the repo per function).

### [OPEN] Profile-toggle consents are recorded against policy version 2026-07-08 while the published policy and onboarding say 2026-07-12
*Surface:* Consent records (policy_version drift)  ·  *Anchor:* `supabase/migrations/0007_backend_contract_and_content_pipeline.sql:547`  ·  *Found by:* fleet

record_privacy_choice defaults p_policy_version to '2026-07-08' and the app never passes one, so every consent flipped from the Profile screen is logged against policy version 2026-07-08. The onboarding RPC hardcodes '2026-07-12' and the live legal pages say 'Last updated: July 12, 2026'. The same account therefore carries consent rows attesting to two different policy versions depending on which screen was used, and the profile-toggle rows point at a version that predates the published policy — a contradiction inside the compliance record.

**Evidence:** Live def: record_privacy_choice(... p_policy_version text DEFAULT '2026-07-08') and coalesce(...,'2026-07-08'); live complete_profile_onboarding inserts policy_version '2026-07-12'; landing/privacy.html:21 = 'Last updated: July 12, 2026'. ProfileService.setPrivacyChoice sends no policy version (ProfileService.swift:46-57), and its own recordConsent wrapper's policyVersion parameter is dead.

**Fix:** Single source of truth: store the current policy version in one place (a config table or a SQL constant function) and have both record_privacy_choice and complete_profile_onboarding read it; update it in the same migration that changes the legal pages. Immediate patch: alter record_privacy_choice's default to '2026-07-12' so new profile-toggle rows match the published policy date.

### [OPEN] A failed 'Send a new email' hides the 6-digit code field even though the user may hold a valid code
*Surface:* Sign-in (email code entry)  ·  *Anchor:* `app/Tapt/Features/Auth/SignInView.swift:216`  ·  *Found by:* fleet

After the first successful send, the code-entry field is shown (gated on emailLinkSent). Tapping 'Send a new email' assigns emailLinkSent directly from the new attempt's result, so a failure — most commonly the OTP rate limit that this exact flow is known to hit — flips emailLinkSent back to false and removes the code field. The user sees the rate-limit error telling them to wait, is still holding a perfectly valid 6-digit code from the first email, and now has no field to type it into.

**Evidence:** SignInView.swift:216 'emailLinkSent = await session.sendEmailSignInLink(to: email)' unconditionally overwrites the previous true state; Session.sendEmailSignInLink returns false on any error including the 429 path it specifically formats ('Too many sign-in emails were requested...'). The code field at SignInView.swift:157 renders only 'if emailLinkSent'.

**Fix:** Make the flag sticky: 'let sent = await session.sendEmailSignInLink(to: email); if sent { emailLinkSent = true }' — a failed resend keeps the existing code field and shows the error above it. Optionally reset emailLinkSent only when the email address text changes, since a code for a different address would be misleading.

### [OPEN] State typo 'MIssouri' on a live venue row
*Surface:* Near You radar rows + venue detail sheet (state hygiene)  ·  *Anchor:* `app/Tapt/Features/NearYou/NearYouView.swift:241`  ·  *Found by:* fleet

Sandy Valley Brewing Co (Hillsboro) has region 'MIssouri', so its radar row and detail sheet read 'Hillsboro, MIssouri, United States'. It is also the reason the US has 52 distinct 'state' values in the venue table (50 states + DC + this typo), which will poison any future state facet or state board built on venue.region.

**Evidence:** Live SQL: SELECT name, city, region FROM venue WHERE external_ids->>'region'='MIssouri' → Sandy Valley Brewing Co, Hillsboro, id f40bc1bf-524c-44ee-a545-63772cc9bf94. Distinct US regions = 52.

**Fix:** One-row UPDATE setting region to 'Missouri', plus a normalization step in the OBDB ingest that maps region values case-insensitively against the canonical US state list (and rejects/flags non-matches) so upstream typos are corrected at import time.

### [OPEN] UK venues split across four country labels — 'United Kingdom' contains exactly one venue and it is mislabeled Scotland anyway
*Surface:* Near You map country data (World filter, country boards)  ·  *Anchor:* `app/Tapt/Features/NearYou/NearYouView.swift:49`  ·  *Found by:* fleet

Venue countries mix conventions: England (62), Scotland (9), Isle of Man (2), and a lone 'United Kingdom' (1 — BrewDog HQ, which is physically in Ellon, Scotland). Searching 'United Kingdom' in the radar returns 1 result while 74 UK venues exist; any country rollup counts these as four separate countries, inflating the 'countries' stat in the radar summary line.

**Evidence:** Live SQL country GROUP BY: England 62, Scotland 9, Isle of Man 2, United Kingdom 1; the UK row is name 'BrewDog HQ'. NearYouView.swift:50 counts Set(taptVenues.compactMap(\.country)) as 'countries'.

**Fix:** Pick one convention (keep the OBDB home-nation labels England/Scotland/Wales/Northern Ireland since 71 rows already use them), retag the BrewDog HQ row country='Scotland', and add the same canonical-country normalization to the ingest path so future imports cannot reintroduce the mixed convention.

### [OPEN] Raw Open Brewery DB jargon shown as venue types: 'Micro', 'Contract', 'Proprietor', 'Large', 'Location'
*Surface:* Near You radar rows + venue detail sheet (type labels)  ·  *Anchor:* `app/Tapt/Core/WorldBeerService.swift:29`  ·  *Found by:* fleet

typeLabel passes OBDB's industry taxonomy straight to drinkers: 4,654 venues display as 'Micro', 146 as 'Contract', 47 as 'Proprietor', 121 as 'Large', 1 as 'Location'. 'Contract' and 'proprietor' breweries typically have no visitable taproom at the stored address, yet they are pinned on a 'Beer Near You' map whose footer promises pubs and beer gardens — a drinker can walk to a pin and find an office. The words themselves also fail the plain-copy bar ('Proprietor' means nothing to a beer fan).

**Evidence:** Live SQL type distribution: micro 4654, brewpub 3379, regional 200, contract 146, large 121, proprietor 47, taproom 46, bar 43, brewery 28, nano 19, cidery 7, beergarden 3, location 1. WorldBeerService.swift:29-32 typeLabel returns the raw string; NearYouView.swift:243 and :364 render it capitalized.

**Fix:** Map OBDB types to drinker-facing words in typeLabel (micro/nano/regional/large/brewery → 'Brewery', brewpub → 'Brewpub', beergarden → 'Beer garden', location → 'Brewery'), and either exclude contract/proprietor rows from the map feed or badge them honestly ('Contract brewer — no taproom') so nobody drives to an address with nothing to pour.

### [OPEN] Em dashes in user-facing titles and one visible copy line, against the owner's voice rule
*Surface:* landing/index.html, dispatch.html, app-preview.html, pitch.html titles and copy  ·  *Anchor:* `landing/index.html:6`  ·  *Found by:* fleet

The owner's hard voice rule bans em dashes in user-facing strings, and the team's own legal-drafts checklist (E4) restates it for web pages. Browser-tab titles, og:title (link previews), and on-page copy are user-facing: index.html title and og:title read 'Tapt — THE Beer Superapp', dispatch.html title reads 'The Tapt Dispatch — one free email a week', app-preview.html title is 'Tapt — Live App Preview' and its visible intro line reads 'Live prototype — a web mockup...', and pitch.html's meta description uses one. Every other separator on the site is the approved middle dot.

**Evidence:** index.html:6 `<title>Tapt — THE Beer Superapp</title>`; index.html:8 og:title same; dispatch.html:6 `<title>The Tapt Dispatch — one free email a week</title>`; app-preview.html:148 '<span class="live">Live prototype</span> — a <b>web mockup</b>...'; pitch.html:7 meta description 'Tapt — THE Beer Superapp...'. legal-drafts/live-page-edits.md E4: 'no em dashes, no hype adjectives'.

**Fix:** Swap the em dashes for the site's existing middle-dot convention: 'Tapt · THE Beer Superapp', 'The Tapt Dispatch · one free email a week', 'Tapt · Live App Preview', and rewrite app-preview's intro as 'Live prototype: a web mockup...'. One pass over landing/*.html grepping for the em dash character keeps it enforced.

### [OPEN] No favicon on the legal/unsubscribe/app-preview pages, and no /favicon.ico fallback exists
*Surface:* landing/privacy.html, terms.html, unsubscribe.html, app-preview.html  ·  *Anchor:* `landing/privacy.html:3`  ·  *Found by:* fleet

The brand rule is the canonical beer-glass mark everywhere. index, dispatch, portal, menu, admin, pitch, and hq all link favicon.svg/favicon-32.png, but privacy.html, terms.html, unsubscribe.html, and app-preview.html have no favicon links at all, and the deploy has no favicon.ico for the browser's automatic fallback request. The pages where a wary user checks whether Tapt is legitimate (privacy, terms, unsubscribe from an email) are exactly the ones showing a blank/default tab icon.

**Evidence:** grep 'favicon' in privacy.html, terms.html, unsubscribe.html, app-preview.html returns nothing; landing/ contains favicon.svg and favicon-32.png but no favicon.ico; compare index.html:15-16 which links both.

**Fix:** Add the same two link tags used on index.html (`<link rel="icon" href="/favicon.svg" type="image/svg+xml">` and `<link rel="icon" href="/favicon-32.png" sizes="32x32">`, root-relative) to the head of privacy.html, terms.html, unsubscribe.html, and app-preview.html, and drop a favicon.ico copy of the 32px mark into landing/ so direct /favicon.ico requests also resolve.

### [OPEN] Nav polish: 'Beer market' anchor lands on the honesty manifesto, wordmark is not a home link, and mobile hides all nav links without a menu
*Surface:* landing/index.html navigation  ·  *Anchor:* `landing/index.html:207`  ·  *Found by:* fleet

Three small navigation inconsistencies on the homepage. (1) The nav link 'Beer market' points to #market, which is the 'The honest part / Real votes. Real beers.' section, not the market feature; the market visual is id='market-card' in the hero and the feature tile is in #features, so the click lands somewhere that does not match its label. (2) The index nav wordmark 'Tapt.' is a plain div while dispatch.html's wordmark is a link home, an inconsistency across pages. (3) At <=820px the CSS hides every nav link except the Get Tapt button with no hamburger, so Features/For business/Dispatch are unreachable from the mobile nav (only via scrolling or the footer).

**Evidence:** index.html:207 `<a href="#market">Beer market</a>` vs index.html:328 `<section id="market" class="biz"...>` titled 'Real votes. Real beers. Zero fabricated hype.'; index.html:204 `<div class="wordmark">Tapt<span>.</span></div>` (not a link) vs dispatch.html:157 `<a href="index.html" class="wordmark"...>`; index.html:54 `@media(max-width:820px){.nav-links a:not(.btn){display:none}}`.

**Fix:** Point the 'Beer market' nav link at the feature it names (give the market bento tile or hero card an anchor and use it, or retitle the #market section so the label matches), wrap the index wordmark in `<a href="/">` to match dispatch, and either add a minimal disclosure menu on mobile or accept the pattern deliberately and mirror it on dispatch (it already behaves the same way there).

### [OPEN] Em dashes in user-facing web strings violate the voice rule
*Surface:* Web · page titles and og tags (index, dispatch, app-preview)  ·  *Anchor:* `landing/index.html:6`  ·  *Found by:* fleet

The voice rule bans em dashes in user-facing strings, but they ship in browser-tab titles and link-preview text that every share unfurl displays: index.html <title> and og:title 'Tapt — THE Beer Superapp' (lines 6, 8), dispatch.html <title> 'The Tapt Dispatch — one free email a week' (line 6), pitch.html meta description 'Tapt — THE Beer Superapp…' (line 7), and app-preview.html title plus a prose em dash ('Live prototype — a web mockup…', line 148).

**Evidence:** index.html:6 `<title>Tapt — THE Beer Superapp</title>`; index.html:8 og:title same; dispatch.html:6 `<title>The Tapt Dispatch — one free email a week</title>`; app-preview.html:148 'Live prototype</span> — a <b>web mockup</b>…'.

**Fix:** Swap the title separators for the middle dot already used elsewhere on the site ('Tapt · THE Beer Superapp', 'The Tapt Dispatch · one free email a week') and rewrite the app-preview prose dash as a comma or colon. Leave the '—' empty-value placeholders in app-preview/portal JS alone; those are data dashes, not prose.

### [OPEN] "No No / Low catalog picks" reads as a stutter, and No / Low vs No/Low spacing is inconsistent
*Surface:* iOS app · Explore trending section (No/Low lens empty state)  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:325`  ·  *Found by:* fleet

When the No/Low lens filters out every trending pick, the empty state reads 'No No / Low catalog picks are available here yet.' — a double 'No' that a user has to parse twice. Separately, the term is spaced 'No / Low' in ten app strings but 'No/Low' in the Game Night Guides copy and on the landing page, so the brand term for the app's flagship inclusive feature isn't written one way.

**Evidence:** ExploreView.swift:325 'No No / Low catalog picks are available here yet. Turn off the lens in You to see the full catalog.'; GameGuidesData.swift:181 '…at least one No/Low pick.' vs FlightsView.swift:175 'No / Low friendly', ProfileView.swift:111 'No / Low lens by default'.

**Fix:** Rewrite the empty state to dodge the stutter: 'Nothing No / Low is trending here yet. Turn off the lens in You to see the full catalog.' Then pick one spelling ('No / Low' — it dominates) and align GameGuidesData.swift:181 and landing copy to it.

### [OPEN] Data-industry jargon in consumer copy: 'first-party signal', 'license-safe venue map layer', 'Seeded from'
*Surface:* iOS app · Explore leaderboards tile + Near You header  ·  *Anchor:* `app/Tapt/Features/Explore/ExploreView.swift:381`  ·  *Found by:* fleet

Two consumer-facing subtitles talk like the data room instead of the barstool: the Explore leaderboards tile reads 'Top beers, tasters, and styles, all first-party signal', and the Near You header reads 'Seeded from Tapt's license-safe venue map layer.' 'First-party signal', 'license-safe', 'seeded', and 'layer' are pitch-deck/engineering vocabulary; a drinker gets no meaning from them, and they run against the plain-voice rule the rest of the screen follows.

**Evidence:** ExploreView.swift:381 'Top beers, tasters, and styles, all first-party signal'; NearYouView.swift:125 'Seeded from Tapt's license-safe venue map layer. Local pubs, bars, taprooms, and beer gardens appear below when location is on.'

**Fix:** ExploreView:381 → 'Top beers, tasters, and styles, from real votes and pours.' NearYouView:125 → 'Real venues from open, credited sources. Local pubs, bars, taprooms, and beer gardens appear below when location is on.' Two string edits.

### [OPEN] Non-canonical brand caption 'The Beer Superapp in your pocket' (untracked instance beyond P1-15)
*Surface:* iOS app · Onboarding welcome screen  ·  *Anchor:* `app/Tapt/Features/Onboarding/OnboardingView.swift:71`  ·  *Found by:* fleet

The brand line is 'THE Beer Superapp' (sign-in screen, share card, landing, pitch all use it). Onboarding's welcome subtitle opens with 'The Beer Superapp in your pocket.' — lowercase 'The', the exact drift P1-15 is fixing on DiscoverView:15, but this instance isn't in that tracked line list and would survive the sweep. The first screen a new user reads shouldn't be the one place the brand is written differently.

**Evidence:** OnboardingView.swift:71 'The Beer Superapp in your pocket. Scan it, score it, play a round, and find local beer spots.' vs SignInView.swift:37 'THE Beer Superapp' and ShareCard.swift:35 'THE BEER SUPERAPP'.

**Fix:** Change to 'THE Beer Superapp, in your pocket. Scan it, score it, play a round, and find local beer spots.' and add OnboardingView.swift:71 to the P1-15 copy-sweep PR so both instances land together.

### [OPEN] Region guides ship invented "hero styles" ("Shore IPA", "Music City lager", "Ozark amber ale") that read as real regional style facts
*Surface:* Cellar Passport / regional beer guides — app + SQL content  ·  *Anchor:* `app/Tapt/Features/Cellar/PassportView.swift:174`  ·  *Found by:* fleet

The region_beer_guide table (36 states + 18 countries, surfaced in PassportView's "Regional beer guides" rails and CellarView stamps, and in the Explore hero subtitle "NJ leans shore ipa: …" when a guide is active) presents fabricated style names as each region's beer identity: New Jersey → "Shore IPA", Tennessee → "Music City lager", Arkansas → "Ozark amber ale", Nevada → "Desert pilsner". None of these are real beer styles (not BJCP, not trade vernacular), and the accompanying top_styles arrays are hand-invented with no vote/check-in/catalog data behind them — on a state/country surface in an app whose landing page promises "Zero fabricated data." A beer-literate user will recognize "Shore IPA" as made up, which undercuts trust in every real number nearby.

**Evidence:** Live query of region_beer_guide: {NJ: hero_style 'Shore IPA', top_styles [IPA,Lager,Porter]}, {TN: 'Music City lager'}, {AR: 'Ozark amber ale'}, {NV: 'Desert pilsner'}, {IN: 'Midwest cream ale'} — none map to beer_style_reference entries. Rendered at PassportView.swift:174 (Text(guide.heroStyle) on unvisited stamps), CellarView.swift:166, and ExploreView.swift:119 ("\($0.name) leans \($0.heroStyle.lowercased())"). docs/21 P1-9 only deletes the dead Explore guideCard; the Passport/Cellar renders are not tracked.

**Fix:** Replace hero_style with a real BJCP style name from beer_style_reference for each region (NJ → 'Hazy IPA', TN → 'American Lager', etc.) or reframe the string as an explicit editorial prompt ("Stamp it with any IPA") so it can't be read as a regional data claim; drop or relabel the invented top_styles arrays until first-party regional vote/check-in data exists to back a real 'top styles' figure, mirroring how the market board stayed empty until real votes arrived.
