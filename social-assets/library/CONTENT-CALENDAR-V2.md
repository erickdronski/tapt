# Tapt — 30-day Instagram calendar v2 (@taptbeerapp)

THE Beer Superapp. All of beer, one app. Handle **@taptbeerapp**, site **taptbeer.com**.

Voice: plain, direct, confident. No hype adjectives, no em dashes, no number-flexing. Every fact is real and cited in the footnotes. Boards and standings come from the live database, never invented.

**What's new since v1:** real app screenshots (`landing/img/screens/01-market.png` … `05-discover.png`), a real SpriteKit Beer Pong game (gameplay clips are now a content pillar), and a live Beer Market with real standings (`beer_market_standing`, refreshed every 30 minutes on prod).

Day 1 is a Monday. Existing assets live in `social-assets/library/out/` and `social-assets/ig/out/`. New renders are specced in full at the bottom.

## The three weekly franchises

1. **Market Monday** (days 1, 8, 15, 22, 29). The live Beer Market board or its weekly crown, rendered from real standings. Standing is the honest blend the app uses: base 10, season fit, cited awards, notability, and votes as they arrive. Until real votes and snapshots exist, copy never claims movement. Verified on prod 2026-07-12: Allagash White holds the top standing; every row has zero votes so far, which is exactly the honest empty-state story we tell.
2. **Tap History Thursday** (days 4, 11, 18, 25). One verified beer-history card per week using `history-template.html`. Two exist (IPA voyage, Plzeň 1842), two are new (Reinheitsgebot 1516, Porter and London).
3. **Game Clip Friday** (days 5, 12, 19, 26). Short reels of the real SpriteKit Beer Pong game, screen-recorded from the app. Real features shown: slingshot with trajectory preview, rim rattle physics, splash particles, streak multiplier, persistent best score. Nothing staged that the game does not do.

## The 30 days

| Day | Format | Visual concept | Asset | Caption hook | Hashtags |
|---|---|---|---|---|---|
| 1 | Post | **Market Monday.** The live board: top five beers by standing, symbols and style, "standing" labeled with the blend footer | NEW `market-monday` (spec 1) | Market Monday. The board is live. Standing blends season, cited awards, and notability. Your votes take it from here. | #beer #craftbeer #beerapp #beercommunity #beermarket #beertography |
| 2 | Carousel (5) | The real app, five real screens in phone frames: Market, Analysis, Home, Taste, Discover | NEW `screens-1..5` (spec 2) | This is Tapt. Five real screens, no mockups. Free on taptbeer.com | #beer #craftbeer #beerapp #appdesign #beerlover #beertography |
| 3 | Story | This or that poll: IPA vs Stout | `ig/out/post-05-poll-story.png` | IPA or Stout. Drop your vote. | #beer #craftbeer #beercommunity #beerlover |
| 4 | Post | **Tap History Thursday.** IPA and the India trade route | `out/history-1.png` | Pale stock ales traveled to India before the name IPA appeared. | #ipa #beerhistory #craftbeer #beer #beereducation #beerfacts |
| 5 | Reel | **Game Clip Friday.** Beer Pong: a clean sink, splash particles, streak counter climbing | NEW gameplay reel A (spec 7) | Beer Pong is in the app. Real physics, real rattle. Sink it. | #beerpong #beer #gamenight #craftbeer #beerapp #mobilegame |
| 6 | Carousel (4) | Who we are: the claim and the honesty ethos | `out/whoweare-1..4.png` | Who we are, in four cards. Boards stay honestly empty until you vote. | #beer #craftbeer #beerapp #beercommunity #beerlover #beertography |
| 7 | Post | Seasonal: summer in a glass, three light styles | `out/seasonal-card.png` | Summer in a glass. Witbier, Hefeweizen, Pilsner. | #summerbeer #witbier #hefeweizen #pilsner #craftbeer #beer |
| 8 | Post | **Market Monday.** Beer of the Week: the beer the market crowns, filled with the real current leader (Allagash White as of 2026-07-12; re-pull before render) | NEW `botw-live` (spec 6) | Beer of the Week. Crowned by the market, medals cited in the app. | #beer #craftbeer #beeroftheweek #allagash #witbier #beercommunity |
| 9 | Post | Taste & Feel: Guinness Draught | `ig/out/post-03-taste-guinness.png` | What Guinness Draught actually tastes like. Black, dry, roasty. | #guinness #stout #beer #craftbeer #beereducation #beertography |
| 10 | Post | Screen spotlight: the Beer Market screen, framed, one line | NEW `screen-spotlight-market` (spec 3) | Every beer is a ticker. This is the board, in the app today. | #beer #craftbeer #beerapp #beermarket #beercommunity #appdesign |
| 11 | Post | **Tap History Thursday.** The first golden beer, Plzeň 1842 | `out/history-2.png` | The first golden beer. Plzeň, 1842. | #pilsner #beerhistory #beer #craftbeer #beerfacts #lager |
| 12 | Reel | **Game Clip Friday.** Beer Pong: the rattle-out. Ball rings the rim and escapes | NEW gameplay reel B (spec 7) | The rim giveth and the rim taketh away. Rattle-outs are real physics. | #beerpong #beer #gamenight #craftbeer #beerapp #mobilegame |
| 13 | Carousel (4) | Menus for partners: claim, publish, QR, activity | `out/partners-1..4.png` | Free menu hosting, forever. Here's how a venue gets on Tapt. | #brewery #taproom #craftbeer #beerbusiness #supportlocalbeer #barlife |
| 14 | Story | Question sticker over the launch story frame: what's in your glass tonight | `out/launch-story.png` + native question sticker | What's in your glass tonight? | #beer #craftbeer #beercommunity #beerlover |
| 15 | Post | **Market Monday.** Fresh board render with that week's live top five | re-render `market-monday` (spec 1) | Market Monday. This week's board, straight from the app. | #beer #craftbeer #beerapp #beercommunity #beermarket #beertography |
| 16 | Carousel (5) | What we do: catalog, market, trending, games, Passport | `out/whatwedo-1..5.png` | Everything beer, one Passport. Swipe the five things Tapt does. | #beer #craftbeer #beerapp #beerlover #beereducation #beertography |
| 17 | Post | Beer school: the American IPA | `ig/out/post-04-ipa.png` | Beer school: the American IPA. Citrus, pine, tropical hops. | #ipa #craftbeer #beer #hops #beereducation #beertography |
| 18 | Post | **Tap History Thursday.** Reinheitsgebot, Bavaria 1516 | NEW `history-3` (spec 4) | 1516. Bavaria says beer is water, barley, and hops. Yeast wasn't discovered yet. | #reinheitsgebot #beerhistory #beer #craftbeer #beerfacts #lager |
| 19 | Reel | **Game Clip Friday.** Beer Pong: the trajectory preview up close, then the shot | NEW gameplay reel C (spec 7) | Line it up. The dotted arc is your aim, the physics do the rest. | #beerpong #beer #gamenight #craftbeer #beerapp #mobilegame |
| 20 | Post | For bars and breweries: menu hosted free, QR for the tables | `out/for-bars-card.png` | Your menu, hosted free. You only ever pay to be louder. | #brewery #taproom #craftbeer #beerbusiness #supportlocalbeer #barlife |
| 21 | Post | Fun fact: lager vs ale isn't about color | `ig/out/fact-3.png` | Lager vs ale isn't about color. It's the yeast. | #beerschool #beereducation #craftbeer #beer #lager #ale |
| 22 | Carousel (3) | **Market Monday.** How standing works: base, season and awards, your votes | NEW `standing-1..3` (spec 5) | How a beer earns its standing. Three cards, no secrets. | #beer #craftbeer #beerapp #beermarket #beercommunity #beertography |
| 23 | Post | Screen spotlight: the Taste & Feel screen, framed, one line | NEW `screen-spotlight-taste` (spec 3) | Every beer gets a Taste & Feel breakdown, built from BJCP style guidelines. | #beer #craftbeer #beerapp #beereducation #appdesign #beertography |
| 24 | Story | Rate this beer slider over the Guinness taste frame | `ig/out/post-03-taste-guinness.png` + native slider sticker | Rate it. Slide your score. | #beer #craftbeer #beercommunity #guinness |
| 25 | Post | **Tap History Thursday.** Porter: the beer named for London's working porters | NEW `history-4` (spec 4) | Porter got its name from the people who drank it. London, 1700s. | #porter #beerhistory #beer #craftbeer #beerfacts #stout |
| 26 | Reel | **Game Clip Friday.** Beer Pong: the best-score chase, streak multiplier on screen | NEW gameplay reel D (spec 7) | Chasing a new best. Streaks multiply, misses reset. How far can you run it? | #beerpong #beer #gamenight #craftbeer #beerapp #mobilegame |
| 27 | Carousel (3) | Mini games: dice, the lineup, tonight's on Tapt | `out/games-1..3.png` | Game night, built in. Trivia, Darts, Beer Pong, the Tapt Deck. | #beer #craftbeer #gamenight #beerpong #beercommunity #beerlover |
| 28 | Post | Fun fact: Guinness pours backwards | `ig/out/fact-2.png` | Guinness pours like it's going backwards. It's the nitrogen. | #guinness #stout #beerfacts #beer #craftbeer #beereducation |
| 29 | Post | **Market Monday.** Beer of the Week refresh with the current live crown | re-render `botw-live` (spec 6) | Beer of the Week. The market decides, every Monday. | #beer #craftbeer #beeroftheweek #beercommunity #beerlover #beermarket |
| 30 | Post | Recap and CTA: it's free | `out/quote-card.png` | All of beer. One app. It's free. taptbeer.com | #beer #craftbeer #beerapp #beerlover #beercommunity #beertography |

## Format mix

- **Single posts:** 17  ·  **Carousels:** 6 sets  ·  **Stories:** 3  ·  **Reels:** 4
- Franchise days: 5 Market Mondays, 4 Tap History Thursdays, 4 Game Clip Fridays.
- Reels are the biggest upgrade over v1: real gameplay is the only motion content we can show that is fully honest, because it is the actual game.

## New assets that need rendering (specs)

Render rules follow `README.md` in this folder: headless Chrome at 2x, singles 1080x1350, stories and reels 1080x1920, tall sheets sliced with PIL (never sips). Brand: gold `#F2A900`, malt `#1A1206`, foam `#FBF6EC`, hop `#3F8F5B`, copper `#B4531F`, Poppins + Inter, canonical mark `brand/glass.svg`.

1. **`market-monday.html` → `out/market-monday.png`** (1080x1350 post, re-rendered each Monday). Ticker-board layout like `market-hero.html` but populated from a **live read** of `beer_market_standing` (top 5 by standing: symbol, display_name, style, standing number). Footer line printed on the graphic: "Standing blends season, cited awards, notability, and community votes." No ▲/▼ arrows and no sparklines until real `beer_market_snapshot` history and nonzero votes exist. As of 2026-07-12 the top row is Allagash White (ALLA, Witbier). Always re-query before rendering.
2. **`screens-carousel.html` → `out/screens-1.png` … `screens-5.png`** (5-frame tall sheet, 1080x1350 each). One real screenshot per slide from `landing/img/screens/` in the order 01-market, 02-analysis, 03-home, 04-taste, 05-discover, each inside a rounded dark phone frame on malt background, one short label per slide (The Market, Analysis, Home, Taste & Feel, Discover), pint mark and taptbeer.com on the last slide.
3. **`screen-spotlight-market.html`** and **`screen-spotlight-taste.html` → `out/screen-spotlight-market.png`, `out/screen-spotlight-taste.png`** (1080x1350 each). Single framed screenshot (`01-market.png`, `04-taste.png`), large, slightly rotated, one headline line above, URL chip below. Same phone-frame treatment as spec 2.
4. **`history-3.html`, `history-4.html` → `out/history-3.png`, `out/history-4.png`** (1080x1350 each, built on `history-template.html`). history-3: Reinheitsgebot, Bavaria 1516, ingredients limited to water, barley, hops (yeast not yet understood). history-4: Porter, London 1700s, named for its popularity with street and river porters; the style that later gave rise to stout. Facts as cited in the footnotes below, framed exactly that carefully on the graphic.
5. **`standing-explainer.html` → `out/standing-1.png` … `standing-3.png`** (3-frame tall sheet, 1080x1350 each). Card 1: "Every beer starts at a base standing." Card 2: "Season fit, cited awards, and notability add to it." Card 3: "Your votes move it most. The board is honest: no bots, no bought spots." Numbers stay off the cards; this explains the blend without flexing the formula.
6. **`beer-of-week.html` (existing template) → `out/botw-live.png`**. Fill the existing Beer of the Week template with the real current market leader at render time (query `beer_market_standing` top row; 2026-07-12 truth: Allagash White, Witbier, Allagash Brewing, United States, cutout via `beer-cutouts` storage if available). Copy on card: "Crowned by the market." Mention awards only as "medals cited in the app," never a count.
7. **Beer Pong gameplay reels A to D** (1080x1920, 8 to 15 seconds each, MP4). Screen-record the real game (`app/Tapt/Features/Games/BeerPongGame.swift`) in the iOS Simulator, crop to 9:16. Reel A: two or three clean sinks with the splash particles and the streak label reaching x2 or higher. Reel B: a rattle-out, ball rings the rim and escapes, then a make. Reel C: slow start holding the drag so the dotted trajectory preview reads clearly, then release and sink. Reel D: a longer run chasing the persistent BEST score shown in the corner. End every reel with a 1-second brand end-card, new file **`reel-endcard.html` → `out/reel-endcard.png`** (1080x1920, pint mark centered, "Beer Pong is in Tapt. Free on taptbeer.com"). No staged or edited outcomes; if the shot misses, keep it or re-record, never composite.

## Honesty guardrails for this calendar

- Market Monday assets read from prod at render time. If the board changes, the graphic changes. Never reuse a stale board render as if current.
- No movement claims (climbing, up this week) until `beer_market_snapshot` has real history and rows have nonzero votes. The v1 "trending" cards (`trending-1/2`) are retired from the schedule until that is true.
- Gameplay reels show only what the game actually does. No fake scores, no composited sinks.
- Beer of the Week names the real current leader. Award mentions stay uncounted in captions.
- No em dashes, no hype adjectives, no number-flexing anywhere in captions or on graphics.

## Fact sources (verified before use)

- **Live market standings (days 1, 8, 15, 22, 29):** prod table `beer_market_standing`, Supabase project qfwiizvqxrhjlthbjosz, queried 2026-07-12. Top standing: Allagash White (season fit + cited award points + notability; zero community votes recorded at query time). Standing formula per `AGENTS.md`: 10 + season(0/40) + awards(≤60, real cited medals only) + notability(≤14) + net_votes×8.
- **IPA and the India trade route (day 4):** BJCP 2021 English IPA history and comments: https://www.bjcp.org/style/2021/12/pale-commonwealth-beer/
- **Pilsner, Plzeň 1842 (day 11):** carried over from v1, sources unchanged. Wikipedia, "Pilsner Urquell": https://en.wikipedia.org/wiki/Pilsner_Urquell · Wikipedia, "Josef Groll": https://en.wikipedia.org/wiki/Josef_Groll
- **Reinheitsgebot, 1516 (day 18):** the Bavarian order adopted in 1516 limited beer ingredients to water, barley, and hops; yeast was not listed because its role in fermentation was not yet understood. Wikipedia, "Reinheitsgebot": https://en.wikipedia.org/wiki/Reinheitsgebot
- **Porter and London's porters, 1700s (day 25):** porter developed in London in the early 18th century and is generally held to be named for its popularity with the city's street and river porters; stronger versions came to be called stout porter, later stout. The naming account is the standard one; the card says "named for the people who drank it" and stays out of contested detail. Wikipedia, "Porter (beer)": https://en.wikipedia.org/wiki/Porter_(beer)
- **Guinness settle (day 28):** carried over from the v1 ig kit. Nitrogenation drives the downward-looking cascade along the glass walls while bubbles rise in the center. Wikipedia, "Guinness" (surge and settle): https://en.wikipedia.org/wiki/Guinness
- **Lager vs ale yeast (day 21):** ale yeasts ferment warmer (top-fermenting); lager yeasts ferment cooler (bottom-fermenting); color is independent of yeast type. Wikipedia, "Beer" and "Lager": https://en.wikipedia.org/wiki/Lager
- **Taste and style descriptors (days 9, 17, and screen spotlights):** BJCP style guidelines, as used by the in-app Taste & Feel engine.
- **App screenshots (days 2, 10, 23):** real captures in `landing/img/screens/` (01-market, 02-analysis, 03-home, 04-taste, 05-discover).
- **Beer Pong feature claims (days 5, 12, 19, 26):** verified in code, `app/Tapt/Features/Games/BeerPongGame.swift` (trajectory preview, rim physics with restitution, splash particles, streak multiplier, persistent best score).
