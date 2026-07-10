import Foundation
import Supabase

// Beer page + Beer of the Week. All numbers are first-party or cited to their
// open-data source (BJCP ranges, Open Food Facts nutrition), never invented.

struct BeerDetail: Decodable, Sendable {
    let id: String
    let name: String
    let style: String?
    let substyle: String?
    let abv: Double?
    let ibu: Int?
    let isNaLow: Bool
    let gtin: String?
    let labelImageUrl: String?
    let labelImageLicense: String?
    let nutrition: Nutrition?
    let dataSource: String?
    let breweryName: String?
    let breweryCountry: String?
    let breweryWebsite: String?
    let styleFamily: String?
    let styleName: String?
    let styleDescription: String?
    let styleAbvMin: Double?
    let styleAbvMax: Double?
    let styleIbuMin: Int?
    let styleIbuMax: Int?
    let styleSrmMin: Int?
    let styleSrmMax: Int?
    let styleSourceUrl: String?
    let ups: Int
    let downs: Int
    let checkinCount: Int
    let avgRating: Double?
    let venuesInCountry: Int
    let awards: [Award]

    struct Award: Decodable, Sendable, Identifiable {
        let awardBody: String
        let year: Int?
        let category: String?
        let medal: String
        let scope: String?
        let region: String?
        let sourceUrl: String?
        let note: String?

        var id: String { [awardBody, year.map(String.init), category, medal, scope, region].compactMap { $0 }.joined(separator: "-") }

        var medalEmoji: String {
            switch medal {
            case "gold": "🥇"
            case "silver": "🥈"
            case "bronze": "🥉"
            case "tapt_favorite": "🍺"
            default: "🏅"
            }
        }

        var medalLabel: String {
            switch medal {
            case "tapt_favorite": "Tapt's Favorite"
            default: medal.capitalized
            }
        }

        enum CodingKeys: String, CodingKey {
            case year, category, medal, scope, region, note
            case awardBody = "award_body"
            case sourceUrl = "source_url"
        }
    }

    struct Nutrition: Decodable, Sendable {
        let kcal100ml: Double?
        let carbsG100ml: Double?
        let proteinG100ml: Double?
        let sugarsG100ml: Double?
        enum CodingKeys: String, CodingKey {
            case kcal100ml = "kcal_100ml"
            case carbsG100ml = "carbs_g_100ml"
            case proteinG100ml = "protein_g_100ml"
            case sugarsG100ml = "sugars_g_100ml"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, style, substyle, abv, ibu, gtin, nutrition, ups, downs, awards
        case isNaLow = "is_na_low"
        case labelImageUrl = "label_image_url"
        case labelImageLicense = "label_image_license"
        case dataSource = "data_source"
        case breweryName = "brewery_name"
        case breweryCountry = "brewery_country"
        case breweryWebsite = "brewery_website"
        case styleFamily = "style_family"
        case styleName = "style_name"
        case styleDescription = "style_description"
        case styleAbvMin = "style_abv_min"
        case styleAbvMax = "style_abv_max"
        case styleIbuMin = "style_ibu_min"
        case styleIbuMax = "style_ibu_max"
        case styleSrmMin = "style_srm_min"
        case styleSrmMax = "style_srm_max"
        case styleSourceUrl = "style_source_url"
        case checkinCount = "checkin_count"
        case avgRating = "avg_rating"
        case venuesInCountry = "venues_in_country"
    }
}

enum BeerDetailService {
    static func detail(beerId: String) async throws -> BeerDetail? {
        struct Params: Encodable { let p_beer_id: String }
        let rows: [BeerDetail] = try await Supa.client
            .rpc("beer_detail", params: Params(p_beer_id: beerId))
            .execute().value
        return rows.first
    }
}

// MARK: - Beer of the Week

struct BeerOfWeekEntry: Identifiable, Decodable, Sendable {
    let rank: Int?
    let beerId: String
    let name: String
    let style: String?
    let breweryName: String?
    let country: String?
    let labelImageUrl: String?
    let weekVotes: Int

    var id: String { beerId }

    enum CodingKeys: String, CodingKey {
        case rank, name, style, country
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case labelImageUrl = "label_image_url"
        case weekVotes = "week_votes"
    }
}

enum BeerOfWeekService {
    static func standings(limit: Int = 5) async throws -> [BeerOfWeekEntry] {
        struct Params: Encodable { let p_limit: Int }
        return try await Supa.client
            .rpc("beer_of_week_standings", params: Params(p_limit: limit))
            .execute().value
    }

    static func latestWinner() async throws -> BeerOfWeekEntry? {
        struct Empty: Encodable {}
        let rows: [BeerOfWeekEntry] = try await Supa.client
            .rpc("beer_of_week_latest_winner", params: Empty())
            .execute().value
        return rows.first
    }
}
