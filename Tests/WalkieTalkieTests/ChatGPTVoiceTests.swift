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

extension ChatGPTVoiceTests {
    /// `VoiceDialog.tail` — what the panel shows of a reply longer than its lines.
    func testThePanelShowsTheEndOfALongReplyFromAWordsStart() {
        XCTAssertEqual(VoiceDialog.tail("short", 20), "short")
        XCTAssertEqual(VoiceDialog.tail("one two three four five six", 12), "… five six")
    }

    /// The labels read from the app on 2026-11-16: the composer's button on a
    /// new chat, and what stands in its place during a call.
    func testTheWindowsOwnVoiceButtonsAreKnownByLabel() {
        XCTAssertTrue(ChatGPTVoice.isVoiceButton("Start new voice chat", stop: false))
        XCTAssertTrue(ChatGPTVoice.isVoiceButton("Start voice chat", stop: false))
        XCTAssertTrue(ChatGPTVoice.isVoiceButton("Stop voice chat", stop: true))
        XCTAssertFalse(ChatGPTVoice.isVoiceButton("Stop voice chat", stop: false))
        XCTAssertFalse(ChatGPTVoice.isVoiceButton("Start new voice chat", stop: true))
        XCTAssertFalse(ChatGPTVoice.isVoiceButton("New voice chat", stop: false))
        XCTAssertFalse(ChatGPTVoice.isVoiceButton("Mute microphone", stop: true))
    }

    @available(macOS 14.2, *)
    func testTheMuteLogSaysWhatItSwallowed() {
        XCTAssertEqual(AppMute.heard(first: nil, last: nil), "the app played nothing meanwhile")
        XCTAssertEqual(AppMute.heard(first: 0.42, last: 1.9), "swallowed its sound from 0.4 s to 1.9 s")
    }

    @available(macOS 14.2, *)
    func testTheMuteEndsWhenTheChimeHasPlayedOut() {
        func over(_ armed: Double, _ first: Double?, _ last: Double?) -> Bool {
            AppMute.isOver(sinceArmed: armed, sinceFirst: first, sinceLast: last, patience: 4, quiet: 0.4, cap: 4)
        }
        XCTAssertFalse(over(1.0, nil, nil), "nothing played yet: wait")
        XCTAssertTrue(over(4.0, nil, nil), "nothing played at all: give up")
        XCTAssertFalse(over(2.0, 0.6, 0.05), "the chime is playing")
        XCTAssertTrue(over(3.4, 2.0, 0.45), "played, then quiet")
        XCTAssertTrue(over(6.0, 4.1, 0.0), "still playing after the cap: that is speech, let it through")
        XCTAssertFalse(AppMute.isOver(sinceArmed: 60, sinceFirst: nil, sinceLast: nil, patience: .infinity, quiet: 0.4, cap: 4),
                       "the connect waits for its chime however late")
        XCTAssertTrue(ChatGPTVoice.connectPatience.isInfinite)
    }

    /// 🔽 ← (2026-11-16): the first question rides the new chat's link, prefilled.
    func testTheQuestionRidesTheNewChatLink() {
        XCTAssertEqual(ChatGPTVoice.newChatLink(resumed: nil, question: nil)?.absoluteString, "codex://threads/new")
        XCTAssertEqual(ChatGPTVoice.newChatLink(resumed: "abc", question: nil)?.absoluteString, "codex://threads/abc")
        XCTAssertEqual(ChatGPTVoice.newChatLink(resumed: nil, question: "")?.absoluteString, "codex://threads/new")
        let link = ChatGPTVoice.newChatLink(resumed: "abc", question: "Cât face 2 + 2 & de ce?")
        XCTAssertEqual(link?.scheme, "codex"); XCTAssertEqual(link?.host, "threads"); XCTAssertEqual(link?.path, "/new")
        let text = link?.absoluteString ?? ""
        XCTAssertFalse(text.contains("+"), text)
        XCTAssertFalse(text.contains(" & "), text)
        let back = URLComponents(string: text)?.queryItems?.first { $0.name == "prompt" }?.value
        XCTAssertEqual(back, "Cât face 2 + 2 & de ce?")
    }
}
