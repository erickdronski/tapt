import Foundation
import Supabase

struct CatalogBeer: Identifiable, Decodable {
    let id: String
    let name: String
    let style: String?
    let abv: Double?
    let brewery: Brewery?
    struct Brewery: Decodable { let name: String?; let country: String? }
    var breweryName: String { brewery?.name ?? "" }
    var country: String { brewery?.country ?? "" }
    var pick: BeerPick {
        BeerPick(id: id, name: name, style: style, abv: abv, breweryName: breweryName, country: country)
    }
}

struct BeerPick: Identifiable, Sendable {
    let id: String
    let name: String
    let style: String?
    let abv: Double?
    let breweryName: String
    let country: String
}

struct ScannedBeer: Identifiable, Decodable {
    let id: String
    let name: String
    let style: String?
    let abv: Double?
    let breweryName: String?
    let country: String?
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id, name, style, abv, country, confidence
        case breweryName = "brewery_name"
    }

    var pick: BeerPick {
        BeerPick(id: id, name: name, style: style, abv: abv, breweryName: breweryName ?? "", country: country ?? "")
    }
}

struct MyCheckin: Identifiable, Decodable {
    let id: String
    let rating: Double?
    let style: String?
    let eventTs: String
    let beer: BeerJoin

    enum CodingKeys: String, CodingKey {
        case id, rating, style
        case eventTs = "event_ts"
        case beer = "beer_catalog"
    }
    struct BeerJoin: Decodable {
        let name: String
        let brewery: BreweryJoin?
    }
    struct BreweryJoin: Decodable { let name: String?; let country: String? }

    var beerName: String { beer.name }
    var breweryName: String { beer.brewery?.name ?? "" }
    var country: String { beer.brewery?.country ?? "" }
}

enum CheckinService {
    static func catalog() async throws -> [CatalogBeer] {
        try await Supa.client.from("beer_catalog")
            .select("id,name,style,abv,brewery(name,country)")
            .order("name").limit(200)
            .execute().value
    }

    static func matchScan(_ raw: String) async throws -> [ScannedBeer] {
        struct Params: Encodable {
            let p_query: String
            let p_limit: Int
        }
        return try await Supa.client.rpc("match_beers", params: Params(p_query: raw, p_limit: 8))
            .execute()
            .value
    }

    static func log(
        beer: BeerPick,
        userId: UUID,
        rating: Double,
        flavorTags: [String] = [],
        glassware: String? = nil,
        occasion: String? = nil
    ) async throws {
        struct Params: Encodable {
            let p_beer_id: String
            let p_rating: Double
            let p_flavor_tags: [String]
            let p_glassware: String?
            let p_occasion: String?
            let p_venue_id: String?
            let p_on_off_premise: String?
            let p_geo_bucket_h3: String?
            let p_photo_url: String?
            let p_price_paid: Double?
            let p_price_tier: String?
            let p_purchase_intent_flags: [String: Bool]
            let p_source: String
        }

        try await Supa.client.rpc(
            "log_checkin",
            params: Params(
                p_beer_id: beer.id,
                p_rating: rating,
                p_flavor_tags: flavorTags,
                p_glassware: glassware,
                p_occasion: occasion,
                p_venue_id: nil,
                p_on_off_premise: nil,
                p_geo_bucket_h3: nil,
                p_photo_url: nil,
                p_price_paid: nil,
                p_price_tier: nil,
                p_purchase_intent_flags: [:],
                p_source: "manual"
            )
        )
            .execute()
    }

    static func mine(userId: UUID) async throws -> [MyCheckin] {
        try await Supa.client.from("checkin_event")
            .select("id,rating,style,event_ts,beer_catalog(name,brewery(name,country))")
            .eq("user_id", value: userId.uuidString)
            .order("event_ts", ascending: false).limit(100)
            .execute().value
    }
}
