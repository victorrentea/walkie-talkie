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

    /// **Twice the size while the words are in flight** — Victor, 2026-09-22:
    /// *"când o dictare la caret este în procesul de transcriere, săgețile cele
    /// trei de sus și jos … trebuie să se dubleze ca mărime … Cele care apar
    /// atunci când fac o pauză în dictare să rămână ca până acum."*
    ///
    /// The two states this shape has were drawn identically and mean different
    /// things. The silence one is a *suggestion* — he has stopped talking, the
    /// caret could go anywhere, and he may perfectly well go on speaking, in
    /// which case the heads fade and nothing was owed. `hold` is not a
    /// suggestion: the microphone is shut, the sentence is coming, and the
    /// pointer must stay where it is until it lands. Same shape at the same size
    /// for both leaves the one moment that has a deadline in it looking exactly
    /// like the one that does not.
    ///
    /// **Size and not colour, speed or count**, because size is the only channel
    /// on this shape that is not already carrying something: the amber is *this
    /// is the arrow*, the wave's rhythm is *inward*, and three a side is the
    /// sequence. Doubling it also puts the outermost pair at 88 pt out, past the
    /// ring's inner hole and into its band, where a bigger shape has to be to
    /// stay legible at all.
    ///
    /// Applied to the container about its own centre — which is the pointer's
    /// hot spot — so the arrangement stays symmetric about the thing it points
    /// at, which is the whole of why it is six heads and not one arrow.
    static let holdScale: CGFloat = 2

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
    /// The container the heads hang off, kept so `hold` can double it. Rebuilt
    /// only with the panel, which is built once for the life of the process.
    private var heads: CALayer?
    /// What `heads.transform` is set to, so a 20 Hz `refresh` does not re-assign
    /// the same transform forty times a second and hand Core Animation forty
    /// chances to animate it implicitly.
    private var scale: CGFloat = 1
    /// A `recall` fade is in flight. Without it every 20 Hz tick through a
    /// silence-that-ended would start another one, and the completion handler of
    /// a fade that has since been overruled would order out a visible panel.
    private(set) var fading = false
    /// The heads are up for the words in flight rather than for the silence —
    /// see `hold`. Cleared only by `hide`, which is the delivery.
    private(set) var holding = false

    /// **What the window is actually doing**, beside what the flags claim — read
    /// by `CaretHalo`'s idle sweep and answered in `GET /test/state.halo`.
    /// `isVisible` is AppKit's own reading and it goes false the instant
    /// `orderOut` is called, so a yes here with nothing in flight is a window
    /// standing on his screen and nothing else.
    var isVisible: Bool { panel?.isVisible ?? false }
    var alpha: CGFloat { panel?.alphaValue ?? 0 }
    var report: [String: Any] {
        ["visible": isVisible, "alpha": Double(alpha),
         "armed": armed, "holding": holding, "fading": fading]
    }

    /// Moved by `CaretHalo.follow`, with the ring and in the same call — see the
    /// type comment for why this is not its own monitor.
    func place(at origin: NSPoint) {
        panel?.setFrameOrigin(origin)
    }

    /// **The words are on their way to the caret — the heads stay up and stop
    /// listening to the microphone** (2026-09-15).
    ///
    /// Victor: *"după ce dictarea se oprește, fulgerul dispare, doar că rămân
    /// săgețile care curg până când efectiv se inseră textul la caret … să-mi
    /// atragă atenția că dictarea încă se procesează și curge spre cursor și să
    /// nu plec cu cursorul de acolo."* Between the microphone closing and the
    /// ⌘V there is a second or two in which the pointer must not wander, and
    /// until now there was nothing on screen saying so: the ring goes down at the
    /// close (it means *microphone open*) and these went down with it.
    ///
    /// It is the same wave, at full strength, for a reason: the shape already
    /// means *the sentence lands here* and a second vocabulary for the same
    /// place would be one more thing to learn. What changes is only what drives
    /// it — `refresh` ramps it in with the silence, which is a question about
    /// whether he has stopped talking; this is past that question and the
    /// answer is yes.
    ///
    /// Idempotent, because it is called from every `follow()` the pointer
    /// produces: the fade in runs once, on the edge, and a second call only
    /// moves the window.
    func hold(at origin: NSPoint) {
        let p = panel ?? makePanel()
        p.setFrameOrigin(origin)
        guard !holding else { return }
        holding = true
        setScale(Self.holdScale)
        // A fade already in flight is overruled rather than waited out — its
        // completion handler orders the window out, and this is the one state
        // where the window has to stay.
        fading = false
        if !p.isVisible {
            p.alphaValue = 0
            p.orderFrontRegardless()
        }
        // `recall`'s length, not the swell's: the wait has already begun, and
        // two seconds of fading in is two seconds of the message he needs *now*
        // arriving late. Short enough to read as *and now they are up*, long
        // enough not to be its own flash.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.recall
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = CGFloat(Self.ceiling)
        }
    }

    /// Sampled at the halo's own 20 Hz rather than animated, for the halo's own
    /// reason: the input is a continuous function of a clock that restarts every
    /// time he says a word, so an animation would be interpolating toward a
    /// target that has already moved.
    func refresh(quiet: TimeInterval, at origin: NSPoint) {
        // **`holding` outranks the microphone**, and it has to: the meter keeps
        // answering after the close, and the one thing that must not happen
        // while the words are in flight is the heads dimming because a clock
        // somewhere says he is talking again.
        guard armed, !holding else { return }
        let t = max(0, min(1, (quiet - CaretHalo.patience) / CaretHalo.swell))
        guard t > 0 else { return fadeAway() }
        let p = panel ?? makePanel()
        // The silence's own size, whatever the last dictation left behind.
        setScale(1)
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
    ///
    /// **A cut, and after a `hold` that is the point**: the heads go at the
    /// instant the ⌘V does, so what replaces them is the words appearing. A fade
    /// there would still be on screen asking him to stay put after the sentence
    /// had already landed.
    func hide() {
        fading = false
        holding = false
        panel?.orderOut(nil)
        panel?.alphaValue = 0
        setScale(1)
    }

    /// **Instant, both ways.** Core Animation would animate a transform over a
    /// quarter of a second on its own, and neither end of this wants that: the
    /// growth *is* the message that the sentence is now on its way, and a
    /// shrink is only ever seen on a window that has already been ordered out.
    private func setScale(_ value: CGFloat) {
        guard scale != value, let heads else { scale = value; return }
        scale = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heads.transform = CATransform3DMakeScale(value, value, 1)
        CATransaction.commit()
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
        let container = build()
        heads = container
        scale = 1
        view.layer?.addSublayer(container)
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
    /// - Parameter scale: `holdScale` draws the pose the heads wear while the
    ///   words are in flight, which is otherwise only on screen for the second
    ///   or two between a stop and a ⌘V.
    static func picture(scale: CGFloat = 1) -> CALayer {
        let layer = DropArrow().build(posed: 1)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        return layer
    }

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
        // **Bare literals, never `.map(NSNumber.init)`.** That bare function
        // reference compiles and resolves to an `NSValue` initialiser, so the
        // array comes out full of `NSConcreteValue` — no `floatValue` on it —
        // and QuartzCore's `copyFloatVector` throws an unrecognised-selector
        // exception inside the `CATransaction` flush. An NSException there is
        // not catchable from Swift: it killed the app 7 s into the first Wispr
        // dictation that raised these heads (2026-09-12, `SIGTRAP` in
        // `-[NSApplication _crashOnException:]`). Under a `[NSNumber]?`
        // contextual type the literals bridge to `__NSCFNumber` correctly, which
        // is the form every other keyframe in this app already uses.
        a.keyTimes = [0, 0.06, 0.22, 1]
        a.duration = cycle
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.timeOffset = Double(ring) * lead
        a.isRemovedOnCompletion = false
        return a
    }
}
