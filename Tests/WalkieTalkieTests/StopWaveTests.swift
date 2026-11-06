import XCTest
@testable import WalkieTalkie

/// The stop's wave (2026-11-05): it starts at the pointer, it keeps its thickness,
/// and it ends off the screen, wherever the pointer was.
final class StopWaveTests: XCTestCase {

    private let screen = NSRect(x: 1728, y: 100, width: 1920, height: 1080)

    func testTheReachIsTheFarthestCorner() {
        let corner = NSPoint(x: screen.minX, y: screen.minY)
        XCTAssertEqual(StopWave.reach(from: corner, in: screen), hypot(1920, 1080), accuracy: 0.01)
        let middle = NSPoint(x: screen.midX, y: screen.midY)
        XCTAssertEqual(StopWave.reach(from: middle, in: screen), hypot(960, 540), accuracy: 0.01)
    }

    func testEveryLocationStaysInsideTheGradientInOrder() {
        let radius = StopWave.radius(reach: 1100)
        for front in stride(from: CGFloat(8), through: radius, by: 40) {
            let stops = StopWave.locations(front: front, radius: radius)
            XCTAssertGreaterThanOrEqual(stops.first!, 0)
            XCTAssertLessThanOrEqual(stops.last!, 1.000001)
            XCTAssertEqual(stops, stops.sorted())
        }
    }

    func testTheBandOpensAtThePointerThenKeepsItsThickness() {
        let radius: CGFloat = 1500
        let opening = StopWave.locations(front: 100, radius: radius)
        XCTAssertEqual(opening.first!, 0, accuracy: 0.0001)
        let travelling = StopWave.locations(front: 1000, radius: radius)
        XCTAssertEqual((travelling.last! - travelling.first!) * radius, StopWave.band, accuracy: 0.01)
    }

    func testAtTheEndTheInnerEdgeHasLeftTheScreen() {
        let reach: CGFloat = 1100
        let radius = StopWave.radius(reach: reach)
        let stops = StopWave.locations(front: radius, radius: radius)
        XCTAssertEqual(stops.first! * radius, reach, accuracy: 0.01)
    }

    // MARK: - The wipe (2026-11-06)

    func testThePictureIsGoneBehindTheCrestAndWholeAtTheOuterEdge() {
        XCTAssertEqual(StopWave.left(at: 0), 0)
        XCTAssertEqual(StopWave.left(at: 0.82), 0)
        XCTAssertGreaterThan(StopWave.left(at: 0.92), 0)
        XCTAssertLessThan(StopWave.left(at: 0.92), 1)
        XCTAssertEqual(StopWave.left(at: 1), 1)
    }

    private func clearing(_ frame: NSRect, from point: NSPoint) -> (CFTimeInterval, CFTimeInterval) {
        let radius = StopWave.radius(reach: StopWave.reach(from: point, in: screen))
        let duration = StopWave.duration(radius: radius)
        return (StopWave.clearing(frame, from: point, radius: radius, duration: duration), duration)
    }

    func testALargerPictureIsClearedLater() {
        let point = NSPoint(x: screen.midX, y: screen.midY)
        let small = NSRect(x: point.x - 100, y: point.y - 100, width: 200, height: 200)
        let large = NSRect(x: point.x - 500, y: point.y - 500, width: 1000, height: 1000)
        XCTAssertLessThan(clearing(small, from: point).0, clearing(large, from: point).0)
    }

    func testTheWholeScreenIsClearedBeforeTheRingHasLeftIt() {
        let point = NSPoint(x: screen.minX + 100, y: screen.minY + 100)
        let (cleared, duration) = clearing(screen, from: point)
        XCTAssertGreaterThan(cleared, 0)
        XCTAssertLessThanOrEqual(cleared, duration)
    }

    /// The front is fast off the pointer: half the way takes far less than half the time.
    func testTheClearingRunsTheEaseBackwards() {
        let point = NSPoint(x: screen.minX, y: screen.minY)
        let radius = StopWave.radius(reach: StopWave.reach(from: point, in: screen))
        let half = NSRect(x: screen.minX, y: screen.minY, width: radius * 0.4, height: 1)
        let cleared = StopWave.clearing(half, from: point, radius: radius, duration: 1)
        XCTAssertLessThan(cleared, 0.35)
    }

    /// A picture outside the wave's reach cannot be waited for past the wave's end.
    func testNothingWaitsPastTheWave() {
        let far = NSRect(x: screen.maxX + 4000, y: screen.minY, width: 500, height: 500)
        let (cleared, duration) = clearing(far, from: NSPoint(x: screen.midX, y: screen.midY))
        XCTAssertEqual(cleared, duration, accuracy: 0.001)
    }
}
