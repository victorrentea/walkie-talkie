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

    func testTheDustFliesFromThePointerToTheWheelAndStaysThere() {
        let f = (from: NSPoint(x: 900, y: 300), to: NSPoint(x: 140, y: 950), at: 100.0)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 99), f.from)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100), f.from)
        let mid = CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime / 2)
        XCTAssertEqual(mid.x, 520, accuracy: 0.5); XCTAssertEqual(mid.y, 625, accuracy: 0.5)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime), f.to)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 200), f.to)
    }

    /// Wherever it comes from, the dust meets the ring going the ring's way (clockwise).
    func testTheDustJoinsTheRingOnItsTangent() {
        let centre = NSPoint(x: 140, y: 950), r: CGFloat = 46
        for from in [NSPoint(x: 900, y: 300), NSPoint(x: 1600, y: 1000), NSPoint(x: 150, y: 100), NSPoint(x: 20, y: 500), NSPoint(x: 800, y: 1100)] {
            let a = CaretHalo.entryAngle(from: from, centre: centre, radius: r)
            // the entry point, and the ring's point a moment later (clockwise = the angle grows, y down)
            let p = NSPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y - r * CGFloat(sin(a)))
            let next = NSPoint(x: centre.x + r * CGFloat(cos(a + 0.05)), y: centre.y - r * CGFloat(sin(a + 0.05)))
            let fx = p.x - from.x, fy = p.y - from.y, tx = next.x - p.x, ty = next.y - p.y
            let cosine = (fx * tx + fy * ty) / (hypot(fx, fy) * hypot(tx, ty))
            XCTAssertGreaterThan(cosine, 0.99, "from \(from): the ring turns away from the flight")
        }
        // The turned path starts at the entry point.
        let start = CaretHalo.wheelPoint(at: 0, centre: centre, entry: 1.2)
        XCTAssertEqual(atan2(Double(centre.y - start.y), Double(start.x - centre.x)), 1.2, accuracy: 0.001)
    }

    func testOnlyTheThreePromptsAreDressedAlike() {
        XCTAssertEqual(HaloDestination.allCases.filter(\.isPrompt), [.caret, .bound, .spawn])
    }
}
