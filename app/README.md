# Tapt - iOS app

Positioning: **THE Beer Superapp. All of beer, one app.** Tapt covers beer discovery, breweries, pubs, bars, taprooms, beer gardens, local events, education, scanning, Cellar and Passport progress, and table games.

Native Swift 6 / SwiftUI (iOS 18+). Backend: Supabase project `qfwiizvqxrhjlthbjosz`.

## Generate and open
The `.xcodeproj` is generated (kept out of git) via XcodeGen:

    brew install xcodegen        # if not installed
    cd app && xcodegen generate  # writes Tapt.xcodeproj
    open Tapt.xcodeproj

Set the Signing Team (`J9DMDH4S58`) and run on an iOS 18+ device or simulator.

## Structure
- `Tapt/TaptApp.swift` - app entry
- `Tapt/RootView.swift` - tab shell: Home / Market / Cellar / Discover / You; Scan is reached from Home
- `Tapt/Core/SupabaseClient.swift` - shared client (public URL + publishable key)
- `Tapt/Core/Models.swift` - Codable models mirroring the DB schema
- `Tapt/Design/Theme.swift` - brand tokens ("Elevated Taproom")
- `Tapt/Features/` - production feature surfaces grouped by domain

## Auth and release gates
- Email magic-link and six-digit code sign-in are implemented and enabled.
- Google is enabled and has completed the hosted callback; each release candidate still requires a signed-device TestFlight callback test.
- Apple is enabled and the native flow is implemented. It intentionally fails closed until the four token-exchange Edge secrets are configured; after that, the server stores the refresh token in Vault so in-app deletion can revoke Apple authorization.
- Facebook is disabled and hidden until Meta credentials and a signed-device callback test are complete.
- X and phone sign-in are not enabled and must not be presented as available.

## Core surfaces
- Scan: VisionKit `DataScanner`, catalog matching, and explicit-rating pour logging
- Near You: MapKit plus the Tapt venue radar for breweries, pubs, bars, taprooms, and beer gardens
- Games: Trivia, Tapt Deck, SpriteKit Beer Pong, Flip Cup, Quarters, and Beer Night Mode
