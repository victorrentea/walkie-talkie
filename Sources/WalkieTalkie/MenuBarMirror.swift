import AppKit

/// The menu bar glyph, repeated on the screens macOS refuses to put it on.
///
/// `NSStatusItem` lives in **one** menu bar: the one on the display that has the
/// keyboard focus. Victor works across three, and the state the glyph carries —
/// paused, loading, listening — is exactly the state he needs while looking at
/// the *other* two, since the chip is hidden the moment he starts typing and the
/// real status item has followed the focus somewhere he is not.
///
/// There is no API for a status item on every display, so this draws one: a tiny
/// borderless panel per screen, at status-bar level, carrying the same string
/// `StatusItem` puts in the menu bar. It is an indicator and nothing else — no
/// menu, no click — because the menu is one focus-change away and a click here
/// would mean moving the mouse to another display anyway.
///
/// **Centred in the menu bar strip, not at either end.** The right end is the
/// clock and Control Center, the left is the frontmost app's menus; the middle is
/// empty on every screen this has ever been looked at, and it is the only spot
/// that cannot cover something macOS put there.
final class MenuBarMirror {

    /// How tall the strip is. Read from the screen rather than assumed: it is 24
    /// on a plain display and taller on a notched one, and a mirror sitting at
    /// the wrong height reads as a floating box rather than as part of the bar.
    private static func barHeight(_ screen: NSScreen) -> CGFloat {
        max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
    }

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var glyph = "🤖"
    private var timer: Timer?

    func start() {
        // The active display is not a notification — `NSScreen.main` moves with
        // the focus and says nothing when it does — so it is polled. Half a
        // second: this is a "which screen am I on" question, and the answer only
        // matters after he has already looked away from one screen and settled on
        // another.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        sync()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (_, panel) in panels { panel.orderOut(nil) }
        panels = [:]
    }

    /// The same string the menu bar shows — `🤖`, `⏸️🤖`, `⏳🤖`.
    func setGlyph(_ value: String) {
        guard glyph != value else { return }
        glyph = value
        for (_, panel) in panels { (panel.contentView?.subviews.first as? NSTextField)?.stringValue = value }
        sync()
    }

    private func sync() {
        let screens = NSScreen.screens
        let active = NSScreen.main.flatMap { Self.displayID($0) }
        var live: Set<CGDirectDisplayID> = []

        for screen in screens {
            guard let id = Self.displayID(screen) else { continue }
            // Not on the active screen: the real status item is already there, and
            // two robots on one menu bar is a bug report waiting to happen.
            guard id != active else { continue }
            live.insert(id)
            let panel = panels[id] ?? makePanel(id: id)
            (panel.contentView?.subviews.first as? NSTextField)?.stringValue = glyph
            place(panel, on: screen)
            panel.orderFront(nil)
        }

        // A screen that became active — or was unplugged — keeps its panel and
        // loses its place on screen. Rebuilding one costs a window; hiding it
        // costs nothing, and displays come back.
        for (id, panel) in panels where !live.contains(id) { panel.orderOut(nil) }
    }

    private func makePanel(id: CGDirectDisplayID) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 22),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // **Dimmed, because every icon beside it is.** macOS draws the menu bar on
        // an inactive display at reduced opacity, and these panels only ever exist
        // on inactive displays — so at full strength ours was the one bright thing
        // in a greyed-out bar, which reads as an alert rather than as a mirror of
        // the item on the other screen. It brightens the moment that display takes
        // the focus, since the mirror is then removed and the real status item
        // arrives in its place.
        panel.alphaValue = 0.45
        // Above the menu bar (`.mainMenu` is 24) so it is not drawn behind the
        // strip it is pretending to be part of.
        panel.level = .statusBar
        // On every space, including full-screen ones — the display Victor is
        // *not* typing on is very often the one with a full-screen window on it,
        // which is precisely when he cannot see the chip either.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // It is a sign, not a target: clicks go through to whatever is underneath,
        // which on a menu bar is the menu bar.
        panel.ignoresMouseEvents = true
        // Never in a screenshot of Victor's own screen — the same rule the flash
        // panel follows, and for the same reason: this thing is about the recording,
        // it is not part of what is being recorded.
        panel.sharingType = .none

        let label = NSTextField(labelWithString: glyph)
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 2, width: 30, height: 18)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 22))
        content.addSubview(label)
        panel.contentView = content

        panels[id] = panel
        return panel
    }

    private func place(_ panel: NSPanel, on screen: NSScreen) {
        let bar = Self.barHeight(screen)
        let size = panel.frame.size
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - bar + (bar - size.height) / 2
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
