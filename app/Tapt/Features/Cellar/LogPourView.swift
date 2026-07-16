import SwiftUI

/// Race an async operation against a wall-clock timeout so a hung network call
/// (e.g. the Simulator keychain/session gotcha, or a dropped connection) can
/// never wedge the UI on a spinner with no success and no error. On timeout it
/// throws, so the caller's catch surfaces a real, dismissible error.
private func withTaptTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TaptTimeoutError()
        }
        guard let result = try await group.next() else { throw TaptTimeoutError() }
        group.cancelAll()
        return result
    }
}

private struct TaptTimeoutError: LocalizedError {
    var errorDescription: String? { "Timed out. Check your connection and try again." }
}

/// Add a beer Tapt doesn't have yet. It goes to our reviewers and lands in your
/// Cellar immediately; it joins the public catalog and Beer Market once approved.
/// Only what you type is saved, nothing is invented. This is how the catalog grows.
struct AddBeerView: View {
    let prefillName: String
    var onAdded: (BeerPick) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brewery = ""
    @State private var style = ""
    @State private var abv = ""
    @State private var saving = false
    @State private var error: String?

    private var canSubmit: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section("Beer") {
                    TextField("Name", text: $name).textInputAutocapitalization(.words)
                    TextField("Brewery (optional)", text: $brewery).textInputAutocapitalization(.words)
                }
                Section("Details (optional)") {
                    TextField("Style, e.g. IPA", text: $style).textInputAutocapitalization(.words)
                    TextField("ABV %", text: $abv).keyboardType(.decimalPad)
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
                Section {} footer: {
                    Text("New beers go to our reviewers. It is in your Cellar right away and joins the public catalog once approved. Only what you type is saved, nothing is invented.")
                }
            }
            .navigationTitle("Add a beer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Adding" : "Add") { add() }.disabled(!canSubmit)
                }
            }
            .onAppear { if name.isEmpty { name = prefillName } }
        }
    }

    private func add() {
        saving = true; error = nil
        let nm = name.trimmingCharacters(in: .whitespaces)
        let bw = brewery.trimmingCharacters(in: .whitespaces)
        let st = style.trimmingCharacters(in: .whitespaces)
        let abvVal = Double(abv.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        Task {
            do {
                let id = try await CheckinService.submitBeer(
                    name: nm, brewery: bw.isEmpty ? nil : bw,
                    style: st.isEmpty ? nil : st, abv: abvVal)
                let pick = BeerPick(id: id, name: nm, style: st.isEmpty ? nil : st,
                                    abv: abvVal, breweryName: bw, country: "")
                await MainActor.run { onAdded(pick) }
            } catch {
                await MainActor.run {
                    let d = error.localizedDescription
                    if d.contains("2 to 80") { self.error = "Beer name must be 2 to 80 characters." }
                    else if d.contains("too many") { self.error = "You have added a lot today. Try again tomorrow." }
                    else if d.contains("abv out of range") { self.error = "Enter an ABV between 0 and 100." }
                    else { self.error = "Could not add the beer. Check your connection and try again." }
                    saving = false
                }
            }
        }
    }
}

/// Log a Pour: pick a beer, rate it, save the check-in, then share the card.
struct LogPourView: View {
    /// When set, submitting UPDATES this existing check-in instead of logging a new pour.
    var updatingCheckinId: String? = nil
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    var onLogged: () -> Void

    @State private var beers: [CatalogBeer] = []
    @State private var venueResults: [VenueSearchResult] = []
    @State private var search = ""
    @State private var venueSearch = ""
    @State private var selected: BeerPick?
    @State private var selectedVenue: VenueSearchResult?
    // Starts unrated so Tapt never records an opinion the user did not express.
    @State private var rating: Double?
    @State private var flavorTags: Set<String> = []
    @State private var glassware: String?
    @State private var occasion: String?
    @State private var saving = false
    @State private var sharePour: PourCard?
    @State private var celebration: TaptCelebration?
    @State private var pendingShare: PourCard?
    @State private var errorMessage: String?
    @State private var loadingCatalog = false
    @State private var showAddBeer = false
    @State private var catalogError: String?
    @State private var loadingVenues = false
    @State private var venueError: String?

    private let tags = ["hoppy", "malty", "crisp", "fruity", "roasty", "sour", "sweet", "dry"]
    private let glasswareOptions = ["Pint", "Can", "Bottle", "Tulip", "Snifter", "Flight"]
    private let occasionOptions = ["home", "bar", "restaurant", "event", "sports", "other"]

    init(initialBeer: BeerPick? = nil, updatingCheckinId: String? = nil, onLogged: @escaping () -> Void = {}) {
        self.onLogged = onLogged
        self.updatingCheckinId = updatingCheckinId
        _selected = State(initialValue: initialBeer)
        _venueSearch = State(initialValue: initialBeer?.breweryName ?? "")
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
            .task(id: search) { await loadCatalog() }
            .task(id: venueSearchTaskKey) { await loadVenues() }
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
        .taptCelebration($celebration) {
            if let pour = pendingShare {
                pendingShare = nil
                sharePour = pour
            }
        }
    }

    private var picker: some View {
        Group {
            if loadingCatalog && beers.isEmpty {
                TaptSkeletonList(rows: 6).padding()
            } else if let catalogError, beers.isEmpty {
                TaptEmptyState(
                    icon: "wifi.exclamationmark",
                    title: "Catalog unavailable",
                    message: catalogError,
                    actionTitle: "Try again",
                    action: { Task { await loadCatalog() } }
                )
            } else if beers.isEmpty {
                VStack(spacing: 14) {
                    TaptEmptyState(
                        icon: "magnifyingglass",
                        title: "No beer found",
                        message: "We may not have this one yet. Add it to log it now and help build the catalog.",
                        actionTitle: nil
                    )
                    Button { showAddBeer = true } label: {
                        Label(search.trimmingCharacters(in: .whitespaces).isEmpty ? "Add a new beer" : "Add \"\(search)\"",
                              systemImage: "plus.circle.fill")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(Brand.malt)
                    }
                    .buttonStyle(.taptPress)
                    .padding(.horizontal)
                    .disabled(session.user == nil)
                    if session.user == nil {
                        Text("Sign in to add a beer.").font(.caption).foregroundStyle(Brand.muted)
                    }
                }
            } else {
                List {
                    if let catalogError {
                        Button {
                            Task { await loadCatalog() }
                        } label: {
                            Label(catalogError, systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.copper)
                        }
                    }

                    ForEach(beers) { beer in
                        Button {
                            selected = beer.pick
                            rating = nil
                            flavorTags = []
                            glassware = nil
                            occasion = nil
                            selectedVenue = nil
                            venueSearch = beer.breweryName
                        } label: {
                            HStack(spacing: 10) {
                                BeerThumb(imageUrl: beer.imageUrl, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(beer.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                                    Text("\(beer.breweryName)  \(beer.style ?? "")").font(.caption).foregroundStyle(Brand.muted)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search beers")
        .sheet(isPresented: $showAddBeer) {
            AddBeerView(prefillName: search.trimmingCharacters(in: .whitespaces)) { pick in
                showAddBeer = false
                selected = pick
                rating = nil; flavorTags = []; glassware = nil; occasion = nil
                selectedVenue = nil
                venueSearch = pick.breweryName
            }
        }
    }

    private func rate(_ beer: BeerPick) -> some View {
        ScrollView {
            VStack(spacing: 18) {
            Text(beer.name).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Brand.text).multilineTextAlignment(.center)
            Text("\(beer.breweryName)  \(beer.style ?? "")").foregroundStyle(Brand.muted)
            Text("Your rating")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Brand.text)
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { rating = Double(i) }
                    } label: {
                        Image(systemName: Double(i) <= (rating ?? 0) ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(Brand.gold)
                            .frame(width: 40, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    .accessibilityAddTraits(rating == Double(i) ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            section("Flavor notes") {
                chipWrap(tags, selection: $flavorTags)
            }
            section("Glass (optional)") {
                pickerRow(glasswareOptions, selection: $glassware)
            }
            section("Occasion (optional)") {
                pickerRow(occasionOptions, selection: $occasion)
            }
            section("Brewery or taproom") {
                venuePicker(for: beer)
            }
            Button(saving ? "Saving..." : (rating != nil ? "Log it" : "Tap a star to rate it")) { save(beer) }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(rating != nil ? Brand.gold : Brand.haze, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(rating != nil ? Brand.malt : Brand.muted)
                // A rating is the one thing a pour means; never invent one.
                .disabled(saving || rating == nil)
                Text("Know your limits. Never drink and drive. 21+.")
                    .font(.caption2).foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
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
                        Text(selectedVenue.placeLine.isEmpty ? "Venue on Tapt" : selectedVenue.placeLine)
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

                if loadingVenues {
                    Label("Searching Tapt venues...", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else if let venueError {
                    Button {
                        Task { await loadVenues() }
                    } label: {
                        Label(venueError, systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.copper)
                    }
                    .buttonStyle(.plain)
                } else if venueSearch.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Text("Type at least two letters to search every Tapt venue.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else if venueResults.isEmpty {
                    Text("No venue match yet. You can still log the pour.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(venueResults.prefix(8)) { venue in
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

    private func venueRow(_ venue: VenueSearchResult) -> some View {
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
                Text(venue.placeLine.isEmpty ? "Venue on Tapt" : venue.placeLine)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.muted)
        }
        .padding(10)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Brand.malt.opacity(0.08), lineWidth: 1))
    }

    private var venueSearchTaskKey: String {
        [selected?.id, selectedVenue?.venueId, venueSearch]
            .compactMap { $0 }
            .joined(separator: "|")
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

    private func pickerRow(_ items: [String], selection: Binding<String?>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let on = selection.wrappedValue == item
                    Button { selection.wrappedValue = on ? nil : item } label: {
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
        guard let rating else {
            errorMessage = "Choose a rating before logging this pour."
            return
        }
        guard let uid = session.user?.id else {
            // Do NOT tear the session down here: endGuestSession() swapped the app
            // root to SignInView and killed this sheet before the alert could show,
            // which read as "Log it does nothing". Just surface the error.
            errorMessage = "Sign in to log this pour and add it to your Cellar."
            return
        }
        saving = true
        let tags = Array(flavorTags).sorted()
        let glass = glassware
        let occ = occasion
        let venueId = selectedVenue?.venueId
        Task {
            do {
                // Timeout-guarded so a hung write can never wedge "Saving…" silently.
                // Coming from a one-tap log, this UPDATES that same check-in;
                // a fresh entry logs a new pour.
                let updatingId = updatingCheckinId
                try await withTaptTimeout(seconds: 20) {
                    if let updatingId {
                        try await CheckinService.updateDetails(
                            checkinId: updatingId,
                            rating: rating,
                            flavorTags: tags,
                            glassware: glass,
                            occasion: occ
                        )
                    } else {
                        _ = try await CheckinService.log(
                            beer: beer,
                            userId: uid,
                            rating: rating,
                            flavorTags: tags,
                            glassware: glass,
                            occasion: occ,
                            venueId: venueId
                        )
                    }
                }
                await MainActor.run {
                    saving = false
                    // Leave the rate form immediately: a stale form behind the
                    // share sheet re-armed "Log it" and a second tap wrote a
                    // duplicate check-in (invented activity in the user's record).
                    selected = nil
                    onLogged()
                    // Stash the share card, then play the pour-to-passport-stamp
                    // celebration; the share sheet opens when it finishes.
                    pendingShare = PourCard(
                        beer: beer.name, brewery: beer.breweryName, style: beer.style ?? "",
                        score: Int(rating / 5 * 100), user: "you",
                        abv: beer.abv.map { String(format: "%.1f%%", $0) },
                        place: selectedVenue.map { sharePlace($0) },
                        beerId: beer.id, rating: Int(rating.rounded()), country: beer.country
                    )
                    celebration = .pourLogged(
                        beer: beer.name,
                        rating: rating,
                        place: selectedVenue.map { sharePlace($0) }
                    )
                }
            } catch {
                await MainActor.run {
                    saving = false
                    errorMessage = "Could not save the pour: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func loadCatalog() async {
        loadingCatalog = true
        defer { loadingCatalog = false }
        if !search.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        if Task.isCancelled {
            return
        }
        do {
            beers = try await CheckinService.catalog(query: search)
            catalogError = nil
        } catch is CancellationError {
            return
        } catch {
            catalogError = "The beer catalog could not be loaded. Check your connection and try again."
        }
    }

    @MainActor
    private func loadVenues() async {
        guard selected != nil else {
            venueResults = []
            venueError = nil
            loadingVenues = false
            return
        }
        guard selectedVenue == nil else {
            loadingVenues = false
            return
        }
        let term = venueSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            venueResults = []
            venueError = nil
            loadingVenues = false
            return
        }

        loadingVenues = true
        venueError = nil
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do {
            let results = try await PartnerService.searchVenues(term, limit: 20)
            guard !Task.isCancelled else { return }
            venueResults = results
        } catch is CancellationError {
            return
        } catch {
            venueError = "Venue search is unavailable. Tap to retry."
        }
        loadingVenues = false
    }

    private func sharePlace(_ venue: VenueSearchResult) -> String {
        venue.placeLine.isEmpty ? venue.name : "\(venue.name), \(venue.placeLine)"
    }
}
