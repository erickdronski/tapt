import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()

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
            .task { await session.start() }
        }
    }
}
