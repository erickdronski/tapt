import SwiftUI

/// The data behind a shareable card. Comes from a real check-in.
struct PourCard: Identifiable {
    var id = UUID()
    var beer: String
    var brewery: String
    var style: String
    var score: Int
    var user: String
    var abv: String?
}

/// A brand-locked 9:16 card built to look identical wherever it is shared
/// (always the light "craft can" look, independent of the app theme).
struct ShareCard: View {
    let pour: PourCard

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tapt").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt)
                Spacer()
                Text("THE beer app").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.55))
            }
            .padding(.horizontal, 28).padding(.top, 28)

            Spacer()

            ZStack {
                Circle().stroke(Brand.malt.opacity(0.12), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(100, pour.score))) / 100)
                    .stroke(Brand.gold, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(pour.score)").font(.system(size: 64, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt)
                    Text("MY SCORE").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.55)).tracking(2)
                }
            }
            .frame(width: 180, height: 180)
            .padding(.bottom, 22)

            VStack(spacing: 5) {
                Text(pour.beer).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt).multilineTextAlignment(.center)
                Text(pour.brewery).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.7))
                HStack(spacing: 8) {
                    tag(pour.style)
                    if let abv = pour.abv { tag("ABV \(abv)") }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)

            Spacer()

            Text("@\(pour.user) tapt it")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.malt.opacity(0.55))
                .padding(.bottom, 28)
        }
        .frame(width: 360, height: 640)
        .background(LinearGradient(colors: [Brand.foam, Brand.haze], startPoint: .top, endPoint: .bottom))
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Brand.malt)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Brand.gold, in: Capsule())
    }
}
