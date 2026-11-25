import XCTest
@testable import WalkieTalkie

/// 2026-11-25 — `POST /question/toggle`, the DJI Link ×2's ⚡ question.
final class QuestionToggleTests: XCTestCase {

    func testAtRestItStartsAQuestion() {
        XCTAssertEqual(QuestionToggle.decide(open: false, quick: false, wordsInFlight: false, blocked: nil), .start)
    }

    func testWhileAQuestionRecordsItEndsIt() {
        XCTAssertEqual(QuestionToggle.decide(open: true, quick: true, wordsInFlight: false, blocked: "`listening`"), .end)
    }

    func testAnyOtherDictationRecordingIsLeftAlone() {
        guard case .refuse(let why) = QuestionToggle.decide(open: true, quick: false, wordsInFlight: false, blocked: "`listening`") else {
            return XCTFail("a prompt or plain dictation must not be ended or replaced")
        }
        XCTAssertTrue(why.contains("another dictation"))
    }

    func testWordsInFlightStartNothing() {
        guard case .refuse = QuestionToggle.decide(open: false, quick: false, wordsInFlight: true, blocked: nil) else {
            return XCTFail("🔼 ← at rest starts nothing while words are in flight; neither does Link ×2")
        }
    }

    func testAStartTheAppWouldRefuseIsRefusedWithItsReason() {
        XCTAssertEqual(QuestionToggle.decide(open: false, quick: false, wordsInFlight: false, blocked: "two sentences in flight"),
                       .refuse("a start would be refused now — two sentences in flight"))
    }

    func testTheAnswers() {
        let started = QuestionToggle.answer(.start)
        XCTAssertEqual(started.status, 200)
        XCTAssertEqual(started.body["result"] as? String, "started")
        XCTAssertEqual(QuestionToggle.answer(.end).body["result"] as? String, "ended")
        let refused = QuestionToggle.answer(.refuse("why"))
        XCTAssertEqual(refused.status, 409)
        XCTAssertEqual(refused.body["result"] as? String, "refused")
        XCTAssertEqual(refused.body["why"] as? String, "why")
    }
}
