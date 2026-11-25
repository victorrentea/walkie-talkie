import XCTest
@testable import WalkieTalkie

/// The Prompt Log reads the envelope back (2026-11-25): pictures where he took
/// them, an area on its screen, highlights as quotes, the footer apart.
///
/// `PROMPT_LOG_HTML=<file> swift test --filter MessageLogRenderTests` also
/// renders the real outbox's last two days into `<file>`, to look at.
final class MessageLogRenderTests: XCTestCase {

    func testTheFooterIsSplitFromTheWords() {
        let line = "[📸0 auto]\nPun un dressing aici [📸1✂️892,405→1162,495] sau aici.\n\n[dictated 💻 · 🎙️]\n[📁=$WALKIE_SHOTS/2026-11-25-08-21-11]\n[🎦1 = $WALKIE_SHOTS/x/film-1/sheet.png, 14s, 51 frames, video video.mov]"
        let (body, meta) = MessageLog.split(line)
        XCTAssertEqual(body, "[📸0 auto]\nPun un dressing aici [📸1✂️892,405→1162,495] sau aici.")
        XCTAssertEqual(meta, ["dictated 💻 · 🎙️", "📁=$WALKIE_SHOTS/2026-11-25-08-21-11",
                              "🎦1 = $WALKIE_SHOTS/x/film-1/sheet.png, 14s, 51 frames, video video.mov"])
    }

    func testTokensAreTheEnvelopesOwnBracketsOnly() {
        XCTAssertEqual(MessageLog.tokenize("a[0] și [📸2] și [😡] gata"),
                       [.text("a[0] și "), .token("📸2"), .text(" și "), .token("😡"), .text(" gata")])
        // A highlight may hold brackets of its own.
        XCTAssertEqual(MessageLog.tokenize(#"vezi [selected: "x[1] = y" from app IntelliJ IDEA] aici"#),
                       [.text("vezi "), .token(#"selected: "x[1] = y" from app IntelliJ IDEA"#), .text(" aici")])
    }

    func testAMovedAreaIsRedThenGreenWithAnArrow() {
        let svg = MessageLog.areaSVG(image: URL(fileURLWithPath: "/tmp/s.jpg"), pixels: CGSize(width: 3456, height: 2234),
                                     box: CGRect(x: 1106, y: 705, width: 251, height: 190),
                                     movedTo: CGRect(x: 1127, y: 792, width: 251, height: 190))
        XCTAssertTrue(svg.contains("viewBox=\"0 0 3456 2234\""))
        XCTAssertTrue(svg.contains("#ff453a"))
        XCTAssertTrue(svg.contains("#30d158"))
        XCTAssertTrue(svg.contains("<polygon"))
    }

    func testTheDestinationIsTheSessionsTitle() {
        var entry = MessageLog.Entry(date: Date(), text: "salut", app: nil, selection: nil, kind: "dictation",
                                     line: "salut\n\n[dictated]", shots: [], sources: [:])
        entry.to = "terminal:ttys004"
        entry.title = "✳ workspace — Taste volum în share Zoom"
        XCTAssertTrue(MessageLog.render(entries: [entry]).contains("→ workspace — Taste volum în share Zoom"))
        entry.title = nil
        let page = MessageLog.render(entries: [entry], titles: ["ttys004": "⠂ petclinic — fix"])
        XCTAssertTrue(page.contains("→ petclinic — fix<small>title now</small>"))
        entry.to = "spawn:/Users/x/workspace/walkie-talkie"
        XCTAssertTrue(MessageLog.render(entries: [entry]).contains("new session in walkie-talkie"))
    }

    func testCopyGivesThePathsNotTheVariable() {
        let entry = MessageLog.Entry(date: Date(), text: "x", app: nil, selection: nil, kind: "dictation",
                                     line: "x\n[📁=$WALKIE_SHOTS/2026-11-25-08-21-11]", shots: [], sources: [:])
        XCTAssertEqual(MessageLog.copyText(entry), "x\n[📁=\(Outbox.cacheRoot.path)/2026-11-25-08-21-11]")
    }

    func testRenderTheRealOutbox() throws {
        guard let path = ProcessInfo.processInfo.environment["PROMPT_LOG_HTML"] else { throw XCTSkip("PROMPT_LOG_HTML not set") }
        let saved = Outbox.outboxURL
        defer { Outbox.outboxURL = saved }
        Outbox.outboxURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".walkie-talkie/outbox.jsonl")
        let titles = TerminalBinding.liveTitles()
        try MessageLog.render(entries: MessageLog.recent(), titles: titles)
            .write(toFile: path, atomically: true, encoding: .utf8)
    }
}
