import XCTest
@testable import WalkieTalkie

/// `WakeWord.question(in:)` and `withoutWakeWord` — what a "Hey Claude"
/// sentence becomes (2026-11-12).
final class WakeWordTests: XCTestCase {

    func testAQuestionOpeningIsTakenOff() {
        XCTAssertEqual(WakeWord.question(in: "I have a question. What port does Grafana use?"),
                       "What port does Grafana use?")
        XCTAssertEqual(WakeWord.question(in: "i have a question, what is PERCLOS"), "what is PERCLOS")
        XCTAssertEqual(WakeWord.question(in: "Am o întrebare: cât e ceasul?"), "cât e ceasul?")
        XCTAssertEqual(WakeWord.question(in: "  I've got a question — why?"), "why?")
    }

    func testTheWakeWordsTailBeforeTheQuestionIsTolerated() {
        XCTAssertEqual(WakeWord.question(in: "Claude, I have a question. Is it raining?"), "Is it raining?")
        XCTAssertEqual(WakeWord.question(in: "Hey Claude I have a question why"), "why")
    }

    func testATaskIsNotAQuestion() {
        XCTAssertNil(WakeWord.question(in: "Fix the build in petclinic"))
        // Only as the opening: later in the sentence it is a task that mentions one.
        XCTAssertNil(WakeWord.question(in: "Write a test. I have a question about it later."))
        XCTAssertNil(WakeWord.question(in: ""))
    }

    func testTheWakeWordIsTakenOffATask() {
        XCTAssertEqual(WakeWord.withoutWakeWord("Claude, fix the build"), "fix the build")
        XCTAssertEqual(WakeWord.withoutWakeWord("Hey Claude. Fix the build"), "Fix the build")
        XCTAssertEqual(WakeWord.withoutWakeWord("Fix Claude's hook"), "Fix Claude's hook")
        // A whole word only.
        XCTAssertEqual(WakeWord.withoutWakeWord("Claudette called"), "Claudette called")
    }
}
