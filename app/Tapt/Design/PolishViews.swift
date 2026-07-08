import SwiftUI

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
            LinearGradient(
                colors: [Brand.malt, Brand.copper.opacity(0.9), tint.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                TimelineView(.animation) { timeline in
                    GeometryReader { proxy in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ForEach(0..<10, id: \.self) { i in
                            let phase = CGFloat((t * 0.22) + Double(i) * 0.37)
                            let x = proxy.size.width * CGFloat((Double(i) * 0.173).truncatingRemainder(dividingBy: 1))
                            let y = proxy.size.height - ((phase.truncatingRemainder(dividingBy: 1)) * proxy.size.height)
                            let r = CGFloat(5 + (i % 4) * 4)
                            Circle()
                                .fill(Brand.foam.opacity(0.11))
                                .frame(width: r, height: r)
                                .position(x: x, y: y)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Brand.malt)
                        .frame(width: 44, height: 44)
                        .background(tint, in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Text(metric)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.foam)
                        .contentTransition(.numericText())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(Brand.foam)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.foam.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(caption)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Brand.gold, in: Capsule())
            }
            .padding(18)

            PourMeter(progress: poured ? 0.82 : 0.08)
                .frame(width: 72, height: 112)
                .offset(x: 8, y: 18)
                .opacity(0.9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Brand.gold.opacity(0.22), lineWidth: 1))
        .shadow(color: Brand.malt.opacity(0.24), radius: 18, y: 12)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.72).delay(0.12)) {
                poured = true
            }
        }
    }
}

struct PourMeter: View {
    let progress: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Brand.foam.opacity(0.16))
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Rectangle().fill(Brand.foam).frame(height: 12)
                    Rectangle().fill(Brand.gold)
                }
                .frame(height: 112 * min(max(progress, 0), 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.foam.opacity(0.5), lineWidth: 3))
    }
}

struct TaptEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle().fill(Brand.gold.opacity(0.18)).frame(width: 92, height: 92)
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Brand.gold)
            }
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
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus.circle.fill")
                        .font(.system(.headline, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(Brand.gold, in: Capsule())
                        .foregroundStyle(Brand.malt)
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
    }
}
