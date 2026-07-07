# Tapt - iOS app

Native Swift 6 / SwiftUI (iOS 18+). Backend: Supabase project `qfwiizvqxrhjlthbjosz`.

## Generate and open
The `.xcodeproj` is generated (kept out of git) via XcodeGen:

    brew install xcodegen        # if not installed
    cd app && xcodegen generate  # writes Tapt.xcodeproj
    open Tapt.xcodeproj

Set the Signing Team (`J9DMDH4S58`) and run on an iOS 18+ device or simulator.

## Structure
- `Tapt/TaptApp.swift` - app entry
- `Tapt/RootView.swift` - tab shell: Scan / Cellar / On Tap / Games
- `Tapt/Core/SupabaseClient.swift` - shared client (public URL + publishable key)
- `Tapt/Core/Models.swift` - Codable models mirroring the DB schema
- `Tapt/Design/Theme.swift` - brand tokens ("Elevated Taproom")
- `Tapt/Features/Placeholders.swift` - branded first-pass screens

## Next
- Auth: Sign in with Apple + Google (via Supabase) once the App ID + SiwA config are provisioned
- Scan: VisionKit `DataScanner` -> pg_trgm match -> rate
- On Tap: MapKit + `MKLocalPointsOfInterestRequest(.brewery)` + check-in heatmap
- Games: Trivia first, then card + table games (Brewery Mode on the Crew engine)
