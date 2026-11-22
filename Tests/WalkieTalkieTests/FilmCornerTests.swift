import XCTest
@testable import WalkieTalkie

/// 🔽 ↑ with the wheel down films the box (2026-11-22): where the box is frozen.
final class FilmCornerTests: XCTestCase {
    private func trail(_ points: [(Double, CGFloat, CGFloat)]) -> [FilmCorner.Sample] {
        points.map { .init(at: $0.0, point: CGPoint(x: $0.1, y: $0.2)) }
    }

    func testNoSampleNoCorner() {
        XCTAssertNil(FilmCorner.corner(of: [], chordAt: 1))
    }

    /// Options+ holds the pointer during the swipe (or he swiped without the
    /// pointer following): the last drag sample is old, and it is the corner.
    func testAPointerThatStoodStillKeepsItsCorner() {
        let t = trail([(0.0, 100, 100), (0.1, 300, 300), (0.2, 500, 400)])
        XCTAssertEqual(FilmCorner.corner(of: t, chordAt: 0.9), CGPoint(x: 500, y: 400))
    }

    /// The pointer follows the swipe: a pause, then 90 pt straight up into the
    /// chord — the box is frozen where the hand paused, not 90 pt shorter.
    func testTheSwipesOwnTravelIsTakenBack() {
        var points: [(Double, CGFloat, CGFloat)] = [(0.0, 100, 100), (0.2, 480, 390), (0.3, 500, 400)]
        for i in 1...9 { points.append((0.8 + Double(i) * 0.01, 500 + CGFloat(i % 2), 400 - CGFloat(i) * 10)) }
        XCTAssertEqual(FilmCorner.corner(of: trail(points), chordAt: 0.9), CGPoint(x: 500, y: 400))
    }

    /// No pause at all: dragging down-right, then straight into the swipe up —
    /// the turn is the corner.
    func testWithNoPauseTheTurnIsTheCorner() {
        var points: [(Double, CGFloat, CGFloat)] = []
        for i in 0...10 { points.append((Double(i) * 0.01, 100 + CGFloat(i) * 20, 100 + CGFloat(i) * 20)) }
        for i in 1...8 { points.append((0.10 + Double(i) * 0.01, 300, 300 - CGFloat(i) * 10)) }
        XCTAssertEqual(FilmCorner.corner(of: trail(points), chordAt: 0.19), CGPoint(x: 300, y: 300))
    }

    /// Still dragging the box when the chord lands, not a swipe's shape
    /// (sideways, or going down, or a few points of wobble): the pointer's place.
    func testADragThatIsNotASwipeIsLeftAlone() {
        var sideways: [(Double, CGFloat, CGFloat)] = []
        var down: [(Double, CGFloat, CGFloat)] = []
        for i in 0...10 {
            let t = Double(i) * 0.01, k = CGFloat(i)
            sideways.append((t, 100 + k * 20, 300 - k))
            down.append((t, 100, 100 + k * 20))
        }
        XCTAssertEqual(FilmCorner.corner(of: trail(sideways), chordAt: 0.1), CGPoint(x: 300, y: 290))
        XCTAssertEqual(FilmCorner.corner(of: trail(down), chordAt: 0.1), CGPoint(x: 100, y: 300))
        let wobble = trail([(0.0, 400, 400), (0.5, 400, 400), (0.51, 401, 396), (0.52, 400, 392)])
        XCTAssertEqual(FilmCorner.corner(of: wobble, chordAt: 0.53), CGPoint(x: 400, y: 392))
    }

    /// An upward run older than the window is the drag, not the swipe.
    func testTheWindowBoundsTheRun() {
        var slow: [(Double, CGFloat, CGFloat)] = []
        for i in 0...30 { slow.append((Double(i) * 0.1, 300, 900 - CGFloat(i) * 10)) }
        // Only the last second counts: from y = 700 (t = 2.0) to 600 (t = 3.0).
        XCTAssertEqual(FilmCorner.corner(of: trail(slow), chordAt: 3.0), CGPoint(x: 300, y: 700))
    }
}
