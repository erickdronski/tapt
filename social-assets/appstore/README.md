# App Store screenshot carousel

Five paste-ready App Store screenshots, 1290x2796 (6.9" required size), built
from real in-app screenshots (iPhone 17 Pro sim). Order = the marketing story.

1. 01_superapp.png  — THE Beer Superapp / All of beer, in one app.
2. 02_market.png    — The global Beer Market / what people are drinking now.
3. 03_beerpage.png  — Every beer, one page / ratings, style, ABV, movement.
4. 04_passport.png  — Your Beer Passport / stamps for exploring, not drinking.
5. 05_nearyou.png   — Beer near you / breweries, pubs, taprooms around you.

_contact_sheet.png = all five at a glance.

To regenerate after UI changes: recapture the five raw screens (1206x2622,
`xcrun simctl status_bar ... --time "9:41"` first), then run `make_carousel.py`
in this directory (RAW_DIR + FONT_DIR env vars; Poppins OFL). Copy for each
slide lives in that script.
Listing text (name, subtitle, description, keywords, age rating, privacy,
review notes) is in `docs/APP-STORE-LISTING.md`.
