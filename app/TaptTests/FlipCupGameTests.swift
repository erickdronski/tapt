import CoreGraphics
import XCTest
@testable import Tapt

final class FlipCupGameTests: XCTestCase {
    func testWeakFlickDoesNotLaunch() {
        let trajectory = FlipCupPhysics.trajectory(
            for: CGSize(width: 0, height: -70)
        )

        XCTAssertFalse(trajectory.launched)
        XCTAssertFalse(trajectory.landed)
    }

    func testCleanSingleRotationLands() {
        let trajectory = FlipCupPhysics.trajectory(
            for: CGSize(width: 0, height: -430)
        )

        XCTAssertTrue(trajectory.launched)
        XCTAssertTrue(trajectory.landed)
        XCTAssertLessThan(trajectory.alignmentError, 10)
    }

    func testUnderAndOverRotationMiss() {
        let under = FlipCupPhysics.trajectory(for: CGSize(width: 0, height: -300))
        let over = FlipCupPhysics.trajectory(for: CGSize(width: 0, height: -700))

        XCTAssertTrue(under.launched)
        XCTAssertFalse(under.landed)
        XCTAssertTrue(over.launched)
        XCTAssertFalse(over.landed)
    }

    func testMatchNormalizesOneToFourPlayers() {
        let empty = FlipCupMatch(playerNames: [], target: 0)
        let many = FlipCupMatch(
            playerNames: ["Ada", "", "Mina", "Jo", "Extra"],
            target: 99
        )

        XCTAssertEqual(empty.playerNames, ["Player 1"])
        XCTAssertEqual(empty.target, 1)
        XCTAssertEqual(many.playerNames, ["Ada", "Player 2", "Mina", "Jo"])
        XCTAssertEqual(many.target, 20)
    }

    func testTurnRotatesAcrossFourPlayersAfterEveryAttempt() {
        var match = FlipCupMatch(
            playerNames: ["One", "Two", "Three", "Four"],
            target: 3
        )

        XCTAssertEqual(match.record(success: true).nextPlayerIndex, 1)
        XCTAssertEqual(match.record(success: false).nextPlayerIndex, 2)
        XCTAssertEqual(match.record(success: true).nextPlayerIndex, 3)
        XCTAssertEqual(match.record(success: false).nextPlayerIndex, 0)
        XCTAssertEqual(match.scores, [1, 0, 1, 0])
        XCTAssertEqual(match.attempts, [1, 1, 1, 1])
    }

    func testWinnerFreezesMatchState() {
        var match = FlipCupMatch(playerNames: ["One", "Two"], target: 2)

        _ = match.record(success: true)
        _ = match.record(success: false)
        let winningTurn = match.record(success: true)
        let frozen = match
        let ignoredTurn = match.record(success: true)

        XCTAssertEqual(winningTurn.winnerIndex, 0)
        XCTAssertEqual(match.winnerIndex, 0)
        XCTAssertEqual(match, frozen)
        XCTAssertEqual(ignoredTurn.winnerIndex, 0)
        XCTAssertFalse(ignoredTurn.success)
    }

    func testStreaksAreTrackedPerPlayer() {
        var match = FlipCupMatch(playerNames: ["One", "Two"], target: 4)

        _ = match.record(success: true)
        _ = match.record(success: true)
        _ = match.record(success: true)
        _ = match.record(success: false)
        _ = match.record(success: false)

        XCTAssertEqual(match.streaks, [0, 0])
        XCTAssertEqual(match.bestStreaks, [2, 1])
    }
}
