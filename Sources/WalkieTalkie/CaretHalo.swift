import AppKit
import QuartzCore

/// **A halo round the pointer for the whole of every dictation — breathing and
/// brightening on his own voice, and turning while it does.**
///
/// ## It was the caret's alone until 2026-09-11, and now it is the microphone's
///
/// It came up for `at caret` dictations and for nothing else, so its presence
/// *was* the message: these words land wherever the focus happens to be, go and
/// put the focus somewhere. Victor took that reading away deliberately and knew
/// what it cost — *"asta va implica și că va trebui să arăți fulgii de zăpadă,
/// haloul de fulgi de zăpadă și când dictezi cu țintă. Însă, da? Fac și eu
/// schimbarea asta"* — because the ring is the better **beacon**: it is the one
/// thing this app draws that is big, alive, and already at the pointer.
///
/// So it took `RecordingBeacon`'s job whole, and that class is gone with it:
/// *"în loc de microfonul care apare jos pe centrul ecranului, aș dori ca
/// fulgerele să pulseze în același ritm al discuției, cu același fade-out care
/// se întâmplă acum la microfon"*. `level` is the beacon's envelope verbatim,
/// spent on `loud` and on `swellScale` at once. The microphone on the bottom
/// edge answered *is it hearing me?* from a fixed spot he had to look at; this
/// answers it round the thing his hand is already on.
///
/// **What the caret dictation lost, `DropArrow` gives back** — and gives back
/// better, since an arrow pointing down at the cursor says *put it somewhere*
/// where a ring only ever said *something is different about this one*.
///
/// Since 2026-09-10 the ring itself is a **picture** — `assets/caret-halo.png`,
/// the electric blue-and-magenta ring Victor picked — resampled so its band sits
/// exactly where the drawn one's did and faded by exactly the same rules. Every
/// texture that came before it is still here, behind `WT_HALO_DESIGN`, and the
/// geometry, the envelope and the swell below are unchanged: only what fills the
/// band is different.
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
/// ## The swell used to be the message, and silence used to trigger it
///
/// *"this halo should increase in opacity the moment there is no voice coming
/// any more … by default it's 10% … but grows up to 50% after two seconds of low
/// voice … over another two seconds"* — the ring sat at `rest` all sentence and
/// climbed over two seconds of quiet, on the argument that **stopping is the
/// signal**: the sentence just finished is about to be pasted, and that is the
/// last moment placing the caret is still free.
///
/// That argument is intact and has simply moved. `DropArrow` keeps its schedule
/// whole — `patience` then `swell`, both still defined here — and says the thing
/// in a shape that can only mean one thing. What the ring does with the same
/// two seconds now is *fall quiet*, because what it is answering is no longer
/// *where do these words go* but *is the microphone still open*, and the honest
/// answer to that when nobody is talking is a dim ring rather than a bright one.
///
/// **The two seconds are still two seconds, and for the old reason**: the gaps
/// *inside* a sentence are ordinary — he pauses to think mid-dictation all the
/// time, and anything that arrived on every breath would be a light flashing at
/// the corner of his eye for the length of every sentence, the same failure that
/// keeps the `HQ` tag's pop edge-triggered.
///
/// ## The breath, and the turn it rides on
///
/// *"acestea ar trebui să pulseze, crescând dimensiunea cu … 20% față de cât e
/// default, și apoi să se contracte înapoi, în timp ce se rotește totodată"*
/// (2026-09-11). The scale is `swellScale` off `level`, the rotation is the
/// `spin` that has been here since the day before, and the two are on separate
/// layers because Core Animation gives a layer one `transform` — see `makePanel`.
///
/// **Scale and opacity from one sample**, so a syllable is one event rather than
/// two effects that coincide. And **from the voice, never from a timer**: a ring
/// breathing on a clock proves a clock is running, which is exactly the
/// substitution that took the beacon's own free-running blink out.
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
/// frames it is standing over. Same rule the capture flash and the menu-bar
/// mirror follow, and the same consequence: it cannot be reviewed with
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
    /// **105 since 2026-09-10, which is 0.7× what it was** (Victor's ask). The
    /// texture that replaced the smooth band carries its light in many small
    /// marks spread over the whole annulus, so at 150 it covered more of the
    /// screen than the band ever did while saying the same thing — the mark got
    /// bigger the moment it stopped being a single soft ring. Everything else
    /// here is expressed in multiples of this, so the plateau, the ramps and the
    /// panel all follow.
    private static let core: CGFloat = 105
    /// How far the glow reaches either side of the core, as a multiple of it.
    /// Twice what the halo shipped at (Victor, 2026-09-09: *"2× mai lat … mai
    /// gros adică"*), and now the **same** number on both sides — see `profile`.
    private static let spread: CGFloat = 0.66
    /// The panel has to hold the whole falloff: a gradient clipped by its own
    /// window ends in a hard circular edge, which is the one thing this shape
    /// must not have.
    ///
    /// **Times `1 + swellScale` since 2026-09-11**, and the contact sheet is
    /// what found it: at the top of his voice the ring is a fifth larger than
    /// the box that was measured to hold exactly its falloff, so the outer glow
    /// was being cut off square by its own window on every loud syllable —
    /// which is the one thing the sentence above says this shape must not have.
    /// The window is sized for the biggest the ring ever gets; everything drawn
    /// inside it is still placed off `core` and `half`, so nothing else moves.
    static var side: CGFloat { (core * (1 + spread) * (1 + swellScale)).rounded() * 2 + 4 }

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
    /// **Full opacity across the central fifth of the ring's thickness, and a
    /// straight line to nothing at both rims.** Victor's spec, and it is exact:
    /// *"a linear, progressive fade out from the center 20% of thickness of the
    /// ring which is full opacity (before overall fadeout at animation time)"*.
    ///
    /// The parenthesis is the important half. There are **two** fades and they
    /// compose: this one is *spatial* and fixed — where the ring is solid and
    /// where it thins — and the temporal one (`rest` → `alert`, on silence) is a
    /// single alpha over the whole panel. This envelope is what the picture *is*;
    /// that one is what it is *doing*.
    ///
    /// It replaces two earlier shapes in one step. A single peak at the core was
    /// a glow — one bright radius with everything on the way to it. Then came a
    /// wide plateau between two circles he drew (r 103 and 193 at the old size),
    /// with the ramps curved by a gamma to make them more transparent. Both are
    /// gone: the plateau is now a fifth of the thickness rather than a half, and
    /// the ramps are **linear**, which he asked for by name. The result is more
    /// transparent than the gamma ever made it, because the ramps are simply
    /// much longer — most of the ring is now fading rather than solid.
    private static let opaqueFraction: CGFloat = 0.20

    /// The plateau's edges, in multiples of the core. **Named because the
    /// texture reads them too** — a number that appears in a drawing and in the
    /// alpha multiplying it must not be able to drift.
    static let plateauInner = 1 - spread * opaqueFraction
    static let plateauOuter = 1 + spread * opaqueFraction

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
    /// **The bright end, and since 2026-09-11 it is reached by talking rather
    /// than by stopping.**
    ///
    /// It was `alert`: the ring sat at `rest` all sentence and climbed here over
    /// two seconds of silence, because stopping is the moment the paste is
    /// imminent. That argument has not gone away — it has moved to `DropArrow`,
    /// which says the same thing in a shape that can only mean one thing, and
    /// says it only in the mode it is true of.
    ///
    /// What the ring does instead is the job the microphone at the bottom of the
    /// screen used to do. Victor, 2026-09-11: *"în loc de microfonul care apare
    /// jos pe centrul ecranului, aș dori ca fulgerele să pulseze în același ritm
    /// al discuției, cu același fade-out care se întâmplă acum la microfon"*.
    /// The envelope is therefore `RecordingBeacon`'s, verbatim — a floor plus
    /// the voice's share of the way to the top, resampled at `tick` — and the
    /// number is unchanged, because what that number was calibrated for is *how
    /// much of this ring a screen can carry while he works under it*, which the
    /// reason for lighting it does not change.
    private static let loud: CGFloat = 0.225
    /// How long a silence has to last before it reads as a stop rather than as
    /// him thinking mid-sentence. The ring no longer acts on it — `DropArrow`
    /// does — but the threshold is the ring's own, kept here because it is the
    /// same judgement about the same pauses.
    static let patience: TimeInterval = 2
    /// And how long the arrow then takes to arrive.
    static let swell: TimeInterval = 2

    /// **How much bigger the ring gets at the top of his voice.**
    ///
    /// Victor, 2026-09-11: *"crescând dimensiunea cu zece la sută. Nu, chiar 20%
    /// față de cât e default, și apoi să se contracte înapoi, în timp ce se
    /// rotește totodată"* — he corrected himself mid-sentence, so this is 0.2
    /// and not 0.1.
    ///
    /// It rides the same `level` the opacity does, which is what makes the two
    /// one gesture rather than two: the ring swells *and* brightens on a
    /// syllable and falls back between them, at the rate `MicRecorder.level`
    /// falls. **Scale and not a free-running pulse** for the reason the beacon's
    /// own timer-blink was taken out: a ring breathing on a timer proves a timer
    /// is running and says nothing about the audio path, and this one is on
    /// screen precisely to answer *is it hearing me*.
    ///
    /// The spin is untouched and composes with it — the scale is set on a layer
    /// of its own between `stage` and the rotating film, so neither animation is
    /// reaching for the same property as the other. The collapse on the way out
    /// keeps `stage` to itself for the same reason.
    private static let swellScale: CGFloat = 0.2

    /// 20 Hz, the beacon's rate and for the beacon's reason: the value is a
    /// continuous function of how long he has been quiet, so it is *sampled*
    /// rather than animated — an animation would be interpolating toward a
    /// target that has already moved.
    private static let tick: TimeInterval = 1.0 / 20

    /// **One turn round the pointer, and it takes sixteen seconds.**
    ///
    /// Victor, 2026-09-10: *"în timp ce e activ, să aibă o mișcare de rotație în
    /// jurul mouse-ului continuă"*. The film already crackles in place — 25
    /// frames of lightning, coming round every 3.75s — and that says *alive*
    /// without saying anything about the pointer it is drawn round. A rotation
    /// does: it is the one motion that has the cursor as its subject, because
    /// the centre is the only part of the picture that stays still.
    ///
    /// Sixteen seconds is 41pt/s at the rim, which is slower than a hand moves
    /// and slower than the crackle it rides on — an 84° drift over one loop of
    /// the film. Anything brisker turns a mark he is meant to see out of the
    /// corner of his eye into a thing spinning next to what he is reading, which
    /// is the objection that already took the film itself down to a third of its
    /// authored rate.
    ///
    /// Clockwise, which is `CursorMarker`'s direction and the app's only other
    /// rotation. Nothing rests on it beyond the two agreeing.
    private static let spin: TimeInterval = 16

    /// **How long the ring takes to collapse into the pointer when it goes.**
    ///
    /// *"când se oprește dictarea … să se micșoreze către mouse, făcând fade pe
    /// ultimele 20% din drum"*. It used to be `orderOut` — there one frame, gone
    /// the next — and a mark that vanishes says only that it stopped being
    /// drawn. Shrinking says where the sentence went: everything this ring has
    /// been warning about converges on the point it converges on.
    ///
    /// Half a second, on `BindFlight`'s argument at a smaller scale: this is a
    /// receipt glanced at on the way back to work, not a gesture to be studied,
    /// and the words are still a decode away from being pasted behind it.
    private static let collapse: TimeInterval = 0.5

    /// The last fifth of the **travel** — not of the time — is where it fades.
    ///
    /// Those are two different instants under any curve but a straight line, and
    /// his sentence is about the way in ("din drum"), so both halves are sampled
    /// against the same eased progress and the fade is keyed off that. Which
    /// also settles what the ring does for the first four fifths: nothing but
    /// get smaller, at the brightness the swell had left it at, so the collapse
    /// is read as one motion rather than as a dissolve that happens to shrink.
    private static let collapseFade: CGFloat = 0.2

    /// Not to zero: a layer scaled to nothing is a layer whose last drawn frame
    /// is undefined, and 2% of 210pt is four points — below the ink of the
    /// filaments it is made of, so it is gone as a picture before it is gone as
    /// a number.
    private static let collapseEnd: CGFloat = 0.02

    /// **Off `sharingType = .none` for a demo, and only for a demo.**
    ///
    /// The panel is invisible to every screen capture on purpose (see the class
    /// note), which is also why *"show me that it animates"* has no answer: a
    /// recording of it is a recording of the desktop behind it. `WT_HALO_DEMO`
    /// flips this, and nothing else does — what it puts on screen is the halo
    /// over an empty desktop with no dictation running, so there is nothing in
    /// the frame the flag could leak.
    static var capturable = false

    private var panel: RelayPanel?
    /// The layer the collapse is played on. It sits between the panel's own view
    /// and the halo so that the two motions never share a matrix: **this one
    /// scales, the halo underneath turns**, and Core Animation rebuilds
    /// `transform` from the model value for each animation it is given — two
    /// animations on one layer's transform overwrite rather than compose, which
    /// is written down in `CursorMarker` and is why its bloom and its quarter
    /// turn had to become a single `CATransform3D`. Two layers is the other way
    /// out of the same trap, and the cheaper one here: the spin never stops and
    /// the collapse is one-shot, so there is no pair to keep in step.
    private var stage: CALayer?
    /// The layer the voice-driven scale is written on, between `stage` and the
    /// turning film — see `makePanel` for why each motion gets a layer of its
    /// own.
    private var pulse: CALayer?
    private var monitors: [Any] = []
    private var timer: Timer?
    private var live = false
    /// A collapse in flight, and which one. The generation is what a `show`
    /// arriving mid-collapse invalidates: the panel is reused between
    /// dictations, so the delayed `orderOut` at the end of the old collapse
    /// would otherwise put the *new* dictation's ring away half a second after
    /// it came up.
    private var closingGeneration = 0
    private var closing = false

    /// **How long since he last said anything**, asked of whoever is holding the
    /// microphone. A closure for the reason `RecordingBeacon.level` is one: what
    /// is listening is the delegate's business, not this class's.
    var quietSeconds: (() -> TimeInterval)?

    /// **How loud he is right now, 0…1**, asked of the same microphone. This is
    /// what the ring breathes on since 2026-09-11 — see `loud` and `swellScale`.
    var level: (() -> Float)?

    /// Whether *this* dictation has somewhere to go.
    ///
    /// The ring is up for every dictation now, so it can no longer be the thing
    /// that says *this one is headed for the caret* — it says *the microphone is
    /// open*, which is true in both. The distinction moved to `DropArrow`, and
    /// this is the flag that decides whether the arrow is armed at all.
    private var atCaret = false
    private let arrow = DropArrow()

    /// On or off, and whether the words have a destination. Idempotent, and
    /// driven from `syncBorrowedGestures` — the one switch every edge of a
    /// dictation already passes through, so this cannot drift out of step with
    /// the chip or the borrowed buttons.
    ///
    /// `atCaret` is read on every call rather than only on the rising edge: a
    /// ⌘⌃B made mid-sentence gives the words a terminal, and the arrow has to
    /// stop asking him to place them the moment that happens.
    func setActive(_ on: Bool, atCaret: Bool = false) {
        if live == on, self.atCaret == atCaret { return }
        self.atCaret = atCaret
        arrow.armed = on && atCaret
        guard live != on else { return }
        live = on
        // Both edges, for the reason the selection watcher logs both: "why did
        // the ring not come up" has to be answerable from the file, and the
        // conditions behind it are not all visible on screen.
        Log.info(on ? "◯ caret halo on — the microphone is open\(atCaret ? ", and these words go wherever the caret is" : "")"
                    : "◯ caret halo off")
        on ? show() : hide()
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        // **A collapse still in the air is taken back whole**, before anything
        // else: he stopped and started again inside half a second, and what has
        // to be on screen is a full-size ring at rest, not the tail of the last
        // one. Removing the animations is enough — neither writes a model value,
        // so the layer is already at identity underneath them.
        closing = false
        closingGeneration &+= 1
        stage?.removeAnimation(forKey: "collapse")
        stage?.removeAnimation(forKey: "collapse-ink")
        // After `makePanel`, never before: building the layer is what measures
        // the picture and so what sets `artworkGain`.
        panel.alphaValue = Self.opacity(Self.rest)
        // The swell and the arrow are both left wherever the last sentence
        // ended, and a ring that comes up 20% oversized on a syllable nobody has
        // said yet is the same lie a frozen indicator tells.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulse?.transform = CATransform3DIdentity
        CATransaction.commit()
        arrow.hide()
        follow()
        panel.orderFrontRegardless()

        // Global catches every other app the pointer moves over; local catches
        // this app's own panels, which never see a global monitor's events —
        // the chip is riding the same cursor and is not click-through, so
        // without the local half the ring would stop dead whenever the pointer
        // crossed it.
        //
        // **Only if there are none.** They outlive a `hide` now, because the
        // collapse has to keep chasing the pointer, so a dictation opening
        // inside those 0.5s would otherwise install a second pair and leave the
        // first pair leaked for the life of the process.
        if monitors.isEmpty {
            let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                                 .rightMouseDragged, .otherMouseDragged]
            if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
                self?.follow()
            }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in
                self?.follow(); return e
            }) { monitors.append(m) }
        }

        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.refresh() }
        timer = t
        // `.common`, because the chords that reach this app are held mouse
        // buttons and a tracking loop would otherwise stall the swell.
        RunLoop.main.add(t, forMode: .common)
    }

    /// **It shrinks into the pointer rather than stopping being drawn.**
    ///
    /// The swell stops here — the timer goes and the panel keeps the alpha the
    /// silence had brought it to — so what moves during the collapse is the
    /// picture's size, and its ink only over the last fifth of the way in.
    private func hide() {
        timer?.invalidate()
        timer = nil
        // **Straight out, not collapsed.** The ring shrinking into the pointer
        // says *the sentence went there*; an arrow still asking him to place the
        // caret while it does would be asking for something already decided.
        arrow.hide()

        guard panel != nil, let stage = stage else {
            for m in monitors { NSEvent.removeMonitor(m) }
            monitors = []
            self.panel?.orderOut(nil)
            return
        }

        closing = true
        closingGeneration &+= 1
        let generation = closingGeneration

        // **Sampled, both of them, against one eased progress.** `u` is how far
        // in it has travelled and `t` is how much of the half-second has gone;
        // they are the same number only for a straight line, and the ask is
        // about the travel. Smoothstep rather than the Bézier `ChipWipe` solves
        // by Newton: they are indistinguishable at this length, and this one is
        // an expression.
        let steps = 24
        var scale: [CGFloat] = [], ink: [CGFloat] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let u = t * t * (3 - 2 * t)
            scale.append(1 - u * (1 - Self.collapseEnd))
            ink.append(u < 1 - Self.collapseFade ? 1 : (1 - u) / Self.collapseFade)
        }

        let shrink = CAKeyframeAnimation(keyPath: "transform.scale")
        shrink.values = scale
        shrink.duration = Self.collapse
        // **Held at the last frame, and never written into the model.** The
        // panel is ordered out on the beat this ends, so a layer snapping back
        // to full size underneath is invisible — and it has to snap back, or the
        // next dictation's ring would come up 2% of its size.
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        stage.add(shrink, forKey: "collapse")

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = ink
        fade.duration = Self.collapse
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        stage.add(fade, forKey: "collapse-ink")

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapse) { [weak self] in
            guard let self = self, self.closingGeneration == generation, !self.live else { return }
            self.closing = false
            for m in self.monitors { NSEvent.removeMonitor(m) }
            self.monitors = []
            self.panel?.orderOut(nil)
            stage.removeAnimation(forKey: "collapse")
            stage.removeAnimation(forKey: "collapse-ink")
        }
    }

    /// Centred on the pointer, every time the pointer reports. Off the events
    /// rather than off a timer for `RelayWindow.startFollowingMouse`'s measured
    /// reason: a 60 Hz poll trails a fast pointer by a whole tick plus a
    /// window-move round trip, and a ring that lags is a ring that is visibly
    /// not *round* anything.
    private func follow() {
        // **Through the collapse as well**, which is the whole of *towards the
        // mouse*: the hand is usually already moving toward wherever the words
        // are going, and a ring shrinking onto the spot the pointer has left is
        // converging on nothing. Same reason `BindFlight` re-reads the cursor
        // every frame instead of sampling it once.
        guard live || closing, let panel = panel else { return }
        panel.setFrameOrigin(Self.origin())
        // The arrow's window rides the same origin, in the same call — see
        // `DropArrow` for why it is a window and why it is not its own monitor.
        arrow.place(at: Self.origin())
    }

    /// Where a panel the size of this one has to sit for its centre to be the
    /// pointer. Two windows read it, which is why it is a function.
    private static func origin() -> NSPoint {
        let p = NSEvent.mouseLocation
        return NSPoint(x: (p.x - side / 2).rounded(), y: (p.y - side / 2).rounded())
    }

    /// **One sample of his voice, spent on two things at once**: how bright the
    /// ring is and how big it is. `RecordingBeacon`'s envelope for the first —
    /// a floor plus the voice's share of the way to the top — and the same
    /// fraction applied to a scale for the second, so the swell and the glow are
    /// one breath rather than two effects that happen to coincide.
    ///
    /// The silence clock is still read, but nothing about the ring depends on it
    /// any more: it goes to `DropArrow`, which is the mode-specific half of what
    /// the swell used to say.
    private func refresh() {
        guard live, let panel = panel else { return }
        let loud = CGFloat(max(0, min(1, level?() ?? 0)))
        let floor = Self.opacity(Self.rest), ceiling = Self.opacity(Self.loud)
        panel.alphaValue = floor + (ceiling - floor) * loud
        // The scale is set on `pulse` and nowhere else — `stage` belongs to the
        // collapse and the film to the spin, and a layer whose transform is
        // written from a timer cannot also be the one an animation is holding.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let s = 1 + Self.swellScale * loud
        pulse?.transform = CATransform3DMakeScale(s, s, 1)
        CATransaction.commit()
        arrow.refresh(quiet: quietSeconds?() ?? 0, at: Self.origin())
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
        /// **Not drawn at all: `assets/caret-halo.png`, and what ships.**
        ///
        /// Everything above answers *what can be drawn that reads like the
        /// reference*; this is the reference. Victor, 2026-09-10: *"use this as
        /// the halo when dictating at caret … faded out dynamically by the same
        /// rules"* — so the band is his picture and the rules around it are
        /// untouched: the same radius, the same envelope, the same 5%→22.5%
        /// swell on silence.
        ///
        /// **This is the second time a picture was tried and the first time it
        /// worked**, and the difference is the file rather than the idea. The
        /// reference sent in September was a glow *authored on white*: keying the
        /// background out left olive mud on a dark editor, because the brightness
        /// had been coming from the white all along. This one arrives with a real
        /// alpha channel and saturated ink — blue and magenta filaments over
        /// nothing — so there is nothing to unmultiply and nothing that was
        /// borrowing light from a ground that is about to be removed.
        ///
        /// It also settles the *"doar galben"* rule by superseding it rather than
        /// breaking it. One hue was the answer to hues that read as a smudge at a
        /// twentieth of an opacity; these two do not, because they are opposite
        /// ends of the spectrum at full saturation rather than three shades of the
        /// same gold, and the picture keeps its structure at any alpha for the
        /// same reason the smooth gradient did — the detail is *in* the falloff,
        /// not laid on top of it.
        case storm
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
    /// **`storm` ships since 2026-09-10** — Victor's picture, which is where a
    /// day of drawing textures was always headed. `codex3`, the reeds that
    /// shipped for an afternoon, and `smooth`, the gradient band that shipped for
    /// a day, both stay: the first because it is the best thing this file drew on
    /// its own, the second because it is the reference the contact sheet is
    /// judged against.
    static let design: Design = {
        guard let name = ProcessInfo.processInfo.environment["WT_HALO_DESIGN"],
              let picked = Design(rawValue: name) else { return .storm }
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
        if design == .storm {
            // Not through `patternCache`: this one is a layer tree with a mask
            // and a running animation, not a still image.
            if let film = filmLayer(side: side) { return film }
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
            // `.storm` only reaches here when its sheet is missing, and then it
            // is the fallback texture rather than nothing.
            let made = strokes(side: side, design: design == .storm ? .codex3 : design)
            patternCache[key] = made
            layer.contents = made
        }
        layer.contentsGravity = .resize
        return layer
    }

    /// **The picture, resampled onto the band, masked by the same envelope, and
    /// running as a film.**
    ///
    /// Victor, on seeing the still: *"nu e animat!! trebuie să fie multiframe: cu
    /// frame-urile decupate din imaginea pe care ți-am dat-o … trebuie să pară că
    /// se animă ca un clip, nu doar fade in, fade out"*. The swell was never the
    /// animation — it is the *state*. The ring itself has to crackle.
    ///
    /// So the asset is a **sprite sheet**: `caret-halo-5x5.png`, the 25 frames of
    /// his GIF keyed off black, packed row-major, at their own 236px. The grid is
    /// read out of the file name (`-<cols>x<rows>`, absent meaning a single
    /// frame), which is the whole of the configuration — drop a different sheet
    /// in with a different grid in its name and it plays.
    ///
    /// Four things happen, and only four:
    ///
    /// 1. **The film is measured once, not per frame.** The frames share a
    ///    centroid and a ring radius by construction, and measuring each one
    ///    separately would let the ring *breathe* — a wobble of a pixel or two
    ///    per frame, which on a mark this size reads as the halo pulsing in and
    ///    out of true. So the alpha is averaged across all 25 first, and the one
    ///    transform that puts that mean ring on `core` is used for every frame.
    /// 2. **The envelope is a mask, not a pixel pass.** With 25 frames the
    ///    per-pixel multiply the single still used would be 25× the work at
    ///    launch for a result the GPU gives away: a radial `CAGradientLayer`
    ///    built from the *same* `profile` masks the whole film at once. Same
    ///    falloff, one layer, and the frames stay untouched images.
    /// 3. **Discrete keyframes, at the GIF's own 20fps.** `.discrete` because
    ///    lightning does not tween — an interpolated cross-fade between two
    ///    crackles is a blur, which is exactly the *fade* he was objecting to.
    /// 4. **The light is still matched on the panel** (`artworkGain`), measured
    ///    on the mean frame for the reason in point 1.
    private static func filmLayer(side: CGFloat) -> CALayer? {
        guard let (url, cols, rows) = artworkFile(),
              let file = NSImage(contentsOf: url),
              let sheet = file.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Log.info("◯ caret halo: no caret-halo sheet found — drawing \(Design.codex3.rawValue) instead")
            return nil
        }
        let cw = sheet.width / cols, ch = sheet.height / rows
        guard cw > 0, ch > 0 else { return nil }

        // Every cell, row-major, which is the order they were packed in and so
        // the order the GIF ran in. `cropping` shares the sheet's pixels.
        var frames: [CGImage] = []
        for r in 0..<rows {
            for c in 0..<cols {
                guard let cell = sheet.cropping(to: CGRect(x: c * cw, y: r * ch, width: cw, height: ch))
                else { continue }
                frames.append(cell)
            }
        }
        guard !frames.isEmpty else { return nil }

        // The mean frame's alpha, in the cell's own pixels: the sheet drawn once
        // and accumulated cell by cell.
        guard let probe = CGContext(data: nil, width: sheet.width, height: sheet.height,
                                    bitsPerComponent: 8, bytesPerRow: sheet.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        probe.draw(sheet, in: CGRect(x: 0, y: 0, width: CGFloat(sheet.width), height: CGFloat(sheet.height)))
        guard let raw = probe.data else { return nil }
        let buf = raw.bindMemory(to: UInt8.self, capacity: sheet.width * sheet.height * 4)
        var mean = [CGFloat](repeating: 0, count: cw * ch)
        for r in 0..<rows {
            for c in 0..<cols {
                for y in 0..<ch {
                    for x in 0..<cw {
                        let sx = c * cw + x, sy = r * ch + y
                        mean[y * cw + x] += CGFloat(buf[(sy * sheet.width + sx) * 4 + 3]) / 255
                    }
                }
            }
        }
        let cells = CGFloat(cols * rows)
        for i in 0..<mean.count { mean[i] /= cells }

        // Centroid and alpha-weighted mean radius, in cell pixels counted from
        // the *top* — which is how a bitmap context's rows run, and so has to be
        // flipped before it can be a drawing origin.
        var mass: CGFloat = 0, mx: CGFloat = 0, my: CGFloat = 0
        for y in 0..<ch {
            for x in 0..<cw {
                let a = mean[y * cw + x]
                guard a > 0 else { continue }
                mass += a; mx += a * CGFloat(x); my += a * CGFloat(y)
            }
        }
        guard mass > 0 else { return nil }
        let cx = mx / mass, cyTop = my / mass
        var spanned: CGFloat = 0
        for y in 0..<ch {
            for x in 0..<cw {
                let a = mean[y * cw + x]
                guard a > 0 else { continue }
                spanned += a * hypot(CGFloat(x) - cx, CGFloat(y) - cyTop)
            }
        }
        let meanRadius = spanned / mass
        guard meanRadius > 1 else { return nil }
        let k = core / meanRadius                       // points per source pixel

        // Flux against the band, integrated in source pixels — each of which
        // covers k² points once mapped.
        var pictureFlux: CGFloat = 0
        for y in 0..<ch {
            for x in 0..<cw {
                let r = hypot(CGFloat(x) - cx, CGFloat(y) - cyTop) * k
                pictureFlux += mean[y * cw + x] * alpha(atRadius: r) * k * k
            }
        }
        var referenceFlux: CGFloat = 0
        let half = side / 2
        for y in 0..<Int(side) {
            for x in 0..<Int(side) {
                referenceFlux += alpha(atRadius: hypot(CGFloat(x) - half, CGFloat(y) - half))
            }
        }
        artworkGain = min(3, referenceFlux / max(pictureFlux, 1))
        Log.info(String(format: "◯ caret halo film: %d frames of %dpx, ring r=%.0fpx → %.0fpt, %.2f× the band's flux, panel ×%.2f",
                        frames.count, cw, meanRadius, core, pictureFlux / max(referenceFlux, 1), artworkGain))

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: side, height: side)

        let film = CALayer()
        film.contentsGravity = .resize
        film.magnificationFilter = .trilinear
        // The cell, scaled by `k` and hung so its centroid is on the pointer.
        // `ch - cyTop` is the flip: the measurement counts rows down, the frame
        // counts points up.
        film.frame = CGRect(x: half - cx * k,
                            y: half - (CGFloat(ch) - cyTop) * k,
                            width: CGFloat(cw) * k, height: CGFloat(ch) * k)
        film.contents = frames[0]
        if frames.count > 1 {
            let reel = CAKeyframeAnimation(keyPath: "contents")
            reel.values = frames
            reel.calculationMode = .discrete
            reel.duration = Double(frames.count) / fps
            reel.repeatCount = .infinity
            // **Removed on completion off, and the model value left at frame 0.**
            // The panel is ordered out between dictations rather than rebuilt, so
            // an animation that tidied itself away would leave a still ring the
            // second time the halo came up.
            reel.isRemovedOnCompletion = false
            film.add(reel, forKey: "reel")
        }
        container.addSublayer(film)

        // The envelope, as the mask the whole film runs behind.
        let fade = CAGradientLayer()
        fade.type = .radial
        fade.frame = container.bounds
        fade.startPoint = CGPoint(x: 0.5, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 1)
        fade.colors = profile.map { NSColor(white: 1, alpha: $0.1).cgColor }
        fade.locations = profile.map { NSNumber(value: Double(min(1, $0.0 * core / half))) }
        container.mask = fade
        return container
    }

    /// **A third of the GIF's own rate** — Victor, on watching it run at 20fps:
    /// *"mai lentă animația 3×"*. The frames were authored for a clip that is
    /// looked *at*; this one runs an inch from what he is reading while he
    /// dictates, and at 20fps a crackle that fast is a flicker in the corner of
    /// the eye rather than a mark that happens to be alive. At 6.7fps the same
    /// 25 frames take 3.75s to come round, which is slow enough to read as
    /// movement and not as noise.
    private static let fps = 20.0 / 3

    /// **How much the panel is brightened to carry the picture's light**, set
    /// when the film is built and 1 for every drawn design.
    private(set) static var artworkGain: CGFloat = 1

    /// The panel opacity for one of the two states, with that gain in it.
    ///
    /// The ceiling is a rail and nothing more: a replacement picture sparse
    /// enough to need the full 3× would otherwise be asking for a two-thirds
    /// opaque ring over his work, which is the objection that took the resting
    /// opacity from 10% to zero in the first place. It must not bite on a normal
    /// picture — clamping the alarmed state is exactly how the flux match this
    /// gain exists to make would get undone, leaving a swell that is quieter
    /// than the one it replaced.
    static func opacity(_ base: CGFloat, for design: Design = design) -> CGFloat {
        min(0.6, base * (design == .storm ? artworkGain : 1))
    }

    /// **The film and its grid, from the file name.** `caret-halo-5x5.png` is
    /// twenty-five frames packed five across; a name without the suffix is a
    /// single frame, which is what makes a still and a film the same code path.
    ///
    /// Found the way `whisper_helper.py` is: `Bundle.main` when installed,
    /// `assets/` walking up from the binary when run out of `.build` — which is
    /// how the contact sheet is shot — and `WT_HALO_IMAGE` overriding both, so a
    /// candidate sheet can be tried without touching the repo.
    private static func artworkFile() -> (URL, Int, Int)? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WT_HALO_IMAGE"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        let names = ["caret-halo-5x5.png", "caret-halo.png"]
        if let res = Bundle.main.resourcePath {
            for n in names { candidates.append(URL(fileURLWithPath: res).appendingPathComponent(n)) }
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            for n in names { candidates.append(dir.appendingPathComponent("assets/\(n)")) }
            dir = dir.deletingLastPathComponent()
        }
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return nil }
        // `…-<cols>x<rows>` at the end of the stem, or one frame.
        let stem = url.deletingPathExtension().lastPathComponent
        guard let dash = stem.range(of: "-", options: .backwards) else { return (url, 1, 1) }
        let parts = stem[dash.upperBound...].split(separator: "x")
        guard parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]), c > 0, r > 0
        else { return (url, 1, 1) }
        return (url, c, r)
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
        case .smooth, .storm:
            // Neither is drawn from strokes: `smooth` returns a gradient layer
            // and `storm` a resampled picture, both before this is ever called.
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
            // Codex's reed field — short radial strokes that never span the band,
            // so they cannot line up into rays from a common origin the way a
            // sunburst does. Its stagger and its hashed jitter are kept verbatim.
            //
            // **One field across the whole ring, not three zones.** It arrived as
            // a dense band between two radii plus two thin scatters outside them,
            // which is what the *previous* envelope wanted — a wide plateau with
            // short ramps. Under this one the ring is mostly ramp, so a texture
            // that concentrated its ink in the middle fifth would leave the fade
            // to be carried by a handful of stragglers. The ink is uniform and
            // the envelope does all the fading, which is what *linear,
            // progressive* asks for.
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
            ctx.setLineCap(.round)

            let lo = inner + 2, hi = outer - 2
            for i in 0..<260 {
                let a = CGFloat(i) * (.pi * 2 / 260) + CGFloat((i * 37) % 19) * 0.003
                let u = CGFloat((i * 29) % 100) / 99
                // Area-weighted: an annulus at r has 2πr to fill, so a count
                // spread evenly in *radius* thins out as it goes. This is the
                // inverse CDF of a density proportional to r — and it is
                // `sqrt(a² + u(b² − a²))`, not `a + sqrt(u)(b − a)`, which was
                // tried and moved the peak outward instead of flattening it.
                let r = sqrt(lo * lo + u * (hi * hi - lo * lo))
                // Lengths as a fraction of the ring's thickness rather than in
                // points, so the texture survives the halo being resized — it
                // has already been scaled by 0.7 once.
                let len = band * (0.07 + CGFloat((i * 17) % 15) / 15 * 0.07)
                let w = CGFloat(3 + ((i * 11) % 3))
                let r0 = max(lo, r - len * 0.48), r1 = min(hi, r + len * 0.52)
                if r1 > r0 { spoke(a, from: r0, to: r1, width: w) }
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
                // **The envelope is the last multiplication, and the clamp goes
                // before it.** Written the other way — `min(1, coverage × gain ×
                // envelope)` — the flux gain destroys the very fade it is meant
                // to be filling in: at a gain of 2.5 every pixel whose envelope
                // is above 0.4 saturates, so both ramps are clipped to a hard
                // edge somewhere inside themselves and the picture ends abruptly
                // instead of thinning out. Victor saw it immediately — *"the
                // image itself should be fading out inner/outer"* — and it is
                // the one arrangement in which the envelope cannot shape the
                // light at all. Clamping the **ink** and then applying the
                // envelope means the falloff he drew is exactly the falloff on
                // screen, whatever the gain.
                let ink = min(1, coverage * gain)
                var a = ink * alpha(atRadius: radius)
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
        p.sharingType = Self.capturable ? .readOnly : .none

        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        // **A stage of our own, rather than the view's backing layer.** AppKit
        // owns that one and resets its transform on any layout it feels like
        // doing; the collapse would then be undone mid-flight by something with
        // no opinion about the halo at all.
        let stage = CALayer()
        stage.frame = CGRect(x: 0, y: 0, width: side, height: side)
        let halo = Self.haloLayer(side: side)
        // **The turn goes on the halo, not on the stage** — see `stage` for why
        // the two motions may not share a layer. Its box is the whole panel, so
        // its centre is the pointer, and the picture inside is hung with its own
        // centroid on that same point: the rotation therefore has no radius to
        // wobble around. The envelope goes round with it and cannot tell,
        // because a radial mask turned about its centre is the same mask.
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * Double.pi
        turn.duration = Self.spin
        turn.repeatCount = .infinity
        // Like the film's own reel, and for the film's own reason: the panel is
        // ordered out between dictations rather than rebuilt, so an animation
        // that tidied itself away would leave a ring that turns for one sentence
        // and stands still for every one after it.
        turn.isRemovedOnCompletion = false
        halo.add(turn, forKey: "spin")
        // **A third layer, for a third motion.** `stage` belongs to the collapse
        // and the film to the spin, and the swell is written from a timer 20
        // times a second — three claims on one `transform`, where Core Animation
        // gives each layer exactly one. The rule is `CursorMarker`'s, arrived at
        // the same way: two animations on one transform overwrite rather than
        // compose. Its box is the whole panel, so it scales about the pointer.
        let pulse = CALayer()
        pulse.frame = CGRect(x: 0, y: 0, width: side, height: side)
        pulse.addSublayer(halo)
        stage.addSublayer(pulse)
        view.layer?.addSublayer(stage)
        self.stage = stage
        self.pulse = pulse
        p.contentView = view

        panel = p
        return p
    }
}

// MARK: - Looking at it

extension CaretHalo {
    /// **The halo on the real screen, round the real pointer, without a
    /// dictation** — `WT_HALO_DEMO=20 ./.build/debug/WalkieTalkie`.
    ///
    /// `shoot` answers *what does the picture look like*; this answers the other
    /// half, which a still cannot: *does it move*. It runs the actual panel on a
    /// **fabricated sentence** — an 12s cycle of six seconds of "speech", at
    /// syllable rate, and six of silence — so one loop shows everything there is
    /// to see: the ring breathing and brightening on the voice, falling back
    /// between syllables, and then the drop arrow fading up two seconds into the
    /// quiet and marching until he starts again.
    ///
    /// `atCaret` is on, because the arrow is half of what there is to look at.
    ///
    /// It is the only path that sets `capturable`, so it is also the only way a
    /// screenshot of this app can contain the ring — which is what makes any of
    /// this provable rather than merely asserted.
    static func demo(seconds: Double) {
        capturable = true
        let halo = CaretHalo()
        let started = Date()
        /// Where in the 12s loop we are.
        let phase = { Date().timeIntervalSince(started).truncatingRemainder(dividingBy: 12) }
        halo.level = {
            let t = phase()
            guard t < 6 else { return 0 }
            // Three syllables a second, never quite to zero between them — which
            // is what `MicRecorder.level`'s three-second fall actually looks like
            // under ordinary speech.
            return Float(0.25 + 0.75 * abs(sin(t * .pi * 3)))
        }
        halo.quietSeconds = { max(0, phase() - 6) }
        halo.setActive(true, atCaret: true)
        // **It ends the way a dictation ends, not with `exit(0)`.** The collapse
        // is the half of this that no still can show and that a demo cut off
        // mid-frame cannot either — so the last half-second of every demo is the
        // ring going where it goes, and a capture taken then is the only proof
        // available that it does.
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            halo.setActive(false)
            Timer.scheduledTimer(withTimeInterval: collapse + 0.3, repeats: false) { _ in exit(0) }
        }
        NSApplication.shared.run()
    }
}

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
        let alphas: [CGFloat] = [rest, loud, 1]
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
                    // **The picture's row is drawn at the picture's opacity.**
                    // `storm` makes its missing flux up on the panel rather than
                    // in the bitmap, so a sheet that used the bare `rest` for
                    // every row would show it at half the light it actually runs
                    // at — which is the one thing a contact sheet exists to get
                    // right. Read after the layer is built: that is what sets
                    // it. The last column is the profile at full strength and
                    // takes no gain — it is there to judge the falloff, not the
                    // state.
                    let lit = alpha < 1 ? opacity(alpha, for: design) : alpha
                    NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                        .draw(in: box, from: .zero, operation: .sourceOver, fraction: lit)
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
        shootArrow(to: (path as NSString).deletingPathExtension + "-arrow.png")
    }

    /// **The same sheet for the two things the picture gained on 2026-09-11**:
    /// the ring at both ends of its voice-driven swell, and `DropArrow` over it.
    ///
    /// It is a second file rather than two more rows, because neither of these
    /// is a *design* — the sheet above is a gallery of textures and this is one
    /// texture in two states with something drawn on top of it.
    ///
    /// The arrow is the reason it had to exist at all. The ring can at least be
    /// watched through `WT_HALO_DEMO`; the arrow only appears two seconds into a
    /// silence in the middle of a caret dictation, on a panel no screen capture
    /// can contain — so without this there is no way to look at it that does not
    /// involve talking into a microphone and then stopping.
    static func shootArrow(to path: String) {
        let side = Self.side
        let cell = NSSize(width: side, height: side)
        let grounds: [NSColor] = [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.97, alpha: 1)]
        // Quiet with the arrow up (which is the state that goes together), and
        // full voice at the top of the swell, which is where the 20% lives.
        let states: [(String, CGFloat, CGFloat, Bool)] = [
            ("quiet + arrow", rest, 1, true),
            ("full voice", loud, 1 + swellScale, false),
        ]
        let sheet = NSImage(size: NSSize(width: cell.width * CGFloat(states.count),
                                         height: cell.height * CGFloat(grounds.count)))
        sheet.lockFocus()
        for (row, ground) in grounds.enumerated() {
            for (col, state) in states.enumerated() {
                let (name, alpha, scale, arrowUp) = state
                let box = NSRect(x: cell.width * CGFloat(col),
                                 y: cell.height * CGFloat(grounds.count - 1 - row),
                                 width: cell.width, height: cell.height)
                ground.setFill()
                box.fill()
                let host = NSView(frame: NSRect(origin: .zero, size: cell))
                host.wantsLayer = true
                // The same three-layer stack `makePanel` builds, posed rather
                // than animated — `ChipWipe.shoot`'s rule, and for its reason: a
                // sheet drawn from a different arrangement than the one that
                // ships is a picture of something nobody sees.
                let pulse = CALayer()
                pulse.frame = CGRect(x: 0, y: 0, width: side, height: side)
                pulse.addSublayer(haloLayer(side: side))
                pulse.transform = CATransform3DMakeScale(scale, scale, 1)
                host.layer?.addSublayer(pulse)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                        .draw(in: box, from: .zero, operation: .sourceOver,
                              fraction: opacity(alpha))
                }
                // **Drawn separately, at its own opacity, because on screen it
                // is its own window** — compositing it through the ring's would
                // be the sheet reproducing the bug that gave it one.
                if arrowUp {
                    let arrowHost = NSView(frame: NSRect(origin: .zero, size: cell))
                    arrowHost.wantsLayer = true
                    arrowHost.layer?.addSublayer(DropArrow.picture())
                    if let rep = arrowHost.bitmapImageRepForCachingDisplay(in: arrowHost.bounds) {
                        arrowHost.cacheDisplay(in: arrowHost.bounds, to: rep)
                        NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                            .draw(in: box, from: .zero, operation: .sourceOver,
                                  fraction: CGFloat(DropArrow.ceiling))
                    }
                }
                (name as NSString).draw(
                    at: NSPoint(x: box.minX + 12, y: box.minY + 12),
                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold),
                                     .foregroundColor: NSColor.systemGray])
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
