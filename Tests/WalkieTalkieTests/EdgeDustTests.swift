import XCTest
@testable import WalkieTalkie

/// The prompt's edge (2026-11-16, `EdgeDust`) and the dust's flight to the corner.
final class EdgeDustTests: XCTestCase {
    func testTheTopStripRunsTheWholeTopEdgeAndTheRightOneTheWholeRight() {
        let screen = NSRect(x: 100, y: 50, width: 1728, height: 1117)
        let top = EdgeDust.frame(.top, on: screen, thickness: 110)
        XCTAssertEqual(top.minX, screen.minX); XCTAssertEqual(top.width, screen.width)
        XCTAssertEqual(top.maxY, screen.maxY); XCTAssertEqual(top.height, 220)       // room for the swell
        let right = EdgeDust.frame(.right, on: screen, thickness: 110)
        XCTAssertEqual(right.maxX, screen.maxX); XCTAssertEqual(right.width, 220)
        XCTAssertEqual(right.minY, screen.minY); XCTAssertEqual(right.height, screen.height)
    }

    /// As dense on a short edge as on a long one.
    func testTheGrainsAreAsDenseOnEitherEdge() {
        XCTAssertEqual(EdgeDust.birthRate(edgeLength: 1728, per100: 5), 86.4, accuracy: 0.01)
        XCTAssertEqual(EdgeDust.birthRate(edgeLength: 1117, per100: 5) / 1117, EdgeDust.birthRate(edgeLength: 1728, per100: 5) / 1728, accuracy: 0.0001)
    }

    func testTheDustFliesFromThePointerToTheWheelAndStaysThere() {
        let f = (from: NSPoint(x: 900, y: 300), to: NSPoint(x: 140, y: 950), at: 100.0)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 99), f.from)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100), f.from)
        let mid = CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime / 2)
        XCTAssertEqual(mid.x, 520, accuracy: 0.5); XCTAssertEqual(mid.y, 625, accuracy: 0.5)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime), f.to)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 200), f.to)
    }

    func testOnlyTheThreePromptsAreDressedAlike() {
        XCTAssertEqual(HaloDestination.allCases.filter(\.isPrompt), [.caret, .bound, .spawn])
    }
}
