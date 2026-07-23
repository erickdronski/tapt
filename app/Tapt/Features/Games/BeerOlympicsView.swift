import SwiftUI

/// Table Olympics, team scoreboard for a multi-event game night. Pure
/// organizing/scorekeeping (medals, points, champion); drinking is never part
/// of the mechanics. State persists across app launches for multi-hour nights.
struct BeerOlympicsView: View {
    @AppStorage("beerOlympicsState") private var savedState = ""
    @State private var teams: [OlympicTeam] = []
    @State private var events: [OlympicEvent] = []
    @State private var newTeamName = ""
    @State private var showReset = false

    private let eventIdeas = [
        "Tapt Trivia", "Cup Pong", "Cup Flip", "Quarters",
        "Cornhole", "Cup Stack Relay", "Categories", "Horse Race",
    ]

    private var standings: [(team: OlympicTeam, points: Int, golds: Int)] {
        teams.map { team in
            let golds = events.filter { $0.gold == team.id }.count
            let silvers = events.filter { $0.silver == team.id }.count
            let bronzes = events.filter { $0.bronze == team.id }.count
            return (team, golds * 3 + silvers * 2 + bronzes, golds)
        }
        .sorted { ($0.points, $0.golds) > ($1.points, $1.golds) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaptHeroPanel(
                    title: "Table Olympics",
                    subtitle: "Draft teams, run skill events, crown a champion. Gold 3 · Silver 2 · Bronze 1.",
                    metric: "PLAY",
                    caption: "Zero-proof teams medal the same",
                    icon: "trophy.fill",
                    tint: Brand.gold
                )

                teamsSection
                if teams.count >= 2 {
                    eventsSection
                    if events.contains(where: { $0.gold != nil }) {
                        medalTable
                    }
                }
                safety
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Table Olympics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !teams.isEmpty || !events.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { showReset = true }.foregroundStyle(Brand.copper)
                }
            }
        }
        .confirmationDialog("Start a fresh Olympics?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) {
                teams = []; events = []; persist()
            }
        }
        .onAppear(perform: restore)
    }

    // MARK: - Teams

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Teams", teams.count < 2 ? "Add at least two" : "\(teams.count) competing")
            ForEach(teams) { team in
                HStack {
                    Text(team.flagEmoji).font(.title3)
                    Text(team.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Spacer()
                    Button {
                        teams.removeAll { $0.id == team.id }
                        events = events.map { $0.clearing(team.id) }
                        persist()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
            }
            if teams.count < 6 {
                HStack(spacing: 8) {
                    TextField("Team name (country optional)", text: $newTeamName)
                        .textInputAutocapitalization(.words)
                        .padding(11)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                    Button {
                        let name = newTeamName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        teams.append(OlympicTeam(name: name))
                        newTeamName = ""
                        persist()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundStyle(Brand.gold)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Events", "Tap a medal to award it")
            ForEach($events) { $event in
                eventCard($event)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(eventIdeas.filter { idea in !events.contains { $0.name == idea } }, id: \.self) { idea in
                        Button {
                            events.append(OlympicEvent(name: idea))
                            persist()
                        } label: {
                            Label(idea, systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Brand.surface, in: Capsule())
                                .foregroundStyle(Brand.text)
                                .overlay(Capsule().stroke(Brand.gold.opacity(0.3)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func eventCard(_ event: Binding<OlympicEvent>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.wrappedValue.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Spacer()
                Button {
                    events.removeAll { $0.id == event.wrappedValue.id }
                    persist()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(Brand.muted)
                }
                .buttonStyle(.plain)
            }
            medalPicker("🥇", selection: event.gold)
            medalPicker("🥈", selection: event.silver)
            if teams.count >= 3 {
                medalPicker("🥉", selection: event.bronze)
            }
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            event.wrappedValue.gold != nil ? Brand.gold.opacity(0.45) : Brand.malt.opacity(0.08)))
    }

    private func medalPicker(_ medal: String, selection: Binding<UUID?>) -> some View {
        HStack(spacing: 8) {
            Text(medal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(teams) { team in
                        let on = selection.wrappedValue == team.id
                        Button {
                            Haptic.firm()
                            selection.wrappedValue = on ? nil : team.id
                            persist()
                        } label: {
                            Text(team.name)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(on ? Brand.gold : Brand.background, in: Capsule())
                                .foregroundStyle(on ? Brand.malt : Brand.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Medal table

    private var medalTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Medal table", "Gold 3 · Silver 2 · Bronze 1")
            ForEach(Array(standings.enumerated()), id: \.element.team.id) { index, row in
                HStack(spacing: 12) {
                    Text(index == 0 ? "👑" : "\(index + 1)")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .frame(width: 30)
                    Text(row.team.flagEmoji)
                    Text(row.team.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    Spacer()
                    Text("\(row.golds) 🥇")
                        .font(.caption.weight(.bold)).foregroundStyle(Brand.muted)
                    Text("\(row.points) pts")
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(index == 0 ? Brand.gold : Brand.text)
                }
                .padding(12)
                .background(
                    index == 0 ? Brand.gold.opacity(0.14) : Brand.surface,
                    in: RoundedRectangle(cornerRadius: 13)
                )
            }
        }
    }

    private var safety: some View {
        Label(GameGuidesData.safetyLine, systemImage: "hand.raised.fill")
            .font(.caption)
            .foregroundStyle(Brand.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
            Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
        }
    }

    // MARK: - Persistence (device-local)

    private func persist() {
        let state = OlympicsState(teams: teams, events: events)
        if let data = try? JSONEncoder().encode(state) {
            savedState = String(data: data, encoding: .utf8) ?? ""
        }
    }

    private func restore() {
        guard teams.isEmpty, events.isEmpty,
              let data = savedState.data(using: .utf8),
              let state = try? JSONDecoder().decode(OlympicsState.self, from: data)
        else { return }
        teams = state.teams
        events = state.events
    }
}

private struct OlympicsState: Codable {
    let teams: [OlympicTeam]
    let events: [OlympicEvent]
}

struct OlympicTeam: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String

    /// A stable, name-derived flag from the Passport country set, cosmetic only.
    var flagEmoji: String {
        let flags = PassportData.countries.map(\.flag)
        var hash = 0
        for scalar in name.unicodeScalars { hash = (hash &* 31 &+ Int(scalar.value)) }
        return flags[abs(hash) % flags.count]
    }
}

struct OlympicEvent: Identifiable, Codable {
    var id = UUID()
    var name: String
    var gold: UUID?
    var silver: UUID?
    var bronze: UUID?

    func clearing(_ teamId: UUID) -> OlympicEvent {
        var copy = self
        if copy.gold == teamId { copy.gold = nil }
        if copy.silver == teamId { copy.silver = nil }
        if copy.bronze == teamId { copy.bronze = nil }
        return copy
    }
}
