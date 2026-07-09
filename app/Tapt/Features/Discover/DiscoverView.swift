import SwiftUI

/// The "Discover" tab: a hub for the fun, secondary surfaces (Beer School + Games).
struct DiscoverView: View {
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TaptHeroPanel(
                        title: "Beer culture mode",
                        subtitle: "Run guided flights, learn styles, play table games, and turn every pour into a better beer night.",
                        metric: "PLAY",
                        caption: "Flights + school + games",
                        icon: "sparkles",
                        tint: Brand.gold
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)

                    DiscoverTile(title: "Flights",
                                 subtitle: "Guided tasting quests that reward curiosity, not volume.",
                                 icon: "map.fill", tint: Brand.gold) { FlightsView() }
                    DiscoverTile(title: "Beer School",
                                 subtitle: "How it's made, the lingo, the history, the legends.",
                                 icon: "graduationcap.fill", tint: Brand.hop) { LearnView() }
                    DiscoverTile(title: "Games",
                                 subtitle: "Trivia and table games for the bar. All free.",
                                 icon: "die.face.5.fill", tint: Brand.copper) { GamesView() }
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Discover")
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true }
            }
        }
    }
}

private struct DiscoverTile<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundStyle(Brand.malt)
                    .frame(width: 64, height: 64)
                    .background(tint, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                    Text(subtitle).font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Brand.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
