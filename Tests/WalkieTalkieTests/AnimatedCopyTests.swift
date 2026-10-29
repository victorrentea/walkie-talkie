import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import WalkieTalkie

/// **A copied GIF plays in the prompt preview** (2026-10-30): the `src` comes out
/// of Chrome's HTML, the GIF sits beside the JPEG, and a label holding its
/// picture draws a different frame when repainted later. `WT_GIF_URL=<url>`
/// also fetches a real one.
final class AnimatedCopyTests: XCTestCase {

    /// Two 8×8 frames, red then blue, 0.1 s each.
    private func twoFrameGIF() -> Data {
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil)!
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            CGImageDestinationAddImage(dest, ctx.makeImage()!,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testSourceOutOfChromesHTML() {
        let html = #"<meta charset='utf-8'><img src="https://upload.wikimedia.org/a/Blinking_Stop_hand.gif?x=1&amp;y=2" alt="Stop"/>"#
        let src = AnimatedCopy.imageSource(inHTML: html)
        XCTAssertEqual(src, "https://upload.wikimedia.org/a/Blinking_Stop_hand.gif?x=1&y=2")
        XCTAssertTrue(AnimatedCopy.mayBeGIF(src!))
        XCTAssertFalse(AnimatedCopy.mayBeGIF("https://encrypted-tbn0.gstatic.com/images?q=tbn:abc"))
        XCTAssertNil(AnimatedCopy.imageSource(inHTML: "<b>no picture</b>"))
    }

    func testDataURLAndStillsAreTold() {
        let gif = twoFrameGIF()
        XCTAssertTrue(AnimatedCopy.isAnimated(gif))
        XCTAssertEqual(AnimatedCopy.fetch("data:image/gif;base64," + gif.base64EncodedString()), gif)
        XCTAssertFalse(AnimatedCopy.isAnimated(Data("not a gif".utf8)))
    }

    func testTheGIFSitsBesideTheJPEG() {
        XCTAssertEqual(AnimatedCopy.gifPath(beside: "/d/screenshot-3-original.jpg"), "/d/screenshot-3.gif")
        XCTAssertEqual(AnimatedCopy.gifPath(beside: "/d/screenshot-3-800px.jpg"), "/d/screenshot-3.gif")
    }

    func testFilmLoopsOnItsDelays() throws {
        let path = NSTemporaryDirectory() + "animated-copy-\(UUID()).gif"
        try twoFrameGIF().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let film = try XCTUnwrap(AnimatedCopy.Film(path: path, maxPixels: 16))
        XCTAssertEqual(film.duration, 0.2, accuracy: 0.001)
        XCTAssertTrue(film.frame(at: 0.05) === film.frames[0])
        XCTAssertTrue(film.frame(at: 0.15) === film.frames[1])
        XCTAssertTrue(film.frame(at: 0.25) === film.frames[0])
    }

    /// The panel's words are a label with the picture as an attachment: a
    /// repaint 0.1 s later must show the other frame, or the GIF stands still.
    func testALabelRepaintsTheNextFrame() throws {
        let path = NSTemporaryDirectory() + "animated-copy-\(UUID()).gif"
        try twoFrameGIF().write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let size = NSSize(width: 40, height: 40)
        let picture = AreaContext.framed(try XCTUnwrap(AnimatedCopy.picture(gif: path, size: size)), size: size)
        picture.cacheMode = .never
        let attachment = NSTextAttachment()
        attachment.image = picture
        attachment.bounds = NSRect(origin: .zero, size: size)
        let label = NSTextField(wrappingLabelWithString: "")
        label.attributedStringValue = NSAttributedString(attachment: attachment)
        label.frame = NSRect(x: 0, y: 0, width: 60, height: 60)

        func centre() -> (r: CGFloat, b: CGFloat) {
            let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds)!
            label.cacheDisplay(in: label.bounds, to: rep)
            var best: (r: CGFloat, b: CGFloat) = (0, 0)
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if c.redComponent + c.blueComponent > best.r + best.b { best = (c.redComponent, c.blueComponent) }
                }
            }
            return best
        }
        var seen: Set<String> = []
        for _ in 0..<4 {
            let c = centre()
            seen.insert(c.r > c.b ? "red" : "blue")
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(seen, ["red", "blue"], "both frames drawn across four repaints 0.1 s apart")
    }

    func testFetchesARealOne() throws {
        guard let url = ProcessInfo.processInfo.environment["WT_GIF_URL"] else { throw XCTSkip("WT_GIF_URL unset") }
        let data = try XCTUnwrap(AnimatedCopy.fetch(url))
        XCTAssertTrue(AnimatedCopy.isAnimated(data))
    }
}
