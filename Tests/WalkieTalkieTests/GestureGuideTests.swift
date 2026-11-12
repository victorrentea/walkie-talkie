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
}
