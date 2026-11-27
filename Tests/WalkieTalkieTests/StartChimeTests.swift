import XCTest
@testable import WalkieTalkie

/// 📻 A sentence bound for the terminal opens with the other radio (2026-11-26).
final class StartChimeTests: XCTestCase {
    func testTheBoundSentenceHasItsOwnRadio() {
        XCTAssertEqual(StartChime.file(bound: true), "chat-voice-on.wav")
        XCTAssertEqual(StartChime.file(bound: false), "start-squelch.wav")
    }
}
