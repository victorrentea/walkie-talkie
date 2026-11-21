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

    /// The ring and the half-size badges round a wheel-dragged area (2026-11-21).
    func testRenderAreaForReview() throws {
        let screen = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let area = NSRect(x: 500, y: 400, width: 600, height: 300)
        XCTAssertEqual(FilmBorder.areaBadgeFrames(area: area, badge: FilmBorder.badgeSize(k: 0.5), screen: screen).count, 4)
        let narrow = NSRect(x: 500, y: 400, width: 120, height: 300)
        XCTAssertEqual(FilmBorder.areaBadgeFrames(area: narrow, badge: FilmBorder.badgeSize(k: 0.5), screen: screen).count, 2)
        guard let dir = ProcessInfo.processInfo.environment["FILM_BORDER_PNG"] else { return }
        let scale: CGFloat = 2
        let view = FilmBorder.areaContent(area: area, screen: screen, scale: scale)
        let ctx = CGContext(data: nil, width: Int(screen.width * scale), height: Int(screen.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: screen.width * scale, height: screen.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        view.layer!.render(in: ctx)
        try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("film-area.png"))
    }

    /// A discrete keyframe animation with as many key times as values is ignored
    /// by Core Animation — the badge and border never blinked until 2026-10-16.
    func testBlinkHasOneMoreKeyTimeThanValues() throws {
        let a = try XCTUnwrap(FilmBorder.blink(values: [1.0, 0.0], duration: 2) as? CAKeyframeAnimation)
        XCTAssertEqual(a.keyTimes?.count, (a.values?.count ?? 0) + 1)
        XCTAssertEqual(a.keyTimes?.last, 1)
    }
}
