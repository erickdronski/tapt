import Foundation
import Supabase

/// The Beer Market: beers ranked by community demand. The number is VOTES, not
/// dollars -- `net` is a beer's standing (up minus down), `change` is how its net
/// moved in the last 24h (trending up/down), `volume` is votes in that window. All
/// computed server-side in `beer_market`, never invented. Pre-launch it reads the
/// isolated, labeled demo lane; flip demo:false at launch to run on real votes.
struct MarketBeer: Identifiable, Decodable, Sendable, Hashable {
    let beerId: String
    let symbol: String
    let name: String
    let brewery: String?
    let style: String?
    let country: String?
    let imageUrl: String?
    let net: Int
    let votes: Int
    let change: Int
    let volume: Int
    let ups: Int
    let downs: Int
    let spark: [Double]
    let reason: String?
    let seasonFit: Int

    var id: String { beerId }
    var isUp: Bool { change >= 0 }
    var netText: String { net > 0 ? "+\(net)" : "\(net)" }
    var changeText: String { "\(change >= 0 ? "+" : "")\(change)" }
    /// A short human "why it's moving" line -- a real seasonal reason if it fits the
    /// season, otherwise the style. Never invented.
    var moveReason: String { reason ?? (style ?? "Community pick") }
    var isSeasonal: Bool { reason != nil }

    enum CodingKeys: String, CodingKey {
        case symbol, name, brewery, style, country, net, votes, change, volume, ups, downs, spark, reason
        case beerId = "beer_id"
        case imageUrl = "image_url"
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
    static func feed(sort: MarketSort = .movers, limit: Int = 40, demo: Bool = true) async throws -> [MarketBeer] {
        struct Params: Encodable { let p_sort: String; let p_limit: Int; let p_demo: Bool }
        return try await Supa.client
            .rpc("beer_market", params: Params(p_sort: sort.rawValue, p_limit: limit, p_demo: demo))
            .execute().value
    }
}
