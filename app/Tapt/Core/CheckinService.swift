import Foundation
import Supabase

struct CatalogBeer: Identifiable, Decodable {
    let id: String
    let name: String
    let style: String?
    let abv: Double?
    let rawBreweryName: String?
    let rawCountry: String?
    let imageUrl: String?
    let total: Int?

    var breweryName: String { rawBreweryName ?? "" }
    var country: String { rawCountry ?? "" }
    var pick: BeerPick {
        BeerPick(id: id, name: name, style: style, abv: abv, breweryName: breweryName, country: country)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, style, abv, total
        case rawBreweryName = "brewery_name"
        case rawCountry = "country"
        case imageUrl = "image_url"
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
    let beerId: String?
    let rating: Double?
    let style: String?
    let eventTs: String
    // Optional on purpose: checkin_event.beer_id is nullable, so one pour with
    // a missing catalog join must not fail the WHOLE Cellar decode (a user with
    // real history would see the empty state). Display falls back below.
    let beer: BeerJoin?
    let venue: VenueJoin?

    enum CodingKeys: String, CodingKey {
        case id, rating, style
        case beerId = "beer_id"
        case eventTs = "event_ts"
        case beer = "beer_catalog"
        case venue
    }
    struct BeerJoin: Decodable {
        let name: String
        let brewery: BreweryJoin?
        // 0083: the Cellar is a visual collection now (cutout-preferred image,
        // BJCP-resolved style; raw checkin styles can be retail categories).
        let image: String?
        let styleRef: String?

        enum CodingKeys: String, CodingKey {
            case name, brewery, image
            case styleRef = "style_ref"
        }
    }
    struct BreweryJoin: Decodable { let name: String?; let country: String? }
    struct VenueJoin: Decodable {
        let name: String?
        let externalIds: VenueMetadata?

        enum CodingKeys: String, CodingKey {
            case name
            case externalIds = "external_ids"
        }
    }
    struct VenueMetadata: Decodable {
        let city: String?
        let region: String?
        let country: String?
        let breweryType: String?

        enum CodingKeys: String, CodingKey {
            case city, region, country
            case breweryType = "brewery_type"
        }
    }

    var beerName: String { beer?.name ?? "Logged pour" }
    var breweryName: String { beer?.brewery?.name ?? "" }
    var imageUrl: String? { beer?.image }
    /// Resolved BJCP style only; raw checkin styles can be retail junk.
    var displayStyle: String? { beer?.styleRef }
    var country: String { beer?.brewery?.country ?? "" }
    var venueName: String { venue?.name ?? "" }
    var venueCity: String { venue?.externalIds?.city ?? "" }
    var venueRegion: String { venue?.externalIds?.region ?? "" }
    var venueCountry: String { venue?.externalIds?.country ?? "" }
    var passportCountry: String { venueCountry.isEmpty ? country : venueCountry }
    var placeSubtitle: String {
        [venueCity, venueRegion, venueCountry].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum CheckinService {
    static func catalog(query: String = "", limit: Int = 60, offset: Int = 0) async throws -> [CatalogBeer] {
        struct Params: Encodable {
            let p_query: String?
            let p_style: String?
            let p_na_only: Bool
            let p_limit: Int
            let p_offset: Int
        }
        return try await Supa.client.rpc(
            "catalog_search",
            params: Params(
                p_query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                p_style: nil,
                p_na_only: false,
                p_limit: limit,
                p_offset: offset
            )
        ).execute().value
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
        occasion: String? = nil,
        venue: BreweryMapVenue? = nil,
        venueId: String? = nil,
        source: String? = nil
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

        _ = userId
        try await Supa.authedRPCVoid(
            "log_checkin",
            params: Params(
                p_beer_id: beer.id,
                p_rating: rating,
                p_flavor_tags: flavorTags,
                p_glassware: glassware,
                p_occasion: occasion,
                p_venue_id: venueId ?? venue?.venueId,
                p_on_off_premise: nil,
                p_geo_bucket_h3: nil,
                p_photo_url: nil,
                p_price_paid: nil,
                p_price_tier: nil,
                p_purchase_intent_flags: [:],
                p_source: source ?? ((venueId ?? venue?.venueId) == nil ? "manual" : "manual_with_venue")
            )
        )
    }

    /// Submit a beer we don't have yet (the data moat). Returns the new beer_id so
    /// the caller can log against it immediately. The row is pending review
    /// (name_ok=false server-side), so it stays out of public search and the Beer
    /// Market until approved, but shows in the submitter's Cellar right away.
    static func submitBeer(name: String, brewery: String?, style: String?, abv: Double?) async throws -> String {
        struct Params: Encodable {
            let p_name: String
            let p_brewery_name: String?
            let p_style: String?
            let p_abv: Double?
        }
        return try await Supa.authedRPC(
            "submit_beer",
            params: Params(p_name: name, p_brewery_name: brewery, p_style: style, p_abv: abv))
    }

    static func mine(userId: UUID) async throws -> [MyCheckin] {
        struct Params: Encodable {
            let p_limit: Int
            let p_before_ts: String?
            let p_before_id: String?
        }

        _ = userId
        let pageSize = 250
        var rows: [MyCheckin] = []
        var beforeTimestamp: String?
        var beforeID: String?
        while true {
            let page: [MyCheckin] = try await Supa.authedRPC(
                "my_checkins",
                params: Params(
                    p_limit: pageSize,
                    p_before_ts: beforeTimestamp,
                    p_before_id: beforeID
                )
            )
            rows.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last else { return rows }
            beforeTimestamp = last.eventTs
            beforeID = last.id
        }
    }
}
