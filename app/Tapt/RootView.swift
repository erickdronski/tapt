import SwiftUI

/// The tab shell. Beer-culture labels, brand tint.
struct RootView: View {
    var body: some View {
        TabView {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "chart.line.uptrend.xyaxis") }
            ScanView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            CellarView()
                .tabItem { Label("Cellar", systemImage: "square.stack.3d.up") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
            ProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
        }
    }
}

#Preview { RootView().tint(Brand.accent) }
