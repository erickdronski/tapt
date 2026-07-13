import SwiftUI
import Supabase
import AuthenticationServices

/// App-wide auth state, driven by Supabase.
@MainActor
@Observable
final class Session {
    private static let pendingPartnerVenueKey = "pendingPartnerVenueId"
    private static let pendingBeerDetailKey = "pendingBeerDetailId"

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
            "homeRegion", "homeRegionGeocoded"
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }
}
