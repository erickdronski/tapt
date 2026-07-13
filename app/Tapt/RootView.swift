import SwiftUI

/// The tab shell. Beer-culture labels, brand tint.
struct RootView: View {
    @Environment(Session.self) private var session
    @State private var selection = 0
    @State private var pendingPartnerVenueId: String?
    @State private var pendingBeerDetailId: String?

    var body: some View {
        tabShell
        .onAppear {
            #if targetEnvironment(simulator)
            if let t = ProcessInfo.processInfo.environment["TAPT_START_TAB"], let i = Int(t) { selection = i }
            if ProcessInfo.processInfo.environment["TAPT_SHARE_PREVIEW"] == "1" { showSharePreview = true }
            if ProcessInfo.processInfo.environment["TAPT_BEER_PREVIEW"] == "1" { showBeerPreview = true }
            if ProcessInfo.processInfo.environment["TAPT_GAME_PREVIEW"] == "1" { showGamePreview = true }
            if ProcessInfo.processInfo.environment["TAPT_CATALOG_PREVIEW"] == "1" { showCatalogPreview = true }
            if ProcessInfo.processInfo.environment["TAPT_MAP_PREVIEW"] == "1" { showMapPreview = true }
            if ProcessInfo.processInfo.environment["TAPT_GAMES_PREVIEW"] == "1" { showGamesPreview = true }
            #endif
            if pendingPartnerVenueId == nil {
                pendingPartnerVenueId = session.consumePendingPartnerMenu()
            }
            if pendingBeerDetailId == nil {
                pendingBeerDetailId = session.consumePendingBeerDetail()
            }
        }
        .sheet(item: $pendingPartnerVenueId) { venueId in
            PartnerMenuSheet(venueId: venueId)
        }
        .sheet(item: $pendingBeerDetailId) { beerId in
            NavigationStack { BeerDetailView(beerId: beerId) }
        }
        .sheet(isPresented: $showBeerPreview) {
            NavigationStack { BeerDetailView(beerId: "8c25e595-f6fc-425c-ad11-b3b8acf9bb9d") }
        }
        .fullScreenCover(isPresented: $showGamePreview) {
            NavigationStack {
                BeerPongGame()
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { showGamePreview = false } } }
            }
        }
        .sheet(isPresented: $showCatalogPreview) {
            NavigationStack { CatalogView() }
        }
        .sheet(isPresented: $showMapPreview) {
            NavigationStack { NearYouView() }
        }
        .sheet(isPresented: $showGamesPreview) {
            NavigationStack { GamesView() }
        }
        .sheet(isPresented: $showSharePreview) {
            NavigationStack {
                ScrollView {
                    CardShareView(pour: PourCard(
                        beer: "Guinness Draught", brewery: "Guinness", style: "Irish Stout",
                        score: 88, user: "you", abv: "4.2%", place: "The Long Hall, Dublin",
                        rating: 5,
                        imageUrl: "https://images.openfoodfacts.org/images/products/500/021/310/1223/front_fr.60.full.jpg",
                        country: "Ireland"))
                    .padding(.vertical)
                }
                .navigationTitle("Share your pour").navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private var tabShell: some View {
        if session.isGuest {
            TabView(selection: $selection) {
                NavigationStack { CatalogView() }
                    .tag(0)
                    .tabItem { Label("Catalog", systemImage: "books.vertical.fill") }
                NearYouView()
                    .tag(1)
                    .tabItem { Label("Near You", systemImage: "map.fill") }
                DiscoverView()
                    .tag(2)
                    .tabItem { Label("Discover", systemImage: "sparkles") }
                ProfileView()
                    .tag(3)
                    .tabItem { Label("You", systemImage: "person.crop.circle") }
            }
        } else {
            TabView(selection: $selection) {
                ExploreView()
                    .tag(0)
                    .tabItem { Label("Home", systemImage: "house.fill") }
                BeerMarketView()
                    .tag(1)
                    .tabItem { Label("Market", systemImage: "chart.line.uptrend.xyaxis") }
                CellarView()
                    .tag(2)
                    .tabItem { Label("Cellar", systemImage: "square.stack.3d.up") }
                DiscoverView()
                    .tag(3)
                    .tabItem { Label("Discover", systemImage: "sparkles") }
                ProfileView()
                    .tag(4)
                    .tabItem { Label("You", systemImage: "person.crop.circle") }
            }
        }
    }

    @State private var showSharePreview = false
    @State private var showBeerPreview = false
    @State private var showGamePreview = false
    @State private var showCatalogPreview = false
    @State private var showMapPreview = false
    @State private var showGamesPreview = false
}

#Preview { RootView().tint(Brand.accent) }
