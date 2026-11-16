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

    /// The stamp covers the whole edge, stays in the strip near the edge, and never jumps.
    func testTheStampSweepsTheWholeEdgeNearIt() {
        var low = 1.0, high = 0.0, last = EdgeDust.stamp(at: 0, sweep: 1.3).along
        for i in 0...(60 * 30) {
            let s = EdgeDust.stamp(at: Double(i) / 60, sweep: 1.3)
            low = min(low, s.along); high = max(high, s.along)
            XCTAssertTrue((0...1).contains(s.along))
            XCTAssertTrue((0.03...0.3).contains(s.depth), "depth \(s.depth)")
            XCTAssertLessThan(abs(s.along - last), 0.05, "a jump at frame \(i)")
            last = s.along
        }
        XCTAssertLessThan(low, 0.05)
        XCTAssertGreaterThan(high, 0.95)
    }

    /// A puff is as many points across on the wide strip as on the tall one.
    func testThePuffKeepsItsSizeOnEitherCanvas() {
        let wide = EdgeDust.radius(puff: 22, canvasHeight: 110), tall = EdgeDust.radius(puff: 22, canvasHeight: 1117)
        XCTAssertEqual(Double(wide.squareRoot()) * 110, Double(tall.squareRoot()) * 1117, accuracy: 0.01)
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
