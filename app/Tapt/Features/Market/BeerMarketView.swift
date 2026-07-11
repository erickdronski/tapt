import SwiftUI

/// The Beer Market tab: a live, trading-floor take on beer. A ticker carousel runs
/// across the top, the board ranks beers as tickers you can sort, and tapping one
/// opens a full analysis. Price + movement are real math on community demand.
struct BeerMarketView: View {
    @State private var beers: [MarketBeer] = []
    @State private var ticker: [MarketBeer] = []
    @State private var sort: MarketSort = .movers
    @State private var loading = false
    @State private var selected: MarketBeer?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        boardHeader
                        if loading && beers.isEmpty {
                            TaptSkeletonList(rows: 8).padding(.top, 6)
                        } else {
                            ForEach(Array(beers.enumerated()), id: \.element.id) { i, b in
                                Button { Haptic.tap(); selected = b } label: { row(rank: i + 1, b) }
                                    .buttonStyle(.plain)
                                Divider().overlay(Brand.malt.opacity(0.06)).padding(.leading, 60)
                            }
                            footer
                        }
                    } header: {
                        tickerBar
                    }
                }
            }
            .background(Brand.background)
            .navigationTitle("Beer Market")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $selected) { b in
                MarketBeerDetailView(beer: b).presentationDetents([.large])
            }
        }
    }

    // MARK: ticker (pinned, auto-scrolling)

    private var tickerBar: some View {
        VStack(spacing: 0) {
            MarketTicker(items: ticker.isEmpty ? beers : ticker) { b in Haptic.tap(); selected = b }
                .background(Brand.malt)
            Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
        }
    }

    // MARK: board header (sort + demo label)

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("The Board").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    Text("Ranked by real votes. Movement is the last 24h.")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Text("DEMO").font(.system(.caption2, design: .rounded).weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.copper.opacity(0.16), in: Capsule())
                    .foregroundStyle(Brand.copper)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MarketSort.allCases) { s in
                        Button {
                            Haptic.tap()
                            sort = s
                            Task { await load() }
                        } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(sort == s ? Brand.gold : Brand.surface, in: Capsule())
                                .foregroundStyle(sort == s ? Brand.malt : Brand.text)
                                .overlay(Capsule().stroke(Brand.malt.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal).padding(.top, 14).padding(.bottom, 10)
        .background(Brand.background)
    }

    // MARK: board row

    private func row(rank: Int, _ b: MarketBeer) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(Brand.muted).frame(width: 20)
            symbolMark(b)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.symbol).font(.system(.subheadline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                Text(b.name).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                if b.isSeasonal {
                    Label(b.moveReason, systemImage: "sun.max.fill")
                        .font(.system(size: 9.5, weight: .bold)).labelStyle(.titleAndIcon)
                        .foregroundStyle(Brand.copper).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Sparkline(values: b.spark, up: b.isUp).frame(width: 54, height: 30)
            VStack(alignment: .trailing, spacing: 1) {
                Text(b.netText).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    .contentTransition(.numericText())
                Text("net votes").font(.system(size: 9)).foregroundStyle(Brand.muted)
                changePill(b)
            }
            .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func symbolMark(_ b: MarketBeer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(Brand.surface)
            if let s = b.imageUrl, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFit().padding(3) }
                    else { Text(String(b.symbol.prefix(2))).font(.caption2.weight(.heavy)).foregroundStyle(Brand.gold) }
                }
            } else {
                Text(String(b.symbol.prefix(2))).font(.caption2.weight(.heavy)).foregroundStyle(Brand.gold)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.malt.opacity(0.08)))
    }

    private func changePill(_ b: MarketBeer) -> some View {
        Label(b.changeText, systemImage: b.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(.caption2, design: .rounded).weight(.heavy))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
    }

    private var footer: some View {
        Text("Standings and movement are real community votes, never invented. Demo activity shown until launch fills the real board.")
            .font(.caption2).foregroundStyle(Brand.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28).padding(.vertical, 18)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let board = try? await MarketService.feed(sort: sort, limit: 40)
        async let tick = try? await MarketService.feed(sort: .active, limit: 16)
        beers = await board ?? []
        if ticker.isEmpty { ticker = await tick ?? [] }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["TAPT_MARKET_AUTOOPEN"] == "1", selected == nil {
            selected = beers.first
        }
        #endif
    }
}

// MARK: - Ticker marquee (seamless auto-scroll via TimelineView)

struct MarketTicker: View {
    let items: [MarketBeer]
    var onTap: (MarketBeer) -> Void
    private let speed: Double = 40
    private let cellWidth: CGFloat = 168

    // Fixed-width cells -> the row width is known without measuring, which keeps the
    // marquee math deterministic and the text from being distorted by a GeometryReader.
    private var rowWidth: CGFloat { cellWidth * CGFloat(max(items.count, 1)) }

    var body: some View {
        // SwiftUI-qualified: the app also defines a local `TimelineView` (Learn history).
        SwiftUI.TimelineView(.animation) { tl in
            HStack(spacing: 0) {
                row
                row
            }
            .offset(x: tickerOffset(at: tl.date))
        }
        .frame(height: 40, alignment: .leading)
        .clipped()
    }

    private func tickerOffset(at date: Date) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        let travelled = date.timeIntervalSinceReferenceDate * speed
        return -CGFloat(travelled.truncatingRemainder(dividingBy: Double(rowWidth)))
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(items) { b in
                Button { onTap(b) } label: {
                    cell(b).frame(width: cellWidth, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cell(_ b: MarketBeer) -> some View {
        HStack(spacing: 5) {
            Text(b.symbol).font(.system(.caption, design: .rounded).weight(.heavy)).foregroundStyle(Brand.foam)
            Text(b.netText).font(.system(.caption2, design: .monospaced)).foregroundStyle(Brand.foam.opacity(0.75))
            Image(systemName: b.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8)).foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
            Text(b.changeText).font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    let up: Bool

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    // fill under the line
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [(up ? Brand.hop : Brand.copper).opacity(0.22), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    // the line
                    Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(up ? Brand.hop : Brand.copper, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - CGFloat((v - lo) / span) * (size.height - 3) - 1.5)
        }
    }
}

#Preview { BeerMarketView().tint(Brand.accent) }
