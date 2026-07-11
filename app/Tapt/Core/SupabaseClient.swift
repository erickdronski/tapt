import Foundation
import Supabase

/// Shared Supabase client. URL + publishable key are public-safe:
/// RLS protects all data, so these can live in the client bundle.
/// Project: qfwiizvqxrhjlthbjosz (us-east-2).
enum Supa {
    static let url = URL(string: "https://qfwiizvqxrhjlthbjosz.supabase.co")!
    static let publishableKey = "sb_publishable_RdaJXK16LieKNlJZjJJ7tQ_5vF9YkhF"
    static let authRedirectURL = URL(string: "tapt://auth-callback")!

    static let client: SupabaseClient = {
        #if targetEnvironment(simulator)
        // Locally-built Simulator apps have no code-signing team, so they get no
        // keychain-access-group and the SDK's default Keychain session storage fails
        // to persist the session. That failure is swallowed (logged only), so with no
        // stored session every authenticated request silently falls back to `anon` and
        // writes (onboarding, pours, votes) return 401. Use a UserDefaults-backed store
        // on the Simulator ONLY, so auth can be exercised during local testing.
        // Device, TestFlight, and App Store builds are never compiled for the simulator,
        // so they always use the secure Keychain storage via the `#else` path below.
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(storage: SimulatorSessionStorage())
            )
        )
        #else
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey
        )
        #endif
    }()
}

#if targetEnvironment(simulator)
/// Simulator-only session storage. NOT compiled into device/TestFlight/App Store
/// builds (which keep the SDK's default Keychain storage). It exists purely so auth
/// works on the Simulator, where unsigned local builds cannot write to the Keychain.
private struct SimulatorSessionStorage: AuthLocalStorage {
    // Reference UserDefaults.standard inline (not a stored property) so the struct
    // stays Sendable under Swift 6 strict concurrency.
    func store(key: String, value: Data) throws { UserDefaults.standard.set(value, forKey: key) }
    func retrieve(key: String) throws -> Data? { UserDefaults.standard.data(forKey: key) }
    func remove(key: String) throws { UserDefaults.standard.removeObject(forKey: key) }
}
#endif
