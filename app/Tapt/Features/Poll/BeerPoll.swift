import SwiftUI

// MARK: - Voting popup (the drunk-proof one-tap flow)

/// One beer at a time, three big buttons: love, nah, skip. Runs through the
/// week / month / year races (only candidates you have not voted on), then hands
/// off to the leaderboard. Shown on app open when there is something to vote on.
struct BeerPollSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    var onSeeLeaderboard: () -> Void = {}

    @State private var queue: [(period: PollPeriod, cand: PollCandidate)] = []
    @State private var index = 0
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var voting = false
    @State private var voteError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                if !loaded {
                    ProgressView().tint(Brand.gold)
                } else if index >= queue.count {
                    doneView
                } else {
                    voteView(queue[index].period, queue[index].cand)
                }
            }
            .navigationTitle("Cast your vote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundStyle(Brand.muted)
                }
            }
        }
        .task { guard !loaded else { return }; await build() }
    }

    /// At most this many cards in one sitting. The full slate is 5 per period
    /// across week/month/year, and 15 cards is a chore at a bar. Voted and
    /// skipped candidates are remembered, so the rest surface on later opens --
    /// week first, then month, then year.
    private static let cardsPerSession = 5

    private func build() async {
        guard let uid = session.user?.id else { await MainActor.run { loaded = true }; return }
        var q: [(PollPeriod, PollCandidate)] = []
        var anyFailed = false
        for period in PollPeriod.allCases {
            guard let cands = await BeerPollService.candidates(period, userId: uid) else {
                anyFailed = true
                continue
            }
            for c in cands where c.myVote == nil { q.append((period, c)) }
        }
        let capped = Array(q.prefix(Self.cardsPerSession))
        let failed = anyFailed
        await MainActor.run { queue = capped; loadFailed = failed; loaded = true }
    }

    private func voteView(_ period: PollPeriod, _ c: PollCandidate) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Label(period.title, systemImage: period.icon)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.gold)
                Text("These are trending worldwide right now. Would you crown it?")
                    .font(.caption).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                BeerImageView(url: c.labelImageUrl, maxPixelSize: 500, style: c.style)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Brand.malt.opacity(0.08)))
                VStack(spacing: 5) {
                    Text(c.name)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                        .multilineTextAlignment(.center).lineLimit(2)
                    Text([c.breweryName, c.style, c.country].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
                    if let s = c.standing {
                        Label("Market standing \(s)", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.gold.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)

            if let voteError {
                Text(voteError).font(.caption.weight(.semibold)).foregroundStyle(Brand.copper)
                    .multilineTextAlignment(.center)
            }
            Text("\(index + 1) of \(queue.count)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(Brand.muted)

            HStack(spacing: 12) {
                voteButton("Nah", "hand.thumbsdown.fill", Brand.copper, -1)
                voteButton("Skip", "forward.fill", Brand.muted, 0)
                voteButton("Love", "hand.thumbsup.fill", Brand.hop, 1)
            }
            .padding(.horizontal).padding(.bottom, 6)
        }
        .disabled(voting)
        .id(c.beerId)                 // fresh transition per beer
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
    }

    private func voteButton(_ label: String, _ icon: String, _ tint: Color, _ value: Int) -> some View {
        Button { vote(value) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 24, weight: .bold))
                Text(label).font(.system(.subheadline, design: .rounded).weight(.heavy))
            }
            .foregroundStyle(value == 0 ? Brand.text : Brand.malt)
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(value == 0 ? Brand.surface : tint, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.35)))
        }
        .buttonStyle(.taptPress)
    }

    private func vote(_ value: Int) {
        guard index < queue.count, !voting, let uid = session.user?.id else { return }
        let item = queue[index]
        voting = true
        voteError = nil
        // A light tap acknowledges the press. The success haptic waits for the
        // server, because firing it up front tells your hand the vote counted
        // before we know it did.
        Haptic.tap()
        Task {
            let ok = await BeerPollService.cast(item.period, beer: item.cand.beerId, vote: value, userId: uid)
            await MainActor.run {
                voting = false
                // Only advance on a real persisted vote -- never report a phantom one.
                if ok {
                    if value == 1 { Haptic.success() }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { index += 1 }
                    if index >= queue.count { Haptic.celebrate() }
                } else {
                    voteError = "Couldn't save that. Check your connection and tap again."
                    Haptic.tap()
                }
            }
        }
    }

    private var doneView: some View {
        // Three distinct outcomes. "All caught up" is a claim about the market, so
        // it is only said when the market actually answered.
        let couldNotLoad = queue.isEmpty && loadFailed
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: couldNotLoad ? "wifi.exclamationmark" : "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(couldNotLoad ? Brand.muted : Brand.hop)
            Text(couldNotLoad ? "Could not load the ballot"
                 : (queue.isEmpty ? "You are all caught up" : "Your votes are in"))
                .font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(couldNotLoad
                 ? "Check your connection and try again."
                 : (queue.isEmpty
                    ? "No new beers to vote on right now. Check back as the market moves."
                    : "You helped crown this period's contenders. See how the race stands."))
                .font(.subheadline).foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            if couldNotLoad {
                Button("Try again") {
                    loaded = false
                    loadFailed = false
                    Task { await build() }
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt)
            }
            if !queue.isEmpty {
                Button("See the leaderboard") { dismiss(); onSeeLeaderboard() }
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Brand.malt)
            }
            Button("Done") { dismiss() }.font(.subheadline).foregroundStyle(Brand.muted)
        }
        .padding(28)
    }
}

// MARK: - Leaderboard: the race for each period

/// The full race page: a period toggle, the reigning champion, and the live
/// standings this period. Reachable from the popup and the Explore card.
struct BeerRaceView: View {
    @State private var period: PollPeriod = .week
    @State private var winner: PollWinner?
    @State private var standings: [PollStanding] = []
    @State private var loading = false
    @State private var showVote = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker

                if let w = winner {
                    winnerBanner(w)
                }

                Button { showVote = true } label: {
                    Label("Cast your vote", systemImage: "hand.thumbsup.fill")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.malt)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.taptPress)

                Text("The race \(period.short.lowercased())")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)

                if loading && standings.isEmpty {
                    ProgressView().tint(Brand.gold).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if standings.isEmpty {
                    Text("No votes yet \(period.short.lowercased()). Cast the first and set the pace.")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 8) {
                        ForEach(standings) { s in standingRow(s) }
                    }
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Beer of Tapt")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: period) { await load() }
        .sheet(isPresented: $showVote) {
            BeerPollSheet()
                .onDisappear { Task { await load() } }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach(PollPeriod.allCases) { p in
                Button {
                    Haptic.tap()
                    withAnimation(.snappy) { period = p }
                } label: {
                    Text(p.short)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(period == p ? Brand.gold : Brand.surface, in: Capsule())
                        .foregroundStyle(period == p ? Brand.malt : Brand.text)
                        .overlay(Capsule().stroke(Brand.malt.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func winnerBanner(_ w: PollWinner) -> some View {
        NavigationLink { BeerDetailView(beerId: w.beerId) } label: {
            HStack(spacing: 12) {
                TaptCrownMedallion(size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reigning champion").font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
                    Text(w.name).font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text).lineLimit(1)
                    Text("\(w.label) · \(w.net) net votes").font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
            }
            .padding(14)
            .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func standingRow(_ s: PollStanding) -> some View {
        NavigationLink { BeerDetailView(beerId: s.beerId) } label: {
            HStack(spacing: 12) {
                Text("\(s.rank)").font(.system(.footnote, design: .monospaced).weight(.bold))
                    .foregroundStyle(Brand.muted).frame(width: 20)
                BeerImageView(url: s.labelImageUrl, maxPixelSize: 120, style: s.style)
                    .frame(width: 40, height: 40)
                    .background(Brand.background, in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text).lineLimit(1)
                    Text([s.breweryName, s.country].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Label("\(s.net)", systemImage: "hand.thumbsup.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.hop)
            }
            .padding(10)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        loading = true
        async let w = BeerPollService.winner(period)
        async let s = BeerPollService.standings(period)
        winner = await w
        standings = await s
        loading = false
    }
}

// MARK: - Explore card

/// Compact "Beer of Tapt" card on the home page: the reigning champion plus the
/// top of this period's race, a Vote button, and a tap through to the full race.
struct BeerRaceCard: View {
    @State private var period: PollPeriod = .week
    @State private var winner: PollWinner?
    @State private var top: [PollStanding] = []
    @State private var loaded = false
    @State private var showVote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Beer of Tapt", systemImage: "crown.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer()
                NavigationLink { BeerRaceView() } label: {
                    HStack(spacing: 3) { Text("See all"); Image(systemName: "chevron.right") }
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.copper)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(PollPeriod.allCases) { p in
                    Button {
                        Haptic.tap(); withAnimation(.snappy) { period = p }
                    } label: {
                        Text(p.short).font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(period == p ? Brand.gold : Brand.background, in: Capsule())
                            .foregroundStyle(period == p ? Brand.malt : Brand.muted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let w = winner {
                NavigationLink { BeerDetailView(beerId: w.beerId) } label: {
                    HStack(spacing: 8) {
                        TaptCrownMedallion(size: 30)
                        Text("Champion: \(w.name)").font(.subheadline.weight(.bold))
                            .foregroundStyle(Brand.text).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if top.isEmpty {
                Text("No votes yet \(period.short.lowercased()). Be the first to crown one.")
                    .font(.subheadline).foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(top.prefix(3)) { s in
                        HStack(spacing: 10) {
                            Text(medal(s.rank)).font(.subheadline).frame(width: 22)
                            BeerImageView(url: s.labelImageUrl, maxPixelSize: 100, style: s.style)
                                .frame(width: 30, height: 30)
                                .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(s.name).font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text).lineLimit(1)
                            Spacer(minLength: 0)
                            Label("\(s.net)", systemImage: "hand.thumbsup.fill")
                                .font(.caption.weight(.heavy)).foregroundStyle(Brand.hop)
                        }
                    }
                }
            }

            Button { showVote = true } label: {
                Label("Vote for \(period.title.replacingOccurrences(of: "Beer of ", with: ""))",
                      systemImage: "hand.thumbsup.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.malt)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.taptPress)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.3)))
        .task(id: period) { await load() }
        .sheet(isPresented: $showVote) {
            BeerPollSheet().onDisappear { Task { await load() } }
        }
    }

    private func medal(_ rank: Int) -> String {
        switch rank { case 1: "🥇"; case 2: "🥈"; case 3: "🥉"; default: "•" }
    }

    private func load() async {
        async let w = BeerPollService.winner(period)
        async let s = BeerPollService.standings(period, limit: 3)
        winner = await w
        top = await s
        loaded = true
    }
}

// MARK: - Tapt honor badge (on winning beers' pages)

/// The unique Tapt crown medallion: gold disc, white crown, worn by beers the
/// community has crowned. Drawn, not emoji, so it reads as a real Tapt award.
struct TaptCrownMedallion: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Brand.gold, Brand.copper],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: size * 0.06))
                .shadow(color: Brand.gold.opacity(0.4), radius: size * 0.12, y: size * 0.06)
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Card on a beer page listing every period the community crowned this beer.
struct TaptHonorsCard: View {
    let beerId: String
    @State private var wins: [PollWin] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !wins.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tapt honors", systemImage: "crown.fill")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    ForEach(wins) { w in
                        HStack(spacing: 12) {
                            TaptCrownMedallion(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.periodTitle)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Brand.text)
                                Text("\(w.label) · voted a favorite by the Tapt community")
                                    .font(.caption).foregroundStyle(Brand.copper)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Brand.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.35)))
            }
        }
        .task {
            guard !loaded else { return }
            wins = await BeerPollService.wins(beer: beerId)
            loaded = true
        }
    }
}
