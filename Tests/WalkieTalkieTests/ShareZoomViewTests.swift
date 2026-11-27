import XCTest
@testable import WalkieTalkie

/// The wheel-drag box under Victor Mac' ⌥⇧ zoom: drawn in desktop points, carried onto
/// the glass the frame is a picture of (2026-11-27).
final class ShareZoomViewTests: XCTestCase {

    private let retina = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let asus = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    /// 2× on the top-right quarter of the Retina (Cocoa y grows up).
    private var quarter: CGRect { CGRect(x: 864, y: 558.5, width: 864, height: 558.5) }

    func testNoZoomLeavesTheBoxAlone() {
        let box = CGRect(x: 100, y: 200, width: 300, height: 40)
        XCTAssertEqual(ShareZoomView.carry(box, slice: nil, screen: retina), box)
    }

    func testTheBoxIsMagnifiedAboutTheSlice() {
        let box = CGRect(x: 964, y: 658.5, width: 100, height: 50)
        XCTAssertEqual(ShareZoomView.carry(box, slice: quarter, screen: retina),
                       CGRect(x: 200, y: 200, width: 200, height: 100))
    }

    func testTheSliceCornerIsTheScreenCorner() {
        let box = CGRect(x: 864, y: 558.5, width: 864, height: 558.5)
        XCTAssertEqual(ShareZoomView.carry(box, slice: quarter, screen: retina), retina)
    }

    /// Part of the box scrolled off the glass during the drag: only what is on it stays.
    func testWhatIsOffTheGlassIsCut() {
        let box = CGRect(x: 764, y: 658.5, width: 200, height: 50)
        XCTAssertEqual(ShareZoomView.carry(box, slice: quarter, screen: retina),
                       CGRect(x: 0, y: 200, width: 200, height: 100))
    }

    /// The zoom is on the Retina, the box was drawn on the ASUS: that frame is the desktop.
    func testAZoomOnAnotherScreenLeavesTheBoxAlone() {
        let box = CGRect(x: -1500, y: 300, width: 200, height: 100)
        XCTAssertEqual(ShareZoomView.carry(box, slice: quarter, screen: asus), box)
    }

    func testTheSliceOnTheLeftScreenUsesItsOwnOrigin() {
        let slice = CGRect(x: -1920 + 480, y: 270, width: 960, height: 540)  // 2×, centred
        let box = CGRect(x: -1440 + 10, y: 270 + 10, width: 50, height: 20)
        XCTAssertEqual(ShareZoomView.carry(box, slice: slice, screen: asus),
                       CGRect(x: -1920 + 20, y: 20, width: 100, height: 40))
    }

    /// A box wholly off the glass keeps its desktop place rather than vanishing.
    func testABoxWhollyOffTheGlassIsLeftAlone() {
        let box = CGRect(x: 10, y: 10, width: 50, height: 50)
        XCTAssertEqual(ShareZoomView.carry(box, slice: quarter, screen: retina), box)
    }

    func testANoteWithTheSliceIsReadAndAnEmptyOneClearsIt() {
        ShareZoomView.note(["x": 1.0, "y": 2.0, "vx": 864.0, "vy": 558.5, "vw": 864.0, "vh": 558.5])
        XCTAssertEqual(ShareZoomView.current(), quarter)
        ShareZoomView.note(nil)
        XCTAssertNil(ShareZoomView.current())
    }

    /// An older Victor Mac publishes the cursor alone: no slice, nothing carried.
    func testACursorOnlyNoteIsNoSlice() {
        ShareZoomView.note(["x": 1.0, "y": 2.0])
        XCTAssertNil(ShareZoomView.current())
    }

    func testASilentChannelIsNoZoom() {
        ShareZoomView.note(["x": 1.0, "y": 2.0, "vx": 864.0, "vy": 558.5, "vw": 864.0, "vh": 558.5])
        XCTAssertNil(ShareZoomView.current(now: CFAbsoluteTimeGetCurrent() + 2))
        ShareZoomView.note(nil)
    }
}
