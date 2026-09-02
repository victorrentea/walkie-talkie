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

    /// A 30pt strip down the right edge, which is what Victor asked for, and
    /// what makes it a *margin* rather than something sitting on his work: the
    /// glyph is drawn inside it, at the top, and nothing else ever is.
    private static let strip: CGFloat = 30
    /// The gap under the menu bar. It hangs just below it rather than in it: the
    /// bar's right end is the clock and Control Center, and the one place a
    /// window may sit at the top-right of every screen without covering
    /// something macOS put there is immediately underneath.
    private static let topGap: CGFloat = 4

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var recording = false
    private var observer: NSObjectProtocol?

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
        sync()
    }

    private func sync() {
        guard recording else {
            for (_, panel) in panels { panel.orderOut(nil) }
            return
        }
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = Self.displayID(screen) else { continue }
            live.insert(id)
            let panel = panels[id] ?? makePanel(id: id)
            place(panel, on: screen)
            panel.orderFront(nil)
            pulse(panel)
        }
        for (id, panel) in panels where !live.contains(id) { panel.orderOut(nil) }
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
        label.font = .systemFont(ofSize: 22)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: side, height: side - 4)
        label.isBezeled = false
        label.drawsBackground = false
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
