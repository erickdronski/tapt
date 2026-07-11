import SwiftUI

/// The tab shell. Beer-culture labels, brand tint.
struct RootView: View {
    @State private var selection = 0

    var body: some View {
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
        .onAppear {
            #if targetEnvironment(simulator)
            if let t = ProcessInfo.processInfo.environment["TAPT_START_TAB"], let i = Int(t) { selection = i }
            if ProcessInfo.processInfo.environment["TAPT_SHARE_PREVIEW"] == "1" { showSharePreview = true }
            if ProcessInfo.processInfo.environment["TAPT_BEER_PREVIEW"] == "1" { showBeerPreview = true }
            #endif
        }
        .sheet(isPresented: $showBeerPreview) {
            NavigationStack { BeerDetailView(beerId: "5f176aee-a946-4c4c-9d0f-daed02e10f62") }
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

    @State private var showSharePreview = false
    @State private var showBeerPreview = false
}

#Preview { RootView().tint(Brand.accent) }
