import SwiftUI
import MapKit

/// A local map of nearby breweries and beer spots from Apple POI.
/// Our own tap-list + check-in data layers on top once check-ins exist.
struct NearYouView: View {
    @AppStorage("locationConsent") private var locationConsent = true
    @State private var location = LocationManager()
    @State private var camera: MapCameraPosition = .automatic
    @State private var breweries: [MKMapItem] = []
    @State private var taptVenues: [BreweryMapVenue] = []
    @State private var loading = false
    @State private var radarLoading = false

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
                        Marker(item.name ?? "Brewery", systemImage: "mug.fill",
                               coordinate: item.placemark.coordinate)
                            .tint(Brand.gold)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .including([.brewery, .nightlife, .winery])))
                .frame(height: 320)

                List {
                    if !taptVenues.isEmpty {
                        Section {
                            ForEach(taptVenues.prefix(60)) { venue in
                                Button { focus(venue) } label: { taptRow(venue) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Tapt brewery radar")
                        } footer: {
                            Text("Seeded from Tapt's license-safe brewery map layer. Local Apple results appear below when location is on.")
                        }
                    } else if radarLoading {
                        Label("Loading Tapt brewery radar...", systemImage: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(Brand.muted)
                    }

                    if !locationConsent {
                        Text("Location is off in your Tapt privacy choices.")
                            .foregroundStyle(Brand.muted)
                    } else if !location.authorized {
                        Button {
                            location.request()
                        } label: {
                            Label("Turn on location to find breweries near you", systemImage: "location.fill")
                                .foregroundStyle(Brand.copper)
                        }
                    } else if loading {
                        Label("Finding breweries near you...", systemImage: "hourglass")
                            .foregroundStyle(Brand.muted)
                    } else if breweries.isEmpty {
                        Text("No breweries found nearby yet.").foregroundStyle(Brand.muted)
                    } else {
                        ForEach(breweries, id: \.self) { item in
                            Button { focus(item) } label: { row(item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Breweries Near You")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadTaptRadar()
                if locationConsent { location.request() }
            }
            .onChange(of: location.location) { _, loc in
                if let loc, breweries.isEmpty { search(near: loc.coordinate) }
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
                Text(item.name ?? "Brewery").font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text)
                if let city = item.placemark.locality {
                    Text(city).font(.subheadline).foregroundStyle(Brand.muted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Brand.muted)
        }
        .padding(.vertical, 4)
    }

    private func taptRow(_ venue: BreweryMapVenue) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Brand.malt)
                .frame(width: 40, height: 40)
                .background(Brand.hop, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name).font(.system(.headline, design: .rounded)).foregroundStyle(Brand.text).lineLimit(1)
                Text(venue.subtitle.isEmpty ? "Tapt brewery map" : venue.subtitle)
                    .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer()
            Text("\(venue.heatScore)")
                .font(.system(.caption, design: .rounded).weight(.bold))
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
            let venues = try await WorldBeerService.breweryMap(limit: 200)
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

    private func search(near coord: CLLocationCoordinate2D) {
        loading = true
        let request = MKLocalPointsOfInterestRequest(center: coord, radius: 8000)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.brewery, .nightlife, .winery])
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
