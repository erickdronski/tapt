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
    // var: a saved vote nudges these in place so the feed doesn't refetch-reshuffle.
    var popularity: Int
    var momentum: Int
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
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
        "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho",
        "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana",
        "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada",
        "New Hampshire", "New Jersey", "New Mexico", "New York",
        "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
        "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota",
        "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington",
        "West Virginia", "Wisconsin", "Wyoming"
    ]
    static let countries = [
        "Australia", "Austria", "Belgium", "Brazil", "Canada", "Czechia",
        "Denmark", "Finland", "France", "Germany", "Ireland", "Italy",
        "Japan", "Mexico", "Netherlands", "New Zealand", "Poland",
        "Portugal", "Singapore", "South Africa", "South Korea", "Spain",
        "United Kingdom"
    ]
    static let all = states + ["Global"] + countries
}
