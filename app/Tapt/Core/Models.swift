import Foundation

// Codable models mirroring the Supabase schema (supabase/migrations/0001_init.sql).
// snake_case columns mapped via CodingKeys.

struct UserProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var handle: String?
    var displayName: String?
    var avatarUrl: String?
    var beerGeekMode: Bool
    enum CodingKeys: String, CodingKey {
        case id, handle
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case beerGeekMode = "beer_geek_mode"
    }
}

struct Brewery: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var country: String?
    var verifiedPartner: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, country
        case verifiedPartner = "verified_partner"
    }
}

struct Beer: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var style: String?
    var abv: Double?
    var ibu: Int?
    var isNaLow: Bool
    var breweryId: UUID?
    enum CodingKeys: String, CodingKey {
        case id, name, style, abv, ibu
        case isNaLow = "is_na_low"
        case breweryId = "brewery_id"
    }
}

/// One check-in = the atomic, immutable "consumption moment" (the sellable unit).
struct CheckinEvent: Codable, Identifiable, Sendable {
    let id: UUID
    var userId: UUID
    var beerId: UUID?
    var rating: Double?
    var flavorTags: [String]
    var eventTs: Date
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case beerId = "beer_id"
        case rating
        case flavorTags = "flavor_tags"
        case eventTs = "event_ts"
    }
}
