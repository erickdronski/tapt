import Foundation

/// A flattened row from `beer_trend`.
struct TrendRow: Decodable {
    let beerId: String
    let name: String
    let style: String?
    let abv: Double?
    let breweryName: String?
    let country: String?
    let imageUrl: String?
    let isNaLow: Bool
    let popularity: Int
    let momentum: Int
    let avgRating: Double?

    enum CodingKeys: String, CodingKey {
        case name, style, abv, country, popularity, momentum
        case isNaLow = "is_na_low"
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case imageUrl = "image_url"
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
    let imageUrl: String?
    let abv: Double?
    // var: a saved vote nudges these in place so the feed doesn't refetch-reshuffle.
    var popularity: Int
    var momentum: Int
    let avgRating: Double?
    let isNaLow: Bool

    init(_ r: TrendRow) {
        id = r.beerId
        name = r.name
        brewery = r.breweryName ?? ""
        country = r.country ?? ""
        style = r.style ?? ""
        imageUrl = r.imageUrl
        abv = r.abv
        popularity = r.popularity
        momentum = r.momentum
        avgRating = r.avgRating
        isNaLow = r.isNaLow
    }
}

enum BeerRegions {
    private static let usRegionPairs: [(code: String, name: String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"),
        ("AR", "Arkansas"), ("CA", "California"), ("CO", "Colorado"),
        ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"),
        ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"),
        ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"),
        ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"),
        ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"),
        ("NE", "Nebraska"), ("NV", "Nevada"), ("NH", "New Hampshire"),
        ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
        ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
        ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"),
        ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"),
        ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
        ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ]

    static let states = usRegionPairs.filter { $0.code != "DC" }.map { $0.name }
    static let usRegions = usRegionPairs.map { $0.name }
    static let countries = [
        "Australia", "Austria", "Belgium", "Brazil", "Canada", "Czechia",
        "Denmark", "Finland", "France", "Germany", "Ireland", "Italy",
        "Japan", "Mexico", "Netherlands", "New Zealand", "Poland",
        "Portugal", "Singapore", "South Africa", "South Korea", "Spain",
        "United Kingdom"
    ]
    static let all = usRegions + ["Global"] + countries

    static func canonicalUSRegion(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return usRegionPairs.first {
            $0.code.localizedCaseInsensitiveCompare(candidate) == .orderedSame
                || $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }?.name
    }

    static func canonicalCountry(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return countries.first {
            $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame
        }
    }
}
