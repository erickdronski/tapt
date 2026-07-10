import SwiftUI

/// Darts, GamePigeon style: drag back to aim, flick to throw. The dart flies
/// with a depth animation into the board; flick harder and your grouping
/// scatters. Pass-and-play, 2 players, 3 darts x 3 rounds each.
struct DartsGame: View {
    @State private var players = ["Player 1", "Player 2"]
    @State private var scores = [0, 0]
    @State private var turn = 0
    @State private var dartsThrown = 0          // total darts (18 = game over)
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var dartFlying = false
    @State private var dartLanding: CGPoint? = nil
    @State private var lastHit: (label: String, points: Int)? = nil
    @State private var landed: [(point: CGPoint, player: Int)] = []
    @State private var gameOver = false

    private let boardSize: CGFloat = 300

    var body: some View {
        VStack(spacing: 14) {
            scoreboard

            ZStack {
                board
                ForEach(Array(landed.enumerated()), id: \.offset) { _, hit in
                    dartMarker(color: hit.player == 0 ? Brand.copper : Brand.hop)
                        .position(hit.point)
                }
                if let landing = dartLanding {
                    dartMarker(color: turn == 0 ? Brand.copper : Brand.hop)
                        .scaleEffect(dartFlying ? 1 : 2.6)
                        .opacity(dartFlying ? 1 : 0)
                        .position(landing)
                }
                if let hit = lastHit {
                    Text(hit.points > 0 ? "\(hit.label) +\(hit.points)" : hit.label)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(hit.points >= 25 ? Brand.gold : Brand.foam)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Brand.malt.opacity(0.82), in: Capsule())
                        .position(x: boardSize / 2, y: 30)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: boardSize, height: boardSize)

            if gameOver { resultPanel } else { throwZone }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Darts")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Board

    private var board: some View {
        ZStack {
            ForEach(rings, id: \.radius) { ring in
                Circle()
                    .fill(ring.color)
                    .frame(width: ring.radius * 2, height: ring.radius * 2)
                    .overlay(Circle().stroke(Brand.malt.opacity(0.5), lineWidth: 1.5))
            }
            Circle().fill(Brand.gold)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Brand.malt, lineWidth: 2))
                .shadow(color: Brand.gold.opacity(0.6), radius: 8)
        }
        .shadow(color: Brand.malt.opacity(0.3), radius: 18, y: 10)
    }

    private var rings: [(radius: CGFloat, color: Color)] {
        [
            (150, Brand.malt),
            (118, Color(hex: 0x2E5E43)),
            (86, Color(hex: 0x8D4C32)),
            (54, Color(hex: 0x2E5E43)),
            (26, Color(hex: 0xB4531F)),
        ]
    }

    private func dartMarker(color: Color) -> some View {
        ZStack {
            Circle().fill(color).frame(width: 13, height: 13)
            Circle().stroke(Brand.foam, lineWidth: 2).frame(width: 13, height: 13)
        }
        .shadow(color: Brand.malt.opacity(0.5), radius: 2, y: 1)
    }

    // MARK: - Throwing

    private var throwZone: some View {
        VStack(spacing: 8) {
            Text(dragging ? "Release to throw!" : "\(players[turn]): drag down, flick up")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(dragging ? Brand.copper : Brand.muted)

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Brand.gold.opacity(0.25)))
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(turn == 0 ? Brand.copper : Brand.hop)
                    .rotationEffect(.degrees(-45))
                    .offset(drag)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            }
            .frame(height: 130)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !dartFlying else { return }
                        dragging = true
                        drag = CGSize(width: value.translation.width * 0.5,
                                      height: min(max(value.translation.height, -10), 90) * 0.6)
                    }
                    .onEnded { value in
                        dragging = false
                        guard !dartFlying else { drag = .zero; return }
                        throwDart(velocity: value.predictedEndTranslation)
                        drag = .zero
                    }
            )

            Text("Dart \(dartsThrown % 3 + 1) of 3 · Round \(min(dartsThrown / 6 + 1, 3)) of 3")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
    }

    private func throwDart(velocity: CGSize) {
        let power = max(-velocity.height, 40)                 // upward flick
        guard power > 40 else { return }                      // needs a real flick
        dartFlying = true
        Haptic.firm()

        // Aim: horizontal drift from the flick angle; accuracy decays when the
        // flick is wild (too hard or too sideways).
        let center = boardSize / 2
        let aimX = center + velocity.width * 0.35
        let overpower = max(0, power - 420) * 0.25
        let scatter = 12 + overpower + abs(velocity.width) * 0.18
        let seed1 = CGFloat((dartsThrown * 733 + Int(power)) % 200) / 100 - 1   // -1...1
        let seed2 = CGFloat((dartsThrown * 397 + Int(abs(velocity.width))) % 200) / 100 - 1
        let landing = CGPoint(
            x: min(max(aimX + seed1 * scatter, 8), boardSize - 8),
            y: min(max(center - (power - 260) * 0.28 + seed2 * scatter, 8), boardSize - 8)
        )

        dartLanding = landing
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            dartFlying = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let hit = score(at: landing)
            lastHit = hit
            scores[turn] += hit.points
            landed.append((landing, turn))
            Haptic.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {}

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation { lastHit = nil }
                dartLanding = nil
                dartFlying = false
                dartsThrown += 1
                if dartsThrown >= 18 {
                    gameOver = true
                    Haptic.celebrate()
                } else if dartsThrown % 3 == 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { turn = 1 - turn }
                }
            }
        }
    }

    private func score(at point: CGPoint) -> (String, Int) {
        let center = CGPoint(x: boardSize / 2, y: boardSize / 2)
        let distance = hypot(point.x - center.x, point.y - center.y)
        switch distance {
        case ..<13: return ("BULLSEYE!", 50)
        case ..<26: return ("Bull ring", 25)
        case ..<54: return ("Inner", 20)
        case ..<86: return ("Middle", 15)
        case ..<118: return ("Outer", 10)
        case ..<150: return ("Edge", 5)
        default: return ("Miss", 0)
        }
    }

    // MARK: - Score UI

    private var scoreboard: some View {
        HStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(players[i])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(turn == i && !gameOver ? Brand.malt : Brand.muted)
                    Text("\(scores[i])")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(turn == i && !gameOver ? Brand.malt : Brand.text)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    turn == i && !gameOver ? (i == 0 ? Brand.copper : Brand.hop) : Brand.surface,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
    }

    private var resultPanel: some View {
        VStack(spacing: 10) {
            Text(scores[0] == scores[1] ? "Dead heat! 🤝"
                 : "🏆 \(players[scores[0] > scores[1] ? 0 : 1]) wins!")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
            Button("Rematch") {
                scores = [0, 0]; turn = 0; dartsThrown = 0
                landed = []; gameOver = false
            }
            .font(.system(.headline, design: .rounded))
            .padding(.horizontal, 26).padding(.vertical, 12)
            .background(Brand.gold, in: Capsule())
            .foregroundStyle(Brand.malt)
            .buttonStyle(.taptPress)
        }
        .padding(.vertical, 16)
    }
}
