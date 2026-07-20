import SwiftUI
import MapKit
import UIKit

/// A local map of nearby beer spots from Tapt, Apple, and live local search.
/// Includes breweries, pubs, bars, taprooms, beer gardens, and restaurants with beer energy.
struct NearYouView: View {
    @AppStorage("locationConsent") private var locationConsent = false
    @AppStorage("homeRegion") private var homeRegion = "Global"
    @State private var location = LocationManager()
    @State private var camera: MapCameraPosition
    @State private var mapRegion: MKCoordinateRegion
    @State private var breweries: [MKMapItem] = []
    @State private var taptVenues: [BreweryMapVenue] = []
    @State private var loading = false
    @State private var radarLoading = false
    @State private var radarFilter: RadarFilter = .all
    @State private var searchText = ""
    @State private var nearLoaded = false
    @State private var nearbyVenueIds = Set<String>()
    @State private var selectedVenue: BreweryMapVenue?
    @State private var radarError: String?
    @State private var sheetDetent: RadarSheetDetent = .half

    init() {
        // Start on a stable continental view. GPS or the saved home region can
        // replace it once that context is available.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.83, longitude: -98.58),
            span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 46)
        )
        _camera = State(initialValue: .region(region))
        _mapRegion = State(initialValue: region)
    }

    private var visibleTaptVenues: [BreweryMapVenue] {
        let filtered = taptVenues.filter { venue in
            switch radarFilter {
            case .all:
                return true
            case .unitedStates:
                return venue.country == "United States"
            case .world:
                return venue.country != "United States"
            }
        }

        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = term.isEmpty ? filtered : filtered.filter { venue in
            [venue.name, venue.city, venue.region, venue.country, venue.breweryType]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
        // Local-first: once we know where the user is, sort the whole radar by
        // distance so their nearby spots lead and far-away global venues sink.
        guard let here = location.location else { return matched }
        return matched.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)
                < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
        }
    }

    private var visibleAppleVenues: [MKMapItem] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return breweries.filter { item in
            let isUS = item.placemark.isoCountryCode == "US"
                || item.placemark.country == "United States"
            let inRegion: Bool
            switch radarFilter {
            case .all: inRegion = true
            case .unitedStates: inRegion = isUS
            case .world: inRegion = !isUS
            }
            guard inRegion, !term.isEmpty else { return inRegion }
            return [item.name, item.placemark.locality, item.placemark.administrativeArea, item.placemark.country]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    private var visibleMapVenues: [BreweryMapVenue] {
        VenueMapSampler.sample(visibleTaptVenues, in: mapRegion)
    }

    private var radarSummary: String {
        let countries = Set(visibleTaptVenues.compactMap(\.country).filter { !$0.isEmpty }).count
        let states = Set(visibleTaptVenues.filter { $0.country == "United States" }.compactMap(\.region).filter { !$0.isEmpty }).count
        return "\(visibleTaptVenues.count) beer spots • \(states) states • \(countries) countries"
    }

    private var spotlightVenue: BreweryMapVenue? {
        guard locationConsent, location.authorized else { return nil }
        return visibleTaptVenues.first { nearbyVenueIds.contains($0.venueId) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(visibleMapVenues) { venue in
                        Annotation(venue.name, coordinate: venue.coordinate) {
                            Button { selectedVenue = venue } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Brand.hop)
                                    .padding(3)
                                    .background(Circle().fill(.white))
                                    .shadow(radius: 1.5)
                            }
                            .buttonStyle(.plain)
                        }
                        .annotationTitles(.hidden)
                    }
                    ForEach(visibleAppleVenues, id: \.self) { item in
                        Marker(item.name ?? "Beer spot", systemImage: "mug.fill",
                               coordinate: item.placemark.coordinate)
                            .tint(Brand.gold)
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    mapRegion = context.region
                }
                .mapStyle(.standard(pointsOfInterest: .including([.brewery, .nightlife, .restaurant, .winery])))
                .mapControls {
                    MapCompass()
                }
                .ignoresSafeArea(edges: .top)

                RadarSheet(detent: $sheetDetent) {
                    radarList
                }
            }
            .overlay(alignment: .topTrailing) { locateButton }
            .navigationTitle("Beer Near You")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Only ask for location if the drinker turned "Nearby beer spots"
                // ON in their own privacy settings. The OS permission is not
                // consent to this feature: someone who granted location for the
                // scanner and left this toggle off must not be located here.
                if locationConsent, !location.deniedOrRestricted { location.request() }
                await loadTaptRadar()
                // If a GPS fix is already cached when we arrive, onChange never
                // fires, so center + pull the local radar here too.
                if let loc = location.location { await applyUserLocation(loc) }
            }
            // Deliberately NOT mirroring location.authorized into locationConsent:
            // granting the iOS prompt is not the same as opting in to nearby
            // spots, and auto-writing it silently overwrote the drinker's own
            // recorded privacy choice (and POSTed a consent grant they never gave).
            // The opt-in row below is the only thing that sets locationConsent.
            .onChange(of: location.location) { _, loc in
                guard let loc else { return }
                Task { await applyUserLocation(loc) }
            }
            .onChange(of: locationConsent) { _, enabled in
                if enabled {
                    location.request()
                } else {
                    location.stop()
                    breweries = []
                    nearLoaded = false
                    nearbyVenueIds = []
                }
            }
            .sheet(item: $selectedVenue) { venue in
                VenueDetailSheet(venue: venue)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// The nearby list that lives inside the draggable sheet. Content is the
    /// same radar the map used to stack beneath it: featured partners, the
    /// spotlight, the Tapt beer radar, and the Apple fallback.
    private var radarList: some View {
        List {
            // Paid-visibility surface: local partners who pay for reach. With no
            // paid rows yet it shows an honest "feature your spot" invite, never a fake ad.
            Section {
                FeaturedPartnersRail()
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)

            if let radarError {
                Button {
                    Task { await loadTaptRadar() }
                } label: {
                    Label(radarError, systemImage: "arrow.clockwise")
                        .foregroundStyle(Brand.copper)
                }
            }

            if let spotlightVenue {
                Section {
                    spotlight(spotlightVenue)
                }
            }

            if !taptVenues.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        radarSearchField
                        Text(radarSummary)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Brand.text)
                        Picker("Radar filter", selection: $radarFilter) {
                            ForEach(RadarFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    if visibleTaptVenues.isEmpty {
                        Text("No beer spots match that search yet.")
                            .foregroundStyle(Brand.muted)
                    }

                    ForEach(visibleTaptVenues.prefix(120)) { venue in
                        Button { selectedVenue = venue } label: { taptRow(venue) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Tapt beer radar")
                } footer: {
                    Text("Explore breweries, pubs, bars, taprooms, and beer gardens. Turn on location to bring the closest places to the top.")
                }
            } else if radarLoading {
                Label("Loading Tapt beer radar...", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Brand.muted)
            }

            if !locationConsent {
                Text("Location is off in your Tapt privacy choices.")
                    .foregroundStyle(Brand.muted)
            } else if location.deniedOrRestricted {
                Button {
                    guard let settings = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(settings)
                } label: {
                    Label("Open Settings to allow nearby beer spots", systemImage: "gear")
                        .foregroundStyle(Brand.copper)
                }
            } else if !location.authorized {
                Button {
                    location.request()
                } label: {
                    Label("Turn on location to find beer spots near you", systemImage: "location.fill")
                        .foregroundStyle(Brand.copper)
                }
            } else if loading {
                Label("Finding pubs, bars, taprooms, and beer gardens near you...", systemImage: "hourglass")
                    .foregroundStyle(Brand.muted)
            } else if visibleAppleVenues.isEmpty {
                Text("No beer spots found nearby yet.").foregroundStyle(Brand.muted)
            } else {
                ForEach(visibleAppleVenues, id: \.self) { item in
                    Button { focus(item) } label: { row(item) }
                        .buttonStyle(.plain)
                }
            }

            if let locationError = location.lastError {
                Text(locationError)
                    .font(.caption)
                    .foregroundStyle(Brand.copper)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: MKMapItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mug.fill")
                .foregroundStyle(Brand.malt)
                .frame(width: 40, height: 40)
                .background(Brand.gold, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Beer spot").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                if let city = item.placemark.locality {
                    Text(city).font(.subheadline).foregroundStyle(Brand.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Brand.muted)
        }
        .padding(.vertical, 4)
    }

    private func spotlight(_ venue: BreweryMapVenue) -> some View {
        Button { focus(venue) } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .foregroundStyle(Brand.malt)
                    .frame(width: 42, height: 42)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby beer spot")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.copper)
                    Text(venue.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    if !venue.subtitle.isEmpty {
                        Text(venue.subtitle)
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var radarSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Brand.muted)
            TextField("Search brewery, pub, city, or state", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Brand.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear venue search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.malt.opacity(0.10)))
    }

    private func taptRow(_ venue: BreweryMapVenue) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Brand.malt)
                .frame(width: 40, height: 40)
                .background(Brand.hop, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text(venue.subtitle.isEmpty ? "Tapt beer map" : venue.subtitle)
                    .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
                Text(venue.typeLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.muted.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private func focus(_ item: MKMapItem) {
        moveCamera(to: MKCoordinateRegion(
            center: item.placemark.coordinate,
            latitudinalMeters: 1200,
            longitudinalMeters: 1200
        ))
    }

    private func focus(_ venue: BreweryMapVenue) {
        moveCamera(to: MKCoordinateRegion(
            center: venue.coordinate,
            latitudinalMeters: 2400,
            longitudinalMeters: 2400
        ))
    }

    private func moveCamera(to region: MKCoordinateRegion) {
        mapRegion = region
        withAnimation {
            camera = .region(region)
        }
    }

    /// A reliably tappable "center on me" control. It lives in the safe area so
    /// the status bar never covers it, even though the map runs full-bleed under
    /// the bar. Tapping asks for permission when needed, then recenters.
    private var locateButton: some View {
        Button { centerOnUser() } label: {
            Image(systemName: location.authorized ? "location.fill" : "location")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(location.deniedOrRestricted ? Brand.muted : Brand.hop)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06)))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .accessibilityLabel("Center the map on my location")
    }

    /// Recenter on the user. Requests permission first when it has not been
    /// asked, routes to Settings if it was denied, and otherwise flies to the
    /// last known location (or kicks off an update if we do not have one yet).
    private func centerOnUser() {
        Haptic.tap()
        switch location.authorizationStatus {
        case .notDetermined:
            location.request()
        case .denied, .restricted:
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settings)
            }
        default:
            if let loc = location.location {
                moveCamera(to: MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 24_000,
                    longitudinalMeters: 24_000
                ))
            } else {
                location.request()
            }
        }
    }

    private func loadTaptRadar() async {
        radarLoading = true
        defer { radarLoading = false }
        do {
            let venues = try await WorldBeerService.breweryMap(limit: 800)
            taptVenues = venues
            // GPS not ready yet: center on the user's home region, never a random
            // global venue (which was dropping the map into Europe).
            if location.location == nil {
                await centerOnHomeRegion(fallback: venues)
            }
            radarError = nil
        } catch {
            radarError = "Beer radar could not refresh. Tap to try again."
        }
    }

    /// Center the map on the stored home region when GPS isn't available yet.
    private func centerOnHomeRegion(fallback venues: [BreweryMapVenue]) async {
        let region = homeRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !region.isEmpty,
              region.localizedCaseInsensitiveCompare("Global") != .orderedSame else {
            return
        }

        if let placemarks = try? await CLGeocoder().geocodeAddressString(region),
           let coord = placemarks.first?.location?.coordinate {
            moveCamera(to: MKCoordinateRegion(
                center: coord,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            ))
            await loadNearbyRadar(coord, establishesLocalContext: false)
            return
        }
        // Geocode failed: use only a venue that actually matches the saved
        // region. Otherwise keep the stable continental default.
        if let home = venues.first(where: {
            $0.region?.localizedCaseInsensitiveCompare(region) == .orderedSame
        }) {
            moveCamera(to: MKCoordinateRegion(
                center: home.coordinate,
                latitudinalMeters: 200_000,
                longitudinalMeters: 200_000
            ))
        }
    }

    /// Center on the user and pull in the dense local radar. Called from both the
    /// location onChange AND on appear, because onChange alone misses an already
    /// cached fix (which left the map continental and the list on far-away venues).
    private func applyUserLocation(_ loc: CLLocation) async {
        if breweries.isEmpty { search(near: loc.coordinate) }
        guard !nearLoaded else { return }
        nearLoaded = true
        moveCamera(to: MKCoordinateRegion(
            center: loc.coordinate,
            latitudinalMeters: 24_000,
            longitudinalMeters: 24_000
        ))
        await loadNearbyRadar(loc.coordinate, establishesLocalContext: true)
    }

    /// Once we know where the user is, swap the global sample for a
    /// distance-ordered radar around them (keeps a global tail for browsing).
    private func loadNearbyRadar(
        _ coord: CLLocationCoordinate2D,
        establishesLocalContext: Bool
    ) async {
        guard let nearby = try? await WorldBeerService.breweryMapNear(
            latitude: coord.latitude, longitude: coord.longitude, km: 80, limit: 250
        ), !nearby.isEmpty else {
            if establishesLocalContext { nearbyVenueIds = [] }
            return
        }
        let nearbyIds = Set(nearby.map(\.venueId))
        if establishesLocalContext { nearbyVenueIds = nearbyIds }
        let globalTail = taptVenues.filter { !nearbyIds.contains($0.venueId) }.prefix(350)
        taptVenues = nearby + Array(globalTail)
    }

    private func search(near coord: CLLocationCoordinate2D) {
        loading = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "brewery pub bar taproom beer garden"
        request.region = MKCoordinateRegion(center: coord, latitudinalMeters: 9000, longitudinalMeters: 9000)
        MKLocalSearch(request: request).start { response, _ in
            Task { @MainActor in
                loading = false
                breweries = response?.mapItems ?? []
                moveCamera(to: MKCoordinateRegion(
                    center: coord,
                    latitudinalMeters: 6000,
                    longitudinalMeters: 6000
                ))
            }
        }
    }
}

/// Keeps the map legible at every zoom level while the full result set remains
/// available in the list. One representative venue is rendered per viewport cell.
enum VenueMapSampler {
    static func sample(
        _ venues: [BreweryMapVenue],
        in region: MKCoordinateRegion,
        columns: Int = 8,
        rows: Int = 5
    ) -> [BreweryMapVenue] {
        guard columns > 0, rows > 0 else { return [] }

        let latitudeSpan = max(abs(region.span.latitudeDelta), 0.000_001)
        let longitudeSpan = min(max(abs(region.span.longitudeDelta), 0.000_001), 360)
        let halfLatitude = latitudeSpan / 2
        let halfLongitude = longitudeSpan / 2
        let minimumLatitude = region.center.latitude - halfLatitude
        var occupiedCells = Set<Int>()
        var sampled: [BreweryMapVenue] = []

        for venue in venues {
            guard abs(venue.latitude - region.center.latitude) <= halfLatitude else { continue }
            let longitudeOffset = normalizedLongitudeDelta(venue.longitude - region.center.longitude)
            guard longitudeSpan >= 359.999 || abs(longitudeOffset) <= halfLongitude else { continue }

            let latitudeProgress = (venue.latitude - minimumLatitude) / latitudeSpan
            let longitudeProgress = (longitudeOffset + halfLongitude) / longitudeSpan
            let row = min(rows - 1, max(0, Int(latitudeProgress * Double(rows))))
            let column = min(columns - 1, max(0, Int(longitudeProgress * Double(columns))))
            let cell = row * columns + column
            guard occupiedCells.insert(cell).inserted else { continue }
            sampled.append(venue)
        }
        return sampled
    }

    private static func normalizedLongitudeDelta(_ value: Double) -> Double {
        var delta = value.truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

private enum RadarFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unitedStates = "U.S."
    case world = "World"

    var id: String { rawValue }
}

/// Tapping a map pin opens this: the real details we have on a beer spot, plus its
/// live tap list when the venue is a claimed partner on Tapt.
private struct VenueDetailSheet: View {
    let venue: BreweryMapVenue
    @Environment(\.dismiss) private var dismiss
    @State private var menu: [VenueMenuRow] = []
    @State private var events: [VenueEvent] = []
    @State private var detail: VenueDetail?
    @State private var loaded = false

    private var glyph: String {
        let cat = (detail?.poiCategory ?? venue.breweryType ?? "").lowercased()
        if cat.contains("brewery") { return "building.2.fill" }
        if cat.contains("garden") { return "leaf.fill" }
        if cat.contains("taproom") { return "drop.fill" }
        return "mug.fill"
    }

    private var premiseLabel: String? {
        switch detail?.onOffPremise {
        case "on_premise": return "Serves on site"
        case "off_premise": return "Bottles to go"
        default: return nil
        }
    }

    private var addressLine: String? {
        let parts = [detail?.address, detail?.city, detail?.region, detail?.postalCode]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    venueMap
                    header
                    if let line = addressLine {
                        Label(line, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Brand.muted)
                    } else if !venue.subtitle.isEmpty {
                        Label(venue.subtitle, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Brand.muted)
                    }
                    if let p = premiseLabel {
                        Label(p, systemImage: "checkmark.circle").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
                    }
                    actionRow
                    if !events.isEmpty { eventsBlock }
                    menuBlock
                    if detail?.isClaimed == false { claimTile }
                    Text("Place details from OpenStreetMap, Overture, and Open Brewery DB.")
                        .font(.caption2).foregroundStyle(Brand.muted)
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Beer spot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            guard !loaded else { return }
            async let m = VenueMenuService.menu(venueId: venue.venueId)
            async let e = VenueMenuService.events(venueId: venue.venueId)
            async let d = VenueDetailService.detail(venueId: venue.venueId)
            menu = (try? await m) ?? []
            events = (try? await e) ?? []
            detail = try? await d
            loaded = true
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Group {
                if let logo = detail?.logoUrl, !logo.isEmpty, let u = URL(string: logo) {
                    AsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Image(systemName: glyph).font(.title2).foregroundStyle(Brand.malt) }
                    }
                } else {
                    Image(systemName: glyph).font(.title2).foregroundStyle(Brand.malt)
                }
            }
            .frame(width: 54, height: 54)
            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                HStack(spacing: 6) {
                    Text(venue.typeLabel).font(.caption.weight(.semibold)).foregroundStyle(Brand.copper)
                    if detail?.isClaimed == true {
                        Label("Claimed on Tapt", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.bold)).foregroundStyle(Brand.hop)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var venueMap: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: venue.coordinate, latitudinalMeters: 500, longitudinalMeters: 500))) {
            Annotation(venue.name, coordinate: venue.coordinate) {
                Image(systemName: glyph)
                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.malt)
                    .padding(8).background(Brand.gold, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
            .annotationTitles(.hidden)
        }
        .frame(height: 152)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button { openInMaps() } label: {
                Label("Directions", systemImage: "location.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.malt)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Brand.gold, in: Capsule())
            }.buttonStyle(.plain)
            if let phone = detail?.phone, !phone.isEmpty,
               let url = URL(string: "tel://" + phone.filter { $0.isNumber || $0 == "+" }) {
                Link(destination: url) {
                    Label("Call", systemImage: "phone.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .overlay(Capsule().stroke(Brand.malt.opacity(0.2)))
                }
            }
            if let site = (detail?.websiteUrl ?? venue.websiteURL), !site.isEmpty,
               let url = URL(string: site.hasPrefix("http") ? site : "https://" + site) {
                Link(destination: url) {
                    Label("Website", systemImage: "safari")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .overlay(Capsule().stroke(Brand.malt.opacity(0.2)))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var eventsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Happening here").font(.headline).foregroundStyle(Brand.text).padding(.top, 4)
            ForEach(events) { e in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar").font(.subheadline).foregroundStyle(Brand.copper).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                        Text([e.kindLabel, e.scheduleLabel].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Brand.muted)
                        if let d = e.details, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(Brand.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(11).background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder private var menuBlock: some View {
        if !menu.isEmpty {
            Text("On tap now").font(.headline).foregroundStyle(Brand.text).padding(.top, 4)
            ForEach(menu) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.beerName).font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                        Text([row.breweryName, row.style].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Brand.muted)
                    }
                    Spacer(minLength: 0)
                    if let p = row.priceText { Text(p).font(.subheadline.weight(.heavy)).foregroundStyle(Brand.copper) }
                }
                .padding(11).background(Brand.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        } else if loaded {
            Text("No live tap list yet.").font(.caption).foregroundStyle(Brand.muted).padding(.top, 4)
        }
    }

    // The claim entry the owner asked for: any venue on the map can be claimed by
    // the partner who runs it, which routes them into the free partner flow.
    private var claimTile: some View {
        NavigationLink { BreweriesHubView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").font(.title3).foregroundStyle(Brand.malt)
                    .frame(width: 40, height: 40).background(Brand.gold, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run this place?").font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                    Text("Claim it free to publish your tap list, add events, and see who is drinking here.")
                        .font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Brand.muted)
            }
            .padding(12).background(Brand.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.gold.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: venue.coordinate))
        item.name = venue.name
        item.openInMaps()
    }
}
