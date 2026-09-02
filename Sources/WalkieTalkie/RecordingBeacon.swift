import AppKit

/// **A microphone in the top-right corner of every screen, for as long as the
/// relay is listening.**
///
/// The chip already says a dictation is running — the pulsing 🔴 and `Listening…`
/// — and it says it *beside the cursor*, which is the one place that is not
/// where Victor is looking when it matters. He talks while reading something on
/// another display, while a full-screen window is up, and macOS hides the
/// pointer the moment he touches the keyboard, taking the chip with it. The one
/// state that must never be in doubt — *is it still hearing me?* — was the state
/// with the least dependable receipt.
///
/// So this is the same fact, nailed down: a fixed corner, on every display, at a
/// size that is readable across a room. It is Wispr Flow's own answer to the
/// same problem, which is what Victor asked for by name.
///
/// **A slow pulse, not a blink.** 1.0 → 0.15 and back over 1.2s each way, which
/// is the 🔴's tempo and chosen for the 🔴's reason: anything brisker is
/// something flashing in the corner of the eye of a man trying to think, and
/// this one is up for the whole minute a dictation to an agent lasts. What the
/// motion buys is the difference between a live indicator and a picture of one —
/// a frozen microphone is indistinguishable from a hung app, which is precisely
/// the failure it is here to rule out.
///
/// **One panel per screen**, for the reason `MenuBarMirror` has one: a window
/// belongs to a single display (`com.apple.spaces spans-displays` is off by
/// default, so no window spans two) and the display Victor is not typing on is
/// exactly the one this is for.
///
/// **Never in a screenshot** (`sharingType = .none`). The relay photographs the
/// screen during the very dictation this marks — the automatic context frame and
/// every F3 — and a confirmation that appears inside the thing it is confirming
/// is a fixture the agent has to learn to ignore. Same rule the capture flash
/// and the menu-bar mirror follow.
final class RecordingBeacon {

    /// **Five times what it was** (2026-09-02, Victor's ask): a 30pt strip with a
    /// 22pt glyph in it, read across a room, was a speck. The whole argument for
    /// this thing is that it answers *is it still hearing me?* from the display
    /// he is not typing on — an indicator that has to be looked for does not.
    ///
    /// It costs the "margin, never on his work" property the 30pt strip had, and
    /// that trade is deliberate: it is up only while he is talking, it is
    /// half-faded for most of that by the pulse, and the corner it sits in is
    /// the one part of a screen nothing is ever laid out against.
    private static let strip: CGFloat = 150
    /// The glyph inside it, at the same 0.73 of the strip it has always been.
    private static let ink: CGFloat = 110
    /// **It flies out of the pointer**, and the beacon is where it lands.
    ///
    /// The corner is the right place for it to *live* and the wrong place for it
    /// to *appear*: a microphone materialising on the far edge of a screen
    /// Victor is not looking at is a thing he finds later, if at all. The gesture
    /// that started the dictation happened under his hand, so that is where the
    /// receipt starts — the same sentence `BindFlight` says about a window, run
    /// for a state instead of a target: *what you just did now lives up there.*
    private static let flightDuration: CFTimeInterval = 0.45
    /// It waits out the red cursor target first (`CaptureFlash.markerDuration`),
    /// because the two would otherwise bloom out of the same pixels at the same
    /// instant and read as one confused shape. A beat later the pointer is
    /// uncovered again and the microphone has somewhere to come *from*.
    private static let leadIn: CFTimeInterval = CaptureFlash.markerDuration + 0.05
    /// The size it leaves the pointer at — a chip beside the cursor, not a
    /// 150pt panel dropped on his work and then dragged off it.
    private static let takeoff: CGFloat = 34
    /// The gap under the menu bar. It hangs just below it rather than in it: the
    /// bar's right end is the clock and Control Center, and the one place a
    /// window may sit at the top-right of every screen without covering
    /// something macOS put there is immediately underneath.
    private static let topGap: CGFloat = 4

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var recording = false
    private var observer: NSObjectProtocol?
    /// Whether this dictation's flight has already been played. A `sync` from a
    /// display change mid-sentence must put the panels back where they belong,
    /// not fly them out of a pointer that has long since moved.
    private var flown = false

    func start() {
        // Displays come and go — a projector at a workshop, the desk monitors
        // waking — and a beacon that only exists on the screens present at
        // launch would be missing from the one plugged in for the room.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.sync() }
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        recording = false
        for (_, panel) in panels { panel.orderOut(nil) }
        panels = [:]
    }

    /// The microphone is open, or it is not. Idempotent, because it is called
    /// from `syncBorrowedGestures` — the one switch every edge of a dictation
    /// already goes through, so this cannot drift out of step with the row on
    /// the chip or with the borrowed buttons.
    func setRecording(_ on: Bool) {
        guard recording != on else { return }
        recording = on
        guard on else { flown = false; sync(); return }
        // Nothing on screen for the length of the cursor mark. A dictation that
        // ends inside that beat — under `MicRecorder.minimumDuration`, i.e. a
        // misfire — never puts anything up at all, which is the correct amount
        // of ceremony for a gesture that did not happen.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leadIn) { [weak self] in
            guard let self = self, self.recording, !self.flown else { return }
            self.flown = true
            self.sync(flyFrom: NSEvent.mouseLocation)
        }
    }

    private func sync(flyFrom cursor: NSPoint? = nil) {
        guard recording else {
            for (_, panel) in panels { panel.orderOut(nil) }
            return
        }
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = Self.displayID(screen) else { continue }
            live.insert(id)
            let panel = panels[id] ?? makePanel(id: id)
            // **Only the screen the pointer is on flies.** A window belongs to a
            // single display, so a flight across two is not a thing that can be
            // drawn — and the sentence being said is *this gesture, under your
            // hand, now lives in that corner*, which is only true of the corner
            // on the screen the hand is on. The others simply come up where they
            // belong, at the same moment, so all of them arrive together.
            if let cursor = cursor, NSMouseInRect(cursor, screen.frame, false) {
                fly(panel, on: screen, from: cursor)
            } else {
                place(panel, on: screen)
                panel.orderFront(nil)
            }
            pulse(panel)
        }
        for (id, panel) in panels where !live.contains(id) { panel.orderOut(nil) }
    }

    /// Put the panel down at the pointer, small, then animate it whole to the
    /// corner at full size.
    ///
    /// `setFrame` on the animator rather than a layer transform: the panel is
    /// what has to end up in the corner, and animating a layer inside a window
    /// that is already there would fly a picture across a screen the window is
    /// invisibly covering the whole time — this thing is `ignoresMouseEvents`
    /// but it is still a 150pt window, and one parked over his work for the
    /// length of a flight is exactly what the corner exists to avoid.
    private func fly(_ panel: NSPanel, on screen: NSScreen, from cursor: NSPoint) {
        let small = Self.takeoff
        panel.setFrame(NSRect(x: (cursor.x - small / 2).rounded(),
                              y: (cursor.y - small / 2).rounded(),
                              width: small, height: small), display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        let side = Self.strip
        let target = NSRect(x: (screen.frame.maxX - side).rounded(),
                            y: (screen.visibleFrame.maxY - side - Self.topGap).rounded(),
                            width: side, height: side)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.flightDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func makePanel(id: CGDirectDisplayID) -> NSPanel {
        let side = Self.strip
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: side, height: side),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, so a full-screen window does not bury the one
        // indicator that is supposed to survive one.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // A sign, not a target — it sits over whatever he is working in.
        panel.ignoresMouseEvents = true
        panel.sharingType = .none

        let content = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        content.wantsLayer = true
        let label = NSTextField(labelWithString: "🎙️")
        label.font = .systemFont(ofSize: Self.ink)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: side, height: side - 4)
        label.isBezeled = false
        label.drawsBackground = false
        // The panel is resized through the flight, so the glyph has to follow it
        // rather than staying the size it was built at.
        label.autoresizingMask = [.width, .height]
        content.autoresizesSubviews = true
        content.addSubview(label)
        panel.contentView = content

        panels[id] = panel
        return panel
    }

    /// Restarted rather than resumed on every `sync`, so a beacon that comes back
    /// after a display change starts from full strength instead of wherever the
    /// last cycle happened to leave the layer.
    private func pulse(_ panel: NSPanel) {
        guard let layer = panel.contentView?.layer else { return }
        layer.removeAnimation(forKey: "beacon")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.15
        fade.duration = 1.2
        fade.autoreverses = true
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "beacon")
    }

    private func place(_ panel: NSPanel, on screen: NSScreen) {
        let side = panel.frame.size.width
        // `visibleFrame` is the screen minus the menu bar (and the Dock), so this
        // lands under the bar on a plain display and under the notch's bar on a
        // MacBook, without either number being written down here.
        let x = screen.frame.maxX - side
        let y = screen.visibleFrame.maxY - side - Self.topGap
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
