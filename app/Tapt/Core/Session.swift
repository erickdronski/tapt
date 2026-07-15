import SwiftUI
import Supabase
import AuthenticationServices

/// App-wide auth state, driven by Supabase.
@MainActor
@Observable
final class Session {
    private static let pendingPartnerVenueKey = "pendingPartnerVenueId"
    private static let pendingBeerDetailKey = "pendingBeerDetailId"
    private static let pendingBeerVoteKey = "pendingBeerVote"

    private struct PendingBeerVote: Codable {
        let beerId: String
        let value: Int
        let createdAt: Date
    }

    var user: User?
    var isLoading = true
    var authError: String?
    var isGuest = UserDefaults.standard.bool(forKey: "guestMode")

    /// Hydrate the current session, then follow auth changes for the app's lifetime.
    func start() async {
        do {
            user = try await Supa.client.auth.session.user
        } catch let error as AuthError {
            // Only a definitively-missing session means signed out. Anything else
            // (expired token whose refresh failed on a flaky cold start, GoTrue
            // hiccup under launch load) must NOT bounce a signed-in user to the
            // sign-in screen: keep the stored session's user and let the SDK's
            // auto-refresh heal the token once the network is back.
            if case .sessionMissing = error {
                user = nil
            } else {
                user = Supa.client.auth.currentSession?.user
            }
        } catch {
            user = Supa.client.auth.currentSession?.user
        }
        if user != nil { setGuest(false) }
        isLoading = false
        for await change in Supa.client.auth.authStateChanges {
            // Account deletion ends the session through this stream (not
            // signOut()), so per-account defaults are cleared here too.
            if change.event == .signedOut || change.event == .userDeleted {
                Self.clearPerAccountDefaults()
            }
            user = change.session?.user
            if user != nil { setGuest(false) }
        }
    }

    /// Public catalog, map, education, and games work without an account. Writes
    /// remain guarded by the existing authenticated RLS policies.
    func continueAsGuest() {
        authError = nil
        setGuest(true)
    }

    func endGuestSession() {
        setGuest(false)
    }

    /// Keep a scanned partner menu intact while a guest signs in. Only a valid
    /// UUID is persisted, and it is consumed once the authenticated shell opens.
    func deferPartnerMenu(venueId: String) {
        guard UUID(uuidString: venueId) != nil else { return }
        UserDefaults.standard.set(venueId, forKey: Self.pendingPartnerVenueKey)
    }

    func consumePendingPartnerMenu() -> String? {
        guard let venueId = UserDefaults.standard.string(forKey: Self.pendingPartnerVenueKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingPartnerVenueKey)
        return UUID(uuidString: venueId) == nil ? nil : venueId
    }

    func deferBeerDetail(beerId: String) {
        guard UUID(uuidString: beerId) != nil else { return }
        UserDefaults.standard.set(beerId, forKey: Self.pendingBeerDetailKey)
    }

    func consumePendingBeerDetail() -> String? {
        guard let beerId = UserDefaults.standard.string(forKey: Self.pendingBeerDetailKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: Self.pendingBeerDetailKey)
        return UUID(uuidString: beerId) == nil ? nil : beerId
    }

    /// Preserve the exact thumb a guest tapped while auth takes over the screen.
    /// The short expiry prevents an abandoned choice from being replayed later.
    func deferBeerVote(beerId: String, value: Int) {
        guard UUID(uuidString: beerId) != nil, value == 1 || value == -1 else { return }
        let vote = PendingBeerVote(beerId: beerId, value: value, createdAt: Date())
        guard let data = try? JSONEncoder().encode(vote) else { return }
        UserDefaults.standard.set(data, forKey: Self.pendingBeerVoteKey)
    }

    func pendingBeerVote(for beerId: String) -> Int? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingBeerVoteKey) else {
            return nil
        }
        guard let vote = try? JSONDecoder().decode(PendingBeerVote.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: Self.pendingBeerVoteKey)
            return nil
        }
        guard Date().timeIntervalSince(vote.createdAt) <= 30 * 60 else {
            UserDefaults.standard.removeObject(forKey: Self.pendingBeerVoteKey)
            return nil
        }
        return vote.beerId == beerId ? vote.value : nil
    }

    func clearPendingBeerVote(for beerId: String) {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingBeerVoteKey),
              let vote = try? JSONDecoder().decode(PendingBeerVote.self, from: data),
              vote.beerId == beerId else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingBeerVoteKey)
    }

    func signInWithOAuth(_ provider: Provider) async {
        authError = nil
        do {
            try await Supa.client.auth.signInWithOAuth(
                provider: provider,
                redirectTo: Supa.authRedirectURL
            )
        } catch {
            // Backing out of the provider sheet is not an error, don't scare the
            // user with a red message (mirrors the Sign in with Apple path).
            if isCancellation(error) { return }
            authError = error.localizedDescription
        }
    }

    /// True when the user simply dismissed/cancelled the web auth sheet.
    private func isCancellation(_ error: Error) -> Bool {
        if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
            return true
        }
        let ns = error as NSError
        if ns.domain == ASWebAuthenticationSessionError.errorDomain,
           ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return true
        }
        // Supabase/URLSession cancellations surface as NSURLErrorCancelled too.
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        return false
    }

    func sendEmailSignInLink(to email: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            authError = "Enter your email address."
            return false
        }

        authError = nil
        do {
            try await Supa.client.auth.signInWithOTP(
                email: normalizedEmail,
                redirectTo: Supa.authRedirectURL
            )
            return true
        } catch {
            let detail = error.localizedDescription
            if detail.localizedCaseInsensitiveContains("rate limit") || detail.contains("429") {
                authError = "Too many sign-in emails were requested. Wait a few minutes, then try again."
            } else {
                authError = detail
            }
            return false
        }
    }

    func signInWithPassword(email: String, password: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), !password.isEmpty else {
            authError = "Enter your email address and password."
            return false
        }

        authError = nil
        do {
            try await Supa.client.auth.signIn(email: normalizedEmail, password: password)
            return true
        } catch {
            let detail = error.localizedDescription
            if detail.localizedCaseInsensitiveContains("rate limit") || detail.contains("429") {
                authError = "Too many sign-in attempts. Wait a few minutes, then try again."
            } else {
                authError = "Email or password didn't match."
            }
            return false
        }
    }

    /// Verify the 6-digit code from the sign-in email. Works even when the
    /// magic-link redirect can't (different device, link scanners, etc.).
    func verifyEmailCode(email: String, code: String) async -> Bool {
        authError = nil
        do {
            try await Supa.client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .email
            )
            return true
        } catch {
            authError = "That code didn't work. Codes expire quickly, request a fresh one."
            return false
        }
    }

    nonisolated func handleOAuthCallback(_ url: URL) {
        Supa.client.auth.handle(url)
    }

    func signOut() async {
        try? await Supa.client.auth.signOut()
        // Clear device-local account choices even if the network revoke fails
        // before the auth-state stream emits signedOut.
        Self.clearPerAccountDefaults()
        setGuest(false)
    }

    private func setGuest(_ enabled: Bool) {
        isGuest = enabled
        UserDefaults.standard.set(enabled, forKey: "guestMode")
    }

    /// Per-account preferences must not leak to the next account on this
    /// device (privacy consents especially). Server copies rehydrate on the
    /// next sign-in; `onboardedUserIDs` stays, it is already user-namespaced.
    static func clearPerAccountDefaults() {
        let keys = [
            "locationConsent", "aggregateConsent", "dataSaleConsent",
            "socialVisible", "beerGeekMode", "noLowDefault",
            "homeRegion", "homeRegionGeocoded",
            "passport.seenBadges", "passport.badgesSeeded"
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.removeObject(forKey: Self.pendingBeerVoteKey)
    }
}
