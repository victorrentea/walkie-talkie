import XCTest
@testable import WalkieTalkie

/// ⌃X ⌃S is pressed only on Claude Code's own hint under this sentence (2026-11-05).
final class SendNowHintTests: XCTestCase {
    private let sent = "please look at the failing test"

    func testTheHintUnderTheSentenceCounts() {
        let tail = "❯ please look at the failing test\n  ctrl+x ctrl+s to send now\n───\n❯ Press up to edit queued messages"
        XCTAssertTrue(TerminalBinding.waitsToSendNow(tail: tail, sent: sent))
    }

    func testASentenceThatSaysTheWordsDoesNot() {
        let said = "explain what to send now means here"
        XCTAssertFalse(TerminalBinding.waitsToSendNow(tail: "❯ \(said)\n───\n❯ \n", sent: said))
    }

    func testAnIdleSessionDoesNot() {
        XCTAssertFalse(TerminalBinding.waitsToSendNow(tail: "❯ \(sent)\n\n⏺ Done.\n───\n❯ \n", sent: sent))
    }
}
