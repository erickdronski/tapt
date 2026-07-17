import SwiftUI

/// The beer page. Every fact is sourced: product fields from the catalog
/// (editorial or Open Food Facts), style science from BJCP 2021, nutrition
/// from Open Food Facts, community numbers from first-party votes and pours.
/// Sections with no real data simply don't render, blank beats invented.
struct BeerDetailView: View {
    @Environment(Session.self) private var session
    let beerId: String

    @State private var detail: BeerDetail?
    @State private var loading = true
    @State private var myVote: Int?
    @State private var loadedVote: Int?     // the caller's vote at load, so counts don't double-count
    @State private var note = ""
    @State private var savedNote = ""
    @State private var savingNote = false
    @State private var showLogPour = false
    @State private var quickLogging = false
    @State private var quickLoggedId: String?
    @State private var quickLogError: String?
    @State private var loadError: String?
    @State private var voteMessage: String?
    @State private var voteMessageIsError = false
    @State private var market: MarketBeer?
    @State private var celebration: TaptCelebration?

    var body: some View {
        ScrollView {
            if let d = detail {
                VStack(alignment: .leading, spacing: 16) {
                    header(d)
                    communityBar(d)
                    if let m = market { marketCard(m) }
                    if let voteMessage {
                        Label(voteMessage, systemImage: voteMessageIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(voteMessageIsError ? Brand.copper : Brand.hop)
                            .padding(.horizontal, 4)
                    }
                    logPourButton(d)
                    if session.user != nil {
                        noteCard(d)
                    } else {
                        signInCard
                    }
                    TaptHonorsCard(beerId: beerId)
                    if !d.awards.isEmpty { awardsCard(d.awards, name: d.name) }
                    if d.styleName != nil { styleScience(d) }
                    if !d.sensory.isEmpty || d.styleFlavorNotes != nil { tasteCard(d) }
                    if let ing = d.styleIngredients, !ing.isEmpty { ingredientsCard(ing) }
                    factsCard(d)
                    if let n = d.nutrition, hasNutrition(n) { nutritionCard(n) }
                    if let origin = matchedOrigin(d) { funFact(origin) }
                    if let hist = d.styleHistory, !hist.isEmpty { styleStoryCard(hist) }
                    whereToFind(d)
                    howItsMadeLink
                    sourcesFooter(d)
                }
                .padding()
            } else if loading {
                VStack(spacing: 14) {
                    TaptSkeletonList(rows: 4, rowHeight: 80)
                }
                .padding(.top, 20)
            } else if let loadError {
                TaptEmptyState(
                    icon: "wifi.exclamationmark",
                    title: "Beer details unavailable",
                    message: loadError,
                    actionTitle: "Try again",
                    action: { Task { await load() } }
                )
            } else {
                TaptEmptyState(
                    icon: "questionmark.circle",
                    title: "Beer not found",
                    message: "This pour seems to have left the cellar.",
                    actionTitle: nil
                )
            }
        }
        .background(Brand.background)
        .taptCelebration($celebration)
        .navigationTitle(detail?.name ?? "Beer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showLogPour) {
            if let detail {
                LogPourView(initialBeer: beerPick(detail), updatingCheckinId: quickLoggedId)
            }
        }
    }

    // MARK: - Header

    private func header(_ d: BeerDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            labelImage(d)
            VStack(alignment: .leading, spacing: 6) {
                Text(d.name)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let brewery = d.breweryName {
                    Text([brewery, d.breweryCountry].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
                HStack(spacing: 6) {
                    if let style = d.style {
                        chip(style, tint: Brand.gold)
                    }
                    if let abv = d.abv {
                        chip(String(format: "%.1f%% ABV", abv), tint: Brand.copper)
                    }
                    if d.isNaLow {
                        chip("No / Low", tint: Brand.hop)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func labelImage(_ d: BeerDetail) -> some View {
        Group {
            if let urlString = d.labelImageUrl, !urlString.isEmpty {
                BeerImageView(url: urlString, style: d.style).padding(6)
            } else {
                srmGlass(d)
            }
        }
        .frame(width: 96, height: 128)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.1)))
    }

    /// When there's no real photo, render the canonical glass tinted by the
    /// style's real color family, branded illustration, never a fake photo.
    private func srmGlass(_ d: BeerDetail) -> some View {
        BeerGlassView(pour: 0.8, animatesPour: false, style: d.style)
            .padding(10)
    }

    private func srmColor(_ d: BeerDetail) -> Color {
        let mid: Double
        if let lo = d.styleSrmMin, let hi = d.styleSrmMax {
            mid = Double(lo + hi) / 2
        } else {
            mid = 5
        }
        return Color.fromSRM(mid)
    }

    // MARK: - Community

    private func communityBar(_ d: BeerDetail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YOUR TAKE")
                .font(.caption2.weight(.heavy)).tracking(0.6)
                .foregroundStyle(Brand.muted)
            HStack(spacing: 12) {
                voteButton(d, 1, "hand.thumbsup.fill", Brand.hop, count: max(0, d.ups - (loadedVote == 1 ? 1 : 0)) + (myVote == 1 ? 1 : 0))
                voteButton(d, -1, "hand.thumbsdown.fill", Brand.copper, count: max(0, d.downs - (loadedVote == -1 ? 1 : 0)) + (myVote == -1 ? 1 : 0))
                Spacer()
                if d.checkinCount > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(d.checkinCount) pours")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Brand.text)
                        if let avg = d.avgRating {
                            Label(String(format: "%.1f", avg), systemImage: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Brand.gold)
                        }
                    }
                } else {
                    Text("Be the first to log it")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
            }
            Text("Saved to your beers. Fresh likes and pours are what move the board each week.")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Beer Market standing (how this beer is tracking, on the one page)

    /// The live market block, folded in from the old separate market screen so the
    /// profile shows sentiment, standing, and movement in one place. Read-only:
    /// the up/down vote above is the single vote action. Renders only when the beer
    /// is on the board (market != nil).
    private func marketCard(_ m: MarketBeer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Beer Market", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                Spacer()
                if m.isFlat {
                    Text("steady today").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
                } else {
                    Label("\(m.changeText) today", systemImage: m.isUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.caption.weight(.heavy)).labelStyle(.titleAndIcon)
                        .foregroundStyle(m.isUp ? Brand.hop : Brand.copper)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(m.net)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text)
                Text("standing").font(.subheadline).foregroundStyle(Brand.muted)
            }
            if !m.moveReason.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: m.isSeasonal ? "sun.max.fill" : "person.3.fill")
                        .font(.footnote).foregroundStyle(m.isSeasonal ? Brand.copper : Brand.hop)
                    Text(m.moveReason).font(.footnote.weight(.semibold)).foregroundStyle(Brand.text)
                    Spacer(minLength: 0)
                }
            }
            Sparkline(values: m.spark, trend: m.change)
                .frame(height: 84)
            HStack(spacing: 10) {
                marketStat("Total votes", "\(m.votes)")
                marketStat("Votes 24h", "\(m.volume)")
            }
            let breakdown = standingBreakdown(m)
            if !breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WHY THIS STANDING")
                        .font(.caption2.weight(.heavy)).tracking(0.6)
                        .foregroundStyle(Brand.muted)
                    ForEach(breakdown, id: \.0) { row in
                        HStack {
                            Text(row.0).font(.caption).foregroundStyle(Brand.text.opacity(0.85))
                            Spacer()
                            Text(row.1)
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(row.1.hasPrefix("-") ? Brand.copper : Brand.hop)
                        }
                    }
                }
                .padding(10)
                .background(Brand.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Moves on what people are drinking and rating lately, plus real awards and what's in season. Beers nobody touches cool off over time. No money, no trading, not a financial product.")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.08)))
    }

    private func marketStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption2).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The core loop, one tap: "I'm drinking this" writes the pour instantly.
    /// Rating, tags, and the rest are optional afterthoughts, never homework.
    private func logPourButton(_ d: BeerDetail) -> some View {
        VStack(spacing: 8) {
            Button {
                guard let uid = session.user?.id else {
                    session.deferBeerDetail(beerId: d.id)
                    session.endGuestSession()
                    return
                }
                guard !quickLogging else { return }
                quickLogging = true
                Haptic.firm()
                Task {
                    do {
                        let id = try await CheckinService.quickLog(beer: beerPick(d), userId: uid)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            quickLoggedId = id
                        }
                        Haptic.firm()
                    } catch {
                        quickLogError = "Could not log that. Try again."
                    }
                    quickLogging = false
                }
            } label: {
                Label(
                    quickLoggedId != nil ? "Logged. Cheers!" : (quickLogging ? "Logging..." : "I'm drinking this"),
                    systemImage: quickLoggedId != nil ? "checkmark.circle.fill" : "plus.circle.fill"
                )
                .font(.system(.headline, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(quickLoggedId != nil ? Brand.hop : Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(quickLoggedId != nil ? .white : Brand.malt)
            }
            .buttonStyle(.taptPress)
            .disabled(quickLogging)

            if let error = quickLogError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            if quickLoggedId != nil {
                Button {
                    showLogPour = true
                } label: {
                    Text("Add a rating or details")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Brand.gold)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Every point on the board is explainable. Rows only appear for real,
    /// nonzero components; nothing is invented to fill the panel.
    private func standingBreakdown(_ m: MarketBeer) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let s = m.seasonPts, s > 0 { rows.append(("In season for this style", "+\(s)")) }
        if let a = m.awardPts, a > 0 { rows.append(("Real medal record", "+\(a)")) }
        if let n = m.notabilityPts, n > 0 { rows.append(("Catalog completeness", "+\(n)")) }
        if let v = m.votePts, v > 0 { rows.append(("Recent votes and pours", "+\(v)")) }
        if let q = m.driftPts, q > 0 { rows.append(("Quiet lately", "-\(q)")) }
        return rows
    }

    private func beerPick(_ d: BeerDetail) -> BeerPick {
        BeerPick(
            id: d.id,
            name: d.name,
            style: d.style,
            abv: d.abv,
            breweryName: d.breweryName ?? "",
            country: d.breweryCountry ?? ""
        )
    }

    private func voteButton(_ d: BeerDetail, _ value: Int, _ icon: String, _ color: Color, count: Int) -> some View {
        let active = myVote == value
        return Button {
            guard let uid = session.user?.id else {
                session.deferBeerVote(beerId: d.id, value: value)
                session.deferBeerDetail(beerId: d.id)
                session.endGuestSession()
                return
            }
            let previous = myVote
            let newValue = active ? nil : value
            if newValue != nil { Haptic.firm() } else { Haptic.tap() }
            // Animate so the digit rolls up and the thumb bounces as the vote lands.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { myVote = newValue }
            Task {
                do {
                    if let v = newValue {
                        try await BeerService.vote(beerId: d.id, userId: uid, value: v)
                        if v == 1 {
                            let upCount = max(0, d.ups - (loadedVote == 1 ? 1 : 0)) + 1
                            await MainActor.run { celebration = .voteCounted(beer: d.name, count: upCount) }
                        }
                    } else {
                        try await BeerService.unvote(beerId: d.id, userId: uid)
                    }
                    await MainActor.run {
                        session.clearPendingBeerVote(for: d.id)
                        voteMessage = nil
                    }
                } catch {
                    // The optimistic thumb must not lie: revert on failure.
                    await MainActor.run {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { myVote = previous }
                        voteMessage = "Vote did not save. Check your connection and try again."
                        voteMessageIsError = true
                        Haptic.tap()
                    }
                }
            }
        } label: {
            Label {
                Text("\(count)").contentTransition(.numericText(value: Double(count)))
            } icon: {
                Image(systemName: icon).symbolEffect(.bounce, value: myVote == value)
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(active ? Brand.malt : color)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(active ? color : Brand.background, in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: active)
    }

    private var signInCard: some View {
        Button {
            session.endGuestSession()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Brand.malt)
                    .frame(width: 46, height: 46)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save your take")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Text("Sign in to vote, add a private note, and build your Cellar.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(14)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Awards (verified, cited)

    /// Awards ordered by prestige so the collapsed tile always shows the best
    /// three first: gold, then Tapt's Favorite, then silver, bronze, newest year up.
    private func rankedAwards(_ awards: [BeerDetail.Award]) -> [BeerDetail.Award] {
        func rank(_ m: String) -> Int {
            switch m {
            case "gold": return 0
            case "tapt_favorite": return 1
            case "silver": return 2
            case "bronze": return 3
            default: return 4
            }
        }
        return awards.sorted {
            if rank($0.medal) != rank($1.medal) { return rank($0.medal) < rank($1.medal) }
            return ($0.year ?? 0) > ($1.year ?? 0)
        }
    }

    /// Collapsed awards tile: only the top three medals, then a "See all" that
    /// opens the full decorated page. Keeps a heavily-awarded beer from burying
    /// the rest of the page under a wall of medals.
    private func awardsCard(_ awards: [BeerDetail.Award], name: String) -> some View {
        let ranked = rankedAwards(awards)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Decorated", systemImage: "medal.fill")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer()
                Text("\(awards.count)")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Brand.gold, in: Capsule())
            }
            ForEach(ranked.prefix(3)) { award in awardRow(award) }
            if ranked.count > 3 {
                NavigationLink {
                    BeerAwardsListView(beerName: name, awards: ranked)
                } label: {
                    HStack(spacing: 4) {
                        Text("See all \(awards.count) awards")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.copper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Brand.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.35)))
    }

    /// One award row, shared by the collapsed tile and the full decorated page.
    func awardRow(_ award: BeerDetail.Award) -> some View { AwardRowView(award: award) }

    // MARK: - Style science (BJCP)

    private func styleScience(_ d: BeerDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.styleName ?? "")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    if let family = d.styleFamily {
                        Text("\(family) family")
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                }
                Spacer()
                if let lo = d.styleSrmMin, let hi = d.styleSrmMax {
                    HStack(spacing: 3) {
                        ForEach([lo, (lo + hi) / 2, hi], id: \.self) { srm in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.fromSRM(Double(srm)))
                                .frame(width: 18, height: 26)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.malt.opacity(0.15)))
                }
            }

            if let description = d.styleDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lo = d.styleIbuMin, let hi = d.styleIbuMax {
                rangeMeter(
                    title: "Hoppiness",
                    icon: "leaf.fill",
                    tint: Brand.hop,
                    lo: Double(lo), hi: Double(hi), scaleMax: 100,
                    value: d.ibu.map(Double.init),
                    unit: "IBU"
                )
            }
            if let lo = d.styleAbvMin, let hi = d.styleAbvMax {
                rangeMeter(
                    title: "Strength",
                    icon: "flame.fill",
                    tint: Brand.copper,
                    lo: lo, hi: hi, scaleMax: 13,
                    value: d.abv,
                    unit: "% ABV"
                )
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.2)))
    }

    /// A style range band on a fixed scale, with the beer's own value marked
    /// when we know it.
    private func rangeMeter(title: String, icon: String, tint: Color, lo: Double, hi: Double, scaleMax: Double, value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
                Text(value.map { trimmed($0) + " \(unit)" } ?? "\(trimmed(lo))-\(trimmed(hi)) \(unit)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.haze.opacity(0.7))
                    Capsule()
                        .fill(tint.opacity(0.55))
                        .frame(width: max(8, w * (hi - lo) / scaleMax))
                        .offset(x: w * lo / scaleMax)
                    if let value {
                        Circle()
                            .fill(tint)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Brand.foam, lineWidth: 2))
                            .offset(x: min(max(w * value / scaleMax - 7, 0), w - 14))
                    }
                }
            }
            .frame(height: 14)
        }
    }

    private func trimmed(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    // MARK: - Taste & feel (sensory profile), ingredients, style story

    /// What it tastes like + a 0-5 sensory profile (hoppiness, bitterness, sourness,
    /// body, roast, sweetness, fruitiness) typical of the beer's style. BJCP-grounded.
    private func tasteCard(_ d: BeerDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Taste & feel", systemImage: "waveform.path.ecg")
                .font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            if let notes = d.styleFlavorNotes, !notes.isEmpty {
                Text(notes).font(.subheadline).foregroundStyle(Brand.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 9) {
                ForEach(d.sensory, id: \.0) { label, value in
                    sensoryBar(label, value)
                }
            }
            Text("Typical for the style · BJCP 2021")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.2)))
    }

    private func sensoryBar(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
                .frame(width: 108, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < value ? sensoryTint(label) : Brand.haze.opacity(0.55))
                        .frame(height: 9)
                }
            }
        }
    }

    private func sensoryTint(_ label: String) -> Color {
        switch label {
        case "Hoppiness": return Brand.hop
        case "Bitterness": return Brand.copper
        case "Roast": return Brand.malt
        case "Sourness": return Brand.gold
        case "Fruitiness": return Brand.copper
        default: return Brand.gold
        }
    }

    private func ingredientsCard(_ ingredients: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What's in it", systemImage: "leaf.circle.fill")
                .font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(ingredients).font(.subheadline).foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Typical ingredients for the style.")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func styleStoryCard(_ history: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Where it comes from", systemImage: "book.closed.fill")
                .font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(history).font(.subheadline).foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.copper.opacity(0.22)))
    }

    // MARK: - Facts / nutrition / fun fact / find it

    private func factsCard(_ d: BeerDetail) -> some View {
        VStack(spacing: 0) {
            if let abv = d.abv { factRow("ABV", String(format: "%.1f%%", abv)) }
            if let ibu = d.ibu { factRow("Bitterness", "\(ibu) IBU") }
            if let substyle = d.substyle { factRow("Substyle", substyle) }
            if let country = d.breweryCountry { factRow("Country", country) }
            if let site = d.breweryWebsite, let url = URL(string: site) {
                HStack {
                    Text("Brewery site").font(.subheadline).foregroundStyle(Brand.muted)
                    Spacer()
                    Link(destination: url) {
                        Text(url.host() ?? "Website")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Brand.copper)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Brand.muted)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
        }
        .padding(.vertical, 10)
    }

    private func hasNutrition(_ n: BeerDetail.Nutrition) -> Bool {
        n.kcal100ml != nil || n.carbsG100ml != nil || n.proteinG100ml != nil || n.sugarsG100ml != nil
    }

    private func nutritionCard(_ n: BeerDetail.Nutrition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nutrition (per 100 ml)", systemImage: "chart.bar.doc.horizontal")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
            HStack(spacing: 10) {
                if let kcal = n.kcal100ml { nutrient("\(Int(kcal))", "kcal") }
                if let carbs = n.carbsG100ml { nutrient(trimmed(carbs), "carbs g") }
                if let sugars = n.sugarsG100ml { nutrient(trimmed(sugars), "sugars g") }
                if let protein = n.proteinG100ml { nutrient(trimmed(protein), "protein g") }
            }
            Text("Source: Open Food Facts")
                .font(.caption2).foregroundStyle(Brand.muted)
            Text("Informational only. Not dietary or medical advice.")
                .font(.caption2).foregroundStyle(Brand.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func nutrient(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption2).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func matchedOrigin(_ d: BeerDetail) -> BreweryOrigin? {
        guard let brewery = d.breweryName?.lowercased() else { return nil }
        return LearnData.origins.first { origin in
            let originName = origin.name.lowercased()
            return originName.contains(brewery) || brewery.contains(originName.components(separatedBy: " (").first ?? originName)
        }
    }

    private func funFact(_ origin: BreweryOrigin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The story", systemImage: "book.fill")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
            Text(origin.story)
                .font(.subheadline)
                .foregroundStyle(Brand.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("💡 \(origin.fact)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.copper)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.copper.opacity(0.25)))
    }

    private func whereToFind(_ d: BeerDetail) -> some View {
        Group {
            if let country = d.breweryCountry, d.venuesInCountry > 0 {
                NavigationLink { NearYouView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill").foregroundStyle(Brand.malt)
                            .frame(width: 42, height: 42)
                            .background(Brand.hop, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Explore its home region")
                                .font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                            Text("\(d.venuesInCountry) beer spots across \(country) are mapped in Tapt")
                                .font(.caption).foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
                    }
                    .padding(14)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var howItsMadeLink: some View {
        NavigationLink { LearnView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill").foregroundStyle(Brand.malt)
                    .frame(width: 42, height: 42)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("How beer is made")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("Malting to packaging, the full journey in Beer School")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(14)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func sourcesFooter(_ d: BeerDetail) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if d.styleName != nil {
                Text("Style ranges: BJCP 2021 Style Guidelines")
            }
            if let license = d.labelImageLicense,
               license.hasPrefix("Open Food Facts") {
                Link("Image source: Open Food Facts", destination: openFoodFactsURL(d))
                Link(
                    "Image license: CC BY-SA 3.0",
                    destination: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!
                )
                if BeerProductImagePolicy.isApproved(d.labelImageUrl) {
                    Text("Modification: background removed by Tapt")
                }
            } else if let license = d.labelImageLicense {
                Text("Label photo: \(license)")
            }
            if d.dataSource == "open_food_facts" {
                Text("Product data: Open Food Facts")
            }
        }
        .font(.caption2)
        .foregroundStyle(Brand.muted)
        .padding(.horizontal, 4)
    }

    private func openFoodFactsURL(_ d: BeerDetail) -> URL {
        let digits = (d.gtin ?? "").filter(\.isNumber)
        if (8...14).contains(digits.count),
           let url = URL(string: "https://world.openfoodfacts.org/product/\(digits)") {
            return url
        }
        return URL(string: "https://world.openfoodfacts.org/")!
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Brand.malt)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.85), in: Capsule())
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await BeerDetailService.detail(beerId: beerId)
            loadError = nil
        } catch {
            loadError = "Check your connection and try again."
            return
        }
        // The one profile also shows how this beer is tracking on the Beer Market.
        // Non-fatal: if it isn't on the board yet, the block simply doesn't render.
        market = try? await MarketService.one(beerId: beerId)
        // Reflect the user's existing vote so the thumbs + counts are correct.
        if let uid = session.user?.id {
            let existing = try? await BeerService.currentVote(beerId: beerId, userId: uid)
            loadedVote = existing
            myVote = existing
            if let pendingVote = session.pendingBeerVote(for: beerId) {
                do {
                    try await BeerService.vote(beerId: beerId, userId: uid, value: pendingVote)
                    myVote = pendingVote
                    session.clearPendingBeerVote(for: beerId)
                    voteMessage = "Signed in. Your vote counted."
                    voteMessageIsError = false
                } catch {
                    voteMessage = "You are signed in, but the vote did not save. Tap it again."
                    voteMessageIsError = true
                }
            }
            let n = (try? await BeerNoteService.get(beerId)) ?? nil
            note = n ?? ""
            savedNote = note
        }
    }

    // MARK: - My note (private, per-user)

    private func noteCard(_ d: BeerDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("My note", systemImage: "square.and.pencil")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                Spacer()
                if savingNote {
                    ProgressView().tint(Brand.gold)
                } else if note != savedNote {
                    Button("Save") { Task { await saveNote() } }
                        .font(.subheadline.weight(.bold)).foregroundStyle(Brand.gold)
                } else if !savedNote.isEmpty {
                    Label("Saved", systemImage: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Brand.hop)
                }
            }
            TextField("Only you see this. Tasting notes, where you had it, what to try next…",
                      text: $note, axis: .vertical)
                .lineLimit(3...8)
                .font(.subheadline).foregroundStyle(Brand.text)
                .padding(12)
                .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.malt.opacity(0.12)))
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.gold.opacity(0.18)))
    }

    private func saveNote() async {
        savingNote = true
        do {
            try await BeerNoteService.save(beerId, note: note)
            savedNote = note
            Haptic.tap()
        } catch { /* keep the unsaved text so nothing is lost */ }
        savingNote = false
    }
}

/// Private, per-user written notes on a beer.
enum BeerNoteService {
    static func get(_ beerId: String) async throws -> String? {
        struct P: Encodable { let p_beer: String }
        return try await Supa.authedRPC("get_beer_note", params: P(p_beer: beerId))
    }
    static func save(_ beerId: String, note: String) async throws {
        struct P: Encodable { let p_beer: String; let p_note: String }
        try await Supa.authedRPCVoid("save_beer_note", params: P(p_beer: beerId, p_note: note))
    }
}

/// One decorated-award row. Shared by the collapsed tile on the beer page and
/// the full "See all awards" page, so both read identically.
struct AwardRowView: View {
    let award: BeerDetail.Award
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(award.medalEmoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text([award.medalLabel,
                      award.awardBody == "Tapt" ? nil : award.awardBody,
                      award.year.map(String.init)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                if let category = award.category {
                    Text(category).font(.caption).foregroundStyle(Brand.muted)
                }
                if award.medal == "tapt_favorite" {
                    Text(award.region.map { "Tapt poured it in \($0), and loved it." } ?? "We were here. We poured it. We loved it.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.copper)
                } else if let note = award.note {
                    Text(note).font(.caption).foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let src = award.sourceUrl, let url = URL(string: src) {
                Link(destination: url) {
                    Image(systemName: "link.circle.fill")
                        .font(.title3).foregroundStyle(Brand.muted)
                }
            }
        }
        .padding(10)
        .background(
            (award.medal == "tapt_favorite" ? Brand.copper : Brand.gold).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

/// The full decorated page: every medal a beer has won, opened from "See all".
struct BeerAwardsListView: View {
    let beerName: String
    let awards: [BeerDetail.Award]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(beerName)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                Text("\(awards.count) awards on record")
                    .font(.caption).foregroundStyle(Brand.muted)
                    .padding(.bottom, 4)
                ForEach(awards) { award in AwardRowView(award: award) }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Decorated")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Color {
    /// Approximate SRM -> beer color (standard reference approximation).
    static func fromSRM(_ srm: Double) -> Color {
        switch srm {
        case ..<2: return Color(hex: 0xF8F4B4)
        case ..<3: return Color(hex: 0xF6F513)
        case ..<4: return Color(hex: 0xECE61A)
        case ..<6: return Color(hex: 0xD5BC26)
        case ..<8: return Color(hex: 0xBF923B)
        case ..<10: return Color(hex: 0xBF813A)
        case ..<13: return Color(hex: 0xA85C25)
        case ..<17: return Color(hex: 0x8D4C32)
        case ..<20: return Color(hex: 0x6B3A1E)
        case ..<24: return Color(hex: 0x5D341A)
        case ..<29: return Color(hex: 0x4E2A0C)
        case ..<35: return Color(hex: 0x361F1B)
        default: return Color(hex: 0x1F1310)
        }
    }
}
