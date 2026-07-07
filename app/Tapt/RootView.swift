import SwiftUI

/// The tab shell. Beer-culture labels, brand tint.
struct RootView: View {
    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
            CellarView()
                .tabItem { Label("Cellar", systemImage: "square.stack.3d.up") }
            NearYouView()
                .tabItem { Label("On Tap", systemImage: "mappin.and.ellipse") }
            GamesView()
                .tabItem { Label("Games", systemImage: "die.face.5") }
        }
    }
}

#Preview { RootView().tint(Brand.accent) }
