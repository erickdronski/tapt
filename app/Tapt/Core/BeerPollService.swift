import Foundation

/// Beer of the Week / Month / Year: the community crown. Candidates are the live
/// top of the Beer Market; the drinker thumbs each up, down, or skip. A winner
/// only exists once a period is complete and finished net-positive -- so the
/// Tapt honor badge a beer wears is earned, never seeded. All read from real
/// votes (see 20260717113000_beer_poll_week_month_year.sql).
enum PollPeriod: String, CaseIterable, Sendable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week:  return "Beer of the Week"
        case .month: return "Beer of the Month"
        case .year:  return "Beer of the Year"
        }
    }
    var short: String {
        switch self {
        case .week:  return "This week"
        case .month: return "This month"
        case .year:  return "This year"
        }
    }
    var icon: String {
        switch self {
        case .week:  return "calendar"
        case .month: return "calendar.badge.clock"
        case .year:  return "crown.fill"
        }
    }
}

struct PollCandidate: Decodable, Identifiable, Sendable {
    let beerId: String
    let name: String
    let style: String?
    let breweryName: String?
    let country: String?
    let labelImageUrl: String?
    let standing: Int?
    let myVote: Int?
    var id: String { beerId }
    enum CodingKeys: String, CodingKey {
        case name, style, country, standing
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case labelImageUrl = "label_image_url"
        case myVote = "my_vote"
    }
}

struct PollStanding: Decodable, Identifiable, Sendable {
    let rank: Int
    let beerId: String
    let name: String
    let style: String?
    let breweryName: String?
    let country: String?
    let labelImageUrl: String?
    let up: Int
    let down: Int
    let net: Int
    var id: String { beerId }
    enum CodingKeys: String, CodingKey {
        case rank, name, style, country, up, down, net
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case labelImageUrl = "label_image_url"
    }
}

struct PollWinner: Decodable, Sendable {
    let beerId: String
    let name: String
    let style: String?
    let breweryName: String?
    let country: String?
    let labelImageUrl: String?
    let net: Int
    let label: String
    enum CodingKeys: String, CodingKey {
        case name, style, country, net, label
        case beerId = "beer_id"
        case breweryName = "brewery_name"
        case labelImageUrl = "label_image_url"
    }
}

struct PollWin: Decodable, Identifiable, Sendable {
    let period: String
    let periodKey: String
    let net: Int
    let label: String
    var id: String { "\(period)-\(periodKey)" }
    var periodTitle: String { PollPeriod(rawValue: period)?.title ?? "Beer of Tapt" }
    enum CodingKeys: String, CodingKey {
        case period, net, label
        case periodKey = "period_key"
    }
}

struct PollPending: Decodable, Sendable {
    let period: String
    let pending: Int
}

enum BeerPollService {
    private struct PeriodParam: Encodable, Sendable { let p_period: String }
    private struct PeriodLimit: Encodable, Sendable { let p_period: String; let p_limit: Int }
    private struct CandParam: Encodable, Sendable { let p_period: String; let p_limit: Int; let p_user: String }
    private struct CastParam: Encodable, Sendable { let p_period: String; let p_beer: String; let p_vote: Int; let p_user: String }
    private struct UserParam: Encodable, Sendable { let p_user: String }
    private struct BeerParam: Encodable, Sendable { let p_beer: String }

    /// Candidates for a period: the live top of the Beer Market, plus my vote.
    /// p_user mirrors recommend_beer so my_vote resolves under the sim's shim too.
    static func candidates(_ period: PollPeriod, userId: UUID, limit: Int = 5) async -> [PollCandidate] {
        (try? await Supa.authedRPC("beer_poll_candidates",
            params: CandParam(p_period: period.rawValue, p_limit: limit, p_user: userId.uuidString))) ?? []
    }

    /// Which periods still have candidates this drinker has not voted on.
    static func pendingPeriods(userId: UUID) async -> [PollPending] {
        (try? await Supa.authedRPC("beer_poll_pending_periods",
            params: UserParam(p_user: userId.uuidString))) ?? []
    }

    /// Cast up (1), down (-1), or skip (0) for the current period.
    static func cast(_ period: PollPeriod, beer: String, vote: Int, userId: UUID) async {
        try? await Supa.authedRPCVoid("beer_poll_cast",
            params: CastParam(p_period: period.rawValue, p_beer: beer, p_vote: vote, p_user: userId.uuidString))
    }

    /// Live standings for the current period.
    static func standings(_ period: PollPeriod, limit: Int = 20) async -> [PollStanding] {
        (try? await Supa.authedRPC("beer_poll_standings",
            params: PeriodLimit(p_period: period.rawValue, p_limit: limit))) ?? []
    }

    /// The reigning champion (winner of the last completed period), or nil.
    static func winner(_ period: PollPeriod) async -> PollWinner? {
        let rows: [PollWinner]? = try? await Supa.authedRPC("beer_poll_winner",
            params: PeriodParam(p_period: period.rawValue))
        return rows?.first
    }

    /// Every completed period this beer has won (for its honor badges).
    static func wins(beer: String) async -> [PollWin] {
        (try? await Supa.authedRPC("beer_poll_wins", params: BeerParam(p_beer: beer))) ?? []
    }
}
