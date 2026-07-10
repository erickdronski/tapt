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
                        caption: "The Beer Superapp",
                        icon: "sparkles",
                        tint: Brand.gold
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)

                    quickPlayRail

                    DiscoverTile(title: "Leaderboards",
                                 subtitle: "Top beers, top tasters, top styles, powered by real votes and pours.",
                                 icon: "trophy.fill", tint: Brand.gold) { LeaderboardsView() }

                    TaptCollapse(title: "Community",
                                 subtitle: "Tonight's feed and your beer circle",
                                 icon: "person.3.fill", tint: Brand.copper, startExpanded: true) {
                        DiscoverTile(title: "Tonight",
                                     subtitle: "Live beer heat, friend pours, your taste graph.",
                                     icon: "flame.fill", tint: Brand.copper) { TonightView() }
                        DiscoverTile(title: "Find friends",
                                     subtitle: "Follow your crew. Their pours light up your feed.",
                                     icon: "person.badge.plus", tint: Brand.hop) { FindFriendsView() }
                    }

                    TaptCollapse(title: "Learn & play",
                                 subtitle: "Flights, Beer School, and the games library",
                                 icon: "graduationcap.fill", tint: Brand.hop) {
                        DiscoverTile(title: "Flights",
                                     subtitle: "Guided tasting quests that reward curiosity.",
                                     icon: "map.fill", tint: Brand.gold) { FlightsView() }
                        DiscoverTile(title: "Beer School",
                                     subtitle: "How it's made, the lingo, the history, the legends.",
                                     icon: "graduationcap.fill", tint: Brand.hop) { LearnView() }
                        DiscoverTile(title: "Games",
                                     subtitle: "Trivia, table games, Beer Olympics. All free.",
                                     icon: "die.face.5.fill", tint: Brand.copper) { GamesView() }
                    }

                    TaptCollapse(title: "For breweries & bars",
                                 subtitle: "Free tools, featured placement, partnerships",
                                 icon: "storefront.fill", tint: Brand.copper) {
                        DiscoverTile(title: "Partner with Tapt",
                                     subtitle: "Get featured to beer fans near you.",
                                     icon: "storefront.fill", tint: Brand.copper) { PartnerInquiryView() }
                    }

                    NewsletterCard()
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

    private var quickPlayRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                QuickPlayTile(title: "Darts", icon: "scope", tint: Brand.copper) {
                    DartsGame()
                }
                QuickPlayTile(title: "Connect 4", icon: "circle.grid.3x3.fill", tint: Brand.gold) {
                    ConnectFourGame()
                }
                QuickPlayTile(title: "Daily 5", icon: "calendar.badge.clock", tint: Brand.hop) {
                    TriviaGame(title: "Daily 5", questionLimit: 5, category: .mixed)
                }
                QuickPlayTile(title: "Trivia", icon: "brain.head.profile", tint: Brand.gold) {
                    TriviaGame()
                }
                QuickPlayTile(title: "Deck", icon: "rectangle.on.rectangle.angled", tint: Brand.hop) {
                    CardDeckGame()
                }
                QuickPlayTile(title: "Pong", icon: "circle.grid.cross.fill", tint: Brand.gold) {
                    BeerPongGame()
                }
                QuickPlayTile(title: "Flip Cup", icon: "cup.and.saucer.fill", tint: Brand.hop) {
                    FlipCupGame()
                }
                QuickPlayTile(title: "Olympics", icon: "trophy.fill", tint: Brand.gold) {
                    BeerOlympicsView()
                }
                QuickPlayTile(title: "Beer Night", icon: "person.3.fill", tint: Brand.copper) {
                    BreweryModeView()
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

private struct QuickPlayTile<Destination: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Brand.malt)
                    .frame(width: 46, height: 46)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12))
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 104, height: 94)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.18)))
        }
        .buttonStyle(.taptPress)
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
        .buttonStyle(.taptPress)
    }
}
