import SwiftUI

@main
struct TaptApp: App {
    @State private var session = Session()
    @State private var serverOnboarded: [String: Bool] = [:]
    @State private var onboardingCheckFailed: Set<String> = []
    @State private var onboardingBypassedForSession: Set<String> = []
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
                    if localOnboarded(id) || onboardingBypassedForSession.contains(id) {
                        RootView()
                    } else if serverOnboarded[id] == false {
                        OnboardingView()
                    } else if onboardingCheckFailed.contains(id) {
                        onboardingRecovery(id)
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
            onboardingCheckFailed.remove(id)
            markLocallyOnboarded(id)
        case false?:
            onboardingCheckFailed.remove(id)
            serverOnboarded[id] = false
        case nil:
            // Unknown is not the same as complete. Keep this recoverable and do
            // not persist a false completion marker across future launches.
            onboardingCheckFailed.insert(id)
        }
    }

    private func onboardingRecovery(_ id: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't check your setup", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Reconnect and retry. You can also continue for this session without changing your saved setup.")
        } actions: {
            Button("Retry") {
                onboardingCheckFailed.remove(id)
            }
            .buttonStyle(.borderedProminent)

            Button("Continue for now") {
                onboardingCheckFailed.remove(id)
                onboardingBypassedForSession.insert(id)
            }
            .buttonStyle(.bordered)
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
