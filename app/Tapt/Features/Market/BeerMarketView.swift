import SwiftUI

/// The Beer Market tab: a live, trading-floor take on beer. A ticker carousel runs
/// across the top, the board ranks beers as tickers you can sort, and tapping one
/// opens a full analysis. Price + movement are real math on community demand.
struct BeerMarketView: View {
    @AppStorage("noLowDefault") private var naOnly = false
    @State private var beers: [MarketBeer] = []
    @State private var ticker: [MarketBeer] = []
    @State private var sort: MarketSort = .movers
    @State private var loading = false
    @State private var loadFailed = false
    @State private var selected: MarketBeer?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    boardHeader
                    if loading && beers.isEmpty {
                        TaptSkeletonList(rows: 8).padding(.top, 6)
                    } else if beers.isEmpty {
                        marketEmptyState
                    } else {
                        ForEach(Array(beers.enumerated()), id: \.element.id) { i, b in
                            Button { Haptic.tap(); selected = b } label: { row(rank: i + 1, b) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(rowAccessibilityLabel(rank: i + 1, beer: b))
                                .accessibilityHint("Opens beer details")
                            Divider().overlay(Brand.malt.opacity(0.06)).padding(.leading, 60)
                        }
                        footer
                    }
                }
            }
            .background(Brand.background)
            // The tape is a fixed top bar whose malt band bleeds through the
            // status bar, covering the top of the phone. It replaces the nav
            // chrome (the board carries the screen title), so nothing scrolls
            // behind a translucent bar anymore.
            .safeAreaInset(edge: .top, spacing: 0) { tickerBar }
            .toolbar(.hidden, for: .navigationBar)
            .task(id: naOnly) { await load() }
            .refreshable { await load() }
            .sheet(item: $selected) { b in
                NavigationStack { BeerDetailView(beerId: b.beerId) }.presentationDetents([.large])
            }
        }
    }

    // MARK: ticker (pinned, auto-scrolling)

    @ViewBuilder private var tickerBar: some View {
        let items = ticker.isEmpty ? beers : ticker
        if !items.isEmpty {   // hide the ticker band entirely on a fresh/empty board
            VStack(spacing: 0) {
                MarketTicker(items: items) { b in Haptic.tap(); selected = b }
                Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
            }
            // Opaque malt band, bled up through the status bar to cover the phone top.
            .background(Brand.malt.ignoresSafeArea(edges: .top))
        }
    }

    // MARK: board header

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("The Board").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    Text("What people are logging and loving right now, plus awards and what's in season.")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        Haptic.tap()
                        naOnly.toggle()
                    } label: {
                        Label("No / Low", systemImage: naOnly ? "checkmark.circle.fill" : "leaf.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(naOnly ? Brand.hop : Brand.surface, in: Capsule())
                            .foregroundStyle(naOnly ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.hop.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
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
            Sparkline(values: b.spark, trend: b.windowTrend)
                .frame(width: 54, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(b.net)").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    .contentTransition(.numericText())
                Text("standing").font(.system(size: 9)).foregroundStyle(Brand.muted)
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
            BeerImageView(
                url: b.imageUrl,
                maxPixelSize: 160,
                style: b.style,
                beerName: b.name,
                breweryName: b.brewery
            )
            .padding(3)
        }
        .frame(width: 34, height: 34)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.malt.opacity(0.08)))
        .accessibilityHidden(true)
    }

    private func rowAccessibilityLabel(rank: Int, beer: MarketBeer) -> String {
        let brewery = beer.brewery.map { ", \($0)" } ?? ""
        let wk = beer.windowTrend
        let movement = beer.isFlat
            ? (wk == 0 ? "steady" : "\(abs(wk)) points \(wk > 0 ? "up" : "down") this week")
            : "\(abs(beer.change)) points \(beer.isUp ? "up" : "down")"
        return "Rank \(rank), \(beer.name)\(brewery), standing \(beer.net), \(movement)"
    }

    @ViewBuilder
    private func changePill(_ b: MarketBeer) -> some View {
        if b.isFlat, b.windowTrend != 0 {
            // Quiet today but the week genuinely moved: report the real
            // week-window movement instead of a dead "steady".
            let wk = b.windowTrend
            Label("\(abs(wk)) wk", systemImage: wk > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .labelStyle(.titleAndIcon)
                .foregroundStyle((wk > 0 ? Brand.hop : Brand.copper).opacity(0.9))
        } else if b.isFlat {
            // Zero movement is a neutral fact, never a green "+0" gain signal.
            Text("steady")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Brand.muted)
        } else {
            Label(b.changeText, systemImage: b.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(b.isUp ? Brand.hop : Brand.copper)
        }
    }

    private var footer: some View {
        Text("Moves on what people log and rate lately, plus real awards and what's in season. Community pours and votes take over as real activity grows. Nothing invented. No money, no trading, not a financial product.")
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
        if let board = try? await MarketService.feed(sort: sort, limit: 40, naOnly: naOnly) {
            beers = board
        } else {
            loadFailed = true
        }
        if let updatedTicker = try? await MarketService.feed(
            sort: .movers,
            limit: 16,
            naOnly: naOnly
        ) {
            ticker = updatedTicker
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
            Text(loadFailed ? "Check your connection and pull to refresh." : "Give it a second, then pull to refresh.")
                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            Button { Task { await load() } } label: {
                Label(loadFailed ? "Retry" : "Refresh board", systemImage: "arrow.clockwise")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The row's true laid-out width, measured once. Feeds the seamless-loop math so
    // cells can size to their OWN content (no wrapping, even gaps) instead of a fixed
    // width that clipped and wrapped 4-letter symbols like STON -> "STO"/"N".
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        Group {
            if reduceMotion {
                ScrollView(.horizontal, showsIndicators: false) {
                    cells(at: nil)
                }
            } else {
                // A GeometryReader container is "greedy": it fills the offered space and reports
                // NO intrinsic preference, so the wide marquee row can never push the parent
                // layout wide (the bug that blanked Home). We only read the visible width.
                GeometryReader { geo in
                    // SwiftUI-qualified: the app also defines a local `TimelineView` (Learn).
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
                        HStack(spacing: 0) {
                            row(at: tl.date)
                            row(at: tl.date).accessibilityHidden(true)
                        }
                        .offset(x: tickerOffset(at: tl.date))
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                    .clipped()
                }
            }
        }
        .frame(height: 40)
    }

    private func tickerOffset(at date: Date) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        let travelled = date.timeIntervalSinceReferenceDate * speed
        return -CGFloat(travelled.truncatingRemainder(dividingBy: Double(rowWidth)))
    }

    private func row(at date: Date) -> some View {
        cells(at: date)
        .background(GeometryReader { g in
            Color.clear.preference(key: TickerRowWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(TickerRowWidthKey.self) { w in
            if w > 0, abs(w - rowWidth) > 0.5 { rowWidth = w }
        }
    }

    private func cells(at date: Date?) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { beer in
                Button { onTap(beer) } label: { cell(beer, at: date) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: beer))
                    .accessibilityHint("Opens beer details")
            }
        }
    }

    private func cell(_ b: MarketBeer, at date: Date?) -> some View {
        // Hot beers pulse in sync with the timeline so a real surge in global
        // sentiment is impossible to miss as the ticker slides by.
        let pulse: Double
        if let date, b.isHot {
            pulse = 0.55 + 0.45 * abs(sin(date.timeIntervalSinceReferenceDate * 2.3))
        } else {
            pulse = 1
        }
        let moveColor = b.isUp ? Brand.hop : Brand.copper
        return HStack(spacing: 5) {
            if b.isHot {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8)).foregroundStyle(Brand.gold).opacity(pulse)
            }
            Text(b.symbol).font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(b.isHot ? Brand.gold : Brand.foam)
                .shadow(color: Brand.gold.opacity(b.isHot ? pulse * 0.6 : 0), radius: 5)
            Text(b.netText).font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(Brand.foam.opacity(0.82))
            if !b.isFlat {
                // Real movement rides in a colored pill so gainers and sliders pop.
                HStack(spacing: 2) {
                    Image(systemName: b.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .black))
                    Text(b.changeText).font(.system(.caption2, design: .rounded).weight(.heavy))
                }
                .foregroundStyle(moveColor)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(moveColor.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(moveColor.opacity(0.32), lineWidth: 0.5))
            } else if b.windowTrend != 0 {
                // Quiet today, moving on the week: the tape tells the same
                // story as the board rows instead of going grey.
                let wk = b.windowTrend
                let wkColor = wk > 0 ? Brand.hop : Brand.copper
                HStack(spacing: 2) {
                    Image(systemName: wk > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .black))
                    Text("\(abs(wk)) wk").font(.system(.caption2, design: .rounded).weight(.heavy))
                }
                .foregroundStyle(wkColor.opacity(0.92))
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(wkColor.opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke(wkColor.opacity(0.26), lineWidth: 0.5))
            }
            Text("•").font(.caption2).foregroundStyle(Brand.foam.opacity(0.25)).padding(.horizontal, 7)
        }
        .lineLimit(1)                      // symbols never wrap to a second line
        .fixedSize()                       // cell hugs its content, even gaps
        .padding(.leading, 4)
        .scaleEffect(date != nil && b.isHot ? 0.97 + 0.05 * pulse : 1)
    }

    private func accessibilityLabel(for beer: MarketBeer) -> String {
        let movement = beer.isFlat
            ? "steady"
            : "\(abs(beer.change)) points \(beer.isUp ? "up" : "down")"
        return "\(beer.name), standing \(beer.net), \(movement)"
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
    let trend: Int

    private var color: Color {
        trend > 0 ? Brand.hop : (trend < 0 ? Brand.copper : Brand.muted)
    }

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if values.count == 1 {
                    // Day one: one real data point, drawn as exactly that --
                    // a centered dot, not a fabricated line.
                    Circle()
                        .fill(Brand.muted.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                if pts.count > 1 {
                    // fill under the line
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    // the line
                    Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(color, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let stepX = size.width / CGFloat(values.count - 1)
        // A steady standing must read as steady: center flat lines and add NO
        // zig-zag (a jagged flat line would fake volatility that didn't happen).
        guard hi - lo >= 1 else {
            return values.indices.map { CGPoint(x: CGFloat($0) * stepX, y: size.height / 2) }
        }
        let span = hi - lo
        let real = values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - CGFloat((v - lo) / span) * (size.height - 3) - 1.5)
        }
        // Stock-chart texture: the real daily vertices stay exactly on their
        // values; only the interpolation between them gets a small deterministic
        // zig-zag (seeded by position, so it never animates or invents a value).
        guard real.count > 1 else { return real }
        let ticks = 2
        let amp = min(5, max(2, size.height * 0.09))
        var out: [CGPoint] = [real[0]]
        for i in 1..<real.count {
            let a = real[i - 1], b = real[i]
            for t in 1...ticks {
                let f = CGFloat(t) / CGFloat(ticks + 1)
                let baseY = a.y + (b.y - a.y) * f
                // alternate above/below, tapering to zero at the real vertices
                let dir: CGFloat = ((i * (ticks + 1) + t) % 2 == 0) ? 1 : -1
                let taper = 1 - abs(f - 0.5) * 2
                out.append(CGPoint(x: a.x + (b.x - a.x) * f,
                                   y: min(size.height - 1, max(1, baseY + dir * amp * taper))))
            }
            out.append(b)
        }
        return out
    }
}

#Preview { BeerMarketView().tint(Brand.accent) }
