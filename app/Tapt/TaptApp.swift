import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("onboardedUserIDs") private var onboardedUserIDs = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoading {
                    ProgressView().tint(Brand.accent)
                } else if session.user == nil {
                    SignInView()
                } else if currentUserOnboarded {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .tint(Brand.accent)
            .environment(session)
            .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme ?? nil)
            .task { await session.start() }
            .onOpenURL { url in
                session.handleOAuthCallback(url)
            }
        }
    }

    private var currentUserOnboarded: Bool {
        guard let id = session.user?.id.uuidString else { return false }
        return Set(onboardedUserIDs.split(separator: ",").map(String.init)).contains(id)
    }
}
