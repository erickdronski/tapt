import SwiftUI

/// Cellar: your growing beer collection. A visual shelf of every distinct beer
/// you have poured, a world-progress strip, earned milestones, and the full
/// pour history. Built to feel like a passport that grows with you.
struct CellarView: View {
    @Environment(Session.self) private var session
    @AppStorage("beerGeekMode") private var beerGeekMode = false
    @State private var checkins: [MyCheckin] = []
    @State private var guides: [RegionBeerGuide] = []
    @State private var showLog = false
    @State private var appeared = false
    @State private var countsRolled = false
    @State private var loading = false
    @State private var loadError: String?

    private var logVerb: String { beerGeekMode ? "Tick a pour" : "Log a pour" }
    private var collectionWord: String { beerGeekMode ? "Cellar" : "Collection" }

    private var styleCount: Int {
        Set(checkins.compactMap { c in
            let s = c.displayStyle ?? c.style
            return (s?.isEmpty == false) ? s : nil
        }).count
    }
    private var uniqueBeerCount: Int { PassportProgress.uniqueBeerCount(in: checkins) }
    private var visitedCountries: Set<String> {
        Set(checkins.map(\.passportCountry).filter { !$0.isEmpty })
    }
    private var visitedStates: Set<String> {
        Set(checkins.filter { $0.passportCountry == "United States" }.map(\.venueRegion).filter { !$0.isEmpty })
    }
    private var countryCount: Int { visitedCountries.count }
    private var stateCount: Int { visitedStates.count }

    /// One card per distinct beer, most recent pour first, image-bearing beers
    /// leading so the shelf reads as a real collection.
    private var collection: [CollectionBeer] {
        var seen = Set<String>()
        var out: [CollectionBeer] = []
        for c in checkins {
            let key = PassportProgress.collectionKey(c)
            guard seen.insert(key).inserted, let beerId = c.beerId else { continue }
            out.append(CollectionBeer(
                id: beerId,
                name: c.beerName,
                brewery: c.breweryName,
                style: c.displayStyle,
                imageUrl: c.imageUrl,
                rating: c.rating
            ))
        }
        // Imaged first, then by recency (already time-desc from the query).
        return out.sorted { ($0.imageUrl != nil ? 0 : 1) < ($1.imageUrl != nil ? 0 : 1) }
    }

    private var stats: PassportStats {
        PassportStats.from(checkins: checkins, beers: uniqueBeerCount,
                           styles: styleCount, states: stateCount, countries: countryCount)
    }
    private var earnedBadges: [Badge] { PassportData.badges.filter { $0.earned(stats) } }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                if session.user == nil { guestEmpty }
                else if loading && checkins.isEmpty { TaptSkeletonList(rows: 5).padding() }
                else if let loadError, checkins.isEmpty { errorState(loadError) }
                else if checkins.isEmpty { empty }
                else { content }
            }
            .navigationTitle("Passport")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if session.user != nil {
                        Button { showLog = true } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Brand.gold)
                        }
                    }
                }
            }
            .task { await load() }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true }
            }
            .sheet(isPresented: $showLog) {
                LogPourView(onLogged: { Task { await load() } })
            }
        }
    }

    private var guestEmpty: some View {
        TaptEmptyState(
            icon: "square.stack.3d.up.fill",
            title: "Make this Cellar yours",
            message: "Sign in to log pours, collect Passport stamps, save private notes, and carry your taste profile across devices.",
            actionTitle: "Sign in to start",
            action: { session.endGuestSession() }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private var empty: some View {
        TaptEmptyState(
            icon: "square.stack.3d.up.fill",
            title: "Your Cellar is thirsty",
            message: "Log your first pour to start your collection, unlock Passport stamps, and build your beer taste graph.",
            actionTitle: logVerb,
            action: { showLog = true }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private func errorState(_ message: String) -> some View {
        TaptEmptyState(
            icon: "wifi.exclamationmark",
            title: "Cellar unavailable",
            message: message,
            actionTitle: "Try again",
            action: { Task { await load() } }
        )
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaptHeroPanel(
                    title: "Passport progress",
                    subtitle: "\(uniqueBeerCount) distinct \(pl(uniqueBeerCount, "beer", "beers")) across \(styleCount) \(pl(styleCount, "style", "styles")), \(stateCount) \(pl(stateCount, "state", "states")), and \(countryCount) \(pl(countryCount, "country", "countries")).",
                    metric: "\(uniqueBeerCount)",
                    caption: nextMilestone,
                    icon: "seal.fill",
                    tint: Brand.hop
                )
                .padding(.horizontal)

                statGrid
                worldStrip
                trophyShelf
                collectionShelf
                regionalShelves
                pourHistory
                Text("Tapt celebrates variety and discovery, not volume. Please drink responsibly.")
                    .font(.caption2).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8).padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private var statGrid: some View {
        // The numbers spin up from zero the moment the Cellar lands
        // (contentTransition(.numericText) only plays when the value changes).
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat(countsRolled ? "\(checkins.count)" : "0", "pours", "drop.fill", Brand.gold)
            stat(countsRolled ? "\(styleCount)" : "0", "styles", "square.grid.2x2.fill", Brand.hop)
            stat(countsRolled ? "\(stateCount)" : "0", "states", "map.fill", Brand.copper)
            stat(countsRolled ? "\(countryCount)" : "0", "countries", "globe", Brand.copper)
        }
        .padding(.horizontal)
    }

    /// Grammatical singular/plural so the passport never reads "1 countries".
    private func pl(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

    private func stat(_ n: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(n).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.22), lineWidth: 1))
        .contentTransition(.numericText())
    }

    /// The world you have tasted: visited flags glow, the rest of the beer
    /// world stays dim. It grows as you travel. Honest to real venue/brewery
    /// countries only, never fabricated.
    private var worldStrip: some View {
        let visited = visitedCountries
        let ordered = PassportData.countries.sorted { a, b in
            let av = visited.contains(a.name), bv = visited.contains(b.name)
            if av != bv { return av }   // visited first
            return false
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your beer world").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Spacer()
                Text("\(countryCount) of \(PassportData.countries.count)")
                    .font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(ordered.enumerated()), id: \.element.name) { i, c in
                        let on = visited.contains(c.name)
                        countryStamp(c, visited: on, index: i)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// A visited country renders as an inked passport stamp: double ring,
    /// dashed seal, a slight hand-pressed rotation that is deterministic per
    /// country (stable across launches, no randomness). Unvisited countries
    /// are faint outlines waiting for ink. Only real pours stamp a page.
    private func countryStamp(_ c: (name: String, flag: String), visited on: Bool, index: Int) -> some View {
        let tilt = Double((index * 7) % 11) - 5.0   // -5..+5 degrees, stable
        return VStack(spacing: 3) {
            Text(c.flag).font(.title3)
                .grayscale(on ? 0 : 1).opacity(on ? 1 : 0.4)
            Text(c.name.uppercased())
                .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(on ? Brand.copper : Brand.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if on {
                Text("TAPT")
                    .font(.system(size: 5.5, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Brand.copper.opacity(0.85))
            }
        }
        .padding(.horizontal, 5)
        .frame(width: 64, height: 60)
        .background(on ? Brand.copper.opacity(0.07) : Brand.surface, in: Circle())
        .overlay {
            if on {
                Circle().stroke(Brand.copper.opacity(0.75), lineWidth: 1.6)
                Circle().inset(by: 3.5)
                    .stroke(Brand.copper.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
            } else {
                Circle().stroke(Brand.malt.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .rotationEffect(.degrees(on ? tilt : 0))
        .padding(.vertical, 3)
    }

    private func currentValue(for metric: BadgeMetric) -> Int { stats.value(for: metric) }

    /// A trophy case, not a highlight reel: EVERY badge shows, so a new user
    /// sees the full shelf to fill. Earned ones shine gold; locked ones stay
    /// dim with an honest progress bar toward the threshold.
    private var trophyShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trophy shelf").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Spacer()
                Text("\(earnedBadges.count) of \(PassportData.badges.count)")
                    .font(.caption.weight(.bold)).foregroundStyle(Brand.gold)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PassportData.badges) { b in trophy(b) }
                }
                .padding(.horizontal)
            }
        }
    }

    private func trophy(_ b: Badge) -> some View {
        BadgeSticker(badge: b, stats: stats, size: 72)
            .frame(width: 96)
    }

    /// The visual heart of the Cellar: a shelf of every distinct beer poured,
    /// real label/cutout imagery, most collectible first.
    private var collectionShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your \(collectionWord.lowercased())").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Spacer()
                Text("\(collection.count) beers").font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
            }
            .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(collection.prefix(24)) { beer in
                    NavigationLink { BeerDetailView(beerId: beer.id) } label: { collectionCard(beer) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func collectionCard(_ beer: CollectionBeer) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                BeerThumb(imageUrl: beer.imageUrl, size: 96, corner: 14)
                if let r = beer.rating {
                    HStack(spacing: 1) {
                        Image(systemName: "star.fill").font(.system(size: 8))
                        Text(String(format: "%.0f", r)).font(.system(size: 10, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Brand.gold, in: Capsule())
                    .padding(5)
                }
            }
            Text(beer.name).font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text).lineLimit(1).minimumScaleFactor(0.8)
            Text(beer.style ?? beer.brewery).font(.system(size: 9))
                .foregroundStyle(Brand.muted).lineLimit(1)
        }
    }

    private var pourHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pour history").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Spacer()
                NavigationLink { PassportView(checkins: checkins, guides: guides) } label: {
                    HStack(spacing: 3) {
                        Text("Passport").font(.caption.weight(.bold))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Brand.copper)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            VStack(spacing: 10) {
                ForEach(checkins.prefix(40)) { row($0) }
            }
            .padding(.horizontal)
            if checkins.count > 40 {
                Text("Showing your 40 most recent pours.")
                    .font(.caption).foregroundStyle(Brand.muted)
                    .frame(maxWidth: .infinity).padding(.top, 2)
            }
        }
    }

    private var regionalShelves: some View {
        let unlockedGuides = guides.filter { guide in
            if guide.scope == "state" { return visitedStates.contains(guide.name) }
            if guide.scope == "country" { return visitedCountries.contains(guide.name) }
            return false
        }
        let suggestions = guides.filter { guide in
            guard !unlockedGuides.contains(guide) else { return false }
            if guide.scope == "state" { return guide.country == "United States" }
            return guide.scope == "country"
        }.prefix(5)
        let shelves = unlockedGuides + Array(suggestions)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Regional shelves")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelves.prefix(8)) { guide in
                        let unlocked = unlockedGuides.contains(guide)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(CountryFlag.symbol(for: guide.flag)).font(.title2)
                                Spacer()
                                Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                                    .foregroundStyle(unlocked ? Brand.hop : Brand.muted)
                            }
                            Text(guide.name)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(guide.scope == "state" ? "State shelf" : "World shelf")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(unlocked ? Brand.copper : Brand.muted)
                            Text(unlocked ? guide.passportPhrase : guide.cellarPrompt)
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                                .lineLimit(3)
                            Spacer(minLength: 0)
                            Text(guide.heroStyle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Brand.malt)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background((unlocked ? Brand.gold : Brand.haze).opacity(unlocked ? 1 : 0.65), in: Capsule())
                        }
                        .padding(14)
                        .frame(width: 184, height: 178, alignment: .leading)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke((unlocked ? Brand.gold : Brand.malt).opacity(0.18)))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func row(_ c: MyCheckin) -> some View {
        let content = HStack(spacing: 12) {
            BeerThumb(imageUrl: c.imageUrl, size: 44, corner: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.beerName).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text([c.breweryName, c.displayStyle ?? ""].filter { !$0.isEmpty }.joined(separator: "  ")).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                if !c.venueName.isEmpty {
                    Text([c.venueName, c.placeSubtitle].filter { !$0.isEmpty }.joined(separator: " - "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Brand.copper)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let r = c.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Brand.gold)
                    Text(String(format: "%.0f", r)).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                }
            }
        }
        .padding(12).background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))

        return Group {
            if let beerId = c.beerId {
                NavigationLink { BeerDetailView(beerId: beerId) } label: { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var nextMilestone: String {
        if uniqueBeerCount < 5 { let n = 5 - uniqueBeerCount; return "\(n) \(pl(n, "beer", "beers")) to first flight" }
        if styleCount < 5 { let n = 5 - styleCount; return "\(n) \(pl(n, "style", "styles")) to Style Explorer" }
        if stateCount < 5 { let n = 5 - stateCount; return "\(n) \(pl(n, "state", "states")) to Tap Trail" }
        if countryCount < 3 { let n = 3 - countryCount; return "\(n) \(pl(n, "country", "countries")) to Border Hopper" }
        if uniqueBeerCount < 120 { let n = 120 - uniqueBeerCount; return "\(n) \(pl(n, "beer", "beers")) to Palate of Legend" }
        return "Palate of Legend reached. Keep exploring."
    }

    private func load() async {
        guard let uid = session.user?.id else { return }
        loading = true
        defer { loading = false }
        do {
            checkins = try await CheckinService.mine(userId: uid)
            loadError = nil
        } catch {
            loadError = "Your pours could not be loaded. Check your connection and try again."
        }
        guides = (try? await WorldBeerService.regionGuides()) ?? []
        // Spin the stat numbers up from zero once the real data is in.
        if !countsRolled {
            withAnimation(.easeOut(duration: 0.6)) { countsRolled = true }
        }
    }
}

/// One distinct beer on the collection shelf.
private struct CollectionBeer: Identifiable {
    let id: String
    let name: String
    let brewery: String
    let style: String?
    let imageUrl: String?
    let rating: Double?
}

/// Applies the gold Shimmer sweep only when a trophy is earned.
private struct ShimmerIf: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View {
        if on { content.modifier(Shimmer()) } else { content }
    }
}
