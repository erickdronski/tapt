import SwiftUI

/// Beer Night Mode: pass-the-phone group play. Round roulette + the table games.
struct BreweryModeView: View {
    @State private var players = 4
    @State private var picked: Int?
    @State private var spinning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Everyone at the table, pass the phone. Games for the whole crew, with NA-friendly play built in.")
                    .font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal)

                VStack(spacing: 14) {
                    Text("Pick the next captain").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                    Stepper("Seats: \(players)", value: $players, in: 2...12).padding(.horizontal, 40)
                    ZStack {
                        Circle().stroke(Brand.haze, lineWidth: 10).frame(width: 150, height: 150)
                        Text(picked.map { "Seat \($0)" } ?? "?")
                            .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Brand.gold)
                            .contentTransition(.numericText())
                    }
                    Button(spinning ? "Spinning..." : "Spin") { spin() }
                        .font(.system(.headline, design: .rounded)).padding(.horizontal, 34).padding(.vertical, 12)
                        .background(Brand.gold, in: Capsule()).foregroundStyle(Brand.malt).disabled(spinning)
                }
                .padding(20).frame(maxWidth: .infinity)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))

                NavigationLink { CardDeckGame() } label: {
                    tile("Tapt Deck", "Draw a card, play the table", "rectangle.on.rectangle.angled", Brand.hop)
                }.buttonStyle(.plain)
                NavigationLink { BeerPongGame() } label: {
                    tile("Beer Pong", "Flick to throw, clear the rack", "circle.grid.cross.fill", Brand.gold)
                }.buttonStyle(.plain)
                NavigationLink { BarGamesView(starting: .flipCup) } label: {
                    tile("Flip Cup", "Fast hands, best times, table streaks", "cup.and.saucer.fill", Brand.hop)
                }.buttonStyle(.plain)
                NavigationLink { TriviaGame() } label: {
                    tile("Beer Trivia", "Miss one, pass the phone", "brain.head.profile", Brand.copper)
                }.buttonStyle(.plain)
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Beer Night Mode")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Brand.malt)
                .frame(width: 52, height: 52).background(tint, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
        }
        .padding(14).frame(maxWidth: .infinity).background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func spin() {
        spinning = true
        Task { @MainActor in
            for _ in 0..<14 {
                withAnimation { picked = Int.random(in: 1...players) }
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            withAnimation { picked = Int.random(in: 1...players) }
            spinning = false
        }
    }
}
