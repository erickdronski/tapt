import SwiftUI

/// A dope, die-cut passport sticker for one achievement. Earned stickers glow in
/// their tier color with a white cut border; locked ones sit dim with a progress
/// ring toward the threshold, so a new drinker sees the whole shelf to fill.
struct BadgeSticker: View {
    let badge: Badge
    let stats: PassportStats
    var size: CGFloat = 92

    private var earned: Bool { badge.earned(stats) }
    private var progress: Double { badge.progress(stats) }

    private var tierColor: Color {
        switch badge.tier {
        case .bronze: return Brand.copper
        case .silver: return Color(hex: 0x8C97A8)
        case .gold:   return Brand.gold
        case .elite:  return Brand.hop
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(
                        earned
                        ? AnyShapeStyle(LinearGradient(
                            colors: [tierColor, tierColor.opacity(0.72)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Brand.surface)
                    )
                    .overlay(Circle().stroke(.white.opacity(earned ? 0.9 : 0.06), lineWidth: 3))
                    .shadow(color: earned ? tierColor.opacity(0.42) : .black.opacity(0.12),
                            radius: earned ? 9 : 3, y: earned ? 5 : 2)

                // Locked: honest progress ring toward the threshold.
                if !earned && progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tierColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }

                // A soft top highlight for the "sticker sheen" on earned medals.
                if earned {
                    Circle()
                        .trim(from: 0.55, to: 0.95)
                        .stroke(.white.opacity(0.35), lineWidth: 2.5)
                        .rotationEffect(.degrees(-90))
                        .padding(9)
                        .blur(radius: 0.6)
                }

                // Custom Tapt-drawn glyph, not emoji. Inked dark on earned
                // (color comes from the tier disc), muted on locked.
                BadgeGlyph(
                    badge: badge,
                    ink: earned ? Brand.malt : Brand.muted.opacity(0.6),
                    accent: earned ? Brand.malt.opacity(0.28) : Brand.muted.opacity(0.18)
                )
                .frame(width: size * 0.6, height: size * 0.6)
                .opacity(earned ? 1 : 0.75)
                .shadow(color: earned ? .black.opacity(0.14) : .clear, radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)

            Text(badge.title)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(earned ? Brand.text : Brand.muted)
                .lineLimit(1).minimumScaleFactor(0.75)

            if earned {
                Text("Earned")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.hop)
            } else {
                Text("\(badge.current(stats))/\(badge.threshold)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title). \(earned ? "Earned" : "Locked, \(badge.current(stats)) of \(badge.threshold). \(badge.detail)")")
    }
}
