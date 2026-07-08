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
        struct Row: Encodable {
            let user_id: String
            let beer_id: String
            let style: String?
            let abv: Double?
            let rating: Double
            let flavor_tags: [String]
            let glassware: String?
            let occasion: String?
        }
        try await Supa.client.from("checkin_event")
            .insert(Row(
                user_id: userId.uuidString,
                beer_id: beer.id,
                style: beer.style,
                abv: beer.abv,
                rating: rating,
                flavor_tags: flavorTags,
                glassware: glassware,
                occasion: occasion
            ))
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
