# Tapt - iOS app

Positioning: **The Beer Superapp**. Tapt covers breweries, pubs, bars, taprooms, beer gardens, local events, education, scanning, cellar/passport progress, and table games.

Native Swift 6 / SwiftUI (iOS 18+). Backend: Supabase project `qfwiizvqxrhjlthbjosz`.

## Generate and open
The `.xcodeproj` is generated (kept out of git) via XcodeGen:

    brew install xcodegen        # if not installed
    cd app && xcodegen generate  # writes Tapt.xcodeproj
    open Tapt.xcodeproj

Set the Signing Team (`J9DMDH4S58`) and run on an iOS 18+ device or simulator.

## Structure
- `Tapt/TaptApp.swift` - app entry
- `Tapt/RootView.swift` - tab shell: Explore / Scan / Cellar / Discover / You
- `Tapt/Core/SupabaseClient.swift` - shared client (public URL + publishable key)
- `Tapt/Core/Models.swift` - Codable models mirroring the DB schema
- `Tapt/Design/Theme.swift` - brand tokens ("Elevated Taproom")
- `Tapt/Features/Placeholders.swift` - branded first-pass screens

## Next
- Auth: Sign in with Apple + Google (via Supabase) once the App ID + SiwA config are provisioned
- Scan: VisionKit `DataScanner` -> pg_trgm match -> rate
- Near You: MapKit + Tapt venue radar for breweries, pubs, bars, taprooms, and beer gardens
- Games: Trivia, Tapt Deck, Beer Pong, Flip Cup, Quarters, and Beer Night Mode
