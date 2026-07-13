# Tapt — Instagram content library

A cohesive, high-design launch set for **Tapt, THE Beer Superapp** (@taptbeerapp · taptbeer.com).

## Publishing gate

The tracked renders are a design review library, not an automatic publishing
queue. Do not publish `launch-post.png` or `launch-story.png` before the App
Store release is live. Do not publish `market-hero.png`, `trending-1.png`,
`trending-2.png`, `whatwedo-2.png`, or `beer-of-week.png`; those legacy frames
contain illustrative market state. Replace them with a same-day production data
render following `CONTENT-CALENDAR-V2.md`.

- Source HTML lives in this folder. Rendered PNGs are in `out/`. Open `gallery.html` to review everything at a glance.
- Built to match `../brand/master.html`: palette (gold `#F2A900`, malt `#1A1206`, foam `#FBF6EC`, hop `#3F8F5B`, copper `#B4531F`), Poppins + Inter, and the shaker-pint mark. Every asset is carried by a visual (the pint mark, style-tinted glass marks, the stock-market ticker language, inline SVG icons, QR marks, or real app screenshots), not by words.
- **Honesty:** no invented data. All beers are real with correct styles and countries. Market ranks, directions, and sparklines are publishable only when generated from the production snapshot used for that render. Beer-glass marks are tinted to each beer's real style color, standing in for product photos so nothing is faked or logo-scraped.

Voice: plain, direct, confident. No hype adjectives, no em dashes, no number-flexing. The claim is "THE Beer Superapp / All of beer, one app."

## Render

Headless Chrome at 2x. Singles are 1080x1350, stories 1080x1920. Carousels and templates are built as one tall stacked sheet, then sliced with PIL.

```
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --virtual-time-budget=5000 --window-size=1080,1350 --screenshot=out/NAME.png "file://ABS/PATH/NAME.html"
# tall sheets: set --window-size=1080,(frames*1350), then crop each frame with PIL
```

Frame count: **31**.

---

## Assets and suggested captions

### Launch
- **`out/launch-post.png`** (post) and **`out/launch-story.png`** (story)
  > It's here. THE Beer Superapp.
  > Rate any beer, build your cellar, and watch it climb the Beer Market as people vote. All of beer, one app.
  > Free on taptbeer.com 🍺
  > #beer #craftbeer #beerapp #beerlover #beertography #beercommunity #cerveza

### Carousel — Who we are (`out/whoweare-1.png` … `whoweare-4.png`)
> Who we are, in four cards.
> THE Beer Superapp. And an honest one: the boards stay empty until the community votes. No bots, no bought spots.
> It's free → taptbeer.com 🍺
> #beer #craftbeer #beerapp #beercommunity #beerlover #beertography

### Carousel — What we do (`out/whatwedo-1.png` … `whatwedo-5.png`)
> Everything beer, one Passport.
> A living catalog, the Beer Market, what's trending and in season by state and country, mini games, and your Passport. Swipe through.
> taptbeer.com 🍺
> #beer #craftbeer #beerapp #beerlover #beereducation #beertography

### Carousel — Who it's for (`out/whoitsfor-1.png` … `whoitsfor-3.png`)
> Who Tapt is for.
> Drinkers rate and cellar what they drink. Bars and breweries get a free hosted menu, QR, and a claimed profile. Everyone in between just likes beer.
> taptbeer.com 🍺
> #beer #craftbeer #brewery #taproom #beercommunity #beerlover

### Carousel — Menus for partners (`out/partners-1.png` … `partners-4.png`)
> Free menu hosting, forever.
> Claim your venue, publish your tap list, print your QR for the tables, and see your real local drinker signal. You only ever pay to be louder.
> Claim it free → taptbeer.com
> #brewery #taproom #craftbeer #beerbusiness #supportlocalbeer #barlife

### Carousel — Mini games (`out/games-1.png` … `games-3.png`)
> Game night, built in.
> Trivia, the Tapt Deck, Darts, Connect 4, Beer Olympics, Flip Cup. A superapp, not a logbook.
> taptbeer.com 🍺
> #beer #craftbeer #gamenight #beerpong #beercommunity #beerlover

### The Beer Market (`out/market-hero.png`)
> A stock market for beer.
> Every beer is a ticker. Vote it up, it climbs. Vote it down, it slides. No prices, just what people actually drink.
> taptbeer.com 🍺
> #beer #craftbeer #beercommunity #beerapp #beertography #cerveza

### Trending beer, weekly template (`out/trending-1.png`, `out/trending-2.png`)
Legacy design examples only. Do not publish them. A replacement must be built
from current production snapshots on the publishing day.

### Beer history, template (`out/history-1.png`, `out/history-2.png`)
> IPA sailed to get its name.
> London brewers shipped well-attenuated, heavily hopped pale stock ales to India from the late 1700s. The name India Pale Ale appeared around 1830.
> Every style, decoded in Tapt → taptbeer.com 🍺
> #ipa #beerhistory #craftbeer #beer #beereducation #beerfacts

> The first golden beer: Plzeň, 1842.
> Before 1842 most beer was dark. In Plzeň, brewer Josef Groll poured the first pale lager, and clear glass finally showed the color off.
> taptbeer.com 🍺
> #pilsner #beerhistory #beer #craftbeer #beerfacts #lager

### One-offs
- **`out/quote-card.png`** — brand statement
  > All of beer. One app. That's the whole idea. taptbeer.com 🍺
  > #beer #craftbeer #beerapp #beerlover #beertography #beercommunity
- **`out/for-bars-card.png`** — for the bars and breweries
  > Your menu, hosted free. Print the QR for your tables, claim your spot on the map, and see your real local activity. You only ever pay to be louder.
  > taptbeer.com · #brewery #taproom #craftbeer #beerbusiness #supportlocalbeer #barlife
- **`out/seasonal-card.png`** — seasonal
  > Summer in a glass. Witbier, Hefeweizen, Pilsner: light, bright, warm-weather styles. Decoded in Tapt.
  > #summerbeer #witbier #hefeweizen #pilsner #craftbeer #beer
- **`out/beer-of-week.png`** — Beer of the Week template
  > Beer of the Week. The beer the market crowns each Monday, from real votes.
  > taptbeer.com · #beer #craftbeer #beeroftheweek #beercommunity #beerlover

### App preview (`out/app-preview.png`)
> The app, already pouring. Real screens: the Beer Market, Discover, and the Taste & Feel breakdown.
> taptbeer.com 🍺
> #beer #craftbeer #beerapp #appdesign #beerlover #beertography

---

## Real beers used (style · country)
Allagash White (Belgian Witbier · USA) · Pilsner Urquell (Czech Pilsner · Czechia) · Guinness Draught (Irish Stout · Ireland) · Sierra Nevada Pale Ale (American Pale Ale · USA) · Weihenstephaner Hefeweissbier (German Hefeweizen · Germany). Style names follow common BJCP categories; glass marks are tinted to each style's real color.

## Fact sources (verified before use)
- **Pilsner, Plzeň 1842:** the first pale lager was brewed in Plzeň (Pilsen), Bohemia; Bavarian brewer Josef Groll brewed the first batch on 5 October 1842 at the Burghers' Brewery (now Pilsner Urquell / Plzeňský Prazdroj).
  - Wikipedia, "Pilsner Urquell": https://en.wikipedia.org/wiki/Pilsner_Urquell
  - Wikipedia, "Josef Groll": https://en.wikipedia.org/wiki/Josef_Groll
- **IPA name and trade route:** London brewers shipped well-attenuated, heavily hopped pale stock ales to India from the late 1700s. George Hodgson's Bow Brewery became a prominent supplier, but did not invent the style for the voyage. The name India Pale Ale appeared around 1830.
  - BJCP 2021, English IPA history and comments: https://www.bjcp.org/style/2021/12/pale-commonwealth-beer/
- **Summer styles (seasonal card):** Witbier, Hefeweizen, and Pilsner are widely recognized light, warm-weather styles. This is a qualitative style claim, not a data point; taste descriptors (citrusy, banana/clove, crisp) follow standard BJCP sensory profiles.

## Honesty notes (what was intentionally left out)
- **No market render is publishable unless every rank, direction, and sparkline comes from the production snapshot used for that render.** The legacy illustrative frames above are quarantined from publishing.
- **The IPA origin story avoids the voyage myth.** BJCP notes that IPA was not invented specifically for India and that other beer styles were also shipped there.
- **No competitor is named and no competitor price is printed on any graphic.** The partner value is stated as "$0 forever for the basics" and "you only ever pay to be louder," consistent with the live site.
- **Beer-glass marks, not product photos or logos.** Tinting a glass to a style's real color avoids fabricated or scraped brand imagery.
