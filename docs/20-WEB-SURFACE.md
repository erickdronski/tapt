# 20 · Web surface strategy (taptbeer.com)

Status: recommendation doc, written 2026-07-12 (Claude). Everything below is
grounded in the repo and live prod reads; data counts were queried read-only
from Supabase `qfwiizvqxrhjlthbjosz` on 2026-07-12.

## 1. Inventory (what exists today)

Static site in `landing/`, Vercel project `tapt-landing`, `cleanUrls: true`
(`landing/vercel.json`), domain taptbeer.com.

| Page | Audience | Data path | Notes |
|---|---|---|---|
| `index` | public | `dispatch-signup` edge fn only (index.html:450) | Full landing, good meta/OG/JSON-LD (index.html:6-12, 490) |
| `menu?v=<uuid>` | public | anon RPCs `venue_menu`, `venue_brand`, `venue_events` (menu.html:59-83) | Live QR tap list + printable QR. Client-rendered |
| `portal` | partners | authed (email OTP) + `resend-send` edge fn | Claim → brand → tap list → events → "Your numbers" analytics card (portal.html:64-125) |
| `dispatch` | public | `dispatch-signup` edge fn (dispatch.html:315) | Newsletter page; archive mount is a static empty state (dispatch.html:284-291). 0 issues shipped yet |
| `admin` | owner | `resend-send` edge fn, gated by `app_admin` | Owner ops |
| `hq` | owner | static links | Unlisted hub |
| `pitch` | partners/press | static | No API calls |
| `app-preview` | public | anon `catalog_search` (app-preview.html:314) | Interactive fake-phone demo of the real catalog |
| `privacy`, `terms` | public | static | Linked from app (`AppSettings.swift:70-71`) |

**Locked anon RPC surface, verified live** (pg_proc privilege query, 2026-07-12):
`catalog_search`, `venue_brand`, `venue_events`, `venue_menu`. That matches
AGENTS.md and migration `0061_shrink_anon_rpc_surface.sql`. One stray:
`clean_beer_name(text)` is still anon-executable. It is a harmless text helper,
but revoking it would make the surface exactly the documented four (flag for
the security lane, not urgent).

**Missing entirely:** `sitemap.xml`, `robots.txt` (verified absent from
`landing/`), any per-beer public URL, any style content on the web, any web
view of the Beer Market.

**Data reality (live counts, 2026-07-12):** 11,054 beers (10,331 listable),
8,694 venues, 5,197 market standing rows, 61 styles with full sensory +
history + ingredients depth (0052/0053), 19 cited awards, 0 published prod
menus (QA rows cleaned), 0 dispatch issues, 1 vote. Any web surface must be
honest about this: leaderboard-style pages are fine (standing is a real blend
of season/awards/notability), but community-count flexing is impossible and
banned anyway.

**Key gap that motivates all of this:** the app's share cards have no per-beer
web URL to point at. `AppLinks.webBase` exists (`AppSettings.swift:69`) but
`ShareCard.swift`/`ShareTools.swift` never build a beer link, because no such
page exists. Every share today is an image with no destination.

## 2. Candidates, scored

Legend: effort S < M < L. "Anon change" = deviation from the locked surface
(allowed if deliberate + noted in AGENTS.md).

### For users

#### A. Style guide pages: `/styles` index + `/style/<slug>` (61 pages)
- **User value:** high. Real reference content (sensory profile bars, flavor
  notes, typical ingredients, history, vital stats) already exists in
  `beer_style_reference` after 0052. Nothing to invent.
- **SEO/growth value:** highest of any candidate. "what is a hefeweizen",
  "gose vs berliner weisse" queries are evergreen and low-competition for a
  fresh domain. 61 substantial static pages is exactly the crawlable content
  taptbeer.com has none of today.
- **Feasibility:** best case. **No anon change.** Generate static HTML at
  build time with a small script (`tools/` pattern) that reads
  `beer_style_reference` with owner credentials and writes
  `landing/style/*.html` committed to the repo. Fully static = actually
  crawlable (unlike the client-rendered pages). Keep BJCP attribution +
  `source_url` per page; keep descriptions excerpt-length, per the in-app
  citation posture (docs/03).
- **Effort:** M (generator script + template + index page + regen doc note).

#### B. Public beer page: `/beer?b=<uuid>`
- **User value:** high. This is the missing share-link destination. App share
  card gains a real URL; recipients see the beer (image, style, stats, awards,
  style science) and an app CTA. Also gives Dispatch and IG posts something to
  link.
- **SEO/growth value:** medium short-term. Client-rendered like `menu.html`,
  so crawlers see a shell; the value is share links and OG previews first,
  SEO later (see D for the upgrade path).
- **Feasibility:** needs **one deliberate anon grant: `beer_detail(uuid)`**.
  Verified safe to expose: it is `security definer`, returns only catalog
  fields, style reference fields, aggregate counts (ups/downs/checkins/avg
  rating) and cited awards; no user rows, no PII
  (0053_beer_detail_sensory_fields.sql:5-15). It was anon until 0061 shrank
  the surface for scale, not for safety. Re-granting is a scoped, documented
  exception; update AGENTS.md's locked list in the same commit.
- **Effort:** S for the page (clone menu.html pattern) + S in the app to add
  the URL to share flows. Rate/DoS posture: same as the other anon RPCs
  (PostgREST, indexed single-row read).

#### C. Web Beer Market: `/market`
- **User value:** medium-high. The flagship feature, visible before install.
  Ticker + top standings + sparklines from real snapshots.
- **SEO/growth value:** medium. A linkable, screenshot-friendly ranking page
  is marketing ammunition (IG posts can link "see the full board").
- **Feasibility:** two honest options. (1) Re-grant `beer_market(text,int,
  boolean)` to anon: it is a pure indexed read of the materialized standing
  (~10ms, 0060), aggregate-only, no PII; this was anon until 0061. (2) Zero
  anon change: a scheduled job bakes `landing/market.json` from the standing
  (ingest-workflow pattern) and the page renders that; data is at most a day
  stale, which is fine for a marketing surface. Prefer (2) first: no surface
  change, and static JSON is cacheable/CDN-friendly. Copy must label the
  number "standing" and explain the blend, same as the app; with ~0 votes
  today the movement is season/awards driven, which is real and fine.
- **Effort:** S-M.

#### D. Static prerender + sitemap layer (SEO backbone)
- **What:** `robots.txt` + `sitemap.xml` (static pages + all `/style/*` +
  optionally per-beer static shells). For beers, the same generator as A can
  emit lightweight static shells (title, meta description, OG tags, minimal
  server-visible content) for the ~10.3K listable beers, hydrating from
  `beer_detail` on load. That converts B from "share link only" to real
  long-tail SEO ("<beer name> abv style").
- **User value:** indirect. **SEO value:** the multiplier for A and B.
- **Feasibility:** static generation fits Vercel + repo. 10K HTML shells is
  large-ish for a repo; acceptable to start with styles only + sitemap of
  fixed pages (XS), and gate the 10K-beer shell build behind a decision
  (repo weight, build cadence). No anon change beyond B's.
- **Effort:** XS for robots/sitemap of existing + style pages; M-L for the
  full beer-shell build. Do the XS part immediately regardless.

#### E. Dispatch web archive: `/dispatch/<slug>`
- **User value:** medium (read issues without an inbox; the page already
  promises "Every issue is hosted here", dispatch.html:283).
- **SEO value:** good over time; each issue is a real content page.
- **Feasibility:** `dispatch_archive` / `dispatch_issue_by_slug` exist but
  were anon-revoked in 0061, and `dispatch_issue` has 0 rows. Prefer baking
  each shipped issue to a static page at send time (the dispatch generator
  already renders HTML) over re-granting the RPCs: static wins for SEO and
  keeps the anon surface unchanged.
- **Effort:** S, but **blocked on issue 001 existing**. Defer until then.

#### F. Venue directory / public venue pages beyond `menu?v=`
- **User value / SEO:** potentially large (local queries: "taprooms in
  Asbury Park"), but today it would be 8,694 thin pages from the OBDB import
  with 0 published menus and near-zero owned content. Thin-content SEO hurts
  a new domain, and empty pages contradict the honest-first posture.
- **Verdict: defer.** Revisit when a meaningful number of venues have claimed
  brands or published menus; then index only those (claimed/published filter),
  linking each to its existing `menu?v=` page.

### For partners

#### G. Embeddable tap-list widget
- **Partner value:** high. "Put your live Tapt menu on your own site" with a
  copy-paste iframe snippet: `<iframe src="https://taptbeer.com/menu?v=<uuid>&embed=1">`.
  `embed=1` hides the brand chrome/QR box in menu.html (a few lines of JS/CSS).
  Their site stays current when they publish in the portal; every embed is a
  live backlink to taptbeer.com.
- **Feasibility:** **no anon change** (`venue_menu` already anon). Surface the
  snippet in portal step 4's `menuLinks` area (portal.html:108).
- **Effort:** S. Highest value-per-effort on this list.

#### H. Portal depth (incremental)
- Already present: claim, branding upload, tap list with draft autosave +
  reorder + publish lifecycle, events/specials, "Your numbers" analytics,
  featured-placement inquiry (portal.html:64-129). The 10-year menu-snapshot
  expiry (0063) means partner menus never rot.
- Worth adding, all authed (no anon change): downloadable QR poster PDF/PNG
  from the portal (today print lives on the public menu page), per-venue menu
  history, and richer analytics (menu page views would need a lightweight
  counter; `featured_impression` exists for featured partners only). Effort
  S-M each. None is a blocker; ship behind partner demand.

#### I. Deeper partner portal (multi-venue, scheduling, CSV import)
- Real requests will tell us which of these matter. All are authed-side.
  **Defer**; do not speculatively build.

## 3. Recommended order

1. **D-lite: robots.txt + sitemap.xml** for existing pages. XS, zero risk.
2. **A: static style guide (61 pages)** + add them to the sitemap. The SEO
   foundation, no anon change.
3. **G: menu embed mode + portal snippet.** S, pure partner win.
4. **B: public beer page + anon `beer_detail(uuid)` grant** (deliberate
   exception, update AGENTS.md locked list in the same commit) + wire the URL
   into the app share flows.
5. **C: /market from a baked daily JSON** (no anon change to start).
6. **E: dispatch archive as static pages** the moment issue 001 ships.
7. **F, I: defer** (thin-content risk / no demand signal yet).

## 4. Rules that bind every item

- Honesty: no invented counts, votes, or movement anywhere. Blank beats
  invented. Market copy says "standing" and explains the blend.
- Voice: plain, direct, no em dashes, no hype adjectives, no number-flexing.
- Brand: `brand/glass.svg` only.
- Anon surface: today it is `catalog_search`, `venue_brand`, `venue_events`,
  `venue_menu`. The only proposed addition is `beer_detail(uuid)` (item B),
  which is aggregate-only and PII-free; grant it in a migration mirrored in
  `supabase/migrations/` and update AGENTS.md in the same commit. Everything
  else here needs no anon change. Also consider revoking the stray anon
  execute on `clean_beer_name(text)`.
- Client-rendered pages (menu, beer, market) are fine for humans and OG
  scrapers with static meta tags, but invisible to search; anything meant to
  rank must be baked static (styles, dispatch issues, sitemap).
- BJCP content on style pages stays excerpt-length with attribution and
  `source_url`, matching the in-app citation posture.
