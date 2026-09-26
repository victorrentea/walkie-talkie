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
}
