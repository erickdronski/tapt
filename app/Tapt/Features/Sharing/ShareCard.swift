import SwiftUI
import UIKit

/// The data behind a shareable card. Comes from a real check-in.
struct PourCard: Identifiable {
    var id = UUID()
    var beer: String
    var brewery: String
    var style: String
    var score: Int
    var user: String
    var abv: String?
    var place: String? = nil
    var beerId: String? = nil       // used to fetch the beer photo for the card
    var rating: Int = 0             // 1-5 stars
    var imageUrl: String? = nil     // real beer photo if we already have it
    var country: String? = nil
}

/// A brand-locked 9:16 card built to look identical wherever it is shared. Now leads
/// with the real beer photo (loaded before render since ImageRenderer is synchronous),
/// the drinker's rating, and the score, so it reads as a proud, social pour.
struct ShareCard: View {
    let pour: PourCard
    var beerImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 0) {
                    Text("Tapt").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt)
                    Text(".").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Brand.gold)
                }
                Spacer()
                Text("THE BEER SUPERAPP").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.5)).tracking(1)
            }
            .padding(.horizontal, 26).padding(.top, 26)

            Spacer(minLength: 8)

            // Hero: real beer photo with the score as a stamp; falls back to the ring.
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = beerImage {
                        Image(uiImage: img).resizable().scaledToFit()
                            .shadow(color: Brand.malt.opacity(0.28), radius: 14, y: 10)
                    } else {
                        scoreRing.frame(width: 168, height: 168)
                    }
                }
                .frame(height: 214)

                if beerImage != nil {
                    scoreRing.frame(width: 92, height: 92)
                        .background(Circle().fill(Brand.foam).shadow(color: Brand.malt.opacity(0.25), radius: 8, y: 3))
                        .offset(x: 8, y: 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 26)

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Text(pour.beer).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                Text([pour.brewery, pour.country ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.68))

                if pour.rating > 0 {
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= pour.rating ? "star.fill" : "star")
                                .font(.system(size: 15)).foregroundStyle(Brand.gold)
                        }
                    }
                    .padding(.top, 2)
                }

                HStack(spacing: 8) {
                    if !pour.style.isEmpty { tag(pour.style) }
                    if let abv = pour.abv { tag("ABV \(abv)") }
                }
                .padding(.top, 6)

                if let place = pour.place, !place.isEmpty {
                    Label(place, systemImage: "mappin.circle.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.malt.opacity(0.55))
                        .multilineTextAlignment(.center).lineLimit(1).padding(.top, 2)
                }
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 8)

            Text("@\(pour.user) tapt it").font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.malt.opacity(0.5)).padding(.bottom, 26)
        }
        .frame(width: 360, height: 640)
        .background(LinearGradient(colors: [Brand.foam, Brand.haze], startPoint: .top, endPoint: .bottom))
    }

    private var scoreRing: some View {
        ZStack {
            Circle().stroke(Brand.malt.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(100, pour.score))) / 100)
                .stroke(Brand.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(pour.score)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Brand.malt)
                Text("SCORE").font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(Brand.malt.opacity(0.5)).tracking(1.5)
            }
        }
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Brand.malt)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Brand.gold, in: Capsule())
    }
}
