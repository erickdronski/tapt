import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()
    @State private var serverOnboarded: [String: Bool] = [:]
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("onboardedUserIDs") private var onboardedUserIDs = ""
    @AppStorage("legalAgeConfirmed") private var legalAgeConfirmed = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !legalAgeConfirmed && !Self.screenshotMode {
                    AgeGateView { legalAgeConfirmed = true }
                } else if Self.screenshotMode {
                    RootView()
                } else if session.isLoading {
                    ProgressView().tint(Brand.accent)
                } else if session.user == nil && !session.isGuest {
                    SignInView()
                } else if session.isGuest {
                    RootView()
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
            .task {
                if !Self.screenshotMode { await session.start() }
            }
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
        var answer = await ProfileService.isOnboarded(userId: uid)
        if answer == nil {
            // Unknown (network blip on a fresh install/cold start). Give it one
            // more shot before deciding anything.
            try? await Task.sleep(for: .seconds(2))
            answer = await ProfileService.isOnboarded(userId: uid)
        }
        switch answer {
        case true?:
            markLocallyOnboarded(id)
        case false?:
            serverOnboarded[id] = false
        case nil:
            // Still unknown: NEVER force re-onboarding on a network failure --
            // completing it again would overwrite the user's saved region,
            // styles, and consents. Let them into the app; preferences remain
            // editable from Profile, and the next launch re-checks.
            markLocallyOnboarded(id)
        }
    }

    private func markLocallyOnboarded(_ id: String) {
        var ids = Set(onboardedUserIDs.split(separator: ",").map(String.init))
        ids.insert(id)
        onboardedUserIDs = ids.sorted().joined(separator: ",")
        serverOnboarded[id] = true
    }

    private static var screenshotMode: Bool {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["TAPT_SCREENSHOT_MODE"] == "1"
        #else
        false
        #endif
    }
}
