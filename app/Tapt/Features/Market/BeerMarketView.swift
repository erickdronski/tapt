import SwiftUI

/// The Beer Market tab. Every number and line comes from the live standing
/// engine; quiet periods are shown as quiet instead of being filled with motion.
struct BeerMarketView: View {
    @Environment(Session.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("noLowDefault") private var naOnly = false
    @State private var beers: [MarketBeer] = []
    @State private var ticker: [MarketBeer] = []
    @State private var spotlight: MarketBeer?
    @State private var pulse: MarketPulse?
    @State private var votedBeerCount = 0
    @State private var sort: MarketSort = .standing
    @State private var loading = false
    @State private var loadFailed = false
    @State private var selected: MarketBeer?
    @State private var spotlightVote: Int?
    @State private var spotlightVoteBeerID: String?
    @State private var voteSaving = false
    @State private var voteFeedback: String?
    @State private var voteFeedbackIsError = false
    @State private var celebration: TaptCelebration?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    boardHeader
                    if loadFailed && !beers.isEmpty { refreshWarning }
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
            .safeAreaInset(edge: .top, spacing: 0) { tickerBar }
            .taptCelebration($celebration)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: queryID) { await load() }
            .task(id: spotlightVoteQueryID) { await loadSpotlightVote() }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    await load()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await load() }
            }
            .refreshable { await load() }
            .sheet(item: $selected) { b in
                NavigationStack { BeerDetailView(beerId: b.beerId) }.presentationDetents([.large])
            }
        }
    }

    // MARK: ticker (pinned, auto-scrolling)

    @ViewBuilder private var tickerBar: some View {
        if !ticker.isEmpty, pulse?.isQuiet == false {
            VStack(spacing: 0) {
                MarketTicker(items: ticker) { b in Haptic.tap(); selected = b }
                Rectangle().fill(Brand.gold.opacity(0.5)).frame(height: 1.5)
            }
            .background(Brand.malt.ignoresSafeArea(edges: .top))
        }
    }

    // MARK: board header

    private var boardHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Beer Market")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                    Text("Real scores, community calls, eligible pours, and what is in season.")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                marketStatus
            }

            if let pulse { pulseStrip(pulse) }
            if let pulse { communityState(pulse) }
            if let spotlight { marketSpotlight(spotlight) }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        Haptic.tap()
                        naOnly.toggle()
                        beers = []
                        ticker = []
                    } label: {
                        Label("No / Low", systemImage: naOnly ? "checkmark.circle.fill" : "leaf.fill")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(naOnly ? Brand.hop : Brand.surface, in: Capsule())
                            .foregroundStyle(naOnly ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.hop.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(naOnly ? "On" : "Off")
                    .accessibilityAddTraits(naOnly ? .isSelected : [])
                    ForEach(primarySorts) { s in
                        Button {
                            guard sort != s else { return }
                            Haptic.tap()
                            sort = s
                            beers = []
                        } label: {
                            Label(s.title, systemImage: s.icon)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(sort == s ? Brand.gold : Brand.surface, in: Capsule())
                                .foregroundStyle(sort == s ? Brand.malt : Brand.text)
                                .overlay(Capsule().stroke(Brand.malt.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(sort == s ? .isSelected : [])
                    }
                    Menu {
                        ForEach(secondarySorts) { s in
                            Button {
                                guard sort != s else { return }
                                Haptic.tap()
                                sort = s
                                beers = []
                            } label: {
                                Label(s.title, systemImage: s.icon)
                            }
                        }
                    } label: {
                        let secondarySelected = secondarySorts.contains(sort)
                        Label(secondarySelected ? sort.title : "More boards",
                              systemImage: secondarySelected ? sort.icon : "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(secondarySelected ? Brand.gold : Brand.surface, in: Capsule())
                            .foregroundStyle(secondarySelected ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.malt.opacity(0.10)))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(sort.boardTitle)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                    Spacer()
                    if !loading {
                        Text("\(beers.count)")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Brand.muted)
                            .contentTransition(.numericText())
                    }
                }
                Text(sort.boardSubtitle)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(.horizontal).padding(.top, 14).padding(.bottom, 10)
        .background(Brand.background)
    }

    private var marketStatus: some View {
        let fresh = pulse?.isFresh() == true
        let active = fresh && pulse?.isQuiet == false
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(active ? Brand.hop : (fresh ? Brand.gold : Brand.copper))
                    .frame(width: 7, height: 7)
                Text(active ? "ACTIVE" : (fresh ? "SETTLED" : "DELAYED"))
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.8)
            }
            .foregroundStyle(active ? Brand.hop : (fresh ? Brand.gold : Brand.copper))
            Text(updatedText)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Brand.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var updatedText: String {
        guard let updated = pulse?.updatedDate else { return "Waiting for snapshot" }
        let minutes = max(0, Int(Date.now.timeIntervalSince(updated) / 60))
        if minutes < 1 { return "Updated just now" }
        if minutes == 1 { return "Updated 1 min ago" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        return "Updated \(hours) hr ago"
    }

    private func pulseStrip(_ pulse: MarketPulse) -> some View {
        HStack(spacing: 0) {
            pulseMetric(
                value: pulse.isQuiet ? votedBeerCount : pulse.moving24h,
                label: pulse.isQuiet ? "with calls" : "moving today"
            )
            pulseDivider
            pulseMetric(value: pulse.communityActions24h, label: "actions 24h")
            pulseDivider
            pulseMetric(value: pulse.tracked, label: "scored")
        }
        .padding(.vertical, 11)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.08)))
    }

    private func pulseMetric(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var pulseDivider: some View {
        Rectangle().fill(Brand.malt.opacity(0.08)).frame(width: 1, height: 30)
    }

    private func communityState(_ pulse: MarketPulse) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pulse.isQuiet ? "waveform.path.ecg" : "bolt.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(pulse.isQuiet ? Brand.copper : Brand.hop)
                .frame(width: 30, height: 30)
                .background((pulse.isQuiet ? Brand.copper : Brand.hop).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(pulse.isQuiet ? "You can wake up this board" : "The community is moving it")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                Text(pulse.isQuiet
                     ? "Make a call for a beer or log a real pour. Tapt rolls those signals into the next 30-minute Market snapshot."
                     : "\(pulse.communityActions24h) votes and eligible pours touched \(pulse.active24h) beers in the last 24 hours. The next snapshot carries them forward.")
                    .font(.caption).foregroundStyle(Brand.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke((pulse.isQuiet ? Brand.copper : Brand.hop).opacity(0.24))
        )
    }

    private func marketSpotlight(_ beer: MarketBeer) -> some View {
        VStack(spacing: 0) {
            Button { Haptic.tap(); selected = beer } label: {
                HStack(spacing: 14) {
                    BeerImageView(
                        url: beer.imageUrl,
                        maxPixelSize: 320,
                        style: beer.displayStyle,
                        beerName: beer.displayName,
                        breweryName: beer.displayBrewery
                    )
                    .frame(width: 78, height: 92)
                    .padding(5)
                    .background(Brand.foam.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(beer.isFlat ? (beer.votes > 0 ? "COMMUNITY CALL" : "BEER TO WATCH") : "BIGGEST MOVE TODAY")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Brand.gold)
                        Text(beer.displayName)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Brand.foam)
                            .lineLimit(2)
                        if let brewery = beer.displayBrewery {
                            Text(brewery).font(.caption).foregroundStyle(Brand.foam.opacity(0.72)).lineLimit(1)
                        }
                        Text(beer.moveReason)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Brand.foam.opacity(0.72))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        if beer.isFlat {
                            Text("\(beer.net)")
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(Brand.gold)
                            Text("Tapt Score").font(.caption2).foregroundStyle(Brand.foam.opacity(0.62))
                        } else {
                            Label(beer.changeText, systemImage: beer.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(beer.isUp ? Brand.hop : Brand.gold)
                                .labelStyle(.titleAndIcon)
                            Text("today").font(.caption2).foregroundStyle(Brand.foam.opacity(0.62))
                        }
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                beer.isFlat
                    ? "Beer to watch, \(beer.displayName), Tapt Score \(beer.net)"
                    : "Biggest move today, \(beer.displayName), \(abs(beer.change)) points \(beer.isUp ? "up" : "down")"
            )
            .accessibilityHint("Opens beer details")

            Rectangle().fill(Brand.foam.opacity(0.12)).frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MAKE YOUR CALL")
                            .font(.system(size: 9.5, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(Brand.gold)
                        Text("Your call joins the next Market snapshot.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Brand.foam.opacity(0.72))
                    }
                    Spacer()
                    if voteSaving { ProgressView().tint(Brand.foam).controlSize(.small) }
                }
                HStack(spacing: 8) {
                    spotlightVoteButton(beer, value: 1, title: "Worth the hype", icon: "hand.thumbsup.fill", tint: Brand.hop)
                    spotlightVoteButton(beer, value: -1, title: "Not for me", icon: "hand.thumbsdown.fill", tint: Brand.gold)
                }
                if let voteFeedback {
                    Label(voteFeedback, systemImage: voteFeedbackIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(voteFeedbackIsError ? Brand.gold : Brand.foam.opacity(0.82))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .background(
            LinearGradient(
                colors: [Brand.malt, Brand.copper.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 19)
        )
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(Brand.gold.opacity(0.28)))
    }

    private func spotlightVoteButton(
        _ beer: MarketBeer,
        value: Int,
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        let active = spotlightVoteBeerID == beer.beerId && spotlightVote == value
        return Button { castSpotlightVote(beer, value: value) } label: {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(active ? Brand.malt : Brand.foam)
                .background(active ? tint : Brand.foam.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(active ? 0.9 : 0.52)))
        }
        .buttonStyle(.plain)
        .disabled(voteSaving)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: board row

    private func row(rank: Int, _ b: MarketBeer) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(.footnote, design: .monospaced).weight(.bold))
                .foregroundStyle(Brand.muted).frame(width: 22)
            symbolMark(b)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text).lineLimit(2)
                HStack(spacing: 5) {
                    Text(b.symbol)
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .foregroundStyle(Brand.copper)
                    if let brewery = b.displayBrewery {
                        Text(brewery).font(.caption2).foregroundStyle(Brand.muted).lineLimit(1)
                    }
                }
                if b.isSeasonal {
                    Label(b.moveReason, systemImage: "sun.max.fill")
                        .font(.system(size: 9.5, weight: .bold)).labelStyle(.titleAndIcon)
                        .foregroundStyle(Brand.copper).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Sparkline(values: b.displaySpark, trend: b.windowTrend)
                .frame(width: 46, height: 30)
                .accessibilityHidden(true)
            rowMetric(b)
        }
        .padding(.horizontal).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func symbolMark(_ b: MarketBeer) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Brand.surface)
            BeerImageView(
                url: b.imageUrl,
                maxPixelSize: 160,
                style: b.displayStyle,
                beerName: b.displayName,
                breweryName: b.displayBrewery
            )
            .padding(2)
        }
        .frame(width: 48, height: 56)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.malt.opacity(0.08)))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowMetric(_ beer: MarketBeer) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch sort {
            case .movers, .gainers, .losers:
                Label(
                    beer.changeText,
                    systemImage: beer.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
                )
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(beer.isUp ? Brand.hop : Brand.copper)
                .labelStyle(.titleAndIcon)
                Text("today").font(.system(size: 9)).foregroundStyle(Brand.muted)
                Text("Tapt Score \(beer.net)").font(.caption2).foregroundStyle(Brand.muted)
            case .active:
                Text("\(beer.volume)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.hop)
                    .contentTransition(.numericText())
                Text(beer.volume == 1 ? "action 24h" : "actions 24h")
                    .font(.system(size: 9)).foregroundStyle(Brand.muted)
                changePill(beer)
            case .season:
                Text(beer.seasonFit > 1 ? "peak" : "fit")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.copper)
                Text("in season").font(.system(size: 9)).foregroundStyle(Brand.muted)
                Text("Tapt Score \(beer.net)").font(.caption2).foregroundStyle(Brand.muted)
            case .top:
                Text(beer.voteBalanceText)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(beer.voteBalance >= 0 ? Brand.hop : Brand.copper)
                    .contentTransition(.numericText())
                Text("net votes").font(.system(size: 9)).foregroundStyle(Brand.muted)
                Text("\(beer.votes) total").font(.caption2).foregroundStyle(Brand.muted)
            case .standing:
                Text("\(beer.net)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                    .contentTransition(.numericText())
                Text("Tapt Score").font(.system(size: 9)).foregroundStyle(Brand.muted)
                changePill(beer)
            }
        }
        .frame(width: 76, alignment: .trailing)
    }

    private func rowAccessibilityLabel(rank: Int, beer: MarketBeer) -> String {
        let brewery = beer.displayBrewery.map { ", \($0)" } ?? ""
        let wk = beer.windowTrend
        let movement = beer.isFlat
            ? (wk == 0 ? "steady" : "\(abs(wk)) points \(wk > 0 ? "up" : "down") this week")
            : "\(abs(beer.change)) points \(beer.isUp ? "up" : "down")"
        let selectedMetric: String
        switch sort {
        case .movers, .gainers, .losers: selectedMetric = "\(movement) today"
        case .active: selectedMetric = "\(beer.volume) community actions in 24 hours"
        case .season: selectedMetric = beer.seasonFit > 1 ? "peak seasonal fit" : "seasonal fit"
        case .top: selectedMetric = "\(beer.voteBalance) net votes from \(beer.votes) total votes"
        case .standing: selectedMetric = "Tapt Score \(beer.net), \(movement)"
        }
        return "Rank \(rank), \(beer.displayName)\(brewery), \(selectedMetric), Tapt Score \(beer.net)"
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
        Text("Votes and eligible pours shape the next snapshot alongside real awards and seasonal fit. Nothing invented. No money, no trading, not a financial product.")
            .font(.caption2).foregroundStyle(Brand.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28).padding(.vertical, 18)
    }

    private var queryID: String { "\(sort.rawValue)|\(naOnly)" }
    private var primarySorts: [MarketSort] { [.standing, .movers, .top] }
    private var secondarySorts: [MarketSort] { [.season, .gainers, .losers, .active] }
    private var spotlightVoteQueryID: String {
        "\(spotlight?.beerId ?? "none")|\(session.user?.id.uuidString ?? "guest")"
    }

    private func loadSpotlightVote() async {
        guard let beer = spotlight else {
            spotlightVote = nil
            spotlightVoteBeerID = nil
            return
        }
        guard let uid = session.user?.id else {
            spotlightVote = nil
            spotlightVoteBeerID = beer.beerId
            return
        }
        let requestedID = beer.beerId
        let current = try? await BeerService.currentVote(beerId: requestedID, userId: uid)
        guard spotlight?.beerId == requestedID else { return }
        spotlightVote = current
        spotlightVoteBeerID = requestedID
    }

    private func castSpotlightVote(_ beer: MarketBeer, value: Int) {
        guard !voteSaving else { return }
        guard let uid = session.user?.id else {
            session.deferBeerVote(beerId: beer.beerId, value: value)
            session.deferBeerDetail(beerId: beer.beerId)
            session.endGuestSession()
            return
        }

        let previous = spotlightVoteBeerID == beer.beerId ? spotlightVote : nil
        let next = previous == value ? nil : value
        Haptic.firm()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
            spotlightVote = next
            spotlightVoteBeerID = beer.beerId
            voteFeedback = nil
        }
        voteSaving = true

        Task {
            do {
                if let next {
                    try await BeerService.vote(beerId: beer.beerId, userId: uid, value: next)
                } else {
                    try await BeerService.unvote(beerId: beer.beerId, userId: uid)
                }
                await MainActor.run {
                    voteSaving = false
                    voteFeedbackIsError = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        voteFeedback = next == nil
                            ? "Call removed."
                            : "Call counted. Watch the next snapshot."
                    }
                    if next == 1 {
                        celebration = .voteCounted(
                            beer: beer.displayName,
                            count: beer.ups + (previous == 1 ? 0 : 1)
                        )
                    }
                }
                await load()
            } catch {
                await MainActor.run {
                    voteSaving = false
                    voteFeedbackIsError = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        spotlightVote = previous
                        voteFeedback = "That call did not save. Try again."
                    }
                }
            }
        }
    }

    private func load() async {
        let requestedSort = sort
        let requestedNAOnly = naOnly
        let requestedQuery = queryID
        if beers.isEmpty { loading = true }
        loadFailed = false

        async let boardRequest: [MarketBeer]? = try? await MarketService.feed(
            sort: requestedSort,
            limit: 40,
            naOnly: requestedNAOnly
        )
        async let tickerRequest: [MarketBeer]? = try? await MarketService.feed(
            sort: .movers,
            limit: 16,
            naOnly: requestedNAOnly
        )
        async let spotlightRequest: [MarketBeer]? = try? await MarketService.feed(
            sort: .top,
            limit: 100,
            naOnly: requestedNAOnly
        )
        async let spotlightFallbackRequest: [MarketBeer]? = try? await MarketService.feed(
            sort: .standing,
            limit: 1,
            naOnly: requestedNAOnly
        )
        async let pulseRequest: MarketPulse? = try? await MarketService.pulse()
        let (board, updatedTicker, updatedSpotlight, spotlightFallback, updatedPulse) = await (
            boardRequest,
            tickerRequest,
            spotlightRequest,
            spotlightFallbackRequest,
            pulseRequest
        )

        guard !Task.isCancelled, requestedQuery == queryID else { return }
        loading = false
        loadFailed = board == nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            if let board { beers = board }
            if let updatedTicker { ticker = updatedTicker }
            spotlight = updatedSpotlight?.first ?? spotlightFallback?.first ?? spotlight
            if let updatedSpotlight { votedBeerCount = updatedSpotlight.count }
            if let updatedPulse { pulse = updatedPulse }
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
            Text(loadFailed ? "Couldn't load the board" : sort.emptyTitle)
                .font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(loadFailed ? "Check your connection and pull to refresh." : sort.emptyMessage)
                .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            Button {
                if loadFailed || sort == .standing {
                    Task { await load() }
                } else {
                    sort = .standing
                    beers = []
                }
            } label: {
                Label(loadFailed || sort == .standing ? "Retry" : "Show top score",
                      systemImage: loadFailed || sort == .standing ? "arrow.clockwise" : "trophy.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.malt)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Brand.gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.top, 70).padding(.horizontal, 40)
    }

    private var refreshWarning: some View {
        Label("Could not refresh. Showing the last loaded board.", systemImage: "wifi.exclamationmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.copper)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal).padding(.vertical, 9)
            .background(Brand.copper.opacity(0.08))
    }
}

// MARK: - Ticker marquee (seamless auto-scroll via TimelineView)

struct MarketTicker: View {
    let items: [MarketBeer]
    var onTap: (MarketBeer) -> Void
    private let speed: Double = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    // The row's true laid-out width, measured once. Feeds the seamless-loop math so
    // cells can size to their OWN content (no wrapping, even gaps) instead of a fixed
    // width that clipped and wrapped 4-letter symbols like STON -> "STO"/"N".
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        Group {
            if reduceMotion || voiceOverEnabled {
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
        return "\(beer.displayName), \(movement) today"
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
            let pts = Self.points(for: values, in: geo.size)
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

    static func points(for values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let stepX = size.width / CGFloat(values.count - 1)
        // A steady standing must read as steady: center flat lines and add NO
        // zig-zag (a jagged flat line would fake volatility that didn't happen).
        guard hi - lo >= 1 else {
            return values.indices.map { CGPoint(x: CGFloat($0) * stepX, y: size.height / 2) }
        }
        let span = hi - lo
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - CGFloat((v - lo) / span) * (size.height - 3) - 1.5)
        }
    }
}

#Preview { BeerMarketView().tint(Brand.accent) }
