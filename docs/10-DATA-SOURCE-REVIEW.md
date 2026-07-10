# Tapt — Data source review, wave 2 (2026-07-09)

Extends `docs/03-DATA-SOURCES.md` (the original 74-source sweep). Verdicts for
the owner's expanded source list, grouped by what we can honestly do with each.
The rule stands: **we only build the sellable core on commercially-usable data,
we cite facts, and we never scrape ratings graphs.**

## ✅ Build on it (open license, ingest)
| Source | Verdict |
|---|---|
| Open Brewery DB | Already fully ingested (8.6k+ venues, 25 countries). Weekly re-sync via the 0008 staging contract. |
| Open Food Facts | Already wired (scan-to-catalog, label photos, nutrition). ODbL/CC-BY-SA — attribute + segregate (we do, via `label_image_license` + `ingestion_source`). |
| BJCP guidelines (2015/2021) | Style facts ingested (60 styles, cited). The /style/2015/21/ipa/ page the owner linked is the same body — 2021 supersedes it. |
| openbeer.github.io (Open Beer DB) | Public-domain-ish but **stale (last real update ~2011)**. Usable as a dedup cross-check only; do not seed from it. |

## 📖 Cite the facts (results are facts; pages are copyrighted)
| Source | Verdict |
|---|---|
| World Beer Cup (worldbeercup.org) | **Wired in 0014.** Competition results = public facts; we store winner rows with year/category/medal + citation. Yearly ingest each spring (2026: 8,166 entries — Allagash White gold already seeded). |
| World Beer Awards | Same treatment; results published each August. Add to the yearly ingest run. |
| Brewers Association / Beer Institute / Beverage Marketing | Industry statistics for pitch decks and market sizing (craft production, NA growth). Cite in docs/marketing; NOT app content. BA's brewery directory is member data — do not scrape. |
| TasteAtlas, YouGov beer ratings | Facts like "YouGov's most popular beer" can be quoted with citation in editorial content; no bulk use. |

## 💡 Inspiration only (study the product, never the data)
| Source | Verdict |
|---|---|
| BeerAdvocate, RateBeer (incl. relbench rel-ratebeer) | Next Glass properties. The Stanford relbench dump is **research-only licensing** — commercially radioactive; touching it poisons our provenance story. Study their *feature set*, import nothing. |
| Untappd lists (e.g. user lists) | Same — user-generated lists on their platform. The *pattern* (shareable themed lists) is a great future Tapt feature. |
| BeerMenus | Direct competitor for tap lists; their data is their moat. Ours comes from partners publishing on Tapt (already built: venue_tap_item). |
| BeerMaverick (hops DB), White Labs (yeast archive) | Compiled databases = their compilations. The *idea* — ingredient education (hops/yeast/malt pages) — is a strong Beer School expansion; source from public hop/yeast facts or grower associations later. |
| CraftBeer.com, Craft Beer & Brewing, VinePair, Paste, Hop Culture, Beer Connoisseur, blogs/Reddit/forums | Editorial "best of" lists are copyrighted compilations. Read for taste-making and trend signals; never ingest as ranked data. Quoting a single line with attribution in editorial content is fine. |
| beer.social, Bier-Universum, globalbeer.com, globalbeerindex, top500bars | Small/aggregator sites; nothing license-clean worth taking. top500bars = inspiration for a future "destination bars" layer via our own partner network. |
| Brewbound | Trade news — good for the Dispatch newsletter's industry section (link + summarize, never republish). |
| Brand sites (AB InBev, Carlsberg, Heineken, Allagash, Dogfish...) | Official product facts (ABV, style) are verifiable references. Logos/press kits are trademarks — used only with partner permission (this is the partner-upload pitch). |

## 🚫 Avoid
| Source | Verdict |
|---|---|
| Kaggle craft-cans (2016) & Datafiniti breweries | Stale scrapes with unclear licenses. Our OBDB layer is fresher and clean. |
| GIS StackExchange POI threads | Point to OSM/commercial POI dumps; we already chose Foursquare OS Places (Apache 2.0) as the licensed POI expansion path (docs/03). |

## What this changes in the product
1. **Awards layer (LIVE, migration 0014):** `beer_award` + medals on beer pages, cited. Yearly ingest cadence: World Beer Cup (spring), World Beer Awards (August), GABF (fall — same facts-with-citation treatment).
2. **Tapt's Favorite (LIVE in schema):** `medal='tapt_favorite'`, global or per-region — our own first-party accolade program (see docs/11-ROADMAP.md).
3. **NA/zero-proof:** No/Low board added to Leaderboards; NA growth stats (Beer Institute/BA) go in the pitch deck, not the app.
4. **Future Beer School expansion:** hops/yeast/ingredient pages from license-clean sources.
