import XCTest
@testable import WalkieTalkie

/// 2026-11-24: a ⚡ follow-up turned into a new session's prompt (🔼 ↑) carries
/// the questions before it — `QuickAsk.carried`, one clause under the words.
final class QuickAskCarriedTests: XCTestCase {
    func testNothingBeforeItCarriesNothing() {
        XCTAssertNil(QuickAsk.carried([]))
    }

    func testEachTurnIsItsQuestionPicturesAndAnswer() {
        let clause = QuickAsk.carried([
            .init(question: "Ce e un monad?\n", images: ["/s/screenshot-1-800px.jpg"], answer: "Un tip cu bind.\n"),
            .init(question: "Și în Java?", images: [], answer: ""),
        ])
        XCTAssertEqual(clause, """
            [Before this, I asked these as ⚡ quick questions — continue from them:
            Q1: Ce e un monad?
              📸 /s/screenshot-1-800px.jpg
            A1: Un tip cu bind.
            Q2: Și în Java?
            A2: (no answer yet)]
            """)
    }

    func testTheAnswersDrawnMarksAreReadPlain() {
        let clause = QuickAsk.carried([.init(question: "q", images: [], answer: "x" + ReplyPanel.dots)])
        XCTAssertTrue(clause?.contains("A1: x…") == true, clause ?? "nil")
    }
}
