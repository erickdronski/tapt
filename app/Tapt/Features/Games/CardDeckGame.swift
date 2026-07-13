import SwiftUI

// Mixed party prompts, not just beer, so anyone at the table can play. Swipe or
// tap to draw. No alcohol instructions; challenges use points, stories, or dares.
private let deckPrompts = [
    // party / social
    "Most likely to. Everyone points. Most points gives a toast.",
    "Never have I ever. Say one. Anyone who has, shares the story or takes the penalty.",
    "Make a rule. Everyone follows it until the next rule card.",
    "Thumb master. Put a thumb on the table. Last to notice draws next.",
    "Truth or dare. The table picks which.",
    "Two truths and a lie. The table guesses.",
    "Silent table. No talking until the next card. Slip up, you draw.",
    "You are the DJ. Pick the next song, no skips.",
    "Best impression. Do your best celebrity impression, table rates it.",
    "Categories: name a country. First to blank picks the next category.",
    "Accent challenge. Say the next sentence in a random accent.",
    "Compliment battle. Give the person on your left a real compliment.",
    // pop culture
    "Name three movies with the same actor in ten seconds, or ask for help.",
    "Hum a song. First to guess it is safe, you draw next.",
    "Finish the lyric. Someone starts a famous line, next person finishes it.",
    "Name a TV bar (Cheers, Paddy's, MacLaren's...). Blank and you draw next.",
    // beer-flavored (still light)
    "Cheers to the person on your right in a new language.",
    "Pick a tasting buddy. Both name one flavor note in the next pour.",
    "Quick trivia: what does IBU measure? Wrong answer asks the table.",
    "Group cheers. Everyone clinks. Skal!",
    "Categories: name a country famous for beer. First to blank picks next.",
    "Name a beer style in five seconds, or the table picks your penalty.",
]

/// The Tapt Deck: a house-built party card game. Swipe or tap to draw. Mixed
/// topics, NA-friendly by default.
struct CardDeckGame: View {
    @State private var order = deckPrompts.shuffled()
    @State private var index = 0
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                card
                    .offset(drag)
                    .rotationEffect(.degrees(Double(drag.width / 22)))
                    .gesture(
                        DragGesture()
                            .onChanged { drag = $0.translation }
                            .onEnded { v in
                                if abs(v.translation.width) > 90 {
                                    Haptic.tap()
                                    withAnimation(.easeIn(duration: 0.18)) {
                                        drag = CGSize(width: v.translation.width > 0 ? 700 : -700, height: v.translation.height)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                        advance(); drag = .zero
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { drag = .zero }
                                }
                            }
                    )
                Spacer()
                Button("Draw next") { Haptic.tap(); withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { advance() } }
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Brand.malt)
                    .buttonStyle(.taptPress)
                Text("Swipe the card or tap draw. NA counts, water counts, play safe.")
                    .font(.caption2).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Tapt Deck")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Brand.gold)
            Text(order[index])
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity, minHeight: 280)
        .background(
            LinearGradient(colors: [Brand.surface, Brand.haze.opacity(0.7)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Brand.gold.opacity(0.25), lineWidth: 1.2))
        .shadow(color: Brand.malt.opacity(0.18), radius: 16, y: 10)
        .id(index)
        .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
    }

    private func advance() {
        if index + 1 < order.count { index += 1 } else { order = deckPrompts.shuffled(); index = 0 }
    }
}
