import SwiftUI

/// Global leaderboards, beers, tasters, styles. Every number is first-party
/// (votes + logged pours). Boards stay honestly empty until the community moves.
struct LeaderboardsView: View {
    @State private var board = Board.beers
    @State private var beers: [LeaderBeer] = []
    @State private var tasters: [LeaderTaster] = []
    @State private var styles: [LeaderStyle] = []
    @State private var loading = false
    @AppStorage("noLowDefault") private var naOnly = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TaptHeroPanel(
                    title: "Leaderboards",
                    subtitle: "Votes and pours from real Tapt drinkers move every board. No bots, no paid placement.",
                    metric: "LIVE",
                    caption: "Powered by the community",
                    icon: "trophy.fill",
                    tint: Brand.gold
                )
                .padding(.horizontal)

                boardPicker

                if loading && beers.isEmpty && tasters.isEmpty && styles.isEmpty {
                    TaptSkeletonList(rows: 6)
                } else {
                    switch board {
                    case .beers: beersBoard
                    case .tasters: tastersBoard
                    case .styles: stylesBoard
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var boardPicker: some View {
        HStack(spacing: 8) {
            ForEach(Board.allCases) { b in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { board = b }
                } label: {
                    Label(b.title, systemImage: b.icon)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(board == b ? b.tint : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(board == b ? Brand.malt : Brand.text)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(b.tint.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var beersBoard: some View {
        VStack(spacing: 10) {
            Button {
                naOnly.toggle()
                Task { beers = (try? await LeaderboardService.beers(naOnly: naOnly)) ?? [] }
            } label: {
                Label(naOnly ? "No / Low only, showing zero-proof podium" : "Show No / Low board",
                      systemImage: naOnly ? "checkmark.circle.fill" : "sparkle.magnifyingglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(naOnly ? Brand.malt : Brand.hop)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(naOnly ? Brand.hop : Brand.hop.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if beers.isEmpty {
                TaptEmptyState(
                    icon: "trophy.fill",
                    title: naOnly ? "The zero-proof podium is open" : "The podium is open",
                    message: naOnly
                        ? "No / Low beers count just as much here. Vote one up to start the board."
                        : "Vote beers up or down on Explore and log pours, the first movers write the leaderboard.",
                    actionTitle: nil
                )
            } else {
                ForEach(Array(beers.enumerated()), id: \.element.id) { i, beer in
                    NavigationLink { BeerDetailView(beerId: beer.beerId) } label: {
                        HStack(spacing: 12) {
                            rankBadge(i + 1)
                            BeerThumb(imageUrl: beer.imageUrl, size: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(beer.name)
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Brand.text).lineLimit(1)
                                Text([beer.breweryName, beer.style, beer.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  "))
                                    .font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                HStack(spacing: 6) {
                                    Label("\(beer.ups)", systemImage: "hand.thumbsup.fill")
                                        .font(.caption.weight(.bold)).foregroundStyle(Brand.hop)
                                    Label("\(beer.downs)", systemImage: "hand.thumbsdown.fill")
                                        .font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
                                }
                                if beer.checkinCount > 0 {
                                    Text("\(beer.checkinCount) pours")
                                        .font(.caption2.weight(.semibold)).foregroundStyle(Brand.muted)
                                }
                            }
                        }
                        .padding(13)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.gold.opacity(i == 0 ? 0.5 : 0.12)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 0)
            }
        }
        .padding(.horizontal)
    }

    private var tastersBoard: some View {
        VStack(spacing: 10) {
            if tasters.isEmpty {
                TaptEmptyState(
                    icon: "person.3.fill",
                    title: "No tasters ranked yet",
                    message: "Log pours to claim the top spot. Styles and countries count more than volume.",
                    actionTitle: nil
                )
            } else {
                ForEach(Array(tasters.enumerated()), id: \.element.id) { i, taster in
                    HStack(spacing: 12) {
                        rankBadge(i + 1)
                        Text(String(taster.displayName.first ?? "T").uppercased())
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Brand.malt)
                            .frame(width: 40, height: 40)
                            .background(Brand.gold, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(taster.displayName)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text).lineLimit(1)
                            Text("\(taster.styles) styles · \(taster.countries) countries")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(taster.pours)")
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(Brand.hop)
                            Text("pours").font(.caption2).foregroundStyle(Brand.muted)
                        }
                    }
                    .padding(13)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.hop.opacity(i == 0 ? 0.5 : 0.12)))
                }
            }
        }
        .padding(.horizontal)
    }

    private var stylesBoard: some View {
        VStack(spacing: 10) {
            if styles.isEmpty {
                TaptEmptyState(
                    icon: "square.grid.2x2.fill",
                    title: "No style trends yet",
                    message: "The most-poured styles show up here as people log pours.",
                    actionTitle: nil
                )
            } else {
                ForEach(Array(styles.enumerated()), id: \.element.id) { i, style in
                    HStack(spacing: 12) {
                        rankBadge(i + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.style)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text).lineLimit(1)
                            if let avg = style.avgRating {
                                Text("Average rating \(String(format: "%.1f", avg))")
                                    .font(.caption).foregroundStyle(Brand.muted)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(style.pours)")
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(Brand.copper)
                            Text("pours").font(.caption2).foregroundStyle(Brand.muted)
                        }
                    }
                    .padding(13)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.copper.opacity(i == 0 ? 0.5 : 0.12)))
                }
            }
        }
        .padding(.horizontal)
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(.subheadline, design: .monospaced).weight(.heavy))
            .foregroundStyle(rank <= 3 ? Brand.malt : Brand.muted)
            .frame(width: 30, height: 30)
            .background(rank <= 3 ? Brand.gold : Brand.background, in: Circle())
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let b: [LeaderBeer] = (try? LeaderboardService.beers(naOnly: naOnly)) ?? []
        async let t: [LeaderTaster] = (try? LeaderboardService.tasters()) ?? []
        async let s: [LeaderStyle] = (try? LeaderboardService.styles()) ?? []
        beers = await b
        tasters = await t
        styles = await s
    }
}

private enum Board: String, CaseIterable, Identifiable {
    case beers, tasters, styles
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beers: "Beers"
        case .tasters: "Tasters"
        case .styles: "Styles"
        }
    }
    var icon: String {
        switch self {
        case .beers: "trophy.fill"
        case .tasters: "person.3.fill"
        case .styles: "square.grid.2x2.fill"
        }
    }
    var tint: Color {
        switch self {
        case .beers: Brand.gold
        case .tasters: Brand.hop
        case .styles: Brand.copper
        }
    }
}
