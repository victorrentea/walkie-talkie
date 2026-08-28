import AppKit

/// The red target that says "the pointer was here when the shutter went".
///
/// **It is drawn on the screen and never into the picture.** It used to be
/// burned into the saved JPEG, on the argument that the file name carried the
/// reading for the agent while Victor — who opens these shots himself — cannot
/// resolve a coordinate pair by eye. What that missed is that a mark painted
/// into a frame *covers the thing it is pointing at*, which is exactly the thing
/// being asked about, and that an agent reading the image has no way to know the
/// red circle is not part of the UI. The screen flash answers the same need at a
/// better moment (`CaptureFlash.markCursor`, at the instant of capture, while
/// the sentence is still being spoken and a mis-aimed shot can still be
/// retaken), and the position still travels in the file name.
///
/// **The look is Victor Addons'**, deliberately: `EmojiAnimator.makeSniperReticle`
/// is already what that desktop draws to say "here", and it is drawn on screen
/// right after every ⌃P capture. A second, differently-shaped mark for the same
/// idea would be one to learn for nothing. Hence a ring, four arms with an empty
/// centre, a centre dot — over a symmetric black shadow rather than a white
/// outline, which is what makes it survive a light page and a dark terminal
/// alike.
///
/// **The same colour as the border, deliberately.** The two are one event — the
/// screen border says *this was photographed*, the reticle says *from here* —
/// and they used to disagree, red mark inside a red border only by coincidence.
/// Both are now `NSColor.captureAccent`, which is the amber ⌃P has drawn in
/// `victor-macos-addons` for years.
enum CursorMarker {

    /// Ratios lifted from `makeSniperReticle`, where they are expressed against a
    /// `65 * scale` box.
    private static let strokeRatio: CGFloat = 2.5 / 65
    private static let gapRatio: CGFloat = 7.0 / 65
    private static let dotRatio: CGFloat = 2.0 / 65
    private static let shadowRatio: CGFloat = 1.5 / 65

    /// The mark, as a layer to hand to a panel.
    ///
    /// `box` is in points, not a fraction of anything: this is drawn over the
    /// real screen at a real size, and nothing downstream resizes it. (The
    /// burned-in version measured itself against the picture's shorter side,
    /// because that one *was* going to be downsampled.)
    static func makeLayer(box: CGFloat) -> CALayer {
        // Room around the mark for the shadow and for the zoom-in it arrives on,
        // which would otherwise be clipped by its own layer's bounds.
        let side = box * 1.6
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            paint(in: ctx, at: CGPoint(x: side / 2, y: side / 2), box: box)
            return true
        }
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.contents = image
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        return layer
    }

    private static func paint(in ctx: CGContext, at centre: CGPoint, box: CGFloat) {
        let stroke = box * strokeRatio
        let radius = box / 2 - stroke
        let gap = box * gapRatio
        let dot = box * dotRatio

        ctx.saveGState()
        // One shadow for the whole mark, offset nowhere, so it reads as a dark
        // halo on a light page and a soft edge on a dark one. A white outline
        // would only have solved the first half.
        ctx.setShadow(offset: .zero,
                      blur: box * shadowRatio,
                      color: NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setStrokeColor(NSColor.captureAccent.cgColor)
        ctx.setFillColor(NSColor.captureAccent.cgColor)
        ctx.setLineWidth(stroke)

        ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                  width: radius * 2, height: radius * 2))
        ctx.strokePath()

        let arms: [(CGPoint, CGPoint)] = [
            (CGPoint(x: centre.x - box / 2, y: centre.y), CGPoint(x: centre.x - gap, y: centre.y)),
            (CGPoint(x: centre.x + gap, y: centre.y), CGPoint(x: centre.x + box / 2, y: centre.y)),
            (CGPoint(x: centre.x, y: centre.y - box / 2), CGPoint(x: centre.x, y: centre.y - gap)),
            (CGPoint(x: centre.x, y: centre.y + gap), CGPoint(x: centre.x, y: centre.y + box / 2)),
        ]
        for (from, to) in arms {
            ctx.move(to: from)
            ctx.addLine(to: to)
        }
        ctx.strokePath()

        ctx.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: dot * 2, height: dot * 2))
        ctx.restoreGState()
    }
}
