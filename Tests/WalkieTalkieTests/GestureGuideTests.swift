import XCTest
@testable import WalkieTalkie

/// The Gesture Guide's page (2026-11-12): self-contained, every section filled,
/// every mouse picture inlined. `GUIDE_HTML=<dir> swift test --filter
/// GestureGuideTests` also writes the page and a copy frozen mid-gesture
/// (`frozen.html`) for a look in a browser.
final class GestureGuideTests: XCTestCase {

    func testThePageIsWholeAndFetchesNothing() throws {
        let html = GestureGuide.page()
        for id in ["forward", "back", "pictures", "keyboard", "trackpad", "voice", "about"] {
            XCTAssertTrue(html.contains("id=\"\(id)\""), "section \(id) missing")
        }
        XCTAssertTrue(html.contains("data:image/png;base64,"), "the mouse is not inlined")
        XCTAssertFalse(html.contains("url()"), "a mouse picture failed to render")
        XCTAssertLessThan(html.utf8.count, 600_000, "a picture is inlined more than once")
        XCTAssertFalse(html.contains("url(http"), "the page must not fetch anything")
        XCTAssertFalse(html.contains("<link"), "the page must not fetch anything")

        if let dir = ProcessInfo.processInfo.environment["GUIDE_HTML"] {
            let url = URL(fileURLWithPath: dir)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try html.write(to: url.appendingPathComponent("guide.html"), atomically: true, encoding: .utf8)
            let frozen = html.replacingOccurrences(of: "</style>", with:
                "* { animation-play-state: paused !important; animation-delay: -1.95s !important; }</style>")
            try frozen.write(to: url.appendingPathComponent("frozen.html"), atomically: true, encoding: .utf8)
        }
    }

    /// The guide follows today's gesture table (2026-11-22): a plain dictation
    /// has a cancel and a stop, every stop ends in Return, 🔽 → at rest and ⌃P
    /// over it are nothing, a ⚡ question is not redirected — and the Custom
    /// gestures window names its rows as the guide's cards.
    func testTheCardsFollowTheGestureTable() {
        let html = GestureGuide.page()
        for gone in ["Dictate, no Return", "Stop — type — unbind", "make it a prompt",
                     "turns it into a prompt", "stop it, no Return", "Start or stop; only the words"] {
            XCTAssertFalse(html.contains(gone), "the guide still says “\(gone)”")
        }
        for said in ["While a ⚡ question records: nothing.", "the words, then Return",
                     "film that box alone", "At rest: nothing."] {
            XCTAssertTrue(html.contains(said), "the guide no longer says “\(said)”")
        }
        for action in CustomGestureAction.allCases {
            XCTAssertTrue(html.contains("<h3>\(action.title)</h3>"), "no guide card titled “\(action.title)”")
        }
    }
}
