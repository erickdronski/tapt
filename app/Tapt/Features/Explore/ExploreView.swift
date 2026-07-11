import CoreLocation
import SwiftUI

/// The discovery home: beer spots near you, the beer "stock market", a global lens by
/// country, and live up/down voting. The screen a beer fan opens first.
struct ExploreView: View {
    @Environment(Session.self) private var session
    @AppStorage("homeRegion") private var homeRegion = "New Jersey"
    @AppStorage("noLowDefault") private var noLowDefault = false
    @AppStorage("locationConsent") private var locationConsent = true
    @AppStorage("homeRegionGeocoded") private var homeRegionGeocoded = false
    @State private var location = LocationManager()
    @State private var region = ""
    @State private var beers: [TrendedBeer] = []
    @State private var guides: [RegionBeerGuide] = []
    @State private var loading = false
    @State private var myVotes: [String: Int] = [:]
    @State private var appeared = false
    @State private var feedNote: String?
    @State private var ticker: [MarketBeer] = []
    @State private var tickerBeer: MarketBeer?

    private var visibleBeers: [TrendedBeer] {
        let base: [TrendedBeer] = noLowDefault
            ? beers.filter { beer in
                beer.style.localizedCaseInsensitiveContains("low")
                || beer.style.localizedCaseInsensitiveContains("non")
                || beer.name.localizedCaseInsensitiveContains("low")
                || beer.name.localizedCaseInsensitiveContains("non")
            }
            : beers
        // The catalog has multiple SKUs per beer -- collapse to one row per name.
        var seen = Set<String>()
        return base.filter { seen.insert($0.name.lowercased()).inserted }
    }
    private var movers: [TrendedBeer] { visibleBeers.sorted { $0.momentum > $1.momentum } }
    private var top: [TrendedBeer] { visibleBeers.sorted { $0.popularity > $1.popularity } }
    private var heroBeer: TrendedBeer? { movers.first ?? top.first }
    private var totalMomentum: Int { movers.prefix(8).map(\.momentum).reduce(0, +) }
    private var activeGuide: RegionBeerGuide? {
        guides.first { $0.name == region }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    marketTickerBar
                    hero
                    scanTile
                    catalogBar
                    quickDuo
                    BeerOfWeekCard().padding(.horizontal)
                    // The thin regional "beer guide" was wasted space; a real local-scene
                    // module returns with the venue/local-data ingestion.
                    regionPicker
                    if loading && beers.isEmpty {
                        TaptSkeletonList(rows: 5)
                    } else {
                        moversSection
                        topSection
                    }
                    FeaturedPartnersRail()
                }
                .padding(.vertical)
            }
            .background(Brand.background)
            .navigationTitle("Explore")
            .onAppear {
                if region.isEmpty { region = homeRegion }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true }
            }
            .task(id: region) { await load() }
            .task { await loadGuides() }
            .task { await detectHomeState() }
            .task { ticker = (try? await MarketService.feed(sort: .active, limit: 18)) ?? [] }
            .sheet(item: $tickerBeer) { b in
                NavigationStack { BeerDetailView(beerId: b.beerId) }
            }
        }
    }

    private var heroPanel: some View {
        TaptHeroPanel(
            title: heroBeer?.name ?? "Your beer radar",
            subtitle: heroBeer.map { "\($0.brewery) is \($0.momentum >= 0 ? "climbing" : "sliding") in \(region.isEmpty ? homeRegion : region)." }
                ?? activeGuide.map { "\($0.name) leans \($0.heroStyle.lowercased()): \($0.flavorNotes.prefix(3).joined(separator: ", "))." }
                ?? "Track what is hot and scan new pours.",
            metric: heroBeer.map { "\($0.momentum >= 0 ? "▲ +" : "▼ ")\(abs($0.momentum))" } ?? "LIVE",
            caption: feedNote ?? (heroBeer != nil ? "Tap to open · \(max(totalMomentum, 0)) market heat"
                                                   : (noLowDefault ? "No / Low lens on" : "\(max(totalMomentum, 0)) market heat")),
            icon: "chart.line.uptrend.xyaxis"
        )
    }

    @ViewBuilder private var hero: some View {
        Group {
            if let heroBeer {
                NavigationLink { BeerDetailView(beerId: heroBeer.id) } label: { heroPanel }
                    .buttonStyle(.plain)
            } else {
                heroPanel
            }
        }
        .padding(.horizontal)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
    }

    /// Live beer ticker pinned at the top of the home page — beers trending up or
    /// down by community votes, like a market tape. Tap one to open the beer.
    @ViewBuilder private var marketTickerBar: some View {
        if !ticker.isEmpty {
            VStack(spacing: 0) {
                MarketTicker(items: ticker) { b in Haptic.tap(); tickerBeer = b }
                    .background(Brand.malt)
                Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
            }
        }
    }

    /// Scan lives on the home page now (it left the tab dock).
    private var scanTile: some View {
        NavigationLink { ScanView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder").font(.headline).foregroundStyle(Brand.malt)
                    .frame(width: 44, height: 44).background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Scan a beer").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("Barcode, label, or a bar QR").font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(13)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.malt.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// Entry to the full searchable catalog, styled like a search field.
    private var catalogBar: some View {
        NavigationLink { CatalogView() } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Brand.muted)
                Text("Search every beer, brewery, style").foregroundStyle(Brand.muted)
                Spacer(minLength: 0)
                Image(systemName: "books.vertical.fill").foregroundStyle(Brand.gold)
            }
            .font(.subheadline)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// First-glance duo: Leaderboards + the map, side by side under the hero.
    private var quickDuo: some View {
        HStack(spacing: 12) {
            duoTile("Leaderboards", "Beers · tasters · styles", "trophy.fill", Brand.gold) { LeaderboardsView() }
            duoTile("Beer near you", "Breweries, pubs & bars", "map.fill", Brand.hop) { NearYouView() }
        }
        .padding(.horizontal)
    }

    private func duoTile<D: View>(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Brand.malt)
                    .frame(width: 40, height: 40)
                    .background(tint, in: RoundedRectangle(cornerRadius: 11))
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.25)))
        }
        .buttonStyle(.taptPress)
    }

    private func guideCard(_ guide: RegionBeerGuide) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(displayFlag(guide))
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(guide.name) beer guide")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text(guide.heroStyle)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
            }

            Text(guide.cellarPrompt)
                .font(.subheadline)
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)

            FlowTags(items: guide.topStyles + Array(guide.flavorNotes.prefix(3)), tint: Brand.gold)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.22)))
        .padding(.horizontal)
    }

    private var regionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BeerRegions.all, id: \.self) { r in
                    Button { region = r } label: {
                        Text(r).font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(region == r ? Brand.gold : Brand.surface, in: Capsule())
                            .foregroundStyle(region == r ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.malt.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var moversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("On the come-up", "Biggest movers in \(region)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(movers.prefix(10))) { ticker($0) }
                }
                .padding(.horizontal)
            }
        }
    }

    private func ticker(_ b: TrendedBeer) -> some View {
        NavigationLink { BeerDetailView(beerId: b.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(b.name).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).lineLimit(1)
                Text(b.brewery).font(.caption2).foregroundStyle(Brand.muted).lineLimit(1)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(b.popularity)").font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    momentum(b.momentum)
                }
            }
            .padding(12).frame(width: 152, height: 110, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.1)))
            .scaleEffect(myVotes[b.id] == 1 ? 1.03 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: myVotes[b.id])
        }
        .buttonStyle(.plain)
    }

    private func momentum(_ m: Int) -> some View {
        let up = m >= 0
        return Label("\(abs(m))", systemImage: up ? "arrow.up.right" : "arrow.down.right")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(up ? Brand.hop : Brand.copper)
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(region == "Global" ? "Trending worldwide" : "Top in \(region)", "Tap to vote it up or down")
            if top.isEmpty && noLowDefault {
                Text("No No / Low picks are trending here yet. Turn off the lens in You to see the full board.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(top.prefix(15).enumerated()), id: \.element.id) { i, b in row(i + 1, b) }
                }
                .padding(.horizontal)
            }
        }
    }

    private func row(_ rank: Int, _ b: TrendedBeer) -> some View {
        HStack(spacing: 12) {
            NavigationLink { BeerDetailView(beerId: b.id) } label: {
                HStack(spacing: 12) {
                    Text("\(rank)").font(.system(.headline, design: .monospaced)).foregroundStyle(Brand.muted).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                        Text(rowSubtitle(b)).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 6) {
                voteButton(b, 1, "hand.thumbsup.fill", Brand.hop)
                voteButton(b, -1, "hand.thumbsdown.fill", Brand.copper)
            }
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(myVotes[b.id] == 1 ? Brand.hop.opacity(0.6) : Brand.malt.opacity(0.08)))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: myVotes[b.id])
    }

    private func voteButton(_ b: TrendedBeer, _ v: Int, _ icon: String, _ color: Color) -> some View {
        let active = myVotes[b.id] == v
        return Button { vote(b, v) } label: {
            Image(systemName: icon).font(.subheadline)
                .foregroundStyle(active ? Brand.malt : color)
                .frame(width: 34, height: 34)
                .background(active ? color : Brand.background, in: Circle())
                .overlay(Circle().stroke(color.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    private var leaderboardLink: some View {
        NavigationLink { LeaderboardsView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill").foregroundStyle(Brand.malt)
                    .frame(width: 42, height: 42).background(Brand.gold, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leaderboards").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("Top beers, tasters, and styles, all first-party signal").font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(14).background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).padding(.horizontal)
    }

    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(s).font(.caption).foregroundStyle(Brand.muted)
        }
        .padding(.horizontal)
    }

    private func displayFlag(_ guide: RegionBeerGuide) -> String {
        switch guide.flag {
        case "AT": return "🇦🇹"
        case "AU": return "🇦🇺"
        case "US": return "🇺🇸"
        case "BE": return "🇧🇪"
        case "BR": return "🇧🇷"
        case "CA": return "🇨🇦"
        case "CZ": return "🇨🇿"
        case "DK": return "🇩🇰"
        case "DE": return "🇩🇪"
        case "ES": return "🇪🇸"
        case "FR": return "🇫🇷"
        case "GB": return "🇬🇧"
        case "IE": return "🇮🇪"
        case "IT": return "🇮🇹"
        case "JP": return "🇯🇵"
        case "KR": return "🇰🇷"
        case "MX": return "🇲🇽"
        case "NL": return "🇳🇱"
        case "PL": return "🇵🇱"
        default: return "🍺"
        }
    }

    /// Build a clean subtitle from whatever we actually have (no empty gaps or stray
    /// beer-emoji flags, e.g. Holsten with no brewery/country).
    private func rowSubtitle(_ b: TrendedBeer) -> String {
        let f = flag(b.country)
        let parts = [b.brewery, b.style].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = parts.joined(separator: " · ")
        if text.isEmpty && f.isEmpty { return "Community pick" }
        if text.isEmpty { return f }
        return f.isEmpty ? text : "\(text)  \(f)"
    }

    private func flag(_ country: String) -> String {
        if country.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return [
            "Australia": "🇦🇺", "Austria": "🇦🇹", "Belgium": "🇧🇪", "Brazil": "🇧🇷",
            "Canada": "🇨🇦", "Czechia": "🇨🇿", "Denmark": "🇩🇰", "France": "🇫🇷",
            "Germany": "🇩🇪", "Ireland": "🇮🇪", "Italy": "🇮🇹", "Japan": "🇯🇵",
            "Mexico": "🇲🇽", "Netherlands": "🇳🇱", "Poland": "🇵🇱",
            "South Korea": "🇰🇷", "Spain": "🇪🇸", "United Kingdom": "🇬🇧",
            "United States": "🇺🇸"
        ][country] ?? "🍺"
    }

    private func load() async {
        guard !region.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let regional = try await BeerService.trends(region: region)
            if regional.isEmpty && region != "Global" {
                beers = try await BeerService.trends(region: "Global")
                feedNote = "\(region) guide + Global radar"
            } else {
                beers = regional
                feedNote = nil
            }
        } catch {
            beers = []
            feedNote = "Guide mode"
        }
    }

    /// One-time: once location permission exists, default the dashboard to the
    /// user's actual state (US) or country. Never overrides a manual pick again.
    private func detectHomeState() async {
        guard locationConsent, !homeRegionGeocoded else { return }
        location.request()
        for _ in 0..<12 where location.location == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let loc = location.location,
              let mark = try? await CLGeocoder().reverseGeocodeLocation(loc).first
        else { return }
        var detected: String?
        if mark.isoCountryCode == "US", let area = mark.administrativeArea {
            detected = BeerRegions.states.first { $0 == area }
                ?? guides.first { $0.scope == "state" && $0.stateCode == area }?.name
        } else if let country = mark.country, BeerRegions.countries.contains(country) {
            detected = country
        }
        if let detected {
            homeRegionGeocoded = true
            homeRegion = detected
            withAnimation { region = detected }
        }
    }

    private func loadGuides() async {
        do {
            guides = try await WorldBeerService.regionGuides()
        } catch {
            guides = []
        }
    }

    private func vote(_ b: TrendedBeer, _ v: Int) {
        Haptic.tap()
        let newValue = (myVotes[b.id] == v) ? nil : v
        myVotes[b.id] = newValue
        guard let uid = session.user?.id else {
            feedNote = "Sign-in expired, vote not saved. Sign out and back in."
            myVotes[b.id] = nil
            return
        }
        guard let value = newValue else { return }
        Task {
            do {
                try await BeerService.vote(beerId: b.id, userId: uid, value: value)
                await load()   // pull the recomputed market so the vote visibly counts
            } catch {
                await MainActor.run {
                    myVotes[b.id] = nil
                    feedNote = "Vote didn't save: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct FlowTags: View {
    let items: [String]
    let tint: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 7)], alignment: .leading, spacing: 7) {
            ForEach(Array(items.prefix(6)), id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.malt)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(tint.opacity(0.22), in: Capsule())
            }
        }
    }
}
