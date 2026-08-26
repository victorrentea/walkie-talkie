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

}
