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

    var id: String { beerId }

    enum CodingKeys: String, CodingKey {
        case name, brewery, style, country, reason
        case beerId = "beer_id"
        case imageUrl = "image_url"
        case abv
        case matchKind = "match_kind"
    }
}

enum RecommendationService {
    struct Params: Encodable, Sendable { let p_user: String }

    /// The user's pick for today, or nil when there is not enough taste signal yet.
    static func pick(userId: UUID) async throws -> RecommendedBeer? {
        let rows: [RecommendedBeer] = try await Supa.authedRPC(
            "recommend_beer", params: Params(p_user: userId.uuidString)
        )
        return rows.first
    }
}

/// "Picked for you": the taste-matched recommendation card on Explore.
struct PickedForYouCard: View {
    let beer: RecommendedBeer

    var body: some View {
        NavigationLink { BeerDetailView(beerId: beer.beerId) } label: {
            HStack(spacing: 14) {
                BeerThumb(imageUrl: beer.imageUrl, size: 64, corner: 14)
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
