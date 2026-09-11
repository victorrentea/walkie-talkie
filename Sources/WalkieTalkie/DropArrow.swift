import AppKit
import QuartzCore

/// **A dotted arrow pointing down at the pointer, drawn only while a dictation
/// with nowhere to go is waiting for him to stop talking.**
///
/// Victor's ask, 2026-09-11: *"ca să pot distinge când dictez fără țintă, vreau
/// ca atunci când tac, când nu mai vorbesc, să apară o animație … o săgeată
/// punctată cu trei linii și un vârf de săgeată în jos din dreptul mouse-ului,
/// care se plimbă cu mouse-ul, ca să sugereze cumva că trebuie să lase acel
/// prompt undeva"*.
///
/// ## It exists because the ring stopped being able to say this
///
/// The halo used to be the whole answer: it was up for `at caret` dictations and
/// for nothing else, so its mere presence meant *these words land wherever the
/// focus happens to be, go and put the focus somewhere*. Since the ring became
/// the voice indicator for **every** dictation that reading is gone — a ring on
/// screen now means the microphone is open, which is equally true of a sentence
/// headed for a bound terminal.
///
/// So the distinction had to be re-said in something that could only mean one
/// thing, and an arrow pointing down at the cursor is that: it names the
/// gesture (*put it somewhere*) rather than warning about a state, and it names
/// it at the only place the gesture happens.
///
/// ## Silence is still the trigger, and for the old reason
///
/// It inherits the swell's schedule whole — `CaretHalo.patience` of quiet before
/// anything appears, `CaretHalo.swell` to fade in. While he is talking the paste
/// is not imminent and there is nothing to ask; the moment he stops, the
/// sentence is about to be delivered and placing the caret is still free. Two
/// seconds rather than instantly because the gaps *inside* a sentence are
/// ordinary — he pauses to think mid-dictation constantly, and an arrow blinking
/// on every breath is a light flashing at the corner of his eye for the length
/// of every sentence.
///
/// ## A panel of its own, and the contact sheet is what proved it had to be
///
/// It was a layer inside `CaretHalo`'s panel for an hour — the obvious build,
/// since that window already sits at the pointer and follows it, and two windows
/// chasing one cursor is two chances to be a frame apart. `WT_SHOOT_HALO`'s
/// arrow sheet is what killed it: **the halo's window alpha is the voice**, and
/// this appears exactly when the voice has stopped, so the arrow was being drawn
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

    /// **How far above the pointer's hot spot the tip sits.** Far enough to
    /// clear the top of the macOS arrow cursor, close enough that what it is
    /// pointing at is unmistakably the cursor and not something under it.
    private static let tip: CGFloat = 14
    private static let headHeight: CGFloat = 15
    private static let headHalfWidth: CGFloat = 9
    /// The shaft starts where the head ends and runs up through the ring's inner
    /// rim. The halo's hole is only ~36pt of radius, so a shaft long enough to
    /// carry three dashes has to cross into the band — which is survivable
    /// because the band is at its faintest there (`CaretHalo.profile` ramps from
    /// nothing at the inner rim) and because this is amber over blue.
    private static let shaftBottom: CGFloat = tip + headHeight - 1
    private static let shaftHeight: CGFloat = 64
    /// **Three lines, which is what he asked for**, and a fourth and fifth that
    /// exist only so the march can loop: the group slides down by exactly one
    /// `period` and repeats, and at the end of that slide the dash that has gone
    /// under the head has to have been replaced at the top by one that was off
    /// the end. The mask fades the top of the shaft out, so what reads on screen
    /// is three dashes flowing into the arrowhead and nothing arriving from
    /// nowhere.
    private static let dashes = 5
    private static let dashLength: CGFloat = 9
    private static let dashWidth: CGFloat = 4
    private static let period: CGFloat = 15
    /// One dash-length of travel per second — walking pace for a hint, and
    /// deliberately slower than the ring's crackle so the two do not compete.
    private static let march: CFTimeInterval = 1.0

    /// **Amber, the halo's own ink.** The film that fills the ring is blue and
    /// magenta, so this is the one hue in the app's palette that cannot be
    /// mistaken for part of it at a glance, and it is the colour every drawn
    /// halo design was tinted with before the picture replaced them.
    private static let ink = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.25, alpha: 1)
    /// Brighter than the ring, and allowed to be: this is a small shape made of
    /// thin strokes, on screen for the seconds between sentences, and it is the
    /// one thing here he is meant to actually read rather than notice.
    static let ceiling: Float = 0.75

    /// Whether this dictation is one the arrow has anything to say about — set
    /// from `CaretHalo.setActive`, and taken away the instant a ⌘⌃B mid-sentence
    /// gives the words a terminal.
    var armed = false {
        didSet {
            guard armed != oldValue else { return }
            if !armed { hide() }
        }
    }

    private var panel: RelayPanel?

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
        guard t > 0 else { return hide() }
        let p = panel ?? makePanel()
        p.setFrameOrigin(origin)
        p.alphaValue = CGFloat(Self.ceiling) * CGFloat(t)
        // `orderFrontRegardless`, like the ring: this app never becomes key, so
        // an ordinary `orderFront` would put it behind whatever is.
        if !p.isVisible { p.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
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
        // **The same box as the ring**, so one origin places both — the arrow
        // needs a tenth of it, and a second rectangle to keep in step with the
        // first is a second thing to get wrong.
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
    static func picture() -> CALayer { DropArrow().build() }

    private func build() -> CALayer {
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

        let head = CAShapeLayer()
        head.frame = container.bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c, y: c + Self.tip))
        path.addLine(to: CGPoint(x: c - Self.headHalfWidth, y: c + Self.tip + Self.headHeight))
        path.addLine(to: CGPoint(x: c + Self.headHalfWidth, y: c + Self.tip + Self.headHeight))
        path.closeSubpath()
        head.path = path
        head.fillColor = Self.ink.cgColor
        container.addSublayer(head)

        // The shaft is its own layer so the march can be a transform on what is
        // inside it while the mask stays put: translating a layer that carries
        // its own mask takes the mask along, and the fade has to belong to the
        // *window* the dashes travel through, not to the dashes.
        let shaft = CALayer()
        shaft.frame = CGRect(x: c - Self.dashWidth, y: c + Self.shaftBottom,
                             width: Self.dashWidth * 2, height: Self.shaftHeight)

        let travelling = CALayer()
        travelling.frame = shaft.bounds
        for i in 0..<Self.dashes {
            let dash = CALayer()
            dash.frame = CGRect(x: (shaft.bounds.width - Self.dashWidth) / 2,
                                y: Self.period * CGFloat(i) + 6,
                                width: Self.dashWidth, height: Self.dashLength)
            dash.cornerRadius = Self.dashWidth / 2
            dash.backgroundColor = Self.ink.cgColor
            travelling.addSublayer(dash)
        }
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = 0
        slide.toValue = -Self.period
        slide.duration = Self.march
        slide.repeatCount = .infinity
        // Linear: a dash that eased would be a dash hesitating, and the sentence
        // this draws is a steady one.
        slide.timingFunction = CAMediaTimingFunction(name: .linear)
        slide.isRemovedOnCompletion = false
        travelling.add(slide, forKey: "march")
        shaft.addSublayer(travelling)

        let fade = CAGradientLayer()
        fade.frame = shaft.bounds
        fade.startPoint = CGPoint(x: 0.5, y: 0)
        fade.endPoint = CGPoint(x: 0.5, y: 1)
        fade.colors = [NSColor.clear, NSColor.white, NSColor.white, NSColor.clear].map(\.cgColor)
        // Hard at the bottom, where a dash sliding under the arrowhead should
        // simply be gone; long at the top, where the loop's seam is.
        fade.locations = [0, 0.04, 0.55, 1]
        shaft.mask = fade
        container.addSublayer(shaft)

        return container
    }
}
