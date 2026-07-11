import Foundation
import Supabase

/// The Beer Market: beers as tickers. Price is derived from real community demand
/// (net votes), movement from vote velocity -- all computed server-side in
/// `beer_market`, never invented. Pre-launch the app reads the isolated, clearly
/// labeled demo lane so the ticker is alive; it flips to real votes at launch.
struct MarketBeer: Identifiable, Decodable, Sendable, Hashable {
    let beerId: String
    let symbol: String
    let name: String
    let brewery: String?
    let style: String?
    let country: String?
    let imageUrl: String?
    let price: Double
    let changePct: Double
    let volume: Int
    let net: Int
    let ups: Int
    let downs: Int
    let marketCap: Double
    let spark: [Double]

    var id: String { beerId }
    var isUp: Bool { changePct >= 0 }
    var priceText: String { String(format: "$%.2f", price) }
    var changeText: String { String(format: "%@%.2f%%", changePct >= 0 ? "+" : "", changePct) }
    var marketCapText: String {
        marketCap >= 1000 ? String(format: "$%.1fK", marketCap / 1000) : String(format: "$%.0f", marketCap)
    }

    enum CodingKeys: String, CodingKey {
        case symbol, name, brewery, style, country, price, volume, net, ups, downs, spark
        case beerId = "beer_id"
        case imageUrl = "image_url"
        case changePct = "change_pct"
        case marketCap = "market_cap"
    }
}

enum MarketSort: String, CaseIterable, Identifiable {
    case movers, gainers, losers, active
    var id: String { rawValue }
    var title: String {
        switch self {
        case .movers: return "Top movers"
        case .gainers: return "Gainers"
        case .losers: return "Losers"
        case .active: return "Most active"
        }
    }
    var icon: String {
        switch self {
        case .movers: return "arrow.up.arrow.down"
        case .gainers: return "chart.line.uptrend.xyaxis"
        case .losers: return "chart.line.downtrend.xyaxis"
        case .active: return "bolt.fill"
        }
    }
}

enum MarketService {
    /// Pre-launch the real boards are empty, so we read the demo lane (labeled in the
    /// UI). Flip to `demo: false` at launch and the exact same view runs on real votes.
    static func feed(sort: MarketSort = .movers, limit: Int = 40, demo: Bool = true) async throws -> [MarketBeer] {
        struct Params: Encodable { let p_sort: String; let p_limit: Int; let p_demo: Bool }
        return try await Supa.client
            .rpc("beer_market", params: Params(p_sort: sort.rawValue, p_limit: limit, p_demo: demo))
            .execute().value
    }
}
