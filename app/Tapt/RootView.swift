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
            #endif
        }
    }
}

#Preview { RootView().tint(Brand.accent) }
