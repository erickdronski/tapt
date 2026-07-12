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

    var body: some View {
        ScrollView {
            if let d = detail {
                VStack(alignment: .leading, spacing: 16) {
                    header(d)
                    communityBar(d)
                    noteCard(d)
                    if !d.awards.isEmpty { awardsCard(d.awards) }
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
        .navigationTitle(detail?.name ?? "Beer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
                BeerImageView(url: urlString).padding(6)
            } else {
                srmGlass(d)
            }
        }
        .frame(width: 96, height: 128)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.1)))
    }

    /// When there's no real photo, render a glass tinted by the style's SRM
    /// color range, reference rendering, not a fake product shot.
    private func srmGlass(_ d: BeerDetail) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Brand.foam).frame(height: 14)
            Rectangle().fill(srmColor(d))
        }
        .overlay(
            Image(systemName: "mug.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white.opacity(0.35))
        )
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
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func voteButton(_ d: BeerDetail, _ value: Int, _ icon: String, _ color: Color, count: Int) -> some View {
        let active = myVote == value
        return Button {
            guard let uid = session.user?.id else { return }
            let previous = myVote
            let newValue = active ? nil : value
            if newValue != nil { Haptic.firm() } else { Haptic.tap() }
            // Animate so the digit rolls up and the thumb bounces as the vote lands.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { myVote = newValue }
            Task {
                do {
                    if let v = newValue {
                        try await BeerService.vote(beerId: d.id, userId: uid, value: v)
                    } else {
                        try await BeerService.unvote(beerId: d.id, userId: uid)
                    }
                } catch {
                    // The optimistic thumb must not lie: revert on failure.
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { myVote = previous }
                    Haptic.tap()
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

    // MARK: - Awards (verified, cited)

    private func awardsCard(_ awards: [BeerDetail.Award]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Decorated", systemImage: "medal.fill")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
            ForEach(awards) { award in
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
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.35)))
    }

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
                            Text("Where you'll find it")
                                .font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                            Text("Home turf \(country), \(d.venuesInCountry) beer spots there on the Tapt map")
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
            if let license = d.labelImageLicense {
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
        detail = try? await BeerDetailService.detail(beerId: beerId)
        // Reflect the user's existing vote so the thumbs + counts are correct.
        if let uid = session.user?.id {
            let existing = try? await BeerService.currentVote(beerId: beerId, userId: uid)
            loadedVote = existing
            myVote = existing
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
        return try await Supa.client.rpc("get_beer_note", params: P(p_beer: beerId)).execute().value
    }
    static func save(_ beerId: String, note: String) async throws {
        struct P: Encodable { let p_beer: String; let p_note: String }
        try await Supa.client.rpc("save_beer_note", params: P(p_beer: beerId, p_note: note)).execute()
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
