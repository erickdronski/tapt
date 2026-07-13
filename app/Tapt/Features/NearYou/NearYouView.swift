import SwiftUI
import MapKit
import UIKit

/// A local map of nearby beer spots from Tapt, Apple, and live local search.
/// Includes breweries, pubs, bars, taprooms, beer gardens, and restaurants with beer energy.
struct NearYouView: View {
    @AppStorage("locationConsent") private var locationConsent = false
    @AppStorage("homeRegion") private var homeRegion = "Global"
    @State private var location = LocationManager()
    // Start on a real region (continental US) -- never `.automatic`, which fit all
    // ~800 global pins and dumped the map in the middle of the Pacific. This renders
    // a real map instantly; geocode + GPS then zoom it in to home / near you.
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.83, longitude: -98.58),
                           span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 46)))
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

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return filtered
        }

        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.filter { venue in
            [venue.name, venue.city, venue.region, venue.country, venue.breweryType]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(term) }
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
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(visibleTaptVenues) { venue in
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
                .mapStyle(.standard(pointsOfInterest: .including([.brewery, .nightlife, .restaurant, .winery])))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .frame(height: 320)

                List {
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
                                Button { focus(venue) } label: { taptRow(venue) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Tapt beer radar")
                        } footer: {
                            Text("Seeded from Tapt's license-safe venue map layer. Local pubs, bars, taprooms, and beer gardens appear below when location is on.")
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
            }
            .navigationTitle("Beer Near You")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search brewery, pub, city, state")
            .task {
                await loadTaptRadar()
                if locationConsent { location.request() }
            }
            .onChange(of: location.location) { _, loc in
                guard let loc else { return }
                if breweries.isEmpty { search(near: loc.coordinate) }
                if !nearLoaded {
                    nearLoaded = true
                    withAnimation {
                        camera = .region(MKCoordinateRegion(center: loc.coordinate,
                                                            latitudinalMeters: 24_000, longitudinalMeters: 24_000))
                    }
                    Task {
                        await loadNearbyRadar(loc.coordinate, establishesLocalContext: true)
                    }
                }
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
                Text("\(venue.typeLabel.capitalized) • \(venue.sourceLabel ?? "Tapt map")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(venue.sourceBadge)
                .font(.system(.caption2, design: .rounded).weight(.heavy))
                .foregroundStyle(Brand.malt)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Brand.gold, in: Capsule())
        }
        .padding(.vertical, 4)
    }

    private func focus(_ item: MKMapItem) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                                                latitudinalMeters: 1200, longitudinalMeters: 1200))
        }
    }

    private func focus(_ venue: BreweryMapVenue) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: venue.coordinate,
                                                latitudinalMeters: 2400, longitudinalMeters: 2400))
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
            camera = .region(MKCoordinateRegion(center: coord,
                                                latitudinalMeters: 60_000, longitudinalMeters: 60_000))
            await loadNearbyRadar(coord, establishesLocalContext: false)
            return
        }
        // Geocode failed: use only a venue that actually matches the saved
        // region. Otherwise keep the stable continental default.
        if let home = venues.first(where: {
            $0.region?.localizedCaseInsensitiveCompare(region) == .orderedSame
        }) {
            camera = .region(MKCoordinateRegion(center: home.coordinate,
                                                latitudinalMeters: 200_000, longitudinalMeters: 200_000))
        }
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
                camera = .region(MKCoordinateRegion(center: coord,
                                                    latitudinalMeters: 6000, longitudinalMeters: 6000))
            }
        }
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
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "mug.fill")
                            .font(.title2).foregroundStyle(Brand.malt)
                            .frame(width: 54, height: 54)
                            .background(Brand.gold, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(venue.name)
                                .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(Brand.text)
                            Text(venue.typeLabel.capitalized)
                                .font(.caption.weight(.semibold)).foregroundStyle(Brand.copper)
                        }
                        Spacer(minLength: 0)
                    }
                    if !venue.subtitle.isEmpty {
                        Label(venue.subtitle, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(Brand.muted)
                    }
                    HStack(spacing: 10) {
                        Button { openInMaps() } label: {
                            Label("Directions", systemImage: "location.fill")
                                .font(.subheadline.weight(.bold)).foregroundStyle(Brand.malt)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Brand.gold, in: Capsule())
                        }.buttonStyle(.plain)
                        if let site = venue.websiteURL, !site.isEmpty,
                           let url = URL(string: site.hasPrefix("http") ? site : "https://" + site) {
                            Link(destination: url) {
                                Label("Website", systemImage: "safari")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(Brand.text)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .overlay(Capsule().stroke(Brand.malt.opacity(0.2)))
                            }
                        }
                    }
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
                        Text("No live tap list yet. If you run this spot, claim it free on Tapt to publish your menu here.")
                            .font(.caption).foregroundStyle(Brand.muted).padding(.top, 4)
                    }
                }
                .padding()
            }
            .background(Brand.background)
            .navigationTitle("Beer spot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .task {
            guard !loaded else { return }
            menu = (try? await VenueMenuService.menu(venueId: venue.venueId)) ?? []
            loaded = true
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: venue.coordinate))
        item.name = venue.name
        item.openInMaps()
    }
}
