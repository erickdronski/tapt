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
        if (try? await Supa.client.auth.session.user) == nil {
            var request = URLRequest(url: Supa.url.appendingPathComponent("functions/v1/dispatch-signup"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "email": email,
                "website": "",
                "source": source
            ])
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            return
        }

        struct Params: Encodable {
            let p_email: String
            let p_source: String
            let p_ui_text: String
        }
        try await Supa.authedRPCVoid(
            "subscribe_newsletter",
            params: Params(
                p_email: email,
                p_source: source,
                p_ui_text: "Send me The Tapt Dispatch: beer trends, new spots, and what the world is pouring."
            )
        )
    }

    static func unsubscribe() async throws {
        struct Empty: Encodable {}
        try await Supa.authedRPCVoid("unsubscribe_newsletter", params: Empty())
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

struct VenueSearchResult: Identifiable, Decodable, Sendable {
    let venueId: String
    let name: String
    let city: String?
    let region: String?
    let country: String?

    var id: String { venueId }
    var placeLine: String {
        [city, region, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case name, city, region, country
        case venueId = "venue_id"
    }
}

enum PartnerService {
    static func searchVenues(_ query: String, limit: Int = 20) async throws -> [VenueSearchResult] {
        struct Params: Encodable { let p_query: String; let p_limit: Int }
        return try await Supa.authedRPC(
            "search_venues",
            params: Params(p_query: query, p_limit: limit)
        )
    }

    static func featured(limit: Int = 10, region: String? = nil) async throws -> [FeaturedPartner] {
        struct Params: Encodable { let p_limit: Int; let p_region: String? }
        return try await Supa.client
            .rpc("featured_partner_feed", params: Params(p_limit: limit, p_region: region))
            .execute().value
    }

    /// Log a reach event for a featured card so a partner can see what Featured
    /// bought them: "impression" when the card is shown, "tap" when it is opened.
    static func logFeatured(id: String, event: String, region: String? = nil) async {
        struct Params: Encodable { let p_featured: String; let p_event: String; let p_region: String? }
        _ = try? await Supa.client
            .rpc("log_featured_event", params: Params(p_featured: id, p_event: event, p_region: region))
            .execute()
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

    /// Confirm a filed inquiry and route the submitter to the portal. The edge
    /// function emails only the caller's own verified address (derived from the
    /// session, never from the client), so we pass no recipient. Best effort,
    /// like logFeatured: a delivery miss must never block or fail the inquiry,
    /// so every error is swallowed.
    static func sendInquiryAck() async {
        struct Body: Encodable { let kind: String }
        guard let session = try? await Supa.client.auth.session else { return }
        var request = URLRequest(url: Supa.url.appendingPathComponent("functions/v1/resend-send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Supa.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(Body(kind: "inquiry_ack"))
        _ = try? await URLSession.shared.data(for: request)
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
    let imageUrl: String?

    var id: String { beerId }

    enum CodingKeys: String, CodingKey {
        case name, style, country, ups, downs
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case netVotes = "net_votes"
        case checkinCount = "checkin_count"
        case avgRating = "avg_rating"
        case imageUrl = "image_url"
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
        return try await Supa.authedRPC(
            "leaderboard_beers",
            params: BeerParams(p_limit: limit, p_na_only: naOnly)
        )
    }

    static func tasters(limit: Int = 20) async throws -> [LeaderTaster] {
        try await Supa.authedRPC("leaderboard_tasters", params: Params(p_limit: limit))
    }

    static func styles(limit: Int = 20) async throws -> [LeaderStyle] {
        try await Supa.authedRPC("leaderboard_styles", params: Params(p_limit: limit))
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
        return try await Supa.authedRPC(
            "search_profiles",
            params: Params(p_query: query, p_limit: limit)
        )
    }

    static func follow(_ userId: String) async throws {
        struct Params: Encodable { let p_followee: String }
        try await Supa.authedRPCVoid("follow_user", params: Params(p_followee: userId))
    }

    static func unfollow(_ userId: String) async throws {
        struct Params: Encodable { let p_followee: String }
        try await Supa.authedRPCVoid("unfollow_user", params: Params(p_followee: userId))
    }

    /// The public passport card shown when you tap a person you follow (or found
    /// in search / the Tonight feed). Coarse aggregates only -- the server never
    /// returns venues, timestamps, or geo. Honors blocks + the social_visible switch.
    static func profile(_ userId: String) async throws -> ProfileCard {
        struct Params: Encodable { let p_user: String }
        return try await Supa.authedRPC(
            "public_profile",
            params: Params(p_user: userId)
        )
    }
}

/// A small, honest snapshot of another drinker: passport totals, a favorite pour,
/// and top styles. Mirrors public_profile()'s jsonb shape 1:1.
struct ProfileCard: Decodable, Sendable {
    let userId: String
    let displayName: String
    let handle: String?
    let avatarUrl: String?
    let region: String?
    let memberSince: String?
    let isSelf: Bool
    var isFollowing: Bool
    let visible: Bool
    let blocked: Bool
    let followers: Int
    let following: Int
    let pours: Int?
    let beersCount: Int?
    let stylesCount: Int?
    let countries: Int?
    let states: Int?
    let breweries: Int?
    let styleFamilies: Int?
    let continents: Int?
    let seasons: Int?
    let noLow: Int?
    let hoppy: Int?
    let dark: Int?
    let wheat: Int?
    let sour: Int?
    let belgian: Int?
    let crisp: Int?
    let topStyles: [StyleCount]?
    let favoriteBeer: FavoriteBeer?

    struct StyleCount: Decodable, Sendable, Identifiable {
        let style: String
        let pours: Int
        var id: String { style }
    }
    struct FavoriteBeer: Decodable, Sendable {
        let name: String
        let brewery: String?
        let pours: Int
        let imageUrl: String?

        enum CodingKeys: String, CodingKey {
            case name, brewery, pours
            case imageUrl = "image_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case handle, region, visible, blocked, followers, following, pours, countries, states
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case memberSince = "member_since"
        case isSelf = "is_self"
        case isFollowing = "is_following"
        case beersCount = "beers_count"
        case stylesCount = "styles_count"
        case topStyles = "top_styles"
        case favoriteBeer = "favorite_beer"
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
        request.setValue("Tapt/1.0 (iOS; THE Beer Superapp)", forHTTPHeaderField: "User-Agent")
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
        struct Body: Encodable { let barcode: String }
        struct Payload: Decodable { let beer: Row? }

        let session = try await Supa.client.auth.session
        var request = URLRequest(url: Supa.url.appendingPathComponent("functions/v1/verify-barcode-beer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Supa.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Body(barcode: off.barcode))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        guard let row = try JSONDecoder().decode(Payload.self, from: data).beer else { return nil }
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

// MARK: - Partner live menus (QR -> in-app)

struct VenueMenuRow: Identifiable, Decodable, Sendable {
    let tapItemId: String
    let venueName: String
    let city: String?
    let region: String?
    let country: String?
    let beerId: String?
    let beerName: String
    let breweryName: String?
    let style: String?
    let abv: Double?
    let beerCountry: String?
    let priceText: String?

    var id: String { tapItemId }

    var beerPick: BeerPick? {
        guard let beerId else { return nil }
        return BeerPick(
            id: beerId,
            name: beerName,
            style: style,
            abv: abv,
            breweryName: breweryName ?? "",
            country: beerCountry ?? ""
        )
    }

    enum CodingKeys: String, CodingKey {
        case tapItemId = "tap_item_id"
        case venueName = "venue_name"
        case city, region, country
        case beerId = "beer_id"
        case beerName = "beer_name"
        case breweryName = "brewery_name"
        case style, abv
        case beerCountry = "beer_country"
        case priceText = "price_text"
    }
}

struct VenueEvent: Identifiable, Decodable, Sendable {
    let kind: String
    let title: String
    let details: String?
    let startsAt: String?
    let endsAt: String?

    var id: String { [kind, title, startsAt ?? ""].joined(separator: "|") }
    var kindLabel: String { kind.replacingOccurrences(of: "_", with: " ").capitalized }
    var scheduleLabel: String? {
        guard let start = Self.date(from: startsAt) else { return nil }
        let startText = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        guard let end = Self.date(from: endsAt) else { return startText }
        return "\(startText) - \(end.formatted(.dateTime.hour().minute()))"
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, details
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum VenueMenuService {
    static func menu(venueId: String) async throws -> [VenueMenuRow] {
        struct Params: Encodable { let p_venue: String }
        return try await Supa.client.rpc("venue_menu", params: Params(p_venue: venueId)).execute().value
    }

    static func events(venueId: String) async throws -> [VenueEvent] {
        struct Params: Encodable { let p_venue: String }
        return try await Supa.client.rpc("venue_events", params: Params(p_venue: venueId)).execute().value
    }
}

/// Enriched, honest venue detail for the map sheet: only real fields from the
/// venue row + external_ids, plus whether it is claimed. Anon-capable.
struct VenueDetail: Decodable, Sendable {
    let name: String?
    let logoUrl: String?
    let poiCategory: String?
    let onOffPremise: String?
    let address: String?
    let city: String?
    let region: String?
    let country: String?
    let postalCode: String?
    let phone: String?
    let websiteUrl: String?
    let sourceNote: String?
    let isClaimed: Bool

    enum CodingKeys: String, CodingKey {
        case name, address, city, region, country, phone
        case logoUrl = "logo_url"
        case poiCategory = "poi_category"
        case onOffPremise = "on_off_premise"
        case postalCode = "postal_code"
        case websiteUrl = "website_url"
        case sourceNote = "source_note"
        case isClaimed = "is_claimed"
    }
}

enum VenueDetailService {
    static func detail(venueId: String) async throws -> VenueDetail? {
        struct Params: Encodable { let p_venue: String }
        let rows: [VenueDetail] = try await Supa.client
            .rpc("venue_detail", params: Params(p_venue: venueId)).execute().value
        return rows.first
    }
}
