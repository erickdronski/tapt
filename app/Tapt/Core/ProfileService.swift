import Foundation
import Supabase

struct AccountPrivacyChoices: Sendable {
    let location: Bool
    let aggregateAnalytics: Bool
    let dataSale: Bool
    let socialVisible: Bool
    let beerGeekMode: Bool
}

/// Account preferences, consent choices, and deletion through narrow server APIs.
enum ProfileService {
    static func setRegion(_ region: String, userId: UUID) async throws {
        struct Params: Encodable {
            let p_region_code: String
            let p_beer_geek_mode: Bool?
        }
        _ = userId
        try await Supa.authedRPCVoid(
            "set_profile_preferences",
            params: Params(p_region_code: region, p_beer_geek_mode: nil)
        )
    }

    static func confirmLegalAge(userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["birth_verified": true]).eq("id", value: userId.uuidString).execute()
    }

    static func setBeerGeek(_ value: Bool, userId: UUID) async throws {
        struct Params: Encodable {
            let p_region_code: String?
            let p_beer_geek_mode: Bool
        }
        _ = userId
        try await Supa.authedRPCVoid(
            "set_profile_preferences",
            params: Params(p_region_code: nil, p_beer_geek_mode: value)
        )
    }

    static func topStyles(userId: UUID) async throws -> [String] {
        struct Row: Decodable {
            let topStyles: [String]
            enum CodingKeys: String, CodingKey { case topStyles = "top_styles" }
        }
        _ = try await Supa.client.auth.session
        let rows: [Row] = try await Supa.client.from("taste_vector")
            .select("top_styles")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute().value
        return rows.first?.topStyles ?? []
    }

    static func setTopStyles(_ styles: [String], userId: UUID) async throws {
        struct TV: Encodable { let user_id: String; let top_styles: [String] }
        _ = try await Supa.client.auth.session
        try await Supa.client.from("taste_vector")
            .upsert(
                TV(user_id: userId.uuidString, top_styles: styles),
                returning: .minimal
            )
            .execute()
    }

    static func setPrivacyChoice(purpose: String, granted: Bool, uiText: String, userId: UUID) async throws {
        struct Params: Encodable {
            let p_purpose: String
            let p_granted: Bool
            let p_ui_text: String
        }
        _ = userId
        try await Supa.authedRPCVoid(
            "record_privacy_choice",
            params: Params(p_purpose: purpose, p_granted: granted, p_ui_text: uiText)
        )
    }

    static func privacyChoices(userId: UUID) async throws -> AccountPrivacyChoices {
        struct ConsentRow: Decodable {
            let purpose: String
            let granted: Bool
        }
        struct ProfileRow: Decodable {
            let socialVisible: Bool
            let beerGeekMode: Bool
            enum CodingKeys: String, CodingKey {
                case socialVisible = "social_visible"
                case beerGeekMode = "beer_geek_mode"
            }
        }

        _ = try await Supa.client.auth.session
        let rows: [ConsentRow] = try await Supa.client.from("consent_ledger")
            .select("purpose,granted")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute().value
        let profile: [ProfileRow] = try await Supa.client.from("user_profile")
            .select("social_visible,beer_geek_mode")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute().value

        var latest: [String: Bool] = [:]
        for row in rows where latest[row.purpose] == nil {
            latest[row.purpose] = row.granted
        }
        return AccountPrivacyChoices(
            location: latest["location"] ?? false,
            aggregateAnalytics: latest["aggregate_analytics"] ?? false,
            dataSale: latest["data_sale"] ?? false,
            socialVisible: profile.first?.socialVisible ?? false,
            beerGeekMode: profile.first?.beerGeekMode ?? false
        )
    }

    static func setSocialVisibility(_ visible: Bool) async throws {
        struct Params: Encodable { let p_visible: Bool }
        try await Supa.authedRPCVoid(
            "set_social_visibility",
            params: Params(p_visible: visible)
        )
    }

    /// The server revokes any stored Sign in with Apple authorization first,
    /// then removes the personal plane, avatar objects, and auth identity.
    static func requestAccountDeletion(userId: UUID, reason: String? = nil) async throws -> Bool {
        _ = userId
        struct DeleteBody: Encodable, Sendable { let reason: String? }
        struct DeleteResponse: Decodable {
            let deleted: Bool
            let manualAppleRevocationRequired: Bool
        }
        _ = try await Supa.client.auth.session
        let response: DeleteResponse = try await Supa.client.functions.invoke(
            "delete-account",
            options: FunctionInvokeOptions(body: DeleteBody(reason: reason))
        )
        guard response.deleted else { throw ProfileServiceError.deletionIncomplete }
        try? await Supa.client.auth.signOut()
        return response.manualAppleRevocationRequired
    }

    /// Whether this user already finished onboarding on the server (region set).
    /// Lets a reinstall / new device skip onboarding instead of repeating it.
    /// Returns nil when the answer is UNKNOWN (network/server failure): a flaky
    /// first launch must never be read as "not onboarded", because completing
    /// onboarding again overwrites the user's saved region/styles/consents.
    static func isOnboarded(userId: UUID) async -> Bool? {
        struct Row: Decodable { let region_code: String? }
        do {
            _ = try await Supa.client.auth.session
            let rows: [Row] = try await Supa.client.from("user_profile")
                .select("region_code").eq("id", value: userId.uuidString).limit(1)
                .execute().value
            return (rows.first?.region_code?.isEmpty == false)
        } catch {
            return nil
        }
    }

    static func completeOnboarding(
        userId: UUID,
        ageConfirmed: Bool,
        region: String,
        topStyles: [String],
        locationConsent: Bool,
        aggregateConsent: Bool,
        dataSaleConsent: Bool
    ) async throws {
        struct Params: Encodable {
            let p_age_confirmed: Bool
            let p_region_code: String
            let p_top_styles: [String]
            let p_location_consent: Bool
            let p_aggregate_consent: Bool
            let p_data_sale_consent: Bool
        }
        try await Supa.authedRPCVoid(
            "complete_profile_onboarding",
            params: Params(
                p_age_confirmed: ageConfirmed,
                p_region_code: region,
                p_top_styles: topStyles,
                p_location_consent: locationConsent,
                p_aggregate_consent: aggregateConsent,
                p_data_sale_consent: dataSaleConsent
            )
        )
    }

    struct MyProfile: Sendable {
        let displayName: String?
        let handle: String?
        let avatarUrl: String?
        let pendingAvatarUrl: String?
        let avatarModerationStatus: String
    }

    /// The caller's own editable identity row.
    static func myProfile(userId: UUID) async throws -> MyProfile {
        struct Row: Decodable {
            let display_name: String?
            let handle: String?
            let avatar_url: String?
            let pending_avatar_url: String?
            let avatar_moderation_status: String
        }
        _ = try await Supa.client.auth.session
        let rows: [Row] = try await Supa.client.from("user_profile")
            .select("display_name,handle,avatar_url,pending_avatar_url,avatar_moderation_status")
            .eq("id", value: userId.uuidString)
            .limit(1).execute().value
        let r = rows.first
        return MyProfile(
            displayName: r?.display_name,
            handle: r?.handle,
            avatarUrl: r?.avatar_url,
            pendingAvatarUrl: r?.pending_avatar_url,
            avatarModerationStatus: r?.avatar_moderation_status ?? "none"
        )
    }

    /// Save display name and/or handle. nil leaves a field unchanged; "" clears the handle.
    static func setIdentity(displayName: String?, handle: String?) async throws {
        struct Params: Encodable { let p_display_name: String?; let p_handle: String? }
        try await Supa.authedRPCVoid("set_profile_identity",
            params: Params(p_display_name: displayName, p_handle: handle))
    }

    static func setAvatarURL(_ url: String?) async throws {
        struct Params: Encodable { let p_url: String? }
        try await Supa.authedRPCVoid("set_avatar_url", params: Params(p_url: url))
    }

    /// Upload each candidate to a unique object so an unreviewed image cannot
    /// overwrite the bytes behind the currently approved public avatar.
    static func uploadAvatar(_ jpeg: Data, userId: UUID) async throws -> String {
        let previousProfile = try? await myProfile(userId: userId)
        let previousPath = previousProfile?.pendingAvatarUrl
            .flatMap { avatarStoragePath(from: $0, userId: userId) }
        let path = "\(userId.uuidString)/\(UUID().uuidString.lowercased()).jpg"
        _ = try await Supa.client.storage.from("avatars").upload(
            path: path, file: jpeg,
            options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true))
        let base = try Supa.client.storage.from("avatars").getPublicURL(path: path).absoluteString
        let busted = base + "?v=\(Int(Date().timeIntervalSince1970))"
        do {
            try await setAvatarURL(busted)
        } catch {
            try? await Supa.client.storage.from("avatars").remove(paths: [path])
            throw error
        }
        if let previousPath, previousPath != path {
            try? await Supa.client.storage.from("avatars").remove(paths: [previousPath])
        }
        return busted
    }

    private static func avatarStoragePath(from value: String, userId: UUID) -> String? {
        guard let url = URL(string: value) else { return nil }
        let marker = "/storage/v1/object/public/avatars/"
        guard let range = url.path.range(of: marker) else { return nil }
        let encoded = String(url.path[range.upperBound...])
        let path = encoded.removingPercentEncoding ?? encoded
        guard path.hasPrefix("\(userId.uuidString)/") else { return nil }
        return path
    }
}

private enum ProfileServiceError: Error {
    case deletionIncomplete
}
