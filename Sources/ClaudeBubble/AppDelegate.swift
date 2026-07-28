import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var bubble: BubbleWindow!
    private let hotkeys = HotkeyTap()
    private let wispr = WisprWatcher()

    /// Screen text captured either explicitly (⌃⌥S) or at the moment dictation
    /// started (Mouse 5). Consumed by — and cleared after — the next message, so
    /// "select a label, dictate about it" sends both together exactly once.
    private var pendingSelection: String?
    private let selectionLock = NSLock()

    private var paused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        ScreenCapture.willCapture = { [weak self] in self?.bubble.hideForCapture() }
        ScreenCapture.didCapture  = { [weak self] in self?.bubble.showAfterCapture() }

        hotkeys.onScreenshot = { [weak self] in self?.captureScreenshot() }
        hotkeys.onStashSelection = { [weak self] in self?.stashSelection(explicit: true) }
        hotkeys.onDictationStarted = { [weak self] in self?.stashSelection(explicit: false) }

        wispr.onTranscript = { [weak self] text, app in
            self?.send(kind: "dictation", text: text, app: app)
        }

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
        selectionLock.lock(); pendingSelection = text; selectionLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.bubble.setSelection(text) }
    }

    private func captureScreenshot() {
        guard !paused else { return }
        guard let path = ScreenCapture.grab() else {
            DispatchQueue.main.async { [weak self] in self?.bubble.flash("⚠️ screenshot failed") }
            return
        }
        send(kind: "screenshot", path: path)
        DispatchQueue.main.async { [weak self] in
            self?.bubble.flash("📸 sent \((path as NSString).lastPathComponent)")
        }
    }

    private func send(kind: String, text: String? = nil, path: String? = nil, app: String? = nil) {
        guard !paused else {
            Log.info("paused — dropped \(kind)")
            return
        }
        selectionLock.lock()
        let selection = pendingSelection
        pendingSelection = nil
        selectionLock.unlock()

        Outbox.send(kind: kind, text: text, selection: selection, path: path, app: app)
        DispatchQueue.main.async { [weak self] in
            self?.bubble.clearSelection()
            if kind == "dictation" { self?.bubble.flash("🎙️ sent") }
            if kind == "typed" { self?.bubble.flash("⌨️ sent") }
        }
    }
}
