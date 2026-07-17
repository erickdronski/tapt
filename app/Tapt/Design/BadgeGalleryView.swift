#if DEBUG
import SwiftUI

/// Dev-only gallery to eyeball every custom badge glyph at once, all earned.
/// Shown when the app launches with TAPT_BADGE_GALLERY=1. Not shipped in UI.
struct BadgeGalleryView: View {
    private var maxed: PassportStats {
        var s = PassportStats(pours: 999, beers: 999, styles: 999, states: 99, countries: 99)
        s.breweries = 99; s.styleFamilies = 9; s.continents = 9; s.seasons = 9; s.noLow = 9
        s.hoppy = 9; s.dark = 9; s.wheat = 9; s.sour = 9; s.belgian = 9; s.crisp = 9
        return s
    }
    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(PassportData.badges) { badge in
                    BadgeSticker(badge: badge, stats: maxed, size: 84)
                }
            }
            .padding()
        }
        .background(Brand.background)
    }
}
#endif
