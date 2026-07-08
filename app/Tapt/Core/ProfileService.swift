import Foundation
import Supabase

/// Fire-and-forget profile writes. Keeping the non-Sendable `PostgrestResponse` inside a
/// nonisolated function (never returning it to the MainActor) satisfies Swift 6 concurrency.
enum ProfileService {
    static func setRegion(_ region: String, userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["region_code": region]).eq("id", value: userId.uuidString).execute()
    }

    static func confirmLegalAge(userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["birth_verified": true]).eq("id", value: userId.uuidString).execute()
    }

    static func setBeerGeek(_ value: Bool, userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["beer_geek_mode": value]).eq("id", value: userId.uuidString).execute()
    }

    static func setTopStyles(_ styles: [String], userId: UUID) async {
        struct TV: Encodable { let user_id: String; let top_styles: [String] }
        _ = try? await Supa.client.from("taste_vector")
            .upsert(TV(user_id: userId.uuidString, top_styles: styles)).execute()
    }

    static func recordConsent(
        purpose: String,
        granted: Bool,
        policyVersion: String = "2026-07-08",
        uiText: String,
        source: String,
        userId: UUID
    ) async {
        struct Consent: Encodable {
            let user_id: String
            let purpose: String
            let action: String
            let granted: Bool
            let policy_version: String
            let ui_text_shown: String
            let source: String
        }
        let row = Consent(
            user_id: userId.uuidString,
            purpose: purpose,
            action: granted ? "granted" : "withdrawn",
            granted: granted,
            policy_version: policyVersion,
            ui_text_shown: uiText,
            source: source
        )
        _ = try? await Supa.client.from("consent_ledger").insert(row).execute()
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
}
