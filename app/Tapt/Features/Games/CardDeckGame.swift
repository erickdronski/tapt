import SwiftUI

private let deckPrompts = [
    "Waterfall. Everyone starts, no one stops before the person to your left.",
    "Categories: pick a beer style. Go around naming one. First to blank sips.",
    "Never have I ever. Say one. Anyone who has, sips.",
    "Cheers to the person on your right.",
    "Make a rule. Everyone follows it until the next rule card.",
    "Most likely to. Everyone points. Most points sips.",
    "Thumb master. Put a thumb on the table. Last to notice sips.",
    "Name three hop varieties in ten seconds, or sip.",
    "Toast. Everyone raise a glass and say cheers in a new language.",
    "Truth or sip. Someone asks you a question.",
    "Pick a drinking buddy. You match sips until the next card.",
    "Quick trivia: what does IBU measure? Wrong answer sips.",
    "Categories: name a country famous for beer. First to blank sips.",
    "Silent table. No talking until the next card. Slip up, sip.",
    "You are the DJ. Pick the next song or sip.",
    "Group cheers. Everyone clinks. Skal.",
]

/// The Tapt Deck: a house-built card game for the table. Sips are optional and NA-friendly.
struct CardDeckGame: View {
    @State private var order = deckPrompts.shuffled()
    @State private var index = 0

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                card
                Spacer()
                Button("Draw next") { draw() }
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Brand.malt)
                Text("Sip = your call. Water counts. Play safe.")
                    .font(.caption2).foregroundStyle(Brand.muted)
            }
            .padding()
        }
        .navigationTitle("Tapt Deck")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.largeTitle).foregroundStyle(Brand.gold)
            Text(order[index])
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 260)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.malt.opacity(0.12)))
        .id(index)
        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
    }

    private func draw() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if index + 1 < order.count { index += 1 } else { order = deckPrompts.shuffled(); index = 0 }
        }
    }
}
