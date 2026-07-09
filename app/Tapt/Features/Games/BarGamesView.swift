import SwiftUI

enum BarGameKind: String, CaseIterable, Identifiable {
    case beerPong = "Beer Pong"
    case flipCup = "Flip Cup"
    case quarters = "Quarters"

    var id: String { rawValue }
}

/// Simple pass-the-phone bar games. Water, NA, and house rules all count.
struct BarGamesView: View {
    @State private var selected: BarGameKind

    init(starting: BarGameKind = .beerPong) {
        _selected = State(initialValue: starting)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Game", selection: $selected) {
                    ForEach(BarGameKind.allCases) { game in
                        Text(game.rawValue).tag(game)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch selected {
                    case .beerPong:
                        BeerPongMiniGame()
                    case .flipCup:
                        FlipCupMiniGame()
                    case .quarters:
                        QuartersMiniGame()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

                Text("Play with water, NA beer, or house rules. Curiosity over capacity.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Bar Games")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: selected)
    }
}

private struct BeerPongMiniGame: View {
    @State private var playerCups = 10
    @State private var tableCups = 10
    @State private var aim = 0.52
    @State private var round = 1
    @State private var lastHit = false
    @State private var message = "Line up a clean arc."

    private var finished: Bool { playerCups == 0 || tableCups == 0 }

    var body: some View {
        VStack(spacing: 16) {
            gameHeader("Beer Pong", "\(tableCups) - \(playerCups)", "circle.grid.cross.fill", Brand.gold)

            HStack(alignment: .center, spacing: 18) {
                cupRack(count: tableCups, tint: Brand.gold)
                VStack(spacing: 10) {
                    Text("R\(round)")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.text)
                    Image(systemName: lastHit ? "checkmark.circle.fill" : "circle.dotted")
                        .font(.title)
                        .foregroundStyle(lastHit ? Brand.hop : Brand.muted)
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .frame(width: 88)
                }
                cupRack(count: playerCups, tint: Brand.hop)
            }

            VStack(spacing: 8) {
                Slider(value: $aim, in: 0...1)
                    .tint(Brand.gold)
                HStack {
                    Text("soft")
                    Spacer()
                    Text("center")
                    Spacer()
                    Text("heater")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Brand.muted)
            }

            HStack(spacing: 10) {
                Button(finished ? "Play again" : "Throw") {
                    if finished {
                        reset()
                    } else {
                        throwBall()
                    }
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt)

                Button("Reset") { reset() }
                    .font(.system(.headline, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Brand.text)
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.gold.opacity(0.22)))
    }

    private func cupRack(count: Int, tint: Color) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0...(row), id: \.self) { col in
                        let index = row * (row + 1) / 2 + col
                        Circle()
                            .fill(index < count ? tint : Brand.haze.opacity(0.45))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Brand.malt.opacity(0.12), lineWidth: 1))
                    }
                }
            }
        }
        .frame(width: 92, height: 106)
    }

    private func throwBall() {
        guard !finished else { return }
        let accuracy = 1 - abs(aim - 0.5) * 1.6
        let chance = min(0.92, max(0.12, accuracy + Double.random(in: -0.22...0.12)))
        let hit = Double.random(in: 0...1) < chance
        lastHit = hit
        if hit {
            tableCups = max(0, tableCups - 1)
            message = ["Clean hit.", "Rim, drop.", "Cup down."].randomElement() ?? "Hit."
        } else {
            message = ["Rim out.", "Short hop.", "Table bounce."].randomElement() ?? "Miss."
        }

        if tableCups > 0 && Double.random(in: 0...1) < 0.38 {
            playerCups = max(0, playerCups - 1)
        }
        round += 1
        if tableCups == 0 { message = "You cleared the rack." }
        if playerCups == 0 { message = "Table wins this rack." }
    }

    private func reset() {
        playerCups = 10
        tableCups = 10
        aim = 0.52
        round = 1
        lastHit = false
        message = "Line up a clean arc."
    }
}

private struct FlipCupMiniGame: View {
    @State private var waiting = false
    @State private var ready = false
    @State private var flipped = false
    @State private var startTime: Date?
    @State private var lastTime: Double?
    @State private var bestTime: Double?
    @State private var streak = 0
    @State private var message = "Set the cup."

    var body: some View {
        VStack(spacing: 16) {
            gameHeader("Flip Cup", bestTime.map { String(format: "%.2fs", $0) } ?? "BEST", "cup.and.saucer.fill", Brand.hop)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.haze.opacity(0.8))
                    .frame(width: 138, height: 168)
                VStack(spacing: 0) {
                    Rectangle().fill(Brand.foam).frame(height: 18)
                    Rectangle().fill(ready ? Brand.hop : Brand.gold)
                }
                .frame(width: 104, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .rotationEffect(.degrees(flipped ? 180 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.62), value: flipped)
            }
            .frame(height: 178)

            VStack(spacing: 4) {
                Text(lastTime.map { String(format: "%.2fs", $0) } ?? "--")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.text)
                    .contentTransition(.numericText())
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }

            HStack(spacing: 10) {
                Button(waiting || ready ? "Flip" : "Start") {
                    waiting || ready ? flip() : startRound()
                }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(ready ? Brand.hop : Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt)

                Label("\(streak)", systemImage: "flame.fill")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.copper)
                    .frame(width: 72)
                    .padding(.vertical, 14)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.hop.opacity(0.22)))
    }

    private func startRound() {
        waiting = true
        ready = false
        flipped = false
        startTime = nil
        lastTime = nil
        message = "Wait for the green cup."
        Task { @MainActor in
            let delay = UInt64.random(in: 850_000_000...2_200_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard waiting else { return }
            ready = true
            startTime = Date()
            message = "Flip now."
        }
    }

    private func flip() {
        if !ready {
            waiting = false
            streak = 0
            message = "Early flip."
            return
        }
        waiting = false
        ready = false
        flipped = true
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        lastTime = elapsed
        if bestTime == nil || elapsed < (bestTime ?? elapsed) {
            bestTime = elapsed
            message = "New table best."
        } else {
            message = elapsed < 0.42 ? "Fast hands." : "Clean flip."
        }
        streak += 1
    }
}

private struct QuartersMiniGame: View {
    @State private var power = 0.48
    @State private var target = Double.random(in: 0.25...0.75)
    @State private var score = 0
    @State private var round = 1
    @State private var coinOffset: CGFloat = 0
    @State private var message = "Find the bounce."

    var body: some View {
        VStack(spacing: 16) {
            gameHeader("Quarters", "\(score)/\(round - 1)", "circle.hexagongrid.fill", Brand.copper)

            ZStack {
                Circle()
                    .stroke(Brand.haze, lineWidth: 18)
                    .frame(width: 176, height: 176)
                Circle()
                    .stroke(Brand.gold, lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(Brand.copper)
                    .frame(width: 34, height: 34)
                    .offset(x: coinOffset)
                    .shadow(color: Brand.malt.opacity(0.18), radius: 8, y: 4)
            }
            .frame(height: 190)

            VStack(spacing: 8) {
                Slider(value: $power, in: 0...1)
                    .tint(Brand.copper)
                HStack {
                    Text("low")
                    Spacer()
                    Text("target")
                    Spacer()
                    Text("high")
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Brand.muted)
            }

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.muted)

            Button("Bounce") { bounce() }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.copper, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.foam)
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Brand.copper.opacity(0.22)))
    }

    private func bounce() {
        let drift = CGFloat((power - target) * 180)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) {
            coinOffset = drift
        }
        let hit = abs(power - target) < 0.105
        if hit {
            score += 1
            message = "Centered."
        } else {
            message = power < target ? "Too soft." : "Too hot."
        }
        round += 1
        target = Double.random(in: 0.25...0.75)
    }
}

private func gameHeader(_ title: String, _ metric: String, _ icon: String, _ tint: Color) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.title2)
            .foregroundStyle(Brand.malt)
            .frame(width: 48, height: 48)
            .background(tint, in: RoundedRectangle(cornerRadius: 12))
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            Text("Table-ready mini game")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        Spacer()
        Text(metric)
            .font(.system(.headline, design: .rounded).weight(.heavy))
            .foregroundStyle(tint)
            .contentTransition(.numericText())
    }
}
