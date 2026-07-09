import Foundation

/// A flattened row from `beer_trend`.
struct TrendRow: Decodable {
    let beerId: String
    let name: String
    let style: String?
    let abv: Double?
    let breweryName: String?
    let country: String?
    let popularity: Int
    let momentum: Int
    let avgRating: Double?

    enum CodingKeys: String, CodingKey {
        case name, style, abv, country, popularity, momentum
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case avgRating = "avg_rating"
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
        id = r.beerId
        name = r.name
        brewery = r.breweryName ?? ""
        country = r.country ?? ""
        style = r.style ?? ""
        abv = r.abv
        popularity = r.popularity
        momentum = r.momentum
        avgRating = r.avgRating
    }
}

enum BeerRegions {
    static let states = [
        "New Jersey", "California", "Colorado", "Massachusetts", "Maine", "Michigan",
        "Minnesota", "Missouri", "New York", "North Carolina", "Ohio", "Oregon",
        "Pennsylvania", "Texas", "Vermont", "Washington", "Alabama", "Alaska",
        "Arizona", "Delaware", "Florida", "Georgia", "Illinois"
    ]
    static let countries = [
        "Belgium", "Czechia", "Germany", "Ireland", "Japan", "Mexico", "Poland",
        "United Kingdom"
    ]
    static let all = states + ["Global"] + countries
}
