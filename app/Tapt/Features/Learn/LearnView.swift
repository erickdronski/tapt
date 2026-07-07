import SwiftUI

/// "Beer School" hub. Presented inside Discover's NavigationStack.
struct LearnView: View {
    var body: some View {
        List {
            LearnRow(title: "How beer is made", subtitle: "From grain to glass in 7 steps", icon: "gearshape.2.fill", tint: Brand.gold) { HowItsMadeView() }
            LearnRow(title: "Beer dictionary", subtitle: "Terms and slang, decoded", icon: "character.book.closed.fill", tint: Brand.hop) { GlossaryView() }
            LearnRow(title: "A short history of beer", subtitle: "9,000 years, fast", icon: "clock.arrow.circlepath", tint: Brand.copper) { TimelineView() }
            LearnRow(title: "Origin stories", subtitle: "How the greats got started", icon: "building.columns.fill", tint: Brand.malt) { OriginsView() }
        }
        .navigationTitle("Beer School")
    }
}

private struct LearnRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint == Brand.malt ? Brand.foam : Brand.malt)
                    .frame(width: 46, height: 46)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.headline, design: .rounded))
                    Text(subtitle).font(.subheadline).foregroundStyle(Brand.muted)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - How it's made
struct HowItsMadeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(LearnData.brewing) { step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(step.n)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(Brand.malt)
                            .frame(width: 44, height: 44)
                            .background(Brand.gold, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.title).font(.system(.headline, design: .rounded))
                            Text(step.what).font(.subheadline).foregroundStyle(Brand.text)
                            Label(step.machine, systemImage: "wrench.and.screwdriver.fill")
                                .font(.caption).foregroundStyle(Brand.copper)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("How beer is made")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Glossary
struct GlossaryView: View {
    @State private var query = ""

    private var filtered: [GlossaryTerm] {
        guard !query.isEmpty else { return LearnData.glossary }
        return LearnData.glossary.filter {
            $0.term.localizedCaseInsensitiveContains(query) || $0.definition.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered) { t in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(t.term).font(.system(.headline, design: .rounded))
                    if t.slang {
                        Text("slang")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.malt)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.hop, in: Capsule())
                    }
                }
                Text(t.definition).font(.subheadline).foregroundStyle(Brand.muted)
            }
            .padding(.vertical, 4)
        }
        .searchable(text: $query, prompt: "Search terms")
        .navigationTitle("Beer dictionary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Timeline
struct TimelineView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(LearnData.timeline) { m in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.year)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Brand.malt)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Brand.gold, in: Capsule())
                        Text(m.title).font(.system(.headline, design: .rounded))
                        Text(m.detail).font(.subheadline).foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle("A short history of beer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Origin stories
struct OriginsView: View {
    var body: some View {
        List(LearnData.origins) { o in
            NavigationLink {
                OriginDetailView(origin: o)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.name).font(.system(.headline, design: .rounded))
                    Text("\(o.founded)  \(o.place)").font(.subheadline).foregroundStyle(Brand.muted)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Origin stories")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OriginDetailView: View {
    let origin: BreweryOrigin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(origin.name).font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text("\(origin.founded)  \(origin.place)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Brand.copper)
                }
                Text(origin.story).font(.body).foregroundStyle(Brand.text)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Brand.gold)
                    Text(origin.fact).font(.subheadline).foregroundStyle(Brand.text)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.haze.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .background(Brand.background)
        .navigationTitle(origin.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
