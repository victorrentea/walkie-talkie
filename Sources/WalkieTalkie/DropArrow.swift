import AppKit
import QuartzCore

/// **Six arrowheads closing on the pointer — three from above, three from
/// below — flashing inward whenever a dictation with nowhere to go falls
/// quiet.**
///
/// Victor's ask, 2026-09-11: *"ca să pot distinge când dictez fără țintă, vreau
/// ca atunci când tac, când nu mai vorbesc, să apară o animație … care se plimbă
/// cu mouse-ul, ca să sugereze cumva că trebuie să lase acel prompt undeva"*.
///
/// And the shape it settled into a few hours later, which is what ships:
/// *"trebuie ca, atunci când mă opresc din dictare, să apară trei capete de
/// săgeți de sus și trei capete de săgeți de jos care clipesc cumva spre
/// interior, spre cursor, ca să-mi atragă atenția să depun dictarea undeva …
/// dacă vorbesc, ele fac fade-out repede, dar cum nu se mai aude voce, fac … ca
/// și cum m-ar atrage privirea spre locul în care e cursorul, ca să pun textul
/// unde trebuie"*.
///
/// ## It exists because the ring stopped being able to say this
///
/// The halo used to be the whole answer: it was up for `at caret` dictations and
/// for nothing else, so its mere presence meant *these words land wherever the
/// focus happens to be, go and put the focus somewhere*. Since the ring became
/// the voice indicator for **every** dictation — Wispr Flow's included — that
/// reading is gone: a ring on screen means the microphone is open, which is
/// equally true of a sentence headed for a bound terminal.
///
/// So the distinction had to be re-said in something that could only mean one
/// thing, at the only place the gesture happens.
///
/// ## Why six heads and not one arrow
///
/// It shipped for four hours as **one dotted arrow above the cursor pointing
/// down** — three dashes marching into a head, the literal reading of the first
/// ask. What was wrong with it is what the replacement is built out of: an arrow
/// hanging above the pointer is a thing to *read*, and reading it costs a
/// fixation. It says *down there* while sitting somewhere else, so the eye lands
/// on the arrow first and on the cursor second, and the cursor is the whole
/// message.
///
/// Six heads closing in from both sides say it without being looked at. They are
/// **symmetric about the hot spot**, so there is no shape off to one side to
/// catch the eye — the only thing the arrangement can point at is its own
/// centre, which is the pointer. And the flash runs **outside → inside**, so
/// what moves is a convergence rather than an object: peripheral vision is built
/// to follow exactly that, which is the property being borrowed
/// (*"ca și cum m-ar atrage privirea spre locul în care e cursorul"*).
///
/// The dashes' rule survives the redesign, in the flash instead of a march:
/// **linear, steady, no easing** — a hint that hesitates is a hint being
/// admired.
///
/// ## Silence is still the trigger, and for the old reason
///
/// It inherits the swell's schedule whole — `CaretHalo.patience` of quiet before
/// anything appears, `CaretHalo.swell` to fade in. While he is talking the paste
/// is not imminent and there is nothing to ask; the moment he stops, the
/// sentence is about to be delivered and placing the caret is still free. Two
/// seconds rather than instantly because the gaps *inside* a sentence are
/// ordinary — he pauses to think mid-dictation constantly, and something
/// blinking on every breath is a light flashing at the corner of his eye for the
/// length of every sentence.
///
/// **Going away is a fade, not a cut** (*"ele fac fade-out repede"*). `quiet`
/// snaps to zero on the first voiced buffer, so the panel used to be ordered out
/// between two frames — a disappearance sharp enough to be its own event, at the
/// exact moment his attention should be going back to the sentence. `recall` is
/// short enough that it is gone before he has finished the next word and long
/// enough that nothing snaps.
///
/// ## A panel of its own, and the contact sheet is what proved it had to be
///
/// It was a layer inside `CaretHalo`'s panel for an hour — the obvious build,
/// since that window already sits at the pointer and follows it, and two windows
/// chasing one cursor is two chances to be a frame apart. `WT_SHOOT_HALO`'s
/// arrow sheet is what killed it: **the halo's window alpha is the voice**, and
/// this appears exactly when the voice has stopped, so it was being drawn
/// through the ring's *floor* — 0.75 × 0.148, i.e. a stain. There is no layer
/// opacity that recovers it, because the number it would have to undo is on the
/// window.
///
/// So it has a window, and it is `CaretHalo` that moves it: the same `follow()`
/// that places the ring places this, off the same two monitors, in the same
/// call. The frames cannot be a frame apart because there is only one frame.
///
/// It keeps `sharingType = .none` and is invisible to every screenshot for the
/// reason the ring is — the shutter is live in Replace Wispr, which is the only
/// mode this is ever drawn in.
final class DropArrow {

    /// **How far from the pointer's hot spot the innermost pair sits.** Far
    /// enough to clear the macOS arrow cursor on both sides — its body hangs
    /// *below* the hot spot, which is why this cannot be the 14pt the old single
    /// arrow used above it — close enough that the convergence has an obvious
    /// centre.
    private static let gap: CGFloat = 18
    /// Between one head and the next. Three heads then span `gap`…`gap + 2×step`
    /// — 18 to 44 pt out, which stays inside the halo's hole (~36 pt) and the
    /// inner ramp of its band, where the film is at its faintest.
    private static let step: CGFloat = 13
    /// **Three a side, which is what he asked for.** Two would not read as a
    /// sequence and four crowd the ring's inner rim.
    private static let heads = 3
    private static let halfWidth: CGFloat = 10
    private static let headHeight: CGFloat = 7
    private static let stroke: CGFloat = 3.2

    /// One full turn of the flash. The wave itself is over in `lead × (heads−1)`
    /// and the rest is dark: a beat between sweeps is what makes it a pulse
    /// rather than a shimmer.
    private static let cycle: CFTimeInterval = 1.4
    /// How far behind the head outside it each one flashes. Fast enough that the
    /// three read as one movement inward rather than three separate blinks.
    private static let lead: CFTimeInterval = 0.14
    /// What a head sits at when the wave is elsewhere. Not zero: the arrangement
    /// has to be legible as a whole between sweeps, or every sweep is a new
    /// shape appearing rather than a light travelling along one.
    ///
    /// **0.40, off the contact sheet, not off the dark ground.** At 0.28 the
    /// unlit heads read fine over a terminal and all but vanished on the white
    /// half of `halo-arrow.png` — 0.28 × `ceiling` is 0.21 of amber on paper,
    /// which the shadow outline alone was holding up. The lit head is still 2.5×
    /// its neighbours, which is all the wave needs.
    private static let dim: Float = 0.40

    /// The fade when he starts talking again — see the type comment.
    private static let recall: TimeInterval = 0.18

    /// **Amber, the halo's own ink.** The film that fills the ring is blue and
    /// magenta, so this is the one hue in the app's palette that cannot be
    /// mistaken for part of it at a glance, and it is the colour every drawn
    /// halo design was tinted with before the picture replaced them.
    private static let ink = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.25, alpha: 1)
    /// Brighter than the ring, and allowed to be: these are small shapes made of
    /// thin strokes, on screen for the seconds between sentences, and they are
    /// the one thing here he is meant to actually read rather than notice.
    static let ceiling: Float = 0.75

    /// Whether this dictation is one the heads have anything to say about — set
    /// from `CaretHalo.setActive`, and taken away the instant a ⌘⌃B mid-sentence
    /// gives the words a terminal.
    var armed = false {
        didSet {
            guard armed != oldValue else { return }
            if !armed { hide() }
        }
    }

    private var panel: RelayPanel?
    /// A `recall` fade is in flight. Without it every 20 Hz tick through a
    /// silence-that-ended would start another one, and the completion handler of
    /// a fade that has since been overruled would order out a visible panel.
    private var fading = false

    /// Moved by `CaretHalo.follow`, with the ring and in the same call — see the
    /// type comment for why this is not its own monitor.
    func place(at origin: NSPoint) {
        panel?.setFrameOrigin(origin)
    }

    /// Sampled at the halo's own 20 Hz rather than animated, for the halo's own
    /// reason: the input is a continuous function of a clock that restarts every
    /// time he says a word, so an animation would be interpolating toward a
    /// target that has already moved.
    func refresh(quiet: TimeInterval, at origin: NSPoint) {
        guard armed else { return }
        let t = max(0, min(1, (quiet - CaretHalo.patience) / CaretHalo.swell))
        guard t > 0 else { return fadeAway() }
        let p = panel ?? makePanel()
        p.setFrameOrigin(origin)
        // Overruling a fade that is still running: the animator owns
        // `alphaValue` until it is told otherwise, so the proxy has to be the one
        // that hears about it — and `fading` going down is what stops the fade's
        // completion handler ordering the window out from under this.
        if fading {
            fading = false
            p.animator().alphaValue = CGFloat(Self.ceiling) * CGFloat(t)
        } else {
            p.alphaValue = CGFloat(Self.ceiling) * CGFloat(t)
        }
        // `orderFrontRegardless`, like the ring: this app never becomes key, so
        // an ordinary `orderFront` would put it behind whatever is.
        if !p.isVisible { p.orderFrontRegardless() }
    }

    /// He is talking again — go, but go softly.
    private func fadeAway() {
        guard let p = panel, p.isVisible, !fading else { return }
        fading = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.recall
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.fading else { return }
            self.fading = false
            p.orderOut(nil)
        })
    }

    /// The hard stop — a bind mid-sentence, or the dictation ending. Nothing is
    /// being asked for any more, so there is nothing to fade out of.
    func hide() {
        fading = false
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    private func makePanel() -> RelayPanel {
        let side = CaretHalo.side
        // `RelayPanel` and not `NSPanel`, for `CaretHalo`'s reason:
        // `constrainFrameRect` drags a borderless window back onto the display
        // and under the menu bar, which for something pinned to the pointer
        // would shove it off the cursor near the top of a screen.
        let p = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = CaretHalo.capturable ? .readOnly : .none
        p.alphaValue = 0
        // **The same box as the ring**, so one origin places both — this needs a
        // tenth of it, and a second rectangle to keep in step with the first is a
        // second thing to get wrong.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.addSublayer(build())
        p.contentView = view
        panel = p
        return p
    }

    // MARK: - Drawing

    /// The drawing on its own, for `CaretHalo.shootArrow` — the only way to look
    /// at a shape that lives on a `sharingType = .none` window and is only up
    /// between two sentences.
    ///
    /// **Posed, not animated**, the rule `ChipWipe.shoot` set: a still of a
    /// repeating animation is whatever frame the screenshot happened to land on.
    /// The pose is the wave halfway in — the outer pair already dim again, the
    /// middle pair lit — which is the only frame that shows what the sweep is
    /// doing.
    static func picture() -> CALayer { DropArrow().build(posed: 1) }

    /// - Parameter posed: `nil` ships the flash as a repeating animation; an
    ///   index freezes it with that ring of heads lit and the others at `dim`.
    private func build(posed: Int? = nil) -> CALayer {
        let side = CaretHalo.side
        let c = side / 2

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: side, height: side)
        // The one concession to backgrounds this cannot know: amber on a white
        // page is legible, amber on a pale-yellow one is not, and a shape with
        // an outline of shadow is legible on both. Same trick the chip's rows
        // use (`RelayWindow.halo`).
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.55
        container.shadowRadius = 3
        container.shadowOffset = .zero

        for ring in 0..<Self.heads {
            let distance = Self.gap + Self.step * CGFloat(ring)
            // Both heads of a ring share one layer and therefore one flash: they
            // are the two halves of a single event closing in, and a pair that
            // could drift apart by a frame would read as two hints rather than
            // one.
            let pair = CALayer()
            pair.frame = container.bounds
            pair.addSublayer(Self.head(at: c, distance: distance, pointingDown: true))
            pair.addSublayer(Self.head(at: c, distance: distance, pointingDown: false))

            if let posed {
                pair.opacity = ring == posed ? 1 : Self.dim
            } else {
                pair.opacity = Self.dim
                pair.add(Self.flash(ring: ring), forKey: "flash")
            }
            container.addSublayer(pair)
        }

        return container
    }

    /// One arrowhead: an open V, never a filled triangle. A stroke reads as a
    /// direction and a fill reads as an object, and six objects around the
    /// pointer would be six things in the way of what they are pointing at.
    private static func head(at c: CGFloat, distance: CGFloat, pointingDown: Bool) -> CAShapeLayer {
        let sign: CGFloat = pointingDown ? 1 : -1
        // The vertex is the end nearest the pointer; the arms open away from it.
        let vertexY = c + sign * distance
        let armY = c + sign * (distance + headHeight)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: c - halfWidth, y: armY))
        path.addLine(to: CGPoint(x: c, y: vertexY))
        path.addLine(to: CGPoint(x: c + halfWidth, y: armY))

        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = nil
        layer.strokeColor = ink.cgColor
        layer.lineWidth = stroke
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    /// The wave, one ring's share of it.
    ///
    /// **`timeOffset`, not `beginTime`.** A `beginTime` is an absolute point on
    /// the layer's timeline, so the phases would be set relative to whenever the
    /// panel happened to be built — and this panel is built once and shown again
    /// on every silence for the rest of the day. `timeOffset` shifts where in
    /// its own repeating cycle the animation starts and keeps meaning that
    /// forever.
    ///
    /// The **outermost** ring gets the largest offset, so it is furthest along
    /// its cycle and lights first; the innermost is last. Outside in, which is
    /// the direction the eye is being walked.
    private static func flash(ring: Int) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [dim, 1.0, dim, dim]
        // Up fast, down over roughly twice as long, then dark for the rest of the
        // cycle — a rise the eye catches and a fall it does not have to watch.
        a.keyTimes = [0, 0.06, 0.22, 1].map(NSNumber.init)
        a.duration = cycle
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.timeOffset = Double(ring) * lead
        a.isRemovedOnCompletion = false
        return a
    }
}
