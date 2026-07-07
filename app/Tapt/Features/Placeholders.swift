import SwiftUI

// First-pass branded screens. Each becomes a real feature next:
//   Scan   -> VisionKit DataScanner -> identify -> rate
//   Cellar -> your logged pours + wishlist
//   On Tap -> MapKit breweries + "popular near me" from first-party check-ins
//   Games  -> trivia / card / table games (Brewery Mode)

// ScanView -> Features/Scan/ScanView.swift

// CellarView -> Features/Cellar/CellarView.swift

// NearYouView -> Features/NearYou/NearYouView.swift

// GamesView -> Features/Games/GamesView.swift

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
