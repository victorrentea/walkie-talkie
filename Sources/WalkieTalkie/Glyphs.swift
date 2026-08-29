import AppKit

/// The two marks the chip draws for itself: a map pin and a folder.
///
/// **Drawn, not typed.** The obvious versions of both are emoji — 📍 and 📁 —
/// and neither is the thing Victor asked for. 📍 is `ROUND PUSHPIN`, which Apple
/// renders as a pin stuck into a surface at an angle, not the teardrop marker
/// everyone means by "a pin on a map"; and an emoji is whatever the installed
/// font decides, at whatever weight and hue it likes, with a baseline that
/// refuses to line up with anything beside it.
///
/// **They also have to be images, not text, for a mechanical reason.** These
/// chip labels are `NSTextField(labelWithString:)`, where
/// `attributedStringValue` silently renders *only* the emoji and drops every
/// other glyph to fully transparent — that is what once left the chip showing a
/// robot head and no session name, and it is why the ⌘-pick row already carries
/// Chrome's icon as an `NSImageView` rather than inline. So a glyph in one of
/// these rows is an image in a box of its own, and these are that image.
///
/// Both are traced from references Victor supplied, by their proportions rather
/// than by eye, so they can be re-derived if the size changes.
enum Glyphs {

    /// The teardrop map marker: a disc with a hole, drawn out to a point below.
    ///
    /// Proportions from the reference: the head is tangent to the top, its radius
    /// is `0.348 × height` (so the whole mark is `0.696 × height` wide), the hole
    /// is `0.196 × height`, and the tip sits on the vertical centre line at the
    /// bottom. The sides are the two **tangents** from that tip to the head,
    /// which is what makes the join seamless — a triangle merely touching a
    /// circle shows its corners at any size worth looking at.
    static func mapPin(height: CGFloat, fill: NSColor = .systemRed) -> NSImage {
        let width = height * 0.696
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let radius = height * 0.348
            // AppKit counts y up, the proportions above count it down from the top.
            let centre = CGPoint(x: width / 2, y: height - radius)
            let tip = CGPoint(x: width / 2, y: 0)

            // Where the tangents touch: with the tip at distance d below the
            // centre, the touch points sit at angle acos(R/d) either side of the
            // line joining them.
            let d = centre.y - tip.y
            guard d > radius else { return false }
            let phi = acos(radius / d)
            let left = -CGFloat.pi / 2 - phi      // measured from the +x axis
            let right = -CGFloat.pi / 2 + phi

            ctx.setFillColor(fill.cgColor)
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: centre.x + radius * cos(right),
                                    y: centre.y + radius * sin(right)))
            // Anticlockwise from the right touch point, over the top, to the left
            // one — the long way round, which is the body of the head.
            ctx.addArc(center: centre, radius: radius,
                       startAngle: right, endAngle: left + 2 * .pi, clockwise: false)
            ctx.closePath()
            ctx.fillPath()

            // The hole. Punched with `.clear` rather than filled white: the chip
            // rides over a terminal, an editor, a photograph, and a white disc
            // would be a white disc on all of them. Cleared, it shows whatever is
            // behind — which is what a hole is.
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: centre.x - height * 0.196,
                                       y: centre.y - height * 0.196,
                                       width: height * 0.392, height: height * 0.392))
            ctx.setBlendMode(.normal)
            return true
        }
    }

    /// An emoji as an **image, trimmed to its ink** and fitted to a square of
    /// `ink` points.
    ///
    /// Set as text, an emoji cannot be lined up with anything. Apple Color Emoji
    /// carries a wide advance with the ink sitting off-centre inside it —
    /// measured on this card, a 15pt 🔴 in a 20pt column drew its ink at x 17…31
    /// while Chrome's 16pt icon in the same column drew at 15…28. Left-align,
    /// centre, either way two glyphs that are supposed to be a column start two
    /// pixels apart and read as two different sizes, because the size you see is
    /// the ink and the size you can lay out is the advance.
    ///
    /// So the glyph is rendered big, its alpha bounding box is measured, and the
    /// result is drawn to fill a square of exactly the size every other icon on
    /// the card gets. After that all four glyphs are images of one size in one
    /// box, and lining them up is arithmetic rather than an eye test.
    ///
    /// Rendered once per glyph at launch — `colorAt` over a 100×100 bitmap is
    /// not something to do while following the cursor.
    static func emoji(_ character: String, ink: CGFloat) -> NSImage {
        let size: CGFloat = 72
        let inset: CGFloat = 8
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size)]
        let string = NSAttributedString(string: character, attributes: attributes)
        let drawn = string.size()
        let w = Int(ceil(drawn.width + inset * 2)), h = Int(ceil(drawn.height + inset * 2))

        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSImage() }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        string.draw(at: NSPoint(x: inset, y: inset))
        NSGraphicsContext.restoreGraphicsState()

        // The alpha bounding box, in the bitmap's own top-down pixels.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return NSImage() }

        // Back to AppKit's y-up coordinates, where the string will be redrawn.
        let box = NSRect(x: CGFloat(minX), y: CGFloat(h - 1 - maxY),
                         width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
        let scale = ink / max(box.width, box.height)

        return NSImage(size: NSSize(width: ink, height: ink), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Place the *ink* in the middle of the square: scale first, then
            // shift by wherever the ink turned out to be inside the render.
            ctx.translateBy(x: (ink - box.width * scale) / 2 - box.minX * scale,
                            y: (ink - box.height * scale) / 2 - box.minY * scale)
            ctx.scaleBy(x: scale, y: scale)
            string.draw(at: NSPoint(x: inset, y: inset))
            return true
        }
    }

}

extension Glyphs {

    /// Which buttons of the mouse the drawing calls out, in red.
    struct Buttons: OptionSet {
        let rawValue: Int
        /// The left button — the whole left half of the front deck.
        static let left = Buttons(rawValue: 1 << 0)
        static let right = Buttons(rawValue: 1 << 1)
        /// The wheel, in its notch between the two.
        static let wheel = Buttons(rawValue: 1 << 2)
        /// The rear side button on the left flank — mouse 4, the one LinearMouse
        /// types Return with and the one the shutter borrows.
        static let back = Buttons(rawValue: 1 << 3)
        /// The forward side button, ahead of it — mouse 5.
        static let forward = Buttons(rawValue: 1 << 4)
    }

    /// **His actual mouse, seen from above, with the buttons the gesture needs
    /// coloured in.**
    ///
    /// The overlay used to say a gesture with emoji: 🖱️ for the device and a
    /// small ▲/🔽 tucked beside it for which part of it to press. That is a
    /// rebus — it needs a legend of its own, it depends on whatever Apple Color
    /// Emoji renders this year, and it cannot say *hold this one while you click
    /// that one*, which is now a gesture the app has. A drawing can: two buttons
    /// red at once is the same picture with one more region filled.
    ///
    /// **Traced from the wireframe Victor supplied**, not drawn by eye. The
    /// outline below is 33 rows sampled off that PNG by a one-off program —
    /// left and right edge per row, normalised — which is why the silhouette is
    /// the real **Logitech Signature M650 L** on his desk
    /// (`~/.config/linearmouse/linearmouse.json` names it): narrow round nose,
    /// the thumb swell low on the left, widest at 72% back. The interior
    /// landmarks come off the same trace: the central island the wheel sits in
    /// spans u 0.382…0.620, the wheel itself 0.456…0.548.
    ///
    /// That island is what makes the picture work at 16pt. The two buttons are
    /// not halves of a blob split down the middle — they are the areas *either
    /// side of the island*, so filling one red is a shape the eye already sees
    /// the boundary of.
    ///
    /// Height is the size that is asked for and the width follows from the
    /// traced proportion, so the result is a tall image in a square icon box
    /// and lines up with the emoji-derived glyphs beside it.
    static func mouse(height: CGFloat,
                      pressed: Buttons = [],
                      body: NSColor = .secondaryLabelColor,
                      highlight: NSColor = .systemRed) -> NSImage {
        let width = (height * Self.mouseAspect).rounded()
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The trace counts v **down** from the nose; AppKit counts y up. One
            // conversion here beats flipping every number in the table.
            func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: u * width, y: (1 - v) * height)
            }

            // Down the right edge, up the left — the sampled rows, closed into a
            // loop and smoothed through their own midpoints. Straight segments
            // would be invisible at 16pt and faceted at 120; the quadratics cost
            // nothing and are right at both.
            var points = Self.mouseOutline.map { p($0.right, $0.v) }
            points += Self.mouseOutline.reversed().map { p($0.left, $0.v) }
            let outline = CGMutablePath()
            outline.move(to: CGPoint(x: (points[points.count - 1].x + points[0].x) / 2,
                                     y: (points[points.count - 1].y + points[0].y) / 2))
            for (i, point) in points.enumerated() {
                let next = points[(i + 1) % points.count]
                outline.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2),
                                     control: point)
            }
            outline.closeSubpath()

            func stadium(_ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat) -> CGPath {
                let r = (u1 - u0) * width / 2
                return CGPath(roundedRect: CGRect(x: u0 * width, y: (1 - v1) * height,
                                                  width: (u1 - u0) * width, height: (v1 - v0) * height),
                              cornerWidth: r, cornerHeight: r, transform: nil)
            }
            let island = stadium(0.382, 0.085, 0.620, 0.560)
            // Drawn a shade wider than the trace (0.456…0.548) and a shade
            // longer. The wireframe's wheel is a tenth of the body's width, which
            // is honest and, filled red at icon size, is a mark two pixels across
            // that reads as a smudge. Victor's words: *abia se vede că e roșu*.
            let wheel = stadium(0.437, 0.125, 0.567, 0.310)

            // A wash inside the outline. The wireframe itself is pure line art,
            // which is right on paper and not on this card: the chip floats over
            // a terminal, an editor, a photograph, and an unfilled outline is a
            // few grey strokes with somebody's code showing through them.
            ctx.addPath(outline)
            ctx.setFillColor(body.withAlphaComponent(0.16).cgColor)
            ctx.fillPath()

            // **A button is the area beside the island, not a half of the body.**
            // Above the island the two meet along the nose seam at u 0.50; below
            // it they stop where the island stops. Filled inside a clip of the
            // silhouette, so the red ends at the mouse's own edge.
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            ctx.setFillColor(highlight.cgColor)
            for (on, sign) in [(pressed.contains(.left), CGFloat(-1)), (pressed.contains(.right), CGFloat(1))] where on {
                let inner: CGFloat = 0.5 + sign * 0.118   // the island's near wall
                let deck = CGMutablePath()
                deck.move(to: p(0.5, -0.05))
                deck.addLine(to: p(0.5, 0.085))
                deck.addLine(to: p(inner, 0.085))
                deck.addLine(to: p(inner, 0.560))
                deck.addLine(to: p(0.5 + sign * 0.7, 0.560))
                deck.addLine(to: p(0.5 + sign * 0.7, -0.05))
                deck.closeSubpath()
                ctx.addPath(deck)
                ctx.fillPath()
            }
            ctx.restoreGState()

            // **A pressed part is outlined in its own colour, not in the body's.**
            // These are small enough that the outline is a large fraction of the
            // mark: a grey ring around a red wheel renders, at 16pt, as a grey
            // wheel. Rendered at both sizes and looked at — that is what it did.
            func part(_ path: CGPath, on: Bool, line: CGFloat) {
                ctx.addPath(path)
                ctx.setFillColor(on ? highlight.cgColor : body.withAlphaComponent(0.22).cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(on ? highlight.cgColor : body.cgColor)
                ctx.setLineWidth(line)
                ctx.strokePath()
            }

            let line = max(0.8, height * 0.024)
            ctx.setLineCap(.round)

            // The seam between the two buttons, from the nose down to the island.
            ctx.setStrokeColor(body.cgColor)
            ctx.setLineWidth(line)
            ctx.move(to: p(0.501, 0.0))
            ctx.addLine(to: p(0.501, 0.09))
            ctx.strokePath()

            // **The island answers for the wheel.** When the wheel is the button
            // being named, the well it sits in is outlined in red too — a red
            // pill inside a red capsule is a mark the size of the island, where
            // the wheel alone is the size of the wheel. It is not a lie about
            // which button is pressed: the island *is* where the wheel is.
            let wheelPressed = pressed.contains(.wheel)
            ctx.addPath(island)
            ctx.setFillColor(body.withAlphaComponent(0.22).cgColor)
            ctx.fillPath()
            ctx.addPath(island)
            ctx.setStrokeColor(wheelPressed ? highlight.cgColor : body.cgColor)
            ctx.setLineWidth(wheelPressed ? line * 1.6 : line)
            ctx.strokePath()

            part(wheel, on: wheelPressed, line: max(0.5, height * 0.020))

            // The two thumb buttons, as the slanted pair they are on the flank —
            // drawn only when one of them is the button being named. At 16pt two
            // extra marks on every mouse in the card is texture, not information.
            if pressed.contains(.back) || pressed.contains(.forward) {
                ctx.setLineWidth(max(1.0, width * 0.11))
                for (on, from, to) in [(pressed.contains(.forward), (CGFloat(0.055), CGFloat(0.340)), (CGFloat(0.075), CGFloat(0.445))),
                                       (pressed.contains(.back), (CGFloat(0.088), CGFloat(0.470)), (CGFloat(0.130), CGFloat(0.580)))] {
                    ctx.setStrokeColor(on ? highlight.cgColor : body.withAlphaComponent(0.55).cgColor)
                    ctx.move(to: p(from.0, from.1))
                    ctx.addLine(to: p(to.0, to.1))
                    ctx.strokePath()
                }
            }

            ctx.addPath(outline)
            ctx.setStrokeColor(body.cgColor)
            ctx.setLineWidth(line)
            ctx.strokePath()

            return true
        }
    }

    /// Width over height, from the traced wireframe's bounding box.
    private static let mouseAspect: CGFloat = 0.568

    /// The silhouette, 33 rows off the wireframe: how far in the left and right
    /// edges sit at each fraction of the way down. Machine-read, so the taper at
    /// the nose and the widest point at v 0.72 are the real mouse's and not a
    /// memory of it.
    ///
    /// Two corrections to the raw trace, both because a min-x-per-row scan reads
    /// *ink*, not *body*: the thumb buttons stick out past the left edge in the
    /// drawing and came back as a notch at v 0.34…0.47, so that stretch is
    /// interpolated across; and the whole column is 3-tap smoothed, which costs
    /// nothing at 16pt and stops the flanks looking chewed at 150.
    private static let mouseOutline: [(v: CGFloat, left: CGFloat, right: CGFloat)] = [
        (0.000, 0.5106, 0.5159), (0.031, 0.2960, 0.7116), (0.062, 0.1825, 0.8188),
        (0.094, 0.1336, 0.8680), (0.125, 0.1015, 0.9008), (0.156, 0.0797, 0.9230),
        (0.188, 0.0655, 0.9368), (0.219, 0.0586, 0.9435), (0.250, 0.0569, 0.9451),
        (0.281, 0.0575, 0.9444), (0.312, 0.0587, 0.9425), (0.344, 0.0589, 0.9392),
        (0.375, 0.0584, 0.9352), (0.406, 0.0578, 0.9319), (0.438, 0.0573, 0.9302),
        (0.469, 0.0567, 0.9312), (0.500, 0.0562, 0.9365), (0.531, 0.0524, 0.9461),
        (0.562, 0.0423, 0.9580), (0.594, 0.0298, 0.9706), (0.625, 0.0188, 0.9822),
        (0.656, 0.0099, 0.9914), (0.688, 0.0036, 0.9974), (0.719, 0.0013, 0.9990),
        (0.750, 0.0040, 0.9964), (0.781, 0.0119, 0.9891), (0.812, 0.0261, 0.9755),
        (0.844, 0.0483, 0.9540), (0.875, 0.0794, 0.9236), (0.906, 0.1220, 0.8816),
        (0.938, 0.1812, 0.8217), (0.969, 0.2883, 0.7129), (1.000, 0.4669, 0.5344),
    ]

}
