import SwiftUI

/// Per-beer analysis: the price line, momentum, buy/sell sentiment from real up/down
/// votes, volume, market cap, and where it sits by style and region. Everything here
/// is derived from community demand -- the honest engine behind the ticker.
struct MarketBeerDetailView: View {
    let beer: MarketBeer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    priceBlock
                    chartCard
                    sentimentCard
                    statsGrid
                    contextCard
                    Text("Price and movement are computed from real community votes and check-ins — never invented. Demo data shown until launch.")
                        .font(.caption2).foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Brand.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(beer.symbol).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.gold)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Brand.surface)
                if let s = beer.imageUrl, let u = URL(string: s) {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFit().padding(6) }
                        else { Text(String(beer.symbol.prefix(2))).font(.headline.weight(.heavy)).foregroundStyle(Brand.gold) }
                    }
                } else {
                    Text(String(beer.symbol.prefix(2))).font(.headline.weight(.heavy)).foregroundStyle(Brand.gold)
                }
            }
            .frame(width: 62, height: 62)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(beer.name).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text).lineLimit(2)
                if let brewery = beer.brewery, !brewery.isEmpty {
                    Text(brewery).font(.subheadline).foregroundStyle(Brand.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var priceBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(beer.priceText).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text)
            Label(beer.changeText, systemImage: beer.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(beer.isUp ? Brand.hop : Brand.copper)
            Spacer()
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("7-day price").font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
            Sparkline(values: beer.spark, up: beer.isUp)
                .frame(height: 120)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke((beer.isUp ? Brand.hop : Brand.copper).opacity(0.18)))
    }

    private var sentimentCard: some View {
        let total = max(beer.ups + beer.downs, 1)
        let upFrac = Double(beer.ups) / Double(total)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Buy \(beer.ups)", systemImage: "hand.thumbsup.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.hop)
                Spacer()
                Label("Sell \(beer.downs)", systemImage: "hand.thumbsdown.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(Brand.hop).frame(width: max(4, g.size.width * upFrac))
                    Rectangle().fill(Brand.copper)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            Text("\(Int(upFrac * 100))% buy pressure").font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.malt.opacity(0.08)))
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            stat("Volume 24h", "\(beer.volume)", "bolt.fill", Brand.gold)
            stat("Market cap", beer.marketCapText, "chart.pie.fill", Brand.hop)
            stat("Net demand", (beer.net >= 0 ? "+" : "") + "\(beer.net)", "arrow.up.arrow.down", Brand.copper)
        }
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption2).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.16)))
    }

    private var contextCard: some View {
        HStack(spacing: 10) {
            if let style = beer.style, !style.isEmpty {
                tag(style, "square.grid.2x2.fill")
            }
            if let country = beer.country, !country.isEmpty {
                tag(country, "globe")
            }
            Spacer()
        }
    }

    private func tag(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold)).foregroundStyle(Brand.malt)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Brand.haze, in: Capsule())
    }
}
