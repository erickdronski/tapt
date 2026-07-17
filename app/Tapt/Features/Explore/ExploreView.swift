import CoreLocation
import SwiftUI

/// The discovery home: beer spots near you, the beer "stock market", a global lens by
/// country, and live up/down voting. The screen a beer fan opens first.
struct ExploreView: View {
    @Environment(Session.self) private var session
    @AppStorage("homeRegion") private var homeRegion = "Global"
    @AppStorage("noLowDefault") private var noLowDefault = false
    @AppStorage("favoriteStyles") private var favoriteStyles = ""
    @AppStorage("locationConsent") private var locationConsent = false
    @AppStorage("homeRegionGeocoded") private var homeRegionGeocoded = false
    @State private var location = LocationManager()
    @State private var region = ""
    // The region the rows on screen actually belong to. When a picked region
    // has no data yet we fall back to the Global feed, and every label must
    // say Global, never relabel worldwide rows as "Top in <state>".
    @State private var dataRegion = "Global"
    // Only regions that actually have a board (loaded from beer_board_regions),
    // so the picker never offers a dead-end. Global always leads.
    @State private var regions: [String] = ["Global"]
    @State private var beers: [TrendedBeer] = []
    @State private var guides: [RegionBeerGuide] = []
    @State private var loading = false
    @State private var myVotes: [String: Int] = [:]
    @State private var appeared = false
    @State private var feedNote: String?
    @State private var voteError: String?
    @State private var celebration: TaptCelebration?
    @State private var recommendation: RecommendedBeer?
    @State private var ticker: [MarketBeer] = []
    @State private var tickerBeer: MarketBeer?

    private var visibleBeers: [TrendedBeer] {
        // No/Low uses the canonical server field, never substring matching.
        let base: [TrendedBeer] = noLowDefault
            ? beers.filter(\.isNaLow)
            : beers
        // The catalog has multiple SKUs per beer -- collapse to one row per name.
        var seen = Set<String>()
        return base.filter { seen.insert($0.name.lowercased()).inserted }
    }
    private var movers: [TrendedBeer] { visibleBeers.sorted { $0.momentum > $1.momentum } }
    private var top: [TrendedBeer] { visibleBeers.sorted { $0.popularity > $1.popularity } }
    private var favoriteStyleNames: [String] { TastePreferences.decode(favoriteStyles) }
    private var personalizedBeers: [TrendedBeer] {
        visibleBeers
            .filter {
                TastePreferences.matches(
                    style: $0.style,
                    isNaLow: $0.isNaLow,
                    selectedStyles: favoriteStyleNames
                )
            }
            .sorted {
                if $0.popularity != $1.popularity { return $0.popularity > $1.popularity }
                if $0.momentum != $1.momentum { return $0.momentum > $1.momentum }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
    private var hasMarketActivity: Bool {
        visibleBeers.contains { $0.popularity != 0 || $0.momentum != 0 }
    }
    private var heroBeer: TrendedBeer? { hasMarketActivity ? (movers.first ?? top.first) : nil }
    private var totalMomentum: Int { movers.prefix(8).map(\.momentum).reduce(0, +) }
    private var activeGuide: RegionBeerGuide? {
        guides.first { $0.name == region }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    exploreHeader.reveal(appeared, 0)
                    hero.reveal(appeared, 1)
                    scanTile.reveal(appeared, 2)
                    catalogBar.reveal(appeared, 3)
                    quickDuo.reveal(appeared, 4)
                    if let recommendation { PickedForYouCard(beer: recommendation).reveal(appeared, 5) }
                    if !personalizedBeers.isEmpty { tasteSection.reveal(appeared, 6) }
                    BeerOfWeekCard().padding(.horizontal).reveal(appeared, 7)
                    // State and country boards are off until we have real
                    // regional activity. The board is worldwide-only for now,
                    // so there is no region picker and nothing to relabel.
                    if loading && beers.isEmpty {
                        TaptSkeletonList(rows: 5)
                    } else {
                        if hasMarketActivity { moversSection.reveal(appeared, 8) }
                        topSection.reveal(appeared, 9)
                    }
                    FeaturedPartnersRail().reveal(appeared, 10)
                }
                .padding(.bottom)
            }
            .background(Brand.background)
            // The live tape is a fixed top bar, not a scrolling row. Its malt
            // band bleeds up through the status bar so it fully covers the top
            // of the phone -- no page content ever shows behind it.
            .safeAreaInset(edge: .top, spacing: 0) { marketTickerBar }
            .overlay(alignment: .bottom) { voteToast }
            .taptCelebration($celebration)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // Worldwide-only board for now: no state/country switching.
                region = "Global"
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true }
            }
            .task(id: region) { await load() }
            .task { await loadGuides() }
            .task { await hydrateTastePreferences() }
            .task { await detectHomeState() }
            .task(id: noLowDefault) { await loadTicker() }
            .task { await loadRecommendation() }
            .refreshable {
                await load()
                await loadTicker()
                await loadRecommendation()
            }
            .sheet(item: $tickerBeer) { b in
                NavigationStack { BeerDetailView(beerId: b.beerId) }
            }
        }
    }

    /// Bottom-anchored transient toast: vote failures were landing in the hero
    /// caption at the top of the scroll view, off-screen from where the user
    /// actually tapped. Auto-dismisses.
    @ViewBuilder private var voteToast: some View {
        if let message = voteError {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.text)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.copper.opacity(0.55)))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(message)
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.easeOut(duration: 0.25)) { voteError = nil }
                }
        }
    }

    private var heroPanel: some View {
        TaptHeroPanel(
            title: heroBeer?.name ?? "Your beer radar",
            subtitle: heroBeer.map { "\($0.brewery) is \($0.momentum >= 0 ? "climbing" : "sliding") \(dataRegion == "Global" ? "worldwide" : "in \(dataRegion)")." }
                ?? activeGuide.map { "\($0.name) leans \($0.heroStyle.lowercased()): \($0.flavorNotes.prefix(3).joined(separator: ", "))." }
                ?? "Browse real beers and cast the vote that starts the board.",
            metric: heroBeer.map { "\($0.momentum >= 0 ? "▲ +" : "▼ ")\(abs($0.momentum))" } ?? "EXPLORE",
            caption: feedNote ?? (heroBeer != nil ? "Tap to open · \(max(totalMomentum, 0)) market heat"
                                                   : (noLowDefault ? "No / Low lens on" : "Catalog ready · market awaiting votes")),
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
    }

    /// Screen title, now BELOW the live ticker tape (the ticker leads the page so
    /// the app opens on motion, not on empty large-title chrome).
    private var exploreHeader: some View {
        Text("Explore")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Brand.text)
            .padding(.horizontal)
            .padding(.top, 2)
    }

    /// Live beer ticker pinned at the top of the home page — beers trending up or
    /// down by community votes, like a market tape. Tap one to open the beer.
    @ViewBuilder private var marketTickerBar: some View {
        if !ticker.isEmpty {
            VStack(spacing: 0) {
                MarketTicker(items: ticker) { b in Haptic.tap(); tickerBeer = b }
                Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
            }
            // Solid malt band that bleeds up through the status bar, so the tape
            // covers the very top of the phone and nothing shows behind it.
            .background(Brand.malt.ignoresSafeArea(edges: .top))
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
                Text("Search beers, breweries, and styles").foregroundStyle(Brand.muted)
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
            duoTile("Leaderboards", "Top drinkers & styles, all-time", "trophy.fill", Brand.gold) { LeaderboardsView() }
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
                ForEach(regions, id: \.self) { r in
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

    /// True when the user picked a specific state or country that has no board of
    /// its own yet, so the rows on screen are the worldwide fallback.
    private var showRegionBoardBanner: Bool {
        region != "Global" && dataRegion == "Global" && dataRegion != region
    }

    /// The honest cold-start explainer for an empty regional board. It is the one
    /// place that carries the "no board yet" message (previously split across the
    /// hero caption, the movers header, and the trending subtitle), and it frames
    /// the emptiness as a be-first invitation: boards are built from real local
    /// pours and votes, which is exactly the behavior we want to prompt.
    private var regionBoardBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.title3.weight(.bold))
                .foregroundStyle(Brand.gold)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(region) doesn't have its own board yet")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Text("Its board grows as we add more of \(region)'s beer and the community votes. Meanwhile, here is what is moving worldwide.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.28)))
        .padding(.horizontal)
    }

    private var moversSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("On the come-up", dataRegion == "Global" ? "Biggest movers worldwide" : "Biggest movers in \(dataRegion)")
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

    private var tasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("For your taste", "Your favorite beer styles")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(personalizedBeers.prefix(10))) { beer in
                        NavigationLink { BeerDetailView(beerId: beer.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                BeerThumb(imageUrl: beer.imageUrl, size: 68, corner: 12, style: beer.style)
                                Text(beer.name)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Brand.text)
                                    .lineLimit(2)
                                Text(beer.style.isEmpty ? beer.brewery : beer.style)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Brand.muted)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(width: 146, height: 168, alignment: .topLeading)
                            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.gold.opacity(0.18)))
                        }
                        .buttonStyle(.taptPress)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func momentum(_ m: Int) -> some View {
        let up = m >= 0
        return Label("\(abs(m))", systemImage: up ? "arrow.up.right" : "arrow.down.right")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(up ? Brand.hop : Brand.copper)
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(
                hasMarketActivity
                    ? (dataRegion == "Global" ? "Trending worldwide" : "Trending in \(dataRegion)")
                    // Catalog-shelf rows are grouped by where the beer was
                    // recorded on shelves, so the honest verb is "found in".
                    : (dataRegion == "Global" ? "Explore worldwide beers" : "Beers found in \(dataRegion)"),
                // The "no board yet" message now lives in the banner above, so this
                // subtitle just describes the rows the user is actually looking at.
                hasMarketActivity ? "Tap to vote it up or down" : "Real catalog beers. Your vote can start the board."
            )
            if top.isEmpty && noLowDefault {
                Text("No No / Low catalog picks are available here yet. Turn off the lens in You to see the full catalog.")
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
                    BeerThumb(imageUrl: b.imageUrl, size: 44, corner: 10, style: b.style)
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
                    Text("Top drinkers, styles, and all-time beers").font(.caption).foregroundStyle(Brand.muted)
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
                dataRegion = "Global"
                // The regionBoardBanner now carries this message prominently, so we
                // leave the hero caption alone instead of duplicating it up top.
                feedNote = nil
            } else {
                beers = regional
                dataRegion = region
                feedNote = nil
            }
        } catch {
            feedNote = "Could not refresh. Pull to try again."
        }
    }

    /// Load the regions that have a live board so the picker only offers real
    /// destinations. Global always leads.
    private func loadBoardRegions() async {
        guard let fetched = try? await BeerService.boardRegions() else { return }
        regions = ["Global"] + fetched
    }

    /// One taste-matched beer the user hasn't had. Silent until there is real
    /// signal (the SQL returns nothing), so the card only shows when it can be
    /// genuinely personal.
    private func loadRecommendation() async {
        guard let uid = session.user?.id else { return }
        // Weekly-stable pick: the same beer all week (logged to the profile),
        // recomputed each new week from the user's latest taste. No more churn
        // on every open.
        recommendation = try? await RecommendationService.weeklyPick(userId: uid)
    }

    private func loadTicker() async {
        do {
            ticker = try await MarketService.feed(
                sort: .movers,
                limit: 18,
                naOnly: noLowDefault
            )
        } catch {
            // Keep the last good tape visible through a transient refresh failure.
        }
    }

    private func hydrateTastePreferences() async {
        guard let userId = session.user?.id else { return }
        guard let styles = try? await ProfileService.topStyles(userId: userId) else { return }
        favoriteStyles = TastePreferences.encode(styles)
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
        // Boards are country-level, so home defaults to the detected country and
        // only if that country actually has a board. US users get "United States",
        // never a state (states have no board of their own yet).
        var detected: String?
        if let country = mark.country {
            if regions.contains(country) {
                detected = country
            } else if let canonical = BeerRegions.canonicalCountry(country),
                      regions.contains(canonical) {
                detected = canonical
            }
        }
        if let detected {
            if let userId = session.user?.id {
                do {
                    try await ProfileService.setRegion(detected, userId: userId)
                } catch {
                    // Keep the visible board and server vote region aligned.
                    // A later appearance retries automatic detection.
                    return
                }
            }
            homeRegionGeocoded = true
            homeRegion = detected
            // Profile region is recorded for later, but the visible board stays
            // worldwide until state/country boards ship with real data.
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
        let previous = myVotes[b.id]
        let newValue = (previous == v) ? nil : v
        myVotes[b.id] = newValue
        guard let uid = session.user?.id else {
            myVotes[b.id] = previous
            showVoteError("Sign-in expired, vote not saved. Sign out and back in.")
            return
        }
        // Write the real change (vote, flip, or un-vote), then nudge just this
        // row's numbers. No full-feed refetch that reshuffles the list under
        // the user's thumb; errors surface in a visible toast, not the hero.
        let delta = (newValue ?? 0) - (previous ?? 0)
        Task {
            do {
                if let value = newValue {
                    try await BeerService.vote(beerId: b.id, userId: uid, value: value)
                } else {
                    try await BeerService.unvote(beerId: b.id, userId: uid)
                }
                await MainActor.run {
                    applyVoteDelta(b.id, delta)
                    // Only a real thumbs-up gets the count-up + confetti payoff.
                    // Flips and un-votes stay quiet.
                    if newValue == 1 {
                        let count = beers.first(where: { $0.id == b.id })?.popularity ?? b.popularity
                        celebration = .voteCounted(beer: b.name, count: count)
                    }
                }
            } catch {
                await MainActor.run {
                    myVotes[b.id] = previous
                    showVoteError("Vote didn't save: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reflect a saved vote in the one row it touched.
    private func applyVoteDelta(_ id: String, _ delta: Int) {
        guard delta != 0, let i = beers.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            beers[i].popularity += delta
            beers[i].momentum += delta
        }
    }

    private func showVoteError(_ message: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { voteError = message }
    }
}

private extension View {
    /// The home screen assembles top-to-bottom on appear: each child fades and
    /// rises in on a short stagger so the page pours itself onto the screen
    /// instead of popping in flat. `index` sets the child's place in the cascade.
    func reveal(_ appeared: Bool, _ index: Int) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.06),
                value: appeared
            )
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
