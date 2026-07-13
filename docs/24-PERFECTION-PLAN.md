# 24 — PERFECTION PLAN

The one execution order for shipping Tapt to the App Store at ultra-high quality. Six lanes collapsed into one ranked sequence. Everything below is concrete enough to implement without re-opening the lane specs. Owner-only actions are called out explicitly; everything else an engineer/agent executes.

Hard laws in force: real data only (blank beats invented), no fabricated numbers, one canonical flat mark, plain non-salesy voice, verify in the running app before claiming a fix.

---

## 1. Do first (this session)

Ranked by user-visible leverage. Each is independently shippable.

### 1.1 Image speed — in-app cache (biggest instant win, no backend)
The most-used image view (`BeerThumb`) is a bare `AsyncImage` with zero caching or downsampling, hit by 8 grid/list screens against OFF's ~7s CDN. Fix the client first; the CDN mirror (section 6) lands incrementally after.

**Files + exact changes**
1. `app/Tapt/TaptApp.swift` — add a struct `init()` that sets a shared cache once at process start:
   ```swift
   init() {
       URLCache.shared = URLCache(memoryCapacity: 64*1024*1024,
                                  diskCapacity: 512*1024*1024, directory: nil)
   }
   ```
2. `app/Tapt/Core/BeerImageView.swift` — add a `Data` overload beside the existing fileURL `downsample`:
   ```swift
   static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
       guard let src = CGImageSourceCreateWithData(data as CFData,
             [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
       // reuse the identical kCGImageSourceCreateThumbnail* options block (lines 33-42)
   }
   ```
3. `app/Tapt/Core/ThumbLoader.swift` — new file. `enum ThumbLoader` with `nonisolated(unsafe) static let memory = NSCache<NSString,UIImage>()` (countLimit ~400, totalCostLimit ~64MB) and `static func load(_ urlString: String, maxPixel: CGFloat) async -> UIImage?`: key = `"\(urlString)|\(Int(maxPixel))"`; return memory hit; else `URLRequest` with `.returnCacheDataElseLoad`, `URLSession.shared.data(for:)`, `SubjectLift.downsample(data, maxPixelSize:)`, store with cost `w*h*4`. No Vision subject-lift here (too heavy for 44pt rows).
4. `app/Tapt/Features/Beer/CatalogView.swift:274-302` — rewrite `BeerThumb.body`: add `@State private var img: UIImage?`; keep the `Brand.surface` base + `Brand.malt` stroke + `mug.fill` fallback unchanged; render `Image(uiImage: img).resizable().scaledToFit().padding(size*0.075)` when loaded; add `.task(id: imageUrl) { if let u = imageUrl, !u.isEmpty { img = await ThumbLoader.load(u, maxPixel: size * UIScreen.main.scale) } }`. All 8 call sites (TonightView:230, CatalogView:185, ExploreView:338/399, ProfileView:80, PublicProfileView:175, LogPourView:130, LeaderboardsView:113, CellarView:298/406) inherit the fix with no per-site edits.

**Done-criteria:** build, run in sim, scroll Explore/Catalog/Leaderboards — each thumb downloads+decodes once, is instant on re-scroll and after relaunch; only real photos appear, glass glyph otherwise. Network inspector shows no repeat OFF fetch on re-scroll.

### 1.2 Recommend-a-beer engine (net-new headline feature)
Full spec in section 4. Ship the migration `0089_recommend_beer.sql`, `RecommendationService.swift`, and the "Picked for you" card on Explore. Honest empty state is the launch default (live signal is ~zero).

**Done-criteria:** in the isolated `demo` schema, a fixture user with 3-4 IPA up-votes gets an "a step out" pick with a real image + real reason (no numeric match score); a zero-signal user gets **no** card (server `centroid.n=0` gate returns empty). Never seed prod.

### 1.3 Venue ingestion — unblock the global map (highest-leverage backend action)
119,811 permissively-licensed Overture places across 219 countries are staged and paid-for, sitting idle because the apply RPC 500s. One batched-apply fix turns the map from 8,645 venues / 25 countries into ~128,000 venues / 219 countries. Full plan in section 3.

**Done-criteria:** `SELECT count(*) FROM venue` ≈ 128,000; `count(DISTINCT external_ids->>'country_code')` ≈ 219; `brewery_map_feed(500)` returns pub/taproom/beer_garden rows; a thin market (e.g. TH) shows real venues.

### 1.4 Scanner fixes — honesty + name quality + flow guards
The barcode path resolves but shows junk foreign names, promises a "label" scan that does not exist, and lets barcodes hijack the menu flow.

**Order + files:**
1. **Honesty (30 min, blocks nothing):** `app/Tapt/Features/Scan/ScanView.swift` — edit hint (line 151), permission copy (176), unsupported copy (166) to claim only "barcode, tap list, or venue QR." Drop every "label" promise until 1.4b exists.
2. **Name quality (highest scan win):** harden the `display_name` normalizer — strip locale nouns (`Bière/Biere/Bier/Cerveza/Birra/Piwo/Alus/Olut/Beer`), pack descriptors (`\d+X\d+`, `PK`, `Pack`, `6pack`, `flaske`, `zzgl. Pfand`), title-case, and when the token collapses to the brewery, fall back to `<Brewery> <style>`. Backfill all 11,061 `beer_catalog` rows. Gate `match_beers` to return only presentable names.
3. **Flow guards:** `ScanView.onChange(of: scanned)` (line 86) — add `guard !showResult && !menuMatching else { return }`. `loadMatches` (line 466) — dedupe by `(lowercased brewery + normalized name)` keeping highest confidence, drop text-query rows below 0.35 (keep exact-GTIN 1.0 unconditionally).
4. **Scan result image:** join `label_image_url` into `ScannedBeer`, render it in `matchRow` (line 315) via `BeerImageView` with a fast placeholder; switch `offCard` (line 357) to the OFF small thumbnail (`.200.jpg`).

**Done-criteria (name probe = acceptance test):** re-run the 6-barcode probe `3119780243570, 5000213101223, 7501064198076, 5410228147855, 59491118, 5035766063254` and confirm clean names ("Corona Extra", "Peroni", "Guinness Draught"), each with a real style and an image.

**Deferred to next session (real menu mode — biggest scanner engineering item, ship behind a toggle):** explicit Scan-beer vs Scan-menu toggle; in menu mode set `recognizedDataTypes = [.text()]` only; accumulate lines across frames (rolling dict keyed by normalized text in `DataScannerView`, replacing the per-frame reset at line 60); raise `prefix(10)` → `prefix(40)` with a live captured-count. Also loosen partner-QR parsing (`URLComponents` `v=` extraction + UUID regex, not `count==36`) with an explicit "menu link not recognized" state.

---

## 2. App Store submission checklist

### Confirmed blockers — MUST fix before uploading

**B1 — Guideline 4.8: Sign in with Apple disabled while Google is enabled (verified end-to-end, real).**
`app/Tapt/Core/AuthProviders.swift:22-28` hardcodes `deviceVerified = AuthProviderFlags(apple: false, google: true, ...)`. `flags()` computes `apple = on("apple") && false` (always false) and `google = on("google") && true`, so a shipping build renders "Continue with Google" and **never** the Apple button. Live `auth/v1/settings` for project `qfwiizvqxrhjlthbjosz` confirms `google:true, apple:false, email:true`. Offering Google social login without the SIWA equivalent is an automatic 4.8 rejection.

The one-line code flip `apple: true` (line 24) is **necessary but not sufficient** — `on("apple")` reads the live Supabase flag, which is currently `false`. Two valid paths:
- **Correct fix (SIWA is fully wired — entitlement, hashed-nonce flow, `signInWithIdToken` all present):** set `apple: true` **and** the owner enables the Apple provider in Supabase (below).
- **Fast compliant fallback:** set `google: false` (line 24) and ship email-only. Clears 4.8 in one line, no owner Supabase work.

**B2 — SIWA never verified on a signed build.** If B1 turns Apple on, complete one real Sign in with Apple round-trip on a signed TestFlight build before submitting, or a misprovisioned Apple Service ID / App-ID capability yields a dead login → 2.1 rejection.

**B3 — Reviewer cannot sign in.** On device the only non-Apple path is email OTP (throttling seen historically); the "Dev sign in" button is `#if targetEnvironment(simulator)` only. Resolve via B1 (reviewer uses their own Apple ID — cleanest) OR a pre-created demo account with step-by-step Review Notes and a confirmed-deliverable inbox.

**B4 — Privacy manifest gaps (ITMS-91053).** `app/Tapt/PrivacyInfo.xcprivacy` declares only UserDefaults (CA92.1). After `xcodebuild archive`, read the Organizer "API usage" warnings and add every reported `NSPrivacyAccessedAPIType` (likely File timestamp C617.1/DDA9.1, Boot time 35F9.1, Disk space E174.1/85F4.1) with its reason string. Confirm whether Supabase-swift 2.46.0 ships its own manifest (2.x should) so only app-target APIs need adding.

**Already compliant (verified, no action):** in-app account deletion (`delete_my_account` RPC, 5.1.1(v)); UGC report/block (`report_content` + `block_user` RPCs live, wired in TonightView); honest, specific permission strings; age gate enforced before all content including guest; live legal/support URLs (`taptbeer.com/{support,privacy,terms}` all 200); `ITSAppUsesNonExemptEncryption=false`; no placeholder/beta user-facing copy.

### Owner-only App Store Connect / provider actions
1. **(if B1 = SIWA)** Apple Developer portal: enable "Sign in with Apple" capability on App ID `app.tapt.tapt`; regenerate the "Tapt App Store CI" distribution profile to include it.
2. **(if B1 = SIWA)** Supabase Auth: enable the Apple provider (Services ID + key) so `auth/v1/settings` returns `external.apple=true`.
3. **App Privacy label** — fill to match the manifest exactly: Contact Info → Name + Email; Identifiers → User ID; Location → Precise Location; Usage Data → Product Interaction; User Content → Other User Content. Every one **Linked to the user**, **none used for tracking**. Answer "No" to tracking/IDFA (no ATT prompt).
4. **Age rating** — "Alcohol, Tobacco, or Drug Use or References" = Frequent/Intense → rates 17+/18+.
5. **Availability** — exclude alcohol-prohibited territories (Saudi Arabia, UAE, etc.).
6. **URLs** — Support = `https://taptbeer.com/support`, Privacy = `https://taptbeer.com/privacy`. Confirm `hello@taptbeer.com` actually receives mail — the ForwardEmail DNS-only forwarding is **not yet applied** (delete GoDaddy secureserver MX → add mx1/mx2.forwardemail.net + forward-email TXT). If the mailbox bounces, App Review contact fails.
7. **Promotional screenshots** — capture from the running signed app (real content, no mockups). The Screens carousel (section 5) doubles as the proof-of-realness set. Never fabricate UI.

**Cleanup (non-blocking):** dead `ProfileService.confirmLegalAge` (Core/ProfileService.swift:26-29) is unused — delete or wire it.

---

## 3. Global venues — exact ingestion plan

**Source decision (final):** Overture Places is the sole ingested source. It carries per-row permissive licenses (CDLA-Permissive-2.0 / Apache-2.0 / CC0-1.0; the importer already hard-filters to exactly these) and is commercially redistributable — required because Tapt sells an aggregate data product. **Do NOT ingest OSM/Overpass into `venue`**: ODbL 1.0 share-alike would taint the resold product. Open Brewery DB is retired (410) and breweries-only — keep it as the brewery-identity layer, not the density source.

**Root cause:** `apply_overture_place_import()` is one giant multi-CTE statement that conflates 119,811 staged rows against 8,645 venues **and** inserts ~119K venues **and** upserts ~119K source links in a single synchronous RPC — it exceeds the PostgREST/Supavisor wall-clock and returns HTTP 500. The conflation alone runs in seconds; the monolithic apply is the only broken link.

**Fix — new migration `0082_overture_apply_batched.sql`:**
```sql
create or replace function public.apply_overture_place_import(
  p_release text, p_country_code text default null)
returns ... language sql volatile security definer
set search_path = public
set statement_timeout to 0
set work_mem to '256MB'
as $$
  -- EXISTING 0069 body, plus in the `normalized` CTE WHERE:
  --   and (p_country_code is null or o.country_code = p_country_code)
$$;
revoke all on function public.apply_overture_place_import(text,text) from public, anon, authenticated;
grant execute on function public.apply_overture_place_import(text,text) to service_role;
```

**Batch the driver:** in `scripts/ingest_overture_venues.py` `upload()`, after staging, replace the single apply call with a loop over distinct staged country_codes (`SELECT DISTINCT country_code FROM overture_place_import WHERE release_id=... ORDER BY count DESC`), POSTing `{p_release, p_country_code}` per code; sum `venues_inserted/updated/matched/source_links_written` into `finish_run`. Largest bucket US=7,416 → every call finishes well inside the gateway window.

**Queries / volume (already staged, verified):** 219 country_codes; categories bar 58,008 / pub 23,081 / bar_and_grill 12,483 / lounge 5,390 / brewery 5,218 / gastropub 4,552 / beer_bar 3,653 / sports_bar 3,363 / irish_pub 1,905 / beer_garden 1,561 + tails. Top markets US 7,416, JP 5,863, ES 5,267, IT 4,754, BR 4,042, FR 4,001, DE 3,983, MX 3,629, GB 3,043. Conflation dedups 399 against existing OBDB rows. Net ≈ +119,412 venues → ~128,000 total.

**Schema map:** Overture category → `poi_category` (brewery / beer_garden / pub / taproom / bar); all as `on_premise`; `geo = st_setsrid(st_makepoint(lon,lat),4326)::geography`; `external_ids.overture_place` = dedup key (partial unique index `venue_overture_place_unique`); `geo_bucket_h3` = real H3 res-8. Dedup = `st_dwithin` 100m + pg_trgm name similarity (the existing conflation CTE).

**Run it (owner action — GH Actions run needs `SUPABASE_SERVICE_ROLE_KEY`, already configured):** apply `0082`, then re-trigger the "Ingest Beer Places" workflow with `dry_run=false, release=2026-06-17.0` (re-stage is idempotent via `on_conflict=overture_id`), OR invoke the batched RPC per country directly with the service role. Note the monthly cron (`24 7 20 * *`) and the `workflow_dispatch` `dry_run` default of `true` — flip the default to false now that the write path is trustworthy, and bump `OVERTURE_RELEASE` to the newest release each cycle. The batched apply also self-heals the cron.

**After apply:** refresh `public_platform_stats` and any cached venue tally; report the **real** live count, never inflated. `geo_bucket_h3` now holds two formats (OBDB `country:region` slug + Overture H3) — `brewery_map_feed` doesn't group on it so the map is fine, but standardize to H3 res-8 before any clustering analytics.

**Venue images (hard law):** no free, license-clean, per-venue image source exists at global scale. Overture carries no photos. Leave `logo_url` NULL; render the canonical glass mark / category glyph as placeholder. Only honest logo path = the existing partner-claim flow (`venue_branding` bucket). For "reviews," reuse first-party `checkin_event` / `venue_tap_snapshot` heat via `brewery_map_feed` — never import third-party reviews.

---

## 4. Recommend a beer — SQL + UI spec

Honest taste-fit recommender. Notability comes from resolved curated style + community net + cutout (awards are effectively empty — only 1 beer has one, so award is a tiny tiebreaker only). Novelty = same `style_family`, unfamiliar `style_name`. Ships behind a server-side empty-state gate.

### Migration `0089_recommend_beer.sql`
```sql
create or replace function public.recommend_beer(p_user uuid, p_limit int default 1)
returns table(
  beer_id uuid, name text, style text, style_family text, brewery_name text,
  abv numeric, image_url text, is_na_low boolean, fit_band text, reason text
)
language sql stable security definer set search_path to 'public' as $function$
with me as ( select coalesce(auth.uid(), p_user) as uid ),   -- privacy: never trust p_user when authed
seen as (
  select beer_id from checkin_event where user_id=(select uid from me) and beer_id is not null
  union select beer_id from beer_vote where user_id=(select uid from me)
),
liked as (
  select ce.beer_id from checkin_event ce
    where ce.user_id=(select uid from me) and coalesce(ce.rating,4) >= 3.5 and ce.beer_id is not null
  union select bv.beer_id from beer_vote bv where bv.user_id=(select uid from me) and bv.value=1
),
liked_axes as (
  select sr.hoppiness,sr.bitterness,sr.sweetness,sr.body,sr.roast,sr.sourness,sr.fruitiness,
         sr.style_family, sr.style_name
  from liked l
  join beer_catalog b on b.id=l.beer_id
  join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(b.style,b.name)
),
pref_axes as (                                                -- fallback from onboarding styles
  select sr.hoppiness,sr.bitterness,sr.sweetness,sr.body,sr.roast,sr.sourness,sr.fruitiness,
         sr.style_family, sr.style_name
  from taste_vector tv
  cross join lateral unnest(tv.top_styles) as pref(label)
  join beer_style_reference sr on (
        lower(sr.style_name)=lower(pref.label)
     or lower(sr.style_family)=lower(pref.label)
     or (lower(pref.label) in ('stout','porter') and sr.style_family in ('Dark','Porter & Stout'))
     or (lower(pref.label) in ('pilsner','lager') and sr.style_family='Lager')
     or (lower(pref.label)='no / low' and sr.style_family in ('No / Low','No & Low'))
  )
  where tv.user_id=(select uid from me)
),
axes as (
  select * from liked_axes
  union all select * from pref_axes where not exists (select 1 from liked_axes)
),
centroid as (
  select avg(hoppiness) h, avg(bitterness) bt, avg(sweetness) sw, avg(body) bd,
         avg(roast) ro, avg(sourness) so, avg(fruitiness) fr, count(*) n from axes
),
known_styles   as ( select distinct style_name   from axes ),
known_families as ( select distinct style_family from axes ),
cand as (
  select b.id, b.name, b.style, b.abv, b.is_na_low,
         coalesce(b.cutout_url,b.label_image_url) as image_url,
         br.name as brewery_name, sr.style_family, sr.style_name,
         sr.hoppiness,sr.bitterness,sr.sweetness,sr.body,sr.roast,sr.sourness,sr.fruitiness,
         (b.cutout_url is not null) as has_cutout,
         exists(select 1 from beer_award a where a.beer_id=b.id) as has_award,
         coalesce(bs.net,0) as net, coalesce(bs.checkins,0) as checkins
  from beer_catalog b
  left join brewery br on br.id=b.brewery_id                  -- LEFT: keep null-brewery beers
  join beer_style_reference sr on sr.style_name = public.tapt_ref_style_name(b.style,b.name)
  left join beer_score bs on bs.beer_id=b.id
  where public.tapt_name_ok(b.name)
    and coalesce(b.cutout_url,b.label_image_url) is not null  -- requires an image
    and b.id not in (select beer_id from seen)
),
scored as (
  select c.*,
    sqrt( power(c.hoppiness-x.h,2)+power(c.bitterness-x.bt,2)+power(c.sweetness-x.sw,2)
         +power(c.body-x.bd,2)+power(c.roast-x.ro,2)+power(c.sourness-x.so,2)
         +power(c.fruitiness-x.fr,2) ) as dist,
    (c.style_name  in (select style_name  from known_styles))   as same_style,
    (c.style_family in (select style_family from known_families)) as same_family,
    case when c.roast>=3 then 'roasty' when c.sourness>=3 then 'tart'
         when c.hoppiness>=4 then 'hop-forward' when c.fruitiness>=3 then 'fruity'
         when c.sweetness>=4 then 'malty-sweet' when c.bitterness>=4 then 'bitter'
         when c.body>=4 then 'full-bodied' else 'balanced' end as flavor_word
  from cand c cross join centroid x
  where (select n from centroid) > 0                           -- HARD empty-state gate
),
ranked as (
  select s.*,
    ( (6.0 - least(s.dist,6.0))
      + case when s.same_family and not s.same_style then 1.6
             when not s.same_family then 0.4 else 0.0 end
      + case when s.has_award then 1.2 else 0 end
      + case when s.has_cutout then 0.5 else 0 end
      + least(greatest(s.net,0),20)*0.03 ) as fit
  from scored s
  where s.dist <= 4.5                                          -- wheelhouse gate
)
select r.id, public.tapt_display_name(r.name), coalesce(r.style_name,r.style), r.style_family,
  r.brewery_name, r.abv, r.image_url, r.is_na_low,
  case when r.same_family and not r.same_style then 'a step out'
       when not r.same_family then 'new territory' else 'in your lane' end,
  trim(
    case when r.has_award then 'Medal-winning ' else '' end
    || coalesce(r.style_name,r.style)
    || case when r.brewery_name is not null then ' from '||r.brewery_name else '' end
    || '. '
    || case
         when r.same_family and not r.same_style then 'A '||r.flavor_word||' '||r.style_family||' a half-step from what you usually pour.'
         when not r.same_family then 'A '||r.flavor_word||' '||r.style_family||' you have not explored yet.'
         else initcap(r.flavor_word)||' like the '||r.style_family||' beers you reach for.'
       end
  )
from ranked r
order by r.fit desc, r.net desc, r.checkins desc
limit greatest(p_limit,1);
$function$;

revoke all on function public.recommend_beer(uuid,int) from public;
grant execute on function public.recommend_beer(uuid,int) to authenticated;
```
The `reason` is assembled **only** from real columns (style, family, brewery, dominant sensory axis, award-if-true). No invented numbers. `centroid.n=0` is the server-side honest empty state. Style science joins the **full** catalog via `tapt_ref_style_name` (not the 44%-populated `style_ref` column). Requires `coalesce(cutout_url, label_image_url)` (10,522 covered), not `cutout_url` alone (only 103).

### App wiring
- **`app/Tapt/Core/RecommendationService.swift`** (new): `struct RecommendedBeer: Decodable, Identifiable` with CodingKeys `beer_id/name/style/style_family/brewery_name/abv/image_url/is_na_low/fit_band/reason`, `var id { beerId }`; `enum RecommendationService { static func pickedForYou(userId:limit:6) async throws -> [RecommendedBeer] }` calling `Supa.client.rpc("recommend_beer", params: {p_user, p_limit})` — mirror the RPC style in `BeerService.swift`.
- **`app/Tapt/Features/Explore/ExploreView.swift`** — insert a "Picked for you" card directly below the hero tile. `@State picks/pickIdx/pickLoaded`. `.task`: guard `session.user?.id`, load picks. Show the card **only** when a pick exists. Card = `BeerImageView(url: pick.imageUrl)` + display name + brewery + a `style_family` chip + a `fit_band` pill + `pick.reason` body. Tap → `BeerDetailView(beerId:)`. A subtle **"Show me another"** cycles `pickIdx = (pickIdx+1) % picks.count`. **Never render a numeric match score.**
- **Empty state (copy-exact):** when `pickLoaded && picks.isEmpty`, either hide the card or show one line — **"Vote on a few beers and set your styles, and we'll pick one you'll love."** — deep-linking to `TastePreferencesView`. No fabricated placeholder beer.
- **Client short-circuit:** render the slot only if `favoriteStyles` (@AppStorage) is non-empty OR the user has any votes/check-ins; else the nudge above.

**QA without faking prod (hard law):** prod has 4 votes / 1 check-in / 1 taste_vector — untestable there. Verify in the `demo` schema: insert a fixture user with 3-4 up-votes across American IPA + Hazy IPA, confirm an "a step out" pick (e.g. West Coast / Double IPA) with image + real reason; confirm `centroid.n=0` users get zero rows. Never write fixtures to `public`.

---

## 5. Content batch — lead posts + elevation edits

The type/color/copy discipline is elite and the data is honest (taste cards match `beer_style_reference` exactly — a genuine differentiator). The batch is **not** post-ready: it runs two mark systems side by side (canonical flat SVG pint vs. glossy Apple/Twemoji 3D emoji), which is the single biggest "AI/generic" tell.

### Elevation edits (do before posting) — in order
1. **Kill the emoji (blocker).** `grep -rl '🍺\|👍\|👇\|📍\|⛵\|👉\|🌾\|☕\|✨\|💬' social-assets/`. Swap every 🍺 hero/header for the inlined `glass.svg` (copy the exact `<svg viewBox="0 0 400 520">` block already in `post-01-meet.html`). Replace 3D object emoji with flat brand-palette SVG glyphs: gold up-chevron (reuse the ▲ from carousel-identity S4) for "rate," a hand-drawn flat map-pin for "claim your spot" (`carousel-breweries.html:39` — note the pushpin is in breweries, not identity), a flat boat-on-foam for the IPA fact (`facts.html:29`). If a slot has no on-brand glyph, delete it and let type + negative space carry it. Re-render via `ig/render.sh` + library render.
2. **Fix the em-dash copy law (blocker).** `social-assets/ig/CAPTIONS.md:25` — change "Irish Stout — black, dry..." to "Irish Stout. Black, dry and roasty with a coffee-like bitterness." Make `library/CONTENT-CALENDAR-V2.md` the single source of truth; mark `CAPTIONS.md` + old `CONTENT-CALENDAR.md` superseded so no stale copy ships.
3. **Empty-state dash glyph.** `library/carousel-whoweare.html:72-74` — replace the literal `—` placeholder rows with a muted "no votes yet" pill or a faint `0`, so the honesty story reads as intentional, not broken.
4. **Normalize meter palette.** `post-03`/`post-04` — make all filled meter segments **gold**, copper only on roast/bitter rows; remove hop-green from meters so green stays reserved for market up-arrows (its single brand meaning). Record the rule in `brand/master.html`.
5. **Compose the carousel covers.** `carousel-identity-1`/`carousel-breweries-1` waste the lower two-thirds — scale headlines to fill the canvas (Poppins 800, 3-4 lines) or add a ghost mark / footer bar. Deliberate use of canvas, not a centered island.
6. **Re-render 2x and eyeball at ~140px** (real IG feed size) to confirm the mark reads and no emoji survives.

### Lead with these (strongest, post-ready after edits 1-2)
1. **post-02 Beer Market** — "A stock market for beer," best hook, earned gold accents. **Lead post.**
2. **post-03 Guinness Taste & Feel** — real BJCP data, "what it actually tastes like." (fix meter palette)
3. **post-04 American IPA Beer School** — same strength, educational pillar.
4. **Market Monday live-board** (V2 spec 1) — strategic anchor, rendered from live `beer_market_standing`.
5. **Screens carousel** (V2 spec 2) — real app screens, "no mockups"; doubles as App Store proof-of-realness.
6. **post-01 Meet Tapt** — clean intro, correct SVG header, no emoji fix needed.
7. **fact-1 "IPA was built for a boat"** — strong hook (replace sailboat emoji).
8. **post-05 IPA vs Stout story** — highest-engagement mechanic; strip the 👇 + "drop your vote" line, leave a clean middle band for the native IG poll sticker.
9. **history card Plzeň 1842 / Reinheitsgebot** — clean cited editorial.
10. **carousel-whoweare** — the honesty ethos no competitor posts (fix the dash rows first).

**Hold until fixed:** both carousel covers (emoji hero + empty canvas), anything using `CAPTIONS.md` copy, any "trending/climbing" market card (V2 correctly retires these until real votes exist — do not resurrect). Keep the BJCP footer (it earns trust) but never drift into "only app with real data" flexing — voice-law violation.

---

## 6. Image performance — cache + CDN mirror

**Fix A (in-app cache)** is section 1.1 — ship it today; it removes the re-download-on-scroll pain immediately.

**Fix B (durable CDN mirror)** removes the OFF dependency entirely. 10,411 beers have only a slow `images.openfoodfacts.org` label URL; mirror them to Supabase Storage (the same fast CDN that already serves cutouts). Every reader already consumes a computed `image_url`, so the app needs **no** Swift change for Fix B.

**Step 1 — schema + bucket (owner):**
```sql
ALTER TABLE public.beer_catalog ADD COLUMN image_cdn_url text;
```
Create a public Storage bucket `beer-images` (mirror `beer-cutouts` settings).

**Step 2 — backfill `scripts/mirror_beer_images.py`** (clone `scripts/build_beer_cutouts.py` structure — same `SupabaseAPI` class, service-role auth, bounded batches, retry table). Candidates: `GET /rest/v1/beer_catalog?select=id,label_image_url&image_cdn_url=is.null&cutout_url=is.null&label_image_url=like.https://images.openfoodfacts.org/*` ordered `updated_at.asc,id.asc`, paged. Per row: normalize trailing `.full.jpg` → `.400.jpg`; download with the Tapt User-Agent; re-encode via Pillow (`thumbnail` max 600px, `save(format='JPEG', quality=82, optimize=True, progressive=True)`); `POST /storage/v1/object/beer-images/{id}.jpg` (`Content-Type: image/jpeg`, `x-upsert: true`); then `PATCH /rest/v1/beer_catalog?id=eq.{id}` `{image_cdn_url: "{SUPABASE_URL}/storage/v1/object/public/beer-images/{id}.jpg"}`. **Only** set `image_cdn_url` on a 200 upload that decoded to a valid image; mark failures in a status row (never blank). Leave `label_image_url` + `label_image_license` untouched (OFF attribution preserved).

**Step 3 — reader precedence (owner applies as one migration).** In each image-serving object, change `COALESCE(alias.cutout_url, alias.label_image_url)` → `COALESCE(alias.cutout_url, alias.image_cdn_url, alias.label_image_url)`. Objects: views `beer_trend_feed`, `beer_catalog_listable`; functions `catalog_search`, `leaderboard_beers`, `beer_detail`, `beer_of_week_latest_winner`, `beer_of_week_standings`, `tonight_feed_v2`, `tonight_feed_near`, `my_beer_activity`, `my_checkins`, `public_profile`. Dump each def with `pg_get_functiondef`/`pg_get_viewdef`, insert the one token, `CREATE OR REPLACE`. Cutout (transparent PNG) still wins; mirror beats raw OFF; raw OFF is last-resort so nothing ever blanks or fabricates.

**Step 4 — run it** as a GH Actions workflow (`SUPABASE_SERVICE_ROLE_KEY` already exists for the cutout pipeline). ~10.4K rows at BATCH=300 ≈ 35 runs. Partial coverage is safe — the COALESCE fallback means the mirror can land incrementally.

**Verify:** after a batch, query a mirrored row → `image_cdn_url` resolves fast from Storage; re-run the app → network inspector shows `*.supabase.co` not `images.openfoodfacts.org`; cutout beers still show their transparent PNG; un-mirrored beers still fall back to raw OFF (never blank, never fabricated).

---

## Execution order at a glance

| # | Action | Owner or eng | Blocks |
|---|--------|--------------|--------|
| 1 | Fix A image cache (TaptApp init + ThumbLoader + BeerThumb) | eng | ships today |
| 2 | Scanner honesty copy + name normalizer backfill + flow guards + scan image | eng | scanner launch-ready |
| 3 | `recommend_beer` migration + service + Explore card | eng | rec feature |
| 4 | Venue apply `0082` batched + driver loop | eng | global map |
| 5 | Run venue apply (`dry_run=false`) | **owner** | global map lands |
| 6 | Content: kill emoji + fix em-dash + meters + covers, re-render | eng | content batch |
| 7 | B1 SIWA: flip `apple:true` (+ Supabase enable) OR `google:false` | eng + **owner** | 4.8 blocker |
| 8 | Signed TestFlight build, verify SIWA round-trip | eng + **owner** | 2.1 risk |
| 9 | Archive → read API-usage warnings → patch PrivacyInfo | eng | ITMS-91053 |
| 10 | ASC: privacy label, age rating, availability, URLs, reviewer access, mail deliverability | **owner** | submit |
| 11 | Fix B CDN mirror (schema, backfill, COALESCE, run) | eng + **owner** | incremental, post-submit OK |