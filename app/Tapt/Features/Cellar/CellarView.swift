import SwiftUI

/// Cellar tab. Empty until real check-ins exist; also the home of the shareable pour card.
struct CellarView: View {
    @State private var showShare = false
    private let example = PourCard(beer: "Hazy Little Thing", brewery: "Sierra Nevada",
                                   style: "Hazy IPA", score: 88, user: "you", abv: "6.7%")

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 44)).foregroundStyle(Brand.gold)
                    Text("Your Cellar is thirsty")
                        .font(.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(Brand.text)
                    Text("Scan and rate your first pour to start your Cellar and fill your Passport.")
                        .font(.body).foregroundStyle(Brand.muted).multilineTextAlignment(.center).padding(.horizontal, 36)
                    Button { showShare = true } label: {
                        Label("Preview a share card", systemImage: "square.and.arrow.up")
                            .font(.system(.headline, design: .rounded))
                            .padding(.horizontal, 20).padding(.vertical, 13)
                            .background(Brand.gold, in: Capsule()).foregroundStyle(Brand.malt)
                    }
                    .padding(.top, 6)
                }
            }
            .navigationTitle("Cellar")
            .sheet(isPresented: $showShare) {
                NavigationStack {
                    ScrollView { CardShareView(pour: example).padding(.vertical) }
                        .background(Brand.background)
                        .navigationTitle("Share your pour")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") { showShare = false } }
                        }
                }
            }
        }
    }
}
