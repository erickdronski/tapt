import SwiftUI
import UIKit

// Motion & tactility system — the "expensive app" layer.
// Haptics on meaningful touches, a shared press style, shimmer skeletons for
// every loading surface, and the hero beer glass rendered as real glass.

// MARK: - Haptics

enum Haptic {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func firm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}

// MARK: - Press style (tactile scale-down on touch)

struct TaptPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TaptPressStyle {
    static var taptPress: TaptPressStyle { TaptPressStyle() }
}

// MARK: - Shimmer skeletons

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, Brand.foam.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: proxy.size.width * phase)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

/// A stack of placeholder rows shown while real data loads. Honest by design:
/// it's obviously a loading state, never fake content.
struct TaptSkeletonList: View {
    var rows: Int = 5
    var rowHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Brand.haze.opacity(0.6))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Brand.haze.opacity(0.6))
                            .frame(width: 130 + CGFloat((i * 37) % 70), height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Brand.haze.opacity(0.4))
                            .frame(width: 80 + CGFloat((i * 53) % 90), height: 9)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(height: rowHeight)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
                .modifier(Shimmer())
            }
        }
        .padding(.horizontal)
        .transition(.opacity)
    }
}

// MARK: - The beer glass, done properly

/// A real glass of beer: curved pint silhouette, gradient-depth beer, live
/// rising bubbles, an irregular foam head, and a glass shine. Pure vector —
/// crisp at any size. The app's signature graphic.
struct BeerGlassView: View {
    var pour: CGFloat = 0.8          // 0...1 fill level
    var animatesPour: Bool = true

    @State private var poured = false

    private var fill: CGFloat { animatesPour ? (poured ? pour : 0.06) : pour }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let glass = pintPath(w: w, h: h)

            ZStack {
                // Back of the glass
                glass
                    .fill(
                        LinearGradient(
                            colors: [Brand.foam.opacity(0.35), Brand.foam.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                // Beer body with depth + live bubbles, clipped to the glass
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .bottom) {
                        beerBody(h: h)
                        bubbles(t: t, w: w, h: h)
                        foam(w: w)
                            .offset(y: -h * fill + 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(width: w, height: h, alignment: .bottom)
                }
                .clipShape(glass)

                // Glass shine streak
                RoundedRectangle(cornerRadius: w * 0.08)
                    .fill(
                        LinearGradient(
                            colors: [Brand.foam.opacity(0.5), Brand.foam.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: w * 0.12, height: h * 0.62)
                    .offset(x: -w * 0.26, y: -h * 0.08)
                    .clipShape(glass)

                // Glass outline
                glass
                    .stroke(
                        LinearGradient(
                            colors: [Brand.malt.opacity(0.85), Brand.malt.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: max(3, w * 0.035), lineJoin: .round)
                    )
            }
            .shadow(color: Brand.malt.opacity(0.22), radius: 16, y: 10)
        }
        .aspectRatio(0.62, contentMode: .fit)
        .onAppear {
            guard animatesPour else { return }
            poured = false
            withAnimation(.spring(response: 1.5, dampingFraction: 0.82).delay(0.25)) {
                poured = true
            }
        }
    }

    private func beerBody(h: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xF7C94B), location: 0),
                        .init(color: Color(hex: 0xF2A900), location: 0.45),
                        .init(color: Color(hex: 0xC97E07), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: h * fill)
    }

    /// Rising bubbles on deterministic per-index paths.
    private func bubbles(t: TimeInterval, w: CGFloat, h: CGFloat) -> some View {
        let beerTop: CGFloat = h * (1 - fill)
        return ForEach(0..<14, id: \.self) { i in
            let speed: Double = 0.10 + Double(i % 5) * 0.035
            let phase: Double = Double(i) * 0.37
            let progress: Double = (t * speed + phase).truncatingRemainder(dividingBy: 1.0)
            let bx: CGFloat = w * (0.18 + CGFloat((Double(i) * 0.618).truncatingRemainder(dividingBy: 1.0)) * 0.64)
            let wobble: CGFloat = CGFloat(sin(t * 1.7 + Double(i))) * 2.5
            let size: CGFloat = CGFloat(2 + (i % 4))
            let by: CGFloat = h - CGFloat(progress) * (h * fill * 0.92)
            Circle()
                .fill(Brand.foam.opacity(0.5 - progress * 0.35))
                .frame(width: size, height: size)
                .position(x: bx + wobble, y: max(by, beerTop + 8))
        }
    }

    /// Classic pint silhouette: wider lip, gentle taper, rounded base.
    private func pintPath(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        let lipInset = w * 0.06
        let baseInset = w * 0.20
        p.move(to: CGPoint(x: lipInset, y: 0))
        p.addLine(to: CGPoint(x: w - lipInset, y: 0))
        p.addCurve(
            to: CGPoint(x: w - baseInset, y: h - w * 0.10),
            control1: CGPoint(x: w - lipInset - w * 0.01, y: h * 0.42),
            control2: CGPoint(x: w - baseInset - w * 0.02, y: h * 0.78)
        )
        p.addQuadCurve(
            to: CGPoint(x: baseInset, y: h - w * 0.10),
            control: CGPoint(x: w / 2, y: h + w * 0.04)
        )
        p.addCurve(
            to: CGPoint(x: lipInset, y: 0),
            control1: CGPoint(x: baseInset + w * 0.02, y: h * 0.78),
            control2: CGPoint(x: lipInset + w * 0.01, y: h * 0.42)
        )
        p.closeSubpath()
        return p
    }

    private func foam(w: CGFloat) -> some View {
        let blobs: [(x: CGFloat, r: CGFloat, y: CGFloat)] = [
            (0.16, 0.10, 0.2), (0.30, 0.13, -0.25), (0.46, 0.11, 0.15),
            (0.60, 0.14, -0.3), (0.76, 0.10, 0.1), (0.88, 0.08, -0.1),
        ]
        return ZStack {
            Capsule()
                .fill(Brand.foam)
                .frame(width: w * 0.86, height: w * 0.15)
            ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                Circle()
                    .fill(Brand.foam)
                    .frame(width: w * blob.r * 2)
                    .offset(x: w * (blob.x - 0.5), y: w * blob.r * blob.y - w * 0.05)
            }
        }
        .compositingGroup()
        .shadow(color: Brand.malt.opacity(0.08), radius: 3, y: 2)
    }
}

#Preview {
    BeerGlassView(pour: 0.8)
        .frame(width: 180)
        .padding(40)
        .background(Brand.background)
}
