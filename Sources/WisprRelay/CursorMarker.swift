import AppKit

/// Paints a red target into a saved screenshot at the spot the pointer was
/// standing when the shutter went.
///
/// The reading was already in the file *name* (`-cursor-34.2x71.8pct`), which is
/// what the agent reads. This is the same fact for the human in the loop: Victor
/// looks at these shots too, and a percentage pair is not something anyone
/// resolves by eye. Both come from the one `cursorFraction`, so the name and the
/// mark can never point at different pixels.
///
/// **The look is Victor Addons'**, deliberately: `EmojiAnimator.makeSniperReticle`
/// is already what that desktop draws to say "here", and it is drawn on screen
/// right after every ⌃P capture. A second, differently-shaped mark for the same
/// idea would be one to learn for nothing. Hence a ring, four arms with an empty
/// centre, a centre dot — `systemRed`, over a symmetric black shadow rather than
/// a white outline, which is what makes it survive a light page and a dark
/// terminal alike.
///
/// Burned into the pixels, not drawn on screen like the Addons one: the shot has
/// already been taken by the time this runs, and a panel raised afterwards would
/// mark the screen for the human but leave the picture unmarked for the agent.
enum CursorMarker {

    /// The reticle's box as a fraction of the picture's shorter side.
    ///
    /// Proportional and not a pixel size, for the same reason the file name is a
    /// percentage: the agent reads these through a tool that downsamples them,
    /// and a mark measured in pixels becomes a smudge the moment the image is
    /// resized. This is roughly what the Addons reticle covers on his display.
    private static let boxFraction: CGFloat = 0.07

    /// Ratios lifted from `makeSniperReticle`, where they are expressed against a
    /// `65 * scale` box.
    private static let strokeRatio: CGFloat = 2.5 / 65
    private static let gapRatio: CGFloat = 7.0 / 65
    private static let dotRatio: CGFloat = 2.0 / 65
    private static let shadowRatio: CGFloat = 1.5 / 65

    /// `spot` is 0…1 across and 0…1 **down from the top**, like the image.
    static func draw(at spot: CGPoint, onJPEGAt file: URL) {
        guard let data = try? Data(contentsOf: file),
              let source = NSBitmapImageRep(data: data) else {
            Log.error("cursor marker: \(file.lastPathComponent) would not decode")
            return
        }
        let width = source.pixelsWide
        let height = source.pixelsHigh
        guard width > 0, height > 0 else { return }

        // A fresh RGBA canvas rather than drawing into the loaded rep: a JPEG
        // decodes to three samples with no alpha, which is not a shape AppKit
        // will hand out a graphics context for.
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: canvas) else { return }

        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        source.draw(in: frame)
        // The context counts y up from the bottom; `spot` counts it down.
        paint(in: context.cgContext,
              at: CGPoint(x: spot.x * CGFloat(width), y: (1 - spot.y) * CGFloat(height)),
              box: CGFloat(min(width, height)) * boxFraction)
        NSGraphicsContext.restoreGraphicsState()

        canvas.size = frame.size
        // Maximum quality on the way back out. This is a *second* JPEG pass over
        // a picture `screencapture` already encoded, and what these shots carry is
        // small text the agent has to read — at 0.9 the same frame came back a
        // tenth of the size, which is not a saving, it is the code going soft.
        guard let jpeg = canvas.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else { return }
        try? jpeg.write(to: file)
    }

    /// The same mark, rendered as a layer to put **on screen** rather than into
    /// a file.
    ///
    /// It goes through `paint` like the burned-in one, so the mark Victor sees
    /// flash on his desktop and the mark he finds in the picture a minute later
    /// are not merely similar — they are one drawing, and cannot drift apart the
    /// way two implementations of "a red target" always eventually do.
    ///
    /// `box` is in points here, not a fraction: this one is drawn over the real
    /// screen at a real size, and nothing downstream is going to resize it.
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
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setFillColor(NSColor.systemRed.cgColor)
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
