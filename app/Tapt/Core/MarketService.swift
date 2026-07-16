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

    var id: String { beerId }
    var isUp: Bool { change > 0 }
    /// Trend across the whole visible spark window (what a drawn sparkline
    /// shows). Falls back to the daily change when there is no window yet.
    var windowTrend: Int {
        guard spark.count > 1, let first = spark.first, let last = spark.last else { return change }
        return Int(last - first)
    }
    /// No movement yet. Rendered as a neutral state, never a green "+0" --
    /// the board must not signal gains that do not exist.
    var isFlat: Bool { change == 0 }
    /// Standing is a level, not a gain: no "+" prefix.
    var netText: String { "\(net)" }
    var changeText: String { "\(change > 0 ? "+" : "")\(change)" }
    /// Worth a visible pulse ONLY when something is actually happening
    /// (real 24h activity or real movement), not from standing alone.
    var isHot: Bool { heat >= 70 && (volume > 0 || change != 0) }
    /// A short human "why it's moving" line -- a real seasonal reason if it fits the
    /// season, otherwise the style. Never invented.
    var moveReason: String { reason ?? (style ?? "Community pick") }
    var isSeasonal: Bool { reason != nil }

    enum CodingKeys: String, CodingKey {
        case symbol, name, brewery, style, country, net, votes, change, volume, ups, downs, spark, reason, heat
        case beerId = "beer_id"
        case imageUrl = "image_url"
        case isNaLow = "is_na_low"
        case seasonFit = "season_fit"
    }
}

enum MarketSort: String, CaseIterable, Identifiable {
    case movers, season, gainers, losers, active, top
    var id: String { rawValue }
    var title: String {
        switch self {
        case .movers: return "Top movers"
        case .season: return "In season"
        case .gainers: return "Gaining"
        case .losers: return "Sliding"
        case .active: return "Most active"
        case .top: return "Top voted"
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
        }
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
        // authedRPC: the market is authenticated-only; never let the SDK's
        // silent anon fallback turn an auth blip into an "empty board".
        return try await Supa.authedRPC(
            "beer_market_v2",
            params: Params(
                p_sort: sort.rawValue,
                p_limit: limit,
                p_demo: false,
                p_na_only: naOnly
            )
        )
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
