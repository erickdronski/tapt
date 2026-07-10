import SwiftUI

/// Quarters, GamePigeon style: flick the coin so it bounces off the table and
/// drops into the cup. Aim is the flick direction, power is the flick strength,
/// and the cup moves every round, so you actually have to read the table.
struct QuartersGame: View {
    @State private var score = 0
    @State private var streak = 0
    @State private var best = 0
    @State private var round = 1

    @State private var coin = CGPoint(x: 150, y: 280)
    @State private var coinScale: CGFloat = 1
    @State private var flying = false
    @State private var cupX: CGFloat = 150
    @State private var madeIt: Bool? = nil
    @State private var message = "Flick the coin into the cup."

    @State private var drag: CGSize = .zero
    @State private var dragging = false

    private let stageW: CGFloat = 300
    private let stageH: CGFloat = 320
    private let cupY: CGFloat = 66
    private let startPoint = CGPoint(x: 150, y: 280)

    var body: some View {
        VStack(spacing: 14) {
            scoreboard

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.copper.opacity(0.25)))

                // Table line (the bounce plane)
                Rectangle()
                    .fill(Brand.malt.opacity(0.12))
                    .frame(height: 8)
                    .position(x: stageW / 2, y: 214)

                // Cup target
                cupView
                    .position(x: cupX, y: cupY)

                // Coin
                coinView
                    .scaleEffect(coinScale)
                    .position(coin)
                    .shadow(color: Brand.malt.opacity(0.25), radius: 4, y: 3)

                if let madeIt {
                    Text(madeIt ? "In the cup!" : "Off the rim")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(madeIt ? Brand.hop : Brand.copper)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Brand.malt.opacity(0.82), in: Capsule())
                        .position(x: stageW / 2, y: 30)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: stageW, height: stageH)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        guard !flying else { return }
                        dragging = true
                        drag = CGSize(width: v.translation.width * 0.3,
                                      height: min(max(v.translation.height, -40), 20) * 0.4)
                    }
                    .onEnded { v in
                        dragging = false
                        guard !flying else { drag = .zero; return }
                        shoot(velocity: v.predictedEndTranslation)
                        drag = .zero
                    }
            )

            Text(dragging ? "Release!" : message)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(dragging ? Brand.copper : Brand.muted)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Quarters")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if round == 1 { cupX = CGFloat.random(in: 70...230) } }
    }

    // MARK: - Pieces

    private var cupView: some View {
        ZStack {
            CupShape()
                .fill(LinearGradient(colors: [Brand.gold, Color(hex: 0xC56B10)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 56, height: 62)
                .overlay(CupShape().stroke(Brand.malt.opacity(0.45), lineWidth: 1.5).frame(width: 56, height: 62))
            // mouth
            Ellipse()
                .fill(Brand.malt.opacity(0.55))
                .frame(width: 50, height: 15)
                .offset(y: -30)
            Ellipse()
                .stroke(Brand.foam.opacity(0.7), lineWidth: 2)
                .frame(width: 50, height: 15)
                .offset(y: -30)
        }
        .shadow(color: Brand.malt.opacity(0.25), radius: 6, y: 4)
    }

    private var coinView: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(hex: 0xE9E4D6), Color(hex: 0xB9B09A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Circle().stroke(Brand.malt.opacity(0.4), lineWidth: 1.5)
            Text("25").font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Brand.malt.opacity(0.55))
        }
        .frame(width: 26, height: 26)
        .offset(dragging ? drag : .zero)
    }

    // MARK: - Physics

    private func shoot(velocity: CGSize) {
        let power = -velocity.height
        guard power > 60 else {
            message = "Give it a real flick."
            return
        }
        flying = true
        Haptic.firm()

        // Direction from the horizontal flick, distance from the power.
        let landingX = min(max(startPoint.x + velocity.width * 0.5, 24), stageW - 24)
        let reachY = min(max(startPoint.y - CGFloat(power) * 0.55, 30), startPoint.y - 40)

        let made = abs(landingX - cupX) < 24 && abs(reachY - cupY) < 42

        // Bounce point: partway to the landing, at the table plane.
        let bounce = CGPoint(x: (startPoint.x + landingX) / 2, y: 210)

        // Phase 1: rise off the table to the bounce point, growing (toward viewer).
        withAnimation(.easeOut(duration: 0.3)) {
            coin = bounce
            coinScale = 1.3
        }

        // Phase 2: arc down toward the cup / landing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let land = made ? CGPoint(x: cupX, y: cupY) : CGPoint(x: landingX, y: reachY)
            withAnimation(.spring(response: 0.42, dampingFraction: made ? 0.75 : 0.55)) {
                coin = land
                coinScale = made ? 0.55 : 0.9
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { madeIt = made }
                if made {
                    score += 1
                    streak += 1
                    best = max(best, streak)
                    Haptic.success()
                    message = streak > 1 ? "🔥 \(streak) in a row!" : "Nothing but cup."
                } else {
                    streak = 0
                    Haptic.tap()
                    message = landingX < cupX ? "Pulled it left." : (landingX > cupX ? "Pushed it right." : "Short hop.")
                }

                // Next round: reset coin, move the cup.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        madeIt = nil
                        coin = startPoint
                        coinScale = 1
                        cupX = CGFloat.random(in: 60...240)
                    }
                    round += 1
                    flying = false
                }
            }
        }
    }

    // MARK: - Scoreboard

    private var scoreboard: some View {
        HStack(spacing: 12) {
            stat("Made", "\(score)", Brand.hop)
            stat("Streak", "\(streak)", Brand.copper)
            stat("Best", "\(best)", Brand.gold)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(Brand.muted)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.3)))
    }
}

#Preview {
    NavigationStack { QuartersGame() }
}
