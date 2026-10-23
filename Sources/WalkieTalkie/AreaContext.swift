import AppKit

/// **The whole screen behind a ✂️ cut-out, with the cut lit and the rest
/// greyed** (2026-10-15).
///
/// Victor: *"When you explain in the prompt preview the images that were
/// cropped, be sure to put after them a picture of the entire screen that was
/// captured … grayed out the rest and highlighting basically fully transparent
/// the area that was selected … bordered in a bit of red rectangle, so it's
/// clear that I'm sending also the entire screen."* The agent does get the whole
/// frame with every area; the cut-out alone hid that.
///
/// **A move draws both boxes and the arrow** (same evening: *"the two, red and
/// the green ones, from where to where with an arrow in the screen, in a
/// thumbnail"*): the source red, the destination green, a white arrow between
/// their centres — the colours the live overlay uses for the same gesture
/// (`AppDelegate.cropStyle`).
///
/// Drawn, never written to disk: it is the panel's picture of a token, and the
/// files the agent reads stay exactly what they were.
enum AreaContext {
    static let sourceColor = NSColor.systemRed
    static let destinationColor = NSColor.systemGreen
    static let arrowColor = NSColor.white

    /// The greyed part — dark enough that the lit box is where the eye lands,
    /// light enough that the screen is still recognisably his.
    private static let veil = NSColor(calibratedWhite: 0.08, alpha: 0.62)

    /// The corners in a `[📸N✂️x1,y1→x2,y2]` token, and the second box of a
    /// `… moved to x1,y1→x2,y2` — in the frame's pixels, top-left origin, as
    /// `ShotMarker.Token.area` wrote them. Nil for every other token.
    static func corners(in token: String) -> (box: CGRect, movedTo: CGRect?)? {
        let pair = #"(\d+),(\d+)→(\d+),(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: "✂️" + pair + "(?: moved to " + pair + ")?"),
              let m = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token))
        else { return nil }
        func number(_ i: Int) -> CGFloat? {
            Range(m.range(at: i), in: token).flatMap { Double(token[$0]) }.map { CGFloat($0) }
        }
        func rect(_ first: Int) -> CGRect? {
            guard let x1 = number(first), let y1 = number(first + 1),
                  let x2 = number(first + 2), let y2 = number(first + 3) else { return nil }
            return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
        }
        guard let box = rect(1) else { return nil }
        return (box, rect(5))
    }

    /// The frame at `size`, greyed outside the box(es), each box ringed in its
    /// colour, and the arrow for a move. `pixels` is the size the corners are
    /// measured in — the original frame's, not the copy being drawn.
    static func image(frame: NSImage, pixels: CGSize, box: CGRect, movedTo: CGRect?, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { bounds in
            frame.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: true, hints: nil)
            let boxes = [scaled(box, pixels: pixels, width: bounds.width)]
                + (movedTo.map { [scaled($0, pixels: pixels, width: bounds.width)] } ?? [])
            // Even-odd with the boxes as holes; two that overlap would cancel
            // each other's hole, so they are unioned first.
            let veilPath = NSBezierPath(rect: bounds)
            let holes = boxes.count == 2 && boxes[0].intersects(boxes[1]) ? [boxes[0].union(boxes[1])] : boxes
            holes.forEach { veilPath.appendRect($0) }
            veilPath.windingRule = .evenOdd
            veil.setFill()
            veilPath.fill()

            for (i, rect) in boxes.enumerated() {
                (i == 0 ? sourceColor : destinationColor).setStroke()
                let ring = NSBezierPath(rect: rect.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2))
                ring.lineWidth = ringWidth
                ring.stroke()
            }
            if boxes.count == 2 {
                arrow(from: CGPoint(x: boxes[0].midX, y: boxes[0].midY),
                      to: CGPoint(x: boxes[1].midX, y: boxes[1].midY))
            }
            return true
        }
    }

    /// A rectangle in the frame's pixels, in a copy of it drawn `width` wide.
    static func scaled(_ r: CGRect, pixels: CGSize, width: CGFloat) -> CGRect {
        let k = width / max(pixels.width, 1)
        return CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
    }

    /// The red (and green) rings: the box on the screen and the cut beside it.
    static let ringWidth: CGFloat = 2

    /// The space between the cut-out and the screen, where the lines cross.
    static let calloutGap: CGFloat = 32

    /// **The cut-out and the screen it came from as one picture, joined by two
    /// lines** (2026-10-15, Victor: *"two lines that go from the corner of the
    /// cropped image to the circled red rectangle on the screen thumbnail, so
    /// it's clear that it comes from that part of the screen"*). Both stand on
    /// the same bottom edge like two attachments on one line would, and the
    /// lines run from the red box's right corners to the cut's left ones — a
    /// funnel that widens out of the place it was cut from. `box` is the red box
    /// in the screen picture's own points.
    ///
    /// **The screen always on the left, the cut always after it** (2026-10-24,
    /// Victor: *"mereu ecranul complet să fie în partea stângă atunci când fac un
    /// decupaj sau o mutare, iar mereu partea mărită … în partea dreaptă a
    /// ecranului întreg"*). Supersedes 2026-10-21's *the cut sits on the side its
    /// box is nearer*: the screens line up on the left edge of the panel whatever
    /// the box, and a cut that changed sides broke that column.
    static func callout(cut: NSImage, cutSize: NSSize, screen: NSImage, box: CGRect) -> NSImage {
        let screenSize = screen.size
        let size = NSSize(width: cutSize.width + calloutGap + screenSize.width,
                          height: max(cutSize.height, screenSize.height))
        return NSImage(size: size, flipped: true) { bounds in
            let cutRect = CGRect(x: screenSize.width + calloutGap,
                                 y: bounds.height - cutSize.height,
                                 width: cutSize.width, height: cutSize.height)
            let screenRect = CGRect(x: 0,
                                    y: bounds.height - screenSize.height,
                                    width: screenSize.width, height: screenSize.height)
            cut.draw(in: cutRect, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
            screen.draw(in: screenRect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
            // The cut ringed in the same red as its box on the screen
            // (2026-10-16, Victor: *"the large image picked also surrounded by
            // a red rectangle … the small box on the big screen becomes the
            // large box at the side of it"*). Inside its edge, so the lines
            // still leave from its outer corners.
            let ring = NSBezierPath(rect: cutRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            ring.lineWidth = ringWidth
            sourceColor.setStroke()
            ring.stroke()
            let target = box.offsetBy(dx: screenRect.minX, dy: screenRect.minY)
            let cutEdge = cutRect.minX
            let boxEdge = target.maxX
            let lines = NSBezierPath()
            lines.move(to: CGPoint(x: cutEdge, y: cutRect.minY))
            lines.line(to: CGPoint(x: boxEdge, y: target.minY))
            lines.move(to: CGPoint(x: cutEdge, y: cutRect.maxY))
            lines.line(to: CGPoint(x: boxEdge, y: target.maxY))
            lines.lineWidth = 1.5
            lines.lineCapStyle = .round
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = .zero
            shadow.set()
            sourceColor.withAlphaComponent(0.9).setStroke()
            lines.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    /// A white shaft and a filled head, with a dark halo so it reads on a white
    /// page as well as a dark one.
    private static func arrow(from a: CGPoint, to b: CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 4 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(10, length * 0.4)
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        let shaft = NSBezierPath()
        shaft.move(to: a)
        shaft.line(to: base)
        shaft.lineWidth = 2
        shaft.lineCapStyle = .round
        let tip = NSBezierPath()
        tip.move(to: b)
        tip.line(to: CGPoint(x: base.x - uy * head * 0.55, y: base.y + ux * head * 0.55))
        tip.line(to: CGPoint(x: base.x + uy * head * 0.55, y: base.y - ux * head * 0.55))
        tip.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        arrowColor.setStroke()
        arrowColor.setFill()
        shaft.stroke()
        tip.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
