import SwiftUI

struct FlightsView: View {
    @Environment(Session.self) private var session
    @State private var checkins: [MyCheckin] = []
    @State private var selectedQuest = FlightsData.quests.first?.id
    @State private var shimmer = false
    @State private var celebration: TaptCelebration?
    @State private var pendingCompletedFlight: String?
    @AppStorage("flights.seenCompleted") private var seenCompletedRaw = ""

    private var selected: FlightQuest {
        FlightsData.quests.first { $0.id == selectedQuest } ?? FlightsData.quests[0]
    }

    private var stylesLogged: Set<String> {
        FlightProgress.normalizedStyles(checkins.compactMap { $0.displayStyle ?? $0.style })
    }

    private var completedStops: Int {
        FlightProgress.completedStops(in: selected, styles: stylesLogged)
    }

    private var completedStopIDs: Set<UUID> {
        FlightProgress.completedStopIDs(in: selected, styles: stylesLogged)
    }

    private var progress: Double {
        guard !selected.stops.isEmpty else { return 0 }
        return Double(completedStops) / Double(selected.stops.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                questRail
                progressPanel
                stopList
                nextPourPanel
            }
            .padding(.vertical)
        }
        .background(Brand.background)
        .taptCelebration($celebration)
        .navigationTitle("Flights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onAppear {
            withAnimation(.linear(duration: 1.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
            if let pendingCompletedFlight {
                celebration = .flightCompleted(title: pendingCompletedFlight)
                self.pendingCompletedFlight = nil
            }
        }
    }

    private var header: some View {
        TaptHeroPanel(
            title: "Guided tasting quests",
            subtitle: "Pick a flight, log the styles, and build a Passport around curiosity instead of volume.",
            metric: "\(completedStops)/\(selected.stops.count)",
            caption: selected.title,
            icon: "map.fill",
            tint: selected.tint
        )
        .padding(.horizontal)
    }

    private var questRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FlightsData.quests) { quest in
                    let active = quest.id == selected.id
                    Button {
                        Haptic.tap()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.76)) {
                            selectedQuest = quest.id
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: quest.icon)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(active ? Brand.malt : quest.tint)
                                .frame(width: 44, height: 44)
                                .background(active ? quest.tint : Brand.surface, in: RoundedRectangle(cornerRadius: 12))
                            Text(quest.title)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(quest.subtitle)
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                                .lineLimit(2)
                        }
                        .frame(width: 190, alignment: .leading)
                        .padding(14)
                        .background(active ? quest.tint.opacity(0.18) : Brand.surface, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(active ? quest.tint : Brand.malt.opacity(0.09), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.title)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                    Text(selected.why)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text("\(Int(progress * 100))%")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(selected.tint)
                    .contentTransition(.numericText())
                if progress == 1 {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(selected.tint)
                        .symbolEffect(.bounce, value: selectedQuest)
                        .accessibilityLabel("Flight complete")
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.haze.opacity(0.8))
                    Capsule()
                        .fill(LinearGradient(colors: [selected.tint, Brand.gold], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, proxy.size.width * progress))
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(Brand.foam.opacity(shimmer ? 0.9 : 0.25))
                                .frame(width: 12, height: 12)
                                .offset(x: 4)
                        }
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected.tint.opacity(0.22), lineWidth: 1))
        .padding(.horizontal)
    }

    private var stopList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flight stops")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Brand.text)
                .padding(.horizontal)

            VStack(spacing: 10) {
                ForEach(Array(selected.stops.enumerated()), id: \.element.id) { index, stop in
                    stopRow(index: index + 1, stop: stop)
                }
            }
            .padding(.horizontal)
        }
    }

    private func stopRow(index: Int, stop: FlightStop) -> some View {
        let done = isDone(stop)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? selected.tint : Brand.haze)
                Image(systemName: done ? "checkmark" : "\(index).circle.fill")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(done ? Brand.malt : Brand.muted)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(stop.style)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                    if stop.noLowFriendly {
                        Text("No / Low friendly")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.malt)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Brand.hop.opacity(0.7), in: Capsule())
                    }
                }
                Text(stop.prompt)
                    .font(.subheadline)
                    .foregroundStyle(Brand.text)
                Text(stop.clue)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(done ? selected.tint.opacity(0.12) : Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(done ? selected.tint.opacity(0.4) : Brand.malt.opacity(0.08), lineWidth: 1))
    }

    private var nextPourPanel: some View {
        let next = selected.stops.first { !isDone($0) }
        return VStack(alignment: .leading, spacing: 10) {
            Label(next == nil ? "Flight complete" : "Next pour", systemImage: next == nil ? "seal.fill" : "arrow.up.forward.circle.fill")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(selected.tint)
            Text(next?.style ?? "You finished this route.")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            Text(next?.clue ?? "Start another flight or revisit your Passport to see what new territory opened up.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            if session.user == nil {
                Button {
                    session.endGuestSession()
                } label: {
                    Label("Sign in to log a pour", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(selected.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                NavigationLink {
                    LogPourView(onLogged: { Task { await load(detectNewCompletion: true) } })
                } label: {
                    Label("Log a pour", systemImage: "plus.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(selected.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected.tint.opacity(0.22), lineWidth: 1))
        .padding(.horizontal)
    }

    private func isDone(_ stop: FlightStop) -> Bool {
        completedStopIDs.contains(stop.id)
    }

    private func load(detectNewCompletion: Bool = false) async {
        guard let uid = session.user?.id else { return }
        let updated = (try? await CheckinService.mine(userId: uid)) ?? []
        let updatedStyles = FlightProgress.normalizedStyles(
            updated.compactMap { $0.displayStyle ?? $0.style }
        )
        let completed = FlightProgress.completedQuestIDs(styles: updatedStyles)
        let seen = Set(seenCompletedRaw.split(separator: ",").map(String.init))

        checkins = updated
        let newCompletions = completed.subtracting(seen)
        if detectNewCompletion,
           let completedID = FlightsData.quests.map(\.id).first(where: newCompletions.contains),
           let quest = FlightsData.quests.first(where: { $0.id == completedID }) {
            pendingCompletedFlight = quest.title
        }
        seenCompletedRaw = seen.union(completed).sorted().joined(separator: ",")
    }
}
