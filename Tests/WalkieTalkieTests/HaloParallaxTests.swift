import XCTest
@testable import WalkieTalkie

/// The bound effect rides at half the pointer's travel (2026-11-05): the middle
/// of the screen stays the middle, and its centre never leaves the box Victor
/// drew on a 1920×1080 frame (396,274 → 1553,909).
final class HaloParallaxTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    func testTheMiddleOfTheScreenStaysPut() {
        let p = CaretHalo.parallax(of: NSPoint(x: 960, y: 540), on: screen)
        XCTAssertEqual(p, NSPoint(x: 960, y: 540))
    }

    func testAPointerInTheCornerMovesItHalfWay() {
        let p = CaretHalo.parallax(of: NSPoint(x: 1920, y: 1080), on: screen)
        XCTAssertEqual(p, NSPoint(x: 1440, y: 810))
    }

    func testAScreenLeftOfThePrimaryIsMeasuredFromItsOwnMiddle() {
        let left = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let p = CaretHalo.parallax(of: NSPoint(x: -1920, y: 0), on: left)
        XCTAssertEqual(p, NSPoint(x: -1440, y: 270))
    }

    func testTheCentreStaysInsideTheBoxHeDrew() {
        for x in stride(from: CGFloat(0), through: 1920, by: 240) {
            for y in stride(from: CGFloat(0), through: 1080, by: 135) {
                let p = CaretHalo.parallax(of: NSPoint(x: x, y: y), on: screen)
                XCTAssertTrue((396...1553).contains(p.x) && (274 - 4...909).contains(p.y), "\(p)")
            }
        }
    }
}
