import Foundation
import SwiftUI

struct TonightView: View {
    @Environment(Session.self) private var session
    @State private var selectedTab = TonightTab.tonight
    @State private var tonight: [TonightBeer] = []
    @State private var pours: [SocialPour] = []
    @State private var tasteProfile: [TasteProfilePoint] = []
    @State private var loading = false
    @State private var message: String?
    @State private var reportedCheckins: Set<String> = []
    @State private var blockedActors: Set<String> = []

    private var topBeer: TonightBeer? { tonight.first }
    private var maxTasteCount: Int { max(tasteProfile.map(\.pourCount).max() ?? 1, 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                tabPicker
                if let message {
                    status(message)
                }
                switch selectedTab {
                case .tonight:
                    tonightSection
                case .friends:
                    socialSection
                case .taste:
                    tasteSection
                }
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .navigationTitle("Tonight")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .overlay { if loading && tonight.isEmpty && pours.isEmpty { ProgressView().tint(Brand.gold) } }
    }

    private var hero: some View {
        TaptHeroPanel(
            title: topBeer?.beerName ?? "What is good tonight",
            subtitle: topBeer.map { beer in
                let place = beer.venueName?.isEmpty == false ? beer.venueName! : "the live board"
                return "\(beer.breweryName ?? "A brewery") is showing heat from \(place)."
            } ?? "Live tap-list scans, market heat, and your circle's pours come together here.",
            metric: topBeer.map { "\($0.heatScore)" } ?? "LIVE",
            caption: topBeer?.sourceLabel.capitalized ?? "Tonight feed",
            icon: "sparkles",
            tint: Brand.gold
        )
        .padding(.horizontal)
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(TonightTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? tab.tint : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selectedTab == tab ? Brand.malt : Brand.text)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tab.tint.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var tonightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("What is good here", "Tap-list intelligence plus market heat")
            if tonight.isEmpty {
                TaptEmptyState(
                    icon: "mug.fill",
                    title: "No live beer heat yet",
                    message: "As tap lists and check-ins build up, this becomes the quick answer for what to order tonight.",
                    actionTitle: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(tonight.prefix(20).enumerated()), id: \.element.id) { index, beer in
                        tonightRow(rank: index + 1, beer: beer)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Your circle is drinking", "Your pours and people you follow")
            if pours.isEmpty {
                TaptEmptyState(
                    icon: "person.2.fill",
                    title: "No social pours yet",
                    message: "Log a pour or follow friends to turn Tapt into a live beer night feed.",
                    actionTitle: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(pours) { pour in
                        socialRow(pour)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var tasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Taste graph", "Private style signal from your check-ins")
            if tasteProfile.isEmpty {
                TaptEmptyState(
                    icon: "chart.bar.xaxis",
                    title: "Your graph needs pours",
                    message: "Log beers across styles and Tapt will start showing where your palate is strongest.",
                    actionTitle: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(tasteProfile.prefix(12))) { point in
                        tasteRow(point)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func tonightRow(rank: Int, beer: TonightBeer) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.headline, design: .monospaced).weight(.bold))
                .foregroundStyle(Brand.muted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(beer.beerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(rowSubtitle([
                    beer.breweryName,
                    beer.style,
                    beer.venueName
                ]))
                .font(.caption)
                .foregroundStyle(Brand.muted)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Label("\(beer.heatScore)", systemImage: "flame.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.copper)
                Text(beer.sourceLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(13)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.gold.opacity(0.18), lineWidth: 1))
    }

    private func socialRow(_ pour: SocialPour) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(pour.actorName.first ?? "T").uppercased())
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.malt)
                .frame(width: 42, height: 42)
                .background(Brand.gold, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pour.actorName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Spacer()
                    if let rating = pour.rating {
                        Label(String(format: "%.0f", rating), systemImage: "star.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Brand.gold)
                    }
                }
                Text(pour.beerName ?? "A beer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(rowSubtitle([pour.breweryName, pour.style, pour.venueName]))
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                actionStrip(for: pour)
            }
        }
        .padding(13)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.malt.opacity(0.08), lineWidth: 1))
    }

    private func actionStrip(for pour: SocialPour) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await report(pour) }
            } label: {
                Label(reportedCheckins.contains(pour.checkinId) ? "Reported" : "Report", systemImage: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(reportedCheckins.contains(pour.checkinId) ? Brand.hop : Brand.muted)
            }
            .buttonStyle(.plain)
            .disabled(reportedCheckins.contains(pour.checkinId))

            if pour.actorId != session.user?.id.uuidString {
                Button {
                    Task { await block(pour) }
                } label: {
                    Label(blockedActors.contains(pour.actorId) ? "Blocked" : "Block", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(blockedActors.contains(pour.actorId) ? Brand.hop : Brand.muted)
                }
                .buttonStyle(.plain)
                .disabled(blockedActors.contains(pour.actorId))
            }
        }
        .padding(.top, 4)
    }

    private func tasteRow(_ point: TasteProfilePoint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(point.style)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Spacer()
                Text("\(point.pourCount)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.hop)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.haze.opacity(0.75))
                    Capsule()
                        .fill(LinearGradient(colors: [Brand.hop, Brand.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, proxy.size.width * CGFloat(point.pourCount) / CGFloat(maxTasteCount)))
                }
            }
            .frame(height: 10)
            if let avgRating = point.avgRating {
                Text("Average rating \(String(format: "%.1f", avgRating))")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(13)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Brand.hop.opacity(0.18), lineWidth: 1))
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .padding(.horizontal)
    }

    private func status(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.hop)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Brand.hop.opacity(0.12), in: Capsule())
            .padding(.horizontal)
    }

    private func rowSubtitle(_ parts: [String?]) -> String {
        let values = parts.compactMap { part -> String? in
            guard let part, !part.isEmpty else { return nil }
            return part
        }
        return values.isEmpty ? "Tapt live signal" : values.joined(separator: "  ")
    }

    private func loadAll() async {
        loading = true
        defer { loading = false }
        await loadTonight()
        await loadSocial()
        await loadTaste()
    }

    private func loadTonight() async {
        tonight = (try? await LiveBeerService.tonight(limit: 24)) ?? []
    }

    private func loadSocial() async {
        guard session.user != nil else {
            pours = []
            return
        }
        pours = (try? await LiveBeerService.socialPours(limit: 30)) ?? []
    }

    private func loadTaste() async {
        guard let userId = session.user?.id else {
            tasteProfile = []
            return
        }
        tasteProfile = (try? await LiveBeerService.tasteProfile(userId: userId)) ?? []
    }

    private func report(_ pour: SocialPour) async {
        guard let uid = session.user?.id else { return }
        do {
            try await LiveBeerService.report(checkinId: pour.checkinId, userId: uid, reason: "in_app_report")
            reportedCheckins.insert(pour.checkinId)
            message = "Report sent for review."
        } catch {
            message = "Could not send report."
        }
    }

    private func block(_ pour: SocialPour) async {
        guard let uid = session.user?.id else { return }
        do {
            try await LiveBeerService.block(actorId: pour.actorId, userId: uid)
            blockedActors.insert(pour.actorId)
            pours.removeAll { $0.actorId == pour.actorId }
            message = "This profile is blocked."
        } catch {
            message = "Could not block profile."
        }
    }
}

private enum TonightTab: String, CaseIterable, Identifiable {
    case tonight
    case friends
    case taste

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonight: return "Tonight"
        case .friends: return "Friends"
        case .taste: return "Taste"
        }
    }

    var icon: String {
        switch self {
        case .tonight: return "flame.fill"
        case .friends: return "person.2.fill"
        case .taste: return "chart.bar.xaxis"
        }
    }

    var tint: Color {
        switch self {
        case .tonight: return Brand.gold
        case .friends: return Brand.copper
        case .taste: return Brand.hop
        }
    }
}
