import Foundation
import Supabase

struct TonightBeer: Identifiable, Decodable, Sendable {
    let venueId: String?
    let venueName: String?
    let beerId: String?
    let beerName: String
    let breweryName: String?
    let style: String?
    let sourceLabel: String
    let heatScore: Int
    let updatedAt: String?

    var id: String {
        [venueId, beerId, beerName, sourceLabel].compactMap { $0 }.joined(separator: "-")
    }

    enum CodingKeys: String, CodingKey {
        case venueId = "venue_id"
        case venueName = "venue_name"
        case beerId = "beer_id"
        case beerName = "beer_name"
        case breweryName = "brewery_name"
        case style
        case sourceLabel = "source_label"
        case heatScore = "heat_score"
        case updatedAt = "updated_at"
    }
}

struct SocialPour: Identifiable, Decodable, Sendable {
    let checkinId: String
    let actorId: String
    let actorName: String
    let avatarUrl: String?
    let beerName: String?
    let breweryName: String?
    let venueName: String?
    let style: String?
    let rating: Double?
    let eventTs: String

    var id: String { checkinId }

    enum CodingKeys: String, CodingKey {
        case checkinId = "checkin_id"
        case actorId = "actor_id"
        case actorName = "actor_name"
        case avatarUrl = "avatar_url"
        case beerName = "beer_name"
        case breweryName = "brewery_name"
        case venueName = "venue_name"
        case style, rating
        case eventTs = "event_ts"
    }
}

struct TasteProfilePoint: Identifiable, Decodable, Sendable {
    let style: String
    let pourCount: Int
    let avgRating: Double?
    let lastPourAt: String?

    var id: String { style }

    enum CodingKeys: String, CodingKey {
        case style
        case pourCount = "pour_count"
        case avgRating = "avg_rating"
        case lastPourAt = "last_pour_at"
    }
}

enum LiveBeerService {
    static func tonight(region: String? = nil, limit: Int = 20) async throws -> [TonightBeer] {
        struct Params: Encodable {
            let p_geo_bucket: String?
            let p_limit: Int
        }

        return try await Supa.client
            .rpc("tonight_feed", params: Params(p_geo_bucket: region, p_limit: limit))
            .execute()
            .value
    }

    static func socialPours(limit: Int = 30) async throws -> [SocialPour] {
        struct Params: Encodable { let p_limit: Int }

        return try await Supa.client
            .rpc("social_pour_feed", params: Params(p_limit: limit))
            .execute()
            .value
    }

    static func tasteProfile(userId: UUID? = nil) async throws -> [TasteProfilePoint] {
        struct Params: Encodable { let p_user: String? }

        return try await Supa.client
            .rpc("taste_profile_snapshot", params: Params(p_user: userId?.uuidString))
            .execute()
            .value
    }

    static func report(checkinId: String, userId: UUID, reason: String) async throws {
        struct Row: Encodable {
            let reporter_id: String
            let target_type: String
            let target_id: String
            let reason: String
        }

        try await Supa.client
            .from("content_report")
            .insert(Row(
                reporter_id: userId.uuidString,
                target_type: "checkin",
                target_id: checkinId,
                reason: reason
            ))
            .execute()
    }

    static func block(actorId: String, userId: UUID) async throws {
        struct Row: Encodable {
            let blocker_id: String
            let blocked_id: String
        }

        try await Supa.client
            .from("user_block")
            .upsert(Row(blocker_id: userId.uuidString, blocked_id: actorId))
            .execute()
    }
}
