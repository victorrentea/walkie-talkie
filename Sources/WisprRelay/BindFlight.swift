import AppKit
import QuartzCore

/// The receipt for a bind: a translucent rectangle that appears **over the
/// window that was just captured**, then shrinks and flies to the cursor,
/// arriving under it at a twentieth of its size and vanishing.
///
/// **Why a flight and not a flash.** ⌘⌃D is pressed while looking at a terminal
/// and answered by a chip that lives next to the *cursor* — two places, and
/// nothing connecting them. A blink over the window would confirm the capture
/// but leave the chip unexplained; a blink at the cursor would confirm the chip
/// but never say which window. The travel is the sentence: *that* window is now
/// *this* chip. It is the same argument Victor Addons' break timer makes when it
/// flies in from the coffee that started it.
///
/// **Blue, and that is a three-way distinction, not a preference.** Victor
/// Addons flashes **yellow** for "I captured this", the relay flashes **red**
/// for "it went to the agent" (`CaptureFlash`), and neither of those is what
/// this says. A bind takes no picture and sends nothing; it changes where words
/// will go. A third meaning that borrowed either colour would be read as the
/// thing it borrowed from.
///
/// **It starts as an outline and ends as a solid.** A filled rectangle over a
/// whole terminal window hides the thing it is pointing at — and mid-workshop
/// that window is on a projector. So the border does the work while the shape is
/// big enough for a border to mean anything, and the fill comes up as it
/// shrinks: at 5% there is nothing left to see through, and a hollow token that
/// small is a token nobody sees arrive.
enum BindFlight {

    /// 2s, as asked. Long enough to follow with the eye across a desk, short
    /// enough that it is gone before it becomes something in the way.
    private static let duration: CFTimeInterval = 2.0

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

    private static var panel: NSPanel?
    private static var shape: CALayer?
    private static var timer: Timer?
    private static var startedAt: CFTimeInterval = 0
    private static var origin: CGRect = .zero

    /// Fly from `source` to wherever the cursor is, for the whole 2s — the mouse
    /// is re-read every frame rather than sampled once, so the rectangle chases
    /// a hand that keeps moving instead of arriving where it used to be.
    ///
    /// Main thread only. A second bind cancels the first: two rectangles in
    /// flight would be two answers to a question with one.
    static func fly(from source: CGRect) {
        cancel()
        guard source.width > 1, source.height > 1 else { return }

        // One panel spanning every screen, with the rectangle as a layer inside
        // it. The alternative — resizing a window 120 times — puts every frame
        // through the window server; a layer's frame is a GPU update, and the
        // flight crosses monitors, which a per-screen panel could not.
        let canvas = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard !canvas.isNull else { return }

        let host = NSPanel(contentRect: canvas,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        host.isOpaque = false
        host.backgroundColor = .clear
        host.hasShadow = false
        host.ignoresMouseEvents = true
        host.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        host.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // A bind is very often followed by a dictation, whose first act is to
        // photograph the screen. This must never be in that picture.
        host.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: canvas.size))
        view.wantsLayer = true

        let rect = CALayer()
        rect.borderColor = NSColor.systemBlue.withAlphaComponent(0.95).cgColor
        rect.backgroundColor = NSColor.systemBlue.withAlphaComponent(0).cgColor
        rect.borderWidth = 4
        rect.cornerRadius = 10
        view.layer?.addSublayer(rect)

        host.contentView = view
        host.setFrame(canvas, display: true)
        host.orderFrontRegardless()

        panel = host
        shape = rect
        origin = source
        startedAt = CACurrentMediaTime()

        place(at: 0)
        let tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            let elapsed = CACurrentMediaTime() - startedAt
            guard elapsed < duration else { return cancel() }
            place(at: elapsed / duration)
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    /// One frame. `t` is 0…1 across the whole 2s, hold included.
    private static func place(at t: CFTimeInterval) {
        guard let panel = panel, let shape = shape else { return }

        // The hold is subtracted here rather than by delaying the timer, so the
        // rectangle is on screen from the first frame — standing still is a
        // state it is *in*, not a wait before it exists.
        let flight = max(0, (t - holdFraction) / (1 - holdFraction))
        let eased = ease(flight)

        let scale = 1 - (1 - endScale) * eased
        let from = CGPoint(x: origin.midX, y: origin.midY)
        // Re-read every frame: this is what makes it follow the hand.
        let to = NSEvent.mouseLocation
        let centre = CGPoint(x: from.x + (to.x - from.x) * eased,
                             y: from.y + (to.y - from.y) * eased)
        let size = CGSize(width: origin.width * scale, height: origin.height * scale)

        // Panel coordinates: the canvas may start left of or below zero on a
        // multi-monitor desk, and the layer lives inside it.
        let frame = CGRect(x: centre.x - size.width / 2 - panel.frame.minX,
                           y: centre.y - size.height / 2 - panel.frame.minY,
                           width: size.width, height: size.height)

        let fade = t > 1 - fadeFraction ? CGFloat((1 - t) / fadeFraction) : 1

        // Implicit animations off: every frame is already the animation, and
        // Core Animation interpolating between them lags the cursor by a beat.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = frame
        // The fill arrives as the border stops being able to carry it.
        shape.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.45 * eased).cgColor
        shape.borderWidth = max(1.5, 4 * (0.35 + 0.65 * scale))
        shape.cornerRadius = min(10, min(size.width, size.height) / 4)
        shape.opacity = Float(fade)
        CATransaction.commit()
    }

    /// Cubic ease-in-out: it leaves the window unhurriedly enough to be followed
    /// and settles under the cursor instead of slamming into it.
    private static func ease(_ t: Double) -> CGFloat {
        let t = min(max(t, 0), 1)
        return CGFloat(t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)
    }

    static func cancel() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        shape = nil
    }
}
