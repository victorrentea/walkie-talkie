import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var bubble: BubbleWindow!
    private let hotkeys = HotkeyTap()
    private let wispr = WisprWatcher()
    private let dictation = DictationMonitor()

    /// Screen text captured either explicitly (⌃⌥S) or at the moment dictation
    /// started (Mouse 5). Consumed by — and cleared after — the next message, so
    /// "select a label, dictate about it" sends both together exactly once.
    private var pendingSelection: String?

    /// Screenshots taken *while a dictation is in flight*. Victor shoots what he
    /// is talking about mid-sentence, so those images belong to that dictation,
    /// not to messages of their own — however many he takes. Drained into the
    /// dictation when its transcript lands.
    private var pendingShots: [String] = []
    private var dictationInFlight = false
    private var orphanFlush: DispatchWorkItem?

    /// Guards `pendingSelection`, `pendingShots` and `dictationInFlight`, all of
    /// which are touched from the event-tap thread, the Wispr poll queue and the
    /// screenshot worker.
    private let stateLock = NSLock()

    /// A dictation that never arrives (Mouse 5 pressed but nothing said, or
    /// Wispr discarded it) must not strand the shots. After this long with no
    /// transcript they are released as a message of their own.
    private let orphanTimeout: TimeInterval = 120

    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything grabs the event tap or starts polling Wispr.
        SingleInstance.enforce()
        Outbox.prepare()
        bubble = BubbleWindow()

        bubble.onSubmit = { [weak self] text in
            self?.send(kind: "typed", text: text)
        }
        bubble.onTogglePause = { [weak self] in
            guard let self = self else { return }
            self.paused.toggle()
            self.bubble.setPaused(self.paused)
        }
        bubble.onEndSession = { [weak self] in self?.endSession() }

        ScreenCapture.willCapture = { [weak self] in self?.bubble.hideForCapture() }
        ScreenCapture.didCapture  = { [weak self] in self?.bubble.showAfterCapture() }

        hotkeys.onScreenshot = { [weak self] in self?.captureScreenshot() }
        hotkeys.onStashSelection = { [weak self] in self?.stashSelection(explicit: true) }
        hotkeys.onDictationStarted = { [weak self] in self?.dictationStarted() }

        wispr.onTranscript = { [weak self] text, app in
            self?.send(kind: "dictation", text: text, app: app)
        }

        // CoreAudio is the authoritative "Wispr is listening" signal — it also
        // catches dictations started by Wispr's own hotkey or UI button, which
        // Mouse 5 alone would miss.
        dictation.onChange = { [weak self] recording in
            guard let self = self else { return }
            DispatchQueue.main.async { self.bubble.setListening(recording) }
            guard recording, !self.paused else { return }
            self.stateLock.lock()
            self.dictationInFlight = true
            self.stateLock.unlock()
            self.armOrphanFlush()
            self.stashSelection(explicit: false)
        }
        dictation.start()

        // Report the permission explicitly. `tapCreate` returning non-nil is not
        // proof on its own — without the Accessibility grant the tap can exist
        // and simply never receive events, which looks like "the shortcuts are
        // broken" with nothing in the log.
        let trusted = AXIsProcessTrusted()
        let tapped = hotkeys.start()
        Log.info("accessibility trusted=\(trusted) eventTap=\(tapped)")
        if !trusted || !tapped {
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("⚠️ grant Accessibility to Claude Bubble — shortcuts off", duration: 15)
            }
        }
        wispr.start()

        if !wispr.isAvailable {
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("⚠️ Wispr Flow DB not found — dictation off", duration: 12)
            }
        }
        Log.info("ready — outbox at \(Outbox.outboxURL.path)")
    }

    // MARK: - Dictation window

    /// Mouse 5 = Wispr push-to-talk. Opens the window during which screenshots
    /// attach to the coming transcript, and snapshots the current selection.
    ///
    /// Fires on both the start and the stop press, which is harmless: re-reading
    /// the selection yields the same text and re-arming the orphan timer only
    /// extends the window.
    private func dictationStarted() {
        guard !paused else { return }
        stateLock.lock()
        dictationInFlight = true
        stateLock.unlock()
        armOrphanFlush()
        stashSelection(explicit: false)
    }

    private func armOrphanFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.orphanFlush?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushOrphanedShots() }
            self.orphanFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.orphanTimeout, execute: work)
        }
    }

    /// No transcript came. Release whatever was shot so it is never silently lost.
    private func flushOrphanedShots() {
        stateLock.lock()
        let shots = pendingShots
        pendingShots = []
        dictationInFlight = false
        stateLock.unlock()
        guard !shots.isEmpty else { return }
        Log.info("no transcript within \(Int(orphanTimeout))s — releasing \(shots.count) shot(s) on their own")
        send(kind: "screenshot", paths: shots)
    }

    /// The ✕ ends the session. Announce it through the outbox before quitting so
    /// the watching Claude learns the bubble is gone from the queue itself — it
    /// is blocked on that file, not on the process, and would otherwise sit
    /// waiting for messages that can no longer come.
    private func endSession() {
        Log.info("session ended from the ✕ button")
        // Bypass `send`: this must go out even when paused, and it carries no
        // stashed selection.
        Outbox.send(kind: "session_end")
        // Give the append (serialised on Outbox's queue) time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Actions

    /// Snapshot the current on-screen selection.
    ///
    /// An empty read never clears an existing stash: pressing Mouse 5 somewhere
    /// with nothing selected must not throw away the text Victor deliberately
    /// stashed with ⌃⌥S a moment earlier.
    private func stashSelection(explicit: Bool) {
        guard !paused else { return }
        let text = SelectionCapture.read()
        Log.info("stash(explicit: \(explicit)) front=\(SelectionCapture.frontmostAppName() ?? "?") → \(text.map { "\($0.count) chars" } ?? "nothing")")
        guard let text = text, !text.isEmpty else {
            if explicit {
                DispatchQueue.main.async { [weak self] in self?.bubble.flash("(nothing selected)") }
            }
            return
        }
        stateLock.lock(); pendingSelection = text; stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.bubble.setSelection(text) }
    }

    private func captureScreenshot() {
        guard !paused else { return }
        guard let path = ScreenCapture.grab() else {
            DispatchQueue.main.async { [weak self] in self?.bubble.flash("⚠️ screenshot failed") }
            return
        }

        stateLock.lock()
        let attaching = dictationInFlight
        if attaching { pendingShots.append(path) }
        let count = pendingShots.count
        stateLock.unlock()

        if attaching {
            // Held back deliberately — it travels with the dictation.
            armOrphanFlush()
            Log.info("📸 attached to in-flight dictation (\(count) so far)")
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("📸 \(count) attached to dictation")
            }
            return
        }

        send(kind: "screenshot", paths: [path])
        DispatchQueue.main.async { [weak self] in
            self?.bubble.flash("📸 sent \((path as NSString).lastPathComponent)")
        }
    }

    private func send(kind: String, text: String? = nil, paths: [String] = [], app: String? = nil) {
        guard !paused else {
            Log.info("paused — dropped \(kind)")
            return
        }
        stateLock.lock()
        let selection = pendingSelection
        pendingSelection = nil
        // A dictation closes the window and takes the shots with it.
        var attached = paths
        if kind == "dictation" {
            attached += pendingShots
            pendingShots = []
            dictationInFlight = false
        }
        stateLock.unlock()

        if kind == "dictation" {
            DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        }

        Outbox.send(kind: kind, text: text, selection: selection, paths: attached, app: app)
        DispatchQueue.main.async { [weak self] in
            self?.bubble.clearSelection()
            switch kind {
            case "dictation":
                self?.bubble.flash(attached.isEmpty ? "🎙️ sent" : "🎙️ sent + \(attached.count) 📸")
            case "typed": self?.bubble.flash("⌨️ sent")
            default: break
            }
        }
    }
}
