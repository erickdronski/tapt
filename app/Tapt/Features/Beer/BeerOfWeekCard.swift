import SwiftUI

/// Beer of the Week — the community race. Standings are live net up-votes
/// this ISO week; a winner locks in every Monday (cron). Honest empty state
/// until votes exist.
struct BeerOfWeekCard: View {
    @State private var standings: [BeerOfWeekEntry] = []
    @State private var winner: BeerOfWeekEntry?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Beer of the Week", systemImage: "crown.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer()
                Text(weekLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }

            if let winner {
                NavigationLink { BeerDetailView(beerId: winner.beerId) } label: {
                    HStack(spacing: 10) {
                        Text("🏆").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Last week's winner: \(winner.name)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text("\(winner.breweryName ?? "") · \(winner.weekVotes) votes")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
                    }
                    .padding(10)
                    .background(Brand.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }

            if standings.isEmpty {
                Text("No votes yet this week. Thumb a beer up on the board below — the whole world sees the race.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(standings.prefix(3)) { entry in
                        NavigationLink { BeerDetailView(beerId: entry.beerId) } label: {
                            HStack(spacing: 10) {
                                Text(medal(entry.rank ?? 0))
                                    .font(.title3)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                                        .foregroundStyle(Brand.text)
                                        .lineLimit(1)
                                    Text([entry.breweryName, entry.country].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(Brand.muted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Label("\(entry.weekVotes)", systemImage: "hand.thumbsup.fill")
                                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                                    .foregroundStyle(Brand.hop)
                            }
                            .padding(10)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.3)))
        .task {
            guard !loaded else { return }
            loaded = true
            async let s: [BeerOfWeekEntry] = (try? BeerOfWeekService.standings(limit: 3)) ?? []
            async let w: BeerOfWeekEntry? = try? BeerOfWeekService.latestWinner()
            standings = await s
            winner = await w
        }
    }

    private var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return "Week of \(formatter.string(from: start))"
    }

    private func medal(_ rank: Int) -> String {
        switch rank {
        case 1: "🥇"
        case 2: "🥈"
        case 3: "🥉"
        default: "•"
        }
    }
}
