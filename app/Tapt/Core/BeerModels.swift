import Foundation

/// A row from `beer_trend` joined with its beer + brewery (PostgREST nested select).
struct TrendRow: Decodable {
    let popularity: Int
    let momentum: Int
    let avgRating: Double?
    let beer: BeerJoin

    enum CodingKeys: String, CodingKey {
        case popularity, momentum
        case avgRating = "avg_rating"
        case beer = "beer_catalog"
    }

    struct BeerJoin: Decodable {
        let id: String
        let name: String
        let style: String?
        let abv: Double?
        let brewery: BreweryJoin?
    }
    struct BreweryJoin: Decodable {
        let name: String?
        let country: String?
    }
}

/// Flattened view model for the Explore UI.
struct TrendedBeer: Identifiable {
    let id: String
    let name: String
    let brewery: String
    let country: String
    let style: String
    let abv: Double?
    let popularity: Int
    let momentum: Int
    let avgRating: Double?

    init(_ r: TrendRow) {
        id = r.beer.id
        name = r.beer.name
        brewery = r.beer.brewery?.name ?? ""
        country = r.beer.brewery?.country ?? ""
        style = r.beer.style ?? ""
        abv = r.beer.abv
        popularity = r.popularity
        momentum = r.momentum
        avgRating = r.avgRating
    }
}

enum BeerRegions {
    static let all = ["New Jersey", "California", "Global", "Germany", "Poland",
                      "Czechia", "Belgium", "Ireland", "United Kingdom", "Mexico"]
}
