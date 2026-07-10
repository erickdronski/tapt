import Foundation
import Supabase

// Superapp services: newsletter, partners, leaderboards, friends, and
// scan-to-catalog. All backed by the 0009/0010 RPC contract; every number
// shown from these calls is first-party or source-attributed, never invented.

// MARK: - Newsletter (The Tapt Dispatch)

enum NewsletterService {
    struct Status: Decodable, Sendable {
        let email: String
        let status: String
    }

    static func status() async throws -> Status? {
        struct Empty: Encodable {}
        let rows: [Status] = try await Supa.client
            .rpc("newsletter_status", params: Empty())
            .execute().value
        return rows.first
    }

    static func subscribe(email: String, source: String) async throws {
        struct Params: Encodable {
            let p_email: String
            let p_source: String
            let p_ui_text: String
        }
        try await Supa.client.rpc(
            "subscribe_newsletter",
            params: Params(
                p_email: email,
                p_source: source,
                p_ui_text: "Send me The Tapt Dispatch: beer trends, new spots, and what the world is pouring."
            )
        ).execute()
    }

    static func unsubscribe() async throws {
        struct Empty: Encodable {}
        try await Supa.client.rpc("unsubscribe_newsletter", params: Empty()).execute()
    }
}

// MARK: - Partners (featured placements + inquiries)

struct FeaturedPartner: Identifiable, Decodable, Sendable {
    let id: String
    let kind: String
    let title: String
    let blurb: String?
    let ctaLabel: String?
    let ctaUrl: String?
    let city: String?
    let region: String?
    let country: String?
    let tier: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, blurb, city, region, country, tier
        case ctaLabel = "cta_label"
        case ctaUrl = "cta_url"
    }

    var placeLine: String {
        [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum PartnerService {
    static func featured(limit: Int = 10) async throws -> [FeaturedPartner] {
        struct Params: Encodable { let p_limit: Int }
        return try await Supa.client
            .rpc("featured_partner_feed", params: Params(p_limit: limit))
            .execute().value
    }

    static func submitInquiry(
        businessName: String,
        kind: String,
        email: String,
        city: String?,
        region: String?,
        country: String?,
        message: String?
    ) async throws {
        struct Params: Encodable {
            let p_business_name: String
            let p_business_kind: String
            let p_contact_email: String
            let p_city: String?
            let p_region: String?
            let p_country: String?
            let p_message: String?
        }
        try await Supa.client.rpc(
            "submit_partner_inquiry",
            params: Params(
                p_business_name: businessName,
                p_business_kind: kind,
                p_contact_email: email,
                p_city: city,
                p_region: region,
                p_country: country,
                p_message: message
            )
        ).execute()
    }
}

// MARK: - Leaderboards (all first-party signal)

struct LeaderBeer: Identifiable, Decodable, Sendable {
    let beerId: String
    let name: String
    let style: String?
    let breweryName: String?
    let country: String?
    let netVotes: Int
    let ups: Int
    let downs: Int
    let checkinCount: Int
    let avgRating: Double?

    var id: String { beerId }

    enum CodingKeys: String, CodingKey {
        case name, style, country, ups, downs
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case netVotes = "net_votes"
        case checkinCount = "checkin_count"
        case avgRating = "avg_rating"
    }
}

struct LeaderTaster: Identifiable, Decodable, Sendable {
    let userId: String
    let displayName: String
    let handle: String?
    let avatarUrl: String?
    let pours: Int
    let styles: Int
    let countries: Int

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case pours, styles, countries, handle
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct LeaderStyle: Identifiable, Decodable, Sendable {
    let style: String
    let pours: Int
    let avgRating: Double?
    let lastPourAt: String?

    var id: String { style }

    enum CodingKeys: String, CodingKey {
        case style, pours
        case avgRating = "avg_rating"
        case lastPourAt = "last_pour_at"
    }
}

enum LeaderboardService {
    private struct Params: Encodable { let p_limit: Int }

    static func beers(limit: Int = 20, naOnly: Bool = false) async throws -> [LeaderBeer] {
        struct BeerParams: Encodable {
            let p_limit: Int
            let p_na_only: Bool
        }
        return try await Supa.client
            .rpc("leaderboard_beers", params: BeerParams(p_limit: limit, p_na_only: naOnly))
            .execute().value
    }

    static func tasters(limit: Int = 20) async throws -> [LeaderTaster] {
        try await Supa.client.rpc("leaderboard_tasters", params: Params(p_limit: limit)).execute().value
    }

    static func styles(limit: Int = 20) async throws -> [LeaderStyle] {
        try await Supa.client.rpc("leaderboard_styles", params: Params(p_limit: limit)).execute().value
    }
}

// MARK: - Friends (search + follow)

struct FoundProfile: Identifiable, Decodable, Sendable {
    let userId: String
    let displayName: String
    let handle: String?
    let avatarUrl: String?
    let pours: Int
    var isFollowing: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case pours, handle
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isFollowing = "is_following"
    }
}

enum SocialGraphService {
    static func search(_ query: String, limit: Int = 12) async throws -> [FoundProfile] {
        struct Params: Encodable {
            let p_query: String
            let p_limit: Int
        }
        return try await Supa.client
            .rpc("search_profiles", params: Params(p_query: query, p_limit: limit))
            .execute().value
    }

    static func follow(_ userId: String) async throws {
        struct Params: Encodable { let p_followee: String }
        try await Supa.client.rpc("follow_user", params: Params(p_followee: userId)).execute()
    }

    static func unfollow(_ userId: String) async throws {
        struct Params: Encodable { let p_followee: String }
        try await Supa.client.rpc("unfollow_user", params: Params(p_followee: userId)).execute()
    }
}

// MARK: - Scan-to-catalog (Open Food Facts barcode fallback)

struct OFFBeer: Sendable {
    let barcode: String
    let name: String
    let brand: String?
    let abv: Double?
    let imageURL: String?
    let isBeerCategory: Bool
}

enum BarcodeCatalogService {
    /// Looks up a scanned barcode against Open Food Facts (free, open database).
    /// Returns nil when the product is unknown, never invents a beer.
    static func lookup(barcode: String) async throws -> OFFBeer? {
        let digits = barcode.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        var request = URLRequest(url: URL(string:
            "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,brands,categories_tags,image_front_url,nutriments"
        )!)
        request.setValue("Tapt/1.0 (iOS; beer passport)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        struct OFFResponse: Decodable {
            let status: Int?
            let product: Product?
            struct Product: Decodable {
                let productName: String?
                let brands: String?
                let categoriesTags: [String]?
                let imageFrontUrl: String?
                let nutriments: Nutriments?
                enum CodingKeys: String, CodingKey {
                    case brands, nutriments
                    case productName = "product_name"
                    case categoriesTags = "categories_tags"
                    case imageFrontUrl = "image_front_url"
                }
            }
            struct Nutriments: Decodable {
                let alcohol: Double?
                enum CodingKeys: String, CodingKey {
                    case alcohol = "alcohol_100g"
                }
            }
        }

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1,
              let product = decoded.product,
              let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return nil }

        let categories = product.categoriesTags ?? []
        let isBeer = categories.contains { $0.contains("beer") }
        let abv = product.nutriments?.alcohol.flatMap { (0...70).contains($0) ? $0 : nil }
        let brand = product.brands?
            .split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return OFFBeer(
            barcode: digits,
            name: name,
            brand: (brand?.isEmpty == false) ? brand : nil,
            abv: abv,
            imageURL: product.imageFrontUrl,
            isBeerCategory: isBeer
        )
    }

    /// Adds the looked-up product to the Tapt catalog (server dedups by GTIN)
    /// and returns a loggable pick.
    static func addToCatalog(_ off: OFFBeer) async throws -> BeerPick? {
        struct Params: Encodable {
            let p_gtin: String
            let p_name: String
            let p_brand: String?
            let p_style: String?
            let p_abv: Double?
            let p_country: String?
            let p_image_url: String?
        }
        struct Row: Decodable {
            let id: String
            let name: String
            let style: String?
            let abv: Double?
            let breweryName: String?
            let country: String?
            enum CodingKeys: String, CodingKey {
                case id, name, style, abv, country
                case breweryName = "brewery_name"
            }
        }
        let rows: [Row] = try await Supa.client.rpc(
            "add_beer_from_barcode",
            params: Params(
                p_gtin: off.barcode,
                p_name: off.name,
                p_brand: off.brand,
                p_style: nil,
                p_abv: off.abv,
                p_country: nil,
                p_image_url: off.imageURL
            )
        ).execute().value
        guard let row = rows.first else { return nil }
        return BeerPick(
            id: row.id,
            name: row.name,
            style: row.style,
            abv: row.abv,
            breweryName: row.breweryName ?? "",
            country: row.country ?? ""
        )
    }
}
