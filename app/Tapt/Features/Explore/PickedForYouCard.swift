import SwiftUI

/// One real beer the user has not had, chosen to fit their taste (see the
/// recommend_beer SQL). Honest by construction: the reason states only true
/// attributes, and the card only appears once there is real signal to pick on.
struct RecommendedBeer: Decodable, Identifiable, Sendable {
    let beerId: String
    let name: String
    let brewery: String?
    let style: String?
    let country: String?
    let imageUrl: String?
    let abv: Double?
    let reason: String
    let matchKind: String
    /// ISO week Monday (YYYY-MM-DD) when this beer was the weekly pick. Present
    /// on weekly_pick / pick_history rows, nil on the menu pick.
    var weekStart: String? = nil

    var id: String { weekStart.map { "\(beerId)-\($0)" } ?? beerId }

    enum CodingKeys: String, CodingKey {
        case name, brewery, style, country, reason
        case beerId = "beer_id"
        case imageUrl = "image_url"
        case abv
        case matchKind = "match_kind"
        case weekStart = "week_start"
    }
}

enum RecommendationService {
    struct Params: Encodable, Sendable { let p_user: String }
    struct MenuParams: Encodable, Sendable { let p_user: String; let p_beer_ids: [String] }

    /// The user's pick for today, or nil when there is not enough taste signal yet.
    static func pick(userId: UUID) async throws -> RecommendedBeer? {
        let rows: [RecommendedBeer] = try await Supa.authedRPC(
            "recommend_beer", params: Params(p_user: userId.uuidString)
        )
        return rows.first
    }

    /// This week's pick: stable all week, recomputed each new week from the
    /// user's latest taste. nil until there is real signal to pick on.
    static func weeklyPick(userId: UUID) async throws -> RecommendedBeer? {
        let rows: [RecommendedBeer] = try await Supa.authedRPC(
            "weekly_pick", params: Params(p_user: userId.uuidString)
        )
        return rows.first
    }

    struct HistoryParams: Encodable, Sendable { let p_user: String; let p_limit: Int }
    /// The log of past weekly picks, newest first, for the profile.
    static func pickHistory(userId: UUID, limit: Int = 24) async -> [RecommendedBeer] {
        let rows: [RecommendedBeer]? = try? await Supa.authedRPC(
            "pick_history", params: HistoryParams(p_user: userId.uuidString, p_limit: limit)
        )
        return rows ?? []
    }

    /// The single beer ON a scanned menu that best fits the user's taste, or nil
    /// when there is no taste signal or nothing on the menu matched.
    static func menuPick(userId: UUID, beerIds: [String]) async -> RecommendedBeer? {
        guard !beerIds.isEmpty else { return nil }
        let rows: [RecommendedBeer]? = try? await Supa.authedRPC(
            "recommend_from_menu", params: MenuParams(p_user: userId.uuidString, p_beer_ids: beerIds)
        )
        return rows?.first
    }
}

/// "Picked for you": the taste-matched recommendation card on Explore.
struct PickedForYouCard: View {
    let beer: RecommendedBeer

    var body: some View {
        NavigationLink { BeerDetailView(beerId: beer.beerId) } label: {
            HStack(spacing: 14) {
                BeerThumb(
                    imageUrl: beer.imageUrl,
                    size: 64,
                    corner: 14,
                    style: beer.style,
                    beerName: beer.name,
                    breweryName: beer.brewery
                )
                VStack(alignment: .leading, spacing: 3) {
                    Label("Picked for you", systemImage: "sparkles")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Brand.copper)
                        .labelStyle(.titleAndIcon)
                    Text(beer.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    Text(beer.reason)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Brand.gold.opacity(0.16), Brand.surface],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.35)))
        }
        .buttonStyle(.taptPress)
        .padding(.horizontal)
    }
}

/// The log of every weekly "Picked for you" beer, newest first. So a drinker who
/// saw a pick but was not at a bar that week can still find it later, at the bar.
struct WeeklyPicksView: View {
    @Environment(Session.self) private var session
    @State private var picks: [RecommendedBeer] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            if picks.isEmpty && loaded {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Brand.muted)
                    Text("No picks yet")
                        .font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("Rate a few beers you like. Each week we pick one new beer for you, and it lands here to revisit.")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 64).padding(.horizontal, 32)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(picks) { pick in
                        NavigationLink { BeerDetailView(beerId: pick.beerId) } label: { row(pick) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Brand.background)
        .navigationTitle("Your weekly picks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded, let uid = session.user?.id else { return }
            picks = await RecommendationService.pickHistory(userId: uid)
            loaded = true
        }
    }

    private func row(_ pick: RecommendedBeer) -> some View {
        HStack(spacing: 12) {
            BeerImageView(
                url: pick.imageUrl,
                maxPixelSize: 160,
                style: pick.style,
                beerName: pick.name,
                breweryName: pick.brewery
            )
                .frame(width: 52, height: 52)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                if let wk = Self.weekLabel(pick.weekStart) {
                    Text(wk).font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.copper)
                }
                Text(pick.name).font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text).lineLimit(1)
                Text(pick.reason).font(.caption).foregroundStyle(Brand.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private static func weekLabel(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFmt.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return "Week of \(out.string(from: date))"
    }
}
