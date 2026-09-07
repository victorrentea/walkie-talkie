import AppKit

/// **A microphone in Wispr Flow's own badge slot, on the screen the pointer is
/// on, for as long as the relay is listening.**
///
/// The chip already says a dictation is running — the pulsing 🔴 and the
/// `Listening...` bar — and it says it *beside the cursor*, which is the one
/// place that is not where Victor is looking when it matters. He talks while
/// reading something on another display, while a full-screen window is up, and
/// macOS hides the pointer the moment he touches the keyboard, taking the chip
/// with it. The one state that must never be in doubt — *is it still hearing
/// me?* — was the state with the least dependable receipt.
///
/// ## It lives where he already looks, which is not where it was
///
/// It spent a week as a 150pt microphone in the **top-right corner** of every
/// display, on the reasoning that a corner is the one part of a screen nothing
/// is ever laid out against and that big is what makes an indicator readable
/// across a room. Both halves were true and both missed the point, which Victor
/// made on 2026-09-07: *"emoji-ul acela de microfon vreau să îl pui în locul
/// badge-ului lui Wispr Flow, în aceeași poziție, că mă uit mereu la el
/// acolo"*.
///
/// **The eye does not go to the best place, it goes to the practised one.** He
/// has been dictating through Wispr Flow for a year and has spent that year
/// glancing at one specific spot in the menu bar to find out whether the
/// microphone is open. An indicator that is objectively more visible somewhere
/// else is still an indicator he has to remember to look for; one in the slot
/// his eyes already travel to costs him nothing to read. That is a stronger
/// argument than size, and it is why this went from 150pt to 19.
///
/// **The slot is measured, not written down.** `anchor(on:)` asks the window
/// server where Wispr Flow's badge actually is on that screen and puts this one
/// there. Hardcoding the coordinate would be hardcoding *how many status items
/// happen to sit to its right*, which changes when anything at all is added to
/// the menu bar — and the failure would be silent and would look exactly like
/// this feature not working.
///
/// ## One screen, the pointer's
///
/// It was every display at once, which is right for a corner nobody clicks and
/// wrong for a badge in the menu bar: four copies of it means three of them are
/// sitting on top of three real menu bars he is not looking at. The pointer is
/// the best available guess at where he is looking — it is the same assumption
/// the chip is built on — and unlike the chip this one survives him typing,
/// because it is not anchored to a pointer that macOS hides.
///
/// ## And it gets out of the way
///
/// The panel already ignores mouse events, so a click was always getting
/// through to whatever is under it. What it did not do is let him *see* what he
/// was aiming at — and what is under it is, by construction, Wispr Flow's own
/// badge. So the pointer arriving inside it takes it off screen until the
/// pointer leaves: *"dacă mouse-ul merge peste el, dispare ca să pot să dau
/// click sub el"*.
///
/// **A slow pulse, not a blink.** 1.0 → 0.15 and back over 1.2s each way, which
/// is the 🔴's tempo and chosen for the 🔴's reason: anything brisker is
/// something flashing in the corner of the eye of a man trying to think, and
/// this one is up for the whole minute a dictation to an agent lasts. What the
/// motion buys is the difference between a live indicator and a picture of one —
/// a frozen microphone is indistinguishable from a hung app, which is precisely
/// the failure it is here to rule out. At 19pt the pulse is doing more work than
/// it used to, since size is no longer carrying any of it.
///
/// **One panel per screen still**, even though only one is ever up: a window
/// belongs to a single display (`com.apple.spaces spans-displays` is off by
/// default), and a panel built for a display keeps that display's scale and
/// Space behaviour. Which of them is *visible* is the pointer's business.
///
/// **Never in a screenshot** (`sharingType = .none`). The relay photographs the
/// screen during the very dictation this marks — the automatic context frame and
/// every shutter press — and a confirmation that appears inside the thing it is
/// confirming is a fixture the agent has to learn to ignore. Same rule the
/// capture flash and the menu-bar mirror follow. It is therefore not checkable
/// with a screenshot; what is checkable is the geometry, through
/// `CGWindowListCopyWindowInfo`, which is how both this and the slot it is
/// aiming at were verified.
final class RecordingBeacon {

    /// The badge, and it is deliberately tiny. Wispr Flow's own is 21 × 24
    /// (measured, 2026-09-07); Victor asked for *"un pic mai mic"*, so the box
    /// is 19 and the glyph inside it 16 — a hair under the thing it is standing
    /// beside rather than a second one competing with it.
    private static let strip: CGFloat = 19
    private static let ink: CGFloat = 16
    /// **It flies out of the pointer**, and the badge is where it lands.
    ///
    /// The slot is the right place for it to *live* and the wrong place for it
    /// to *appear*: a microphone materialising in a menu bar he is not looking
    /// at is a thing he finds later, if at all. The gesture that started the
    /// dictation happened under his hand, so that is where the receipt starts —
    /// the same sentence `BindFlight` says about a window, run for a state
    /// instead of a target: *what you just did now lives up there.*
    ///
    /// It **shrinks** now where it used to grow, which is the bind flight's own
    /// direction and reads the same way: a thing under the hand becoming a mark
    /// in the corner.
    private static let flightDuration: CFTimeInterval = 0.45
    /// It waits out the red cursor target first (`CaptureFlash.markerDuration`),
    /// because the two would otherwise bloom out of the same pixels at the same
    /// instant and read as one confused shape. A beat later the pointer is
    /// uncovered again and the microphone has somewhere to come *from*.
    private static let leadIn: CFTimeInterval = CaptureFlash.markerDuration + 0.05
    /// The size it leaves the pointer at. Bigger than where it lands, and bigger
    /// than the badge is by enough to be seen leaving: a 19pt mark that starts
    /// at 19pt does not read as having travelled.
    private static let takeoff: CGFloat = 34
    /// How far the pointer has to be from the badge before it comes back — the
    /// badge's own box plus this. A bare containment test flickers it on and off
    /// while he works along the menu bar; a margin makes leaving a decision
    /// rather than a jitter.
    private static let clearance: CGFloat = 8

    /// Where Wispr Flow's badge sits when it cannot be found — because it is not
    /// running, or because it has stopped publishing a window.
    ///
    /// Measured from the real thing on all four of Victor's displays: 513pt from
    /// the right edge on each external monitor and 532 on the built-in, i.e. it
    /// is the same handful of status items on every bar. 513 is the one that is
    /// right three times out of four, and being a few points off in a fallback
    /// nothing is expected to reach is the correct amount of wrong.
    private static let fallbackInsetFromRight: CGFloat = 513

    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var recording = false
    private var observer: NSObjectProtocol?
    private var pointerMonitor: Any?
    /// Whether this dictation's flight has already been played. A `sync` from a
    /// display change mid-sentence must put the badge back where it belongs, not
    /// fly it out of a pointer that has long since moved.
    private var flown = false
    /// The display the badge is currently showing on, so a pointer move that
    /// stays on one screen costs a comparison and nothing else.
    private var shownOn: CGDirectDisplayID?
    private var hiddenByPointer = false

    func start() {
        // Displays come and go — a projector at a workshop, the desk monitors
        // waking — and a badge that only knew the screens present at launch
        // would be missing from the one plugged in for the room.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.sync() }
    }

    func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
        releasePointer()
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
        guard on else { flown = false; releasePointer(); sync(); return }
        // Nothing on screen for the length of the cursor mark. A dictation that
        // ends inside that beat — under `MicRecorder.minimumDuration`, i.e. a
        // misfire — never puts anything up at all, which is the correct amount
        // of ceremony for a gesture that did not happen.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leadIn) { [weak self] in
            guard let self = self, self.recording, !self.flown else { return }
            self.flown = true
            self.watchPointer()
            self.sync(flyFrom: NSEvent.mouseLocation)
        }
    }

    // MARK: - Following the pointer

    /// **A global monitor, not a poll.** `MenuBarMirror` polls `NSScreen.main`
    /// every 500ms because the focused screen posts nothing; the pointer does
    /// post, and half a second of lag on *get out of the way so I can click* is
    /// half a second of him clicking at a thing that is still covered.
    ///
    /// A global monitor sees only events going to other applications, which is
    /// every event there is here: the app is `.accessory`, never becomes key,
    /// and this panel ignores the mouse. It is armed for the length of a
    /// dictation and taken down with it, rather than run all day for a badge
    /// that is on screen for a minute an hour.
    private func watchPointer() {
        releasePointer()
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in self?.applyPointer() }
        applyPointer()
    }

    private func releasePointer() {
        if let m = pointerMonitor { NSEvent.removeMonitor(m) }
        pointerMonitor = nil
        shownOn = nil
        hiddenByPointer = false
    }

    /// Which panel is up, and whether it is up at all. The two questions the
    /// pointer answers, asked together because they change together and because
    /// the answer has to be idempotent — this runs on every mouse move.
    private func applyPointer() {
        guard recording, flown else { return }
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }),
              let id = Self.displayID(screen) else { return }

        let panel = panels[id] ?? makePanel(id: id)
        let over = panel.frame.insetBy(dx: -Self.clearance, dy: -Self.clearance).contains(cursor)
        guard id != shownOn || over != hiddenByPointer else { return }

        for (other, p) in panels where other != id { p.orderOut(nil) }
        if over {
            panel.orderOut(nil)
        } else {
            place(panel, on: screen)
            panel.orderFront(nil)
            pulse(panel)
        }
        shownOn = id
        hiddenByPointer = over
    }

    // MARK: - Placement

    private func sync(flyFrom cursor: NSPoint? = nil) {
        guard recording else {
            for (_, panel) in panels { panel.orderOut(nil) }
            shownOn = nil
            return
        }
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = Self.displayID(screen) else { continue }
            live.insert(id)
            let panel = panels[id] ?? makePanel(id: id)
            // Only the pointer's screen shows anything — see the type comment.
            // The flight is that same screen's, for the reason it always was:
            // the sentence is *this gesture, under your hand, now lives up
            // there*, which is only true of the bar on the screen the hand is on.
            if let cursor = cursor, NSMouseInRect(cursor, screen.frame, false) {
                fly(panel, on: screen, from: cursor)
            } else {
                panel.orderOut(nil)
            }
        }
        for (id, panel) in panels where !live.contains(id) {
            panel.orderOut(nil)
            panels[id] = nil
        }
        applyPointer()
    }

    /// Put the panel down at the pointer, then animate it whole into the badge
    /// slot at its final size.
    ///
    /// `setFrame` on the animator rather than a layer transform: the panel is
    /// what has to end up in the slot, and animating a layer inside a window
    /// that is already there would fly a picture across a screen the window is
    /// invisibly covering the whole time.
    private func fly(_ panel: NSPanel, on screen: NSScreen, from cursor: NSPoint) {
        let small = Self.takeoff
        panel.setFrame(NSRect(x: (cursor.x - small / 2).rounded(),
                              y: (cursor.y - small / 2).rounded(),
                              width: small, height: small), display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        pulse(panel)
        let target = Self.anchor(on: screen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.flightDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func place(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrame(Self.anchor(on: screen), display: false)
    }

    /// **Wispr Flow's badge on this screen, asked of the window server.**
    ///
    /// It publishes one small window per display at menu-bar height
    /// (`layer` 25, 21 × 24 or so). Both halves of the filter matter: the owner
    /// name alone would also match its 512 × 586 `Status` panel, and a size
    /// filter alone would match half the menu bar.
    ///
    /// `CGWindowListCopyWindowInfo` speaks **CG global coordinates** — y
    /// downwards from the top-left of the primary display — and everything this
    /// class does is in Cocoa's, so the flip is the load-bearing line. It agrees
    /// with Cocoa only on the primary screen, which is the same trap
    /// `TerminalBinding.cocoaRect` is written under and which stays invisible
    /// until a second monitor is plugged in.
    ///
    /// Bounds are readable without Screen Recording; only the *pixels* need it,
    /// and nothing here reads pixels.
    private static func anchor(on screen: NSScreen) -> NSRect {
        let side = strip
        // Under the menu bar's own baseline: the badge is centred in the bar's
        // height rather than hung off `visibleFrame`, which is the bar's bottom
        // edge and would put a 19pt mark half into the content below it.
        let barTop = screen.frame.maxY
        let barBottom = screen.visibleFrame.maxY
        let centred = barBottom + (barTop - barBottom - side) / 2

        if let slot = wisprBadge(on: screen) {
            return NSRect(x: (slot.midX - side / 2).rounded(),
                          y: (slot.midY - side / 2).rounded(),
                          width: side, height: side)
        }
        return NSRect(x: (screen.frame.maxX - fallbackInsetFromRight - side / 2).rounded(),
                      y: centred.rounded(), width: side, height: side)
    }

    private static func wisprBadge(on screen: NSScreen) -> NSRect? {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // CG's origin is the top-left of the *primary* display — the one whose
        // Cocoa frame starts at zero — not of the union of all of them.
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        guard let flipAbout = primary?.frame.maxY else { return nil }

        for w in windows {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  owner.localizedCaseInsensitiveContains("wispr"),
                  let layer = w[kCGWindowLayer as String] as? Int, layer > 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w0 = b["Width"], let h0 = b["Height"],
                  w0 <= 60, h0 <= 60 else { continue }
            let rect = NSRect(x: x, y: flipAbout - y - h0, width: w0, height: h0)
            if NSMouseInRect(NSPoint(x: rect.midX, y: rect.midY), screen.frame, false) { return rect }
        }
        return nil
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
        // indicator that is supposed to survive one — and so that it draws over
        // the bar it is sitting in rather than under it.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // A sign, not a target — it sits over whatever he is working in, and it
        // sits over another app's badge, which he may want to press.
        panel.ignoresMouseEvents = true
        panel.sharingType = .none

        let content = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        content.wantsLayer = true
        let label = NSTextField(labelWithString: "🎙️")
        label.font = .systemFont(ofSize: Self.ink)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: side, height: side - 2)
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

    /// Restarted rather than resumed on every appearance, so a badge that comes
    /// back after a display change or after the pointer moved off it starts from
    /// full strength instead of wherever the last cycle left the layer.
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

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
