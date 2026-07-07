import SwiftUI

/// The "Discover" tab: a hub for the fun, secondary surfaces (Beer School + Games).
struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DiscoverTile(title: "Beer School",
                                 subtitle: "How it's made, the lingo, the history, the legends.",
                                 icon: "graduationcap.fill", tint: Brand.gold) { LearnView() }
                    DiscoverTile(title: "Games",
                                 subtitle: "Trivia and table games for the bar. All free.",
                                 icon: "die.face.5.fill", tint: Brand.hop) { GamesView() }
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Discover")
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
        }
        .buttonStyle(.plain)
    }
}
