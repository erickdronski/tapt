import Foundation
import Supabase

/// The Beer Market: beers ranked by a real STANDING computed server-side in
/// `beer_market` -- a composite of what's genuinely in season now (time-varying),
/// real cited awards, catalog notability, and real community votes (which
/// dominate as they accumulate). `net` is that standing; `votes`/`ups`/`downs`
/// are real vote counts; `change` is the 24h standing move from stored daily
/// snapshots; `volume` is real vote/pour activity in the last 24h. Nothing is
/// invented -- the board is always populated from real signals and becomes fully
/// community-driven as people vote.
struct MarketBeer: Identifiable, Decodable, Sendable, Hashable {
    let beerId: String
    let symbol: String
    let name: String
    let brewery: String?
    let style: String?
    let country: String?
    let imageUrl: String?
    let isNaLow: Bool
    let net: Int
    let votes: Int
    let change: Int
    let volume: Int
    let ups: Int
    let downs: Int
    let spark: [Double]
    let reason: String?
    let seasonFit: Int
    /// 0-100 trending intensity relative to the hottest beer on the board right now.
    /// Drives the ticker/board pulse so a surge in global sentiment is impossible to miss.
    let heat: Int
    // Standing components (returned by beer_market_one only; nil on the lean
    // board feed). These power the "why this standing" breakdown on the beer
    // page: every point on the board is explainable, nothing is invented.
    var seasonPts: Int? = nil
    var awardPts: Int? = nil
    var notabilityPts: Int? = nil
    var votePts: Int? = nil
    var driftPts: Int? = nil

    var id: String { beerId }
    var isUp: Bool { change > 0 }
    /// Trend across the whole visible spark window (what a drawn sparkline
    /// shows). Falls back to the daily change when there is no window yet.
    var windowTrend: Int {
        // A flat current snapshot cannot safely prove that older scores were
        // calculated with the same formula. Prefer a conservative flat state.
        guard change != 0 else { return 0 }
        guard spark.count > 1, let first = spark.first, let last = spark.last else { return change }
        return Int(last - first)
    }
    var displaySpark: [Double] {
        change == 0 ? [Double(net)] : spark
    }
    /// No movement yet. Rendered as a neutral state, never a green "+0" --
    /// the board must not signal gains that do not exist.
    var isFlat: Bool { change == 0 }
    /// Standing is a level, not a gain: no "+" prefix.
    var netText: String { "\(net)" }
    var changeText: String { "\(change > 0 ? "+" : "")\(change)" }
    var voteBalance: Int { ups - downs }
    var voteBalanceText: String { "\(voteBalance > 0 ? "+" : "")\(voteBalance)" }
    var displayName: String { name.decodingCatalogEntities }
    var displayBrewery: String? { brewery?.decodingCatalogEntities }
    var displayStyle: String? { style?.decodingCatalogEntities }
    /// Worth a visible pulse ONLY when something is actually happening
    /// (real 24h activity or real movement), not from standing alone.
    var isHot: Bool { heat >= 70 && (volume > 0 || change != 0) }
    /// A short human "why it's moving" line -- a real seasonal reason if it fits the
    /// season, otherwise the style. Never invented.
    var moveReason: String {
        (reason ?? (style ?? "Movement detail unavailable")).decodingCatalogEntities
    }
    var isSeasonal: Bool { reason?.hasSuffix("in season now") == true }

    enum CodingKeys: String, CodingKey {
        case symbol, name, brewery, style, country, net, votes, change, volume, ups, downs, spark, reason, heat
        case beerId = "beer_id"
        case imageUrl = "image_url"
        case isNaLow = "is_na_low"
        case seasonFit = "season_fit"
        case seasonPts = "season_pts"
        case awardPts = "award_pts"
        case notabilityPts = "notability_pts"
        case votePts = "vote_pts"
        case driftPts = "drift_pts"
    }
}

private extension String {
    /// A few imported catalog sources HTML-encode punctuation in otherwise plain
    /// product text. Keep those source values intact while presenting clean labels.
    var decodingCatalogEntities: String {
        let replacements = [
            ("&#039;", "'"), ("&#39;", "'"), ("&apos;", "'"),
            ("&quot;", "\""), ("&#34;", "\""), ("&amp;", "&"),
            ("&lt;", "<"), ("&gt;", ">")
        ]
        let once = replacements.reduce(self) { value, replacement in
            value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
        return replacements.reduce(once) { value, replacement in
            value.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }
}

struct MarketPulse: Decodable, Sendable, Equatable {
    let computedAt: String?
    let tracked: Int
    let moving24h: Int
    let gainers24h: Int
    let sliders24h: Int
    let active24h: Int
    let votes24h: Int
    let pours24h: Int
    let votes7d: Int
    let pours7d: Int

    var communityActions24h: Int { votes24h + pours24h }
    var communityActions7d: Int { votes7d + pours7d }
    var isQuiet: Bool { communityActions24h == 0 }

    var updatedDate: Date? {
        guard let computedAt else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: computedAt) ?? ISO8601DateFormatter().date(from: computedAt)
    }

    func isFresh(at now: Date = .now) -> Bool {
        guard let updatedDate else { return false }
        return now.timeIntervalSince(updatedDate) < 65 * 60
    }

    enum CodingKeys: String, CodingKey {
        case tracked
        case computedAt = "computed_at"
        case moving24h = "moving_24h"
        case gainers24h = "gainers_24h"
        case sliders24h = "sliders_24h"
        case active24h = "active_24h"
        case votes24h = "votes_24h"
        case pours24h = "pours_24h"
        case votes7d = "votes_7d"
        case pours7d = "pours_7d"
    }
}

enum MarketSort: String, CaseIterable, Identifiable, Sendable {
    case movers, season, gainers, losers, active, top, standing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .movers: return "Moving"
        case .season: return "In season"
        case .gainers: return "Gaining"
        case .losers: return "Cooling"
        case .active: return "Active now"
        case .top: return "Top voted"
        case .standing: return "Top score"
        }
    }
    var icon: String {
        switch self {
        case .movers: return "arrow.up.arrow.down"
        case .season: return "sun.max.fill"
        case .gainers: return "chart.line.uptrend.xyaxis"
        case .losers: return "chart.line.downtrend.xyaxis"
        case .active: return "bolt.fill"
        case .top: return "trophy.fill"
        case .standing: return "list.number"
        }
    }

    var boardTitle: String {
        switch self {
        case .movers: return "Moving today"
        case .season: return "Built for this season"
        case .gainers: return "Gaining score"
        case .losers: return "Cooling today"
        case .active: return "Community activity"
        case .top: return "Top voted"
        case .standing: return "Highest Tapt Score"
        }
    }

    var boardSubtitle: String {
        switch self {
        case .movers: return "Largest changes since yesterday's snapshot."
        case .season: return "Season fit first, then Tapt Score."
        case .gainers: return "Only beers with a positive daily change."
        case .losers: return "Only beers with a negative daily change."
        case .active: return "Only beers with a vote or eligible pour in the last 24 hours."
        case .top: return "Only beers with real community votes. Net votes lead."
        case .standing: return "Tapt Score blends season, cited awards, votes, and eligible pours."
        }
    }

    var emptyTitle: String {
        switch self {
        case .movers: return "No score changes yet"
        case .season: return "No seasonal board yet"
        case .gainers: return "No beer is gaining today"
        case .losers: return "No beer is cooling today"
        case .active: return "No community activity today"
        case .top: return "No community votes yet"
        case .standing: return "No score data yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .movers: return "The latest snapshot is steady. A real vote or eligible pour can start the next move."
        case .season: return "No beer currently meets the seasonal fit threshold."
        case .gainers: return "The latest snapshot has no positive score changes."
        case .losers: return "The latest snapshot has no negative score changes."
        case .active: return "There are no votes or eligible pours in the last 24 hours."
        case .top: return "Cast the first vote from a beer page to start this board."
        case .standing: return "The score engine has not published a board yet."
        }
    }

    var leadsWithMovement: Bool {
        self == .movers || self == .gainers || self == .losers
    }
}

enum MarketService {
    // The old marketing "demo lane" is gone: since the real standing engine
    // (0058+) the board is always populated with REAL data, so there is
    // nothing to fake and nothing to label. p_demo remains in the RPC
    // signature for wire compatibility only; the server ignores it.
    static func feed(
        sort: MarketSort = .movers,
        limit: Int = 40,
        naOnly: Bool = false
    ) async throws -> [MarketBeer] {
        struct Params: Encodable {
            let p_sort: String
            let p_limit: Int
            let p_demo: Bool
            let p_na_only: Bool
        }
        return try await Supa.client
            .rpc(
                "beer_market_v2",
                params: Params(
                    p_sort: sort.rawValue,
                    p_limit: limit,
                    p_demo: false,
                    p_na_only: naOnly
                )
            )
            .execute()
            .value
    }

    static func pulse() async throws -> MarketPulse? {
        let rows: [MarketPulse] = try await Supa.client
            .rpc("beer_market_pulse")
            .execute()
            .value
        return rows.first
    }

    /// One beer's live standing + 7-day sparkline for the unified beer profile.
    /// Anon-capable (beer_market_one is granted to anon + authenticated), so a
    /// guest browsing a beer page sees it too. Returns nil when the beer isn't on
    /// the board yet, so the profile simply hides its market block. Non-fatal.
    static func one(beerId: String) async throws -> MarketBeer? {
        struct Params: Encodable { let p_beer_id: String }
        let rows: [MarketBeer] = try await Supa.client
            .rpc("beer_market_one", params: Params(p_beer_id: beerId))
            .execute().value
        return rows.first
    }
}
