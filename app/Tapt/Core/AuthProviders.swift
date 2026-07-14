import Foundation

/// Reads configured auth providers from Supabase. External providers are
/// release-gated until the live provider has created a Supabase identity and
/// the app redirect wiring has been verified.
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
    /// Dashboard "enabled" state is not enough. A provider is exposed only
    /// after a real hosted callback has created a Supabase identity; the signed
    /// device deep link remains part of TestFlight release validation.
    // Sign in with Apple is ON so it appears alongside Google (App Store 4.8
    // requires it whenever a third-party social login is offered). It is still
    // ANDed with on("apple"), so it only renders once the Apple provider is
    // actually enabled in Supabase - never a broken button before that.
    private static let deviceVerified = AuthProviderFlags(
        apple: true,
        google: true,
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
