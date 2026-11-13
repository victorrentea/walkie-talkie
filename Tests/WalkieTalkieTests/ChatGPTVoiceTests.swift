import XCTest
@testable import WalkieTalkie

/// `ChatGPTVoice.fill` — where 🔽 ← puts ChatGPT's window (2026-11-13).
final class ChatGPTVoiceTests: XCTestCase {

    func testThePrimaryScreenUnderItsMenuBar() {
        // 1728×1117, menu bar 38 pt: the visible frame in AppKit starts at y 0.
        XCTAssertEqual(ChatGPTVoice.fill(CGRect(x: 0, y: 0, width: 1728, height: 1079), primaryHeight: 1117),
                       CGRect(x: 0, y: 38, width: 1728, height: 1079))
    }

    func testAScreenLeftOfAndAboveThePrimary() {
        XCTAssertEqual(ChatGPTVoice.fill(CGRect(x: -1920, y: 1117, width: 1920, height: 1055), primaryHeight: 1117),
                       CGRect(x: -1920, y: -1055, width: 1920, height: 1055))
    }

    func testTheDjiRemapIsVolumeUpToF20() {
        XCTAssertTrue(DjiButton.mapping(on: true).contains("0xC000000E9"))
        XCTAssertTrue(DjiButton.mapping(on: true).contains("0x70000006F"))
        XCTAssertEqual(DjiButton.keyCode, 90)
    }
}

extension ChatGPTVoiceTests {
    /// The newest conversation is the last key as the file has them.
    func testTheVoiceThreadsInTheFilesOwnOrder() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("continuity-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try #"{"version":1,"threads":{"zz-old":{"items":[]},"aa-new":{"items":[{"role":"user","text":"zz-old"}]}}}"#
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ChatGPTVoice.voiceThreads(in: file), ["zz-old", "aa-new"])
        XCTAssertEqual(ChatGPTVoice.voiceThreads(in: file.appendingPathExtension("missing")), [])
    }
}
