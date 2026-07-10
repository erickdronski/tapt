import SwiftUI

/// Games hub. Presented inside Discover's NavigationStack.
struct GamesView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink { DartsGame() } label: {
                    GameTile(title: "Darts", subtitle: "Flick to throw. Real aim, real scatter, pass-and-play.", icon: "scope", tint: Brand.copper, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { ConnectFourGame() } label: {
                    GameTile(title: "Connect 4", subtitle: "Gravity drops, four in a row, table bragging rights.", icon: "circle.grid.3x3.fill", tint: Brand.gold, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { TriviaGame(title: "Daily 5", questionLimit: 5) } label: {
                    GameTile(title: "Daily 5", subtitle: "A quick five-question run from the beer world.", icon: "calendar.badge.clock", tint: Brand.hop, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { TriviaGame() } label: {
                    GameTile(title: "Beer Trivia", subtitle: "How deep does your knowledge pour? Free, endless.", icon: "brain.head.profile", tint: Brand.gold, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { CardDeckGame() } label: {
                    GameTile(title: "Tapt Deck", subtitle: "A house-built card game for the table. Free.", icon: "rectangle.on.rectangle.angled", tint: Brand.hop, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { BeerPongGame() } label: {
                    GameTile(title: "Beer Pong", subtitle: "Flick to throw. Real arc physics, clear the rack, pass-and-play.", icon: "circle.grid.cross.fill", tint: Brand.gold, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { BarGamesView(starting: .flipCup) } label: {
                    GameTile(title: "Flip Cup", subtitle: "Reaction-time table play with streaks and best times.", icon: "cup.and.saucer.fill", tint: Brand.hop, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { BarGamesView(starting: .quarters) } label: {
                    GameTile(title: "Quarters", subtitle: "Dial in the bounce and chase the clean center.", icon: "circle.hexagongrid.fill", tint: Brand.copper, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { BreweryModeView() } label: {
                    GameTile(title: "Beer Night Mode", subtitle: "Round roulette plus games for the whole table.", icon: "person.3.fill", tint: Brand.copper, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { BeerOlympicsView() } label: {
                    GameTile(title: "Beer Olympics", subtitle: "Teams, events, medal table, champion. The big one.", icon: "trophy.fill", tint: Brand.gold, ready: true)
                }
                .buttonStyle(.taptPress)
                NavigationLink { GameNightGuidesView() } label: {
                    GameTile(title: "Game Night Guides", subtitle: "Classic card + no-prop games, explained in a minute. Real deck or no props.", icon: "book.fill", tint: Brand.hop, ready: true)
                }
                .buttonStyle(.taptPress)

                Label(GameGuidesData.safetyLine, systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GameTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let ready: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Brand.malt)
                .frame(width: 60, height: 60)
                .background(tint, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                Text(subtitle).font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            if ready {
                Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            } else {
                Text("SOON").font(.caption2.weight(.bold)).foregroundStyle(Brand.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Brand.haze, in: Capsule())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
        .opacity(ready ? 1 : 0.75)
    }
}

// MARK: - Beer Trivia (playable)
struct TriviaGame: View {
    let title: String
    let questionLimit: Int?
    @State private var order: [TriviaQuestion]
    @State private var index = 0
    @State private var selected: Int?
    @State private var score = 0
    @State private var streak = 0
    @State private var finished = false

    private var q: TriviaQuestion { order[index] }

    init(title: String = "Beer Trivia", questionLimit: Int? = nil) {
        self.title = title
        self.questionLimit = questionLimit
        _order = State(initialValue: Self.pickQuestions(limit: questionLimit))
    }

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            if finished { results } else { question }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
        switch Double(score) / Double(order.count) {
        case 0.9...: "Certified beer nerd. Whale-hunter status."
        case 0.6..<0.9: "Solid pour. You know your stuff."
        case 0.3..<0.6: "Getting there. Keep tasting."
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
        if i == q.correct { score += 1; streak += 1 } else { streak = 0 }
    }

    private func next() {
        if index + 1 < order.count { index += 1; selected = nil } else { finished = true }
    }

    private func restart() {
        order = Self.pickQuestions(limit: questionLimit); index = 0; selected = nil; score = 0; streak = 0; finished = false
    }

    private static func pickQuestions(limit: Int?) -> [TriviaQuestion] {
        let shuffled = TriviaData.questions.shuffled()
        guard let limit else { return shuffled }
        return Array(shuffled.prefix(max(1, min(limit, shuffled.count))))
    }
}
