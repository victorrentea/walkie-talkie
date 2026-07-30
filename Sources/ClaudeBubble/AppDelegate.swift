import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var bubble: BubbleWindow!
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Outbox.prepare()
        bubble = BubbleWindow()

        bubble.onTogglePause = { [weak self] in
            guard let self = self else { return }
            self.paused.toggle()
            self.bubble.setPaused(self.paused)
        }
        bubble.onEndSession = { [weak self] in self?.endSession() }

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
        wispr.start()
        dictation.start()

        if !wispr.isAvailable {
            DispatchQueue.main.async { [weak self] in
                self?.bubble.flash("⚠️ Wispr Flow DB not found", duration: 12)
            }
        }
        Log.info("ready — label \(SessionLabel.value), outbox at \(Outbox.outboxURL.path)")
    }

    // MARK: - Dictation window

    /// Everything that must be true at the instant dictation starts: open the
    /// window for attaching shots, grab the selection, and photograph the screen
    /// being talked about.
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
        stateLock.unlock()

        armOrphanFlush()
        stashSelection()

        guard !alreadyOpen else { return }
        guard let path = ScreenCapture.grab(announce: true) else { return }
        stateLock.lock()
        pendingScreen = path
        stateLock.unlock()
        Log.info("context screen captured: \((path as NSString).lastPathComponent)")
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

    private func stashSelection() {
        let text = SelectionCapture.read()
        Log.info("selection front=\(SelectionCapture.frontmostAppName() ?? "?") → \(text.map { "\($0.count) chars" } ?? "nothing")")
        // An empty read never clears what an earlier probe already found: Mouse 5
        // and the CoreAudio transition both call this, and by the second one the
        // selection may have been dismissed by Wispr's own UI.
        guard let text = text, !text.isEmpty else { return }
        stateLock.lock(); pendingSelection = text; stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.bubble.setSelection(text) }
    }

    /// ⌃⌥P — one more shot for the dictation in progress.
    private func plusOneShot() {
        guard !paused else { return }
        DispatchQueue.main.async { [weak self] in self?.bubble.flashTitle("+1 📸") }

        guard let path = ScreenCapture.grab(announce: true) else {
            DispatchQueue.main.async { [weak self] in self?.bubble.flash("⚠️ screenshot failed") }
            return
        }

        stateLock.lock()
        let attaching = dictationInFlight
        if attaching { pendingShots.append(path) }
        let count = pendingShots.count
        stateLock.unlock()

        if attaching {
            armOrphanFlush()
            Log.info("📸 attached to in-flight dictation (\(count) so far)")
            DispatchQueue.main.async { [weak self] in self?.bubble.flash("📸 \(count) attached") }
            return
        }
        send(kind: "screenshot", paths: [path])
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

    /// The ✕ ends the session. Announce it through the outbox before quitting so
    /// the watching Claude learns the bubble is gone from the queue itself — it
    /// is blocked on that file, not on the process, and would otherwise sit
    /// waiting for messages that can no longer come.
    private func endSession() {
        announceEnd("✕ button")
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

        Outbox.send(kind: kind, text: text, selection: selection,
                    paths: attached, screen: screen, app: app)

        // Show what actually went out — selection included, since that is part
        // of the prompt the agent receives, not a separate thing.
        let shown = Self.promptPreview(text: text, selection: selection, shots: attached.count)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.bubble.clearSelection()
            if let shown = shown {
                self.bubble.showSentPrompt(shown)
            } else if kind == "dictation" {
                self.bubble.flash(attached.isEmpty ? "🎙️ sent" : "🎙️ sent + \(attached.count) 📸")
            }
        }
    }
}
