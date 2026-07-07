import Foundation
import Supabase

/// Fire-and-forget profile writes. Keeping the non-Sendable `PostgrestResponse` inside a
/// nonisolated function (never returning it to the MainActor) satisfies Swift 6 concurrency.
enum ProfileService {
    static func setRegion(_ region: String, userId: UUID) async {
        _ = try? await Supa.client.from("user_profile")
            .update(["region_code": region]).eq("id", value: userId.uuidString).execute()
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
}
