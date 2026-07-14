import SwiftUI

/// The Passport: countries collected, styles explored, and earned badges.
struct PassportView: View {
    let checkins: [MyCheckin]
    var guides: [RegionBeerGuide] = []

    // Badge-unlock celebration: remember which badges we've already shown so a
    // newly earned one gets a moment, but pre-existing ones never false-fire.
    @AppStorage("passport.seenBadges") private var seenBadgesRaw = ""
    @AppStorage("passport.badgesSeeded") private var badgesSeeded = false
    @State private var celebration: TaptCelebration?
    @State private var showsAllStates = false
    @State private var showsAllCountries = false

    private var stats: PassportStats {
        PassportStats.from(
            checkins: checkins,
            beers: uniqueBeerCount,
            styles: visitedStyles.count,
            states: visitedStates.count,
            countries: visitedCountries.count
        )
    }
    private var visitedCountries: Set<String> {
        Set(checkins.map(\.passportCountry).filter { !$0.isEmpty })
    }
    private var visitedStates: Set<String> {
        Set(checkins.filter { $0.passportCountry == "United States" }.map(\.venueRegion).filter { !$0.isEmpty })
    }
    private var visitedStyles: [String] {
        Array(Set(checkins.compactMap { ($0.style?.isEmpty == false) ? $0.style : nil })).sorted()
    }
    private var uniqueBeerCount: Int {
        PassportProgress.uniqueBeerCount(in: checkins)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                progressOverview

                section("Badges", "\(earnedBadgeCount) / \(PassportData.badges.count)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                        ForEach(PassportData.badges) { badge in
                            BadgeSticker(badge: badge, stats: stats)
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
                    section("State shelves", "\(visitedStateGuideCount) unlocked") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(orderedGuides(scope: "state", visited: visitedStates).prefix(12)) { guide in
                                let visited = visitedStates.contains(guide.name)
                                shelfCard(guide, visited: visited)
                            }
                        }
                    }

                    section("World shelves", "\(visitedGuideCount) unlocked") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(orderedGuides(scope: "country", visited: visitedCountries).prefix(12)) { guide in
                                let visited = visitedCountries.contains(guide.name)
                                shelfCard(guide, visited: visited)
                            }
                        }
                    }
                }

                section("States collected", "\(stats.states) / \(BeerRegions.states.count)") {
                    let visibleStates = showsAllStates
                        ? BeerRegions.states
                        : BeerRegions.states.filter { visitedStates.contains($0) }
                    if !visibleStates.isEmpty { stateGrid(visibleStates) }
                    collectionToggle(
                        title: showsAllStates ? "Hide state map" : "View all states",
                        expanded: showsAllStates
                    ) {
                        showsAllStates.toggle()
                    }
                }

                section("Countries collected", "\(stats.countries) / \(PassportData.countries.count)") {
                    let visibleCountries = showsAllCountries
                        ? PassportData.countries
                        : PassportData.countries.filter { visitedCountries.contains($0.name) }
                    if !visibleCountries.isEmpty { countryGrid(visibleCountries) }
                    collectionToggle(
                        title: showsAllCountries ? "Hide world map" : "View all countries",
                        expanded: showsAllCountries
                    ) {
                        showsAllCountries.toggle()
                    }
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Passport")
        .navigationBarTitleDisplayMode(.inline)
        .taptCelebration($celebration)
        .onAppear { checkForNewBadge() }
        .onChange(of: checkins.count) { checkForNewBadge() }
    }

    private var earnedBadgeCount: Int {
        PassportData.badges.filter { $0.earned(stats) }.count
    }

    private var progressOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your beer trail")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 14) {
                progressMetric("\(stats.pours)", "pours", "drop.fill", Brand.gold)
                progressMetric("\(uniqueBeerCount)", "beers", "shippingbox.fill", Brand.copper)
                progressMetric("\(stats.styles)", "styles", "square.grid.2x2.fill", Brand.hop)
                progressMetric("\(stats.states)", "states", "map.fill", Brand.copper)
                progressMetric("\(stats.countries)", "countries", "globe", Brand.gold)
            }
        }
    }

    private func progressMetric(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                Text(label).font(.caption2).foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .combine)
    }

    private func stateGrid(_ states: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(states, id: \.self) { state in
                let visited = visitedStates.contains(state)
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: visited ? "checkmark.seal.fill" : "mappin.circle.fill")
                        .foregroundStyle(visited ? Brand.gold : Brand.muted)
                    Text(state)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(visited ? Brand.text : Brand.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(visited ? Brand.gold.opacity(0.16) : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(visited ? Brand.gold : Brand.malt.opacity(0.08), lineWidth: 1.3))
                .accessibilityElement(children: .combine)
                .accessibilityValue(visited ? "Collected" : "Not collected")
            }
        }
    }

    private func countryGrid(_ countries: [(name: String, flag: String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
            ForEach(countries, id: \.name) { item in
                let visited = visitedCountries.contains(item.name)
                VStack(spacing: 4) {
                    Text(item.flag)
                        .font(.system(size: 30))
                        .grayscale(visited ? 0 : 1)
                        .opacity(visited ? 1 : 0.4)
                    Text(item.name)
                        .font(.caption2)
                        .foregroundStyle(visited ? Brand.text : Brand.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(visited ? Brand.gold.opacity(0.15) : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(visited ? Brand.gold : .clear, lineWidth: 1.5))
                .accessibilityElement(children: .combine)
                .accessibilityValue(visited ? "Collected" : "Not collected")
            }
        }
    }

    private func collectionToggle(title: String, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { action() }
        } label: {
            Label(title, systemImage: expanded ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Brand.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Brand.haze, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    /// Fires a badge-unlock celebration for the most impressive newly earned
    /// badge. On first ever view it silently records what's already earned.
    private func checkForNewBadge() {
        let earned = PassportData.badges.filter { $0.earned(stats) }
        let earnedIds = Set(earned.map(\.id))
        let seen = Set(seenBadgesRaw.split(separator: ",").map(String.init))
        guard badgesSeeded else {
            seenBadgesRaw = earnedIds.sorted().joined(separator: ",")
            badgesSeeded = true
            return
        }
        let fresh = earned.filter { !seen.contains($0.id) }
        if celebration == nil, let newest = fresh.max(by: { $0.threshold < $1.threshold }) {
            celebration = .badgeUnlocked(title: newest.title, symbol: newest.icon)
        }
        seenBadgesRaw = earnedIds.union(seen).sorted().joined(separator: ",")
    }

    private var visitedGuideCount: Int {
        guides.filter { $0.scope == "country" && visitedCountries.contains($0.name) }.count
    }

    private var visitedStateGuideCount: Int {
        guides.filter { $0.scope == "state" && visitedStates.contains($0.name) }.count
    }

    private func orderedGuides(scope: String, visited: Set<String>) -> [RegionBeerGuide] {
        guides
            .filter { $0.scope == scope }
            .sorted { lhs, rhs in
                let lhsVisited = visited.contains(lhs.name)
                let rhsVisited = visited.contains(rhs.name)
                if lhsVisited != rhsVisited { return lhsVisited }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func shelfCard(_ guide: RegionBeerGuide, visited: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CountryFlag.symbol(for: guide.flag)).font(.title2)
                Spacer()
                Image(systemName: visited ? "seal.fill" : "lock.fill")
                    .foregroundStyle(visited ? Brand.gold : Brand.muted)
            }
            Text(guide.name)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
                .lineLimit(1)
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
