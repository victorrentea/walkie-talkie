import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var bubble: BubbleWindow!
    private var status: StatusItem!
    private var snapshotSignal: DispatchSourceSignal?
    private let hotkeys = HotkeyTap()
    private let wispr = WisprWatcher()
    private let dictation = DictationMonitor()

    /// Text that happened to be selected when Wispr started listening. There is
    /// no shortcut for this any more and none is needed: if something was
    /// selected, it is simply picked up — Victor dictates *about* what he has
    /// highlighted, so the selection is the subject of the sentence.
    private var pendingSelection: String?

    /// The screen Victor was looking at when he started talking, captured
    /// automatically. Offered as context ("look if you need to"), unlike the
    /// deliberate ⌃⌥P shots which are things he wants seen.
    private var pendingScreen: String?

    /// Deliberate ⌃⌥P shots taken while a dictation is in flight.
    private var pendingShots: [String] = []
    private var dictationInFlight = false
    private var orphanFlush: DispatchWorkItem?

    private let stateLock = NSLock()

    /// A dictation that never arrives (Wispr discarded it, or nothing was said)
    /// must not strand the shots. After this long with no transcript they are
    /// released as a message of their own.
    private let orphanTimeout: TimeInterval = 120

    private var paused = false
    private var endAnnounced = false

    /// A message that is built, shown, and *not yet written*. It lives here for
    /// the few seconds the bubble displays it, so Cancel has something to stop.
    /// Main thread only.
    private var held: Message?

    /// Long enough to see the prompt, read it, and get a hand to the mouse.
    /// Started at 3–5s and went to 4–7s the first time Victor tried to cancel a
    /// real dictation and didn't make it. Scaled up with length so a long
    /// dictation is still readable, and capped so it never parks over his work.
    private static let minHold: TimeInterval = 4.0
    private static let maxHold: TimeInterval = 7.0

    /// Everything one outbox line is made of, kept together so it can be held
    /// back, released, or dropped as a unit.
    private struct Message {
        let kind: String
        let text: String?
        let selection: String?
        let paths: [String]
        let screen: String?
        let app: String?
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Outbox.prepare()
        bubble = BubbleWindow()

        bubble.onTogglePause = { [weak self] in
            guard let self = self else { return }
            self.paused.toggle()
            self.bubble.setPaused(self.paused)
        }
        bubble.onEndSession = { [weak self] in self?.endSession(reason: "✕ button") }

        status = StatusItem()
        status.onExit = { [weak self] in self?.endSession(reason: "menu bar Exit") }
        bubble.onPromptResolved = { [weak self] send in self?.releaseHeld(send: send) }

        hotkeys.onScreenshot = { [weak self] in self?.plusOneShot() }
        // Mouse 5 is only a hint; DictationMonitor is the authority. Kept because
        // it fires a beat before CoreAudio reports the stream, which makes the
        // selection snapshot land closer to the moment Victor pressed.
        hotkeys.onDictationStarted = { [weak self] in self?.captureContext() }

        wispr.onTranscript = { [weak self] text, app in
            self?.send(kind: "dictation", text: text, app: app)
        }

        dictation.onChange = { [weak self] recording in
            guard let self = self else { return }
            DispatchQueue.main.async { self.bubble.setListening(recording) }
            guard recording else { return }
            self.captureContext()
        }

        let trusted = AXIsProcessTrusted()
        let tapped = hotkeys.start()
        Log.info("accessibility trusted=\(trusted) eventTap=\(tapped)")
        if !trusted || !tapped {
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("⚠️ grant Accessibility to Claude Bubble", duration: 15)
            }
        }
        startListeningForSnapshots()

        wispr.start()
        dictation.start()

        if !wispr.isAvailable {
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("⚠️ Wispr Flow DB not found", duration: 12)
            }
        }
        Log.info("ready — label \(SessionLabel.value), outbox at \(Outbox.outboxURL.path)")

        if ProcessInfo.processInfo.environment["BUBBLE_DEMO"] == "1" { runDemo() }
    }

    /// `kill -USR1 <pid>` writes what is on screen right now to
    /// `<home>/snapshot.png` — the documentation screenshot the window itself
    /// refuses to appear in, and the only way to review a layout change without
    /// standing behind Victor.
    ///
    /// A `DispatchSourceSignal` on the main queue rather than a C handler: drawing
    /// a view has to happen on the main thread, and almost nothing is legal inside
    /// a real signal handler. `SIG_IGN` first, or the default action kills us
    /// before the source ever sees it.
    private func startListeningForSnapshots() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            let path = Outbox.home.appendingPathComponent("snapshot.png").path
            self?.bubble.snapshot(to: path)
        }
        source.resume()
        snapshotSignal = source
    }

    /// Walk the bubble through its states with canned content, for documentation
    /// screenshots. Nothing here touches the outbox: `held` stays nil, so the
    /// displayed prompt resolves into nothing.
    private func runDemo() {
        Log.info("demo mode — driving the UI with canned content")
        let selection = "public Order placeOrder(Cart cart) {"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.bubble.setSelection(selection)
            self?.bubble.setListening(true)
        }
        // The automatic context shot, then one taken with F3 — the two ways the
        // count moves in a real dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.bubble.setShotCount(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.bubble.setShotCount(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.bubble.setListening(false)
            self?.bubble.showSentPrompt("↪ \(selection)\nextract the tax calculation out of this method",
                                        hold: 25)
        }
    }

    // MARK: - Dictation window

    /// Everything that must be true at the instant dictation starts: confirm it
    /// on screen, open the window for attaching shots, grab the selection, and
    /// photograph the screen being talked about.
    ///
    /// Runs on both the Mouse 5 press and the CoreAudio transition, which can
    /// fire within a few hundred ms of each other. That is deliberate and
    /// harmless — but the screen is only captured once per dictation, since a
    /// second capture would cost a megabyte for an identical frame.
    private func captureContext() {
        guard !paused else { return }

        stateLock.lock()
        let alreadyOpen = dictationInFlight
        dictationInFlight = true
        // A new dictation is a new subject. Clear the old one before probing, so
        // a selection stranded by a dictation that never produced a transcript
        // cannot ride along with the next thing he says.
        if !alreadyOpen { pendingSelection = nil }
        stateLock.unlock()

        // The receipt comes FIRST — before the AX probe, before screencapture.
        // Those take the best part of a second between them, and a flash that
        // lands after the work is a flash that no longer means "now": it was
        // firing long after the frame it confirms had already been taken.
        if !alreadyOpen { CaptureFlash.announce() }

        armOrphanFlush()

        // Off the caller's thread on purpose. The clipboard probe sleeps up to
        // 400ms and screencapture is a subprocess we wait on; left on the event
        // tap or the main queue, that is the flash frozen mid-fade.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.stashSelection()

            guard !alreadyOpen else { return }
            guard let path = ScreenCapture.grab() else { return }
            self.stateLock.lock()
            self.pendingScreen = path
            self.stateLock.unlock()
            self.publishShotCount()
            Log.info("context screen captured: \((path as NSString).lastPathComponent)")
        }
    }

    /// Keep the bubble's `📸 ×N` honest. N is what this dictation would carry if it
    /// were sent right now: the automatic context screen counts as the first
    /// picture, because that is what it is — he took it by starting to talk.
    private func publishShotCount() {
        stateLock.lock()
        let count = (pendingScreen != nil ? 1 : 0) + pendingShots.count
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.bubble.setShotCount(count) }
    }

    private func armOrphanFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.orphanFlush?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushOrphaned() }
            self.orphanFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.orphanTimeout, execute: work)
        }
    }

    /// No transcript came. Release deliberate shots so they are never lost; the
    /// automatic context screen is dropped, since without a transcript there is
    /// nothing for it to be context *for*.
    private func flushOrphaned() {
        stateLock.lock()
        let shots = pendingShots
        pendingShots = []
        pendingScreen = nil
        pendingSelection = nil
        dictationInFlight = false
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in self?.bubble.clearSelection() }
        guard !shots.isEmpty else { return }
        Log.info("no transcript within \(Int(orphanTimeout))s — releasing \(shots.count) shot(s) on their own")
        send(kind: "screenshot", paths: shots)
    }

    // MARK: - Actions

    /// What was selected when he started talking IS the subject, for the whole
    /// dictation — so the first non-empty read wins and nothing later overwrites
    /// it. He talks for a minute, another window jumps in front, he switches
    /// apps to look something up, Wispr's own UI takes focus: none of that
    /// changes what he is talking about. Later probes exist only to fill a blank
    /// the first one left (Mouse 5 and the CoreAudio transition both call this,
    /// a few hundred ms apart).
    private func stashSelection() {
        stateLock.lock()
        let alreadyHave = pendingSelection != nil
        stateLock.unlock()
        guard !alreadyHave else { return }

        let text = SelectionCapture.read()
        Log.info("selection front=\(SelectionCapture.frontmostAppName() ?? "?") → \(text.map { "\($0.count) chars" } ?? "nothing")")
        guard let text = text, !text.isEmpty else { return }

        stateLock.lock()
        let lost = pendingSelection != nil      // the other probe got there first
        if !lost { pendingSelection = text }
        stateLock.unlock()
        guard !lost else { return }
        DispatchQueue.main.async { [weak self] in self?.bubble.setSelection(text) }
    }

    /// F3 — one more shot for the dictation in progress.
    private func plusOneShot() {
        guard !paused else { return }
        // Flash first, capture second — same reason as in `captureContext`: the
        // confirmation should land on the keypress, not on the subprocess.
        CaptureFlash.announce()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let path = ScreenCapture.grab() else {
                DispatchQueue.main.async { self.bubble.flash("⚠️ screenshot failed") }
                return
            }

            self.stateLock.lock()
            let attaching = self.dictationInFlight
            if attaching { self.pendingShots.append(path) }
            let count = self.pendingShots.count
            self.stateLock.unlock()

            if attaching {
                self.armOrphanFlush()
                Log.info("📸 attached to in-flight dictation (\(count) so far)")
                // No flash and no title override any more: both are panel states,
                // and throwing the panel into the corner is exactly what taking a
                // picture mid-dictation must not do. The `📸 ×N` in the recording
                // row goes up under his cursor instead — the receipt is the number.
                self.publishShotCount()
                return
            }
            self.send(kind: "screenshot", paths: [path])
        }
    }

    /// What to render in the bubble as "this is what the agent got". Returns nil
    /// for messages with no words in them (a bare screenshot), which fall back
    /// to the one-line flash.
    private static func promptPreview(text: String?, selection: String?, shots: Int) -> String? {
        var parts: [String] = []
        if let selection = selection, !selection.isEmpty { parts.append("↪ " + selection) }
        if let text = text, !text.isEmpty { parts.append(text) }
        guard !parts.isEmpty else { return nil }
        if shots > 0 { parts.append("📸 ×\(shots)") }
        return parts.joined(separator: "\n")
    }

    /// The ✕ and the menu bar's Exit both end the session. Announce it through the
    /// outbox before quitting so the watching Claude learns the bubble is gone
    /// from the queue itself — it is blocked on that file, not on the process, and
    /// would otherwise sit waiting for messages that can no longer come.
    private func endSession(reason: String) {
        announceEnd(reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// Every deliberate way out goes through here — the ✕, ⌘Q, a Quit sent from
    /// Activity Monitor — and it fires at most once.
    ///
    /// The words travel in `text`, not just in `kind`: the agent is watching a
    /// queue, and "user closed the bubble" reads as the instruction it is —
    /// stop watching — where a bare `session_end` has to be interpreted.
    private func announceEnd(_ reason: String) {
        guard !endAnnounced else { return }
        endAnnounced = true
        // Anything still counting down goes out ahead of the goodbye. Quitting is
        // not cancelling — Cancel is a button he presses on purpose — and the
        // outbox writes serially, so it lands in the right order.
        bubble?.flushHeldPrompt()
        Log.info("session ended via \(reason)")
        Outbox.send(kind: "session_end", text: "user closed the bubble")
    }

    /// Catches the quit routes the ✕ does not: ⌘Q, and the Apple Event a newly
    /// launched instance sends to its predecessor.
    ///
    /// Which is exactly why it consults the replacement marker first. Restarting
    /// the bubble kills the old one, and reporting *that* as "user closed the
    /// bubble" would tell the agent to stop watching at the very moment Victor
    /// asked for a fresh session — the one failure mode worth writing code to
    /// avoid, since it is silent and he would only notice by talking into a void.
    func applicationWillTerminate(_ notification: Notification) {
        guard !SingleInstance.beingReplaced() else {
            Log.info("terminating to make way for a new instance — no session_end")
            return
        }
        announceEnd("app terminate")
    }

    private func send(kind: String, text: String? = nil, paths: [String] = [], app: String? = nil) {
        guard !paused else {
            Log.info("paused — dropped \(kind)")
            return
        }
        stateLock.lock()
        let selection = pendingSelection
        pendingSelection = nil
        var attached = paths
        var screen: String?
        if kind == "dictation" {
            attached += pendingShots
            screen = pendingScreen
            pendingShots = []
            pendingScreen = nil
            dictationInFlight = false
        }
        stateLock.unlock()

        if kind == "dictation" {
            DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        }

        let message = Message(kind: kind, text: text, selection: selection,
                              paths: attached, screen: screen, app: app)

        // Show what is about to go out — selection included, since that is part
        // of the prompt the agent receives, not a separate thing.
        let shown = Self.promptPreview(text: text, selection: selection, shots: attached.count)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bubble.clearSelection()

            // Nothing to read is nothing to cancel: a bare screenshot goes
            // straight out, and so does the goodbye.
            guard let shown = shown else {
                self.commit(message)
                if kind == "dictation" {
                    self.bubble.flash(attached.isEmpty ? "🎙️ sent" : "🎙️ sent + \(attached.count) 📸")
                }
                return
            }

            let words = shown.split(whereSeparator: { $0.isWhitespace }).count
            let hold = min(max(Self.minHold, Double(words) / 3.0), Self.maxHold)
            if self.bubble.showSentPrompt(shown, hold: hold) {
                self.held = message
            } else {
                self.commit(message)
            }
        }
    }

    /// The only route to the outbox. Everything else builds a `Message` and
    /// hands it here — eventually, or never.
    private func commit(_ m: Message) {
        Outbox.send(kind: m.kind, text: m.text, selection: m.selection,
                    paths: m.paths, screen: m.screen, app: m.app)
    }

    /// The countdown ran out (or he clicked the bubble away) → write it. He hit
    /// Cancel → drop it, and say so, because a message that silently disappears
    /// is indistinguishable from a bubble that has stopped working.
    ///
    /// Cancelling is cheap precisely because nothing was written: the agent polls
    /// the outbox every couple of seconds, so a line already in the file may
    /// already be a tool call in flight.
    private func releaseHeld(send: Bool) {
        guard let m = held else { return }
        held = nil
        guard send else {
            Log.info("✕ cancelled — \(m.text?.count ?? 0) chars never left the bubble")
            bubble.flash("✕ cancelled", duration: 2.0)
            return
        }
        commit(m)
    }
}
