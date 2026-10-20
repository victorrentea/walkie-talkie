import AppKit
import XCTest
@testable import WalkieTalkie

final class FilmBorderTests: XCTestCase {
    /// `FILM_BORDER_PNG=<dir> swift test --filter FilmBorderTests` — the recording
    /// badges in the four corners, dots lit, over a light and a dark page.
    func testRenderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["FILM_BORDER_PNG"] else { return }
        let size = CGSize(width: 1728, height: 1117), scale: CGFloat = 2
        let view = FilmBorder.content(size: size, menuBar: 33, scale: scale)
        for (name, grey) in [("light", 0.95), ("dark", 0.12)] {
            let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            ctx.setFillColor(NSColor(white: grey, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
            ctx.scaleBy(x: scale, y: scale)
            view.layer!.render(in: ctx)
            // The whole display: a badge in each of the four corners.
            try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("film-badge-\(name).png"))
        }
    }

    /// A discrete keyframe animation with as many key times as values is ignored
    /// by Core Animation — the badge and border never blinked until 2026-10-16.
    func testBlinkHasOneMoreKeyTimeThanValues() throws {
        let a = try XCTUnwrap(FilmBorder.blink(values: [1.0, 0.0], duration: 2) as? CAKeyframeAnimation)
        XCTAssertEqual(a.keyTimes?.count, (a.values?.count ?? 0) + 1)
        XCTAssertEqual(a.keyTimes?.last, 1)
    }
}
