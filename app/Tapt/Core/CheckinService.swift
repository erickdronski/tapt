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

    static func log(beer: CatalogBeer, userId: UUID, rating: Double) async throws {
        struct Row: Encodable {
            let user_id: String
            let beer_id: String
            let style: String?
            let abv: Double?
            let rating: Double
        }
        try await Supa.client.from("checkin_event")
            .insert(Row(user_id: userId.uuidString, beer_id: beer.id, style: beer.style, abv: beer.abv, rating: rating))
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
