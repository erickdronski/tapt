import Foundation
import Supabase

enum BeerService {
    /// Trending beers for a region (ordered by momentum; the caller can re-sort by popularity).
    static func trends(region: String) async throws -> [TrendedBeer] {
        let columns = "beer_id,name,style,abv,brewery_name,country,popularity,momentum,avg_rating"
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

    /// Cast (or update) a +1 / -1 vote for a beer.
    static func vote(beerId: String, userId: UUID, value: Int) async throws {
        struct Vote: Encodable { let user_id: String; let beer_id: String; let value: Int }
        try await Supa.client
            .from("beer_vote")
            .upsert(Vote(user_id: userId.uuidString, beer_id: beerId, value: value))
            .execute()
    }
}
