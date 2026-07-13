import MapKit
import XCTest
@testable import Tapt

final class VenueMapSamplerTests: XCTestCase {
    func testSamplerCapsPinsToOnePerViewportCell() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        )
        let venues = (0..<100).map { index in
            venue(
                id: "venue-\(index)",
                latitude: Double(index % 10) - 4.5,
                longitude: Double(index / 10) - 4.5
            )
        }

        let sampled = VenueMapSampler.sample(venues, in: region, columns: 8, rows: 5)

        XCTAssertLessThanOrEqual(sampled.count, 40)
        XCTAssertEqual(Set(sampled.map(\.id)).count, sampled.count)
    }

    func testSamplerExcludesVenuesOutsideViewport() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40, longitude: -100),
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 30)
        )
        let inside = venue(id: "inside", latitude: 39, longitude: -98)
        let outside = venue(id: "outside", latitude: 52, longitude: -98)

        let sampled = VenueMapSampler.sample([outside, inside], in: region)

        XCTAssertEqual(sampled.map(\.id), ["inside"])
    }

    func testVenueTypesUseConsumerLabels() {
        XCTAssertEqual(venue(id: "micro", type: "micro").typeLabel, "Craft brewery")
        XCTAssertEqual(venue(id: "garden", type: "beer_garden").typeLabel, "Beer garden")
        XCTAssertEqual(venue(id: "custom", type: "cocktail_lounge").typeLabel, "Cocktail Lounge")
    }

    private func venue(
        id: String,
        latitude: Double = 0,
        longitude: Double = 0,
        type: String? = "brewery"
    ) -> BreweryMapVenue {
        BreweryMapVenue(
            venueId: id,
            name: id,
            city: nil,
            region: nil,
            country: nil,
            latitude: latitude,
            longitude: longitude,
            sourceLabel: nil,
            heatScore: 0,
            updatedAt: nil,
            breweryType: type,
            websiteURL: nil
        )
    }
}
