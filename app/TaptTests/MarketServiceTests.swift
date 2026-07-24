import XCTest
@testable import Tapt

final class MarketServiceTests: XCTestCase {
    func testPulseCombinesOnlyRealActions() {
        let pulse = makePulse(votes24h: 3, pours24h: 4, votes7d: 8, pours7d: 5)

        XCTAssertEqual(pulse.communityActions24h, 7)
        XCTAssertEqual(pulse.communityActions7d, 13)
        XCTAssertFalse(pulse.isQuiet)
    }

    func testPulseIsQuietWithNoActions() {
        XCTAssertTrue(makePulse().isQuiet)
    }

    func testPulseFreshnessUsesServerTimestamp() {
        let pulse = makePulse(computedAt: "2026-07-24T16:00:00.000Z")

        XCTAssertTrue(pulse.isFresh(at: date("2026-07-24T16:30:00Z")))
        XCTAssertFalse(pulse.isFresh(at: date("2026-07-24T17:06:00Z")))
    }

    func testEveryMarketSortHasSpecificBoardAndEmptyCopy() {
        for sort in MarketSort.allCases {
            XCTAssertFalse(sort.boardTitle.isEmpty)
            XCTAssertFalse(sort.boardSubtitle.isEmpty)
            XCTAssertFalse(sort.emptyTitle.isEmpty)
            XCTAssertFalse(sort.emptyMessage.isEmpty)
        }
    }

    func testOnlyDirectionalBoardsLeadWithMovement() {
        XCTAssertTrue(MarketSort.movers.leadsWithMovement)
        XCTAssertTrue(MarketSort.gainers.leadsWithMovement)
        XCTAssertTrue(MarketSort.losers.leadsWithMovement)
        XCTAssertFalse(MarketSort.active.leadsWithMovement)
        XCTAssertFalse(MarketSort.season.leadsWithMovement)
        XCTAssertFalse(MarketSort.top.leadsWithMovement)
        XCTAssertFalse(MarketSort.standing.leadsWithMovement)
    }

    func testEveryFilteredBoardFallsBackToRealStandingWhenEmpty() {
        for sort in MarketSort.allCases where sort != .standing {
            XCTAssertTrue(sort.showsStandingFallbackWhenEmpty)
        }
        XCTAssertFalse(MarketSort.standing.showsStandingFallbackWhenEmpty)
    }

    func testMarketLabelsDecodeImportedCatalogEntities() {
        let beer = MarketBeer(
            beerId: UUID().uuidString,
            symbol: "YOUN",
            name: "Young&#039;s &amp; Co.",
            brewery: "L&amp;#39;Abbaye",
            style: "Porter &amp; Stout",
            country: nil,
            imageUrl: nil,
            isNaLow: false,
            net: 10,
            votes: 0,
            change: 1,
            volume: 0,
            ups: 0,
            downs: 0,
            spark: [9, 10],
            reason: nil,
            seasonFit: 0,
            heat: 1
        )

        XCTAssertEqual(beer.displayName, "Young's & Co.")
        XCTAssertEqual(beer.displayBrewery, "L'Abbaye")
        XCTAssertEqual(beer.displayStyle, "Porter & Stout")
    }

    func testFlatScoreHidesIncomparableHistoricalSpark() {
        let beer = makeBeer(change: 0, spark: [100, 66])

        XCTAssertEqual(beer.windowTrend, 0)
        XCTAssertEqual(beer.displaySpark, [66])
    }

    @MainActor
    func testSparklineUsesOnlyRealSnapshotVertices() {
        let values = [20.0, 24.0, 21.0, 25.0]
        let points = Sparkline.points(for: values, in: CGSize(width: 90, height: 30))

        XCTAssertEqual(points.count, values.count)
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 90)
    }

    private func makePulse(
        computedAt: String? = "2026-07-24T16:00:00Z",
        votes24h: Int = 0,
        pours24h: Int = 0,
        votes7d: Int = 0,
        pours7d: Int = 0
    ) -> MarketPulse {
        MarketPulse(
            computedAt: computedAt,
            tracked: 4_891,
            moving24h: 112,
            gainers24h: 0,
            sliders24h: 112,
            active24h: votes24h + pours24h,
            votes24h: votes24h,
            pours24h: pours24h,
            votes7d: votes7d,
            pours7d: pours7d
        )
    }

    private func makeBeer(change: Int, spark: [Double]) -> MarketBeer {
        MarketBeer(
            beerId: UUID().uuidString,
            symbol: "TEST",
            name: "Test Beer",
            brewery: "Test Brewery",
            style: "Lager",
            country: nil,
            imageUrl: nil,
            isNaLow: false,
            net: Int(spark.last ?? 1),
            votes: 0,
            change: change,
            volume: 0,
            ups: 0,
            downs: 0,
            spark: spark,
            reason: nil,
            seasonFit: 0,
            heat: 0
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
