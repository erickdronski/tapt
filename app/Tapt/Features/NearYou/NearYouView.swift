import SwiftUI
import MapKit

/// "On Tap Near You": a live map of nearby breweries (Apple POI), the signature surface.
/// Our own tap-list + check-in data layers on top once check-ins exist.
struct NearYouView: View {
    @State private var location = LocationManager()
    @State private var camera: MapCameraPosition = .automatic
    @State private var breweries: [MKMapItem] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(breweries, id: \.self) { item in
                        Marker(item.name ?? "Brewery", systemImage: "mug.fill",
                               coordinate: item.placemark.coordinate)
                            .tint(Brand.gold)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .including([.brewery, .nightlife, .winery])))
                .frame(height: 320)

                List {
                    if !location.authorized {
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
            .navigationTitle("On Tap Near You")
            .navigationBarTitleDisplayMode(.inline)
            .task { location.request() }
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

    private func focus(_ item: MKMapItem) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                                                latitudinalMeters: 1200, longitudinalMeters: 1200))
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
