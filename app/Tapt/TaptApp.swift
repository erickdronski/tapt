import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoading {
                    ProgressView().tint(Brand.accent)
                } else if session.user != nil {
                    RootView()
                } else {
                    SignInView()
                }
            }
            .tint(Brand.accent)
            .environment(session)
            .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme ?? nil)
            .task { await session.start() }
        }
    }
}
