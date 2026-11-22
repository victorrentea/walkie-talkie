import XCTest
@testable import WalkieTalkie

/// 🛑 Interrupt (2026-11-22): 🔽 ← over a bound sentence, ⌃X ⌃S on Claude Code's queue.
final class InterruptGateTests: XCTestCase {

    // MARK: The flick

    func testOnlyASentenceBoundForTheTerminalIsMarked() {
        XCTAssertEqual(InterruptGate.flick(boundOpen: true, ownDictation: true, quick: false), .interrupt)
        XCTAssertEqual(InterruptGate.flick(boundOpen: false, ownDictation: true, quick: false), .nothing)
        XCTAssertEqual(InterruptGate.flick(boundOpen: true, ownDictation: true, quick: true), .nothing)
        XCTAssertEqual(InterruptGate.flick(boundOpen: true, ownDictation: false, quick: false), .nothing)
    }

    func testBoundMeansTheTerminalAndNothingElse() {
        func bound(isBound: Bool = true, quick: Bool = false, spawn: Bool = false,
                   caret: Bool = false, plainAtCaret: Bool = false, listening: Bool = true) -> Bool {
            InterruptGate.bound(listening: listening, isBound: isBound, quick: quick, spawn: spawn,
                                caret: caret, plainAtCaret: plainAtCaret)
        }
        XCTAssertTrue(bound())
        XCTAssertFalse(bound(isBound: false))
        XCTAssertFalse(bound(quick: true), "a ⚡ question")
        XCTAssertFalse(bound(spawn: true), "a new session")
        XCTAssertFalse(bound(caret: true), "the caret prompt")
        XCTAssertFalse(bound(plainAtCaret: true), "a plain dictation")
        XCTAssertFalse(bound(listening: false), "the microphone is closed")
    }

    // MARK: The keys

    func testTheChordIsControlXControlS() {
        XCTAssertEqual(Array(TerminalBinding.sendNowChord.utf8), [0x18, 0x13])
    }

    private let sent = "please look at the failing test\n\n[dictated 💻 · 🎤]"
    /// The 14:23:58 delivery, 2026-11-22: queued, the hint out of the 600 read, no chord.
    private var queuedNoHint: String {
        "❯ please look at the failing test\n" + String(repeating: "─", count: 160) + "\n❯ Press up to edit queued messages\n"
            + String(repeating: "─", count: 160) + "\n 📡 Fable 5.2 m 550K ⏵⏵ auto mode on · esc to interrupt"
    }

    func testAnInterruptPressesItOnTheQueueItself() {
        XCTAssertTrue(TerminalBinding.sendsNow(tail: queuedNoHint, sent: sent, interrupt: true))
    }

    func testAnOrdinarySentenceStillNeedsTheHint() {
        XCTAssertFalse(TerminalBinding.sendsNow(tail: queuedNoHint, sent: sent, interrupt: false))
        let hinted = "❯ [dictated 💻 · 🎤]\n  Queued · ctrl+x ctrl+s to send now\n───\n❯ Press up to edit queued messages"
        XCTAssertTrue(TerminalBinding.sendsNow(tail: hinted, sent: sent, interrupt: false))
    }

    func testAnIdleSessionGetsNothingEvenWhenInterrupting() {
        let idle = "❯ please look at the failing test\n\n⏺ Done.\n───\n❯ \n───\n ⏵⏵ auto mode on"
        XCTAssertFalse(TerminalBinding.sendsNow(tail: idle, sent: sent, interrupt: true))
    }

    func testASentenceStillInTheBoxOrSayingTheWordsIsNotAQueue() {
        let inBox = "───\n❯ please look at the failing test\n───\n ⏵⏵ auto mode on"
        XCTAssertFalse(TerminalBinding.sendsNow(tail: inBox, sent: sent, interrupt: true))
        let said = "press up to edit queued messages is what it shows"
        XCTAssertFalse(TerminalBinding.sendsNow(tail: "❯ \(said)\n\n⏺ Yes.\n───\n❯ \n", sent: said, interrupt: true))
        XCTAssertFalse(TerminalBinding.queueShown(tail: "$ cat\nPress up to edit queued messages"), "no ❯: not Claude Code's box")
    }

    // MARK: The receipt

    func testTheFlashSaysWhatHappened() {
        XCTAssertEqual(InterruptGate.receipt(sentNow: true, readsBack: true), "🛑 Interrupt — sent now")
        XCTAssertNil(InterruptGate.receipt(sentNow: false, readsBack: true), "Claude Code took it at once")
        XCTAssertEqual(InterruptGate.receipt(sentNow: false, readsBack: false),
                       "🛑 Interrupt works only in Claude Code in Terminal — sent as usual")
        XCTAssertTrue(TerminalBinding.Handle.terminalApp(tty: "/dev/ttys001").readsBack)
        XCTAssertFalse(TerminalBinding.Handle.tmux(pane: "%1", tty: "/dev/ttys001").readsBack)
    }
}
