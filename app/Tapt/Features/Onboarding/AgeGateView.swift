import SwiftUI

/// A single first-launch assurance gate shared by guest and account journeys.
/// Tapt stores only the confirmation, never a date of birth.
struct AgeGateView: View {
    let onConfirm: () -> Void
    @State private var declined = false

    var body: some View {
        ZStack {
            Brand.background.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                BeerGlassView(pour: 0.72)
                    .frame(width: 118)

                Text(declined ? "Tapt is not available yet" : "Before the first pour")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)

                Text(declined
                     ? "Come back when you are of legal drinking age where you live."
                     : "Tapt is for people of legal drinking age where they live. We store your confirmation, not your birth date.")
                    .font(.body)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if declined {
                    Button("Review again") { declined = false }
                        .font(.headline)
                        .foregroundStyle(Brand.text)
                } else {
                    VStack(spacing: 12) {
                        Button {
                            Haptic.success()
                            onConfirm()
                        } label: {
                            Text("I am of legal drinking age")
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(Brand.malt)
                        }
                        .buttonStyle(.plain)

                        Button("I am not of legal drinking age") { declined = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: 420)
                }

                HStack(spacing: 18) {
                    Link("Privacy", destination: URL(string: AppLinks.privacy)!)
                    Link("Terms", destination: URL(string: AppLinks.terms)!)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.copper)
                Spacer()
            }
            .padding(28)
        }
    }
}

#Preview { AgeGateView(onConfirm: {}) }
