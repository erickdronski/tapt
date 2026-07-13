import Foundation
import Supabase

enum BeerService {
    /// Trending beers for a region (ordered by momentum; the caller can re-sort by popularity).
    static func trends(region: String) async throws -> [TrendedBeer] {
        let columns = "beer_id,name,style,abv,brewery_name,country,popularity,momentum,avg_rating,is_na_low"
        let rows: [TrendRow]
        if region == "Global" {
            rows = try await Supa.client
                .from("beer_trend_feed")
                .select(columns)
                .order("momentum", ascending: false)
                .limit(40)
                .execute()
                .value
        } else {
            rows = try await Supa.client
                .from("beer_trend_feed")
                .select(columns)
                .eq("region", value: region)
                .order("momentum", ascending: false)
                .limit(40)
                .execute()
                .value
        }
        return rows.map(TrendedBeer.init)
    }

    /// Cast (or update) a +1 / -1 vote for a beer. Explicit conflict target +
    /// minimal return (no SELECT round-trip, no RLS-read dependency).
    static func vote(beerId: String, userId: UUID, value: Int) async throws {
        struct Vote: Encodable { let user_id: String; let beer_id: String; let value: Int }
        try await Supa.client
            .from("beer_vote")
            .upsert(
                Vote(user_id: userId.uuidString, beer_id: beerId, value: value),
                onConflict: "user_id,beer_id",
                returning: .minimal
            )
            .execute()
    }

    /// The caller's current vote for a beer (+1 / -1), or nil if they haven't voted.
    static func currentVote(beerId: String, userId: UUID) async throws -> Int? {
        struct Row: Decodable { let value: Int }
        let rows: [Row] = try await Supa.client
            .from("beer_vote")
            .select("value")
            .eq("user_id", value: userId.uuidString)
            .eq("beer_id", value: beerId)
            .limit(1)
            .execute()
            .value
        return rows.first?.value
    }

    /// Remove the caller's vote for a beer (toggling a thumb back off).
    static func unvote(beerId: String, userId: UUID) async throws {
        try await Supa.client
            .from("beer_vote")
            .delete(returning: .minimal)
            .eq("user_id", value: userId.uuidString)
            .eq("beer_id", value: beerId)
            .execute()
    }
}
