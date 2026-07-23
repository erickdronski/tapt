import SwiftUI

/// A local Cup Flip match for one to four players. The flick still drives the
/// cup's spin and landing, while match state stays separate and testable.
struct FlipCupGame: View {
    private enum Phase {
        case setup
        case playing
    }

    @AppStorage("flipCupBestStreak") private var bestStreak = 0
    @State private var phase: Phase = .setup
    @State private var playerCount = 2
    @State private var playerNames = ["Player 1", "Player 2", "Player 3", "Player 4"]
    @State private var target = 5
    @State private var match: FlipCupMatch?

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var airborne = false
    @State private var cupSpin: Double = 0
    @State private var cupLift: CGFloat = 0
    @State private var result: Bool?
    @State private var resultPlayerIndex: Int?
    @State private var message = "Flick up to flip the cup."
    @State private var resolutionTask: Task<Void, Never>?

    private let stageHeight: CGFloat = 300
    private let playerTints = [
        Brand.copper,
        Brand.hop,
        Brand.gold,
        Color(hex: 0x3E6DB5),
    ]

    var body: some View {
        Group {
            switch phase {
            case .setup: setup
            case .playing: game
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Cup Flip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if phase == .playing {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rematch", systemImage: "arrow.clockwise", action: rematch)
                        Button("Change players", systemImage: "person.2.fill", action: changePlayers)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Cup Flip options")
                }
            }
        }
        .onDisappear { resolutionTask?.cancel() }
    }

    // MARK: - Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Set the table")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                    Text(
                        playerCount == 1
                            ? "Land the target in as few attempts as you can."
                            : "First to land the target wins."
                    )
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                    if bestStreak > 0 {
                        Label("Best run \(bestStreak)", systemImage: "flag.checkered")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Brand.copper)
                    }
                }

                setupSection("Players") {
                    Picker("Players", selection: $playerCount) {
                        ForEach(1...4, id: \.self) { count in
                            Text("\(count)P").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 10) {
                        ForEach(0..<playerCount, id: \.self) { index in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(playerTints[index])
                                    .frame(width: 10, height: 10)
                                TextField("Player \(index + 1)", text: $playerNames[index])
                                    .textInputAutocapitalization(.words)
                                    .submitLabel(index + 1 == playerCount ? .done : .next)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Brand.text)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Brand.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(playerTints[index].opacity(0.35))
                            )
                        }
                    }
                }

                setupSection("Race to") {
                    Picker("Target", selection: $target) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("7").tag(7)
                    }
                    .pickerStyle(.segmented)
                }

                Button(action: startMatch) {
                    Label("Start match", systemImage: "play.fill")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Brand.gold, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.taptPress)

                Label(GameGuidesData.safetyLine, systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
    }

    private func setupSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.muted)
            content()
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Match

    private var game: some View {
        VStack(spacing: 14) {
            scoreboard

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(activeTint.opacity(0.32)))
                Rectangle()
                    .fill(Brand.malt.opacity(0.14))
                    .frame(height: 10)
                    .padding(.bottom, 30)

                cup
                    .frame(width: 78, height: 96)
                    .rotationEffect(.degrees(cupSpin))
                    .offset(y: -30 - cupLift)
                    .shadow(color: Brand.malt.opacity(0.28), radius: 8, y: 6)

                if let result, let playerIndex = resultPlayerIndex, let match {
                    Text(result ? successMessage(for: playerIndex, match: match) : "Tipped over")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(result ? Brand.hop : Brand.copper)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Brand.malt.opacity(0.86), in: Capsule())
                        .offset(y: -stageHeight * 0.6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: stageHeight)
            .contentShape(Rectangle())
            .gesture(flickGesture)

            if let winner = match?.winnerIndex, let match, !airborne {
                winnerPanel(winner, match: match)
            } else {
                VStack(spacing: 5) {
                    Text(dragging ? "Release!" : currentTurnLabel)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(dragging ? Brand.copper : activeTint)
                    Text(dragging ? "" : message)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .frame(minHeight: 16)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }

    private var flickGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !airborne, match?.winnerIndex == nil else { return }
                dragging = true
                drag = CGSize(
                    width: value.translation.width * 0.2,
                    height: min(max(value.translation.height, -8), 40)
                )
            }
            .onEnded { value in
                dragging = false
                guard !airborne, match?.winnerIndex == nil else {
                    drag = .zero
                    return
                }
                flip(velocity: value.predictedEndTranslation)
                drag = .zero
            }
    }

    private var cup: some View {
        ZStack {
            CupShape()
                .fill(
                    LinearGradient(
                        colors: [activeTint, activeTint.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(CupShape().stroke(Brand.malt.opacity(0.5), lineWidth: 1.5))
            VStack {
                Capsule()
                    .fill(Brand.foam)
                    .frame(height: 12)
                    .padding(.horizontal, 6)
                Spacer()
            }
            .padding(.top, 4)
        }
        .offset(dragging ? drag : .zero)
        .scaleEffect(dragging ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
        .accessibilityHidden(true)
    }

    private var scoreboard: some View {
        HStack(spacing: 8) {
            if let match {
                ForEach(match.playerNames.indices, id: \.self) { index in
                    let active = match.currentPlayerIndex == index && match.winnerIndex == nil
                    VStack(spacing: 3) {
                        Text(match.playerNames[index])
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(active ? Brand.malt : Brand.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text("\(match.scores[index])")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(active ? Brand.malt : Brand.text)
                            .contentTransition(.numericText())
                        Text("of \(match.target)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(active ? Brand.malt.opacity(0.7) : Brand.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        active ? playerTints[index] : Brand.surface,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(playerTints[index].opacity(active ? 0 : 0.28))
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(match.playerNames[index]), \(match.scores[index]) of \(match.target)"
                    )
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .animation(.snappy, value: match)
    }

    private func winnerPanel(_ winner: Int, match: FlipCupMatch) -> some View {
        VStack(spacing: 10) {
            Image(systemName: match.playerNames.count == 1 ? "flag.checkered" : "trophy.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Brand.gold)
                .symbolEffect(.bounce, value: winner)
            Text(match.playerNames.count == 1 ? "Run complete" : "\(match.playerNames[winner]) wins")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            Text("\(match.scores[winner]) landed in \(match.attempts[winner]) attempts")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            HStack(spacing: 10) {
                Button(action: rematch) {
                    Label("Rematch", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.gold)

                Button(action: changePlayers) {
                    Image(systemName: "person.2.fill")
                        .frame(width: 38)
                }
                .buttonStyle(.bordered)
                .tint(Brand.text)
                .accessibilityLabel("Change players")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.gold.opacity(0.35)))
    }

    // MARK: - Match actions

    private func startMatch() {
        let names = Array(playerNames.prefix(playerCount))
        match = FlipCupMatch(playerNames: names, target: target)
        resetCup()
        phase = .playing
        Haptic.firm()
    }

    private func rematch() {
        guard let match else { return }
        resolutionTask?.cancel()
        self.match = FlipCupMatch(playerNames: match.playerNames, target: match.target)
        resetCup()
        Haptic.tap()
    }

    private func changePlayers() {
        resolutionTask?.cancel()
        resetCup()
        phase = .setup
        match = nil
        Haptic.tap()
    }

    private func resetCup() {
        airborne = false
        dragging = false
        drag = .zero
        cupSpin = 0
        cupLift = 0
        result = nil
        resultPlayerIndex = nil
        message = "Flick up to flip the cup."
    }

    private func flip(velocity: CGSize) {
        guard let activeMatch = match else { return }
        let trajectory = FlipCupPhysics.trajectory(for: velocity)
        guard trajectory.launched else {
            message = "Not enough on it. Flick harder."
            Haptic.tap()
            return
        }

        let playerIndex = activeMatch.currentPlayerIndex
        airborne = true
        result = nil
        resultPlayerIndex = playerIndex
        Haptic.firm()

        withAnimation(.easeOut(duration: 0.4)) {
            cupSpin = trajectory.spin
            cupLift = trajectory.lift
        }

        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }

            let base = (trajectory.spin / 360).rounded() * 360
            withAnimation(.spring(response: 0.5, dampingFraction: trajectory.landed ? 0.72 : 0.5)) {
                cupLift = 0
                cupSpin = trajectory.landed
                    ? base
                    : base + (trajectory.remainder < 180 ? 118 : -118)
            }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard var resolvedMatch = match,
                  resolvedMatch.currentPlayerIndex == playerIndex,
                  resolvedMatch.winnerIndex == nil
            else { return }
            let outcome = resolvedMatch.record(success: trajectory.landed)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                match = resolvedMatch
                result = trajectory.landed
            }
            if trajectory.landed {
                bestStreak = max(bestStreak, resolvedMatch.bestStreaks[playerIndex])
                Haptic.success()
                message = landingMessage(alignmentError: trajectory.alignmentError)
            } else {
                Haptic.tap()
                message = "Next player up."
            }

            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                cupSpin = 0
                result = nil
            }
            resultPlayerIndex = nil
            airborne = false

            if outcome.winnerIndex != nil {
                Haptic.celebrate()
                message = "Match complete."
            } else {
                message = "Flick up to flip the cup."
            }
        }
    }

    private var activeTint: Color {
        guard let index = resultPlayerIndex ?? match?.currentPlayerIndex,
              playerTints.indices.contains(index)
        else { return Brand.copper }
        return playerTints[index]
    }

    private var currentTurnLabel: String {
        guard let match else { return "Flick up" }
        return "\(match.playerNames[match.currentPlayerIndex])'s flip"
    }

    private func successMessage(for playerIndex: Int, match: FlipCupMatch) -> String {
        "\(match.playerNames[playerIndex]) landed it"
    }

    private func landingMessage(alignmentError: Double) -> String {
        alignmentError < 10 ? "Perfect flip." : "Clean landing."
    }
}

// MARK: - Testable game rules

struct FlipCupTrajectory: Equatable {
    let launched: Bool
    let spin: Double
    let lift: CGFloat
    let remainder: Double
    let alignmentError: Double
    let landed: Bool
}

enum FlipCupPhysics {
    static func trajectory(for predictedEndTranslation: CGSize) -> FlipCupTrajectory {
        let power = -predictedEndTranslation.height
        guard power > 70 else {
            return FlipCupTrajectory(
                launched: false,
                spin: 0,
                lift: 0,
                remainder: 0,
                alignmentError: 360,
                landed: false
            )
        }

        let spin = min(Double(power) * 0.82, 620)
        let lift = min(power * 0.55, 230)
        let remainder = spin.truncatingRemainder(dividingBy: 360)
        let alignmentError = min(remainder, 360 - remainder)
        return FlipCupTrajectory(
            launched: true,
            spin: spin,
            lift: lift,
            remainder: remainder,
            alignmentError: alignmentError,
            landed: spin > 300 && alignmentError < 34
        )
    }
}

struct FlipCupTurnOutcome: Equatable {
    let playerIndex: Int
    let success: Bool
    let nextPlayerIndex: Int
    let winnerIndex: Int?
}

struct FlipCupMatch: Equatable {
    let playerNames: [String]
    let target: Int
    private(set) var scores: [Int]
    private(set) var attempts: [Int]
    private(set) var streaks: [Int]
    private(set) var bestStreaks: [Int]
    private(set) var currentPlayerIndex = 0
    private(set) var winnerIndex: Int?

    init(playerNames: [String], target: Int) {
        let names = Array(playerNames.prefix(4)).enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
        self.playerNames = names.isEmpty ? ["Player 1"] : names
        self.target = min(max(target, 1), 20)
        scores = Array(repeating: 0, count: self.playerNames.count)
        attempts = Array(repeating: 0, count: self.playerNames.count)
        streaks = Array(repeating: 0, count: self.playerNames.count)
        bestStreaks = Array(repeating: 0, count: self.playerNames.count)
    }

    @discardableResult
    mutating func record(success: Bool) -> FlipCupTurnOutcome {
        let playerIndex = currentPlayerIndex
        guard winnerIndex == nil else {
            return FlipCupTurnOutcome(
                playerIndex: playerIndex,
                success: false,
                nextPlayerIndex: playerIndex,
                winnerIndex: winnerIndex
            )
        }

        attempts[playerIndex] += 1
        if success {
            scores[playerIndex] += 1
            streaks[playerIndex] += 1
            bestStreaks[playerIndex] = max(bestStreaks[playerIndex], streaks[playerIndex])
            if scores[playerIndex] >= target {
                winnerIndex = playerIndex
            }
        } else {
            streaks[playerIndex] = 0
        }

        if winnerIndex == nil {
            currentPlayerIndex = (playerIndex + 1) % playerNames.count
        }

        return FlipCupTurnOutcome(
            playerIndex: playerIndex,
            success: success,
            nextPlayerIndex: currentPlayerIndex,
            winnerIndex: winnerIndex
        )
    }
}

/// A solo-cup silhouette: wide rim, tapered base.
struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let topInset = rect.width * 0.03
        let bottomInset = rect.width * 0.19
        path.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    NavigationStack { FlipCupGame() }
}
