import SwiftUI

// First-pass branded screens. Each becomes a real feature next:
//   Scan   -> VisionKit DataScanner -> identify -> rate
//   Cellar -> your logged pours + wishlist
//   On Tap -> MapKit breweries + "popular near me" from first-party check-ins
//   Games  -> trivia / card / table games (Brewery Mode)

struct ScanView: View {
    var body: some View { BrandScreen(title: "Scan", subtitle: "Point at a can, tap list, or label.", symbol: "viewfinder") }
}

struct CellarView: View {
    var body: some View { BrandScreen(title: "Cellar", subtitle: "Your Cellar is looking thirsty. Log your first pour.", symbol: "square.stack.3d.up") }
}

struct NearYouView: View {
    var body: some View { BrandScreen(title: "On Tap Near You", subtitle: "See what is good on tap around you.", symbol: "mappin.and.ellipse") }
}

struct GamesView: View {
    var body: some View { BrandScreen(title: "Tapt Games", subtitle: "Trivia, cards, and table games. Free, always.", symbol: "die.face.5") }
}

/// Shared branded empty-state scaffold (voice + tokens from docs/06-BRAND.md).
struct BrandScreen: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Brand.text)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}
