# Tapt App Store Listing

Paste-ready metadata for App Store Connect. Voice: plain, direct, no hype, no
em dashes. Everything here reflects what the app actually does today.

Bundle ID: `app.tapt.tapt` · Version: `1.0` · Primary language: English (U.S.)

---

## App name (30 char max)
```
Tapt: THE Beer Superapp
```
(23 chars. If a shorter name is preferred: `Tapt`.)

## Subtitle (30 char max)
```
THE Beer Superapp
```
(17 chars.)

## Category
- Primary: **Food & Drink**
- Secondary: **Social Networking**

---

## Promotional text (170 char max, editable anytime without review)
```
Scan a label or barcode, log a pour, stamp your Passport, browse nearby beer spots, vote on the Beer Market, and play table games. Free for drinkers.
```

## Keywords (100 char max, comma separated, no spaces)
```
beer,brewery,bar,pub,taproom,cellar,passport,scanner,trivia,games,craft
```

---

## Description
```
Meet Tapt, THE Beer Superapp.

SCAN AND LEARN
Scan a barcode, beer label, tap list, or venue QR. Explore style science,
tasting notes, ingredients, history, awards, and brewery information from
sourced catalog data.

BUILD YOUR CELLAR
Log pours, add private notes, track styles, and turn each new state or country
into Passport progress.

FIND BEER NEAR YOU
Browse real breweries, pubs, bars, taprooms, and beer gardens on the global Beer
Radar. Tapt's venue map uses real coordinates and source provenance.

RIDE THE BEER MARKET
Vote beers up or down and watch rankings move from real community activity. No
invented scores: empty boards stay empty until people vote or log pours.

LEARN AND PLAY
Use guided flights, Beer School, trivia, skill games, and zero-proof-friendly
table tools to bring people together. Tapt games never require alcohol and never
score alcohol use.

FOLLOW YOUR BEER CIRCLE
Find friends, follow public Passport progress, and see eligible check-ins on
Tonight. Report and block controls are built in.

FOR BREWERIES AND BARS
Claim a venue, publish a live tap list, share a QR menu, and view real venue
activity through Tapt for Business.

Tapt is free for drinkers. It is for people of legal drinking age and does not
sell alcohol. Please drink responsibly and never drink and drive.
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
- Gambling: **No** (the Beer Market is a popularity board, not gambling; see
  review notes)

## Copyright
```
2026 Tapt
```

---

## App Privacy (must match PrivacyInfo.xcprivacy)
Data collected and linked to the user:
- **Contact Info:** name, email address (from Sign in with Apple / account):
  used for App Functionality, Account Management.
- **User Content:** the beers you rate, log, and note; photos you add:
  App Functionality.
- **Identifiers:** user ID: App Functionality.
- **Location:** precise location, only when granted, to show nearby venues:
  App Functionality. Not used for tracking. Not collected in the background.
- **Usage Data / Diagnostics:** basic app diagnostics: App Functionality,
  Analytics.

- Tracking (ATT): **No.** Tapt does not track users across apps or websites.
- Aggregated, de-identified insights may be shared with partners; individual
  identity is not sold. This is disclosed in the Privacy Policy.

---

## App Review notes (paste into the "Notes" field)
```
Tapt is an informational and social beer app for legal-drinking-age adults. It
does not sell alcohol.

PUBLIC REVIEW PATH
- Tap "Explore without an account" to inspect catalog search, the local MapKit
beer-place map, Beer School, points-only table games, Discover, and partner
information without providing credentials.
- Account-only actions clearly return the reviewer to sign-in.

ACCOUNT REVIEW PATH
- Tap "Sign in with password" and use the dedicated demo account supplied in the
App Review fields. The account opens the full signed-in experience, including
Discover and account-only social surfaces.
- Email link/code, Sign in with Apple, and Google are also available. All
complete inside the signed app and return to Tapt.
- Delete account: You tab > Delete account > confirm. This revokes stored Sign
in with Apple authorization, deletes avatar objects, the auth identity, and all
personal-plane rows.
- Privacy controls: You tab > Privacy Choices. Optional aggregate and
partner-insight sharing default off.
- UGC safety: profile text is filtered before publication; avatar uploads wait
for approval; report/block actions are available from social feed items and
public profiles; reports enter an authenticated admin moderation queue.
- Age rating: Tapt includes social-media capability through profile search,
follows, and the Tonight feed, and includes frequent contests through
trivia/rankings. We do not claim the under-13 social-media mitigation because
Tapt does not use Apple's Declared Age Range API.
- Responsible play: games are skill, trivia, and scorekeeping experiences. They
never require alcohol, include zero-proof play, and contain no volume,
speed-drinking, or alcohol-consumption prompts. The prior visible game labels
have been revised for App Review: Beer Olympics is now Table Olympics, Beer
Night is now Game Night, Beer Pong is now Cup Pong, and Flip Cup is now Cup
Flip.
- Passport badges reward distinct beers, styles, and places rather than repeat
consumption volume.

LOCATION AND CAMERA
- Both permissions are optional and requested in context. The public catalog,
learning, and games remain usable without either permission.
- The camera supports beer barcodes, printed label/tap-list text, and partner QR
scanning.

DATA INTEGRITY
- Beer, brewery, and venue records are source-attributed. Community boards
remain empty until real eligible activity exists; the production app contains
no fabricated votes or check-ins.
```

---

## Owner setup checklist (things I cannot do because they need your Apple account)
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
