import XCTest
@testable import WalkieTalkie

/// `QuitGate.verdict` — a quit waits for a sentence, never for ever, and never
/// past a second ask (2026-11-22: a Quit and a SIGTERM both waited on two
/// sentences that could not land; the app had to be SIGKILLed).
final class QuitGateTests: XCTestCase {
    let busy = ["transcribing", "an earlier sentence in flight"]

    func testNothingInTheWayGoesAtOnce() {
        XCTAssertEqual(QuitGate.verdict(blockers: [], waited: nil, askedAgain: true), .go(""))
        XCTAssertEqual(QuitGate.verdict(blockers: [], waited: 3, askedAgain: false), .go(""))
    }

    func testTheFirstAskMidSentenceWaits() {
        XCTAssertEqual(QuitGate.verdict(blockers: busy, waited: nil, askedAgain: true), .wait)
    }

    func testTheRetryKeepsWaitingUntilTheCeiling() {
        XCTAssertEqual(QuitGate.verdict(blockers: busy, waited: 58, askedAgain: false), .wait)
        guard case .go(let why) = QuitGate.verdict(blockers: busy, waited: QuitGate.ceiling, askedAgain: false) else {
            return XCTFail("the ceiling lets it through")
        }
        XCTAssertTrue(why.contains("transcribing"), why)
    }

    func testASecondAskGoesAtOnce() {
        // 13:56:07 Quit (deferred), 13:57:05 SIGTERM — 58 s later, still refused.
        guard case .go(let why) = QuitGate.verdict(blockers: busy, waited: 58, askedAgain: true) else {
            return XCTFail("a second ask must go")
        }
        XCTAssertTrue(why.contains("asked again"), why)
    }

    func testTheSameClickTwiceIsNotASecondAsk() {
        XCTAssertEqual(QuitGate.verdict(blockers: busy, waited: 0.2, askedAgain: true), .wait)
    }

    func testTheHardExitIsShort() {
        XCTAssertLessThanOrEqual(QuitGate.hardExit, 2)
    }
}
