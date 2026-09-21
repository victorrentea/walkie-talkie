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

    /// A small filled badge with a word written into it — `HQ`, the mark that
    /// says this dictation now has enough speech behind it to transcribe well.
    ///
    /// **Drawn rather than typed, for this file's own reason**: it rides an
    /// `NSTextField` row that carries a halo, where an inline glyph turns every
    /// other character transparent, and a word set in the row's own font would
    /// read as another word in the sentence rather than as a label stuck on it.
    /// A filled capsule is the one shape that says *tag* with no text at all.
    ///
    /// Sized off the height it is given, so it stays in proportion if the row's
    /// ink ever changes: the corner radius is half the height (a capsule), the
    /// word is bold at `0.66 ×` it, and the side padding is `0.36 ×` it.
    static func tag(_ word: String, height: CGFloat, fill: NSColor = .systemBlue,
                    ink: NSColor = .white) -> NSImage {
        let font = NSFont.systemFont(ofSize: max(7, (height * 0.66).rounded()), weight: .bold)
        let text = NSAttributedString(string: word, attributes: [.font: font,
                                                                .foregroundColor: ink])
        let drawn = text.size()
        let width = (ceil(drawn.width) + (height * 0.36).rounded() * 2).rounded()
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            // Centred on the ink the font reports rather than on its line box:
            // a capital-only word sits high in a line box built for descenders.
            text.draw(at: NSPoint(x: ((rect.width - drawn.width) / 2).rounded(),
                                  y: ((rect.height - drawn.height) / 2).rounded()))
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

    /// **The same mouse from the side, which is the only view its thumb buttons
    /// have** (2026-09-22).
    ///
    /// `mouse(height:)` above is the view from over the desk, and from up there
    /// the two side buttons are edge-on: the drawing shows them as two short
    /// slanted strokes on the left flank, drawn only when one of them is the
    /// button being named, because at 16pt two extra marks on every mouse in
    /// the card are texture rather than information. That is the honest
    /// rendering of a button the viewpoint cannot see — and it is no use at all
    /// on a page whose job is *which button is this*. Victor asked for the
    /// picture that answers it: *"caută o schiță în care să se vadă și butoanele
    /// laterale."*
    ///
    /// **Traced from Logitech's own schematic**, the way the top view was traced
    /// from the wireframe: the Signature M650 user manual's *Product Overview*
    /// figure carries three views, and the third is the left flank with callout
    /// **8 — Back/Forward buttons** pointing straight at the pair. The silhouette
    /// below is 33 columns sampled off that render by a one-off program (nose at
    /// u 0, tail at u 1, `top` and `bottom` counted **down** from the figure's
    /// own bounding box), so the long low nose, the palm peak at u 0.59 and the
    /// short steep tail are the real mouse's proportions and not a memory of
    /// them. The bounding box is 188×66, which is where `mouseSideAspect` comes
    /// from.
    ///
    /// **The two buttons are slanted bars, because that is what they are.** The
    /// same trace read the dark pair off the flank: the front one runs from
    /// (u 0.32, v 0.48) up to (u 0.49, v 0.36) and the rear one carries on from
    /// (u 0.50, v 0.35) to (u 0.60, v 0.32) — a shallower, shorter bar, sitting
    /// higher, exactly as a thumb finds them. Filling one red is a shape the eye
    /// already sees the boundary of, which was the whole argument for the
    /// island in the view above.
    ///
    /// **The wheel is the crease, and `.left` / `.right` are not here at all.**
    /// From the side the wheel shows only as a rise in the casing, so `.wheel`
    /// thickens the crease under that rise in red rather than filling a disc
    /// that does not exist in this view.
    ///
    /// **`.left`, `.right` and the deck are not highlightable here**, and that is
    /// deliberate rather than unfinished: from the side the two main buttons are
    /// one unbroken shell, and colouring it would be a picture claiming to name
    /// a button it cannot distinguish. The caller picks the view that can answer
    /// its question — `AboutWindow` pairs the two, so every button is shown by
    /// the drawing that actually sees it.
    static func mouseSide(height: CGFloat,
                          pressed: Buttons = [],
                          body: NSColor = .secondaryLabelColor,
                          highlight: NSColor = .systemRed) -> NSImage {
        let width = (height * Self.mouseSideAspect).rounded()
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The trace counts v **down** from the top of the figure; AppKit
            // counts y up. One conversion here, as in `mouse(height:)`.
            func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: u * width, y: (1 - v) * height)
            }

            // Along the top nose-to-tail, back along the bottom — the sampled
            // columns closed into a loop and smoothed through their own
            // midpoints, the same quadratics the top view uses and for the same
            // reason: right at 16pt and right at 150.
            var points = Self.mouseSideOutline.map { p($0.u, $0.top) }
            points += Self.mouseSideOutline.reversed().map { p($0.u, $0.bottom) }
            let outline = CGMutablePath()
            outline.move(to: CGPoint(x: (points[points.count - 1].x + points[0].x) / 2,
                                     y: (points[points.count - 1].y + points[0].y) / 2))
            for (i, point) in points.enumerated() {
                let next = points[(i + 1) % points.count]
                outline.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2),
                                     control: point)
            }
            outline.closeSubpath()

            /// A thumb button: a stadium laid along the line the trace measured,
            /// built in the image's own coordinates so the slant survives the
            /// aspect ratio. A bar rotated by the angle of its own centreline —
            /// not a rotated rectangle in u-v space, which the 2.85 aspect would
            /// shear into a parallelogram.
            func bar(_ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat,
                     thickness: CGFloat) -> CGPath {
                let a = p(u0, v0), b = p(u1, v1)
                let len = hypot(b.x - a.x, b.y - a.y)
                let t = thickness * height
                let rect = CGRect(x: 0, y: -t / 2, width: len, height: t)
                var m = CGAffineTransform(translationX: a.x, y: a.y)
                    .rotated(by: atan2(b.y - a.y, b.x - a.x))
                return CGPath(roundedRect: rect, cornerWidth: t / 2, cornerHeight: t / 2,
                              transform: &m)
            }

            let forward = bar(0.335, 0.478, 0.487, 0.356, thickness: 0.165)
            let back = bar(0.505, 0.347, 0.593, 0.322, thickness: 0.160)

            // A wash inside the outline, for the top view's reason: the card and
            // the chip both float over whatever is behind them, and an unfilled
            // outline is a few grey strokes with somebody's code showing through.
            ctx.addPath(outline)
            ctx.setFillColor(body.withAlphaComponent(0.16).cgColor)
            ctx.fillPath()

            let line = max(0.8, height * 0.055)
            ctx.setLineCap(.round)

            // **The wheel is a hump in the shell, not a disc on it.** Zoomed in
            // on the schematic it is exactly that: the casing rises over the
            // wheel and drops back behind it, with a crease where the wheel
            // meets the shell — no circle is visible at all from this side. A
            // filled disc drawn here read as a ball stuck on the nose, which is
            // what rendering it settled.
            //
            // So the bump lives in the silhouette (`mouseSideOutline`, u 0.19…
            // 0.25) and the wheel is **the crease under it**. The bump is
            // lifted about 0.03 above what the trace measured, which is the top
            // view's argument repeated — the honest rise is half a pixel in the
            // source and invisible at 16pt, and this is the one landmark the
            // nose end of the drawing has.
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            let wheelPressed = pressed.contains(.wheel)
            let crease = CGMutablePath()
            crease.move(to: p(0.142, 0.398))
            crease.addQuadCurve(to: p(0.262, 0.318), control: p(0.205, 0.452))
            ctx.addPath(crease)
            ctx.setStrokeColor(wheelPressed ? highlight.cgColor : body.cgColor)
            ctx.setLineWidth(wheelPressed ? line * 2.2 : line)
            ctx.strokePath()

            // **The skirt** — the darker base the body sits on, a single line
            // rather than a second filled region. It is what stops the
            // silhouette reading as a pebble: it says *this end is the desk*.
            ctx.setStrokeColor(body.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(line * 0.8)
            ctx.move(to: p(0.16, 0.893))
            ctx.addLine(to: p(0.80, 0.893))
            ctx.strokePath()
            ctx.restoreGState()

            // **Both buttons are always drawn here**, unlike the top view's two
            // strokes. This picture exists to show them; leaving one out until
            // it is pressed would make the pair's *arrangement* — which is the
            // fact a thumb needs — visible only in the state that already
            // answers the question.
            for (path, on) in [(forward, pressed.contains(.forward)),
                               (back, pressed.contains(.back))] {
                ctx.addPath(path)
                ctx.setFillColor(on ? highlight.cgColor : body.withAlphaComponent(0.30).cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(on ? highlight.cgColor : body.cgColor)
                ctx.setLineWidth(on ? line * 1.3 : line * 0.9)
                ctx.strokePath()
            }

            ctx.addPath(outline)
            ctx.setStrokeColor(body.cgColor)
            ctx.setLineWidth(line)
            ctx.strokePath()

            return true
        }
    }

    /// Width over height of the flank, from the schematic's bounding box —
    /// 188×66 px. The top view is taller than wide and this one is nearly three
    /// times wider than tall, which is the whole reason they are two images and
    /// not one drawing with a flag.
    private static let mouseSideAspect: CGFloat = 2.8485

    /// The flank, 33 columns off Logitech's schematic: how far down the top and
    /// the bottom edge sit at each fraction of the way from the nose to the
    /// tail. Machine-read, 5-tap smoothed — the smoothing costs nothing at 16pt
    /// and stops the long shallow back looking chewed at 150.
    /// The flank, 49 columns off Logitech's schematic: how far down the top and
    /// the bottom edge sit at each fraction of the way from the nose to the
    /// tail.
    ///
    /// **49 and not 33, and the ends are not smoothed** — both learnt by
    /// rendering it. The tail is a quarter-round: `top` is pinned flat at
    /// 0.3077 for the last twelve columns while `bottom` sweeps from 0.98 up to
    /// meet it, and three samples across that corner, run through the same
    /// midpoint quadratics as the rest, cut it into a chip out of the back of
    /// the mouse. The nose tip is the same corner at the other end. So the
    /// middle is 5-tap smoothed, which stops the long shallow back looking
    /// chewed at 150pt, and the six columns at each end are left raw.
    private static let mouseSideOutline: [(u: CGFloat, top: CGFloat, bottom: CGFloat)] = [
        (0.000, 0.7077, 0.7385), (0.021, 0.6631, 0.8599), (0.042, 0.6303, 0.9383),
        (0.062, 0.5854, 0.9848), (0.083, 0.5374, 1.0000), (0.104, 0.4896, 0.9969),
        (0.125, 0.4012, 1.0000), (0.146, 0.3351, 1.0000), (0.167, 0.2974, 1.0000),
        (0.188, 0.2546, 1.0000), (0.208, 0.2297, 1.0000), (0.229, 0.2403, 1.0000),
        (0.250, 0.2612, 1.0000), (0.271, 0.2371, 1.0000), (0.292, 0.2121, 1.0000),
        (0.312, 0.1850, 1.0000), (0.333, 0.1610, 1.0000), (0.354, 0.1371, 1.0000),
        (0.375, 0.1196, 1.0000), (0.396, 0.1015, 1.0000), (0.417, 0.0833, 1.0000),
        (0.438, 0.0683, 0.9969), (0.458, 0.0532, 1.0000), (0.479, 0.0381, 1.0000),
        (0.500, 0.0292, 1.0000), (0.521, 0.0172, 1.0000), (0.542, 0.0154, 1.0000),
        (0.562, 0.0056, 1.0000), (0.583, 0.0000, 1.0000), (0.604, 0.0000, 1.0000),
        (0.625, 0.0027, 1.0000), (0.646, 0.0147, 1.0000), (0.667, 0.0154, 0.9887),
        (0.688, 0.0263, 0.9925), (0.708, 0.0353, 1.0000), (0.729, 0.0503, 1.0000),
        (0.750, 0.0685, 1.0000), (0.771, 0.0871, 1.0000), (0.792, 0.1110, 1.0000),
        (0.812, 0.1350, 1.0000), (0.833, 0.1677, 0.9944), (0.854, 0.2037, 0.9846),
        (0.875, 0.2446, 0.9846), (0.896, 0.2879, 0.9846), (0.917, 0.3077, 0.9846),
        (0.938, 0.3077, 0.9725), (0.958, 0.3077, 0.9118), (0.979, 0.3077, 0.8122),
        (1.000, 0.3077, 0.3231),
    ]

    /// **One picture with every button on it** — the M650 L seen from above and
    /// in front of its left shoulder (2026-09-22).
    ///
    /// Victor, having looked at the two views this replaces: *"1 singură poză,
    /// din diagonală cumva să se vadă toate butoanele."* And he is right that
    /// two drawings was a workaround. `mouse(height:)` sees the deck and the
    /// wheel but meets the thumb buttons edge-on; `mouseSide(height:)` sees the
    /// thumb buttons and hides everything else behind the shell. Neither can
    /// answer *where is this button on the thing in my hand* on its own, and a
    /// reader made to hold two viewpoints in their head to assemble one mouse
    /// is doing the work the picture was supposed to do.
    ///
    /// **The three-quarter is the only projection where all five are at once**,
    /// and it is the angle Logitech themselves shoot the product at: this is
    /// traced from their `m650-graphite-large-3qtr-front-angle` gallery render
    /// (3000×2592, transparent), which Victor picked out of the candidates.
    ///
    /// **The silhouette is machine-exact.** The render has a real alpha channel,
    /// so the outline is not sampled off ink the way the other two were — it is
    /// the alpha boundary itself, marched at 72 even angles from the centroid
    /// (the shape is star-shaped about it, so that parametrisation is lossless
    /// here) and closed with the same midpoint quadratics the others use. The
    /// polygon covers the real silhouette at **IoU 0.998**; the remaining 0.2%
    /// is the anti-aliased edge.
    ///
    /// **The interior landmarks are measured, not drawn by eye.** The bright
    /// LED strip came out of a luminance threshold (its green LED sits at
    /// u 0.509, v 0.192 and is the one landmark exact to a pixel); the wheel out
    /// of the same pass; the thumb pair out of a dark-blob pass over the flank,
    /// checked against a 2× crop, which is what finally settled that they are
    /// **one trough split in two** running up the flank rather than two separate
    /// islands — front at (0.60, 0.67)→(0.69, 0.50), rear carrying on from
    /// (0.70, 0.49)→(0.78, 0.38).
    ///
    /// **`v` counts down**, as in the other two tables, and `u`/`v` are both
    /// fractions of the *bounding box* — so a point is `p(u, v)` and nothing in
    /// here is in pixels.
    static func mouseIso(height: CGFloat,
                         pressed: Buttons = [],
                         body: NSColor = .secondaryLabelColor,
                         highlight: NSColor = .systemRed) -> NSImage {
        let width = (height * Self.mouseIsoAspect).rounded()
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: u * width, y: (1 - v) * height)
            }
            /// A closed path through the points, smoothed through their own
            /// midpoints — the idiom the other two drawings use, so all three
            /// round their corners the same way at every size.
            func smooth(_ uv: [(CGFloat, CGFloat)]) -> CGPath {
                let pts = uv.map { p($0.0, $0.1) }
                let path = CGMutablePath()
                path.move(to: CGPoint(x: (pts[pts.count - 1].x + pts[0].x) / 2,
                                      y: (pts[pts.count - 1].y + pts[0].y) / 2))
                for (i, pt) in pts.enumerated() {
                    let next = pts[(i + 1) % pts.count]
                    path.addQuadCurve(to: CGPoint(x: (pt.x + next.x) / 2, y: (pt.y + next.y) / 2),
                                      control: pt)
                }
                path.closeSubpath()
                return path
            }
            /// A stadium laid along a line, built in image coordinates so the
            /// slant survives the 1.44 aspect instead of being sheared by it.
            func bar(_ u0: CGFloat, _ v0: CGFloat, _ u1: CGFloat, _ v1: CGFloat,
                     thickness: CGFloat) -> CGPath {
                let a = p(u0, v0), b = p(u1, v1)
                let len = hypot(b.x - a.x, b.y - a.y), t = thickness * height
                var m = CGAffineTransform(translationX: a.x, y: a.y)
                    .rotated(by: atan2(b.y - a.y, b.x - a.x))
                return CGPath(roundedRect: CGRect(x: 0, y: -t / 2, width: len, height: t),
                              cornerWidth: t / 2, cornerHeight: t / 2, transform: &m)
            }

            let outline = smooth(Self.mouseIsoOutline)
            let line = max(0.8, height * 0.022)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // The wash, for the reason the other two have one: this floats over
            // a terminal, an editor, a photograph.
            ctx.addPath(outline)
            ctx.setFillColor(body.withAlphaComponent(0.16).cgColor)
            ctx.fillPath()

            // **The two deck buttons are areas either side of the spine**, and
            // the spine is the wheel and the LED strip behind it — the same
            // argument the top view's island makes: a button filled red has to
            // be a shape whose boundary the eye already sees, and here the eye
            // sees the strip. Both are clipped to the silhouette, so the red
            // stops at the mouse's own edge rather than at the polygon's.
            ctx.saveGState()
            ctx.addPath(outline)
            ctx.clip()
            for (region, on) in [(Self.mouseIsoRightButton, pressed.contains(.right)),
                                 (Self.mouseIsoLeftButton, pressed.contains(.left))] where on {
                ctx.addPath(smooth(region))
                ctx.setFillColor(highlight.cgColor)
                ctx.fillPath()
            }
            // The grip texture's upper edge and the shell's parting line: two
            // creases that stop the silhouette reading as a pebble. Drawn under
            // everything else and inside the clip.
            ctx.setStrokeColor(body.withAlphaComponent(0.40).cgColor)
            ctx.setLineWidth(line * 0.75)
            for crease in [Self.mouseIsoFlankCrease, Self.mouseIsoPartingLine] {
                let path = CGMutablePath()
                path.move(to: p(crease[0].0, crease[0].1))
                for i in 1..<crease.count {
                    let a = p(crease[i - 1].0, crease[i - 1].1), b = p(crease[i].0, crease[i].1)
                    path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
                }
                path.addLine(to: p(crease[crease.count - 1].0, crease[crease.count - 1].1))
                ctx.addPath(path)
            }
            ctx.strokePath()
            ctx.restoreGState()

            /// A part of the shell: filled faintly when idle, red when named,
            /// and outlined in its own colour either way — a grey ring round a
            /// red mark renders at 16pt as a grey mark, which is what the top
            /// view learnt the expensive way.
            func part(_ path: CGPath, on: Bool, weight: CGFloat = 1.0) {
                ctx.addPath(path)
                ctx.setFillColor(on ? highlight.cgColor : body.withAlphaComponent(0.26).cgColor)
                ctx.fillPath()
                ctx.addPath(path)
                ctx.setStrokeColor(on ? highlight.cgColor : body.cgColor)
                ctx.setLineWidth(on ? line * 1.4 : line * weight)
                ctx.strokePath()
            }

            // **The spine: the LED strip, and the wheel in its well at the front
            // of it.** All three are `bar`s along the measured axis rather than
            // hand-listed point loops — the first pass listed points and every
            // one of them came out too thin, because a lens drawn through a few
            // points is narrower than the band it was read off. A bar takes the
            // axis *and* the width as numbers, which is what the measurements
            // actually gave.
            let island = bar(0.318, 0.432, 0.566, 0.138, thickness: 0.118)
            ctx.addPath(island)
            ctx.setFillColor(body.withAlphaComponent(0.13).cgColor)
            ctx.fillPath()
            ctx.addPath(island)
            ctx.setStrokeColor(body.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(line * 0.8)
            ctx.strokePath()

            let wheelOn = pressed.contains(.wheel)
            // **The wheel is an ellipse, not a knob.** The first correction
            // pass made it 0.18 long and 0.15 thick, which is a circle, and a
            // circle on the end of the strip reads as a lollipop. In the render
            // it is about twice as long as it is wide, lying along the mouse's
            // own axis — that ratio is the whole difference between *a wheel*
            // and *a button*.
            let well = bar(0.182, 0.648, 0.324, 0.412, thickness: 0.198)
            ctx.addPath(well)
            ctx.setFillColor(body.withAlphaComponent(0.13).cgColor)
            ctx.fillPath()
            ctx.addPath(well)
            ctx.setStrokeColor(wheelOn ? highlight.cgColor : body.cgColor)
            ctx.setLineWidth(wheelOn ? line * 1.4 : line * 0.8)
            ctx.strokePath()
            part(bar(0.200, 0.622, 0.308, 0.438, thickness: 0.126), on: wheelOn)

            // **Both thumb buttons are always drawn**, unlike the top view's two
            // strokes: this projection exists to show them, and hiding one until
            // it is pressed would make the pair's arrangement — the fact a thumb
            // actually needs — visible only in the state that already answers it.
            part(bar(0.602, 0.660, 0.688, 0.503, thickness: 0.100),
                 on: pressed.contains(.forward))
            part(bar(0.706, 0.487, 0.778, 0.386, thickness: 0.092),
                 on: pressed.contains(.back))

            ctx.addPath(outline)
            ctx.setStrokeColor(body.cgColor)
            ctx.setLineWidth(line)
            ctx.strokePath()
            return true
        }
    }

    /// 1773 × 1230, the alpha bounding box of Logitech's own render.
    private static let mouseIsoAspect: CGFloat = 1.4415

    /// The silhouette: 72 points marched off the render's alpha channel at even
    /// angles from the centroid. IoU 0.998 against the real alpha.
    private static let mouseIsoOutline: [(CGFloat, CGFloat)] = [
        (0.9890, 0.4870), (0.9647, 0.5474), (0.9298, 0.5998), (0.8914, 0.6436),
        (0.8525, 0.6792), (0.8145, 0.7077), (0.7787, 0.7305), (0.7465, 0.7498),
        (0.7177, 0.7671), (0.6912, 0.7826), (0.6681, 0.7995), (0.6459, 0.8159),
        (0.6250, 0.8337), (0.6044, 0.8524), (0.5836, 0.8728), (0.5618, 0.8939),
        (0.5386, 0.9159), (0.5135, 0.9370), (0.4862, 0.9565), (0.4567, 0.9728),
        (0.4252, 0.9858), (0.3918, 0.9947), (0.3572, 0.9980), (0.3212, 0.9972),
        (0.2840, 0.9919), (0.2467, 0.9801), (0.2096, 0.9622), (0.1740, 0.9371),
        (0.1390, 0.9069), (0.1041, 0.8727), (0.0706, 0.8329), (0.0393, 0.7874),
        (0.0144, 0.7346), (0.0020, 0.6741), (0.0020, 0.6101), (0.0116, 0.5469),
        (0.0279, 0.4870), (0.0494, 0.4320), (0.0730, 0.3820), (0.0990, 0.3375),
        (0.1249, 0.2975), (0.1514, 0.2620), (0.1769, 0.2297), (0.2022, 0.2004),
        (0.2277, 0.1744), (0.2529, 0.1508), (0.2777, 0.1289), (0.3026, 0.1091),
        (0.3274, 0.0907), (0.3527, 0.0744), (0.3781, 0.0589), (0.4041, 0.0456),
        (0.4306, 0.0329), (0.4580, 0.0232), (0.4862, 0.0142), (0.5153, 0.0077),
        (0.5454, 0.0028), (0.5765, 0.0012), (0.6089, 0.0012), (0.6423, 0.0045),
        (0.6772, 0.0102), (0.7127, 0.0207), (0.7491, 0.0354), (0.7854, 0.0557),
        (0.8213, 0.0817), (0.8564, 0.1134), (0.8892, 0.1516), (0.9208, 0.1949),
        (0.9495, 0.2440), (0.9755, 0.2981), (0.9935, 0.3581), (0.9986, 0.4224),
    ]



    /// **The right button is everything up-left of the spine**, the left button
    /// everything down-right of it as far as the grip. Both run past the
    /// silhouette on purpose — they are filled inside a clip of the outline, so
    /// the red ends at the mouse's edge and the polygon never has to agree with
    /// it. The shared border is the wheel-and-strip line, which is the boundary
    /// the eye already reads.
    private static let mouseIsoRightButton: [(CGFloat, CGFloat)] = [
        (0.0300, 0.7900), (0.1450, 0.6180), (0.1980, 0.4570), (0.2530, 0.4030),
        (0.3070, 0.3830), (0.3960, 0.2790), (0.5150, 0.1470), (0.5880, 0.1000),
        (0.6100, -0.0400), (0.2000, -0.0400), (-0.0400, 0.3000), (-0.0400, 0.7900),
    ]
    private static let mouseIsoLeftButton: [(CGFloat, CGFloat)] = [
        (0.0700, 0.7950), (0.1750, 0.6760), (0.2700, 0.6010), (0.3520, 0.4580),
        (0.4300, 0.3760), (0.5400, 0.2420), (0.5900, 0.1500), (0.6280, 0.2560),
        (0.6120, 0.3620), (0.5480, 0.5060), (0.4600, 0.6480), (0.3500, 0.7800),
        (0.2400, 0.8620),
    ]

    /// The upper edge of the ribbed grip panel, and the parting line where the
    /// upper shell meets the base.
    private static let mouseIsoFlankCrease: [(CGFloat, CGFloat)] = [
        (0.6320, 0.3120), (0.7150, 0.2620), (0.8050, 0.2400), (0.8850, 0.2650),
        (0.9420, 0.3250),
    ]
    private static let mouseIsoPartingLine: [(CGFloat, CGFloat)] = [
        (0.0620, 0.8180), (0.1700, 0.8850), (0.2900, 0.9280), (0.4100, 0.9420),
        (0.5300, 0.9200), (0.6500, 0.8650), (0.7600, 0.7900), (0.8500, 0.7050),
        (0.9200, 0.6100),
    ]

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
