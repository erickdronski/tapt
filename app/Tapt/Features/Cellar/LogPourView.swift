import SwiftUI

/// Log a Pour: pick a beer, rate it, save the check-in, then share the card.
struct LogPourView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onLogged: () -> Void = {}

    @State private var beers: [CatalogBeer] = []
    @State private var venues: [BreweryMapVenue] = []
    @State private var search = ""
    @State private var venueSearch = ""
    @State private var selected: BeerPick?
    @State private var selectedVenue: BreweryMapVenue?
    @State private var rating: Double = 4
    @State private var flavorTags: Set<String> = []
    @State private var glassware = "Pint"
    @State private var occasion = "bar"
    @State private var saving = false
    @State private var sharePour: PourCard?
    @State private var errorMessage: String?

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
                        if selected == nil {
                            dismiss()
                        } else {
                            selected = nil
                            selectedVenue = nil
                            venueSearch = ""
                        }
                    }
                }
            }
            .task {
                beers = (try? await CheckinService.catalog()) ?? []
                venues = (try? await WorldBeerService.breweryMap(limit: 800)) ?? []
            }
            .sheet(item: $sharePour) { pour in
                NavigationStack {
                    ScrollView { CardShareView(pour: pour).padding(.vertical) }
                        .background(Brand.background)
                        .navigationTitle("Share your pour").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                }
            }
            .alert("Could not log pour", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Try again in a moment.")
            }
        }
    }

    private var picker: some View {
        List(filtered) { beer in
            Button {
                selected = beer.pick
                rating = 4
                flavorTags = []
                selectedVenue = nil
                venueSearch = beer.breweryName
            } label: {
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
            section("Brewery or taproom") {
                venuePicker(for: beer)
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

    private func venuePicker(for beer: BeerPick) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedVenue {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Brand.malt)
                        .frame(width: 34, height: 34)
                        .background(Brand.hop, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedVenue.name)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Brand.text)
                            .lineLimit(1)
                        Text(selectedVenue.subtitle.isEmpty ? "Tapt brewery map" : selectedVenue.subtitle)
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        self.selectedVenue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Brand.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Brand.hop.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.hop.opacity(0.35), lineWidth: 1))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Brand.muted)
                    TextField("Search brewery or city", text: $venueSearch)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                }
                .padding(11)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.10), lineWidth: 1))

                let matches = venueMatches(for: beer)
                if matches.isEmpty {
                    Text(venues.isEmpty ? "Brewery radar is loading." : "No brewery match yet. You can still log the pour.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(matches) { venue in
                            Button {
                                selectedVenue = venue
                                venueSearch = venue.name
                            } label: {
                                venueRow(venue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func venueRow(_ venue: BreweryMapVenue) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Brand.malt)
                .frame(width: 34, height: 34)
                .background(Brand.haze, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(venue.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(venue.subtitle.isEmpty ? venue.typeLabel.capitalized : venue.subtitle)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(venue.sourceBadge)
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.malt)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Brand.gold, in: Capsule())
        }
        .padding(10)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.08), lineWidth: 1))
    }

    private func venueMatches(for beer: BeerPick) -> [BreweryMapVenue] {
        let term = venueSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty {
            return Array(venues.prefix(8))
        }

        let searchMatches = venues.filter { venue in
            [venue.name, venue.city, venue.region, venue.country, venue.breweryType]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
        if !searchMatches.isEmpty {
            return Array(searchMatches.prefix(8))
        }

        let brewery = beer.breweryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brewery.isEmpty else { return [] }
        return Array(venues.filter { venue in
            venue.name.localizedCaseInsensitiveContains(brewery) || brewery.localizedCaseInsensitiveContains(venue.name)
        }.prefix(8))
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
            do {
                try await CheckinService.log(
                    beer: beer,
                    userId: uid,
                    rating: rating,
                    flavorTags: Array(flavorTags).sorted(),
                    glassware: glassware,
                    occasion: occasion,
                    venue: selectedVenue
                )
                await MainActor.run {
                    saving = false
                    onLogged()
                    sharePour = PourCard(
                        beer: beer.name, brewery: beer.breweryName, style: beer.style ?? "",
                        score: Int(rating / 5 * 100), user: "you",
                        abv: beer.abv.map { String(format: "%.1f%%", $0) },
                        place: selectedVenue.map { sharePlace($0) }
                    )
                }
            } catch {
                await MainActor.run {
                    saving = false
                    errorMessage = "Tapt could not save that pour yet. Please try again."
                }
            }
        }
    }

    private func sharePlace(_ venue: BreweryMapVenue) -> String {
        let location = [venue.city, venue.region, venue.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return location.isEmpty ? venue.name : "\(venue.name), \(location)"
    }
}
