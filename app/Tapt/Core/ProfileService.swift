import Foundation
import Supabase

/// Fire-and-forget profile writes. Keeping the non-Sendable `PostgrestResponse` inside a
/// nonisolated function (never returning it to the MainActor) satisfies Swift 6 concurrency.
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

    static func setPrivacyChoice(purpose: String, granted: Bool, uiText: String, userId: UUID) async {
        struct Params: Encodable {
            let p_purpose: String
            let p_granted: Bool
            let p_ui_text: String
        }
        _ = try? await Supa.client.rpc(
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
    ) async {
        await setPrivacyChoice(purpose: purpose, granted: granted, uiText: uiText, userId: userId)
    }

    static func requestAccountDeletion(userId: UUID, reason: String? = nil) async throws {
        struct Request: Encodable {
            let user_id: String
            let reason: String?
        }
        try await Supa.client.from("account_deletion_request")
            .insert(Request(user_id: userId.uuidString, reason: reason))
            .execute()
    }

    static func completeOnboarding(
        userId: UUID,
        region: String,
        topStyles: [String],
        locationConsent: Bool,
        aggregateConsent: Bool,
        dataSaleConsent: Bool
    ) async throws {
        struct Params: Encodable {
            let p_region_code: String
            let p_top_styles: [String]
            let p_location_consent: Bool
            let p_aggregate_consent: Bool
            let p_data_sale_consent: Bool
        }
        try await Supa.client.rpc(
            "complete_profile_onboarding",
            params: Params(
                p_region_code: region,
                p_top_styles: topStyles,
                p_location_consent: locationConsent,
                p_aggregate_consent: aggregateConsent,
                p_data_sale_consent: dataSaleConsent
            )
        ).execute()
    }
}
