import XCTest
@testable import WalkieTalkie

/// The 🔎/🧐 answers as shown: `(site)` links, no bibliography (2026-10-10).
final class QuickAskCitedTests: XCTestCase {
    let raw = """
        Islanda are în jur de 396.500 de locuitori: „The population of Iceland at the end of the second quarter 2026 was 396,500" [1]. Capitala e Reykjavik [2].

        [1] https://statice.is/publications/news-archive/inhabitants/population-2026/
        [2] Wikipedia — https://en.wikipedia.org/wiki/Reykjavík
        CHANGED
        """

    func testSourcesBecomeSiteLinksAndTheListGoes() {
        let c = QuickAsk.cited(raw)
        XCTAssertTrue(c.changed)
        let (plain, links) = ReplyPanel.parseLinks(c.text)
        XCTAssertEqual(plain, "Islanda are în jur de 396.500 de locuitori: „The population of Iceland at the end of the second quarter 2026 was 396,500\" (statice.is). Capitala e Reykjavik (en.wikipedia.org).")
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual((plain as NSString).substring(with: links[0].range), "(statice.is)")
        XCTAssertFalse(plain.contains("http"))
        XCTAssertFalse(plain.contains("CHANGED"))
    }

    func testTheQuoteIsSelectedOnThePage() {
        let links = ReplyPanel.parseLinks(QuickAsk.cited(raw).text).links
        // A long quote: first and last four words.
        XCTAssertEqual(links[0].url.absoluteString,
                       "https://statice.is/publications/news-archive/inhabitants/population-2026/#:~:text=The%20population%20of%20Iceland,quarter%202026%20was%20396%2C500")
        // No quote before it: the page alone.
        XCTAssertFalse(links[1].url.absoluteString.contains(":~:"))
    }

    func testAnAnswerWithoutSourcesIsLeftAlone() {
        let c = QuickAsk.cited("Doar un răspuns.")
        XCTAssertEqual(c.text, "Doar un răspuns.")
        XCTAssertFalse(c.changed)
    }
}
