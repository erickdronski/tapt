import SwiftUI
import UIKit

// The dopamine layer. Signature reward moments that make an action feel earned:
// a pour fills and a passport stamp thuds down, a vote count springs upward, a
// badge medallion shines in, the Beer of the Week crown descends. Gold confetti
// on every one. Reused everywhere something worth celebrating happens.
//
// Swift 6 note: no TimelineView(.animation) anywhere (it miscompiles under strict
// concurrency). Motion is driven by withAnimation on @State plus a stepped Timer.

// MARK: - Celebration kinds

enum TaptCelebration: Identifiable, Equatable {
    /// A beer was logged. The marquee moment: glass fills, passport stamps.
    case pourLogged(beer: String, rating: Double, place: String?)
    /// A vote landed. The number counts up with a bump.
    case voteCounted(beer: String, count: Int)
    /// A passport milestone unlocked a badge.
    case badgeUnlocked(title: String, symbol: String)
    /// Beer of the Week was crowned.
    case bowCrowned(beer: String)

    var id: String {
        switch self {
        case .pourLogged(let b, _, _):  return "pour-\(b)"
        case .voteCounted(let b, let c): return "vote-\(b)-\(c)"
        case .badgeUnlocked(let t, _):  return "badge-\(t)"
        case .bowCrowned(let b):        return "bow-\(b)"
        }
    }
}

// MARK: - Attach modifier

extension View {
    /// Presents a full-screen celebration when `celebration` becomes non-nil.
    /// `onFinish` fires after it plays out (or the user taps to skip) and the
    /// binding is cleared, so it's the place to continue the flow (e.g. share).
    func taptCelebration(_ celebration: Binding<TaptCelebration?>,
                         onFinish: @escaping () -> Void = {}) -> some View {
        modifier(TaptCelebrationModifier(celebration: celebration, onFinish: onFinish))
    }
}

private struct TaptCelebrationModifier: ViewModifier {
    @Binding var celebration: TaptCelebration?
    var onFinish: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if let kind = celebration {
                CelebrationOverlay(kind: kind) {
                    celebration = nil
                    onFinish()
                }
                .transition(.opacity)
                .zIndex(1000)
            }
        }
        .animation(.easeOut(duration: 0.28), value: celebration)
    }
}

// MARK: - Overlay

struct CelebrationOverlay: View {
    let kind: TaptCelebration
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var reveal = false      // stamp / crown / medallion thud
    @State private var confetti = false
    @State private var dismissed = false

    var body: some View {
        ZStack {
            // Dim, warm scrim with a soft gold glow behind the hero.
            Rectangle()
                .fill(Brand.malt.opacity(appear ? 0.62 : 0))
                .ignoresSafeArea()
            RadialGradient(colors: [Brand.gold.opacity(appear ? 0.22 : 0), .clear],
                           center: .center, startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
                .blendMode(.plusLighter)

            ConfettiBurst(active: confetti)
                .allowsHitTesting(false)

            hero
                .scaleEffect(appear ? 1 : 0.86)
                .opacity(appear ? 1 : 0)
                .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismissed = true }   // tap to skip; the sequence notices
        .task { await run() }
    }

    // The center content, per celebration kind.
    @ViewBuilder private var hero: some View {
        switch kind {
        case .pourLogged(let beer, let rating, let place):
            VStack(spacing: 18) {
                ZStack {
                    BeerGlassView(pour: max(0.35, rating / 5), animatesPour: !reduceMotion)
                        .frame(width: 132)
                    PassportStamp(label: "LOGGED", symbol: "checkmark")
                        .rotationEffect(.degrees(reveal ? -13 : -34))
                        .scaleEffect(reveal ? 1 : 1.9)
                        .opacity(reveal ? 1 : 0)
                        .offset(y: 6)
                }
                .frame(height: 232)
                title(beer)
                Label(String(format: "%.0f", rating * 20) + " · added to your Passport",
                      systemImage: "book.pages.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Brand.foam.opacity(0.9))
                if let place, !place.isEmpty {
                    Text(place).font(.caption).foregroundStyle(Brand.foam.opacity(0.6)).lineLimit(1)
                }
            }

        case .voteCounted(let beer, let count):
            VStack(spacing: 16) {
                CountUp(target: count)
                Label("vote counted", systemImage: "arrowtriangle.up.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.gold)
                title(beer)
            }

        case .badgeUnlocked(let heading, let symbol):
            VStack(spacing: 18) {
                Medallion(symbol: symbol, shine: reveal)
                    .frame(width: 150, height: 150)
                    .scaleEffect(reveal ? 1 : 0.4)
                    .rotationEffect(.degrees(reveal ? 0 : -30))
                Text("BADGE UNLOCKED")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .tracking(2).foregroundStyle(Brand.gold)
                title(heading)
            }

        case .bowCrowned(let beer):
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    BeerGlassView(pour: 0.82, animatesPour: !reduceMotion)
                        .frame(width: 128)
                        .padding(.top, 34)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(Brand.gold)
                        .shadow(color: Brand.gold.opacity(0.5), radius: 12)
                        .offset(y: reveal ? -6 : -70)
                        .opacity(reveal ? 1 : 0)
                }
                .frame(height: 232)
                Text("BEER OF THE WEEK")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .tracking(2).foregroundStyle(Brand.gold)
                title(beer)
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .foregroundStyle(Brand.foam)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    // MARK: sequence
    // Everything runs inside the single .task (MainActor-isolated), so mutating
    // @State + withAnimation is safe under Swift 6 strict concurrency. No
    // DispatchQueue, no nested Task, no withAnimation completion overload.

    @MainActor private func run() async {
        if reduceMotion {
            // No flying confetti under Reduce Motion, just show the moment.
            appear = true; reveal = true
            Haptic.success()
        } else {
            Haptic.firm()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { appear = true }
            await pause(0.7)
            if !dismissed {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { reveal = true }
                withAnimation(.easeOut(duration: 0.1)) { confetti = true }
                Haptic.celebrate()
            }
        }
        await hold(reduceMotion ? 1.5 : 1.7)   // ends early if tapped to skip
        dismissed = true
        withAnimation(.easeIn(duration: 0.26)) { appear = false; confetti = false }
        await pause(0.28)
        onFinish()
    }

    /// A plain pause.
    @MainActor private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// A hold that returns early the moment the user taps to skip.
    @MainActor private func hold(_ seconds: Double) async {
        var elapsed = 0.0
        while elapsed < seconds && !dismissed {
            try? await Task.sleep(for: .seconds(0.06))
            elapsed += 0.06
        }
    }
}

// MARK: - Passport stamp

/// A rubber-stamp mark, like the one that thuds onto a real passport page.
struct PassportStamp: View {
    var label: String
    var symbol: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 26, weight: .heavy))
            Text(label)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(1)
        }
        .foregroundStyle(Brand.copper)
        .frame(width: 118, height: 118)
        .overlay(Circle().stroke(Brand.copper, lineWidth: 5))
        .overlay(Circle().stroke(Brand.copper.opacity(0.5), lineWidth: 2).padding(9))
        .background(Circle().fill(Brand.foam.opacity(0.92)))
        .rotationEffect(.degrees(-8))
        .opacity(0.92)
        .shadow(color: Brand.malt.opacity(0.35), radius: 8, y: 4)
    }
}

// MARK: - Medallion (badge)

struct Medallion: View {
    var symbol: String
    var shine: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [Color(hex: 0xFFD24D), Brand.gold, Color(hex: 0xC56B10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(Circle().stroke(Brand.foam.opacity(0.65), lineWidth: 3).padding(8))
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Brand.malt)
            // shine sweep
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Brand.foam.opacity(0.7), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 34)
                .rotationEffect(.degrees(22))
                .offset(x: shine ? 90 : -90)
                .mask { Circle() }
                .animation(.easeInOut(duration: 0.8).delay(0.25), value: shine)
        }
        .shadow(color: Brand.gold.opacity(0.5), radius: 16, y: 6)
    }
}

// MARK: - Count-up number

/// Springs a number upward from a lower value to `target`, with a bump on land.
struct CountUp: View {
    var target: Int
    @State private var value = 0
    @State private var bump = false
    private let timer = Timer.publish(every: 0.045, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("\(value)")
            .font(.system(size: 76, weight: .black, design: .rounded))
            .foregroundStyle(Brand.foam)
            .monospacedDigit()
            .scaleEffect(bump ? 1.12 : 1)
            .shadow(color: Brand.gold.opacity(0.4), radius: 18)
            .onAppear { value = max(0, target - min(target, 8)) }
            .onReceive(timer) { _ in
                guard value < target else { return }
                let step = max(1, (target - value) / 4)
                value = min(target, value + step)
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { bump.toggle() }
            }
    }
}

// MARK: - Confetti

/// Lightweight gold-and-foam confetti. Deterministic per-index geometry so it
/// never reshuffles across view updates; no per-frame timers.
struct ConfettiBurst: View {
    var active: Bool
    var count: Int = 28

    private let palette: [Color] = [Brand.gold, Brand.foam, Brand.hop, Brand.copper,
                                    Color(hex: 0xFFD24D)]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    piece(i, w: w, h: h)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func frac(_ x: Double) -> Double { x - x.rounded(.down) }

    private func piece(_ i: Int, w: CGFloat, h: CGFloat) -> some View {
        let xf = frac(Double(i) * 0.61803)                 // even horizontal spread
        let startX = w * CGFloat(xf)
        let drift  = CGFloat((i % 2 == 0 ? 1 : -1)) * CGFloat(18 + (i % 5) * 10)
        let size   = CGFloat(6 + (i % 4) * 3)
        let rot    = Double((i % 2 == 0 ? 1 : -1) * (160 + i * 22))
        let dur    = 1.15 + Double(i % 5) * 0.12
        let delay  = Double(i % 6) * 0.045
        let color  = palette[i % palette.count]

        return RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: size, height: size * 1.6)
            .position(x: startX + (active ? drift : 0),
                      y: active ? h * 1.1 : h * 0.14)
            .rotationEffect(.degrees(active ? rot : 0))
            .opacity(active ? 0 : 1)
            .animation(.easeIn(duration: dur).delay(delay), value: active)
    }
}

#Preview("Pour logged") {
    let demo: TaptCelebration? = .pourLogged(beer: "Pliny the Elder", rating: 4.5,
                                             place: "Russian River, Santa Rosa, CA")
    return ZStack { Brand.background.ignoresSafeArea() }
        .taptCelebration(.constant(demo))
}
