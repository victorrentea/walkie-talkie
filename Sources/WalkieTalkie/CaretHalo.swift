import AppKit
import QuartzCore

/// **A ring round the pointer while a dictation is headed for the caret and
/// nothing is bound — faint while he talks, and swelling once he stops.**
///
/// Victor's ask, 2026-09-09: *"when this mode is activated, when I'm not bound,
/// draw a little halo ring around the mouse … about 100 pixels, to warn me that
/// I need to basically pick somewhere to paste it"*.
///
/// ## What it is warning about
///
/// Every other destination this app has is a thing he **pointed at** and a thing
/// the chip **names**: a terminal's icon and `petclinic@main`, a picked folder,
/// `✨` for a session that does not exist yet. A caret dictation names its
/// destination too — `at caret` — and that is exactly the problem: it is the one
/// destination that is not a place, it is *wherever the focus happens to be when
/// the words arrive*. Unbound there is no second answer either, so a sentence
/// spoken with the focus in the wrong window is pasted into the wrong window,
/// discovered afterwards, with nothing having said so at the time.
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

    /// **100pt across, which is his number** and is also the smallest a ring
    /// round the pointer can be and still read as a ring: the cursor itself is
    /// about 20pt, so anything much tighter is a decoration *on* the arrow
    /// rather than a circle drawn round it.
    private static let diameter: CGFloat = 100
    private static let stroke: CGFloat = 3
    /// The panel is a little wider than the ring so the stroke has room to sit
    /// inside it — a shape layer clipped by its own window loses its outer half.
    private static var side: CGFloat { diameter + stroke * 2 + 2 }

    /// What it looks like while he is talking: there, and no more than that.
    private static let rest: CGFloat = 0.10
    /// And once he has stopped. Half-opaque is loud for something riding the
    /// pointer, which is the point — by then it is the only thing on screen
    /// asking the question.
    private static let alert: CGFloat = 0.50
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
        Log.info(on ? "◯ caret halo on — nothing bound, the words go to the caret"
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
        let ring = CAShapeLayer()
        let inset = (side - Self.diameter) / 2
        ring.path = CGPath(ellipseIn: CGRect(x: inset, y: inset,
                                             width: Self.diameter, height: Self.diameter),
                           transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        // **Blue, which is this app's one colour that has never meant an
        // event.** Red is *this went to the agent* and yellow is *Victor Addons
        // captured it*; both announce something that just happened. This
        // announces nothing — it is a standing fact about where the next
        // sentence will land, which is the same reading the `HQ` tag took blue
        // for one row down on the chip.
        ring.strokeColor = NSColor.systemBlue.cgColor
        ring.lineWidth = Self.stroke
        view.layer?.addSublayer(ring)
        p.contentView = view

        panel = p
        return p
    }
}
