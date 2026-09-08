import AppKit
import QuartzCore

/// **An oblique line sweeps across the chip: it brightens the words it crosses,
/// then takes them away and leaves the next ones behind it.**
///
/// Victor's ask, 2026-09-07: *"an oblique line that wipes out the message of
/// dictating when I cancel by holding the wheel down… an effect that wipes the
/// text that was there and replaces it with 'cancelled'… imagine an oblique
/// line, like 60 degrees from the horizontal, which makes the text a bit
/// brighter where it passes through and then it wipes the text out, or replaces
/// it with another text"*.
///
/// **Why the chip needed a transition at all.** Every message beside the pointer
/// is one row being swapped for another — `🔴 Listening…` becomes
/// `🗑️ Dictation aborted` becomes the chip again — and a swap made in a single
/// frame is indistinguishable from a redraw. Nothing on screen says the second
/// row *replaced* the first, which is exactly the fact a cancel has to carry:
/// the sentence he was recording is the thing that just went away. What was
/// there before was a half-second alpha dissolve on the message going out and
/// nothing at all on the message coming in — an asymmetric fade for a symmetric
/// event.
///
/// **Why a line and not a fade.** A fade says *this is ending*; a wipe says
/// *this is being replaced by that*, because at every instant both are on screen
/// with a boundary between them. The chip is a flat stack of one-line facts, so
/// the one thing a transition here can add is direction — and a line travelling
/// through it is direction with nothing else attached.
///
/// **60° from the horizontal, which is his number and also the only one that
/// works.** The chip is wide and short (~200 × 40–100 points), so a vertical
/// edge crosses every row at the same instant — one column of text after
/// another, which reads as a curtain rather than as a stroke — and a horizontal
/// one takes the rows off one at a time, which reads as three separate events.
/// A steep oblique crosses the whole stack at once but reaches the bottom row a
/// beat after the top, so the shape is read as a single gesture with a *grain*
/// to it. Steeper than 45° on purpose: at 45° the edge's travel is dominated by
/// the chip's height and the sweep looks like it is going down rather than
/// across.
///
/// **Why it is drawn in the chip's own layer and not in a panel of its own.**
/// `UnbindPop` and `BindFlight` open a window over the screen because what they
/// draw leaves the chip — a burst spreading past its edges, a rectangle
/// travelling from a terminal. This never leaves the chip: it is the chip's own
/// content being exchanged, and the chip is riding the pointer while it happens.
/// A separate window would have to chase the cursor for a third of a second to
/// stay registered with the thing it is drawing on, and would be composited at
/// its own opacity instead of at the chip's 0.80.
///
/// **Nothing here survives a photograph.** `RelayWindow.snapshot` draws the view
/// hierarchy, not the layer tree, and `docs/shoot-overlay-states.sh` photographs
/// *states* — a transition is by definition not one. `enabled` turns the whole
/// thing off under `RELAY_SHOOT` rather than relying on the two drawing paths
/// agreeing, because a catalogue of 33 pictures is the last place to find out
/// that they do not.
enum ChipWipe {

    /// The chip's pixels at some instant, and how big it was then. Captured by
    /// the caller *before* it relayouts, because after the relayout there is
    /// nowhere left to read the old content from.
    struct Frame {
        let image: CGImage
        let size: CGSize
    }

    /// **A third of a second.** This is a receipt glanced at, not an animation to
    /// study: the argument that halved the bind flight from 2s to 1s applies
    /// harder here, because a bind is answered once per binding and this runs on
    /// every flash the app raises — dozens of times a day, an inch from whatever
    /// he is reading.
    ///
    /// The floor is the brightening. Below about a quarter of a second the band
    /// crosses a 200pt chip faster than the eye resolves it and the whole effect
    /// collapses into a flicker, which is worse than the instant swap it
    /// replaced. 0.32 leaves the band roughly four frames over any given word at
    /// 60Hz — enough to be seen travelling — and is over well before the message
    /// it is announcing has been read.
    static let duration: CFTimeInterval = 0.32

    /// Measured from the horizontal, counter-clockwise, as Victor said it.
    static let angle: CGFloat = 60

    /// How wide the bright band is across itself. Wide enough to hold a couple of
    /// glyphs at once: a band narrower than a letter reads as a scanline artefact
    /// rather than as light moving over the words.
    private static let bandWidth: CGFloat = 13

    /// How soft the erasing edge is. Hard enough to read as an edge, soft enough
    /// not to alias into a staircase along a 60° diagonal.
    private static let softEdge: CGFloat = 3

    /// The band rides **ahead** of the erasing edge by this much of its own
    /// width, so the order Victor described is the order it happens in: brighter
    /// first, gone second. It still straddles the edge rather than clearing it,
    /// which is what lets one sweep brighten the incoming words on the way past
    /// instead of a glow that stops dead at the seam.
    private static let leadFraction: CGFloat = 0.25

    /// Off while the state pages are being shot — see the note on the type.
    static var enabled: Bool { ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil }

    /// Whether a sweep is in the air — which is also the window in which the real
    /// rows are muted, so anything that wants to read the chip's pixels has to
    /// ask first.
    static var isRunning: Bool { host != nil }

    /// The one wipe that may be in the air, and the rows it took off screen for
    /// the length of it. Static like `UnbindPop`'s panel: there is one chip.
    private static var host: CALayer?
    private static var muted: [NSView] = []

    // MARK: - Capturing

    /// The view's current pixels, by the same route `RelayWindow.snapshot` uses:
    /// the window is excluded from every screen capture, so the only way to get a
    /// picture of the chip is to ask it to draw one.
    ///
    /// **Anything this effect has laid over the chip comes down first.** A wipe
    /// in flight has the real rows muted (see `play`), so a capture taken over
    /// one would photograph an empty chip and the next sweep would wipe nothing
    /// into nothing.
    static func capture(_ view: NSView) -> Frame? {
        guard enabled else { return nil }
        cancel()
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        return Frame(image: image, size: bounds.size)
    }

    // MARK: - Playing it

    /// Sweep `view`'s new content in over `before`'s old content.
    ///
    /// Call it **after** the relayout: the new rows have to be laid out, because
    /// the incoming half of the sweep is a picture of them.
    static func play(over view: NSView, from before: Frame) {
        guard enabled else { return }
        guard let root = view.layer else { return }
        let size = view.bounds.size
        guard size.width >= 1, size.height >= 1 else { return }
        // `capture` cancels whatever was running, which is what puts the real
        // rows back before they are photographed.
        guard let after = capture(view) else { return }

        let scale = view.window?.backingScaleFactor ?? 2

        // **Both halves of the swap are pictures, and the live rows are taken off
        // screen for the length of it.**
        //
        // The obvious build is one picture of the old content erased over the
        // live new content, and it is wrong in a way that only shows on a message
        // longer than the one it replaces: the chip's background is transparent,
        // so wherever the old picture has no ink the *new* row is already visible
        // through it — `Dictation aborted` sticking its tail out past
        // `Listening…` from the first frame, on the side the edge has not reached
        // yet. Two masked pictures and a muted view tree is the only arrangement
        // in which the region ahead of the line is honestly *only* the old chip.
        //
        // Muted by `alphaValue`, not by `isHidden`: `layoutContent` owns `isHidden`
        // on every one of these rows and would fight for it.
        muted = view.subviews
        for row in muted { row.alphaValue = 0 }

        let host = CALayer()
        host.frame = CGRect(origin: .zero, size: size)
        // AppKit owns the sublayers of a layer-backed view — one per subview — and
        // reorders them as rows come and go, which is exactly what a relayout
        // mid-wipe would do. A z above all of them is the only way to stay on top
        // by construction rather than by insertion order.
        host.zPosition = 100
        host.masksToBounds = true
        host.contentsScale = scale

        host.addSublayer(picture(after, in: size, scale: scale, keeping: .behind, animated: true).layer)
        host.addSublayer(picture(before, in: size, scale: scale, keeping: .ahead, animated: true).layer)

        root.addSublayer(host)
        self.host = host

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            // Only if it is still ours: a flash raised inside a third of a second
            // has already replaced this, and tearing it down here would take the
            // new sweep — and its muting — with it.
            guard self.host === host else { return }
            cancel()
        }
    }

    // MARK: - Looking at it

    /// **Draw the whole sweep as a strip of frames and write it to a PNG.**
    ///
    /// `WT_SHOOT_WIPE=/tmp/wipe.png` — `RelayWindow.shootWipe`.
    ///
    /// This effect is the least reviewable thing in the app and it took a bug
    /// report to notice. The chip is invisible to every screen capture
    /// (`sharingType`), the sweep lasts a third of a second, and it is drawn in
    /// *layers* — so `RelayWindow.snapshot`, which draws the view tree and
    /// explicitly stands a wipe down first, cannot see it either. Reviewing a
    /// change to it meant provoking a cancel and watching, twelve times.
    ///
    /// The same argument as `docs/overlay-states.html` and `WT_SHOOT_MENU`, and
    /// the same answer: the real layers, drawing themselves, at instants chosen
    /// by hand. `CALayer.render(in:)` honours `mask` — checked before this was
    /// built, since the whole effect is two masked pictures and a stencil, and a
    /// renderer that ignored masks would have produced a confident lie.
    ///
    /// **On a dark ground**, because the chip is bare and its ink is white with
    /// a halo: rendered on white the brightening is invisible, and rendered on
    /// transparency it is unjudgeable. A terminal is what this actually sits on.
    static func shoot(over view: NSView, from before: Frame, to path: String, frames: Int = 13) {
        guard let after = capture(view) else { return }
        let size = view.bounds.size
        let scale: CGFloat = 2
        let gap: CGFloat = 8
        let sheetW = size.width
        let sheetH = (size.height + gap) * CGFloat(frames) - gap

        guard let ctx = CGContext(data: nil, width: Int(sheetW * scale), height: Int(sheetH * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)

        let back = picture(after, in: size, scale: scale, keeping: .behind, animated: false)
        let front = picture(before, in: size, scale: scale, keeping: .ahead, animated: false)
        let host = CALayer()
        host.frame = CGRect(origin: .zero, size: size)
        host.masksToBounds = true
        host.contentsScale = scale
        host.addSublayer(back.layer)
        host.addSublayer(front.layer)

        for i in 0..<frames {
            let t = CGFloat(i) / CGFloat(frames - 1)
            back.pose(t)
            front.pose(t)
            ctx.saveGState()
            // Top frame first, so the sheet reads downward like the sweep does.
            ctx.translateBy(x: 0, y: sheetH - (size.height + gap) * CGFloat(i) - size.height)
            ctx.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            host.render(in: ctx)
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: sheetW, height: sheetH)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        Log.info("wipe sheet → \(path) (\(frames) frames of \(Int(size.width))×\(Int(size.height)))")
    }

    /// Take the sweep down and give the real rows back. Idempotent, and the only
    /// place `alphaValue` is restored — so an interrupted wipe cannot leave the
    /// chip blank.
    static func cancel() {
        host?.removeFromSuperlayer()
        host = nil
        for row in muted { row.alphaValue = 1 }
        muted = []
    }

    // MARK: - The geometry of one oblique line

    /// Which side of the travelling edge a mask keeps.
    private enum Side { case ahead, behind }

    /// How much room the stripes need beyond the chip before the sweep starts and
    /// after it ends. The widest thing crossing is the band, which is centred a
    /// quarter of its width ahead of the edge, so it — and not the erasing edge —
    /// is what decides when the chip is clear.
    private static var clearance: CGFloat { bandWidth / 2 + bandWidth * leadFraction }

    /// Where the edge starts and ends, in the chip's own coordinates.
    ///
    /// Both stripes are built with a *vertical* boundary and rotated until it
    /// stands at `angle` off the horizontal, so their local +x axis is the
    /// direction the edge travels in and the whole animation is one number: the
    /// stripe's `position.x`.
    ///
    /// A point `P` sits ahead of an edge centred at `pos` by `(P - pos) · n`,
    /// where `n` is that local +x axis after rotation. Solving it for the two
    /// corners that meet the edge first and last gives the terms below: a chip
    /// `H` tall needs `H·cos/2sin` of extra travel at each end before an oblique
    /// has cleared it, which is what a vertical wipe would not need and is the
    /// whole reason the range is not simply `0…W`.
    private static func travel(size: CGSize) -> (from: CGFloat, to: CGFloat) {
        let radians = angle * .pi / 180
        let corner = size.height * Foundation.cos(radians) / (2 * Foundation.sin(radians))
        let pad = max(softEdge, clearance) / Foundation.sin(radians) + 2
        return (-(corner + pad), size.width + corner + pad)
    }

    private static var rotation: CATransform3D {
        // Negative because the chip's layer is y-up: a clockwise turn is what tips
        // a vertical line towards the right-leaning oblique Victor drew with his
        // hand, and leaves the local +x axis pointing across the chip.
        CATransform3DMakeRotation((angle - 90) * .pi / 180, 0, 0, 1)
    }

    /// One of the two pictures, laid into the chip and clipped to its side of the
    /// line.
    ///
    /// **Anchored top-left, not centred.** The chip's rows are laid out from its
    /// top edge downward and the window anchors that edge when it resizes
    /// (`layoutContent`), so a message a row shorter than the one it replaces
    /// still shares its first row's pixels. Centring would slide every row of the
    /// old picture half the difference and turn a swap into a jump.
    private static func picture(_ frame: Frame, in size: CGSize, scale: CGFloat,
                                keeping: Side, animated: Bool)
                                -> (layer: CALayer, pose: (CGFloat) -> Void) {
        let inset = size.height - frame.size.height
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: inset, width: frame.size.width, height: frame.size.height)
        layer.contents = frame.image
        layer.contentsScale = scale
        // **The mask lives in the picture's coordinates, not the chip's**, and a
        // picture shorter than the chip is inset from it — so the edge is shifted
        // by that inset rather than the mask's `frame` being set. Setting `frame`
        // on the stripe would be the natural-looking thing and is exactly wrong:
        // it would recompute `bounds` and `position` from the rectangle given and
        // throw away both the oversized span the rotation needs and the animation
        // riding on `position`.
        let path = travel(size: size)
        let axis = size.height / 2 - inset
        let edge = sweep(size: size, scale: scale, keeping: keeping)
        edge.position = CGPoint(x: path.from, y: axis)
        if animated { edge.add(slide(from: path.from, to: path.to, y: axis, lead: 0), forKey: "sweep") }
        layer.mask = edge

        // **The light is masked by the words, so only the words brighten.** A
        // white band laid straight over the chip would be a translucent stripe
        // dragged across whatever Victor is reading behind it — the chip is bare
        // (*Nothing beside the pointer draws a window*), so "behind the text" is
        // his own screen. The picture's own ink is the stencil, and every lit
        // pixel lands on a pixel that was already ink.
        //
        // **And it rides inside the picture rather than over the chip**, so it
        // inherits the same edge: nothing lights up where its own text is no
        // longer (or not yet) on screen. Built the other way — one glow over the
        // union of both pictures — the band lit the outgoing and the incoming
        // words *at once* wherever it straddled the seam, which on two different
        // strings is two different words superimposed and reads as a smear
        // rather than as a line.
        var lit: CALayer?
        var stripe: CALayer?
        if let stencil = stencil(frame, scale: scale) {
            let glow = CALayer()
            glow.frame = CGRect(origin: .zero, size: frame.size)
            glow.contentsScale = scale
            glow.mask = stencil
            let bar = band(size: size, scale: scale)
            bar.position = CGPoint(x: path.from + bandLead, y: axis)
            glow.addSublayer(bar)
            // Up and down at the ends, or the band is switched on at the chip's
            // left edge and cut off at its right — a light that is switched on is
            // a different event from a light that arrives.
            glow.opacity = 0
            if animated {
                bar.add(slide(from: path.from, to: path.to, y: axis, lead: bandLead), forKey: "sweep")
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = glowKeys.map { NSNumber(value: Double($0.value)) }
                fade.keyTimes = glowKeys.map { NSNumber(value: Double($0.at)) }
                fade.duration = duration
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                glow.add(fade, forKey: "fade")
            }
            layer.addSublayer(glow)
            lit = glow
            stripe = bar
        }

        // **The same numbers the animations ride on, as a function of time** —
        // so `shoot` photographs the effect rather than an impression of it. A
        // second implementation of the motion is a second thing to keep in step;
        // this one is the same three assignments the CA animations make, made by
        // hand at one instant.
        let pose: (CGFloat) -> Void = { t in
            let travelled = path.from + (path.to - path.from) * ease(t)
            edge.position = CGPoint(x: travelled, y: axis)
            stripe?.position = CGPoint(x: travelled + bandLead, y: axis)
            lit?.opacity = Float(glowOpacity(at: t))
        }

        // **A row that no longer fits is faded out, not guillotined** (2026-09-09).
        //
        // The chip hugs its current state, so a two-row `🔴 Listening... [HQ]` /
        // `petclinic@main` is 23pt taller than the one-row `🗑️ Dictation
        // aborted` that replaces it — and the window has already resized by the
        // time the sweep plays. Top-aligned and clipped to the host, the second
        // row was therefore **cut through the middle of its letters** and sat
        // there sliced for the whole third of a second, in every frame before
        // the edge reached it. That is the "strange" part of what Victor was
        // looking at, and it is not something a sweep can be blamed for: nothing
        // about a line crossing the chip says the row under it should end in a
        // horizontal cut.
        //
        // Nothing can *show* the extra row — the window is the size it is — so
        // the honest thing is to let it leave rather than to sever it. A
        // vertical ramp over the last few points of what fits reads as the row
        // going out of frame, which is what is actually happening.
        guard inset < -0.5, let ramp = bottomFade(frame.size, visible: size.height, scale: scale)
        else { return (layer, pose) }
        let holder = CALayer()
        holder.frame = layer.frame
        // The mask on the picture is in the picture's own coordinates and its
        // bounds do not change, so re-homing the layer inside a holder leaves the
        // sweep exactly where it was.
        layer.frame = CGRect(origin: .zero, size: frame.size)
        holder.addSublayer(layer)
        holder.mask = ramp
        return (holder, pose)
    }

    /// How many points the overflowing picture takes to disappear at the bottom.
    private static let fadeHeight: CGFloat = 12

    /// A mask that is opaque over the picture and ramps to nothing across the
    /// bottom `fadeHeight` of what the chip can actually show.
    private static func bottomFade(_ size: CGSize, visible: CGFloat, scale: CGFloat) -> CALayer? {
        guard size.height > visible, size.height > 0 else { return nil }
        // In the picture's own y-up coordinates, the chip shows everything above
        // this line and clips the rest.
        let cut = size.height - visible
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = scale
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let solid = NSColor.white.withAlphaComponent(1).cgColor
        layer.colors = [clear, clear, solid, solid]
        layer.locations = [0,
                           NSNumber(value: Double(cut / size.height)),
                           NSNumber(value: Double(min(1, (cut + fadeHeight) / size.height))),
                           1]
        return layer
    }

    /// How far ahead of the erasing edge the bright band rides, in points.
    private static var bandLead: CGFloat { bandWidth * leadFraction }

    /// The band's opacity over the sweep, as `(time, value)` stops.
    private static let glowKeys: [(at: CGFloat, value: CGFloat)] =
        [(0, 0), (0.15, 1), (0.8, 1), (1.0, 0)]

    private static func glowOpacity(at t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        for i in 1..<glowKeys.count {
            let a = glowKeys[i - 1], b = glowKeys[i]
            guard t <= b.at else { continue }
            let span = b.at - a.at
            let f = span > 0 ? (t - a.at) / span : 1
            return a.value + (b.value - a.value) * f
        }
        return glowKeys.last?.value ?? 0
    }

    /// CoreAnimation's `easeInEaseOut`, which is the cubic Bézier (0.42, 0,
    /// 0.58, 1), solved for y at x = t by Newton.
    ///
    /// Written out because `shoot` has to place the layers at an instant by hand
    /// and a sheet drawn from a *different* curve than the one that ships would
    /// be a picture of something nobody sees.
    private static func ease(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 0.42, c2: CGFloat = 0.58
        func curve(_ u: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
            let m = 1 - u
            return 3 * m * m * u * p1 + 3 * m * u * u * p2 + u * u * u
        }
        var u = min(max(t, 0), 1)
        for _ in 0..<8 {
            let dx = 3 * (1 - u) * (1 - u) * c1 + 6 * (1 - u) * u * (c2 - c1) + 3 * u * u * (1 - c2)
            guard Swift.abs(dx) > 1e-6 else { break }
            u -= (curve(u, c1, c2) - t) / dx
            u = min(max(u, 0), 1)
        }
        return curve(u, 0, 1)
    }

    /// The travelling boundary, as a mask: opaque on `keeping`'s side, clear on
    /// the other, sliding from one end of `travel` to the other.
    private static func sweep(size: CGSize, scale: CGFloat, keeping: Side) -> CALayer {
        let span = 2 * (size.width + size.height) + 200
        let edge = softEdge / span
        // Both stops are white — one at zero alpha — rather than `NSColor.clear`,
        // which is a *grey* colour and would have the gradient interpolate across
        // two colour spaces to say nothing more than "alpha goes from 0 to 1".
        let clear = NSColor.white.withAlphaComponent(0).cgColor
        let solid = NSColor.white.withAlphaComponent(1).cgColor
        let layer = CAGradientLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: span, height: span)
        layer.contentsScale = scale
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        // Local +x is *ahead* of the edge, so the picture that survives ahead of
        // the line — the outgoing one — is opaque at the far end of the gradient,
        // and the incoming one is opaque at the near end.
        layer.colors = keeping == .ahead ? [clear, clear, solid, solid]
                                         : [solid, solid, clear, clear]
        layer.locations = [NSNumber(value: 0.0), NSNumber(value: 0.5 - Double(edge)),
                           NSNumber(value: 0.5 + Double(edge)), NSNumber(value: 1.0)]
        layer.transform = rotation
        return layer
    }

    /// The bright band: a stripe of white that fades out on both of its own
    /// flanks, so it has no edges of its own to be seen. The only edge in this
    /// effect is the one doing the wiping.
    private static func band(size: CGSize, scale: CGFloat) -> CALayer {
        let span = 2 * (size.width + size.height) + 200
        let layer = CAGradientLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: span)
        layer.contentsScale = scale
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        // Not colour: coverage. The chip's words are *already* white, with a dark
        // halo behind them so they read over a terminal (`refreshChrome`), so
        // white light on white ink changes nothing by itself. What the band does
        // is fill that halo and — through the fattened stencil below — put a rim
        // on the stroke, which is what "a bit brighter" looks like on ink that
        // was white to begin with.
        layer.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.55).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        layer.locations = [NSNumber(value: 0.0), NSNumber(value: 0.5), NSNumber(value: 1.0)]
        layer.transform = rotation
        return layer
    }

    private static func slide(from: CGFloat, to: CGFloat, y: CGFloat, lead: CGFloat) -> CABasicAnimation {
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: NSPoint(x: from + lead, y: y))
        move.toValue = NSValue(point: NSPoint(x: to + lead, y: y))
        move.duration = duration
        // Eased at both ends rather than linear. A constant-speed wipe reads as a
        // machine part sliding through; a stroke starts and finishes, which is
        // what a hand does and what an oblique line drawn across a word is meant
        // to look like.
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        return move
    }

    // MARK: - The words, as a stencil

    /// One picture reduced to **where its white ink is**, fattened by a point, to
    /// be used as the band's mask.
    ///
    /// **Luminance, not alpha, and that is the whole of it.** Every row on the
    /// bare chip is white text carrying a dark halo (`RelayWindow.refreshChrome`)
    /// so that it reads over a terminal as well as over a white page — and the
    /// halo has alpha too. A stencil taken from the alpha channel is therefore a
    /// blurred blob around each glyph rather than the glyph, and lighting it up
    /// turns the row into a white smear with the letters lost inside it.
    /// Measured against a rendered sheet of the sweep: alpha-stencilled, the seam
    /// is an unreadable slab; luminance-stencilled it is the words, brighter.
    ///
    /// **The fattening is what makes the brightening visible at all.** White ink
    /// lit with white light is still the same white; what changes under the band
    /// is the *edge* of each glyph — the halo is filled and the stroke gains a
    /// rim, so the word reads as momentarily bolder and hotter rather than as
    /// unchanged. A one-point cross is enough, and is cheaper and cleaner than
    /// the eight-way ring it started as: on a 17pt face the diagonals only
    /// thicken what the axes already did.
    private static func stencil(_ frame: Frame, scale: CGFloat) -> CALayer? {
        let size = frame.size
        let pixelW = Int((size.width * scale).rounded())
        let pixelH = Int((size.height * scale).rounded())
        guard pixelW > 0, pixelH > 0 else { return nil }
        let bitmap = CGImageAlphaInfo.premultipliedLast.rawValue
        let space = CGColorSpaceCreateDeviceRGB()
        guard let flat = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: space, bitmapInfo: bitmap),
              let raw = flat.data else { return nil }
        flat.scaleBy(x: scale, y: scale)
        flat.draw(frame.image, in: CGRect(origin: .zero, size: size))
        // Premultiplied, so the brightest channel *is* the white ink's coverage —
        // a black halo at any alpha reads as zero here, which is the point.
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        for row in 0..<flat.height {
            for column in 0..<flat.width {
                let p = bytes + row * flat.bytesPerRow + column * 4
                let lit = max(p[0], max(p[1], p[2]))
                p[0] = lit; p[1] = lit; p[2] = lit; p[3] = lit
            }
        }
        guard let ink = flat.makeImage(),
              let fat = CGContext(data: nil, width: pixelW, height: pixelH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: bitmap) else { return nil }
        fat.scaleBy(x: scale, y: scale)
        let full = CGRect(origin: .zero, size: size)
        for offset in [CGPoint.zero, CGPoint(x: dilation, y: 0), CGPoint(x: -dilation, y: 0),
                       CGPoint(x: 0, y: dilation), CGPoint(x: 0, y: -dilation)] {
            fat.draw(ink, in: full.offsetBy(dx: offset.x, dy: offset.y))
        }
        guard let mask = fat.makeImage() else { return nil }
        let layer = CALayer()
        layer.frame = full
        layer.contents = mask
        layer.contentsScale = scale
        return layer
    }

    /// How far the stencil is grown past the ink, in points.
    private static let dilation: CGFloat = 1
}
