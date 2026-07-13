import SwiftUI

/// Per-beer analysis: the price line, momentum, buy/sell sentiment from real up/down
/// votes, volume, market cap, and where it sits by style and region. Everything here
/// is derived from community demand -- the honest engine behind the ticker.
struct MarketBeerDetailView: View {
    let beer: MarketBeer
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    // The trading floor is live: a Buy/Sell moves the pressure bar in place and
    // pays out the same count-up + confetti as the rest of the app.
    @State private var myVote: Int?
    @State private var liveUps: Int?
    @State private var liveDowns: Int?
    @State private var celebration: TaptCelebration?

    private var ups: Int { liveUps ?? beer.ups }
    private var downs: Int { liveDowns ?? beer.downs }

    private var movementColor: Color {
        beer.isFlat ? Brand.muted : (beer.isUp ? Brand.hop : Brand.copper)
    }

    private var reasonText: String {
        if beer.isSeasonal { return "\(beer.moveReason), right in season" }
        if beer.isFlat { return "Holding on current signals" }
        return beer.isUp ? "Climbing on real signals" : "Sliding on current signals"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    priceBlock
                    reasonCard
                    chartCard
                    sentimentCard
                    tradeButtons
                    statsGrid
                    contextCard
                    Text("Standing blends what's in season, real awards, and community votes. It goes fully community-driven as people vote. Nothing invented. Votes only. No money, no trading, not a financial product.")
                        .font(.caption2).foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding()
            }
            .background(Brand.background)
            .taptCelebration($celebration)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(beer.symbol).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Brand.gold)
                }
            }
            .task {
                guard let uid = session.user?.id else { return }
                myVote = try? await BeerService.currentVote(beerId: beer.beerId, userId: uid)
            }
        }
    }

    /// The one action that turns passive analysis into a trade. Buy = thumbs up,
    /// Sell = thumbs down; the pressure bar above springs the instant you tap.
    private var tradeButtons: some View {
        HStack(spacing: 10) {
            tradeButton(side: 1, label: "Buy", icon: "hand.thumbsup.fill", tint: Brand.hop)
            tradeButton(side: -1, label: "Sell", icon: "hand.thumbsdown.fill", tint: Brand.copper)
        }
    }

    private func tradeButton(side: Int, label: String, icon: String, tint: Color) -> some View {
        let active = myVote == side
        return Button { trade(side) } label: {
            Label(active ? "\(label)ing" : label, systemImage: icon)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(active ? Brand.malt : tint)
                .background(active ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.5)))
        }
        .buttonStyle(.taptPress)
        .disabled(session.user == nil)
    }

    private func trade(_ side: Int) {
        guard let uid = session.user?.id else { return }
        Haptic.firm()
        let previous = myVote
        let newValue: Int? = (previous == side) ? nil : side
        // Optimistic: move the pressure bar now.
        var u = ups, d = downs
        if previous == 1 { u -= 1 } else if previous == -1 { d -= 1 }
        if newValue == 1 { u += 1 } else if newValue == -1 { d += 1 }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            myVote = newValue; liveUps = max(0, u); liveDowns = max(0, d)
        }
        Task {
            do {
                if let v = newValue {
                    try await BeerService.vote(beerId: beer.beerId, userId: uid, value: v)
                    if v == 1 {
                        await MainActor.run { celebration = .voteCounted(beer: beer.name, count: ups) }
                    }
                } else {
                    try await BeerService.unvote(beerId: beer.beerId, userId: uid)
                }
            } catch {
                // Roll the optimistic move back on failure.
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        myVote = previous; liveUps = beer.ups; liveDowns = beer.downs
                    }
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
            .frame(width: 68, height: 84)
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(beer.net)").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text)
            Text("standing").font(.subheadline).foregroundStyle(Brand.muted)
            Spacer()
            if beer.isFlat {
                Text("steady today")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Brand.muted)
            } else {
                Label("\(beer.changeText) today", systemImage: beer.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(beer.isUp ? Brand.hop : Brand.copper)
            }
        }
    }

    private var reasonCard: some View {
        HStack(spacing: 10) {
            Image(systemName: beer.isSeasonal ? "sun.max.fill" : "person.3.fill")
                .font(.headline).foregroundStyle(beer.isSeasonal ? Brand.copper : Brand.hop)
            VStack(alignment: .leading, spacing: 1) {
                Text("Why it's moving").font(.caption2.weight(.bold)).foregroundStyle(Brand.muted)
                Text(beer.isSeasonal ? beer.moveReason
                     : (beer.isFlat ? "Steady. Standing comes from season fit, real awards, and notability."
                                    : "Moving on real votes and activity"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.text)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((beer.isSeasonal ? Brand.copper : Brand.hop).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label the REAL span: no "7 days" claim over one day of history.
            Text(beer.spark.count <= 1 ? "Standing · day one" : "Standing · last \(beer.spark.count) days")
                .font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
            Sparkline(values: beer.spark, trend: beer.change)
                .frame(height: 120)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(movementColor.opacity(0.18)))
    }

    private var sentimentCard: some View {
        let cast = ups + downs
        let upFrac = Double(ups) / Double(max(cast, 1))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Buy \(ups)", systemImage: "hand.thumbsup.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.hop)
                Spacer()
                Label("Sell \(downs)", systemImage: "hand.thumbsdown.fill").font(.caption.weight(.bold)).foregroundStyle(Brand.copper)
            }
            if cast > 0 {
                GeometryReader { g in
                    HStack(spacing: 0) {
                        Rectangle().fill(Brand.hop).frame(width: max(4, g.size.width * upFrac))
                        Rectangle().fill(Brand.copper)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                Text("\(Int(upFrac * 100))% buy pressure").font(.caption2).foregroundStyle(Brand.muted)
            } else {
                Text("No votes yet. Be the first to weigh in.").font(.caption2).foregroundStyle(Brand.muted)
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.malt.opacity(0.08)))
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            stat("Standing", "\(beer.net)", "chart.line.uptrend.xyaxis", Brand.gold)
            stat("Total votes", "\(beer.votes)", "hand.thumbsup.fill", Brand.hop)
            stat("Votes 24h", "\(beer.volume)", "bolt.fill", Brand.copper)
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
