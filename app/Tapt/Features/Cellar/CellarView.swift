import SwiftUI

/// Cellar: your logged pours + a Passport strip (pours, styles, countries). Log flow wired in.
struct CellarView: View {
    @Environment(Session.self) private var session
    @State private var checkins: [MyCheckin] = []
    @State private var guides: [RegionBeerGuide] = []
    @State private var showLog = false
    @State private var appeared = false

    private var styleCount: Int {
        Set(checkins.compactMap { ($0.style?.isEmpty == false) ? $0.style : nil }).count
    }
    private var countryCount: Int {
        Set(checkins.map(\.country).filter { !$0.isEmpty }).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                if checkins.isEmpty { empty } else { content }
            }
            .navigationTitle("Cellar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showLog = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Brand.gold)
                    }
                }
            }
            .task { await load() }
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { appeared = true }
            }
            .sheet(isPresented: $showLog) {
                LogPourView(onLogged: { Task { await load() } })
            }
        }
    }

    private var empty: some View {
        TaptEmptyState(
            icon: "square.stack.3d.up.fill",
            title: "Your Cellar is thirsty",
            message: "Log your first pour to start your Cellar, unlock Passport stamps, and build your beer taste graph.",
            actionTitle: "Log a pour",
            action: { showLog = true }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TaptHeroPanel(
                    title: "Passport progress",
                    subtitle: "\(checkins.count) pours logged across \(styleCount) styles and \(countryCount) countries.",
                    metric: "\(checkins.count)",
                    caption: nextMilestone,
                    icon: "seal.fill",
                    tint: Brand.hop
                )
                .padding(.horizontal)

                NavigationLink { PassportView(checkins: checkins, guides: guides) } label: {
                    HStack(spacing: 6) {
                        Text("Passport").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Brand.muted)
                    }
                }
                .buttonStyle(.plain).padding(.horizontal)
                HStack(spacing: 12) {
                    stat("\(checkins.count)", "pours", "drop.fill", Brand.gold)
                    stat("\(styleCount)", "styles", "square.grid.2x2.fill", Brand.hop)
                    stat("\(countryCount)", "countries", "globe", Brand.copper)
                }
                .padding(.horizontal)

                regionalShelves

                Text("Your pours").font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text).padding(.horizontal).padding(.top, 4)
                VStack(spacing: 10) {
                    ForEach(checkins) { row($0) }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func stat(_ n: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(n).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
            Text(label).font(.caption).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.22), lineWidth: 1))
        .contentTransition(.numericText())
    }

    private var regionalShelves: some View {
        let visited = guides.filter { guide in
            guide.scope == "country" && checkins.contains { $0.country == guide.name }
        }
        let suggestions = guides.filter { $0.scope == "country" && !visited.contains($0) }.prefix(4)
        let shelves = visited + Array(suggestions)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Regional shelves")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shelves.prefix(8)) { guide in
                        let unlocked = visited.contains(guide)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(flag(guide.flag)).font(.title2)
                                Spacer()
                                Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                                    .foregroundStyle(unlocked ? Brand.hop : Brand.muted)
                            }
                            Text(guide.name)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(unlocked ? guide.passportPhrase : guide.cellarPrompt)
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                                .lineLimit(3)
                            Spacer(minLength: 0)
                            Text(guide.heroStyle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Brand.malt)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background((unlocked ? Brand.gold : Brand.haze).opacity(unlocked ? 1 : 0.65), in: Capsule())
                        }
                        .padding(14)
                        .frame(width: 184, height: 178, alignment: .leading)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke((unlocked ? Brand.gold : Brand.malt).opacity(0.18)))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func row(_ c: MyCheckin) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mug.fill").foregroundStyle(Brand.malt)
                .frame(width: 40, height: 40).background(Brand.gold, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.beerName).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text("\(c.breweryName)  \(c.style ?? "")").font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer()
            if let r = c.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(Brand.gold)
                    Text(String(format: "%.0f", r)).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                }
            }
        }
        .padding(12).background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var nextMilestone: String {
        if checkins.count < 5 { return "\(5 - checkins.count) pours to first flight" }
        if styleCount < 5 { return "\(5 - styleCount) styles to style badge" }
        if countryCount < 3 { return "\(3 - countryCount) countries to explorer badge" }
        return "Passport is warming up"
    }

    private func load() async {
        guard let uid = session.user?.id else { return }
        checkins = (try? await CheckinService.mine(userId: uid)) ?? []
        guides = (try? await WorldBeerService.regionGuides()) ?? []
    }

    private func flag(_ code: String?) -> String {
        switch code {
        case "BE": return "🇧🇪"
        case "CZ": return "🇨🇿"
        case "DE": return "🇩🇪"
        case "IE": return "🇮🇪"
        case "JP": return "🇯🇵"
        case "MX": return "🇲🇽"
        case "PL": return "🇵🇱"
        case "GB": return "🇬🇧"
        case "US": return "🇺🇸"
        default: return "🍺"
        }
    }
}
