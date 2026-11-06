import AppKit
import XCTest
@testable import WalkieTalkie

final class PromptAtomTests: XCTestCase {
    private let area = NSRect(x: -1920, y: 0, width: 1920, height: 1040)

    func testItStandsInThePointersScreensCorner() {
        let home = PromptAtom.home(in: area)
        XCTAssertEqual(home.minX, -1920 + 28)
        XCTAssertEqual(home.maxY, 1040 - 44)
        XCTAssertEqual(home.size, NSSize(width: 170, height: 170))
    }

    func testAtRestOnlyTheAtomCounts() {
        let atom = PromptAtom.home(in: area)
        let panel = NSRect(x: atom.minX, y: 300, width: 600, height: atom.maxY - 300)
        let zone = PromptAtom.zone(atom: atom, panel: panel, revealed: false)
        XCTAssertFalse(zone.contains(NSPoint(x: atom.maxX + 100, y: atom.midY)), "the dialog's empty rectangle is his page")
        XCTAssertTrue(zone.contains(NSPoint(x: atom.midX, y: atom.midY)))
    }

    /// A one-line dialog is shorter than the atom. Were the pointer on the atom's
    /// lower half outside the zone, the dialog would go, the atom come, the dialog
    /// come, for as long as he stood there.
    func testAShortDialogDoesNotFlickerUnderThePointerThatBroughtIt() {
        let atom = PromptAtom.home(in: area)
        let short = NSRect(x: atom.minX, y: atom.maxY - 60, width: 300, height: 60)
        let zone = PromptAtom.zone(atom: atom, panel: short, revealed: true)
        XCTAssertTrue(zone.contains(NSPoint(x: atom.midX, y: atom.minY + 5)))
    }

    func testTheStillIsBlueAndPinkAndLeavesTheCornersEmpty() throws {
        let image = try XCTUnwrap(PromptAtom.still())
        let bitmap = NSBitmapImageRep(cgImage: image)
        var blue = 0, pink = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                if c.blueComponent > 0.8, c.redComponent < 0.4 { blue += 1 }
                if c.redComponent > 0.8, c.greenComponent < 0.5 { pink += 1 }
            }
        }
        XCTAssertGreaterThan(blue, 50)
        XCTAssertGreaterThan(pink, 50)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0)
    }
}
