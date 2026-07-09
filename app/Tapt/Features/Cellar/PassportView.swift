import SwiftUI

/// The Passport: countries collected, styles explored, and earned badges.
struct PassportView: View {
    let checkins: [MyCheckin]
    var guides: [RegionBeerGuide] = []

    private var stats: PassportStats {
        PassportStats(pours: checkins.count, styles: visitedStyles.count, countries: visitedCountries.count)
    }
    private var visitedCountries: Set<String> {
        Set(checkins.map(\.country).filter { !$0.isEmpty })
    }
    private var visitedStyles: [String] {
        Array(Set(checkins.compactMap { ($0.style?.isEmpty == false) ? $0.style : nil })).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("Countries", "\(stats.countries) / \(PassportData.countries.count)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                        ForEach(PassportData.countries, id: \.name) { item in
                            let visited = visitedCountries.contains(item.name)
                            VStack(spacing: 4) {
                                Text(item.flag).font(.system(size: 30)).grayscale(visited ? 0 : 1).opacity(visited ? 1 : 0.4)
                                Text(item.name).font(.caption2).foregroundStyle(visited ? Brand.text : Brand.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(visited ? Brand.gold.opacity(0.15) : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(visited ? Brand.gold : .clear, lineWidth: 1.5))
                        }
                    }
                }

                if !visitedStyles.isEmpty {
                    section("Styles explored", "\(stats.styles)") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                            ForEach(visitedStyles, id: \.self) { s in
                                Text(s).font(.caption.weight(.semibold)).foregroundStyle(Brand.malt)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(Brand.hop.opacity(0.25), in: Capsule())
                            }
                        }
                    }
                }

                if !guides.isEmpty {
                    section("World shelves", "\(visitedGuideCount) unlocked") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(guides.filter { $0.scope == "country" }.prefix(12)) { guide in
                                let visited = visitedCountries.contains(guide.name)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(flag(guide.flag)).font(.title2)
                                        Spacer()
                                        Image(systemName: visited ? "seal.fill" : "lock.fill")
                                            .foregroundStyle(visited ? Brand.gold : Brand.muted)
                                    }
                                    Text(guide.name)
                                        .font(.system(.headline, design: .rounded).weight(.bold))
                                        .foregroundStyle(Brand.text)
                                    Text(visited ? guide.passportPhrase : guide.heroStyle)
                                        .font(.caption)
                                        .foregroundStyle(Brand.muted)
                                        .lineLimit(3)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
                                .background(visited ? Brand.gold.opacity(0.14) : Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(visited ? Brand.gold : Brand.malt.opacity(0.08)))
                            }
                        }
                    }
                }

                section("Badges", "") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                        ForEach(PassportData.badges) { badge in
                            let earned = badge.earned(stats)
                            HStack(spacing: 10) {
                                Image(systemName: earned ? badge.icon : "lock.fill")
                                    .foregroundStyle(earned ? Brand.malt : Brand.muted)
                                    .frame(width: 40, height: 40)
                                    .background(earned ? Brand.gold : Brand.haze, in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(badge.title).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                                    Text(badge.detail).font(.caption2).foregroundStyle(Brand.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                            .opacity(earned ? 1 : 0.55)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Passport")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var visitedGuideCount: Int {
        guides.filter { $0.scope == "country" && visitedCountries.contains($0.name) }.count
    }

    private func flag(_ code: String?) -> String {
        switch code {
        case "BE": return "🇧🇪"
        case "CZ": return "🇨🇿"
        case "DE": return "🇩🇪"
        case "IE": return "🇮🇪"
        case "JP": return "🇯🇵"
        case "MX": return "🇲🇽"
        case "PL": return "🇵🇱"
        case "GB": return "🇬🇧"
        case "US": return "🇺🇸"
        default: return "🍺"
        }
    }

    private func section<Content: View>(_ title: String, _ trailing: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Brand.muted)
                }
            }
            content()
        }
    }
}
