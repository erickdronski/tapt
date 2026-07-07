# Tapt - Social & sharing

The whole app is built to be shareable. Every meaningful moment produces a brand-locked card you can post in one tap.

## Share cards (auto-generated)
- `PourCard` model + `ShareCard` view (`Features/Sharing/ShareCard.swift`): 360x640 (9:16), rendered to a 1080x1920 image via `ImageRenderer`. Always the light "craft can" look so it reads the same everywhere.
- `CardShareView` bundles the card with a system share button + a direct "Stories" button.

## Channels
- **Anywhere:** SwiftUI `ShareLink` opens the iOS share sheet (Messages, Instagram feed, X, save to Photos, etc.).
- **Instagram Stories (direct):** set the pasteboard item `com.instagram.sharedSticker.backgroundImage` and open `instagram-stories://share?source_application=<FB_APP_ID>` (`ShareTools.shareToInstagramStories`).

## Setup required (one-time)
1. **Info.plist:** add `LSApplicationQueriesSchemes` with `instagram-stories` so `canOpenURL` works. In xcodegen add under the target's `info.properties`:
   ```yaml
   LSApplicationQueriesSchemes: [instagram-stories]
   ```
2. **Facebook App ID:** create an app at developers.facebook.com, then pass it to `CardShareView(facebookAppID:)`. Without it the generic Share sheet still posts to Instagram feed and everywhere else.

## Card types to add next
Pour card (done) -> Badge unlock -> Passport milestone (styles/countries) -> Flight results -> Crew leaderboard -> "Year in Beer".
