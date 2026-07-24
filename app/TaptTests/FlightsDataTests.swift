import XCTest
@testable import Tapt

final class FlightsDataTests: XCTestCase {
    func testFlightProgressMatchesStylesCaseInsensitively() throws {
        let quest = try XCTUnwrap(FlightsData.quests.first { $0.id == "world-lager-lap" })
        let styles = FlightProgress.normalizedStyles(["czech PILSNER", "Munich Helles"])

        XCTAssertEqual(FlightProgress.completedStops(in: quest, styles: styles), 2)
    }

    func testFlightProgressDoesNotCountUnrelatedStyles() throws {
        let quest = try XCTUnwrap(FlightsData.quests.first { $0.id == "dark-room" })
        let styles = FlightProgress.normalizedStyles(["Hazy IPA", "Pilsner"])

        XCTAssertEqual(FlightProgress.completedStops(in: quest, styles: styles), 0)
    }

    func testCompletedQuestIDsRequiresEveryStop() throws {
        let quest = try XCTUnwrap(FlightsData.quests.first { $0.id == "world-lager-lap" })
        let partial = FlightProgress.normalizedStyles(quest.stops.dropLast().map(\.style))
        let complete = FlightProgress.normalizedStyles(quest.stops.map(\.style))

        XCTAssertFalse(FlightProgress.completedQuestIDs(styles: partial).contains(quest.id))
        XCTAssertTrue(FlightProgress.completedQuestIDs(styles: complete).contains(quest.id))
    }

    func testOneSpecificStyleCannotCompleteTwoStops() throws {
        let quest = try XCTUnwrap(FlightsData.quests.first { $0.id == "dark-room" })
        let styles = FlightProgress.normalizedStyles(["Nitro Stout"])

        XCTAssertEqual(FlightProgress.completedStops(in: quest, styles: styles), 1)
    }

    func testGenericLagerDoesNotCompleteNonAlcoholicLager() throws {
        let quest = try XCTUnwrap(FlightsData.quests.first { $0.id == "no-low-all-stars" })
        let styles = FlightProgress.normalizedStyles(["Lager"])

        XCTAssertEqual(FlightProgress.completedStops(in: quest, styles: styles), 0)
    }

    func testNormalizedStylesDeduplicatesEquivalentEntries() {
        let styles = FlightProgress.normalizedStyles([" Pilsner ", "pilsner", "PILSNER"])

        XCTAssertEqual(styles, Set(["pilsner"]))
    }
}
