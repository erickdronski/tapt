import SwiftUI

/// Flip Cup, GamePigeon style: flick the cup off the table edge with the right
/// spin so it turns a full rotation and lands flat on its base. Too soft and it
/// flops short, too hard and it over-spins and tips. Chase your best streak.
struct FlipCupGame: View {
    @State private var streak = 0
    @AppStorage("flipCupBestStreak") private var best = 0
    @State private var flips = 0                 // total successful flips
    @State private var attempts = 0

    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var airborne = false
    @State private var cupSpin: Double = 0       // degrees, 0 = upright on base
    @State private var cupLift: CGFloat = 0       // how high off the table
    @State private var result: Bool? = nil        // nil = mid-flight
    @State private var message = "Flick up to flip the cup."

    private let stageHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 14) {
            scoreboard

            ZStack(alignment: .bottom) {
                // Table
                RoundedRectangle(cornerRadius: 22)
                    .fill(Brand.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.hop.opacity(0.25)))
                Rectangle()
                    .fill(Brand.malt.opacity(0.14))
                    .frame(height: 10)
                    .padding(.bottom, 30)

                // The cup
                cup
                    .frame(width: 78, height: 96)
                    .rotationEffect(.degrees(cupSpin))
                    .offset(y: -30 - cupLift)
                    .shadow(color: Brand.malt.opacity(0.28), radius: 8, y: 6)

                // Result flash
                if let result {
                    Text(result ? (message) : "Tipped over")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(result ? Brand.hop : Brand.copper)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Brand.malt.opacity(0.82), in: Capsule())
                        .offset(y: -stageHeight * 0.6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: stageHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        guard !airborne else { return }
                        dragging = true
                        // preview the wind-up: cup dips and cocks slightly
                        drag = CGSize(width: v.translation.width * 0.2,
                                      height: min(max(v.translation.height, -8), 40))
                    }
                    .onEnded { v in
                        dragging = false
                        guard !airborne else { drag = .zero; return }
                        flip(velocity: v.predictedEndTranslation)
                        drag = .zero
                    }
            )

            Text(dragging ? "Release!" : message)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(dragging ? Brand.copper : Brand.muted)
                .frame(maxWidth: .infinity)

            if attempts > 0 && !airborne {
                Button("Reset streak") { streak = 0; message = "Flick up to flip the cup." }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.background)
        .navigationTitle("Flip Cup")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cup

    private var cup: some View {
        ZStack {
            CupShape()
                .fill(
                    LinearGradient(colors: [Brand.copper, Color(hex: 0x8D3E17)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(CupShape().stroke(Brand.malt.opacity(0.5), lineWidth: 1.5))
            // foam / liquid line near the rim (top)
            VStack {
                Capsule().fill(Brand.foam).frame(height: 12).padding(.horizontal, 6)
                Spacer()
            }
            .padding(.top, 4)
        }
        .offset(dragging ? drag : .zero)
        .scaleEffect(dragging ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: dragging)
    }

    // MARK: - Physics

    private func flip(velocity: CGSize) {
        let power = -velocity.height                 // upward flick strength
        guard power > 70 else {                      // too weak to leave the table
            message = "Not enough on it. Flick harder."
            return
        }
        airborne = true
        attempts += 1
        Haptic.firm()

        // Map flick power to spin (degrees) and arc height. A clean single flip
        // is 360; the sweet spot sits around a well-judged medium flick.
        let spin = min(Double(power) * 0.82, 620)
        let lift = min(power * 0.55, 230)
        let mod = spin.truncatingRemainder(dividingBy: 360)
        let offBy = min(mod, 360 - mod)              // distance from a clean landing
        let success = spin > 300 && offBy < 34

        // Phase 1: launch, arc up, spin.
        withAnimation(.easeOut(duration: 0.4)) {
            cupSpin = spin
            cupLift = lift
        }

        // Phase 2: come down and settle either flat (success) or tipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            let base = (spin / 360).rounded() * 360
            withAnimation(.spring(response: 0.5, dampingFraction: success ? 0.72 : 0.5)) {
                cupLift = 0
                cupSpin = success ? base : base + (mod < 180 ? 118 : -118)   // tip to its side
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    result = success
                }
                if success {
                    streak += 1
                    flips += 1
                    best = max(best, streak)
                    Haptic.success()
                    message = perfect(offBy)
                } else {
                    streak = 0
                    Haptic.tap()
                }

                // Reset the cup for the next flick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        cupSpin = 0
                        result = nil
                    }
                    airborne = false
                    if success && streak == best && best > 0 { message = "Best streak: \(best)." }
                    else if !success { message = "Flick up to flip the cup." }
                }
            }
        }
    }

    private func perfect(_ offBy: Double) -> String {
        offBy < 10 ? "Perfect flip!" : ["Clean flip.", "Landed it.", "On the base."].randomElement() ?? "Landed it."
    }

    // MARK: - Scoreboard

    private var scoreboard: some View {
        HStack(spacing: 12) {
            stat("Streak", "\(streak)", Brand.hop)
            stat("Best", "\(best)", Brand.gold)
            stat("Landed", "\(flips)/\(attempts)", Brand.copper)
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

/// A solo-cup silhouette: wide rim, tapered base.
struct CupShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topInset = rect.width * 0.03
        let botInset = rect.width * 0.19
        p.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - botInset, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + botInset, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    NavigationStack { FlipCupGame() }
}
