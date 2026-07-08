import SwiftUI
import Supabase

/// App-wide auth state, driven by Supabase.
@MainActor
@Observable
final class Session {
    var user: User?
    var isLoading = true
    var authError: String?

    /// Hydrate the current session, then follow auth changes for the app's lifetime.
    func start() async {
        user = try? await Supa.client.auth.session.user
        isLoading = false
        for await change in Supa.client.auth.authStateChanges {
            user = change.session?.user
        }
    }

    func signInWithOAuth(_ provider: Provider) async {
        authError = nil
        do {
            try await Supa.client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: Supa.authRedirectURL
            )
        } catch {
            authError = error.localizedDescription
        }
    }

    nonisolated func handleOAuthCallback(_ url: URL) {
        Supa.client.auth.handle(url)
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
    }
}
