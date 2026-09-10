import AppKit
import QuartzCore

/// **A golden halo round the pointer whenever a dictation is headed for the
/// caret — faint while he talks, and swelling once he stops.**
///
/// Victor's ask, 2026-09-09: *"when this mode is activated … draw a little halo
/// ring around the mouse … about 100 pixels, to warn me that I need to basically
/// pick somewhere to paste it"*.
///
/// ## What it is warning about
///
/// Every other destination this app has is a thing he **pointed at** and a thing
/// the chip **names**: a terminal's icon and `petclinic@main`, a picked folder,
/// `✨` for a session that does not exist yet. A caret dictation names its
/// destination too — `at caret` — and that is exactly the problem: it is the one
/// destination that is not a place, it is *wherever the focus happens to be when
/// the words arrive*. A sentence spoken with the focus in the wrong window is
/// pasted into the wrong window, discovered afterwards, with nothing having said
/// so at the time.
///
/// **Whether or not a terminal is bound**, and it shipped the other way for an
/// hour. The gate was `pasteMode && !isBound`, on the reading that a binding is
/// a second answer to *where do these words go*. It is not — in this mode they
/// go to the caret either way, so the failure is exactly as available bound as
/// unbound. Victor: *"nu ne-legat e cheia, ci dacă transcriu at caret (legat sau
/// nu)"*. If anything bound is the worse case: the chip carries a terminal's
/// name and icon all day, so `at caret` is the row that has to be *noticed*
/// changing.
///
/// The chip cannot carry this. It rides beside the pointer, and macOS hides the
/// pointer the moment he touches the keyboard — which is precisely the gesture
/// this is about. So the warning is drawn round the pointer instead of beside
/// it: a ring is visible at the edge of vision without being read, and what it
/// is drawn round is the thing he has to move.
///
/// ## The swell is the whole message, and silence is what triggers it
///
/// *"this halo should increase in opacity the moment there is no voice coming
/// any more … by default it's 10% … but grows up to 50% after two seconds of low
/// voice … over another two seconds"*.
///
/// While he is talking the paste is not imminent and the ring has nothing to
/// ask, so it sits at `rest` — present, ignorable, and there to be recognised
/// later rather than read now. **Stopping is the signal**: the sentence he has
/// just finished is about to be pasted, and it is the last moment placing the
/// caret is still free. So the ring is quiet exactly while he is busy and
/// insistent exactly when he is not, which is the opposite of what a fixed
/// warning does.
///
/// **Two seconds before it starts, not immediately**, because the gaps *inside*
/// a sentence are ordinary: he pauses to think mid-dictation all the time, and a
/// ring that brightened on every breath would be a light flashing at the corner
/// of his eye for the length of every sentence — the same failure that keeps the
/// `HQ` tag's pop edge-triggered. Two seconds of nothing is a stop.
///
/// ## What it does not do
///
/// It does not move the caret, name a window, or refuse anything. It is drawn on
/// `ignoresMouseEvents`, so a click through it lands where it would have landed,
/// and there is nothing to press: the correction is to click where the words
/// should go, which is a gesture he already makes.
///
/// **Never in a screenshot** (`sharingType = .none`) — the shutter is live in
/// Replace Wispr, so this would otherwise be a blue ring burned into the very
/// frames it is standing over. Same rule the beacon, the capture flash and the
/// menu-bar mirror follow, and the same consequence: it cannot be reviewed with
/// a screenshot, only through `CGWindowListCopyWindowInfo` and his own eyes.
final class CaretHalo {

    /// **The core of the halo sits at 150pt out**, three times the radius the
    /// ring shipped at a few hours earlier.
    ///
    /// 100pt across was picked as the smallest circle that still reads as one
    /// round a 20pt cursor, which answered the wrong question: this is not a
    /// mark *on* the pointer, it is the only thing on screen saying where a
    /// whole sentence is about to land. At that size and 10% it was polite to
    /// the point of being missable — exactly the failure it exists to prevent.
    /// This is a presence in the periphery rather than an ornament to be looked
    /// at, which is the one place it has to work: he is reading something else
    /// while he talks.
    private static let core: CGFloat = 150
    /// How far the glow reaches either side of the core, as a multiple of it.
    /// Twice what the halo shipped at (Victor, 2026-09-09: *"2× mai lat … mai
    /// gros adică"*), and now the **same** number on both sides — see `profile`.
    private static let spread: CGFloat = 0.66
    /// The panel has to hold the whole falloff: a gradient clipped by its own
    /// window ends in a hard circular edge, which is the one thing this shape
    /// must not have.
    private static var side: CGFloat { (core * (1 + spread)).rounded() * 2 + 4 }

    /// **The halo's cross-section**, as `(distance from the pointer ÷ core,
    /// alpha)`. One colour, and symmetric about the core.
    ///
    /// It was neither for an hour. It was read off the reference picture Victor
    /// sent — a near-white inner rim, a gold body, an amber tail, and a long
    /// outer falloff against a short inner one — and he took all of that back
    /// the same evening: *"să nu fie multi-color. doar galben, gradient similar
    /// de opacitate și înăuntru și afară"*.
    ///
    /// **The picture was of a picture, and this is a signal.** In that image the
    /// hues are what make it read as *light* — a photograph of a glow, looked at
    /// on its own. This is drawn over Victor's actual work at a fraction of an
    /// opacity, and there a second and third hue do not survive being that faint:
    /// they read as a smudge with a colour cast, and on a dark editor the white
    /// rim came out grey. One colour at one falloff is the same shape with
    /// nothing left in it that the opacity can spoil.
    ///
    /// **Symmetric for the same reason.** The asymmetry was borrowed from how a
    /// glow behaves round a bright hole, and there is no bright hole here — what
    /// is in the middle is the pointer. A band that is heavier on one side reads
    /// as a ring lit from somewhere, which is a fact about a light source that
    /// does not exist.
    ///
    /// Every stop is still zero at one end, so there is no radius at which the
    /// alpha steps.
    /// **A plateau since 2026-09-10, not a peak** — Victor drew it. He marked a
    /// render of the chosen texture with two circles and said it should be fully
    /// opaque *only* between them, with the fade to either side much more
    /// pronounced: *"să fie full opac doar între cercul verde și cercul roșu …
    /// poza tre să aibă transparență parțială pe periferie/interior"*. Measured
    /// off his markup: green at **r 103**, red at **r 193**, which in multiples
    /// of the core radius is 0.687 and 1.287.
    ///
    /// **What that changes is what the shape *is*.** A single peak at the core
    /// is a glow — one bright radius with everything else on the way to it. A
    /// plateau is a *band* with soft edges: a wide region that is simply the
    /// halo, and two ramps that stop it having an edge. That is the honest
    /// envelope for a texture made of many small marks, because with a peak the
    /// marks nearest the core are lit and the rest are on a gradient toward not
    /// existing — the field reads as a ring with a bright middle rather than as
    /// a field.
    ///
    /// The two ramps are 0.347 and 0.373 core-units wide, i.e. not quite equal.
    /// They come from circles he drew by hand and are left as measured: the
    /// asymmetry is a third of a percent of the radius and no eye will find it,
    /// where rounding them to a matched pair would be preferring tidiness to
    /// what he actually asked for.
    /// The two radii he drew, as multiples of the core. **Named because two
    /// things read them**: the envelope below, and the texture's own code, which
    /// distributes its marks evenly across the plateau and thins them out into
    /// the ramps. A number that appears in a drawing and in the alpha that
    /// multiplies it is a number that must not be able to drift.
    static let plateauInner: CGFloat = 0.687   // his green circle, r 103
    static let plateauOuter: CGFloat = 1.287   // his red circle, r 193

    private static let profile: [(CGFloat, CGFloat)] = [
        (1 - spread,     0),
        (plateauInner,   1),
        (plateauOuter,   1),
        (1 + spread,     0),
    ]

    /// **One yellow, and nothing else.** `NSColor.systemYellow` is deliberately
    /// not used: it is a dynamic colour that shifts with the appearance, and
    /// this is drawn over whatever is on screen rather than over the app's own
    /// surfaces — it has to be the same gold on a white page and on a dark
    /// terminal.
    private static let ink = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.25, alpha: 1)

    /// **5% while he is talking** — the faintest this has ever drawn itself, and
    /// arrived at from both directions in one evening.
    ///
    /// It was **10%**, on the argument that a mark present and ignorable is one
    /// he learns to recognise before he ever needs it. That number was chosen
    /// for a 100pt ring and did not survive the halo becoming 300pt across: at
    /// that size a tenth of an opacity is not a faint mark, it is a wash over
    /// everything under his hand, all sentence, every sentence. So Victor set it
    /// to **zero** — and then, minutes later, to five.
    ///
    /// Zero was the overcorrection. It is the halo *arriving* that says the
    /// paste is imminent, and something has to be there for the arrival to be a
    /// change in — with nothing at rest, the swell is a shape materialising out
    /// of empty desktop, which is a bigger event than the thing it reports. At
    /// 5% it is at the edge of visible: enough to have been there, not enough to
    /// be in the way.
    /// **×1.5 on 2026-09-10** (Victor: *"overall, să fie haloul 1.5× mai
    /// opac"*), which is the second correction in the same direction: 10 → 0 →
    /// 5 → 7.5. The spoked designs are part of why it can afford it — a pattern
    /// of thin lines covers a fraction of the pixels a solid band does, so the
    /// same nominal alpha is a far lighter wash over the work underneath.
    private static let rest: CGFloat = 0.075
    private static let alert: CGFloat = 0.225
    /// How long a silence has to last before the ring reads it as a stop rather
    /// than as him thinking mid-sentence.
    private static let patience: TimeInterval = 2
    /// And how long it then takes to get there.
    private static let swell: TimeInterval = 2

    /// 20 Hz, the beacon's rate and for the beacon's reason: the value is a
    /// continuous function of how long he has been quiet, so it is *sampled*
    /// rather than animated — an animation would be interpolating toward a
    /// target that has already moved.
    private static let tick: TimeInterval = 1.0 / 20

    private var panel: RelayPanel?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var live = false

    /// **How long since he last said anything**, asked of whoever is holding the
    /// microphone. A closure for the reason `RecordingBeacon.level` is one: what
    /// is listening is the delegate's business, not this class's.
    var quietSeconds: (() -> TimeInterval)?

    /// On or off. Idempotent, and driven from `syncBorrowedGestures` — the one
    /// switch every edge of a dictation already passes through, so this cannot
    /// drift out of step with the chip, the beacon or the borrowed buttons.
    func setActive(_ on: Bool) {
        guard live != on else { return }
        live = on
        // Both edges, for the reason the selection watcher logs both: "why did
        // the ring not come up" has to be answerable from the file, and the
        // three conditions behind it are not all visible on screen.
        Log.info(on ? "◯ caret halo on — these words go wherever the caret is"
                    : "◯ caret halo off")
        on ? show() : hide()
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        panel.alphaValue = Self.rest
        follow()
        panel.orderFrontRegardless()

        // Global catches every other app the pointer moves over; local catches
        // this app's own panels, which never see a global monitor's events —
        // the chip is riding the same cursor and is not click-through, so
        // without the local half the ring would stop dead whenever the pointer
        // crossed it.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                             .rightMouseDragged, .otherMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.follow()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in
            self?.follow(); return e
        }) { monitors.append(m) }

        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.refresh() }
        timer = t
        // `.common`, because the chords that reach this app are held mouse
        // buttons and a tracking loop would otherwise stall the swell.
        RunLoop.main.add(t, forMode: .common)
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        panel?.orderOut(nil)
    }

    /// Centred on the pointer, every time the pointer reports. Off the events
    /// rather than off a timer for `RelayWindow.startFollowingMouse`'s measured
    /// reason: a 60 Hz poll trails a fast pointer by a whole tick plus a
    /// window-move round trip, and a ring that lags is a ring that is visibly
    /// not *round* anything.
    private func follow() {
        guard live, let panel = panel else { return }
        let p = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: (p.x - Self.side / 2).rounded(),
                                     y: (p.y - Self.side / 2).rounded()))
    }

    private func refresh() {
        guard live, let panel = panel else { return }
        let quiet = quietSeconds?() ?? 0
        let t = max(0, min(1, (quiet - Self.patience) / Self.swell))
        panel.alphaValue = Self.rest + (Self.alert - Self.rest) * CGFloat(t)
    }

    // MARK: - Designs

    /// **What the halo is made of.** Victor, 2026-09-10: *"cercul halou … să fie
    /// alcătuit din «spițe»: linii de 3-5 px grosime concentrice, mai
    /// transparente spre interior și exterior, exact ca haloul ca feeling, dar
    /// stilizat cu liniuțe."*
    ///
    /// Every one of them is the **same falloff** — `profile`, unchanged — with
    /// a different pattern of strokes underneath it. That is what makes them
    /// comparable at all: they differ in texture and in nothing else, so a
    /// choice between them is a choice about texture rather than about which
    /// one happens to be brighter.
    enum Design: String, CaseIterable {
        /// The band as it shipped: a smooth radial gradient, no strokes. Kept as
        /// the reference row on the contact sheet — a set of proposals with
        /// nothing to be different *from* is a set nobody can judge.
        case smooth
        /// **Three thick feathered bands.** The literal reading of the brief that
        /// can also survive being looked *past*: 5pt strokes with soft edges,
        /// spaced about a stroke apart, so the low frequencies the periphery
        /// actually sees are still there.
        case bands
        /// Seven thin rings across the band — the same idea at the other end of
        /// the thickness/count trade.
        case rings
        /// Rings whose **width** carries the falloff as well as their alpha:
        /// fat at the core, hairline at the edges. The only design where the
        /// profile is drawn rather than multiplied in.
        case waves
        /// Radial spokes crossing the whole band, the literal reading of
        /// *spițe* — the one texture orthogonal to every ring above.
        case spokes
        /// Dots rather than dashes, on three radii. A dot has no direction and
        /// no handedness, which is what keeps it from reading as a spinner or a
        /// compass — the failure that killed half of round one.
        case stipple
        /// **The lines cut out of the band rather than drawn on it.** The smooth
        /// halo with a dozen radial slots taken out of it: the mass — and so the
        /// peripheral visibility — is the reference's, and the stylisation is in
        /// the gaps.
        case slots
        /// **The band itself, with the lines taken *out* of its brightness.**
        ///
        /// Three rounds of drawing strokes onto nothing established the ceiling:
        /// the smooth band covers 20.4% of its disc at peak brightness, and
        /// strokes over the same annulus top out at 9–15% before they stop
        /// looking like strokes — so a texture built *up* from lines is short of
        /// light by 2.6× with no headroom left, because its strokes are already
        /// at the reference's peak. The brief as stated is unsatisfiable.
        ///
        /// This is it inverted: start at the reference's own mass and modulate
        /// the alpha ±25% with a radial sinusoid. Flux stays ~1.00× because it is
        /// the halo minus a little, rather than nothing plus a lot; the resting
        /// state survives because it *is* the resting state; and it reads as
        /// concentric banding — stylised with lines — without becoming a
        /// bullseye, because the gaps never go dark. `slots` proved the
        /// mass-preserving half works and failed only because its cuts were 100%
        /// deep and reached the core.
        case ripple
        /// **Four from Codex (GPT-5.5), on Victor's ask** — given the same brief,
        /// the same geometry, and the list of everything already tried and
        /// measured, so they had to be new rather than merely different.
        case codex1, codex2, codex3, codex4
    }

    /// Which one is live. `WT_HALO_DESIGN=spokes` runs the app with a candidate
    /// so it can be lived with over a real dictation before it is chosen — a
    /// contact sheet answers *what does it look like*, and this answers the
    /// question that actually decides it, which is whether it is still bearable
    /// an inch from the work after the twentieth sentence.
    /// **`codex3` ships, since 2026-09-10.** Victor picked it out of the gallery
    /// of twelve — short radial reeds that stop short of the centre — and it is
    /// the one texture in the set that no round of this arrived at on its own:
    /// every design drawn here was either concentric or a full-band sunburst,
    /// and this is neither. `smooth`, the gradient band that shipped for a day,
    /// stays as the reference the contact sheet is judged against.
    static let design: Design = {
        guard let name = ProcessInfo.processInfo.environment["WT_HALO_DESIGN"],
              let picked = Design(rawValue: name) else { return .codex3 }
        return picked
    }()

    /// **The falloff, sampled.** `profile` is a handful of stops in multiples of
    /// the core radius; this is the same curve as a function, so a pattern of
    /// strokes can be faded by exactly what the gradient fades by.
    static func alpha(atRadius r: CGFloat) -> CGFloat {
        let t = r / core
        guard t > profile.first!.0, t < profile.last!.0 else { return 0 }
        for i in 1..<profile.count where t <= profile[i].0 {
            let (t0, a0) = profile[i - 1], (t1, a1) = profile[i]
            let f = (t - t0) / max(t1 - t0, 0.0001)
            return a0 + (a1 - a0) * f
        }
        return 0
    }

    /// **A radial gradient, not a stroked path**, because the whole shape is a
    /// falloff: a `CAShapeLayer`'s stroke has one alpha across its width and
    /// would give the hard hoop the picture is emphatically not.
    ///
    /// For `.radial` the start point is the centre and the end point sets the
    /// extent, so with (0.5, 0.5) → (1, 1) a stop at `t` sits at radius
    /// `t × side / 2`. That is the whole of the arithmetic: `profile` is in
    /// multiples of the core radius, and this turns it into fractions of the
    /// panel's half-width.
    ///
    /// Built here rather than inline in `makePanel` so `shoot` draws the same
    /// layer the panel does — a contact sheet of a *different* gradient would be
    /// worse than none.
    static func haloLayer(side: CGFloat, design: Design = design) -> CALayer {
        guard design != .smooth else {
            let ring = CAGradientLayer()
            ring.type = .radial
            ring.frame = CGRect(x: 0, y: 0, width: side, height: side)
            ring.startPoint = CGPoint(x: 0.5, y: 0.5)
            ring.endPoint = CGPoint(x: 1, y: 1)
            let half = side / 2
            ring.colors = profile.map { ink.withAlphaComponent($0.1).cgColor }
            ring.locations = profile.map { NSNumber(value: Double(min(1, $0.0 * core / half))) }
            return ring
        }
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        // **Cached per design.** The panel asks for one, but the contact sheet
        // asks for every design six times over, and each answer is a million
        // pixels stroked, blurred and integrated — 72 of those is a minute of
        // waiting for a picture that has a dozen different things in it.
        let key = "\(design.rawValue)-\(Int(side))"
        if let done = patternCache[key] {
            layer.contents = done
        } else {
            let made = strokes(side: side, design: design)
            patternCache[key] = made
            layer.contents = made
        }
        layer.contentsGravity = .resize
        return layer
    }

    /// **The strokes, drawn once and faded by the same curve the gradient uses.**
    ///
    /// The pattern is stroked in white into a scratch bitmap and then multiplied,
    /// pixel by pixel, by `alpha(atRadius:)`. Doing it that way rather than
    /// giving each stroke its own alpha is what keeps the promise the whole
    /// family rests on — *mai transparente spre interior și exterior* — true
    /// **along** a line as well as across the set of them: a spoke crosses every
    /// radius in the band, so a per-stroke alpha would make it a bar of one
    /// brightness, which is the hard hoop this shape has always refused.
    ///
    /// It also means the antialiasing is paid for once, in the stroking, and the
    /// result is a still image: no shape layers to composite, nothing to
    /// re-rasterise while the panel chases the pointer.
    private static func strokes(side: CGFloat, design: Design) -> CGImage? {
        let scale: CGFloat = 2
        let px = Int((side * scale).rounded())
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: px * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setAllowsAntialiasing(true)

        let c = CGPoint(x: side / 2, y: side / 2)
        let inner = core * (1 - spread), outer = core * (1 + spread)
        let band = outer - inner

        func ring(_ r: CGFloat, width: CGFloat, dash: [CGFloat] = [], phase: CGFloat = 0) {
            ctx.setLineWidth(width)
            ctx.setLineDash(phase: phase, lengths: dash)
            ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.strokePath()
        }
        func spoke(_ angle: CGFloat, from r0: CGFloat, to r1: CGFloat, width: CGFloat) {
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: c.x + cos(angle) * r0, y: c.y + sin(angle) * r0))
            ctx.addLine(to: CGPoint(x: c.x + cos(angle) * r1, y: c.y + sin(angle) * r1))
            ctx.strokePath()
        }

        switch design {
        case .smooth:
            break

        case .bands:
            // Three, at the full 5pt, one stroke-width apart. Round one drew
            // everything hairline-thin and the whole set lost 86-94% of its
            // contrast to a mild peripheral blur where the smooth reference lost
            // 14% — a line has to be *thick* to survive being seen out of the
            // corner of an eye, which is the one place this mark is ever seen.
            for i in 0..<3 {
                ring(inner + band * (CGFloat(i) + 0.5) / 3, width: 5)
            }

        case .rings:
            let n = 7
            for i in 0..<n { ring(inner + band * (CGFloat(i) + 0.5) / CGFloat(n), width: 4) }

        case .waves:
            // **The falloff drawn twice**: in the alpha, like every other design
            // here, and in the stroke *width* — 10pt at the core down to 3pt at
            // the rim. Measured, this is the one line design whose blurred radial
            // signature is the smooth halo's exactly (correlation 1.00), which is
            // to say it is the only one that is still the same object.
            //
            // **The width is where the missing light comes from, and that is the
            // whole point.** At 5pt it carried a quarter of the reference's flux
            // and the arithmetic fix — four times the alpha — would have put the
            // pair at 30%/90%, a wash over his work and the exact objection that
            // took the halo off 10% in the first place. Mass out of geometry
            // leaves 7.5%/22.5% untouched and keeps the signature that makes this
            // one worth having.
            let n = 4
            for i in 0..<n {
                let t = (CGFloat(i) + 0.5) / CGFloat(n)
                let r = inner + band * t
                let closeness = 1 - abs(t - 0.5) * 2
                ring(r, width: 3 + 7 * closeness)
            }

        case .spokes:
            // 30 of them, at 5pt. The falloff does the rest: a spoke is
            // brightest where it passes the core and gone at both ends, so the
            // set reads as a ring made of radial strokes rather than as a star.
            for i in 0..<30 { spoke(CGFloat(i) * .pi / 15, from: inner, to: outer, width: 5) }

        case .stipple:
            // Three radii, dots sized by how close the radius is to the core, so
            // the texture beads rather than breaking. Isotropic by construction.
            for i in 0..<3 {
                let t = (CGFloat(i) + 0.5) / 3
                let r = inner + band * t
                let d = 4 + 3 * (1 - abs(t - 0.5) * 2)
                let n = max(12, Int((2 * .pi * r) / (d * 2.6)))
                for k in 0..<n {
                    let a = CGFloat(k) * 2 * .pi / CGFloat(n)
                    ctx.setLineDash(phase: 0, lengths: [])
                    ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * r - d / 2,
                                               y: c.y + sin(a) * r - d / 2,
                                               width: d, height: d))
                }
            }

        case .ripple:
            // No strokes at all: the annulus solid, and the lines are put in by
            // the modulation in the alpha pass below.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            ctx.setBlendMode(.normal)

        case .slots:
            // The band, solid, with twelve radial slots cut out of it. Everything
            // else here throws away 30-90% of the reference's light to make room
            // for the stylisation; this one keeps it and puts the little lines in
            // the gaps instead.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            for i in 0..<12 {
                let a = CGFloat(i) * .pi / 6
                ctx.setLineWidth(9)
                ctx.setLineDash(phase: 0, lengths: [])
                ctx.move(to: CGPoint(x: c.x + cos(a) * (inner - 2), y: c.y + sin(a) * (inner - 2)))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * (outer + 2), y: c.y + sin(a) * (outer + 2)))
                ctx.strokePath()
            }
            ctx.setBlendMode(.normal)

        case .codex1:
            // Tangential reed-field: dense short concentric linelets at many radii, staggered so blur preserves a soft annular mass.
            // No line crosses the band radially, keeping the centre empty and avoiding sunburst motion.
            ctx.saveGState()
            ctx.setLineCap(.round)
            for i in 0..<18 {
                let t = CGFloat(i) / 17
                let r = inner + band * t
                let crown = 1 - abs(r - core) / (band * 0.5)
                let count = 26 + Int(18 * max(0, crown))
                let width: CGFloat = i % 3 == 0 ? 5 : 4
                let phase = CGFloat(i * 37).truncatingRemainder(dividingBy: 360) * .pi / 180
                for j in 0..<count {
                    if (j + i * 2) % 7 == 0 { continue }
                    let a = phase + CGFloat(j) * 2 * .pi / CGFloat(count)
                    let len = 14 + 22 * crown + CGFloat((j * 11 + i * 5) % 9)
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: a)
                    ctx.setLineWidth(width)
                    ctx.move(to: CGPoint(x: r, y: -len * 0.5))
                    ctx.addLine(to: CGPoint(x: r, y: len * 0.5))
                    ctx.strokePath()
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()

        case .codex2:
            // Nested broken contour bands: chunky arc fragments overlap like contour marks, giving high fill without forming a progress ring.
            // Each radius uses uneven fragment lengths and missing beats, so the texture has no clock axes or handedness.
            ctx.saveGState()
            ctx.setLineCap(.round)
            for i in 0..<15 {
                let t = CGFloat(i) / 14
                let r = inner + band * t
                let crown = max(0, 1 - abs(r - core) / (band * 0.5))
                let count = 18 + Int(12 * crown)
                let width: CGFloat = i % 2 == 0 ? 5 : 4
                let phase = CGFloat((i * i * 19) % 360) * .pi / 180
                for j in 0..<count {
                    if (j * 3 + i) % 10 == 0 { continue }
                    let base = phase + CGFloat(j) * 2 * .pi / CGFloat(count)
                    let sweep = (0.075 + 0.06 * crown) * (0.75 + CGFloat((j + i) % 5) * 0.11)
                    let drift = CGFloat(((j * 13 + i * 7) % 9) - 4) * 0.006
                    ctx.setLineWidth(width)
                    ctx.addArc(center: c, radius: r, startAngle: base + drift, endAngle: base + sweep + drift, clockwise: false)
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()

        case .codex3:
            // Rebalanced for the 103...193 plateau: uniform reed density through the opaque band, with sparser/shorter reeds in both fade ramps.
            // Staggered short radial dashes keep the centre empty and avoid a continuous ring or sunburst read.
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.setLineCap(.round)

            let plateauIn = core * plateauInner
            let plateauOut = core * plateauOuter
            let fadeIn: CGFloat = inner
            let fadeOut: CGFloat = outer

            func reed(_ a: CGFloat, _ r0: CGFloat, _ r1: CGFloat, _ w: CGFloat) {
                guard r0 >= inner + 1, r1 <= outer - 1, r1 > r0 else { return }
                spoke(a, from: r0, to: r1, width: w)
            }

            // **The lane is area-weighted, and without that the plateau is not
            // flat.** Reeds spread evenly *in radius* thin out as they go, since
            // an annulus at r has circumference 2πr to fill — measured on the
            // first render, the band peaked at r≈130 and was 40% down by the
            // red circle, which is a gradient inside the region that is supposed
            // to be uniformly opaque. `sqrt` of the lane puts the count in
            // proportion to r, so the *density* is constant and the envelope is
            // the only thing shaping the light.
            for i in 0..<168 {
                let a = CGFloat(i) * (.pi * 2 / 168) + CGFloat((i * 37) % 19) * 0.003
                let u = CGFloat((i * 29) % 100) / 99
                // The inverse CDF of a density proportional to r, which is
                // `sqrt(a² + u(b² − a²))` and **not** `a + sqrt(u)(b − a)` —
                // the latter was tried first and overshot, moving the peak from
                // r≈130 out to r≈180 and leaving a trough where the band starts.
                let r = sqrt(plateauIn * plateauIn + u * (plateauOut * plateauOut - plateauIn * plateauIn))
                let len = CGFloat(13 + ((i * 17) % 15))
                let w = CGFloat(3 + ((i * 11) % 3))
                reed(a, r - len * 0.48, r + len * 0.52, w)
            }

            for i in 0..<44 {
                let a = CGFloat(i) * (.pi * 2 / 44) + CGFloat((i * 41) % 23) * 0.009
                let t = CGFloat((i * 31) % 100) / 99
                let r = fadeIn + 10 + pow(t, 0.72) * (plateauIn - fadeIn - 13)
                let len = CGFloat(5 + ((i * 13) % 10))
                let w = CGFloat(3 + ((i * 7) % 2))
                reed(a, r - len * 0.38, r + len * 0.62, w)
            }

            for i in 0..<50 {
                let a = CGFloat(i) * (.pi * 2 / 50) + CGFloat((i * 43) % 29) * 0.008
                let t = CGFloat((i * 23) % 100) / 99
                let r = plateauOut + 7 + pow(t, 1.35) * (fadeOut - plateauOut - 15)
                let len = CGFloat(6 + ((i * 19) % 11))
                let w = CGFloat(3 + ((i * 5) % 2))
                reed(a, r - len * 0.50, r + len * 0.50, w)
            }

        case .codex4:
            // Brick-weave halo: small rounded chord strokes occupy alternating radial lanes, like annular masonry rather than rings.
            // The lanes overlap enough for blur to hold the halo shape, while the broken offsets keep it non-directional.
            ctx.saveGState()
            ctx.setLineCap(.round)
            for lane in 0..<9 {
                let laneT = CGFloat(lane) / 8
                let laneCenter = inner + band * laneT
                let crown = max(0, 1 - abs(laneCenter - core) / (band * 0.5))
                let rows = lane % 2 == 0 ? 3 : 2
                let count = 20 + Int(16 * crown)
                for row in 0..<rows {
                    let r = laneCenter + CGFloat(row - rows / 2) * 6
                    if r <= inner + 4 || r >= outer - 4 { continue }
                    let width: CGFloat = row == 1 ? 5 : 4
                    let phase = (CGFloat(lane * 41 + row * 73) * .pi / 180) + (lane % 2 == 0 ? 0 : .pi / CGFloat(count))
                    for j in 0..<count {
                        if (j * 5 + lane + row) % 11 == 0 { continue }
                        let a = phase + CGFloat(j) * 2 * .pi / CGFloat(count)
                        let len = 18 + 19 * crown + CGFloat((j * 7 + lane * 3 + row) % 6)
                        ctx.saveGState()
                        ctx.translateBy(x: c.x, y: c.y)
                        ctx.rotate(by: a)
                        ctx.setLineWidth(width)
                        ctx.move(to: CGPoint(x: r, y: -len * 0.5))
                        ctx.addLine(to: CGPoint(x: r, y: len * 0.5))
                        ctx.strokePath()
                        ctx.restoreGState()
                    }
                }
            }
            ctx.restoreGState()
        }

        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: px * px * 4)

        // **Feathered, because a crisp hairline is invisible in the periphery.**
        // Measured on round one: through a mild peripheral blur the six line
        // designs lost 86–94% of their contrast against the ground, where the
        // smooth band lost 14%. A soft-edged stroke keeps the low frequencies
        // that survive being *looked past*, which is the only way this mark is
        // ever seen — he is reading something else while he talks.
        var alphaMap = [CGFloat](repeating: 0, count: px * px)
        for i in 0..<(px * px) { alphaMap[i] = CGFloat(buf[i * 4 + 3]) / 255 }
        blur(&alphaMap, side: px, radius: Int((1.2 * scale).rounded()))

        // **And normalised to the same light as the band it replaces.** A pattern
        // of strokes covers a tenth of the pixels a solid annulus does, so at the
        // same nominal alpha it is a tenth of the mark — measured at 0.08× to
        // 0.71× of the shipping halo's flux *at full opacity*. Scaling each
        // design so the total light matches is what makes "1.5× more opaque"
        // mean the same thing whichever one is chosen; the cap keeps a very
        // sparse pattern from being pushed to opaque hairlines, which trades one
        // kind of invisibility for one kind of harshness.
        let mid = CGFloat(px) / 2
        var patternFlux: CGFloat = 0, referenceFlux: CGFloat = 0
        for y in 0..<px {
            for x in 0..<px {
                let dx = CGFloat(x) - mid, dy = CGFloat(y) - mid
                let fade = alpha(atRadius: sqrt(dx * dx + dy * dy) / scale)
                patternFlux += alphaMap[y * px + x] * fade
                referenceFlux += fade
            }
        }
        let gain = min(fluxCeiling, referenceFlux / max(patternFlux, 1))
        let r = ink.redComponent, g = ink.greenComponent, b = ink.blueComponent
        for y in 0..<px {
            for x in 0..<px {
                let coverage = alphaMap[y * px + x]
                let i = (y * px + x) * 4
                guard coverage > 0 else { buf[i] = 0; buf[i+1] = 0; buf[i+2] = 0; buf[i+3] = 0; continue }
                let dx = CGFloat(x) - mid, dy = CGFloat(y) - mid
                let radius = sqrt(dx * dx + dy * dy) / scale
                var a = min(1, coverage * gain * alpha(atRadius: radius))
                if design == .ripple { a *= ripple(atRadius: radius) }
                buf[i]     = UInt8(max(0, min(255, r * a * 255)))
                buf[i + 1] = UInt8(max(0, min(255, g * a * 255)))
                buf[i + 2] = UInt8(max(0, min(255, b * a * 255)))
                buf[i + 3] = UInt8(max(0, min(255, a * 255)))
            }
        }
        return ctx.makeImage()
    }

    /// **The lines, as a dip in brightness rather than a stroke.** Five cycles
    /// across the band at ±25%: deep enough to be seen as banding up close,
    /// shallow enough that no radius is ever dark, which is what keeps the shape
    /// a glow rather than a target. Its own falloff to flat at the rim, so the
    /// modulation cannot put a hard edge where the halo's whole point is that it
    /// has none.
    private static func ripple(atRadius r: CGFloat) -> CGFloat {
        let t = (r - core * (1 - spread)) / (core * spread * 2)
        guard t > 0, t < 1 else { return 1 }
        let envelope = sin(t * .pi)          // zero at both rims, one in the middle
        return 1 + 0.25 * envelope * cos(t * 5 * 2 * .pi)
    }

    private static var patternCache: [String: CGImage?] = [:]

    /// How much a sparse pattern may be brightened to match the band's light.
    /// Past this it stops being a faint texture and becomes thin hard lines,
    /// which is a different mark rather than a dimmer one.
    /// **8×, because 3× was binding on every design and fixing none of them.**
    /// A pattern filling a fifteenth of the annulus needs more gain than that to
    /// carry the same light, so the cap was not a safety rail — it was the thing
    /// defeating the normalisation. It still exists for the case it was written
    /// for: a pattern sparse enough that matching the flux would mean opaque
    /// hairlines, which is a different mark rather than a dimmer one.
    private static let fluxCeiling: CGFloat = 8.0

    /// A separable box blur, run twice — two passes of a box are near enough a
    /// Gaussian for an edge nobody is meant to resolve, and it costs a handful
    /// of milliseconds on the one image this draws per launch.
    private static func blur(_ map: inout [CGFloat], side: Int, radius: Int) {
        guard radius > 0 else { return }
        var tmp = [CGFloat](repeating: 0, count: map.count)
        for _ in 0..<2 {
            for y in 0..<side {
                var sum: CGFloat = 0
                for x in -radius...radius { sum += map[y * side + min(max(x, 0), side - 1)] }
                for x in 0..<side {
                    tmp[y * side + x] = sum / CGFloat(radius * 2 + 1)
                    sum -= map[y * side + min(max(x - radius, 0), side - 1)]
                    sum += map[y * side + min(max(x + radius + 1, 0), side - 1)]
                }
            }
            for x in 0..<side {
                var sum: CGFloat = 0
                for y in -radius...radius { sum += tmp[min(max(y, 0), side - 1) * side + x] }
                for y in 0..<side {
                    map[y * side + x] = sum / CGFloat(radius * 2 + 1)
                    sum -= tmp[min(max(y - radius, 0), side - 1) * side + x]
                    sum += tmp[min(max(y + radius + 1, 0), side - 1) * side + x]
                }
            }
        }
    }

    private func makePanel() -> RelayPanel {
        let side = Self.side
        // `RelayPanel`, not `NSPanel`: AppKit's `constrainFrameRect` drags a
        // borderless window back onto the display and below the menu bar, which
        // for something pinned to the pointer is precisely wrong — at the top of
        // the screen it would shove the ring off the cursor to keep it whole.
        let p = RelayPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = .none

        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.addSublayer(Self.haloLayer(side: side))
        p.contentView = view

        panel = p
        return p
    }
}

// MARK: - Looking at it

/// **Draw the halo onto a dark ground and a light one, and quit** —
/// `WT_SHOOT_HALO=/tmp/halo.png`.
///
/// The panel is `sharingType = .none` like everything else this app puts near
/// the pointer, so **no screen capture can contain it**: the only way to judge a
/// falloff was to start a caret dictation and look, which answers *is it there*
/// and not *does it look like the picture he sent*. Same problem
/// `docs/overlay-states.html`, `WT_SHOOT_MENU` and `WT_SHOOT_WIPE` were built
/// for, same answer — the real layer drawing itself.
///
/// **Two grounds, because this shape spends its life over both** and a halo that
/// reads on one can vanish on the other; that is precisely the fault that took
/// the ring off blue. Each is drawn twice, at the resting opacity and at the
/// alarmed one, which are the two states there are.
extension CaretHalo {
    static func shoot(to path: String) {
        let side = Self.side
        let cell = NSSize(width: side, height: side)
        let grounds: [NSColor] = [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.97, alpha: 1)]
        // The two states there are, and then the profile at full strength —
        // which is the only way to judge a falloff at all once it is drawn at a
        // twentieth of an opacity.
        let alphas: [CGFloat] = [rest, alert, 1]
        // **One row per design, and the current halo is the top row.** A sheet
        // of proposals with nothing to be different *from* is one nobody can
        // judge — and the question being asked of it is precisely whether the
        // spokes still feel like the halo.
        // **One design when one is named.** The sheet is twelve million pixels
        // stroked, blurred and integrated; iterating on a single texture through
        // the whole catalogue is two minutes a look. `WT_HALO_DESIGN=codex3`
        // narrows it to the reference and that one.
        let designs = ProcessInfo.processInfo.environment["WT_HALO_DESIGN"] == nil
            ? Design.allCases : [.smooth, design]
        let columns = alphas.count * grounds.count
        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(columns),
                                         height: cell.height * CGFloat(designs.count)))
        sheet.lockFocus()
        for (row, design) in designs.enumerated() {
            for (i, ground) in grounds.enumerated() {
            for (j, alpha) in alphas.enumerated() {
                let col = i * alphas.count + j
                // Top row first: `NSImage` counts up from the bottom.
                let box = NSRect(x: cell.width * CGFloat(col),
                                 y: cell.height * CGFloat(designs.count - 1 - row),
                                 width: cell.width, height: cell.height)
                ground.setFill()
                box.fill()
                let host = NSView(frame: NSRect(origin: .zero, size: cell))
                host.wantsLayer = true
                host.layer?.addSublayer(haloLayer(side: side, design: design))
                // **The opacity is applied once, in the draw.** Setting it on
                // the host *as well* squared it — the resting column came out at
                // 1% and looked like a bug in the gradient rather than in the
                // sheet, which is the exact way a contact sheet can lie.
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                        .draw(in: box, from: .zero, operation: .sourceOver, fraction: alpha)
                }
                // The name, so a sheet of seven near-identical circles can be
                // talked about at all.
                if col == 0 {
                    (design.rawValue as NSString).draw(
                        at: NSPoint(x: box.minX + 12, y: box.minY + 12),
                        withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                                         .foregroundColor: NSColor.white])
                }
            }
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
