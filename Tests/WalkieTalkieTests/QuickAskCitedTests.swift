import XCTest
@testable import WalkieTalkie

/// The 🔎/🧐 answers as shown (2026-10-10): the facts and a `(site)` after each,
/// the quote only in the link — never in the words — and no bibliography.
final class QuickAskCitedTests: XCTestCase {
    let raw = """
        Islanda are aproximativ 396.500 de locuitori [1: "The population of Iceland at the end of the second quarter 2026 was 396,500"]. Capitala e Reykjavík [2].

        [1] https://statice.is/publications/news-archive/inhabitants/population-2026/
        [2] Wikipedia — https://en.wikipedia.org/wiki/Reykjavík
        CHANGED
        """

    func testTheFactsAndTheSitesOnly() {
        let c = QuickAsk.cited(raw)
        XCTAssertTrue(c.changed)
        let (plain, links) = ReplyPanel.parseLinks(c.text)
        XCTAssertEqual(plain, "Islanda are aproximativ 396.500 de locuitori (statice.is). Capitala e Reykjavík (en.wikipedia.org).")
        // Only the name is the link, not its brackets.
        XCTAssertEqual((plain as NSString).substring(with: links[0].range), "statice.is")
        XCTAssertEqual(links.count, 2)
    }

    func testTheQuoteIsSelectedOnThePage() {
        let links = ReplyPanel.parseLinks(QuickAsk.cited(raw).text).links
        // A long quote: its first and last four words.
        XCTAssertEqual(links[0].url.absoluteString,
                       "https://statice.is/publications/news-archive/inhabitants/population-2026/#:~:text=The%20population%20of%20Iceland,quarter%202026%20was%20396%2C500")
        XCTAssertFalse(links[1].url.absoluteString.contains(":~:"))
    }

    func testAnAnswerWithoutSourcesIsLeftAlone() {
        let c = QuickAsk.cited("Doar un răspuns.")
        XCTAssertEqual(c.text, "Doar un răspuns.")
        XCTAssertFalse(c.changed)
    }

    func testTheRunningDotsReadAsAnEllipsis() {
        XCTAssertEqual(ReplyPanel.plain("— Opus 5.5 · 🔎 searching" + ReplyPanel.dots), "— Opus 5.5 · 🔎 searching…")
    }
}
