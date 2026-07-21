import XCTest
@testable import Tapt

final class TriviaDataTests: XCTestCase {
    func testQuestionCatalogIntegrity() {
        XCTAssertGreaterThanOrEqual(TriviaData.questions.count, 54)
        XCTAssertEqual(
            Set(TriviaData.questions.map(\.q)).count,
            TriviaData.questions.count,
            "Question text must be unique"
        )

        for question in TriviaData.questions {
            XCTAssertEqual(question.options.count, 4, question.q)
            XCTAssertEqual(Set(question.options).count, question.options.count, question.q)
            XCTAssertTrue(question.options.indices.contains(question.correct), question.q)
            XCTAssertFalse(question.why.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, question.q)
        }
    }

    func testSeededRoundsAreDeterministic() {
        let first = TriviaData.round(limit: 12, category: .mixed, seed: "2026-07-21")
        let second = TriviaData.round(limit: 12, category: .mixed, seed: "2026-07-21")

        XCTAssertEqual(first.map(\.q), second.map(\.q))
        XCTAssertEqual(first.map(\.options), second.map(\.options))
        XCTAssertEqual(first.map(\.correct), second.map(\.correct))
    }

    func testOptionShufflePreservesEveryCorrectAnswer() throws {
        let originals = Dictionary(uniqueKeysWithValues: TriviaData.questions.map {
            ($0.q, $0.options[$0.correct])
        })
        let round = TriviaData.round(limit: nil, category: .mixed, seed: "answer-preservation")

        for question in round {
            let originalAnswer = try XCTUnwrap(originals[question.q])
            XCTAssertEqual(question.options[question.correct], originalAnswer, question.q)
        }
    }

    func testFixedFirstAnswerCategoriesNoLongerRevealTheAnswer() {
        let popRound = TriviaData.round(limit: nil, category: .popCulture, seed: "pop-options")
        let factsRound = TriviaData.round(limit: nil, category: .funFacts, seed: "facts-options")

        XCTAssertTrue(popRound.contains { $0.correct != 0 })
        XCTAssertTrue(factsRound.contains { $0.correct != 0 })
    }

    func testRoundLimitIsBounded() {
        XCTAssertEqual(TriviaData.round(limit: 5, category: .mixed, seed: "daily").count, 5)
        XCTAssertEqual(
            TriviaData.round(limit: 500, category: .general, seed: "all").count,
            TriviaData.general.count
        )
    }
}
