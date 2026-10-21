import XCTest
@testable import WalkieTalkie

/// The typed line (R18, TD20) and the review read-back (TD19) — batch 5, 2026-09-26.
final class TerminalLineTests: XCTestCase {

    func testControlBytesAreStrippedFromTheTypedLine() {
        let said = "a \u{3} ctrl-c here \u{1B}[201~ paste-end \u{1B}]0;title\u{7}b \u{7F}c\u{1B}Pdcs\u{1B}\\d \u{9B}2Je"
        XCTAssertEqual(TerminalBinding.singleLine(said), "a ctrl-c here paste-end b cd e")
    }

    func testLiteralsTabsAndLinesSurvive() {
        let said = "He said \"yes\" then $(date) and `whoami`\tok\nsecond line ăîșțâ 🎤"
        XCTAssertEqual(TerminalBinding.singleLine(said),
                       "He said \"yes\" then $(date) and `whoami` ok\nsecond line ăîșțâ 🎤")
    }

    func testTheEchoOfTheSentenceIsNotTheHint() {
        let sent = "TD19 so press Enter to send it now"
        let tail = "Last login: Sat\n$ exec cat >> x\nTD19 so press Enter to send it now\n"
        XCTAssertFalse(TerminalBinding.asksForReview(tail: tail, sent: sent))
    }

    func testTheHintUnderTheBoxIsSeen() {
        let sent = "please fix the build and tell me what broke"
        let tail = """
        ────────────────────────
        > please fix the build and tell me what
          broke
        ────────────────────────
          Removed 1 invisible character · review and press Enter to send
        """
        XCTAssertTrue(TerminalBinding.asksForReview(tail: tail, sent: sent))
    }

    func testACollapsedPasteIsReadWhole() {
        let sent = "a long envelope\nwith a footer line at the end"
        let tail = "> [Pasted text #1 +3 lines]\n  review and press Enter to send"
        XCTAssertTrue(TerminalBinding.asksForReview(tail: tail, sent: sent))
    }

    func testASentenceEndingInTheHintDoesNotAskItself() {
        let sent = "just type it and press Enter to send"
        XCTAssertFalse(TerminalBinding.asksForReview(tail: "$ cat\njust type it and press Enter to send\n", sent: sent))
    }

    // 2026-09-29: the 4 s watch ends early only on a sentence seen submitted.
    func testASentenceStillInTheBoxIsNotSubmitted() {
        let sent = "please fix the build and tell me what broke"
        let tail = "⏺ done\n────\n❯ please fix the build and tell me what broke\n────\n  Opus 5.5 · auto mode on"
        XCTAssertTrue(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
        XCTAssertFalse(TerminalBinding.submitted(tail: tail, sent: sent))
    }

    func testAnEchoAboveAnEmptyBoxIsSubmitted() {
        let sent = "please fix the build and tell me what broke"
        let tail = "> please fix the build and tell me what broke\n\n✻ Thinking…\n────\n❯ \n────\n  Opus 5.5 · auto mode on"
        XCTAssertFalse(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
        XCTAssertTrue(TerminalBinding.submitted(tail: tail, sent: sent))
    }

    func testOnlyTheStatusLineIsNeitherSoTheWatchGoesOn() {
        let sent = "please fix the build and tell me what broke"
        let tail = "────────────────\n  Opus 5.5 · 220K · auto mode on (shift+tab to cycle)"
        XCTAssertFalse(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
        XCTAssertFalse(TerminalBinding.submitted(tail: tail, sent: sent))
    }

    // 2026-09-29 15:19: a long envelope collapsed in the box is still unsent.
    func testACollapsedPasteInTheBoxIsStillInPrompt() {
        let sent = "[📸0 auto]\nI still don't see the change here\n\n[Dictated in RO or EN]"
        let tail = "⏺ done\n────\n❯ [Pasted text #1 +6 lines]\n────\n  Opus 5.5 · auto mode on"
        XCTAssertTrue(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
        XCTAssertFalse(TerminalBinding.submitted(tail: tail, sent: sent))
    }

    func testACollapsedPasteAboveAnEmptyBoxIsNotPressedAgain() {
        let sent = "[📸0 auto]\nI still don't see the change here"
        let tail = "> [Pasted text #1 +6 lines]\n\n✻ Thinking…\n────\n❯ \n────\n  Opus 5.5 · auto mode on"
        XCTAssertFalse(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
    }

    // 15:30: the box held the envelope's later lines, not its first.
    func testALaterLineOfTheEnvelopeInTheBoxIsStillInPrompt() {
        let sent = "[📸0 auto]\nfix the legend\n\n[Dictated in RO or EN]\n[📁=$WALKIE_SHOTS/2026-09-29-15-23-32/15-29-57]"
        let tail = "⏺ done\n────\n❯ [Dictated in RO or EN]\n  [📁=$WALKIE_SHOTS/2026-09-29-15-23-32/15-29-57]\n────\n  Opus 5.5 · auto mode on"
        XCTAssertTrue(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
    }

    // 15:26: box drawn empty, the footer says a paste is still held.
    func testPasteAgainToExpandIsStillInPrompt() {
        let sent = "[📸0 auto]\na seventy second dictation"
        let tail = "────\n❯ \n────\n  Opus 5.5 · human-review · paste again to expand"
        XCTAssertTrue(TerminalBinding.stillInPrompt(tail: tail, sent: sent))
    }
}
