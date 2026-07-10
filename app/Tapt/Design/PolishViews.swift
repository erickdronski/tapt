import SwiftUI

/// The signature hero panel: layered gradient depth, drifting bubble field,
/// a real poured glass, and double-layer shadows. Same API as v1.
struct TaptHeroPanel: View {
    let title: String
    let subtitle: String
    let metric: String
    let caption: String
    let icon: String
    var tint: Color = Brand.gold

    @State private var poured = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Depth: linear base + radial glow + vignette
            LinearGradient(
                colors: [Brand.malt, Brand.copper.opacity(0.92), tint.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [tint.opacity(0.35), .clear],
                    center: .bottomTrailing, startRadius: 10, endRadius: 320
                )
            )
            .overlay(
                LinearGradient(
                    colors: [Brand.malt.opacity(0.25), .clear],
                    startPoint: .top, endPoint: .center
                )
            )
            .overlay {
                GeometryReader { proxy in
                    ForEach(0..<12, id: \.self) { i in
                        let x = proxy.size.width * CGFloat((Double(i) * 0.173).truncatingRemainder(dividingBy: 1))
                        let r = CGFloat(4 + (i % 5) * 4)
                        Circle()
                            .fill(Brand.foam.opacity(i % 3 == 0 ? 0.16 : 0.09))
                            .frame(width: r, height: r)
                            .blur(radius: i % 4 == 0 ? 1.5 : 0)
                            .position(x: x, y: poured ? -24 : proxy.size.height + 24)
                            .animation(
                                .linear(duration: Double(6 + (i % 6)))
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.35),
                                value: poured
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Brand.malt)
                        .frame(width: 44, height: 44)
                        .background(tint, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Brand.foam.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Brand.malt.opacity(0.3), radius: 6, y: 3)
                    Spacer()
                    Text(metric)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.foam)
                        .contentTransition(.numericText())
                        .shadow(color: Brand.malt.opacity(0.4), radius: 4, y: 2)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.foam)
                        .shadow(color: Brand.malt.opacity(0.35), radius: 3, y: 1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.foam.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 68)

                Text(caption)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Brand.gold)
                            .shadow(color: Brand.malt.opacity(0.25), radius: 4, y: 2)
                    )
            }
            .padding(18)

            BeerGlassView(pour: 0.82)
                .frame(width: 74)
                .rotationEffect(.degrees(4))
                .offset(x: 2, y: 12)
                .opacity(0.96)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [Brand.foam.opacity(0.35), Brand.gold.opacity(0.15)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Brand.malt.opacity(0.10), radius: 3, y: 2)
        .shadow(color: Brand.malt.opacity(0.22), radius: 22, y: 14)
        .onAppear { poured = true }
    }
}

/// Collapsible section — tap the header to expand/collapse. Saves real estate
/// on dense screens; springy chevron, remembers nothing (fresh per screen).
struct TaptCollapse<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    var tint: Color = Brand.gold
    @State private var expanded: Bool
    @ViewBuilder var content: () -> Content

    init(title: String, subtitle: String? = nil, icon: String, tint: Color = Brand.gold,
         startExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.content = content
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Haptic.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Brand.malt)
                        .frame(width: 38, height: 38)
                        .background(tint, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Brand.text)
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(Brand.muted).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Brand.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.taptPress)

            if expanded {
                VStack(spacing: 10) { content() }
                    .padding([.horizontal, .bottom], 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.18)))
    }
}

/// Branded empty state with a gently floating icon and glow ring.
/// Honest empty > fake content, so make empty beautiful.
struct TaptEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    var action: (() -> Void)?

    @State private var floating = false

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Brand.gold.opacity(0.28), Brand.gold.opacity(0.05)],
                            center: .center, startRadius: 8, endRadius: 60
                        )
                    )
                    .frame(width: 104, height: 104)
                    .scaleEffect(floating ? 1.06 : 0.97)
                Circle()
                    .stroke(Brand.gold.opacity(0.25), lineWidth: 1.2)
                    .frame(width: 92, height: 92)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Brand.gold, Brand.copper], startPoint: .top, endPoint: .bottom)
                    )
                    .offset(y: floating ? -4 : 3)
            }
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: floating)

            Text(title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let actionTitle, let action {
                Button {
                    Haptic.tap()
                    action()
                } label: {
                    Label(actionTitle, systemImage: "plus.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(Brand.gold)
                                .shadow(color: Brand.gold.opacity(0.4), radius: 10, y: 5)
                        )
                        .foregroundStyle(Brand.malt)
                }
                .buttonStyle(.taptPress)
                .padding(.top, 4)
            }
        }
        .padding(24)
        .onAppear { floating = true }
    }
}
