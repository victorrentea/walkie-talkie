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
}
