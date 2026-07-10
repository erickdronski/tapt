import SwiftUI

/// Game Night Guides, how to play classic party games with a real deck (or
/// nothing at all), plus ready-to-run party templates. The digital versions
/// live in Games; these are for when the table wants the real thing.
struct GameNightGuidesView: View {
    @State private var kind: GuideKind = .cards

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TaptHeroPanel(
                    title: "Game Night Guides",
                    subtitle: "Got a deck of cards or just a crew? Every classic, explained in a minute. Digital versions live in Games.",
                    metric: "📖",
                    caption: "Play, don't push",
                    icon: "book.fill",
                    tint: Brand.hop
                )

                kindPicker

                ForEach(GameGuidesData.guides.filter { $0.kind == kind }) { guide in
                    guideCard(guide)
                }

                Label(GameGuidesData.safetyLine, systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("Game Night Guides")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var kindPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuideKind.allCases) { k in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { kind = k }
                    } label: {
                        Text(k.rawValue)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(kind == k ? Brand.gold : Brand.surface, in: Capsule())
                            .foregroundStyle(kind == k ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.malt.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func guideCard(_ guide: GameGuide) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .monospaced).weight(.heavy))
                            .foregroundStyle(Brand.malt)
                            .frame(width: 22, height: 22)
                            .background(Brand.gold, in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(Brand.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("🏠 \(guide.houseRule)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.copper)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(guide.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                Text(guide.vibe)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                HStack(spacing: 10) {
                    Label(guide.players, systemImage: "person.2.fill")
                    Label(guide.needs, systemImage: "checklist")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Brand.copper)
                .lineLimit(1)
            }
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.malt.opacity(0.08)))
        .tint(Brand.muted)
    }
}
