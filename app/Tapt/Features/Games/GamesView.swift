import SwiftUI

/// Games hub. Presented inside Discover's NavigationStack. A vibrant grid so it
/// reads like a real arcade (GamePigeon energy), Beer Olympics featured up top.
struct GamesView: View {
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Game Night")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.text)
                    Text("Pick a game, pass the phone. Real physics, real trivia, all free.")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                }
                .padding(.horizontal, 2)

                // The big one, featured full width.
                NavigationLink { BeerOlympicsView() } label: {
                    FeaturedGameCard(
                        title: "Beer Olympics",
                        tag: "Teams, events, medal table, a champion. The big one.",
                        icon: "trophy.fill",
                        colors: [Color(hex: 0xE0A64B), Brand.copper])
                }
                .buttonStyle(.taptPress)

                sectionLabel("Flick & aim")
                LazyVGrid(columns: cols, spacing: 14) {
                    gameCard("Darts", "Real aim & scatter", "scope",
                             [Brand.copper, Color(hex: 0x7E2A1B)]) { DartsGame() }
                    gameCard("Beer Pong", "Real arc physics", "circle.grid.cross.fill",
                             [Brand.gold, Brand.copper]) { BeerPongGame() }
                    gameCard("Flip Cup", "1-4 player race", "cup.and.saucer.fill",
                             [Brand.hop, Color(hex: 0x2E7D5B)]) { FlipCupGame() }
                    gameCard("Quarters", "Bounce it in", "circle.hexagongrid.fill",
                             [Brand.copper, Color(hex: 0x6B4A2A)]) { QuartersGame() }
                }

                sectionLabel("Brain")
                LazyVGrid(columns: cols, spacing: 14) {
                    gameCard("Trivia", "Pick your topic", "brain.head.profile",
                             [Color(hex: 0x3E6DB5), Color(hex: 0x243F6E)]) { TriviaGame() }
                    gameCard("Daily 5", "Five quick ones", "calendar.badge.clock",
                             [Brand.hop, Color(hex: 0x2E7D5B)]) {
                        TriviaGame(title: "Daily 5", questionLimit: 5, category: .mixed)
                    }
                }

                sectionLabel("Around the table")
                LazyVGrid(columns: cols, spacing: 14) {
                    gameCard("Connect 4", "Four in a row", "circle.grid.3x3.fill",
                             [Brand.gold, Color(hex: 0xC77E2E)]) { ConnectFourGame() }
                    gameCard("Tapt Deck", "House card game", "rectangle.on.rectangle.angled",
                             [Color(hex: 0x7A4FB0), Color(hex: 0x4A2E80)]) { CardDeckGame() }
                    gameCard("Beer Night", "Round roulette", "person.3.fill",
                             [Brand.copper, Color(hex: 0x8A5A2E)]) { BreweryModeView() }
                    gameCard("Guides", "Learn in a minute", "book.fill",
                             [Color(hex: 0x4C6A57), Color(hex: 0x2E4136)]) { GameNightGuidesView() }
                }

                Label(GameGuidesData.safetyLine, systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
                    .padding(.top, 4)
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .foregroundStyle(Brand.muted)
            .tracking(1.2)
            .padding(.top, 4).padding(.horizontal, 2)
    }

    private func gameCard<D: View>(_ title: String, _ tag: String, _ icon: String,
                                   _ colors: [Color],
                                   @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            GameCard(title: title, tag: tag, icon: icon, colors: colors)
        }
        .buttonStyle(.taptPress)
    }
}

/// A vibrant square game tile: gradient field, white glyph, name + one-line tag.
private struct GameCard: View {
    let title: String
    let tag: String
    let icon: String
    let colors: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            Spacer(minLength: 12)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
            Text(tag)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(15)
        .frame(height: 132, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: (colors.last ?? .black).opacity(0.35), radius: 9, y: 5)
    }
}

/// The featured hero card (wider, taller) for the flagship game.
private struct FeaturedGameCard: View {
    let title: String
    let tag: String
    let icon: String
    let colors: [Color]

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FEATURED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).tracking(1.5)
                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(tag)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: (colors.last ?? .black).opacity(0.4), radius: 12, y: 7)
    }
}

// MARK: - Trivia (playable, mixed topics)
struct TriviaGame: View {
    let title: String
    let questionLimit: Int?
    @State private var category: TriviaCategory?
    @State private var order: [TriviaQuestion] = []
    @State private var index = 0
    @State private var selected: Int?
    @State private var score = 0
    @State private var streak = 0
    @State private var finished = false

    private var q: TriviaQuestion { order[index] }

    /// Pass a category to skip the chooser (e.g. Daily 5 -> .mixed).
    init(title: String = "Trivia", questionLimit: Int? = nil, category: TriviaCategory? = nil) {
        self.title = title
        self.questionLimit = questionLimit
        _category = State(initialValue: category)
        if let category {
            _order = State(initialValue: Self.pickQuestions(
                limit: questionLimit,
                category: category,
                seed: title == "Daily 5" ? Self.dailySeed(category: category) : nil
            ))
        }
    }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            if category == nil { chooser }
            else if finished { results }
            else { question }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chooser: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Pick a category")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.text)
                    .padding(.top, 10)
                Text("Beer, pop culture, wild facts, or general, play what you know.")
                    .font(.subheadline).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                ForEach(TriviaCategory.allCases) { cat in
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            category = cat
                            order = Self.pickQuestions(limit: questionLimit, category: cat)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Brand.malt)
                                .frame(width: 50, height: 50)
                                .background(catTint(cat), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.rawValue)
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Brand.text)
                                Text("\(TriviaData.pool(cat).count) questions")
                                    .font(.caption).foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
                        }
                        .padding(14)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(catTint(cat).opacity(0.25)))
                    }
                    .buttonStyle(.taptPress)
                }
            }
            .padding()
        }
    }

    private func catTint(_ c: TriviaCategory) -> Color {
        switch c {
        case .mixed: Brand.gold
        case .beer: Brand.copper
        case .popCulture: Brand.hop
        case .funFacts: Brand.gold
        case .general: Brand.copper
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Q\(index + 1) / \(order.count)").font(.system(.subheadline, design: .monospaced)).foregroundStyle(Brand.muted)
                Spacer()
                Label("\(score)", systemImage: "star.fill").foregroundStyle(Brand.gold)
                if streak >= 2 { Label("\(streak)", systemImage: "flame.fill").foregroundStyle(Brand.copper) }
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))

            Text(q.q).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)

            VStack(spacing: 12) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, opt in
                    Button { choose(i) } label: {
                        HStack {
                            Text(opt).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Brand.text).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            if let s = selected {
                                if i == q.correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.hop) }
                                else if i == s { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.copper) }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(optionBackground(i), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.malt.opacity(0.12)))
                    }
                    .buttonStyle(.taptPress)
                    .disabled(selected != nil)
                }
            }

            if selected != nil {
                Text(q.why).font(.subheadline).foregroundStyle(Brand.muted)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                Button(index + 1 < order.count ? "Next" : "See results") { next() }
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Brand.malt)
            }
            Spacer()
        }
        .padding()
        .animation(.snappy, value: selected)
    }

    private var results: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("\(score) / \(order.count)").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(Brand.gold)
            Text(verdict).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).multilineTextAlignment(.center).padding(.horizontal, 24)
            Spacer()
            Button("Play again") { restart() }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt)
        }
        .padding(28)
    }

    private var verdict: String {
        switch Double(score) / Double(max(order.count, 1)) {
        case 0.9...: "Genius level. Take a bow."
        case 0.6..<0.9: "Sharp. You know your stuff."
        case 0.3..<0.6: "Getting there. Run it back."
        default: "Everyone starts somewhere. Cheers."
        }
    }

    private func optionBackground(_ i: Int) -> Color {
        guard let s = selected else { return Brand.surface }
        if i == q.correct { return Brand.hop.opacity(0.25) }
        if i == s { return Brand.copper.opacity(0.22) }
        return Brand.surface
    }

    private func choose(_ i: Int) {
        guard selected == nil else { return }
        selected = i
        if i == q.correct { score += 1; streak += 1; Haptic.success() } else { streak = 0; Haptic.tap() }
    }

    private func next() {
        Haptic.tap()
        if index + 1 < order.count { index += 1; selected = nil } else { finished = true; Haptic.celebrate() }
    }

    private func restart() {
        let selectedCategory = category ?? .mixed
        order = Self.pickQuestions(
            limit: questionLimit,
            category: selectedCategory,
            seed: title == "Daily 5" ? Self.dailySeed(category: selectedCategory) : nil
        )
        index = 0; selected = nil; score = 0; streak = 0; finished = false
    }

    private static func pickQuestions(
        limit: Int?,
        category: TriviaCategory,
        seed: String? = nil
    ) -> [TriviaQuestion] {
        TriviaData.round(limit: limit, category: category, seed: seed)
    }

    private static func dailySeed(category: TriviaCategory) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(category.rawValue)"
    }
}
