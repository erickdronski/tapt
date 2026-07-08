import SwiftUI

/// Log a Pour: pick a beer, rate it, save the check-in, then share the card.
struct LogPourView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onLogged: () -> Void = {}

    @State private var beers: [CatalogBeer] = []
    @State private var search = ""
    @State private var selected: BeerPick?
    @State private var rating: Double = 4
    @State private var flavorTags: Set<String> = []
    @State private var glassware = "Pint"
    @State private var occasion = "bar"
    @State private var saving = false
    @State private var sharePour: PourCard?

    private let tags = ["hoppy", "malty", "crisp", "fruity", "roasty", "sour", "sweet", "dry"]
    private let glasswareOptions = ["Pint", "Can", "Bottle", "Tulip", "Snifter", "Flight"]
    private let occasionOptions = ["home", "bar", "restaurant", "event", "sports", "other"]

    private var filtered: [CatalogBeer] {
        search.isEmpty ? beers : beers.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.breweryName.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let beer = selected { rate(beer) } else { picker }
            }
            .background(Brand.background)
            .navigationTitle(selected == nil ? "Log a pour" : "Rate it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selected == nil ? "Cancel" : "Back") {
                        if selected == nil { dismiss() } else { selected = nil }
                    }
                }
            }
            .task { beers = (try? await CheckinService.catalog()) ?? [] }
            .sheet(item: $sharePour) { pour in
                NavigationStack {
                    ScrollView { CardShareView(pour: pour).padding(.vertical) }
                        .background(Brand.background)
                        .navigationTitle("Share your pour").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                }
            }
        }
    }

    private var picker: some View {
        List(filtered) { beer in
            Button { selected = beer.pick; rating = 4; flavorTags = [] } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(beer.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                    Text("\(beer.breweryName)  \(beer.style ?? "")").font(.caption).foregroundStyle(Brand.muted)
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $search, prompt: "Search beers")
    }

    private func rate(_ beer: BeerPick) -> some View {
        ScrollView {
            VStack(spacing: 18) {
            Text(beer.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text).multilineTextAlignment(.center)
            Text("\(beer.breweryName)  \(beer.style ?? "")").foregroundStyle(Brand.muted)
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: Double(i) <= rating ? "star.fill" : "star")
                        .font(.title).foregroundStyle(Brand.gold)
                        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { rating = Double(i) } }
                }
            }
            .padding(.vertical, 6)
            section("Flavor notes") {
                chipWrap(tags, selection: $flavorTags)
            }
            section("Glass") {
                pickerRow(glasswareOptions, selection: $glassware)
            }
            section("Occasion") {
                pickerRow(occasionOptions, selection: $occasion)
            }
            Button(saving ? "Saving..." : "Log it") { save(beer) }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Brand.malt)
                .disabled(saving)
            }
            .padding()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipWrap(_ items: [String], selection: Binding<Set<String>>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selection.wrappedValue.contains(item)
                Button {
                    if on { selection.wrappedValue.remove(item) } else { selection.wrappedValue.insert(item) }
                } label: {
                    Text(item.capitalized)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Brand.gold : Brand.surface, in: Capsule())
                        .foregroundStyle(on ? Brand.malt : Brand.text)
                        .overlay(Capsule().stroke(Brand.malt.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pickerRow(_ items: [String], selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = selection.wrappedValue == item
                    Button { selection.wrappedValue = item } label: {
                        Text(item.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(on ? Brand.gold : Brand.surface, in: Capsule())
                            .foregroundStyle(on ? Brand.malt : Brand.text)
                            .overlay(Capsule().stroke(Brand.malt.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save(_ beer: BeerPick) {
        guard let uid = session.user?.id else { return }
        saving = true
        Task {
            try? await CheckinService.log(
                beer: beer,
                userId: uid,
                rating: rating,
                flavorTags: Array(flavorTags).sorted(),
                glassware: glassware,
                occasion: occasion
            )
            saving = false
            onLogged()
            sharePour = PourCard(
                beer: beer.name, brewery: beer.breweryName, style: beer.style ?? "",
                score: Int(rating / 5 * 100), user: "you",
                abv: beer.abv.map { String(format: "%.1f%%", $0) }
            )
        }
    }
}
