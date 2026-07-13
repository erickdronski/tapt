import Foundation
import Supabase

struct AccountPrivacyChoices: Sendable {
    let location: Bool
    let aggregateAnalytics: Bool
    let dataSale: Bool
    let socialVisible: Bool
}

/// Account preferences, consent choices, and deletion through narrow server APIs.
enum ProfileService {
    static func setRegion(_ region: String, userId: UUID) async {
        struct Params: Encodable {
            let p_region_code: String
            let p_beer_geek_mode: Bool?
        }
        _ = try? await Supa.client.rpc(
            "set_profile_preferences",
            params: Params(p_region_code: region, p_beer_geek_mode: nil)
        ).execute()
    }

    static func confirmLegalAge(userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["birth_verified": true]).eq("id", value: userId.uuidString).execute()
    }

    static func setBeerGeek(_ value: Bool, userId: UUID) async {
        struct Params: Encodable {
            let p_region_code: String?
            let p_beer_geek_mode: Bool
        }
        _ = try? await Supa.client.rpc(
            "set_profile_preferences",
            params: Params(p_region_code: nil, p_beer_geek_mode: value)
        ).execute()
    }

    static func setTopStyles(_ styles: [String], userId: UUID) async {
        struct TV: Encodable { let user_id: String; let top_styles: [String] }
        _ = try? await Supa.client.from("taste_vector")
            .upsert(TV(user_id: userId.uuidString, top_styles: styles)).execute()
    }

    static func setPrivacyChoice(purpose: String, granted: Bool, uiText: String, userId: UUID) async throws {
        struct Params: Encodable {
            let p_purpose: String
            let p_granted: Bool
            let p_ui_text: String
        }
        _ = userId
        try await Supa.client.rpc(
            "record_privacy_choice",
            params: Params(p_purpose: purpose, p_granted: granted, p_ui_text: uiText)
        ).execute()
    }

    static func recordConsent(
        purpose: String,
        granted: Bool,
        policyVersion: String = "2026-07-08",
        uiText: String,
        source: String,
        userId: UUID
    ) async throws {
        try await setPrivacyChoice(purpose: purpose, granted: granted, uiText: uiText, userId: userId)
    }

    static func privacyChoices(userId: UUID) async throws -> AccountPrivacyChoices {
        struct ConsentRow: Decodable {
            let purpose: String
            let granted: Bool
        }
        struct ProfileRow: Decodable {
            let socialVisible: Bool
            enum CodingKeys: String, CodingKey { case socialVisible = "social_visible" }
        }

        let rows: [ConsentRow] = try await Supa.client.from("consent_ledger")
            .select("purpose,granted")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute().value
        let profile: [ProfileRow] = try await Supa.client.from("user_profile")
            .select("social_visible")
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
            socialVisible: profile.first?.socialVisible ?? false
        )
    }

    static func setSocialVisibility(_ visible: Bool) async throws {
        struct Params: Encodable { let p_visible: Bool }
        try await Supa.client.rpc(
            "set_social_visibility",
            params: Params(p_visible: visible)
        ).execute()
    }

    /// Real, immediate account deletion (App Store 5.1.1(v) + GDPR/CCPA): the
    /// delete_my_account RPC wipes the caller's entire personal plane (votes,
    /// check-ins, profile, follows, claims, consent, ...) and their auth identity;
    /// the k-anon aggregate plane is retained per the two-plane design. Then sign out.
    static func requestAccountDeletion(userId: UUID, reason: String? = nil) async throws {
        _ = reason // kept for call-site compatibility; deletion is immediate, not queued
        try await Supa.client.rpc("delete_my_account").execute()
        try? await Supa.client.auth.signOut()
    }

    /// Whether this user already finished onboarding on the server (region set).
    /// Lets a reinstall / new device skip onboarding instead of repeating it.
    /// Returns nil when the answer is UNKNOWN (network/server failure): a flaky
    /// first launch must never be read as "not onboarded", because completing
    /// onboarding again overwrites the user's saved region/styles/consents.
    static func isOnboarded(userId: UUID) async -> Bool? {
        struct Row: Decodable { let region_code: String? }
        do {
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
        try await Supa.client.rpc(
            "complete_profile_onboarding",
            params: Params(
                p_age_confirmed: ageConfirmed,
                p_region_code: region,
                p_top_styles: topStyles,
                p_location_consent: locationConsent,
                p_aggregate_consent: aggregateConsent,
                p_data_sale_consent: dataSaleConsent
            )
        ).execute()
    }
}
