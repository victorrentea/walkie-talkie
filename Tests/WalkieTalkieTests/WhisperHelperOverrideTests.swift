import XCTest
@testable import WalkieTalkie

/// `WT_WHISPER_HELPER` (2026-10-22): the desk's fake local helper — the environment wins,
/// then the last line of `elevenlabs.env` that names it.
final class WhisperHelperOverrideTests: XCTestCase {

    func testNoneAnywhereIsNone() {
        XCTAssertNil(LocalWhisper.overrideValue(env: [:], file: nil))
        XCTAssertNil(LocalWhisper.overrideValue(env: [:], file: "ELEVENLABS_API_KEY=sk_1\n"))
    }

    func testTheFileLineIsRead() {
        let file = """
        ELEVENLABS_API_KEY=sk_1
        # fake-whisper: written by evals/plan/cases_chunks.py
        WT_WHISPER_HELPER=/repo/evals/plan/fake_whisper_helper.py
        # fake-whisper: (end)
        """
        XCTAssertEqual(LocalWhisper.overrideValue(env: [:], file: file), "/repo/evals/plan/fake_whisper_helper.py")
    }

    func testQuotesAndCommentsAndEmpty() {
        XCTAssertEqual(LocalWhisper.overrideValue(env: [:], file: "WT_WHISPER_HELPER=\"/a b/f.py\""), "/a b/f.py")
        XCTAssertNil(LocalWhisper.overrideValue(env: [:], file: "# WT_WHISPER_HELPER=/x.py"))
        XCTAssertNil(LocalWhisper.overrideValue(env: [:], file: "WT_WHISPER_HELPER="))
        XCTAssertNil(LocalWhisper.overrideValue(env: [:], file: "WT_WHISPER_HELPER_X=/x.py"))
    }

    func testTheEnvironmentWins() {
        XCTAssertEqual(LocalWhisper.overrideValue(env: ["WT_WHISPER_HELPER": "/env.py"],
                                                  file: "WT_WHISPER_HELPER=/file.py"), "/env.py")
        XCTAssertEqual(LocalWhisper.overrideValue(env: ["WT_WHISPER_HELPER": ""],
                                                  file: "WT_WHISPER_HELPER=/file.py"), "/file.py")
    }
}
