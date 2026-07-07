import SwiftUI

/// The discovery home: breweries near you, the beer "stock market", a global lens by
/// country, and live up/down voting. The screen a beer fan opens first.
struct ExploreView: View {
    @Environment(Session.self) private var session
    @State private var region = "New Jersey"
    @State private var beers: [TrendedBeer] = []
    @State private var loading = false
    @State private var myVotes: [String: Int] = [:]

    private var movers: [TrendedBeer] { beers.sorted { $0.momentum > $1.momentum } }
    private var top: [TrendedBeer] { beers.sorted { $0.popularity > $1.popularity } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    mapLink
                    regionPicker
                    moversSection
                    topSection
                }
                .padding(.vertical)
            }
            .background(Brand.background)
            .navigationTitle("Explore")
            .task(id: region) { await load() }
            .overlay { if loading && beers.isEmpty { ProgressView().tint(Brand.gold) } }
        }
    }

    private var mapLink: some View {
        NavigationLink { NearYouView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill").foregroundStyle(Brand.malt)
                    .frame(width: 42, height: 42).background(Brand.gold, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Breweries near you").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("See what is good on tap around you").font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(14).background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).padding(.horizontal)
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
            VStack(spacing: 10) {
                ForEach(Array(top.prefix(15).enumerated()), id: \.element.id) { i, b in row(i + 1, b) }
            }
            .padding(.horizontal)
        }
    }

    private func row(_ rank: Int, _ b: TrendedBeer) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)").font(.system(.headline, design: .monospaced)).foregroundStyle(Brand.muted).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text("\(b.brewery)  \(flag(b.country))  \(b.style)").font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                voteButton(b, 1, "hand.thumbsup.fill", Brand.hop)
                voteButton(b, -1, "hand.thumbsdown.fill", Brand.copper)
            }
        }
        .padding(12).background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
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

    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(s).font(.caption).foregroundStyle(Brand.muted)
        }
        .padding(.horizontal)
    }

    private func flag(_ country: String) -> String {
        ["United States": "🇺🇸", "Germany": "🇩🇪", "Poland": "🇵🇱", "Czechia": "🇨🇿",
         "Belgium": "🇧🇪", "Ireland": "🇮🇪", "United Kingdom": "🇬🇧", "Mexico": "🇲🇽"][country] ?? "🍺"
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { beers = try await BeerService.trends(region: region) } catch { beers = [] }
    }

    private func vote(_ b: TrendedBeer, _ v: Int) {
        let newValue = (myVotes[b.id] == v) ? nil : v
        myVotes[b.id] = newValue
        guard let uid = session.user?.id, let value = newValue else { return }
        Task { try? await BeerService.vote(beerId: b.id, userId: uid, value: value) }
    }
}
