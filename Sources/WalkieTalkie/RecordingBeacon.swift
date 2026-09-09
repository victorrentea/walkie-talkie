import AppKit

/// **A microphone on the bottom edge of the screen the pointer is on, halfway
/// across, lit by his own voice, for as long as the relay is listening.**
///
/// The chip already says a dictation is running — the pulsing 🔴 and the
/// `Listening...` bar — and it says it *beside the cursor*, which is the one
/// place that is not where Victor is looking when it matters. He talks while
/// reading something on another display, while a full-screen window is up, and
/// macOS hides the pointer the moment he touches the keyboard, taking the chip
/// with it. The one state that must never be in doubt — *is it still hearing
/// me?* — was the state with the least dependable receipt.
///
/// ## It has moved twice, and each move was a smaller claim about his eyes
///
/// It spent a week as a 150pt microphone in the **top-right corner** of every
/// display, then a fortnight as a 19pt one **in Wispr Flow's own badge slot**,
/// on the reasoning Victor gave on 2026-09-07: *"mă uit mereu la el acolo"* —
/// the eye goes to the practised place, not the objectively visible one, so an
/// indicator in the slot his eyes already travel to costs him nothing to read.
///
/// **What that argument left out is that the slot belonged to somebody else.**
/// Its coordinate was Wispr Flow's badge, asked of the window server on every
/// appearance and every pointer move; when Wispr's badge stopped publishing at
/// the end of a dictation the query answered nothing, a hardcoded fallback
/// answered somewhere else, and the microphone moved across the bar on its own.
/// That is the *"pleacă … ca un glonț, undeva spre sus"* Victor reported on
/// 2026-09-09, along with where he wanted it instead — drawn on a screenshot
/// rather than described: **84pt on the bottom edge, centred**.
///
/// **And the bottom edge is nobody's.** `anchor(on:)` is now `midX` and
/// `minY + 8` of the screen and asks nothing of anything. The practised-place
/// argument is spent along with the slot, but it has been replaced by something
/// stronger than a habit: at 84pt, lit by his voice, it is not an indicator he
/// has to find.
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
/// was aiming at — and at 84pt on the bottom edge that is a good deal more of
/// his screen than a badge in the menu bar was. So the pointer arriving inside
/// it takes it off screen until the pointer leaves. He asked for it twice, a
/// fortnight apart and in the same words: *"dacă mouse-ul merge peste el,
/// dispare ca să pot să dau click sub el"*, and again on 2026-09-09 — *"să
/// dispară ca să pot să dau click sub el liniștit, fără să mă stresez"*.
///
/// **The voice is the only thing that moves it.** It rests, still, at `quiet`,
/// and rides `MicRecorder.level` up to full while he speaks — *"by default not
/// blink, but stay there very transparent … and then when I speak, blink in sync
/// with the volume of my voice, so that I can see when I am actually being
/// recorded"* (2026-09-09).
///
/// There **was** a second opacity under this one: a free-running 1.0 → 0.5 pulse
/// at 1.2s each way, the 🔴's tempo, multiplied by the voice-driven alpha. The two
/// were said to answer different questions — *is it hearing me right now* and *is
/// this thing still running* — and the pulse was there because a frozen microphone
/// is indistinguishable from a hung app. That argument is what `quiet` is now set
/// from, and it is why the pulse could go: **the voice answers both questions, and
/// answers the second one better.** A timer-driven blink proves a timer is running;
/// it proves nothing about the audio path, and a beacon blinking cheerfully over a
/// dead microphone is the exact failure it claimed to rule out. One that lifts when
/// he speaks cannot be faked by anything except a working capture — and it is
/// checked at the only moment the answer matters, which is while he is talking.
///
/// What it costs is the resting state: still, and dim enough to be ignorable.
/// `quiet` is therefore set to **the dimmest the old blink already went** (0.35
/// alpha × the pulse's 0.5 floor), so nothing on screen got brighter — the light
/// simply stopped moving when nobody is talking.
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

    /// **The size and the spot are both Victor's, drawn rather than described**
    /// (2026-09-09): he marked a rounded square on a screenshot of his own
    /// screen — centred on the X axis, sitting on the bottom edge — and asked
    /// for *"și ca mărime și ca poziție"*. Measured off that mark it is 84pt a
    /// side with about 8 under it, which is what these are.
    ///
    /// It is four times the badge it used to be because nothing is standing
    /// beside it any more to be polite to: in the menu bar it was a 19pt mark
    /// among other 19pt marks, and on an empty edge that reads as a speck.
    private static let strip: CGFloat = 84
    private static let ink: CGFloat = 68
    /// How far the box floats over the bottom edge of the screen. Off
    /// `frame`, not `visibleFrame`: his Dock is not at the bottom, and the spot
    /// he drew is the screen's own edge rather than the content area's.
    private static let bottomInset: CGFloat = 8
    /// **The flight out of the pointer is gone** (2026-09-09). It used to take
    /// off from the cursor and shrink into the menu bar, on the argument that a
    /// microphone materialising in a bar he is not looking at is a thing he
    /// finds later, if at all. Victor reported it as noise — *"pleacă de la
    /// mouse … ca un glonț, undeva spre sus"* — and the argument does not
    /// survive the move: the box lands on the bottom edge at 84pt, which is not
    /// somewhere he has to be *shown*, and a shape crossing his screen every
    /// time he starts talking is a cost paid per sentence for a fact he learns
    /// once. It fades up in place instead.
    private static let fadeIn: CFTimeInterval = 0.2
    /// It waits out the red cursor target first (`CaptureFlash.markerDuration`),
    /// so the two do not bloom at the same instant and read as one confused
    /// shape. It also means a dictation that ends inside that beat — under
    /// `MicRecorder.minimumDuration`, i.e. a misfire — never puts anything up.
    private static let leadIn: CFTimeInterval = CaptureFlash.markerDuration + 0.05
    /// How far the pointer has to be from the badge before it comes back — the
    /// badge's own box plus this. A bare containment test flickers it on and off
    /// while he works along the menu bar; a margin makes leaving a decision
    /// rather than a jitter.
    private static let clearance: CGFloat = 8

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
    /// **How loud he is, asked of whoever is holding the microphone.** A closure
    /// rather than a reference to `MicRecorder`, for the reason every other seam
    /// in this app is a closure: the beacon marks *the relay is listening*, and
    /// what is listening is the app delegate's business, not this class's.
    var level: (() -> Float)?
    private var levelTimer: Timer?

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
        stopWatchingLevel()
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
        guard on else { flown = false; stopWatchingLevel(); releasePointer(); sync(); return }
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
                appear(panel, on: screen)
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

    /// Put the panel where it lives and bring it up out of nothing. The alpha
    /// is handed to `watchLevel` the moment the fade is over, so the first thing
    /// he says lights it.
    private func appear(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrame(Self.anchor(on: screen), display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = Self.quiet
        }, completionHandler: { [weak self] in self?.watchLevel(panel) })
    }

    private func place(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrame(Self.anchor(on: screen), display: false)
    }

    /// **The bottom edge, halfway across.** A constant of the screen and nothing
    /// else — which is the second reason for the move, under Victor's own.
    ///
    /// The slot it used to aim at was *Wispr Flow's badge*, asked of the window
    /// server on every appearance and on every pointer move. That made this
    /// badge's home a property of another app's menu-bar item: when Wispr's
    /// badge went away at the end of a dictation the query answered nothing, the
    /// hardcoded fallback answered somewhere else, and the microphone jumped
    /// across the bar for no reason he could see. Nothing here asks anybody
    /// anything now.
    private static func anchor(on screen: NSScreen) -> NSRect {
        let side = strip
        return NSRect(x: (screen.frame.midX - side / 2).rounded(),
                      y: (screen.frame.minY + bottomInset).rounded(),
                      width: side, height: side)
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

    /// **The panel's opacity is his voice, and nothing else.** One opacity now,
    /// not two multiplied: *"să se aprindă, să fie mai opac, atunci când e mai
    /// mult volum pe audio. Să facă fade când nu mai pronunț nimic"*, and then
    /// *"by default not blink … and then when I speak, blink in sync with the
    /// volume of my voice"*. The pulse that used to run underneath it is gone —
    /// see the type comment for why the voice is the better liveness proof.
    ///
    /// **It never goes out.** Silence lands it at `quiet`, not at zero: the one
    /// state this exists to rule out is a microphone that has stopped hearing
    /// him, and an indicator that disappears when he pauses is indistinguishable
    /// from one that died. The fade is a dimming, not an exit.
    ///
    /// Set flat rather than animated. `MicRecorder.level` is already smoothed on
    /// the audio thread with an attack and a release chosen for the eye, and a
    /// second animation over it would only add lag to a light whose whole job is
    /// to be simultaneous with a voice.
    private func watchLevel(_ panel: NSPanel) {
        levelTimer?.invalidate()
        guard let level = level else { panel.alphaValue = 1; return }
        let tick = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self, weak panel] _ in
            guard let self = self, let panel = panel, self.recording else { return }
            let loud = CGFloat(max(0, min(1, level())))
            panel.alphaValue = Self.quiet + (1 - Self.quiet) * loud
        }
        levelTimer = tick
        RunLoop.main.add(tick, forMode: .common)
    }

    private func stopWatchingLevel() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// What silence looks like: still, and as faint as this badge has ever been.
    ///
    /// **0.175 is not a new number** — it is exactly where the old pulse's floor
    /// already took it (`quiet` 0.35 × the fade's 0.5), i.e. the dimmest this has
    /// ever drawn itself. Asked for "as transparent as it's minimally now", that
    /// is the honest reading: keep the faintest frame the blink used to pass
    /// through and stop passing through the brighter ones.
    private static let quiet: CGFloat = 0.175

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
