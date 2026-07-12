import Foundation

/// Reads which auth providers are actually enabled on the Supabase project
/// (public GoTrue settings endpoint), so the sign-in screen only offers
/// buttons that can succeed. No more dead login buttons.
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
            apple: on("apple"),
            google: on("google"),
            facebook: on("facebook"),
            twitter: on("twitter"),
            email: on("email")
        )
    }
}
