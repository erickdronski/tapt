import Foundation

/// Reads configured auth providers from Supabase. External providers also need
/// a signed-device callback test before they are allowed into a release build.
struct AuthProviderFlags: Sendable {
    var apple = false
    var google = false
    var facebook = false
    var twitter = false
    var email = true

    // A settings outage must not expose providers that may be misconfigured.
    // Email is the only provider we can safely keep available without discovery.
    static let fallback = AuthProviderFlags(apple: false, google: false, facebook: false, twitter: false, email: true)
}

enum AuthProvidersService {
    /// Change a provider to true only after its full TestFlight callback has
    /// produced a Supabase session. Dashboard "enabled" state is not enough.
    private static let deviceVerified = AuthProviderFlags(
        apple: false,
        google: false,
        facebook: false,
        twitter: false,
        email: true
    )

    static func flags() async -> AuthProviderFlags {
        struct Settings: Decodable {
            let external: [String: Bool?]
        }
        var request = URLRequest(url: Supa.url.appendingPathComponent("auth/v1/settings"))
        request.setValue(Supa.publishableKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .fallback }

        func on(_ key: String) -> Bool { settings.external[key].flatMap { $0 } ?? false }
        return AuthProviderFlags(
            apple: on("apple") && deviceVerified.apple,
            google: on("google") && deviceVerified.google,
            facebook: on("facebook") && deviceVerified.facebook,
            twitter: on("twitter") && deviceVerified.twitter,
            email: on("email")
        )
    }
}
