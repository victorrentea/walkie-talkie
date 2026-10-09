import XCTest
import AppKit
@testable import WalkieTalkie

/// The reply pop-up's burst to the right (2026-10-09): whole at the start,
/// gone at the end, and every piece moves right.
final class ReplyBurstTests: XCTestCase {

    private func popUp(_ size: CGSize, scale: CGFloat = 2) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(NSColor(white: 0.1, alpha: 0.95).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ("walkie-talkie — Haiku vs Opus" as NSString).draw(at: NSPoint(x: 44, y: size.height - 34),
            withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.6)])
        ("Yes, it works on your subscription: one Claude Code kept running answers in about 0.7 s." as NSString)
            .draw(in: NSRect(x: 12, y: 12, width: size.width - 30, height: size.height - 50),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    func testWholeAtTheStartGoneAtTheEnd() {
        let b = ReplyBurst(image: popUp(CGSize(width: 380, height: 110)), scale: 2, panel: CGSize(width: 380, height: 110))
        b.apply(0)
        let tiles = b.host.sublayers ?? []
        XCTAssertFalse(tiles.isEmpty)
        XCTAssertTrue(tiles.allSatisfy { $0.opacity == 1 && CATransform3DIsIdentity($0.transform) })
        b.apply(1)
        XCTAssertTrue(tiles.allSatisfy { $0.opacity == 0 }, "every piece has faded out")
        XCTAssertTrue(tiles.allSatisfy { $0.transform.m41 > 20 }, "every grain drifted right")
    }

    /// `REPLY_BURST_PNG=<dir> swift test --filter ReplyBurstTests` — the burst at
    /// six moments, over a desktop-grey background, to look at.
    func testRenderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["REPLY_BURST_PNG"] else { return }
        let panel = CGSize(width: 380, height: 110)
        let b = ReplyBurst(image: popUp(panel), scale: 2, panel: panel)
        for u in [0.0, 0.15, 0.3, 0.5, 0.7, 0.9] {
            b.apply(u)
            let ctx = CGContext(data: nil, width: Int(b.size.width * 2), height: Int(b.size.height * 2),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            ctx.setFillColor(NSColor(white: 0.35, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: b.size.width * 2, height: b.size.height * 2))
            ctx.scaleBy(x: 2, y: 2)
            b.host.render(in: ctx)
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "burst-%03d.png", Int(u * 100))))
        }
    }
}
