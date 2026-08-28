import AppKit
import QuartzCore

/// The receipt for a bind: **a picture of the window that was just captured**,
/// which appears exactly over that window, then shrinks and flies to the cursor,
/// arriving under it at the size of the chip and vanishing.
///
/// **Why a flight and not a flash.** ⌘⌃D is pressed while looking at a terminal
/// and answered by a chip that lives next to the *cursor* — two places, and
/// nothing connecting them. A blink over the window would confirm the capture
/// but leave the chip unexplained; a blink at the cursor would confirm the chip
/// but never say which window. The travel is the sentence: *that* window is now
/// *this* chip. It is the same argument Victor Addons' break timer makes when it
/// flies in from the coffee that started it.
///
/// **The thing that flies is the window itself, not a chenar around it.** An
/// outline says "something here"; the picture says *which* — a rectangle over a
/// terminal is a rectangle, and two terminals side by side make one of them the
/// wrong answer at a glance. Carrying the pixels also makes the sentence literal:
/// what lands under the cursor is the window, so the chip that stays there is
/// visibly what that window became. Falls back to the old hollow rectangle when
/// the grab returns nothing (no Screen Recording permission, or a window that
/// went away between the bind and the frame) — a flight with no picture still
/// answers *where from*, which is most of what it is for.
///
/// **White, not blue, and not a signal colour at all.** Victor Addons flashes
/// **yellow** for "I captured this" and the relay flashes **red** for "it went to
/// the agent" (`CaptureFlash`) — both of those are events being announced. This
/// is not an announcement, it is a thing being *moved*, and a screenshot in
/// flight already carries its own colours. White is the one tint that frames it
/// without claiming to mean something, and it is the colour the chip it flies
/// into is drawn in.
///
/// **It starts faint and arrives at half.** Opacity climbs from 20% to 50% as it
/// shrinks, which is the inverse of what an alpha ramp usually does and is the
/// point: at the start it lies exactly over the window it was copied from, where
/// anything solid would hide the thing being pointed at — mid-workshop, on a
/// projector — and where being faint costs nothing, since what is underneath is
/// the same picture. By the time it is small enough to hide nothing it is solid
/// enough to be followed across a desk.
///
/// **One panel per screen, and that is not an optimisation — it is the only
/// thing that works.** This was written as a single panel spanning the union of
/// every display, which is the obvious shape for something that has to cross
/// them. It played on exactly one screen. Two rounds of diagnosis went past the
/// real cause: `constrainFrameRect` genuinely was clamping the frame (fixed by
/// using `RelayPanel`, which overrides it), and after that the geometry was
/// provably right — the panel measured `-1920,0 5568×2197` and the layer landed
/// at exactly the source window — and it *still* drew on one screen only.
///
/// The reason is `com.apple.spaces spans-displays`, which is unset on Victor's
/// Mac and unset by default on macOS: **each display has its own Space, so the
/// window server gives a window to one display and no window spans two.**
/// `canJoinAllSpaces` does not buy it back — that is about Spaces on a display,
/// not about spanning displays. So the rectangle is one layer per screen, all
/// showing the same global rectangle in their own coordinates, which is exactly
/// the shape `CaptureFlash` already had for the same reason.
enum BindFlight {

    /// 1s — **halved on 2026-08-28**, from the 2s it was first asked for. Two
    /// seconds is how long a flight has to be to be *studied*, and this one is
    /// not studied twice: once the gesture is learned the animation is a receipt
    /// glanced at, and a receipt that outstays the glance is in the way. Still
    /// long enough to be followed across a desk, which is the floor.
    ///
    /// Not private: the bind flash is sized to it, so the panel in the corner
    /// clears at the exact moment the picture lands and the chip takes over.
    /// A second number would drift from this one.
    static let duration: CFTimeInterval = 1.0

    /// The first eighth is spent standing still at full size. Without it the
    /// rectangle is already shrinking by the time the eye arrives, and the one
    /// question it exists to answer — *which window?* — is asked of a shape
    /// that has stopped covering it.
    private static let holdFraction = 0.125

    /// What it has left when it reaches the cursor.
    private static let endScale: CGFloat = 0.05

    /// The last fifth is a fade. It is already small by then, so the fade is
    /// what makes it *end* rather than blink out mid-flight.
    private static let fadeFraction = 0.2

    /// Opacity at the window and opacity at the cursor. It climbs — see the note
    /// on the type. 0.5 is where it stops: a picture that arrived opaque would be
    /// a small window sitting on the desktop for a frame, which reads as a real
    /// window rather than as a token vanishing into the chip.
    private static let startAlpha: CGFloat = 0.2
    private static let endAlpha: CGFloat = 0.5

    /// One per display, each drawing the same rectangle in its own coordinates.
    private struct Pane {
        let panel: NSPanel
        let shape: CALayer
        /// The screen's frame, kept rather than re-read: `NSScreen` objects are
        /// replaced when the display configuration changes, and a flight that
        /// outlived a monitor being unplugged would otherwise ask a stale object
        /// for its origin.
        let frame: CGRect
    }

    private static var panes: [Pane] = []
    /// Fired when the rectangle has finished arriving — **never on cancel**,
    /// which is what a replacing bind does, and whose old answer must not land
    /// on top of the new one.
    private static var onLanded: (() -> Void)?
    private static var timer: Timer?
    private static var startedAt: CFTimeInterval = 0
    private static var origin: CGRect = .zero
    /// Asked every frame for **the chip's frame**, not just its centre: the
    /// rectangle now ends the exact size of the label it is flying into, so the
    /// last thing it does before sliding under it is match its outline. It used
    /// to shrink to a fixed 5% of the captured window — a token whose size said
    /// nothing about where it was going, and which arrived as a different shape
    /// from the thing that was supposed to have become it.
    private static var target: () -> CGRect = { CGRect(origin: NSEvent.mouseLocation, size: .zero) }
    /// Whether the grab came back with anything. Only the fill consults it: with
    /// a picture in the layer a fill would be behind it and invisible, and
    /// without one it is the whole shape.
    private static var hasPicture = false

    /// Fly from `source` to wherever the cursor is, for the whole second — the mouse
    /// is re-read every frame rather than sampled once, so the rectangle chases
    /// a hand that keeps moving instead of arriving where it used to be.
    ///
    /// Main thread only. A second bind cancels the first: two rectangles in
    /// flight would be two answers to a question with one.
    /// `landed` runs the instant the rectangle reaches the cursor. That is when
    /// the chip's label appears, so the two read as one gesture: the rectangle
    /// does not merely end near the pointer, it *becomes* the thing now sitting
    /// there.
    /// `to` is asked **every frame** for where the rectangle is heading — the
    /// chip's own centre, not the raw pointer. The two are 10×22pt apart, which
    /// is the whole difference between a rectangle that stops next to the label
    /// and one that goes *into* it. Defaults to the pointer for callers with no
    /// chip to aim at.
    static func fly(from source: CGRect,
                    to destination: @escaping () -> CGRect = { CGRect(origin: NSEvent.mouseLocation, size: .zero) },
                    landed: (() -> Void)? = nil) {
        cancel()
        guard source.width > 1, source.height > 1 else { return }

        // **Grabbed before the panels exist, not after.** The panels are excluded
        // from captures anyway (`sharingType = .none`), but the grab is also the
        // slowest thing here, and doing it first means the picture is ready for
        // frame one — a flight that started as an outline and acquired its
        // contents a few frames in would flicker at the only moment the eye is
        // actually on it.
        let picture = grab(source)
        hasPicture = picture != nil

        panes = NSScreen.screens.map { screen in
            // `RelayPanel`, not `NSPanel`: AppKit's `constrainFrameRect` pulls a
            // window back onto a display and below the menu bar, and `RelayPanel`
            // overrides that away. It matters even at exactly one screen's size —
            // a screen above the primary starts above the menu bar.
            let panel = RelayPanel(contentRect: screen.frame,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            // **Under the chip, not over it.** This used to sit at the maximum
            // window level, which put the rectangle *on top of* the label it is
            // flying into — the last thing it did was cover the answer. One level
            // below the overlay's own `.statusBar` and it slides underneath and
            // is gone, which is what "it becomes the chip" should look like.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            // A bind is very often followed by a dictation, whose first act is to
            // photograph the screen. This must never be in that picture.
            //
            panel.sharingType = .none

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true

            let rect = CALayer()
            // One `CGImage` shared by every screen's layer: it is read-only and
            // immutable, and copying a retina window per display would be a few
            // megabytes each for a picture that is on screen for one second.
            rect.contents = picture
            // `.resize` and not `.resizeAspect`: the frame *is* the window's
            // aspect on the way out and the chip's on the way in, so letterboxing
            // would open bars along the sides exactly as it arrives. The squeeze
            // into the chip's proportions is the shape becoming the label.
            rect.contentsGravity = .resize
            // The picture has to be clipped by the rounded corners, or it draws
            // square over them and the radius is only visible in the border.
            rect.masksToBounds = true
            // Opaque white deliberately: the layer's own opacity ramp already
            // dims it to a fifth at the start, and a border that was translucent
            // *as well* would leave the shape with no visible edge over the very
            // window it is naming.
            rect.borderColor = NSColor.white.cgColor
            // Only ever seen without a picture — behind one it would be invisible.
            // It is the old rectangle's fill, in white.
            rect.backgroundColor = NSColor.white.withAlphaComponent(0).cgColor
            rect.borderWidth = 4
            rect.cornerRadius = 10
            view.layer?.addSublayer(rect)

            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return Pane(panel: panel, shape: rect, frame: screen.frame)
        }
        guard !panes.isEmpty else { return }

        origin = source
        target = destination
        onLanded = landed
        startedAt = CACurrentMediaTime()

        place(at: 0)
        let tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let elapsed = CACurrentMediaTime() - startedAt
            guard elapsed < duration else { return land() }
            place(at: elapsed / duration)
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// One frame. `t` is 0…1 across the whole flight, hold included.
    private static func place(at t: CFTimeInterval) {
        guard !panes.isEmpty else { return }

        // The hold is subtracted here rather than by delaying the timer, so the
        // rectangle is on screen from the first frame — standing still is a
        // state it is *in*, not a wait before it exists.
        let flight = max(0, (t - holdFraction) / (1 - holdFraction))
        let eased = ease(flight)

        let from = CGPoint(x: origin.midX, y: origin.midY)
        // Re-read every frame: this is what makes it follow the hand.
        let destination = target()
        let to = CGPoint(x: destination.midX, y: destination.midY)
        let centre = CGPoint(x: from.x + (to.x - from.x) * eased,
                             y: from.y + (to.y - from.y) * eased)
        // Toward the chip's own width and height, or — with no chip to land in —
        // the old fixed fraction, so a caller without one still gets a token
        // rather than a rectangle that never shrinks.
        let end = destination.isEmpty
            ? CGSize(width: origin.width * endScale, height: origin.height * endScale)
            : destination.size
        let size = CGSize(width: origin.width + (end.width - origin.width) * eased,
                          height: origin.height + (end.height - origin.height) * eased)
        // The rectangle in global screen coordinates, computed once and then
        // expressed in each screen's own — so every display draws the same shape
        // and it crosses their edges continuously rather than jumping.
        let global = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2,
                            width: size.width, height: size.height)

        let fade = t > 1 - fadeFraction ? CGFloat((1 - t) / fadeFraction) : 1
        // The climb from faint to half-solid, times the fade at the end. With a
        // picture the layer's own opacity is the whole effect; without one the
        // white fill does the same job the blue one used to, and the two are
        // multiplied rather than added so a fallback flight is not twice as pale.
        let alpha = startAlpha + (endAlpha - startAlpha) * eased
        let fill = hasPicture
            ? NSColor.white.withAlphaComponent(0).cgColor
            : NSColor.white.withAlphaComponent(0.55 * eased).cgColor
        // The border thins as the shape does, and "how far along is it" is now
        // read off the flight itself rather than off a scale factor that no
        // longer exists — the rectangle interpolates toward the chip's size, not
        // toward a fraction of its own.
        let border = max(1.5, 4 * (1 - 0.65 * eased))
        let radius = min(10, min(size.width, size.height) / 4)

        // Implicit animations off: every frame is already the animation, and
        // Core Animation interpolating between them lags the cursor by a beat.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pane in panes {
            // A screen the rectangle has left is not asked to composite it. The
            // window would clip it anyway; this skips the work rather than the
            // pixels.
            guard pane.frame.intersects(global) else {
                pane.shape.isHidden = true
                continue
            }
            pane.shape.isHidden = false
            pane.shape.frame = global.offsetBy(dx: -pane.frame.minX, dy: -pane.frame.minY)
            // The fill arrives as the border stops being able to carry it.
            pane.shape.backgroundColor = fill
            pane.shape.borderWidth = border
            pane.shape.cornerRadius = radius
            pane.shape.opacity = Float(fade * alpha)
        }
        CATransaction.commit()
    }

    /// A picture of what is on screen inside `source`, in Cocoa coordinates.
    ///
    /// **The screen, not the window.** `CGWindowListCreateImage` can be asked for
    /// one window's own buffer by id, which would come back unobstructed and
    /// without a shadow — and would be the *wrong* picture: what has to be
    /// recognisable is what Victor was looking at when he pressed, including
    /// whatever is sitting on top of that terminal. Grabbing the rectangle also
    /// costs nothing extra and needs no window id, which the binding does not
    /// keep (see `Target.sourceFrame`).
    ///
    /// **Not `screencapture`**, which everything else in this app uses: that is a
    /// subprocess, waited on, ~200ms — a fifth of the whole flight spent before
    /// the first frame, and the gesture would feel like it had missed the press.
    /// This is one in-process call at retina resolution in a few milliseconds.
    /// It is deprecated in favour of ScreenCaptureKit, whose API is async and
    /// would put the picture a callback away from a flight that has to start now.
    ///
    /// Cocoa's y grows upward from the primary screen's bottom, the window
    /// server's downward from its top — the same conversion `TerminalBinding`
    /// does on the way in, run backwards.
    private static func grab(_ source: CGRect) -> CGImage? {
        guard let primary = NSScreen.screens.first else { return nil }
        let flipped = CGRect(x: source.minX,
                             y: primary.frame.maxY - source.maxY,
                             width: source.width, height: source.height)
        return CGWindowListCreateImage(flipped, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution])
    }

    /// Cubic ease-in-out: it leaves the window unhurriedly enough to be followed
    /// and settles under the cursor instead of slamming into it.
    private static func ease(_ t: Double) -> CGFloat {
        let t = min(max(t, 0), 1)
        return CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
    }

    /// The flight ran its course: tear it down, *then* hand over.
    private static func land() {
        let completion = onLanded
        cancel()
        completion?()
    }

    static func cancel() {
        timer?.invalidate()
        timer = nil
        for pane in panes { pane.panel.orderOut(nil) }
        panes = []
        onLanded = nil
        hasPicture = false
    }
}
