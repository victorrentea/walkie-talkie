import AppKit
import QuartzCore

/// **A map pin standing on the caret for the whole of a caret dictation — and
/// glinting when he falls quiet** (2026-10-14).
///
/// Victor: *"When I dictate at caret, simple dictation or prompt at caret,
/// there should be the same icon as the one displayed in the tooltip but larger
/// like a pin on Google Maps, which is pointing exactly to where the caret is
/// … And if that … cursor location changes, [the pin] should follow it. And
/// that can allow you to replace the arrows pointing to the cursor when I am
/// silent. By making the pin somehow have a effect of glow … shining
/// diagonally … to remind me that's where I'm gonna inject my text or prompt."*
///
/// **Supersedes the six heads** (2026-09-12 → 2026-10-13: three amber Vs above
/// and three below, flashing inward on silence). The class keeps its name and
/// every entry point `CaretHalo` drives — `armed`, `refresh(quiet:at:)`,
/// `hold(at:)`, `hide()` — so the schedule the heads were tuned to is the
/// pin's schedule too. What changed is what the schedule turns on and off:
///
/// | moment | heads (until 2026-10-13) | pin |
/// |---|---|---|
/// | talking | nothing | the pin, plain |
/// | `patience` of quiet, then `swell` | the heads fade in | the glint and the glow fade in |
/// | words in flight (`hold`) | heads ×2 | pin ×`holdScale`, pulsing, shine at full and unbroken, a ring filling in the hole |
/// | the ⌘V | cut | cut |
///
/// **Always up while he talks**, because the pin answers *where*, and that is
/// a question for the whole sentence; the heads only answered *put it
/// somewhere*, which only the silence asked. The silence now changes how loud
/// the answer is, not whether there is one.
///
/// **The tooltip's own glyph** (`Glyphs.mapPinShape`, the shape behind
/// `RelayWindow.pinGlyph`), so the chip's `caret` row and the mark on the caret
/// are one sign at two sizes. **Its tip on the caret**: `CaretHalo.headsAt` is
/// the caret line's middle (`TerminalBinding.caret`), so the tip sits
/// `tipLift` above it, on the top of the line — the pin stands on the line
/// rather than stabbing through the letters.
///
/// **The shine is two things at one opacity**: an amber glow round the pin that
/// breathes (`glowBreath`), and a white band that sweeps across it bottom-left
/// to top-right (`glintSweep`, then `glintRest` dark) — the diagonal shine he
/// asked for, clipped to the pin's shape so it reads as light on the pin and
/// not as a stripe on the page. Amber is the heads' ink and the orange
/// outline's family (`FocusFrame`): *the words land here*.
///
/// ## A panel of its own, moved by `CaretHalo`
///
/// The heads' reason still holds: the halo's window alpha *is* the voice, so
/// anything drawn in it is drawn through the ring's floor. This window is the
/// size of the ring's (one origin places both — `CaretHalo.headsOrigin`), is
/// click-through, and keeps `sharingType = .none`, so no screenshot sees it.
final class DropArrow {

    /// The pin's height — the chip's is 18 (`RelayWindow.pinGlyph`). 46 pt at
    /// first, the size of the marker Google Maps drops; **92 since 2026-10-15**,
    /// Victor: *"make the [pin] that is displayed when I dictate a prompt at the
    /// caret two times larger"*.
    private static let pinHeight: CGFloat = 92
    /// From the caret line's middle to its top — where the tip sits. Half a
    /// typical 15–18 pt editor line.
    private static let tipLift: CGFloat = 8

    /// One sweep of the glint across the pin, then `glintRest` of nothing: a
    /// beat between sweeps is what makes it a glint and not a shimmer.
    private static let glintSweep: CFTimeInterval = 0.7
    private static let glintRest: CFTimeInterval = 0.9
    /// One breath of the glow, in and out.
    private static let glowBreath: CFTimeInterval = 1.6

    /// The fade of the pin's first appearance and of the shine when he talks
    /// again — short enough to be gone before the next word, long enough not to
    /// snap (the heads' *"ele fac fade-out repede"*).
    private static let recall: TimeInterval = 0.18

    /// **Larger while the words are in flight** (the heads' 2026-09-22 rule:
    /// the moment with a deadline in it must not look like the one without).
    /// ×2 doubled three thin Vs; a 92 pt pin doubled is a thing in the way, so
    /// ×1.3 — about the tip, so the point does not move off the caret.
    /// **×1.4, and breathing up to `pulseScale` × that** (2026-10-20, Victor:
    /// *"once I end the dictation, it gets bigger … and pulsates smaller bigger,
    /// smaller bigger until the … transcription [ends]. Shining as well"*).
    static let holdScale: CGFloat = 1.4
    static let pulseScale: CGFloat = 1.15
    /// One breath, out and back.
    private static let pulsePeriod: CFTimeInterval = 0.9

    /// **A thin ring round the pin's hole fills until the local model would
    /// take the sentence anyway** (2026-10-20, Victor: *"a progress bar inside
    /// the hole, on that pin"*, then *"make … that circle progress bar complete
    /// when the local model would [deliver] the [transcription] anyway … a
    /// transparent center … a bit thinner overall"*). Linear over the AutoLocal
    /// budget, from the close (`localClock`, pushed by `AppDelegate.syncLocalNow`
    /// — the clock the chip's `💻 local in 3s` counts down); with no budget
    /// running (AutoLocal off), over the decode estimate `hold` was given. Full
    /// is the hand-over, and it stays full.
    static func progress(elapsed: TimeInterval, span: TimeInterval) -> CGFloat {
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, elapsed / span)))
    }

    /// The AutoLocal budget for the words in flight: the close, and its length.
    var localClock: (since: CFAbsoluteTime, seconds: TimeInterval)?

    /// The heads' amber.
    private static let ink = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.25, alpha: 1)
    /// The window's alpha when up — the pin is solid. Read by the contact sheet.
    static let ceiling: Float = 1

    /// Whether this dictation is one the pin has anything to say about — set
    /// from `CaretHalo`, and taken away the instant a ⌘⌃B mid-sentence gives
    /// the words a terminal or the caret is lost.
    var armed = false {
        didSet {
            guard armed != oldValue else { return }
            if !armed { hide() }
        }
    }

    /// **No caret to stand on — the pin is grey and crossed out, and never
    /// shines** (2026-10-14, Victor: *"when you don't have where to put the pin,
    /// there is no cursor, tell that visually somehow"*). Placed by `CaretHalo`
    /// on the middle of the window the words would go to (`noCaretAt`). Grey
    /// because the red is *here*; a red ✕ because that is *nowhere* in every
    /// app he uses.
    var crossed = false {
        didSet {
            guard crossed != oldValue else { return }
            applyCrossed()
        }
    }

    /// Hidden with the ring while a crop is framed — see `CaretHalo.veiled`.
    var veiled = false {
        didSet {
            guard veiled != oldValue, let view = panel?.contentView else { return }
            CaretHalo.veil(view, veiled)
        }
    }

    private var panel: RelayPanel?
    /// The pin and its shine, scaled about the tip by `hold`.
    private var pin: CALayer?
    /// The glow and the glint, whose opacity is the silence.
    private var shineLayers: [CALayer] = []
    private var body: CAShapeLayer?
    private var cross: CALayer?
    private var glint: CAGradientLayer?
    /// The ring round the hole, and its arc.
    private var ring: CALayer?
    private var arcs: [CAShapeLayer] = []
    private var progressTimer: Timer?
    private var holdFrom: CFAbsoluteTime = 0
    private var holdEstimate: TimeInterval = 0
    private(set) var progressShown: CGFloat = 0
    private var scale: CGFloat = 1
    private var shine: Float = 0
    /// The appearance fade is in flight — a 20 Hz `refresh` must not restart it.
    private(set) var fading = false
    /// Up for the words in flight rather than for the dictation — see `hold`.
    /// Cleared only by `hide`, which is the delivery.
    private(set) var holding = false

    /// **What the window is actually doing**, beside what the flags claim — read
    /// by `CaretHalo`'s idle sweep and answered in `GET /test/state.halo.heads`.
    var isVisible: Bool { panel?.isVisible ?? false }
    var alpha: CGFloat { panel?.alphaValue ?? 0 }
    var report: [String: Any] {
        var r: [String: Any] = ["visible": isVisible, "alpha": Double(alpha), "shine": Double(shine), "crossed": crossed,
                                "armed": armed, "holding": holding, "fading": fading,
                                "progress": Double(progressShown), "estimate": holdEstimate,
                                "localBudget": localClock?.seconds ?? 0]
        if let f = panel?.frame { r["frame"] = [f.minX, f.minY, f.width, f.height] }
        if let t = panel?.contentView?.layer?.sublayerTransform { r["shift"] = [t.m41, t.m42] }
        return r
    }

    /// Moved by `CaretHalo`, on every caret reading and every pointer event.
    func place(at origin: NSPoint) {
        if let p = panel { move(p, to: origin) }
    }

    /// **The window stays on the caret's display, the pin on the caret**
    /// (2026-10-20, Victor: *"the pin pointing to where the cursor is
    /// flickering between two terminals"*). The box is the ring's, 422 pt,
    /// centred on the caret; for a terminal tiled against the ASUS's left edge
    /// (caret x ≈ 1757, the edge at 1728) it hung ~180 pt onto the Retina, and
    /// with *Displays have separate Spaces* on, a window across two displays is
    /// drawn on one of them at a time — the pin flickered while the reading
    /// under it stood still (`focusFrame.caret` polled at 10 Hz: one value per
    /// click). Measured on his four tiles: only the two at x = 1730 flickered.
    /// So the window is slid inside the caret's screen and its content slid
    /// back by the same amount; a pin within its own half-width of an edge is
    /// clipped there, never split.
    private func move(_ p: RelayPanel, to origin: NSPoint) {
        let side = CaretHalo.side
        let caret = NSPoint(x: origin.x + side / 2, y: origin.y + side / 2)
        var o = origin
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(caret) })?.frame {
            o.x = min(max(o.x, screen.minX), screen.maxX - side)
            o.y = min(max(o.y, screen.minY), screen.maxY - side)
        }
        p.setFrameOrigin(o)
        let back = CATransform3DMakeTranslation(origin.x - o.x, origin.y - o.y, 0)
        guard let layer = p.contentView?.layer, !CATransform3DEqualToTransform(layer.sublayerTransform, back) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = back
        CATransaction.commit()
    }

    /// **The words are on their way to the caret — the pin grows, breathes and
    /// shines at full until they land, a ring filling round its hole** (the
    /// heads' 2026-09-15 rule: *"să nu plec cu cursorul de acolo"*; the pulse and
    /// the ring 2026-10-20). Idempotent: called from every `follow()`;
    /// `estimate` is read on the first call only, and only stands in for a
    /// `localClock` that is not running.
    ///
    /// **`since` is the close, not this call** (2026-10-21, Victor: *"If I change
    /// the focus of a window during the progress bar … the wheel seems to start
    /// anew from scratch. It should continue where it left off"*). A focus
    /// change through a window with no caret takes the pin down (`armed` off →
    /// `hide`) and the next reading raises it again with a fresh `hold`; the
    /// ring is a function of the sentence's own clock (`CaretHalo.deliverFrom`),
    /// so a re-raised pin comes back at the fill it would have had anyway.
    func hold(at origin: NSPoint, estimate: TimeInterval = 0, since: CFAbsoluteTime? = nil) {
        let p = panel ?? makePanel()
        move(p, to: origin)
        guard !holding else { return }
        holding = true
        setScale(Self.holdScale)
        setShine(1, animated: true)
        setInFlight(true, estimate: estimate, since: since ?? CFAbsoluteTimeGetCurrent())
        appear(p)
    }

    /// The pulse, the unbroken glint and the ring — on for the words in flight,
    /// off at the delivery.
    private func setInFlight(_ on: Bool, estimate: TimeInterval = 0, since: CFAbsoluteTime = 0) {
        progressTimer?.invalidate()
        progressTimer = nil
        progressShown = 0
        guard let pin else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if on {
            let a = CABasicAnimation(keyPath: "transform.scale")
            a.fromValue = Self.holdScale
            a.toValue = Self.holdScale * Self.pulseScale
            a.duration = Self.pulsePeriod / 2
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.isRemovedOnCompletion = false
            pin.add(a, forKey: "pulse")
        } else {
            pin.removeAnimation(forKey: "pulse")
        }
        if let glint { Self.sweep(glint, rest: on ? 0 : Self.glintRest) }
        // Crossed means nowhere to land: nothing is filling — but the clock
        // runs on, so a pin that finds a caret again shows the fill it has
        // earned (`applyCrossed`).
        ring?.isHidden = !(on && !crossed)
        for arc in arcs { arc.strokeEnd = 0 }
        CATransaction.commit()
        guard on else { return }
        holdFrom = since
        holdEstimate = estimate
        // Drawn now, not a tick later: a pin raised again mid-flight must not
        // show one frame of an empty ring.
        tickProgress()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tickProgress() }
        RunLoop.main.add(t, forMode: .common)
        progressTimer = t
    }

    private func tickProgress() {
        let now = CFAbsoluteTimeGetCurrent()
        let v = localClock.map { Self.progress(elapsed: now - $0.since, span: $0.seconds) }
            ?? Self.progress(elapsed: now - holdFrom, span: holdEstimate)
        guard abs(v - progressShown) > 0.002 else { return }
        progressShown = v
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for arc in arcs { arc.strokeEnd = v }
        CATransaction.commit()
    }

    /// Sampled at the halo's 20 Hz: the pin is up whenever armed, the shine
    /// follows the silence — `patience` of quiet, then up over `swell`.
    func refresh(quiet: TimeInterval, at origin: NSPoint) {
        // **`holding` outranks the microphone** — the meter keeps answering
        // after the close, and the shine must not dim while the words travel.
        guard armed, !holding else { return }
        let p = panel ?? makePanel()
        setScale(1)
        move(p, to: origin)
        let t = Float(max(0, min(1, (quiet - CaretHalo.patience) / CaretHalo.swell)))
        // Talking again: the shine goes softly, once; the ramp itself is set
        // straight, it is already a 20 Hz curve.
        setShine(t, animated: t == 0 && shine > 0)
        appear(p)
    }

    /// The hard stop — a bind mid-sentence, the caret lost, or the ⌘V. A cut:
    /// what replaces the pin is the words appearing.
    func hide() {
        fading = false
        if holding { setInFlight(false) }
        // `localClock` is the sentence's, not the pin's: a hide on the way to
        // another window must not lose it (2026-10-21). `CaretHalo.setDelivering(false)`
        // clears it at the delivery, `AppDelegate.syncLocalNow` whenever no budget runs.
        holding = false
        panel?.orderOut(nil)
        panel?.alphaValue = 0
        setScale(1)
        setShine(0, animated: false)
    }

    /// In over `recall` the first time; nothing on a window already up.
    /// `orderFrontRegardless`, like the ring: this app never becomes key.
    private func appear(_ p: RelayPanel) {
        guard !p.isVisible || p.alphaValue < CGFloat(Self.ceiling), !fading else { return }
        if !p.isVisible {
            p.alphaValue = 0
            p.orderFrontRegardless()
        }
        fading = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.recall
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = CGFloat(Self.ceiling)
        }, completionHandler: { [weak self] in self?.fading = false })
    }

    /// Instant unless asked — Core Animation would otherwise animate every
    /// 20 Hz assignment over a quarter of a second on its own.
    private func setShine(_ value: Float, animated: Bool) {
        // Nothing to remind him of: the words have nowhere to land.
        let value = crossed ? 0 : value
        guard shine != value else { return }
        shine = value
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Self.recall)
        } else {
            CATransaction.setDisableActions(true)
        }
        for layer in shineLayers { layer.opacity = value }
        CATransaction.commit()
    }

    /// Instant, both ways: the growth *is* the message, and the shrink is only
    /// ever seen on a window already ordered out.
    private func setScale(_ value: CGFloat) {
        guard scale != value, let pin else { scale = value; return }
        scale = value
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pin.transform = CATransform3DMakeScale(value, value, 1)
        CATransaction.commit()
    }

    private func makePanel() -> RelayPanel {
        let side = CaretHalo.side
        // `RelayPanel`, not `NSPanel`: `constrainFrameRect` would drag a
        // borderless window back under the menu bar, off the caret.
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
        // The ring's box, so one origin places both.
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        let built = build()
        pin = built.pin
        shineLayers = built.shine
        body = built.body
        cross = built.cross
        glint = built.glint
        ring = built.ring
        arcs = built.arcs
        scale = 1
        shine = 0
        for layer in shineLayers { layer.opacity = 0 }
        view.layer?.addSublayer(built.pin)
        applyCrossed()
        p.contentView = view
        view.isHidden = veiled
        panel = p
        return p
    }

    private func applyCrossed() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body?.fillColor = (crossed ? Self.deadFill : NSColor.systemRed).cgColor
        body?.strokeColor = (crossed ? Self.deadRim : Self.rim).cgColor
        cross?.isHidden = !crossed
        // In flight, the ring follows the cross both ways; its clock never stopped.
        if holding { ring?.isHidden = crossed }
        CATransaction.commit()
        if crossed { setShine(0, animated: false) }
    }

    // MARK: - Drawing

    /// The pin's darker rim, so it holds on a red page.
    private static let rim = NSColor(srgbRed: 0.55, green: 0.05, blue: 0.05, alpha: 1)
    private static let deadFill = NSColor(white: 0.62, alpha: 1)
    private static let deadRim = NSColor(white: 0.32, alpha: 1)

    /// The drawing on its own, for `CaretHalo.shootArrow` — the only way to look
    /// at a shape that lives on a `sharingType = .none` window. **Posed, not
    /// animated** (`ChipWipe.shoot`'s rule): the glint halfway across and the
    /// glow at full, the one frame that shows what the shine is doing.
    /// `scale` 0 is never asked; `holdScale` draws the words-in-flight pose.
    /// `progress` > 0 draws the ring round the hole at that fill — the
    /// words-in-flight pose.
    static func picture(scale: CGFloat = 1, shining: Bool = true, crossed: Bool = false,
                        progress: CGFloat = 0) -> CALayer {
        let built = DropArrow().build(posed: true)
        built.ring.isHidden = progress <= 0 || crossed
        for arc in built.arcs { arc.strokeEnd = progress }
        for layer in built.shine { layer.opacity = shining && !crossed ? 1 : 0 }
        built.body.fillColor = (crossed ? deadFill : NSColor.systemRed).cgColor
        built.body.strokeColor = (crossed ? deadRim : rim).cgColor
        built.cross.isHidden = !crossed
        built.pin.transform = CATransform3DMakeScale(scale, scale, 1)
        let box = CALayer()
        box.frame = CGRect(x: 0, y: 0, width: CaretHalo.side, height: CaretHalo.side)
        box.addSublayer(built.pin)
        return box
    }

    /// The pin in a layer whose anchor is its tip, placed with the tip
    /// `tipLift` above the box's centre (which is the caret).
    private func build(posed: Bool = false) -> (pin: CALayer, shine: [CALayer], body: CAShapeLayer, cross: CALayer,
                                                glint: CAGradientLayer, ring: CALayer, arcs: [CAShapeLayer]) {
        let side = CaretHalo.side
        let height = Self.pinHeight
        let width = height * 0.696
        let shape = Glyphs.mapPinShape(height: height)!
        let outline = CGMutablePath()
        outline.addPath(shape.body)
        outline.addEllipse(in: shape.hole)

        let group = CALayer()
        group.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        group.anchorPoint = CGPoint(x: 0.5, y: 0)
        group.position = CGPoint(x: side / 2, y: side / 2 + Self.tipLift)

        // The glow: the pin's own silhouette in amber, blurred out by its
        // shadow, under the pin — so only the halo round it shows.
        let glow = CAShapeLayer()
        glow.frame = group.bounds
        glow.path = outline
        glow.fillRule = .evenOdd
        glow.fillColor = Self.ink.cgColor
        glow.shadowColor = Self.ink.cgColor
        glow.shadowOpacity = 1
        glow.shadowRadius = 10
        glow.shadowOffset = .zero
        let breath = CALayer()
        breath.frame = group.bounds
        breath.addSublayer(glow)
        // **Outside only** (2026-10-20, Victor: *"the outside glow should be there,
        // but the inside glow should be the one that expresses the progress … I
        // can't tell if it's progress bar or the glow"*): the hole is cut out of
        // the breath, so all that lights it is the progress (`ring`).
        let outsideOnly = CAShapeLayer()
        outsideOnly.frame = group.bounds
        let keep = CGMutablePath()
        keep.addRect(group.bounds.insetBy(dx: -60, dy: -60))
        keep.addEllipse(in: shape.hole)
        outsideOnly.path = keep
        outsideOnly.fillRule = .evenOdd
        breath.mask = outsideOnly
        if !posed {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.35
            a.toValue = 1.0
            a.duration = Self.glowBreath / 2
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.isRemovedOnCompletion = false
            glow.add(a, forKey: "breath")
        }
        group.addSublayer(breath)

        // The pin: the chip's red, a darker rim so it holds on a red page, and
        // a short black shadow so it holds on a white one.
        let body = CAShapeLayer()
        body.frame = group.bounds
        body.path = outline
        body.fillRule = .evenOdd
        body.fillColor = NSColor.systemRed.cgColor
        body.strokeColor = Self.rim.cgColor
        body.lineWidth = 1.2
        body.shadowColor = NSColor.black.cgColor
        body.shadowOpacity = 0.5
        body.shadowRadius = 3
        body.shadowOffset = CGSize(width: 0, height: -1)
        group.addSublayer(body)

        // The glint: a white band crossing the pin bottom-left → top-right,
        // clipped to the pin.
        let glint = CAGradientLayer()
        glint.frame = group.bounds
        glint.colors = [NSColor(white: 1, alpha: 0).cgColor,
                        NSColor(white: 1, alpha: 0.9).cgColor,
                        NSColor(white: 1, alpha: 0).cgColor]
        glint.startPoint = CGPoint(x: 0, y: 0)
        glint.endPoint = CGPoint(x: 1, y: 1)
        let mask = CAShapeLayer()
        mask.frame = group.bounds
        mask.path = outline
        mask.fillRule = .evenOdd
        glint.mask = mask
        if posed {
            glint.locations = [0.35, 0.5, 0.65]
        } else {
            glint.locations = Self.glintBefore
            Self.sweep(glint, rest: Self.glintRest)
        }
        group.addSublayer(glint)

        // **A glow on the inside of the hole's rim, sweeping round it** (2026-10-20,
        // Victor: *"an interior wide border … of the pinhole … no space between the
        // pin margin and that progress bar … a glow interior to that hole, which
        // progresses the same way … Something subtle"*). An amber band flush with
        // the rim, blurred by its own shadow and clipped to the hole, so it only
        // bleeds inward; clockwise from twelve; the middle stays clear. The
        // falloff is bands flush with the rim, each wider than the last — a
        // radial gradient a stroke can carry.
        let hole = shape.hole
        let rim = hole.width / 2
        let centre = CGPoint(x: hole.midX, y: hole.midY)
        let ring = CALayer()
        ring.frame = group.bounds
        let clip = CAShapeLayer()
        clip.frame = group.bounds
        clip.path = CGPath(ellipseIn: hole, transform: nil)
        ring.mask = clip
        var arcs: [CAShapeLayer] = []
        // Eight overlapping bands of 9 %: ~53 % at the rim, fading to 9 % a
        // third of the way in.
        for i in 1...8 {
            let w = rim * 0.08 * CGFloat(i)
            let alpha: CGFloat = 0.09
            // Start at the top, go clockwise: in a y-up layer that is decreasing angle.
            let circle = CGMutablePath()
            circle.addArc(center: centre, radius: rim - w / 2, startAngle: .pi / 2,
                          endAngle: .pi / 2 - 2 * .pi, clockwise: true)
            let arc = CAShapeLayer()
            arc.frame = group.bounds
            arc.path = circle
            arc.fillColor = nil
            arc.strokeColor = Self.ink.withAlphaComponent(alpha).cgColor
            arc.lineWidth = w
            arc.strokeEnd = 0
            ring.addSublayer(arc)
            arcs.append(arc)
        }
        ring.isHidden = true
        group.addSublayer(ring)

        // The ✕ for *nowhere*: two red strokes across the head, white-edged so
        // they read on the grey and on any page.
        let r = height * 0.30
        let c = CGPoint(x: width / 2, y: height - height * 0.348)
        let x = CGMutablePath()
        x.move(to: CGPoint(x: c.x - r, y: c.y - r))
        x.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
        x.move(to: CGPoint(x: c.x - r, y: c.y + r))
        x.addLine(to: CGPoint(x: c.x + r, y: c.y - r))
        let cross = CALayer()
        cross.frame = group.bounds
        for (colour, line) in [(NSColor.white, CGFloat(7)), (NSColor.systemRed, CGFloat(4))] {
            let stroke = CAShapeLayer()
            stroke.frame = group.bounds
            stroke.path = x
            stroke.strokeColor = colour.cgColor
            stroke.lineWidth = line
            stroke.lineCap = .round
            stroke.fillColor = nil
            cross.addSublayer(stroke)
        }
        cross.isHidden = true
        group.addSublayer(cross)

        return (group, [breath, glint], body, cross, glint, ring, arcs)
    }

    private static let glintBefore: [NSNumber] = [-0.3, -0.15, 0]
    private static let glintAfter: [NSNumber] = [1, 1.15, 1.3]

    /// The glint's cycle: one sweep, then `rest` of nothing — **no rest while
    /// the words are in flight** (2026-10-20, *"the [shine] should be something
    /// continuous"*). Replacing the animation restarts it from the left edge.
    private static func sweep(_ glint: CAGradientLayer, rest: CFTimeInterval) {
        // **Bare literals, never `.map(NSNumber.init)`** — that resolves to
        // an `NSValue` initialiser and crashes the `CATransaction` flush
        // (the heads' 2026-09-12 `SIGTRAP`).
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = glintBefore
        sweep.toValue = glintAfter
        sweep.duration = glintSweep
        sweep.timingFunction = CAMediaTimingFunction(name: rest > 0 ? .easeInEaseOut : .linear)
        let cycle = CAAnimationGroup()
        cycle.animations = [sweep]
        cycle.duration = glintSweep + rest
        cycle.repeatCount = .infinity
        cycle.isRemovedOnCompletion = false
        glint.add(cycle, forKey: "glint")
    }
}
