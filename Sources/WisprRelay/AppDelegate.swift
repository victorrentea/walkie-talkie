import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlay: RelayWindow!
    private var status: StatusItem!
    private var snapshotSignal: DispatchSourceSignal?
    private let hotkeys = HotkeyTap()
    private let wispr = WisprWatcher()
    private let dictation = DictationMonitor()
    private let picker = ElementPicker()

    /// The terminal dictations are typed into, when Victor has pointed the relay
    /// at one. Unbound, everything below behaves exactly as it did before this
    /// existed — the outbox is still written, and the skill's watcher still
    /// reads it.
    private let terminal = TerminalBinding()

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
    /// When each deliberate shot was taken, in seconds since this dictation
    /// opened — parallel to `pendingShots`, written under the same lock.
    ///
    /// Wall-clock times would say nothing: what makes a shot findable in a
    /// three-minute dictation is *where in the sentence* it was taken, and the
    /// only clock that measures that starts when he starts talking.
    private var pendingShotOffsets: [TimeInterval] = []
    /// Elements ⌘-clicked in Chrome, waiting for the sentence they belong to.
    ///
    /// Taken **during** the dictation, like the deliberate shots — ⌘ in Chrome is
    /// the relay's only while the recording row is up (`syncBorrowedGestures`), so
    /// a pick is always something he did mid-sentence, while pointing at what he
    /// was in the middle of saying.
    ///
    /// Unlike shots they are still **not** cleared when a dictation opens, because
    /// Cancel puts them back: a cancelled prompt leaves the picks in the queue for
    /// the next attempt, and those legitimately predate the dictation they end up
    /// riding — which is why the stamps can still come out negative.
    private var pendingPicks: [ElementPick] = []

    /// A pick nobody ever spoke about is not context, it is litter — a queue left
    /// behind by a cancelled prompt he never retried. Ten minutes is longer than
    /// any gap between cancelling and saying it again, and short enough that this
    /// morning's browsing cannot ride into this afternoon's prompt.
    private let pickTTL: TimeInterval = 600

    /// When the current dictation opened, i.e. the zero of those offsets.
    private var dictationStartedAt: Date?
    private var dictationInFlight = false
    private var orphanFlush: DispatchWorkItem?

    /// The context shot is promised but `screencapture` has not come back yet.
    ///
    /// It counts as a picture from the instant the dictation opens, because that
    /// is when he took it — by starting to talk. Waiting for the file meant the
    /// row appeared saying `📸 ×0` and only became `×1` the best part of a second
    /// later, once a clipboard probe and a subprocess had both finished: a count
    /// that reads zero while a picture is being taken is simply wrong, and it is
    /// wrong in the one moment he looks at the row. It drops back to zero if the
    /// capture actually fails, which is the only case where zero is the truth.
    private var contextShotPending = false

    private let stateLock = NSLock()

    /// A dictation that never arrives (Wispr discarded it, or nothing was said)
    /// must not strand the shots. After this long with no transcript they are
    /// released as a message of their own.
    private let orphanTimeout: TimeInterval = 120

    /// Forwarding is off. **Wispr itself is untouched** — that is the entire point:
    /// pause is what Victor presses when he wants to dictate into a browser, a
    /// chat, a commit message, without the words also landing in the agent's
    /// queue. So nothing here tries to stop or intercept the transcription; the
    /// relay simply stops acting on it — no context capture, no screenshots, no
    /// outbox lines (`captureContext`, `plusOneShot`, `send` all bail).
    private var paused = false
    private var endAnnounced = false

    /// Wispr is recording. Main thread only, and kept here rather than read back
    /// off the overlay because it is half of what decides whether mouse 4 and
    /// ⌘-click belong to the relay or to the software they were borrowed from
    /// (`syncBorrowedGestures`).
    private var listening = false

    /// A message that is built, shown, and *not yet written*. It lives here for
    /// the few seconds the overlay displays it, so Cancel has something to stop.
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
        let elements: [ElementPick]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Outbox.prepare()
        overlay = RelayWindow()

        overlay.onTogglePause = { [weak self] in self?.togglePause(reason: "chip click") }
        overlay.onEndSession = { [weak self] in self?.endSession(reason: "✕ button") }

        status = StatusItem()
        status.onExit = { [weak self] in self?.endSession(reason: "menu bar Exit") }
        status.onTogglePause = { [weak self] in self?.togglePause(reason: "menu bar") }
        status.setPaused(paused)
        overlay.onPromptResolved = { [weak self] send in self?.releaseHeld(send: send) }
        overlay.onRefreshBound = { [weak self] in self?.refreshBoundTitle() }

        hotkeys.onScreenshot = { [weak self] cursor in self?.plusOneShot(cursor: cursor) }
        picker.onPick = { [weak self] pick in self?.record(pick) }
        picker.onBind = { [weak self] in self?.bindFrontmostTerminal() }
        picker.onUnbind = { [weak self] in self?.unbindTerminal() }
        picker.describeTarget = { [weak self] in self?.terminal.target.map { Self.describe($0) } }
        // Enters exactly where `wispr.onTranscript` does, so what it exercises
        // is the real path and not a shortcut through it.
        picker.onTestDictationStart = { [weak self] in
            guard let self = self else { return }
            self.captureContext()
            DispatchQueue.main.async {
                self.listening = true
                self.syncBorrowedGestures()
                self.overlay.setListening(true)
                self.publishShotCount()
            }
        }
        picker.onTestDictation = { [weak self] text in
            self?.send(kind: "dictation", text: text, app: "test")
        }
        // Mouse 5 is only a hint; DictationMonitor is the authority. Kept because
        // it fires a beat before CoreAudio reports the stream, which makes the
        // selection snapshot land closer to the moment Victor pressed.
        hotkeys.onDictationStarted = { [weak self] in self?.captureContext() }

        wispr.onTranscript = { [weak self] text, app in
            self?.send(kind: "dictation", text: text, app: app)
        }

        // `captureContext` first, and only then the overlay: it books the context
        // shot synchronously, and `setListening(true)` zeroes the count — so the
        // other order publishes `×1` into a row that is about to reset it to zero.
        dictation.onChange = { [weak self] recording in
            guard let self = self else { return }
            if recording { self.captureContext() }
            DispatchQueue.main.async {
                self.listening = recording
                self.syncBorrowedGestures()
                self.overlay.setListening(recording)
                if recording {
                    self.publishShotCount()
                    // Normally zero, but a cancelled prompt hands its picks back —
                    // and the row must open showing what the queue actually holds,
                    // not the hint for an empty one.
                    self.publishPicks()
                }
            }
        }

        let trusted = AXIsProcessTrusted()
        let tapped = hotkeys.start()
        Log.info("accessibility trusted=\(trusted) eventTap=\(tapped)")
        if !trusted || !tapped {
            DispatchQueue.main.async { [weak self] in
                self?.overlay.flash("⚠️ grant Accessibility to Wispr Relay", duration: 15)
            }
        }
        startListeningForSnapshots()

        wispr.start()
        dictation.start()
        picker.start()

        if !wispr.isAvailable {
            DispatchQueue.main.async { [weak self] in
                self?.overlay.flash("⚠️ Wispr Flow DB not found", duration: 12)
            }
        }
        Log.info("ready — label \(SessionLabel.value), outbox at \(Outbox.outboxURL.path)")

        if ProcessInfo.processInfo.environment["RELAY_DEMO"] == "1" { runDemo() }
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
            self?.overlay.snapshot(to: path)
        }
        source.resume()
        snapshotSignal = source
    }

    /// Walk the overlay through its states with canned content, for documentation
    /// screenshots. Nothing here touches the outbox: `held` stays nil, so the
    /// displayed prompt resolves into nothing.
    private func runDemo() {
        Log.info("demo mode — driving the UI with canned content")
        let selection = "public Order placeOrder(Cart cart) {"
        let opened = Date()
        let picks = [
            ElementPick(at: opened.addingTimeInterval(12), path: "main.content > button.buy-button",
                        tag: "button", text: "Add to cart"),
            ElementPick(at: opened.addingTimeInterval(21), path: "div#cart > span.price",
                        tag: "span", text: "100 €"),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.overlay.setSelection(selection)
            self?.overlay.setListening(true)
        }
        // Empty first, so the hint gets its moment — that is the state he is in
        // for the first seconds of every dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.overlay.setPicks(count: 1, newest: picks[0].short)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
            self?.overlay.setPicks(count: 2, newest: picks[1].short)
        }
        // The automatic context shot, then one taken with F3 — the two ways the
        // count moves in a real dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.overlay.setShotCount(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.overlay.setShotCount(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.overlay.setListening(false)
            self?.overlay.setPicks(count: 0, newest: nil)
            // Built by the real formatter, so a documentation shot cannot drift
            // from what the panel actually renders.
            let body = Self.promptPreview(text: "extract the tax calculation out of this method",
                                          selection: selection, shotOffsets: [0, 38],
                                          picks: picks, since: opened) ?? ""
            self?.overlay.showSentPrompt(body, hold: 25)
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

        // Where he was pointing when he started talking. Taken here and carried
        // down: by the time the capture actually runs, a clipboard probe and a
        // subprocess later, the pointer has moved on.
        let cursor = NSEvent.mouseLocation

        stateLock.lock()
        let alreadyOpen = dictationInFlight
        dictationInFlight = true
        // A new dictation is a new subject. Clear the old one before probing, so
        // a selection stranded by a dictation that never produced a transcript
        // cannot ride along with the next thing he says.
        if !alreadyOpen {
            pendingSelection = nil
            contextShotPending = true
            // The zero of every offset in this dictation. Set here rather than on
            // the Wispr transition because this is the moment the context shot is
            // booked, and that shot has to come out at 0:00 exactly.
            dictationStartedAt = Date()
            pendingShotOffsets = []
        }
        stateLock.unlock()

        // Say `📸 ×1` now, not when the subprocess returns.
        publishShotCount()

        // The receipt comes FIRST — before the AX probe, before screencapture.
        // Those take the best part of a second between them, and a flash that
        // lands after the work is a flash that no longer means "now": it was
        // firing long after the frame it confirms had already been taken.
        if !alreadyOpen { CaptureFlash.announce(cursor: cursor) }

        armOrphanFlush()

        // Off the caller's thread on purpose. The clipboard probe sleeps up to
        // 400ms and screencapture is a subprocess we wait on; left on the event
        // tap or the main queue, that is the flash frozen mid-fade.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.stashSelection()

            guard !alreadyOpen else { return }
            // 0:00 by definition — he took this one by starting to talk.
            let path = ScreenCapture.grab(cursor: cursor, offset: 0)
            self.stateLock.lock()
            self.pendingScreen = path
            self.contextShotPending = false
            self.stateLock.unlock()
            // Either way: the promised picture is now a file, or it never will be
            // and the count has to come back down to the truth.
            self.publishShotCount()
            guard let path = path else { return }
            Log.info("context screen captured: \((path as NSString).lastPathComponent)")
        }
    }

    /// Keep the overlay's `📸 ×N` honest. N is what this dictation would carry if it
    /// were sent right now: the automatic context screen counts as the first
    /// picture, because that is what it is — he took it by starting to talk.
    private func publishShotCount() {
        stateLock.lock()
        let context = (pendingScreen != nil || contextShotPending) ? 1 : 0
        let count = context + pendingShots.count
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.overlay.setShotCount(count) }
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
        pendingShotOffsets = []
        dictationStartedAt = nil
        pendingScreen = nil
        pendingSelection = nil
        dictationInFlight = false
        contextShotPending = false
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in self?.overlay.clearSelection() }
        guard !shots.isEmpty else { return }
        Log.info("no transcript within \(Int(orphanTimeout))s — releasing \(shots.count) shot(s) on their own")
        send(kind: "screenshot", paths: shots)
    }

    // MARK: - Actions

    /// The single switch behind both routes into pause — a click on the chip and
    /// the menu bar item — so the two can never disagree about the state, and so
    /// every display of it is updated in one place.
    ///
    /// Main thread only, which is where both callers already are: `paused` is read
    /// without the lock from the capture paths.
    private func togglePause(reason: String) {
        paused.toggle()
        overlay.setPaused(paused)
        status.setPaused(paused)
        syncBorrowedGestures()
        Log.info(paused ? "paused via \(reason) — dictation stays in Wispr, nothing is relayed"
                        : "resumed via \(reason)")
    }

    /// The two gestures the relay **borrows from other software**, handed over and
    /// handed back together.
    ///
    /// Mouse 4 is Victor's Return key (LinearMouse types one with it) and ⌘-click
    /// is how a link opens in a new tab; the relay takes both **only while there is
    /// a dictation for them to add to**. Outside that window — at rest, and the
    /// whole time forwarding is paused — they must go back to doing what every
    /// other app expects, so this is called from both edges that can change the
    /// answer: Wispr starting or stopping, and pause being toggled.
    ///
    /// One switch for both, so the recording row can never be on screen advertising
    /// a gesture that is no longer live, or off while one still is. Main thread only.
    private func syncBorrowedGestures() {
        let live = listening && !paused
        hotkeys.dictating = live
        picker.dictating = live
    }

    // MARK: - The bound terminal

    /// ⌘⌃D, arriving over loopback from Victor Addons: point the relay at the
    /// terminal in front and type every later dictation straight into it.
    ///
    /// **Runs on the listener queue** — `TerminalBinding.bind` spends a couple
    /// of `osascript` and `ps` subprocesses working out what it is looking at,
    /// and the main thread is drawing an overlay that follows the cursor at
    /// 60 Hz. Only the one main-thread question — which app is in front — is
    /// asked there, and it is asked first, before any of that work has had the
    /// chance to move the focus it is about to read.
    private func bindFrontmostTerminal() -> [String: Any]? {
        var front: NSRunningApplication?
        DispatchQueue.main.sync { front = NSWorkspace.shared.frontmostApplication }
        guard let front = front, let bound = terminal.bind(app: front) else {
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("⚠️ nothing bindable in front", duration: 3) }
            return nil
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlay.setBound(label: bound.label, title: bound.title)
            // The rectangle flies from the window that was captured to the
            // cursor, which is where the chip lives — the one thing that
            // connects the terminal he pressed at to the label that appears next
            // to his hand.
            if let frame = bound.sourceFrame { BindFlight.fly(from: frame) }
            // The flash names the **address**, which the chip then drops: this is
            // the one moment the answer to "did it grab the right tab?" is worth
            // a panel, and `ttys004` is what settles it. Afterwards the chip's
            // job is to say which session, not which device file.
            //
            // It is also where the shell guard's absence is reported, now that
            // the chip no longer distinguishes ⌨️ from 🎯: binding is the moment
            // that fact can still change what Victor does about it.
            let unguarded = bound.isGuarded ? "" : " — no shell guard"
            self.overlay.flash("📍 \(bound.label) · \(bound.address)\(unguarded)", duration: 3)
        }
        return Self.describe(bound)
    }

    private func unbindTerminal() {
        terminal.unbind()
        DispatchQueue.main.async { [weak self] in
            self?.overlay.setBound(label: nil)
            self?.overlay.flash("📍 unbound — back to the outbox", duration: 3)
        }
    }

    /// The bound terminal has been renamed by whatever is running in it. Called
    /// off the overlay's 10s tick — and doing the work on a background queue,
    /// because reading the title is an `osascript` round trip and the caller is
    /// the main thread in the middle of a timer.
    private func refreshBoundTitle() {
        guard terminal.target != nil else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let updated = self.terminal.refreshTitle() else { return }
            DispatchQueue.main.async {
                self.overlay.setBound(label: updated.label, title: updated.title)
            }
        }
    }

    private static func describe(_ target: TerminalBinding.Target) -> [String: Any] {
        var obj: [String: Any] = ["label": target.label, "address": target.address,
                                  "guarded": target.isGuarded]
        if let title = target.title { obj["title"] = title }
        return obj
    }

    /// Type a message into the bound terminal, if there is one.
    ///
    /// Off the main thread for the same reason binding is: this is subprocesses
    /// all the way down. It is fire-and-forget — the outbox line has already
    /// been written by the time this runs, so a failure here costs the delivery
    /// and nothing else, and the flash is how Victor learns which.
    private func deliverToTerminal(_ m: Message) {
        guard terminal.target != nil else { return }
        let line = Self.terminalLine(m)
        guard !line.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = self.terminal.deliver(line)
            DispatchQueue.main.async { self.report(outcome) }
        }
    }

    /// **Silent on success.** A dictation that landed announces itself in the
    /// terminal it landed in, which is a whole window of evidence; a flash
    /// saying the same thing would be a panel thrown across Victor's work to
    /// repeat what the target already shows. Every other outcome is a message
    /// that goes nowhere unless this says so.
    private func report(_ outcome: TerminalBinding.Outcome) {
        switch outcome {
        case .delivered:
            Log.info("⌨️ delivered to the bound terminal")
        case .noTarget:
            break
        case .targetGone(let what):
            Log.error("⌨️ \(what) — unbound")
            overlay.setBound(label: nil)
            overlay.flash("📍 \(what) — unbound", duration: 6)
        case .wouldRunAsShell(let shell):
            Log.error("⛔️ \(shell) is at the prompt — refused, nothing sent")
            // The one refusal in the whole app, and it is worth six seconds of
            // panel: what was stopped is a sentence about to be run as a
            // command. The binding is deliberately *kept* — he pressed Escape
            // or the agent exited, and starting it again is all this needs.
            overlay.flash("⛔️ \(shell) is at the prompt — not sent", duration: 6)
        case .failed(let why):
            Log.error("⌨️ delivery failed: \(why)")
            overlay.flash("⚠️ \(why)", duration: 5)
        }
    }

    /// One line, carrying everything the outbox JSON carries.
    ///
    /// **One line because the delivery ends with a Return**, so an embedded
    /// newline is not a paragraph break — it is an early submit that sends half
    /// the sentence and leaves the rest to arrive as a prompt of its own.
    ///
    /// The shots travel as **paths, not as a `📸 ×2` count**: the panel's
    /// preview is written for Victor, who took the pictures and needs only to
    /// be told they landed, while this is written for an agent, which can do
    /// nothing with a number and everything with something to `Read`. That is
    /// the same split the outbox already makes, said in one line instead of in
    /// keys — and it is what replaces the skill, which is no longer there to
    /// explain what a field called `screen` is for.
    private static func terminalLine(_ m: Message) -> String {
        var parts: [String] = []
        if let text = m.text, !text.isEmpty { parts.append(text) }
        if let selection = m.selection, !selection.isEmpty {
            parts.append("[selected: \(clampForTerminal(selection))]")
        }
        // `look at` and `context` stay separate, exactly as `paths` and `screen`
        // do: one is what he deliberately photographed and wants opened, the
        // other is the frame that happened to be on screen when he started
        // talking. Collapsing them would have every dictation drag a megabyte of
        // desktop into a context window nobody asked to spend.
        if !m.paths.isEmpty { parts.append("[look at: \(m.paths.joined(separator: " "))]") }
        if let screen = m.screen { parts.append("[context: \(screen)]") }
        if !m.elements.isEmpty {
            let named = m.elements.map { pick -> String in
                guard let text = pick.text, !text.isEmpty else { return pick.path }
                return "\(pick.path) (\(clampForTerminal(text, 60)))"
            }
            parts.append("[pointed at: \(named.joined(separator: " · "))]")
        }
        return parts.joined(separator: " ")
    }

    /// The full text is in the outbox either way. What rides into the terminal
    /// is a prompt somebody has to be able to read back, and a selection can be
    /// an entire file.
    private static func clampForTerminal(_ s: String, _ limit: Int = 400) -> String {
        let flat = s.components(separatedBy: .newlines).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

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
        DispatchQueue.main.async { [weak self] in self?.overlay.setSelection(text) }
    }

    /// F3, or mouse 4 while dictating — one more shot for the dictation in
    /// progress, with the cursor recorded so the agent can see what he was
    /// pointing at when he pressed.
    private func plusOneShot(cursor: NSPoint) {
        guard !paused else { return }
        // Sampled at the gesture, like the cursor and for the same reason: by the
        // time `screencapture` returns, a subprocess later, the moment he pressed
        // at is a second in the past — and a second is a whole sentence.
        let takenAt = Date()
        // Flash first, capture second — same reason as in `captureContext`: the
        // confirmation should land on the keypress, not on the subprocess.
        CaptureFlash.announce(cursor: cursor)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Where in the sentence this is, read **before** the capture: the
            // name is built from it, and a dictation that ends while
            // `screencapture` runs would otherwise turn a 1:52 into a timestamp.
            self.stateLock.lock()
            let openNow = self.dictationInFlight
            let startedAt = self.dictationStartedAt
            self.stateLock.unlock()
            let offset = openNow ? takenAt.timeIntervalSince(startedAt ?? takenAt) : nil

            guard let path = ScreenCapture.grab(cursor: cursor, offset: offset) else {
                DispatchQueue.main.async { self.overlay.flash("⚠️ screenshot failed") }
                return
            }

            self.stateLock.lock()
            let attaching = self.dictationInFlight
            if attaching {
                self.pendingShots.append(path)
                self.pendingShotOffsets.append(
                    takenAt.timeIntervalSince(self.dictationStartedAt ?? takenAt))
            }
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

    // MARK: - Picked elements

    /// A ⌘-click landed in Chrome. Off the main thread — this arrives on the
    /// listener's queue.
    ///
    /// Only reachable while dictating: the endpoint refuses everything else
    /// (`ElementPicker.dictating`), so by the time one gets here it is a thing he
    /// pointed at in the middle of a sentence. The `paused` check is the same
    /// belt-and-braces the other capture paths carry — pause is flipped on the
    /// main thread and this runs on another.
    ///
    /// There is no flash and no panel, deliberately: the outline in the page has
    /// already turned green under his cursor, at the pixel he clicked, before this
    /// code ran. A second receipt across the screen would be the same news, later
    /// and further away. What this adds is the running total, in the chip.
    private func record(_ pick: ElementPick) {
        guard !paused else { return }
        stateLock.lock()
        pendingPicks.append(pick)
        pruneStalePicks()
        let count = pendingPicks.count
        let last = pendingPicks.last?.short ?? ""
        stateLock.unlock()
        Log.info("🎯 \(count) element(s) waiting on a sentence — newest \(last)")
        publishPicks()
    }

    /// Caller holds `stateLock`.
    private func pruneStalePicks() {
        let cutoff = Date().addingTimeInterval(-pickTTL)
        pendingPicks.removeAll { $0.at < cutoff }
    }

    /// Keep the overlay's `🎯 ×N` honest, and name the newest one — the count says
    /// the click landed, the name says *what* landed, which is the half he can
    /// actually check against what he meant to point at.
    private func publishPicks() {
        stateLock.lock()
        pruneStalePicks()
        let count = pendingPicks.count
        let newest = pendingPicks.last?.short
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.overlay.setPicks(count: count, newest: newest) }
    }

    /// The elements line(s): one per thing he pointed at, in the order he pointed
    /// at them, each with when it happened relative to the dictation.
    ///
    /// A selector is not a stamp on a list, it *is* the content — so unlike the
    /// pictures, these get a line each rather than a row of times. He has to be
    /// able to read "that is the buy button, not the price next to it" in the
    /// seconds Cancel is still available, and a comma-separated run of CSS paths
    /// is not readable at that speed.
    ///
    /// **Negative stamps are the point, not an edge case.** Pointing usually comes
    /// *before* the sentence — he finds the thing, then says what to do with it —
    /// so `−0:08` reads exactly as it should: you pointed at this eight seconds
    /// before you started talking.
    private static func pickLines(_ picks: [ElementPick], since: Date?) -> [String] {
        let shown = picks.prefix(maxPickLines)
        var lines = shown.map { pick -> String in
            guard let since = since else { return "🎯 \(pick.short)" }
            let seconds = Int(pick.at.timeIntervalSince(since).rounded())
            let sign = seconds < 0 ? "−" : ""
            let abs = Swift.abs(seconds)
            return String(format: "🎯 %@%d:%02d %@", sign, abs / 60, abs % 60, pick.short)
        }
        if picks.count > shown.count { lines.append("🎯 +\(picks.count - shown.count) more") }
        return lines
    }

    /// Enough to check the ones he is likely to still be holding in his head. Past
    /// that the panel is a list he has to read instead of a prompt he has to
    /// approve, and the countdown is running.
    private static let maxPickLines = 3

    /// The pictures line: how many are riding along, and **when each was taken**,
    /// as m:ss from the moment he started talking.
    ///
    /// The count alone answers "did my shots land"; it does not answer the
    /// question he actually has a few seconds later, which is *which* moments he
    /// caught. In a three-minute dictation `📸 ×4` is four indistinguishable
    /// files, while `0:00 · 0:38 · 1:52 · 2:41` is a table of contents — and this
    /// panel, with Cancel still running, is the last instant at which noticing a
    /// missing one is free.
    ///
    /// Relative to the dictation, never wall-clock: the shots exist only as parts
    /// of this message, and 15:22:07 says nothing about where in it he was.
    ///
    /// **The context shot's `0:00` is not printed.** It is the one stamp that
    /// carries no information — the automatic capture is always at zero, by
    /// definition — so it only pushed the stamps that do mean something one
    /// column to the right. The count still includes it; what is listed are the
    /// moments he chose.
    private static func shotLine(_ offsets: [TimeInterval]) -> String? {
        guard !offsets.isEmpty else { return nil }
        let stamps = offsets.filter { $0 > 0 }.map { offset -> String in
            let s = max(0, Int(offset.rounded()))
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        guard !stamps.isEmpty else { return "📸 ×\(offsets.count)" }
        return "📸 ×\(offsets.count) " + stamps.joined(separator: " · ")
    }

    /// What to render in the overlay as "this is what the agent got". Returns nil
    /// for messages with no words in them (a bare screenshot), which fall back
    /// to the one-line flash.
    private static func promptPreview(text: String?, selection: String?,
                                      shotOffsets: [TimeInterval],
                                      picks: [ElementPick], since: Date?) -> String? {
        var parts: [String] = []
        if let selection = selection, !selection.isEmpty { parts.append("↪ " + selection) }
        if let text = text, !text.isEmpty { parts.append(text) }
        guard !parts.isEmpty else { return nil }
        if let shots = shotLine(shotOffsets) { parts.append(shots) }
        parts.append(contentsOf: pickLines(picks, since: since))
        return parts.joined(separator: "\n")
    }

    /// The ✕ and the menu bar's Exit both end the session. Announce it through the
    /// outbox before quitting so the watching agent learns the overlay is gone
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
    /// queue, and "user closed the relay" reads as the instruction it is —
    /// stop watching — where a bare `session_end` has to be interpreted.
    private func announceEnd(_ reason: String) {
        guard !endAnnounced else { return }
        endAnnounced = true
        // Anything still counting down goes out ahead of the goodbye. Quitting is
        // not cancelling — Cancel is a button he presses on purpose — and the
        // outbox writes serially, so it lands in the right order.
        overlay?.flushHeldPrompt()
        Log.info("session ended via \(reason)")
        Outbox.send(kind: "session_end", text: "user closed the relay")
    }

    /// Catches the quit routes the ✕ does not: ⌘Q, and the Apple Event a newly
    /// launched instance sends to its predecessor.
    ///
    /// Which is exactly why it consults the replacement marker first. Restarting
    /// the relay kills the old one, and reporting *that* as "user closed the
    /// overlay" would tell the agent to stop watching at the very moment Victor
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
        // The context shot is the first picture and it was taken at 0:00 — he took
        // it by starting to talk. Counting from `pendingScreen` rather than from
        // `attached` is what keeps this total agreeing with the `📸 ×N` he watched
        // go up while he was speaking, which does include it.
        var offsets: [TimeInterval] = []
        var picks: [ElementPick] = []
        var since: Date?
        if kind == "dictation" {
            attached += pendingShots
            screen = pendingScreen
            offsets = (pendingScreen != nil ? [0] : []) + pendingShotOffsets
            // Everything he pointed at goes with the words, whether he pointed
            // before or during — the queue exists precisely because those two
            // orders are equally normal. `since` is what turns the absolute
            // stamps into "where in this sentence", negatives and all.
            pruneStalePicks()
            picks = pendingPicks
            since = dictationStartedAt
            pendingPicks = []
            pendingShots = []
            pendingShotOffsets = []
            dictationStartedAt = nil
            pendingScreen = nil
            dictationInFlight = false
            contextShotPending = false
        }
        stateLock.unlock()

        if kind == "dictation" { publishPicks() }

        if kind == "dictation" {
            DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        }

        let message = Message(kind: kind, text: text, selection: selection,
                              paths: attached, screen: screen, app: app, elements: picks)

        // Show what is about to go out — selection included, since that is part
        // of the prompt the agent receives, not a separate thing.
        let shown = Self.promptPreview(text: text, selection: selection, shotOffsets: offsets,
                                       picks: picks, since: since)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlay.clearSelection()

            // Nothing to read is nothing to cancel: a bare screenshot goes
            // straight out, and so does the goodbye.
            guard let shown = shown else {
                self.commit(message)
                if kind == "dictation" {
                    // `offsets`, not `attached`: same total the recording row was
                    // showing a second ago, context shot included.
                    self.overlay.flash(offsets.isEmpty ? "🎙️ sent" : "🎙️ sent + \(offsets.count) 📸")
                }
                return
            }

            let words = shown.split(whereSeparator: { $0.isWhitespace }).count
            let hold = min(max(Self.minHold, Double(words) / 3.0), Self.maxHold)
            if self.overlay.showSentPrompt(shown, hold: hold) {
                self.held = message
            } else {
                self.commit(message)
            }
        }
    }

    /// The only route to the outbox — and therefore the only place the bound
    /// terminal has to be taught about. Everything else builds a `Message` and
    /// hands it here, eventually or never; Cancel is still the thing that means
    /// neither happens.
    ///
    /// **The outbox is written whether or not a terminal is bound**, and that is
    /// deliberate. It is the log of what Victor said — the record that outlives
    /// the session, the thing to read when a delivery went somewhere surprising
    /// — and a binding is a second destination, not a replacement for the first.
    /// It also means an agent watching the queue the old way keeps working while
    /// the same words are being typed at another one.
    ///
    /// `session_end` is the exception: it is addressed to a watcher, and there
    /// is nothing for a terminal to do with "the user closed the relay".
    private func commit(_ m: Message) {
        Outbox.send(kind: m.kind, text: m.text, selection: m.selection,
                    paths: m.paths, screen: m.screen, app: m.app,
                    elements: m.elements.map { $0.json })
        guard m.kind != "session_end" else { return }
        deliverToTerminal(m)
    }

    /// The countdown ran out (or he clicked the overlay away) → write it. He hit
    /// Cancel → drop it, and say so, because a message that silently disappears
    /// is indistinguishable from an overlay that has stopped working.
    ///
    /// Cancelling is cheap precisely because nothing was written: the agent polls
    /// the outbox every couple of seconds, so a line already in the file may
    /// already be a tool call in flight.
    private func releaseHeld(send: Bool) {
        guard let m = held else { return }
        held = nil
        guard send else {
            Log.info("✕ cancelled — \(m.text?.count ?? 0) chars never left the overlay")
            // The picked elements go back in the queue. Cancel means the sentence
            // was wrong, not that he pointed at the wrong things — and re-taking a
            // pick means finding the element in the page again, which is the
            // expensive half of the gesture. (Shots are not restored: he can take
            // another one blind, and the screen has moved on anyway.)
            if !m.elements.isEmpty {
                stateLock.lock()
                pendingPicks = m.elements + pendingPicks
                pruneStalePicks()
                stateLock.unlock()
                publishPicks()
            }
            overlay.flash("✕ cancelled", duration: 2.0)
            return
        }
        commit(m)
    }
}
