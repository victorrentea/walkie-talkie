import AppKit
import ImageIO
import UniformTypeIdentifiers

/// **The one picture an agent can actually look at** — N frames of a screen
/// recording laid out as a numbered grid (2026-09-18).
///
/// The feature Victor asked for is a short screen recording, and the thing that
/// makes it non-obvious is that **an agent cannot watch a video**. A `.mp4` path
/// in the envelope is a path to something the recipient has no way to open; the
/// frames have to arrive as an image or they do not arrive at all.
///
/// So the film reaches the agent twice, at two resolutions, and the split is
/// Victor's (2026-09-18): *"it should be in very low resolution, first of all,
/// and then give access to the actual frames somehow"*.
///
/// | | what it is | who reads it |
/// |---|---|---|
/// | the sheet | every frame, thumbnailed, one PNG | the agent, immediately, at a glance |
/// | the frames | full resolution, one JPEG each | the agent when it needs to read the screen, and Victor |
///
/// **The sheet is deliberately cheap.** A 10 s recording at 5 fps is 50 cells;
/// at `cellWidth` they cost about as many tokens as one ordinary screenshot,
/// which is the whole budget this feature is allowed to spend on *what
/// happened*. Anything the agent wants to actually **read** is a numbered file
/// away, and the cell labels are how it knows which number to ask for.
enum FilmSheet {

    /// **360 px wide cells, four across, sixteen at most** — and every one of
    /// those three numbers is the same constraint, which is the *reader*.
    ///
    /// An LLM downsamples an image to roughly 1568 px on its longest side before
    /// it looks at it. That is the budget, and it is spent whatever we put in
    /// it: a 50-cell sheet of a 10 s recording is six columns by nine rows, so
    /// after downsampling each cell is about a hundred pixels of a 5K desktop —
    /// a grey smear that costs a full image's tokens to say nothing. Fewer,
    /// bigger cells say *what moved and when* at the same price.
    ///
    /// So the sheet is a **sample** of the recording, not the whole of it. Every
    /// frame is still on disk at full resolution; the cell labels carry the
    /// frame numbers, which is how the agent asks for the one it wants to read.
    static let cellWidth: CGFloat = 360
    static let columns = 4

    /// At most this many cells, sampled evenly across the recording. Sixteen at
    /// `cellWidth` is 1476 px across — just inside the downsample — by four rows.
    static let maxCells = 16

    /// The label strip under each cell — `0:04` and the frame's own number, so
    /// the agent can name the file it wants.
    private static let labelHeight: CGFloat = 16
    private static let gap: CGFloat = 4
    private static let margin: CGFloat = 8

    struct Frame {
        /// The full-resolution JPEG already on disk.
        let url: URL
        /// Seconds from the first frame.
        let at: TimeInterval
        /// 1-based, and the number the file name carries.
        let index: Int
    }

    /// Compose the sheet and write it beside the frames.
    ///
    /// **A `CGBitmapContext`, not `NSImage.lockFocus`.** `lockFocus` draws
    /// through the current `NSGraphicsContext`, which means the backing scale of
    /// whatever display happens to be current — the same trap
    /// `RelayWindow.snapshot` was rebuilt to avoid when every file in
    /// `docs/states/` turned up in a diff for no reason. A sheet whose pixel
    /// size depends on which monitor was awake is a sheet whose token cost does
    /// too. This context is 1× and fixed, always.
    ///
    /// Returns nil rather than a blank sheet: a picture that says nothing
    /// happened is worse than no picture, because the agent believes it.
    @discardableResult
    static func write(frames all: [Frame], to url: URL) -> URL? {
        guard !all.isEmpty else { return nil }
        // **Sampled evenly, ends included.** The first and last frame are the
        // two the agent is most likely to be asked about — *what did it look
        // like before, what does it look like now* — so the stride is computed
        // to land on both rather than dropping whichever end the arithmetic
        // happens to lose.
        let frames: [Frame]
        if all.count <= maxCells {
            frames = all
        } else {
            let step = Double(all.count - 1) / Double(maxCells - 1)
            frames = (0..<maxCells).map { all[Int((Double($0) * step).rounded())] }
            Log.info("🎬 sheet samples \(maxCells) of \(all.count) frames — all of them are on disk")
        }

        // Every frame of one recording is the same display, so the aspect of the
        // first one sets every cell — measured rather than assumed, because a
        // recording that spans a display change would otherwise letterbox
        // silently.
        guard let first = thumbnail(frames[0].url, width: cellWidth) else { return nil }
        let cellHeight = (cellWidth * CGFloat(first.height) / CGFloat(first.width)).rounded()

        let cols = min(columns, frames.count)
        let rows = Int(ceil(Double(frames.count) / Double(cols)))
        let cellTotal = cellHeight + labelHeight
        let width = margin * 2 + CGFloat(cols) * cellWidth + CGFloat(cols - 1) * gap
        let height = margin * 2 + CGFloat(rows) * cellTotal + CGFloat(rows - 1) * gap

        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        for (n, frame) in frames.enumerated() {
            let col = n % cols
            let row = n / cols
            let x = margin + CGFloat(col) * (cellWidth + gap)
            // Top-down reading order in a bottom-up context.
            let yTop = height - margin - CGFloat(row) * (cellTotal + gap)
            let imageRect = CGRect(x: x, y: yTop - cellHeight, width: cellWidth, height: cellHeight)

            if let thumb = thumbnail(frame.url, width: cellWidth) {
                ctx.draw(thumb, in: imageRect)
            } else {
                // A frame that could not be read is drawn as a hole rather than
                // skipped: the grid's positions are the timeline, and a missing
                // cell would silently shift every later frame's label onto the
                // wrong picture.
                ctx.setFillColor(NSColor.darkGray.cgColor)
                ctx.fill(imageRect)
            }

            let label = String(format: "#%d  %d:%02d.%d", frame.index,
                               Int(frame.at) / 60, Int(frame.at) % 60,
                               Int((frame.at * 10).truncatingRemainder(dividingBy: 10)))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.white,
            ]
            NSAttributedString(string: label, attributes: attrs)
                .draw(at: NSPoint(x: x + 2, y: yTop - cellHeight - labelHeight + 3))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        Log.info("🎬 contact sheet → \(url.lastPathComponent) (\(frames.count) frames, \(Int(width))×\(Int(height)))")
        return url
    }

    /// **Thumbnailed by ImageIO, never by decoding the full frame first.**
    /// `kCGImageSourceCreateThumbnailFromImageAlways` with a max pixel size
    /// decodes at a reduced scale, so a 50-cell sheet off a 5K display never
    /// holds fifty full-resolution bitmaps at once — which is the difference
    /// between a few megabytes and a few gigabytes.
    private static func thumbnail(_ url: URL, width: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // The long edge, so a landscape display lands at `width` across.
            kCGImageSourceThumbnailMaxPixelSize: Int(width * 2),
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}
