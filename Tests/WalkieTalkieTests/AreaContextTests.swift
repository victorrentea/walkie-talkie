import XCTest
import AppKit
@testable import WalkieTalkie

/// **The whole screen behind a ✂️ cut-out** (2026-10-15): the corners come back
/// out of the token `ShotMarker.Token.area` wrote, and the drawing greys the
/// outside, keeps the box clear and rings it red (a move's second box green).
/// `AREA_CONTEXT_PNG=<dir>` writes the two drawings for a look.
final class AreaContextTests: XCTestCase {
    func testCornersOfAnArea() {
        let token = ShotMarker.Token.area(3, CGRect(x: 900, y: 345, width: 1694, height: 229))
        let c = AreaContext.corners(in: token)
        XCTAssertEqual(c?.box, CGRect(x: 900, y: 345, width: 1694, height: 229))
        XCTAssertNil(c?.movedTo)
    }

    func testCornersOfAMove() {
        let token = ShotMarker.Token.area(1, CGRect(x: 10, y: 20, width: 30, height: 40),
                                          movedTo: CGRect(x: 100, y: 200, width: 50, height: 60))
        let c = AreaContext.corners(in: token)
        XCTAssertEqual(c?.box, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(c?.movedTo, CGRect(x: 100, y: 200, width: 50, height: 60))
    }

    func testNotAnArea() {
        XCTAssertNil(AreaContext.corners(in: "[📸2🖱️@1204:388]"))
        XCTAssertNil(AreaContext.corners(in: "[selected: \"x\"]"))
    }

    func testTheBoxIsClearTheRestGreyTheRingRed() throws {
        let rep = try draw(box: CGRect(x: 100, y: 50, width: 100, height: 60), movedTo: nil)
        // Inside the box: the frame's own white.
        XCTAssertGreaterThan(brightness(rep, 150, 80), 0.95)
        // Outside: greyed well below it.
        XCTAssertLessThan(brightness(rep, 20, 20), 0.5)
        // On the ring (just outside the top edge): red.
        let ring = color(rep, 150, 49)
        XCTAssertGreaterThan(ring.redComponent, 0.7)
        XCTAssertLessThan(ring.greenComponent, 0.5)
    }

    func testAMoveRingsTheDestinationGreen() throws {
        let rep = try draw(box: CGRect(x: 20, y: 20, width: 60, height: 40),
                           movedTo: CGRect(x: 200, y: 130, width: 60, height: 40))
        let ring = color(rep, 230, 129)
        XCTAssertGreaterThan(ring.greenComponent, 0.6)
        XCTAssertLessThan(ring.redComponent, 0.5)
        // The destination is clear too.
        XCTAssertGreaterThan(brightness(rep, 215, 140), 0.95)
    }

    func testTheCalloutJoinsTheCutToTheRedBox() throws {
        // A 60 × 40 cut, the screen 320 × 200 to its right, the box at 60,100
        // — left of the middle, so the cut stays on the left.
        let cut = NSImage(size: NSSize(width: 60, height: 40), flipped: false) { r in
            NSColor.white.setFill(); r.fill(); return true
        }
        let screen = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { r in
            NSColor.black.setFill(); r.fill(); return true
        }
        let box = CGRect(x: 60, y: 100, width: 60, height: 40)
        let image = AreaContext.callout(cut: cut, cutSize: cut.size, screen: screen, box: box)
        let gap = AreaContext.calloutGap
        XCTAssertEqual(image.size, NSSize(width: 60 + gap + 320, height: 200))
        let rep = try render(image, name: "callout.png")
        // In the gap, halfway along the upper line: red.
        let from = CGPoint(x: 60, y: 160), to = CGPoint(x: 60 + gap + 60, y: 100)
        let mid = reddest(rep, Int((from.x + 60 + gap) / 2 + 0.5),
                          Int(from.y + (to.y - from.y) * ((gap / 2) / (to.x - from.x)) + 0.5))
        XCTAssertGreaterThan(mid.redComponent, 0.6)
        XCTAssertLessThan(mid.greenComponent, 0.4)
        // The cut is ringed red, like its box on the screen.
        let edge = color(rep, 0, 180)
        XCTAssertGreaterThan(edge.redComponent, 0.6)
        XCTAssertLessThan(edge.greenComponent, 0.4)
        // The cut stands on the bottom edge.
        XCTAssertGreaterThan(brightness(rep, 30, 180), 0.95)
        XCTAssertLessThan(brightness(rep, 30, 100), 0.1)
    }

    func testABoxOnTheRightPutsTheCutOnTheRight() throws {
        // The same cut and screen, the box at 200,100 — right of the middle:
        // the screen first, the cut `calloutGap` after it.
        let cut = NSImage(size: NSSize(width: 60, height: 40), flipped: false) { r in
            NSColor.white.setFill(); r.fill(); return true
        }
        let screen = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { r in
            NSColor.black.setFill(); r.fill(); return true
        }
        let box = CGRect(x: 200, y: 100, width: 60, height: 40)
        XCTAssertTrue(AreaContext.cutsOnRight(box: box, screenWidth: 320))
        let image = AreaContext.callout(cut: cut, cutSize: cut.size, screen: screen, box: box)
        let gap = AreaContext.calloutGap
        XCTAssertEqual(image.size, NSSize(width: 60 + gap + 320, height: 200))
        let rep = try render(image, name: "callout-right.png")
        // The screen at the left edge, the cut at the right one, on the bottom.
        XCTAssertLessThan(brightness(rep, 30, 180), 0.1)
        XCTAssertGreaterThan(brightness(rep, Int(320 + gap) + 30, 180), 0.95)
        // In the gap, halfway along the upper line (box's right corner → cut's
        // left one): red.
        let from = CGPoint(x: 260, y: 100), to = CGPoint(x: 320 + gap, y: 160)
        let midX = 320 + gap / 2
        let mid = reddest(rep, Int(midX + 0.5),
                          Int(from.y + (to.y - from.y) * ((midX - from.x) / (to.x - from.x)) + 0.5))
        XCTAssertGreaterThan(mid.redComponent, 0.6)
        XCTAssertLessThan(mid.greenComponent, 0.4)
        // The cut is ringed red at its right edge.
        let edge = color(rep, Int(320 + gap + 59), 180)
        XCTAssertGreaterThan(edge.redComponent, 0.6)
    }

    // MARK: -

    private func render(_ image: NSImage, name: String) throws -> NSBitmapImageRep {
        let w = Int(image.size.width), h = Int(image.size.height)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        if let dir = ProcessInfo.processInfo.environment["AREA_CONTEXT_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return rep
    }

    /// A white 320 × 200 frame drawn at 1:1, so a point is a pixel.
    private func draw(box: CGRect, movedTo: CGRect?) throws -> NSBitmapImageRep {
        let frame = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { r in
            NSColor.white.setFill(); r.fill(); return true
        }
        let image = AreaContext.image(frame: frame, pixels: CGSize(width: 320, height: 200),
                                      box: box, movedTo: movedTo, size: NSSize(width: 320, height: 200))
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 200,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 320, height: 200))
        NSGraphicsContext.restoreGraphicsState()
        if let dir = ProcessInfo.processInfo.environment["AREA_CONTEXT_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            let name = movedTo == nil ? "area.png" : "move.png"
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return rep
    }

    /// `x, y` from the top-left, like the corners.
    private func color(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        (rep.colorAt(x: x, y: y) ?? .clear).usingColorSpace(.deviceRGB) ?? .clear
    }
    /// The reddest of the pixel and its two vertical neighbours: a 1.5 pt
    /// slanted line need not cover the one pixel its maths rounds to.
    private func reddest(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        (y - 1...y + 1).map { color(rep, x, $0) }.max { $0.redComponent < $1.redComponent }!
    }
    private func brightness(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let c = color(rep, x, y)
        return (c.redComponent + c.greenComponent + c.blueComponent) / 3
    }
}
