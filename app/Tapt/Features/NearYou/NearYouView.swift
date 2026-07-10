import SwiftUI
import MapKit

/// A local map of nearby beer spots from Tapt, Apple, and live local search.
/// Includes breweries, pubs, bars, taprooms, beer gardens, and restaurants with beer energy.
struct NearYouView: View {
    @AppStorage("locationConsent") private var locationConsent = true
    @State private var location = LocationManager()
    @State private var camera: MapCameraPosition = .automatic
    @State private var breweries: [MKMapItem] = []
    @State private var taptVenues: [BreweryMapVenue] = []
    @State private var loading = false
    @State private var radarLoading = false
    @State private var radarFilter: RadarFilter = .all
    @State private var searchText = ""
    @State private var nearLoaded = false

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

    private var radarSummary: String {
        let countries = Set(taptVenues.compactMap(\.country).filter { !$0.isEmpty }).count
        let states = Set(taptVenues.filter { $0.country == "United States" }.compactMap(\.region).filter { !$0.isEmpty }).count
        return "\(taptVenues.count) beer spots • \(states) states • \(countries) countries"
    }

    private var spotlightVenue: BreweryMapVenue? {
        visibleTaptVenues.first ?? taptVenues.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(taptVenues) { venue in
                        Marker(venue.name, systemImage: "mappin.and.ellipse", coordinate: venue.coordinate)
                            .tint(Brand.hop)
                    }
                    ForEach(breweries, id: \.self) { item in
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
                    } else if breweries.isEmpty {
                        Text("No beer spots found nearby yet.").foregroundStyle(Brand.muted)
                    } else {
                        ForEach(breweries, id: \.self) { item in
                            Button { focus(item) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
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
                    Task { await loadNearbyRadar(loc.coordinate) }
                }
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
                Image(systemName: "megaphone.fill")
                    .foregroundStyle(Brand.malt)
                    .frame(width: 42, height: 42)
                    .background(Brand.gold, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local beer spotlight")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.copper)
                    Text(venue.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    Text(venue.subtitle.isEmpty ? "Fresh taps, events, and game nights nearby" : venue.subtitle)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("SPOT")
                    .font(.system(.caption2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Brand.malt)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Brand.hop.opacity(0.75), in: Capsule())
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
            if location.location == nil, let first = venues.first {
                camera = .region(MKCoordinateRegion(center: first.coordinate,
                                                    latitudinalMeters: 4_500_000,
                                                    longitudinalMeters: 4_500_000))
            }
        } catch {
            taptVenues = []
        }
    }

    /// Once we know where the user is, swap the global sample for a
    /// distance-ordered radar around them (keeps a global tail for browsing).
    private func loadNearbyRadar(_ coord: CLLocationCoordinate2D) async {
        guard let nearby = try? await WorldBeerService.breweryMapNear(
            latitude: coord.latitude, longitude: coord.longitude, km: 80, limit: 250
        ), !nearby.isEmpty else { return }
        let nearbyIds = Set(nearby.map(\.venueId))
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
