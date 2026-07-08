import SwiftUI

private let deckPrompts = [
    "Categories: pick a beer style. Go around naming one. First to blank picks the next style.",
    "Never have I ever. Say one. Anyone who has, shares the story or passes.",
    "Cheers to the person on your right.",
    "Make a rule. Everyone follows it until the next rule card.",
    "Most likely to. Everyone points. Most points gives a toast.",
    "Thumb master. Put a thumb on the table. Last to notice draws next.",
    "Name three hop varieties in ten seconds, or ask the table for help.",
    "Toast. Everyone raise a glass and say cheers in a new language.",
    "Truth or pass. Someone asks you a question.",
    "Pick a tasting buddy. Both name one flavor note in the next pour.",
    "Quick trivia: what does IBU measure? Wrong answer asks for a hint.",
    "Categories: name a country famous for beer. First to blank picks the next category.",
    "Silent table. No talking until the next card. Slip up, draw next.",
    "You are the DJ. Pick the next song.",
    "Group cheers. Everyone clinks. Skal.",
]

/// The Tapt Deck: a house-built card game for the table. NA-friendly by default.
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
                Text("NA counts. Water counts. Play safe.")
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
