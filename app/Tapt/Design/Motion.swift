import SwiftUI
import UIKit

// Motion & tactility system, the "expensive app" layer.
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

/// The canonical Tapt beer glass, matching brand/glass.svg: a line-art pint with
/// a gold beer fill, a solid foam cap, ONE soft highlight, and a heavy dark
/// outline. No rising bubbles, no glossy sheen. It still fills on appear for a
/// little life, but the resting mark is the canonical one, used everywhere.
struct BeerGlassView: View {
    var pour: CGFloat = 0.8          // 0...1 fill level
    var animatesPour: Bool = true

    /// The canonical mark's ink (brand/glass.svg #130A02).
    private let ink = Color(hex: 0x130A02)

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
                ZStack(alignment: .bottom) {
                    beerBody(h: h)
                    foam(w: w)
                        .offset(y: -h * fill + 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: w, height: h, alignment: .bottom)
                .clipShape(glass)

                // ONE soft highlight streak (the canonical mark's single shine, not a glossy sheen)
                RoundedRectangle(cornerRadius: w * 0.06)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: w * 0.08, height: h * 0.55)
                    .offset(x: -w * 0.24, y: -h * 0.02)
                    .clipShape(glass)

                // Heavy dark outline, matching the canonical mark's ink.
                glass
                    .stroke(ink, style: StrokeStyle(lineWidth: max(4, w * 0.05), lineJoin: .round))
            }
            .shadow(color: Brand.malt.opacity(0.22), radius: 16, y: 10)
        }
        .aspectRatio(0.62, contentMode: .fit)
        .onAppear {
            if animatesPour {
                poured = false
                withAnimation(.spring(response: 1.5, dampingFraction: 0.82).delay(0.25)) {
                    poured = true
                }
            } else {
                poured = true
            }
        }
    }

    private func beerBody(h: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFD24D), location: 0),
                        .init(color: Color(hex: 0xF2A900), location: 0.45),
                        .init(color: Color(hex: 0xC56B10), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: h * fill)
    }

    /// Shaker-pint silhouette matching the icon and landing hero: a nearly
    /// full-width rim, gentle taper, and a FLAT base with small rounded corners
    /// (a real beer glass, not a tapered vial).
    private func pintPath(w: CGFloat, h: CGFloat) -> Path {
        var p = Path()
        let lipInset = w * 0.02          // rim ~ full width
        let baseInset = w * 0.17         // base ~66% of the rim
        let corner = w * 0.05            // small rounded base corners
        let belly = w * 0.015            // barely-there outward curve on the sides
        p.move(to: CGPoint(x: lipInset, y: 0))
        p.addLine(to: CGPoint(x: w - lipInset, y: 0))
        // right side down to the base
        p.addQuadCurve(
            to: CGPoint(x: w - baseInset, y: h - corner),
            control: CGPoint(x: w - baseInset + belly, y: h * 0.52)
        )
        // rounded bottom-right corner
        p.addQuadCurve(
            to: CGPoint(x: w - baseInset - corner, y: h),
            control: CGPoint(x: w - baseInset, y: h)
        )
        // flat base
        p.addLine(to: CGPoint(x: baseInset + corner, y: h))
        // rounded bottom-left corner
        p.addQuadCurve(
            to: CGPoint(x: baseInset, y: h - corner),
            control: CGPoint(x: baseInset, y: h)
        )
        // left side up to the rim
        p.addQuadCurve(
            to: CGPoint(x: lipInset, y: 0),
            control: CGPoint(x: baseInset - belly, y: h * 0.52)
        )
        p.closeSubpath()
        return p
    }

    /// Solid foam cap outlined in ink, matching the canonical mark. No bubbles.
    private func foam(w: CGFloat) -> some View {
        Capsule()
            .fill(Brand.foam)
            .frame(width: w * 0.9, height: max(8, w * 0.17))
            .overlay(Capsule().stroke(ink, lineWidth: max(2, w * 0.028)))
            .compositingGroup()
            .shadow(color: ink.opacity(0.10), radius: 3, y: 2)
    }
}

#Preview {
    BeerGlassView(pour: 0.8)
        .frame(width: 180)
        .padding(40)
        .background(Brand.background)
}
