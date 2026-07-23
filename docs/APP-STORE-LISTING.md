# Tapt — App Store listing (copy + setup)

Paste-ready metadata for App Store Connect. Voice: plain, direct, no hype, no
em dashes. Everything here reflects what the app actually does today.

Bundle ID: `app.tapt.tapt` · Version: `1.0` · Primary language: English (U.S.)

---

## App name (30 char max)
```
Tapt: The Beer Superapp
```
(23 chars. If a shorter name is preferred: `Tapt`.)

## Subtitle (30 char max)
```
Rate, log, and discover beer
```
(28 chars.)

## Category
- Primary: **Food & Drink**
- Secondary: **Social Networking**

---

## Promotional text (170 char max — editable anytime without review)
```
The global Beer Market is live: see what people are logging and rating right now, follow the movers, and log your own pours. All of beer, one app.
```

## Keywords (100 char max, comma separated, no spaces)
```
beer,brewery,ale,ipa,lager,stout,craft beer,taproom,pub,rate beer,beer log,tasting,cellar,pilsner
```

---

## Description
```
Tapt is THE beer superapp. All of beer, in one place.

Rate what you drink, log it to your Cellar, and discover your next pour from a
catalog of tens of thousands of beers from around the world.

THE GLOBAL BEER MARKET
See what people are logging and rating lately. The Beer Market is a live
community popularity board with movers, trends, and a Beer of the Week. It is
not a financial product. There is no money, no trading, and nothing to buy or
sell. Just what the world is pouring right now.

EVERY BEER, ONE PAGE
Open any beer to find its style, flavor notes, brewery, and a bit of history,
plus how the community rates it. Add your own private notes and rating.

YOUR BEER PASSPORT
Earn stamps for exploring, not for drinking. Tapt celebrates variety and
discovery: new styles, new breweries, new countries, and smart low and no
alcohol choices. It never rewards how much you drink.

BEER NEAR YOU
Find breweries, pubs, and taprooms around you on the map, with popular spots
near the top.

THE TAPT DISPATCH
Subscribe to a free weekly read on the beer world: what is moving, a piece of
beer history, and a legendary bar or brewery worth knowing.

FOR BREWERIES AND BARS
Claim your venue, tell your story, and reach people who are looking for their
next beer.

Tapt is for people of legal drinking age. Please drink responsibly and never
drink and drive. Tapt does not sell alcohol.
```

## What's New (version 1.0)
```
Welcome to Tapt. Rate and log beer, follow the global Beer Market, earn Passport
stamps for exploring, and find breweries and bars near you.
```

---

## URLs
- Marketing URL: `https://taptbeer.com`
- Support URL: `https://taptbeer.com/support`
- Privacy Policy URL: `https://taptbeer.com/privacy`

> Confirm each resolves before submitting. Terms live at
> `https://taptbeer.com/terms`.

---

## Age rating
Answer the questionnaire so the app lands at **17+** (old system) / **18+**
(new 2025 system), which is required for alcohol content.

- Alcohol, Tobacco, or Drug Use or References: **Frequent**
- Contests: **Frequent** (trivia and community rankings)
- Age Assurance, User-Generated Content, Social Media, Advertising: **Yes**
- Social Media Disabled for Users Under 13: **No**
- Everything else (violence, sexual content, gambling, simulated gambling,
  horror, mature/suggestive, medical, profanity, messaging/chat): **None/No**
- Unrestricted Web Access: **No**
- Gambling: **No** (the Beer Market is a popularity board, not gambling — see
  review notes)

## Copyright
```
2026 Tapt
```

---

## App Privacy (must match PrivacyInfo.xcprivacy)
Data collected and linked to the user:
- **Contact Info:** name, email address (from Sign in with Apple / account) —
  used for App Functionality, Account Management.
- **User Content:** the beers you rate, log, and note; photos you add —
  App Functionality.
- **Identifiers:** user ID — App Functionality.
- **Location:** precise location, only when granted, to show nearby venues —
  App Functionality. Not used for tracking. Not collected in the background.
- **Usage Data / Diagnostics:** basic app diagnostics — App Functionality,
  Analytics.

- Tracking (ATT): **No.** Tapt does not track users across apps or websites.
- Aggregated, de-identified insights may be shared with partners; individual
  identity is not sold. This is disclosed in the Privacy Policy.

---

## App Review notes (paste into the "Notes" field)
```
Tapt is a beer discovery and logging app for people of legal drinking age. It
does not sell alcohol or facilitate its purchase or delivery.

AGE GATE: Onboarding requires confirming legal drinking age. Terms and Privacy
require legal drinking age.

THE "BEER MARKET": This is a community popularity board that ranks beers by
recent check-ins and ratings. It is NOT gambling and NOT a financial product.
There is no currency, no wagering, no real or virtual money, and nothing to buy
or sell. "Up" and "down" arrows reflect changes in community popularity only.

SIGN IN: Sign in with Apple is supported. A demo account is provided in the App
Review Information fields and opens the full signed-in experience, including
Discover and account-only social surfaces.

UGC SAFETY: Users can report and block other users and content. A EULA
(Terms of Service) is linked in-app and on the website.

ACCOUNT DELETION: Users can delete their account in-app under You > Settings.

RESPONSIBLE PLAY: Games are skill, trivia, and scorekeeping experiences. They
never require alcohol and never score alcohol use. Visible labels were revised
for App Review: Beer Olympics is now Table Olympics, Beer Night is now Game
Night, Beer Pong is now Cup Pong, and Flip Cup is now Cup Flip.

Demo account:
Stored only in App Store Connect and the protected GitHub Actions secrets
`ASC_DEMO_ACCOUNT_NAME` and `ASC_DEMO_ACCOUNT_PASSWORD`. Never commit the
credentials to this repository.
```

---

## Owner setup checklist (things I cannot do — they need your Apple account)
1. Create the app record in App Store Connect (bundle `app.tapt.tapt`, name above).
2. Upload a signed build (Xcode Archive > Distribute, or the CI pipeline).
3. Paste the copy above into the version page.
4. Upload the screenshot set (see social-assets / App Store carousel).
5. Set age rating via the questionnaire above (lands at 17+/18+).
6. Fill App Privacy to match this doc + PrivacyInfo.xcprivacy.
7. Create the review demo account and add its email/password to the protected
   GitHub Actions secrets above; release preparation writes them to App Store
   Connect without logging their values.
8. Submit for review.
