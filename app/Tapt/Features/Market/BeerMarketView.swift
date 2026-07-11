import SwiftUI

/// The Beer Market tab: a live, trading-floor take on beer. A ticker carousel runs
/// across the top, the board ranks beers as tickers you can sort, and tapping one
/// opens a full analysis. Price + movement are real math on community demand.
struct BeerMarketView: View {
    @State private var beers: [MarketBeer] = []
    @State private var ticker: [MarketBeer] = []
    @State private var sort: MarketSort = .movers
    @State private var loading = false
    @State private var loadFailed = false
    @State private var selected: MarketBeer?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        boardHeader
                        if loading && beers.isEmpty {
                            TaptSkeletonList(rows: 8).padding(.top, 6)
                        } else if beers.isEmpty {
                            marketEmptyState
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

    @ViewBuilder private var tickerBar: some View {
        let items = ticker.isEmpty ? beers : ticker
        if !items.isEmpty {   // hide the ticker band entirely on a fresh/empty board
            VStack(spacing: 0) {
                MarketTicker(items: items) { b in Haptic.tap(); selected = b }
                    .background(Brand.malt)
                Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
            }
        }
    }

    // MARK: board header (sort + demo label)

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("The Board").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    Text("Ranked by real votes. Movement blends recent votes, pours & buzz.")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                if MarketService.demoEnabled {
                    Text("DEMO").font(.system(.caption2, design: .rounded).weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Brand.copper.opacity(0.16), in: Capsule())
                        .foregroundStyle(Brand.copper)
                }
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
        Text(MarketService.demoEnabled
             ? "Standings and movement are real community votes, never invented. Demo activity shown until launch fills the real board."
             : "Standings and movement are real community votes. Nothing invented.")
            .font(.caption2).foregroundStyle(Brand.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28).padding(.vertical, 18)
    }

    private func load() async {
        loading = true
        loadFailed = false
        defer { loading = false }
        // Resilient refresh: a transient failure must NOT blank a board that was
        // already showing (the "refresh broke it" bug). Only replace on success.
        if let board = try? await MarketService.feed(sort: sort, limit: 40) {
            beers = board
        } else {
            loadFailed = true
        }
        if ticker.isEmpty {
            ticker = (try? await MarketService.feed(sort: .active, limit: 16)) ?? []
        }
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["TAPT_MARKET_AUTOOPEN"] == "1", selected == nil {
            selected = beers.first
        }
        #endif
    }

    private var marketEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: loadFailed ? "wifi.exclamationmark" : "chart.bar.xaxis")
                .font(.largeTitle).foregroundStyle(Brand.muted)
            Text(loadFailed ? "Couldn't load the board" : "The board is warming up")
                .font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(loadFailed ? "Check your connection and pull to refresh." : "Come back in a moment.")
                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.malt)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Brand.gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.top, 70).padding(.horizontal, 40)
    }
}

// MARK: - Ticker marquee (seamless auto-scroll via TimelineView)

struct MarketTicker: View {
    let items: [MarketBeer]
    var onTap: (MarketBeer) -> Void
    private let speed: Double = 34
    // The row's true laid-out width, measured once. Feeds the seamless-loop math so
    // cells can size to their OWN content (no wrapping, even gaps) instead of a fixed
    // width that clipped and wrapped 4-letter symbols like STON -> "STO"/"N".
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        // A GeometryReader container is "greedy": it fills the offered space and reports
        // NO intrinsic preference, so the wide marquee row can never push the parent
        // layout wide (the bug that blanked Home). We only read the visible width.
        GeometryReader { geo in
            // SwiftUI-qualified: the app also defines a local `TimelineView` (Learn).
            SwiftUI.TimelineView(.animation) { tl in
                HStack(spacing: 0) {
                    row(at: tl.date)
                    row(at: tl.date)
                }
                .offset(x: tickerOffset(at: tl.date))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .frame(height: 40)
    }

    private func tickerOffset(at date: Date) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        let travelled = date.timeIntervalSinceReferenceDate * speed
        return -CGFloat(travelled.truncatingRemainder(dividingBy: Double(rowWidth)))
    }

    private func row(at date: Date) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { b in
                Button { onTap(b) } label: { cell(b, at: date) }
                    .buttonStyle(.plain)
            }
        }
        .background(GeometryReader { g in
            Color.clear.preference(key: TickerRowWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(TickerRowWidthKey.self) { w in
            if w > 0, abs(w - rowWidth) > 0.5 { rowWidth = w }
        }
    }

    private func cell(_ b: MarketBeer, at date: Date) -> some View {
        // Hot beers pulse in sync with the timeline so a real surge in global
        // sentiment is impossible to miss as the ticker slides by.
        let t = date.timeIntervalSinceReferenceDate
        let pulse = b.isHot ? (0.55 + 0.45 * abs(sin(t * 2.3))) : 1.0
        return HStack(spacing: 5) {
            if b.isHot {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8)).foregroundStyle(Brand.gold).opacity(pulse)
            }
            Text(b.symbol).font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(b.isHot ? Brand.gold : Brand.foam)
                .shadow(color: Brand.gold.opacity(b.isHot ? pulse * 0.6 : 0), radius: 5)
            Text(b.netText).font(.system(.caption2, design: .monospaced)).foregroundStyle(Brand.foam.opacity(0.7))
            Image(systemName: b.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8)).foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
            Text(b.changeText).font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
            Text("•").font(.caption2).foregroundStyle(Brand.foam.opacity(0.25)).padding(.horizontal, 7)
        }
        .lineLimit(1)                      // symbols never wrap to a second line
        .fixedSize()                       // cell hugs its content, even gaps
        .padding(.leading, 4)
        .scaleEffect(b.isHot ? 0.97 + 0.05 * pulse : 1)
    }
}

/// Measures the true laid-out width of one ticker row so the marquee can loop
/// seamlessly with content-sized (non-wrapping) cells.
private struct TickerRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
