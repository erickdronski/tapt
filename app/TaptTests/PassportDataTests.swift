import XCTest
@testable import Tapt

final class PassportDataTests: XCTestCase {
    func testUniqueBeerCountDeduplicatesRepeatPours() {
        let checkins = [
            makeCheckin(id: "one", beerId: "beer-a", name: "Pils", brewery: "Tapt"),
            makeCheckin(id: "two", beerId: "beer-a", name: "Pils", brewery: "Tapt"),
            makeCheckin(id: "three", beerId: "beer-b", name: "Stout", brewery: "Tapt")
        ]

        XCTAssertEqual(PassportProgress.uniqueBeerCount(in: checkins), 2)
    }

    func testUniqueBeerCountUsesNormalizedFallbackIdentity() {
        let checkins = [
            makeCheckin(id: "one", beerId: nil, name: "House Lager", brewery: "Main Street"),
            makeCheckin(id: "two", beerId: nil, name: "HOUSE LAGER", brewery: "MAIN STREET")
        ]

        XCTAssertEqual(PassportProgress.uniqueBeerCount(in: checkins), 1)
    }

    func testUniqueBeerCountGroupsPackageLevelCatalogRecords() {
        let checkins = [
            makeCheckin(id: "one", beerId: "single-bottle", name: "Pilsner", brewery: "Old Town"),
            makeCheckin(id: "two", beerId: "six-pack", name: "Pilsner", brewery: "Old Town")
        ]

        XCTAssertEqual(PassportProgress.uniqueBeerCount(in: checkins), 1)
    }

    func testExplorationBadgesUseDistinctBeers() throws {
        let firstFlight = try XCTUnwrap(PassportData.badges.first { $0.id == "flight" })
        let centuryCellar = try XCTUnwrap(PassportData.badges.first { $0.id == "century" })

        XCTAssertFalse(firstFlight.earned(PassportStats(pours: 20, beers: 4, styles: 1, states: 0, countries: 0)))
        XCTAssertTrue(firstFlight.earned(PassportStats(pours: 5, beers: 5, styles: 1, states: 0, countries: 0)))
        XCTAssertFalse(centuryCellar.earned(PassportStats(pours: 150, beers: 99, styles: 10, states: 5, countries: 3)))
        XCTAssertTrue(centuryCellar.earned(PassportStats(pours: 100, beers: 100, styles: 10, states: 5, countries: 3)))
    }

    private func makeCheckin(
        id: String,
        beerId: String?,
        name: String,
        brewery: String
    ) -> MyCheckin {
        MyCheckin(
            id: id,
            beerId: beerId,
            rating: 4,
            style: "Lager",
            eventTs: "2026-07-12T12:00:00Z",
            beer: .init(name: name, brewery: .init(name: brewery, country: "United States")),
            venue: nil
        )
    }
}
