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

/// Style-accurate glass tinting. Colors follow real SRM ranges per family
/// (straw pilsners, hazy wheats, amber IPAs, near-black stouts with tan foam).
/// Unknown or empty styles keep the canonical brand-gold glass. Illustration,
/// clearly branded artwork; never a fake product photo.
struct StyleGlassTint {
    let top: Color
    let mid: Color
    let bottom: Color
    let foamTop: Color
    let foamBottom: Color
    let haze: Double

    static let brand = StyleGlassTint(
        top: Color(hex: 0xFFD24D), mid: Color(hex: 0xF2A900), bottom: Color(hex: 0xC56B10),
        foamTop: .white, foamBottom: Color(hex: 0xF3E7CC), haze: 0
    )

    static func resolve(_ style: String?) -> StyleGlassTint {
        guard let style, !style.isEmpty else { return .brand }
        let s = style.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { s.contains($0) } }

        // Order matters: darkest and most specific families first.
        if has("stout", "porter", "schwarz", "black ale", "black ipa") {
            return StyleGlassTint(top: Color(hex: 0x4A2C14), mid: Color(hex: 0x2A160A), bottom: Color(hex: 0x140A04),
                                  foamTop: Color(hex: 0xF0DCC0), foamBottom: Color(hex: 0xD9B98E), haze: 0)
        }
        if has("dubbel", "quad", "abbey", "barleywine", "old ale", "scotch") {
            return StyleGlassTint(top: Color(hex: 0xA65A24), mid: Color(hex: 0x733414), bottom: Color(hex: 0x3E1A08),
                                  foamTop: Color(hex: 0xF5E3C8), foamBottom: Color(hex: 0xE2C49A), haze: 0)
        }
        if has("brown", "dunkel", "bock", "doppel", "mild") {
            return StyleGlassTint(top: Color(hex: 0xB97335), mid: Color(hex: 0x8A4A1B), bottom: Color(hex: 0x4F250B),
                                  foamTop: Color(hex: 0xF7E8D0), foamBottom: Color(hex: 0xE8CFA8), haze: 0)
        }
        if has("sour", "gose", "lambic", "berliner", "kriek", "flanders", "fruit") {
            return StyleGlassTint(top: Color(hex: 0xFFB37A), mid: Color(hex: 0xE86A4A), bottom: Color(hex: 0xA83A2E),
                                  foamTop: Color(hex: 0xFFF0E8), foamBottom: Color(hex: 0xF6D6C4), haze: 0.10)
        }
        if has("amber", "red ale", "red ipa", "märzen", "marzen", "vienna", "oktoberfest", "irish red", "altbier") {
            return StyleGlassTint(top: Color(hex: 0xF0A94E), mid: Color(hex: 0xD07B22), bottom: Color(hex: 0x8F4A10),
                                  foamTop: .white, foamBottom: Color(hex: 0xF0DDBE), haze: 0)
        }
        if has("wit", "wheat", "hefe", "weizen", "weiss") {
            return StyleGlassTint(top: Color(hex: 0xFFF3C4), mid: Color(hex: 0xFFD877), bottom: Color(hex: 0xDFAE45),
                                  foamTop: .white, foamBottom: Color(hex: 0xFAF0DC), haze: 0.22)
        }
        if has("hazy", "new england", "neipa") {
            return StyleGlassTint(top: Color(hex: 0xFFDF8A), mid: Color(hex: 0xF7B733), bottom: Color(hex: 0xD08A1E),
                                  foamTop: .white, foamBottom: Color(hex: 0xF7ECD4), haze: 0.20)
        }
        if has("ipa", "india pale") {
            return StyleGlassTint(top: Color(hex: 0xFFCC4D), mid: Color(hex: 0xF29C00), bottom: Color(hex: 0xB86A10),
                                  foamTop: .white, foamBottom: Color(hex: 0xF3E7CC), haze: 0)
        }
        if has("pils", "lager", "helles", "kölsch", "kolsch", "crisp", "dortmund") {
            return StyleGlassTint(top: Color(hex: 0xFFF2B8), mid: Color(hex: 0xFFE07A), bottom: Color(hex: 0xE8B93E),
                                  foamTop: .white, foamBottom: Color(hex: 0xFBF3DF), haze: 0)
        }
        if has("saison", "tripel", "golden", "blonde", "pale ale", "farmhouse") {
            return StyleGlassTint(top: Color(hex: 0xFFDD66), mid: Color(hex: 0xFFB627), bottom: Color(hex: 0xD98E1B),
                                  foamTop: .white, foamBottom: Color(hex: 0xF6ECD2), haze: 0.06)
        }
        return .brand
    }
}

struct BeerGlassView: View {
    var pour: CGFloat = 0.8          // 0...1 fill level
    // Static by default: the glass is simply THERE on load, already full, so it
    // never appears half-broken with foam floating over an empty glass while a
    // screen settles. Only the pour celebration opts in to the fill animation.
    var animatesPour: Bool = false
    /// Optional beer style; tints the pour to the style's real color family.
    var style: String? = nil

    private var tint: StyleGlassTint { StyleGlassTint.resolve(style) }

    /// The canonical mark's ink (brand/glass.svg #130A02).
    private let ink = Color(hex: 0x130A02)

    @State private var poured = false

    private var fill: CGFloat { animatesPour ? (poured ? pour : 0.06) : pour }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // Headroom above the rim so the canonical foam cloud can overflow it.
            let rimY = h * 0.16
            let glassH = h - rimY
            let glass = pintPath(w: w, h: h, rimY: rimY)
            let beerTopY = h - glassH * fill

            ZStack {
                // Back of the glass
                glass
                    .fill(
                        LinearGradient(
                            colors: [Brand.foam.opacity(0.35), Brand.foam.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                // Beer body, clipped to the glass
                beerBody(height: glassH * fill)
                    .frame(width: w, height: h, alignment: .bottom)
                    .clipShape(glass)

                // Wheat and hazy families read cloudy, not brilliant.
                if tint.haze > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(tint.haze))
                        .frame(width: w, height: glassH * fill, alignment: .bottom)
                        .frame(width: w, height: h, alignment: .bottom)
                        .clipShape(glass)
                }

                // ONE soft highlight streak (the canonical mark's single shine, not a glossy sheen)
                RoundedRectangle(cornerRadius: w * 0.06)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: w * 0.08, height: h * 0.5)
                    .offset(x: -w * 0.24, y: h * 0.06)
                    .clipShape(glass)

                // Heavy dark outline, matching the canonical mark's ink.
                glass
                    .stroke(ink, style: StrokeStyle(lineWidth: max(4, w * 0.05), lineJoin: .round))

                // Canonical foam cloud riding the beer line; at a full pour it
                // overflows the rim exactly like brand/glass.svg. Drawn last,
                // unclipped, with the mark's white gradient + ink outline.
                foamCloud(w: w, baselineY: beerTopY)
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

    private func beerBody(height: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.top, location: 0),
                        .init(color: tint.mid, location: 0.45),
                        .init(color: tint.bottom, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(height: height)
    }

    /// Shaker-pint silhouette matching the icon and landing hero: a nearly
    /// full-width rim, gentle taper, and a FLAT base with small rounded corners
    /// (a real beer glass, not a tapered vial). The rim sits at `rimY` so the
    /// canonical foam cloud has headroom to overflow it.
    private func pintPath(w: CGFloat, h: CGFloat, rimY: CGFloat) -> Path {
        var p = Path()
        let lipInset = w * 0.02          // rim ~ full width
        let baseInset = w * 0.17         // base ~66% of the rim
        let corner = w * 0.05            // small rounded base corners
        let belly = w * 0.015            // barely-there outward curve on the sides
        let midY = rimY + (h - rimY) * 0.52
        p.move(to: CGPoint(x: lipInset, y: rimY))
        p.addLine(to: CGPoint(x: w - lipInset, y: rimY))
        // right side down to the base
        p.addQuadCurve(
            to: CGPoint(x: w - baseInset, y: h - corner),
            control: CGPoint(x: w - baseInset + belly, y: midY)
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
            to: CGPoint(x: lipInset, y: rimY),
            control: CGPoint(x: baseInset - belly, y: midY)
        )
        p.closeSubpath()
        return p
    }

    /// The canonical foam cloud, traced from brand/glass.svg (bumpy crest,
    /// slight overhang past both rim edges, gentle sag below the beer line).
    /// `baselineY` is the beer surface it sits on.
    private func foamPath(w: CGFloat, baselineY: CGFloat) -> Path {
        let lip = w * 0.02
        let u = w - lip * 2               // rim span; the SVG glass is 210 units wide
        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: lip + nx * u, y: baselineY + ny * u)
        }
        var p = Path()
        p.move(to: pt(-0.033, 0.010))
        p.addCurve(to: pt(0.119, -0.276), control1: pt(-0.081, -0.152), control2: pt(0.005, -0.257))
        p.addCurve(to: pt(0.386, -0.352), control1: pt(0.110, -0.362), control2: pt(0.262, -0.400))
        p.addCurve(to: pt(0.662, -0.343), control1: pt(0.452, -0.429), control2: pt(0.595, -0.419))
        p.addCurve(to: pt(0.976, -0.248), control1: pt(0.776, -0.400), control2: pt(0.919, -0.352))
        p.addCurve(to: pt(1.033, 0.010), control1: pt(1.062, -0.238), control2: pt(1.052, -0.105))
        p.addCurve(to: pt(-0.033, 0.010), control1: pt(0.786, 0.038), control2: pt(0.214, 0.038))
        p.closeSubpath()
        return p
    }

    private func foamCloud(w: CGFloat, baselineY: CGFloat) -> some View {
        let path = foamPath(w: w, baselineY: baselineY)
        return path
            .fill(
                LinearGradient(
                    colors: [tint.foamTop, tint.foamBottom],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                path.stroke(
                    ink,
                    style: StrokeStyle(lineWidth: max(3, w * 0.045), lineJoin: .round)
                )
            )
    }
}

#Preview {
    BeerGlassView(pour: 1.0)
        .frame(width: 180)
        .padding(40)
        .background(Brand.background)
}
