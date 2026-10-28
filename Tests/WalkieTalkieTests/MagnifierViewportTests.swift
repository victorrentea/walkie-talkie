import XCTest
@testable import WalkieTalkie

/// The magnifier's visible rectangle from SkyLight's centre + factor — the shape
/// a shot is cut to while the full-screen magnifier is zoomed in (2026-10-28).
final class MagnifierViewportTests: XCTestCase {

    private let asus = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    func testAtOneToOneThereIsNoViewport() {
        XCTAssertNil(MagnifierViewport.visible(display: asus, center: CGPoint(x: -960, y: 540), factor: 1))
        XCTAssertNil(MagnifierViewport.visible(display: asus, center: CGPoint(x: -960, y: 540), factor: 1.005))
    }

    /// Measured: 2× asked around (−1900, 20), SkyLight answered (−1440, 270).
    func testTheMeasuredCornerReadingIsTheTopLeftQuarter() {
        XCTAssertEqual(MagnifierViewport.visible(display: asus, center: CGPoint(x: -1440, y: 270), factor: 2),
                       CGRect(x: -1920, y: 0, width: 960, height: 540))
    }

    /// A centre read mid-animation still yields a rectangle on the display.
    func testACentreTooCloseToTheEdgeIsClamped() {
        XCTAssertEqual(MagnifierViewport.visible(display: asus, center: CGPoint(x: -10, y: 1075), factor: 4),
                       CGRect(x: -480, y: 810, width: 480, height: 270))
    }

    func testAppKitFlipsAgainstThePrimary() {
        let retinaTop = CGRect(x: 100, y: 50, width: 864, height: 558)
        XCTAssertEqual(MagnifierViewport.appKit(retinaTop, primaryHeight: 1117),
                       CGRect(x: 100, y: 509, width: 864, height: 558))
    }
}
