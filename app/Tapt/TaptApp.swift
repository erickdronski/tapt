import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()
    @State private var serverOnboarded: [String: Bool] = [:]
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("onboardedUserIDs") private var onboardedUserIDs = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoading {
                    ProgressView().tint(Brand.accent)
                } else if session.user == nil {
                    SignInView()
                } else if let id = session.user?.id.uuidString {
                    if localOnboarded(id) {
                        RootView()
                    } else if serverOnboarded[id] == false {
                        OnboardingView()
                    } else {
                        // Not onboarded locally (e.g. reinstall / new device):
                        // confirm against the server before making them redo it.
                        ProgressView().tint(Brand.accent)
                            .task { await checkServerOnboarded(id) }
                    }
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

    private func localOnboarded(_ id: String) -> Bool {
        Set(onboardedUserIDs.split(separator: ",").map(String.init)).contains(id)
    }

    private func checkServerOnboarded(_ id: String) async {
        guard let uid = session.user?.id else { return }
        let ok = await ProfileService.isOnboarded(userId: uid)
        if ok {
            var ids = Set(onboardedUserIDs.split(separator: ",").map(String.init))
            ids.insert(id)
            onboardedUserIDs = ids.sorted().joined(separator: ",")
        }
        serverOnboarded[id] = ok
    }
}
