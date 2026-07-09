import CoreLocation
import Foundation
import Supabase

struct BreweryMapVenue: Identifiable, Decodable, Sendable {
    let venueId: String
    let name: String
    let city: String?
    let region: String?
    let country: String?
    let latitude: Double
    let longitude: Double
    let sourceLabel: String?
    let heatScore: Int
    let updatedAt: String?
    let breweryType: String?
    let websiteURL: String?

    var id: String { venueId }
    var subtitle: String {
        [city, region, country].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: ", ")
    }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var typeLabel: String {
        guard let breweryType, !breweryType.isEmpty else { return "brewery" }
        return breweryType.replacingOccurrences(of: "_", with: " ")
    }
    var sourceBadge: String {
        if let sourceLabel, sourceLabel.localizedCaseInsensitiveContains("Open Brewery DB") {
            return "OBDB"
        }
        return "Tapt"
    }

    enum CodingKeys: String, CodingKey {
        case venueId = "venue_id"
        case name, city, region, country, latitude, longitude
        case sourceLabel = "source_label"
        case heatScore = "heat_score"
        case updatedAt = "updated_at"
        case breweryType = "brewery_type"
        case websiteURL = "website_url"
    }
}

struct RegionBeerGuide: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let scope: String
    let name: String
    let country: String
    let stateCode: String?
    let flag: String?
    let heroStyle: String
    let flavorNotes: [String]
    let signatureDrinks: [String]
    let topStyles: [String]
    let cellarPrompt: String
    let passportPhrase: String
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, scope, name, country, flag
        case stateCode = "state_code"
        case heroStyle = "hero_style"
        case flavorNotes = "flavor_notes"
        case signatureDrinks = "signature_drinks"
        case topStyles = "top_styles"
        case cellarPrompt = "cellar_prompt"
        case passportPhrase = "passport_phrase"
        case latitude, longitude
    }
}

enum WorldBeerService {
    private struct EmptyParams: Encodable {}

    static func breweryMap(limit: Int = 800) async throws -> [BreweryMapVenue] {
        struct Params: Encodable { let p_limit: Int }

        return try await Supa.client
            .rpc("brewery_map_feed", params: Params(p_limit: limit))
            .execute()
            .value
    }

    static func regionGuides() async throws -> [RegionBeerGuide] {
        try await Supa.client
            .rpc("region_guide_feed", params: EmptyParams())
            .execute()
            .value
    }
}
