import XCTest
@testable import WalkieTalkie

/// 2026-11-22 — a bound prompt needs a bound terminal; nothing is held for a bind.
final class BoundPromptGateTests: XCTestCase {

    func testABoundPromptWithNothingBoundDoesNotStart() {
        XCTAssertEqual(BoundPromptGate.start(spawn: false, paste: false, bound: false, bindInFlight: false), .refuse)
    }

    func testABoundPromptWithATerminalBoundStarts() {
        XCTAssertEqual(BoundPromptGate.start(spawn: false, paste: false, bound: true, bindInFlight: false), .open)
    }

    func testAPressDuringABindStillResolvingIsBanked() {
        XCTAssertEqual(BoundPromptGate.start(spawn: false, paste: false, bound: false, bindInFlight: true), .bank)
    }

    /// The caret prompt, the plain dictation, the ⚡ question (`paste`) and the
    /// new session / wake word (`spawn`) never ask about the binding.
    func testEverythingThatIsNotABoundPromptStartsUnbound() {
        for inFlight in [false, true] {
            XCTAssertEqual(BoundPromptGate.start(spawn: false, paste: true, bound: false, bindInFlight: inFlight), .open)
            XCTAssertEqual(BoundPromptGate.start(spawn: true, paste: false, bound: false, bindInFlight: inFlight), .open)
        }
    }

    func testACaretSentenceIsNotFlippedToBoundWithNothingBound() {
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: true, spawn: false, pickInFlight: false, bound: false), .stay)
    }

    func testTheFlipIsStillAToggleWhenBound() {
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: true, spawn: false, pickInFlight: false, bound: true), .toBound)
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: false, spawn: false, pickInFlight: false, bound: true), .toCaret)
    }

    /// Its terminal unbound while he spoke: 🔼 → still takes it to the caret.
    func testATerminalSentenceGoesToTheCaretEvenUnbound() {
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: false, spawn: false, pickInFlight: false, bound: false), .toCaret)
    }

    func testASpawnAndAPickEndOnTheGesture() {
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: false, spawn: true, pickInFlight: false, bound: true), .end)
        XCTAssertEqual(BoundPromptGate.flip(gesture: true, atCaret: false, spawn: false, pickInFlight: true, bound: false), .end)
    }

    /// The wheel's toggle (no flip): redirects a caret sentence when bound, else stops.
    func testTheWheelToggleKeepsItsStop() {
        XCTAssertEqual(BoundPromptGate.flip(gesture: false, atCaret: true, spawn: false, pickInFlight: false, bound: true), .toBound)
        XCTAssertEqual(BoundPromptGate.flip(gesture: false, atCaret: true, spawn: false, pickInFlight: false, bound: false), .end)
        XCTAssertEqual(BoundPromptGate.flip(gesture: false, atCaret: false, spawn: false, pickInFlight: false, bound: true), .end)
    }

    /// English, says why and what to do; the kept prompt names both places.
    func testTheSentences() {
        XCTAssertEqual(BoundPromptGate.nothingBound, "📍 Nothing bound — ⌘⌃B binds the terminal in front")
        XCTAssertEqual(BoundPromptGate.undelivered("Terminal closed"),
                       "⚠️ Terminal closed — find the prompt in Prompt History or ⌘V")
        // One flash line holds ~60 characters; the longest of the three must fit.
        XCTAssertLessThanOrEqual(BoundPromptGate.undelivered("No new session").count, 60)
        XCTAssertEqual(BoundPromptGate.undeliveredTo, "undelivered")
    }

    /// Prompt History reads the outbox: an undelivered row is shown, and marked.
    func testPromptHistoryMarksAnUndeliveredRow() {
        XCTAssertEqual(MessageLog.undelivered(["to": "undelivered", "wanted": "terminal:ttys004"]), "terminal:ttys004")
        XCTAssertNil(MessageLog.undelivered(["to": "terminal:ttys004"]))
        XCTAssertNil(MessageLog.undelivered(nil))
        let entry = MessageLog.Entry(date: Date(), text: "fix the tax rounding", app: nil, selection: nil,
                                     kind: "dictation", line: "fix the tax rounding\n\n[dictated]", shots: [],
                                     sources: [:], undelivered: "terminal:ttys004")
        let page = MessageLog.render(entries: [entry])
        XCTAssertTrue(page.contains("not delivered — was for terminal:ttys004"))
        XCTAssertTrue(page.contains("fix the tax rounding"))
    }

    /// The hold is gone from the app: no chip row, no state field, no constant.
    func testNothingHoldsForABindAnyMore() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["AppDelegate.swift", "RelayWindow.swift", "OverlayStates.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/WalkieTalkie/\(file)"), encoding: .utf8)
            for gone in ["var awaitingBind", "func holdForBind", "static let holdsForBind", "setHeldCount", "\"awaitingBind\"",
                         "waiting — bind to send", "held — bind a terminal", "func aimAtPreviousTerminal"] {
                XCTAssertFalse(text.contains(gone), "\(file) still has `\(gone)`")
            }
        }
    }
}
