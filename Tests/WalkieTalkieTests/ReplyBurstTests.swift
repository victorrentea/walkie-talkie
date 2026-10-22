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

    /// ☠️ (2026-10-14): whole at the start, gone at the end, every shard thrown
    /// away from the skull — left of it to the left, right of it to the right.
    func testTheSkullBlowsItApart() {
        let panel = CGSize(width: 380, height: 110), skull = CGPoint(x: 310, y: 92)
        let b = ReplyBurst(image: popUp(panel), scale: 2, panel: panel, style: .explode(from: skull))
        b.apply(0)
        let shards = (b.host.sublayers ?? []).filter { $0.contents != nil }
        XCTAssertGreaterThan(shards.count, 40)
        XCTAssertTrue(shards.allSatisfy { $0.opacity == 1 && CATransform3DIsIdentity($0.transform) })
        b.apply(0.5)
        // `position`, not `frame` — `frame` is the moved box. A shard flies a
        // little off its ray, so the side is held by nine in ten, not all.
        let left = shards.filter { $0.position.x - b.inset.x < skull.x - 40 }
        let right = shards.filter { $0.position.x - b.inset.x > skull.x + 40 }
        XCTAssertGreaterThan(Double(left.filter { $0.transform.m41 < -20 }.count), 0.9 * Double(left.count), "left of the skull flies left")
        XCTAssertGreaterThan(Double(right.filter { $0.transform.m41 > 20 }.count), 0.9 * Double(right.count), "right of the skull flies right")
        b.apply(1)
        XCTAssertTrue(shards.allSatisfy { $0.opacity == 0 }, "every shard has faded out")
    }

    /// 🔼 → over a ⚡ answer (2026-10-22): the grains go right as before, and ❓
    /// pop over them — none at the start, all up mid-way, all gone at the end.
    func testAFollowUpGoesInQuestionMarks() {
        let panel = CGSize(width: 380, height: 110)
        let b = ReplyBurst(image: popUp(panel), scale: 2, panel: panel, style: .questions)
        let layers = b.host.sublayers ?? []
        let marks = layers.filter { $0.contentsGravity == .resizeAspect }
        XCTAssertEqual(marks.count, ReplyBurst.marks)
        b.apply(0)
        XCTAssertTrue(marks.allSatisfy { $0.opacity == 0 }, "no ❓ before it starts")
        b.apply(0.4)
        XCTAssertTrue(marks.allSatisfy { $0.opacity > 0.5 }, "every ❓ is up mid-way")
        b.apply(1)
        XCTAssertTrue(layers.allSatisfy { $0.opacity == 0 }, "grains and ❓ all gone")
        XCTAssertTrue(marks.allSatisfy { $0.transform.m41 > 20 }, "the ❓ ride right too")
    }

    /// `REPLY_BURST_PNG=<dir> swift test --filter ReplyBurstTests` — the burst and
    /// the blast at six moments, over a desktop-grey background, to look at.
    func testRenderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["REPLY_BURST_PNG"] else { return }
        let panel = CGSize(width: 380, height: 110)
        try render(ReplyBurst(image: popUp(panel), scale: 2, panel: panel), "burst", dir)
        try render(ReplyBurst(image: popUp(panel), scale: 2, panel: panel, style: .explode(from: CGPoint(x: 310, y: 92))), "blast", dir)
        try render(ReplyBurst(image: popUp(panel), scale: 2, panel: panel, style: .questions), "ask", dir)
    }

    private func render(_ b: ReplyBurst, _ name: String, _ dir: String) throws {
        for u in [0.0, 0.08, 0.2, 0.4, 0.65, 0.9] {
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
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "\(name)-%03d.png", Int(u * 100))))
        }
    }
}
