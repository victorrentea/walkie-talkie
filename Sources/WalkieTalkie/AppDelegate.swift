import AppKit
import ServiceManagement
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlay: RelayWindow!
    private var status: StatusItem!
    private var snapshotSignal: DispatchSourceSignal?
    private let hotkeys = HotkeyTap()
    private let picker = ElementPicker()

    /// Pauses whatever Chrome is playing for the length of a dictation, and
    /// resumes exactly that afterwards. Driven from `syncBorrowedGestures`, the
    /// one place that already knows when the window opens and closes.
    private let music = MusicBridge()

    /// Keeps every dictation's **recording** beside the model's reading of it,
    /// so a recogniser can be measured on Victor's own voice later. It changes
    /// nothing about what the agent receives — see `VoiceCorpus`.
    private let corpus = VoiceCorpus()

    /// The recogniser. Idle and costing nothing until a dictation is coming —
    /// the weights are 1.5 GB resident, and the ordinary case is a relay sitting
    /// in the menu bar all day with nothing bound.
    private let whisper = LocalWhisper()

    /// The microphone. The relay records for itself: it opens the input, hands
    /// the WAV to the model, and nothing outside this app hears the sentence.
    private let mic = MicRecorder()

    /// A recording is open. Main thread only — it is written and read from the
    /// wheel toggle and the menu, both of which hop to main.
    private var localRecording = false

    /// What was in front when the recording started, for the message's `app`
    /// field. Read at the press, not at the end: by the time the model answers he
    /// has usually switched away.
    private var localRecordingApp: String?

    /// The terminal dictations are typed into, when Victor has pointed the relay
    /// at one. Unbound, everything below behaves exactly as it did before this
    /// existed — the outbox is still written, and the skill's watcher still
    /// reads it.
    private let terminal = TerminalBinding()

    /// Text that happened to be selected when the dictation opened. There is
    /// no shortcut for this any more and none is needed: if something was
    /// selected, it is simply picked up — Victor dictates *about* what he has
    /// highlighted, so the selection is the subject of the sentence.
    private var pendingSelection: String?

    /// Text he highlighted **later in the same dictation**, each stamped with
    /// where in the sentence he was when he took the shot that carried it.
    ///
    /// `pendingSelection` above is still frozen at the first non-empty read and
    /// still means what it always meant: the subject he started talking about.
    /// This is the other thing that happens in a long dictation — he keeps
    /// talking, highlights a second line, presses the shutter, highlights a
    /// third. Overwriting the frozen one with each of those would lose the
    /// subject; ignoring them loses everything he pointed at after the first
    /// sentence. So they accumulate beside it, in order, with their offsets.
    ///
    /// Only the shutter fills this (`plusOneShot`), which is what keeps it
    /// honest: a selection lands here because he deliberately took a picture
    /// while it was highlighted, not because the caret happened to be somewhere
    /// when a timer fired.
    private var pendingExtraSelections: [(at: TimeInterval, text: String)] = []

    /// The screen Victor was looking at when he started talking, captured
    /// automatically. Offered as context ("look if you need to"), unlike the
    /// deliberate ⌃⌥P shots which are things he wants seen.
    private var pendingScreen: String?

    /// Deliberate ⌃⌥P shots taken while a dictation is in flight.
    private var pendingShots: [String] = []

    /// What was in front when each picture was taken — `Chrome — Gmail – Inbox`,
    /// `IntelliJ IDEA — OwnerController.java` — keyed by the path of the frame it
    /// belongs to.
    ///
    /// **A dictionary and not a fourth parallel array.** `pendingShots` and
    /// `pendingShotOffsets` already run alongside each other under one lock, and
    /// the automatic context screen lives in a field of its own rather than in
    /// either of them; a third list would have to be kept in step with two
    /// different things at once. Keyed by path, the source travels with the
    /// picture no matter which of those two routes the picture took.
    private var shotSources: [String: String] = [:]
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

    /// A dictation that never arrives (nothing was said, or the model returned
    /// nothing) must not strand the shots. After this long with no transcript
    /// they are released as a message of their own.
    private let orphanTimeout: TimeInterval = 120

    /// Forwarding is off. Pause is what Victor presses when he wants the mouse
    /// and the keyboard back — the wheel goes to the app underneath, mouse 4
    /// types Return again, and no dictation can be started. The relay stops
    /// acting on everything: no context capture, no screenshots, no outbox lines
    /// (`captureContext`, `plusOneShot`, `send` all bail).
    private var paused = false
    private var endAnnounced = false

    /// **There is a destination, so a dictation is the relay's business.**
    ///
    /// Unbound the app does nothing at all: no dictation can be started, mouse 4
    /// and mouse 5 and ⌘⇧-click stay with the software they belong to, no picture
    /// is taken, and no line is written. It bails out of exactly the places
    /// `paused` does — `captureContext`, `plusOneShot`, `send`,
    /// `syncBorrowedGestures` — plus `syncLocalCapture`, which is where the
    /// microphone's claim on the wheel lives.
    ///
    /// Why this became necessary: the relay was started per session and lived
    /// only as long as Victor was dictating at an agent, so "running" and "aimed
    /// at something" were the same fact. Since 2026-08-26 it is a login item and
    /// sits there all day — and every one of those behaviours was being applied
    /// to every sentence he spoke into a browser, a chat or a commit message,
    /// with nowhere for the words to go. That is what pause exists to stop, and
    /// he was having to press it against an app that had no destination anyway.
    ///
    /// Read off `TerminalBinding`, which locks, so this is safe from any thread.
    private var isBound: Bool { terminal.target != nil }

    /// **The dictation being spoken right now is going to open its own
    /// terminal** — ⇧ + the wheel. Set at the press that starts it and carried
    /// on the `Message`, so a prompt held on screen for five seconds cannot be
    /// overtaken by whatever the flag has become by the time it commits.
    ///
    /// It is the second half of *Unbound is inert*: every gate there asks "is
    /// there anywhere for these words to go", and until now a binding was the
    /// only way to answer yes. A spawn is the other way — the destination does
    /// not exist yet, but it is going to, which is the same answer for every
    /// purpose those gates have.
    private var spawnPending = false

    /// Somewhere for this dictation to go: a terminal already bound, or one it
    /// is about to open for itself.
    private var hasDestination: Bool { isBound || spawnPending }

    /// A dictation is running. Main thread only, and kept here rather than read
    /// back off the overlay because it is half of what decides whether mouse 4 and
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
        /// `var`, because the panel can hand back a corrected transcript: a local
        /// Whisper line is occasionally fluent nonsense, and the hold exists so
        /// that is catchable before it reaches an agent.
        var text: String?
        let selection: String?
        /// Highlighted later in the same dictation, each with its offset. Empty
        /// in the ordinary case, which is why `selection` above stays exactly
        /// what it was rather than becoming element zero of a list.
        var extraSelections: [(at: TimeInterval, text: String)] = []
        let paths: [String]
        let screen: String?
        /// Path → what was in front when that frame was taken. Covers both
        /// `paths` and `screen`, which is the reason it is keyed rather than
        /// ordered.
        var sources: [String: String] = [:]
        let app: String?
        let elements: [ElementPick]
        /// This one opens its own terminal instead of being typed into a bound
        /// one. Carried here rather than read off `spawnPending` at delivery,
        /// because the two are seconds apart — the panel holds every prompt — and
        /// the next dictation may have started by then.
        var spawn: Bool = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Self.startAtLogin()
        Outbox.prepare()
        overlay = RelayWindow()

        overlay.onTogglePause = { [weak self] in self?.togglePause(reason: "chip click") }
        overlay.onEndSession = { [weak self] in self?.endSession(reason: "✕ button") }

        status = StatusItem()
        status.onExit = { [weak self] in self?.endSession(reason: "menu bar Quit") }
        status.onTogglePause = { [weak self] in self?.togglePause(reason: "menu bar") }
        // The same call `POST /unbind` makes: the words go back to the outbox and
        // the relay keeps running, which is the difference between this and ⌘⌃D
        // on the bound target.
        status.onDisconnect = { [weak self] in self?.unbindTerminal() }
        status.whisperFootprint = { [weak self] in self?.whisper.footprintBytes }
        // The menu asks rather than being told, like the footprint above: the flag
        // flips on every dictation, and the only moment its answer has to be right
        // is the moment the row is on screen.
        status.isRecording = { [weak self] in self?.localRecording ?? false }
        // Deliberately the *same* call mouse 5 makes rather than a quieter variant:
        // a recording ended from the menu is still a dictation, and it is
        // transcribed and sent exactly as if the button had ended it.
        status.onStopRecording = { [weak self] in self?.stopLocalRecording() }
        status.onCancelDictation = { [weak self] in self?.cancelLocalRecording() }
        status.onStartDictation = { [weak self] in self?.startLocalRecording() }
        // **On main, like the toggle two lines down.** It was not, and the
        // asymmetry is the whole bug: the tap dispatches globally, so cancelling
        // reached `RelayWindow.layoutContent` → `NSWindow.setFrame` on
        // `com.apple.root.default-qos` and AppKit trapped. Crash log
        // 2026-08-29 11:04:40, EXC_BREAKPOINT, one frame under
        // `cancelLocalRecording`.
        hotkeys.onLocalCancel = { [weak self] in
            DispatchQueue.main.async { self?.cancelLocalRecording() }
        }
        hotkeys.onWheelBind = { [weak self] in self?.bindFrontmostTerminal() != nil }
        // The menu's copy of ⌘ + the wheel. The same call, so the window it opens
        // and the destination it arms cannot drift from the gesture's.
        status.onNewSession = { [weak self] in
            DispatchQueue.main.async { self?.startLocalRecording(spawn: true) }
        }
        // The menu's copy of F3. **After a beat**, because the menu is dismissed
        // by AppKit and the screen redrawn a frame or two later — a capture fired
        // on the click would photograph the menu that ordered it.
        status.onShot = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.plusOneShot(cursor: NSEvent.mouseLocation)
            }
        }
        status.onBind = { [weak self] in
            // Off the main thread: `bindFrontmostTerminal` asks it for the front
            // app with `main.sync`, and a menu action arrives already on main.
            DispatchQueue.global().async { [weak self] in _ = self?.bindFrontmostTerminal() }
        }
        status.frontIsBindable = { [weak self] in self?.hotkeys.frontIsBindable ?? false }
        startWatchingFrontApp()

        // **The model is not brought up at launch any more**, even when the
        // setting says Local Whisper.
        //
        // It used to be, on the argument that loading it lazily would cost ten
        // seconds mid-sentence. That argument was made when the relay was started
        // per session by ⌘⌃D and lived for as long as Victor was dictating.
        // Since 2026-08-26 it starts at **login** and sits there all day, so
        // eager loading means 2.5 GB of unified memory held from breakfast for a
        // dictation that may not come until the afternoon — on a Mac whose GPU
        // memory is also what the training demos run in.
        //
        // The ten seconds are not paid mid-sentence either: the load is kicked
        // off by the two gestures that mean a dictation is coming — ⌘⌃D binding a
        // terminal, and mouse 5 on an engine that is not up yet — and both say
        // ⏳ while it happens.
        Log.info("the model stays down until a session starts")
        status.setPaused(paused)
        syncLocalCapture()
        overlay.onPromptResolved = { [weak self] send, edited in
            self?.releaseHeld(send: send, edited: edited)
        }
        overlay.onRefreshBound = { [weak self] in self?.refreshBoundTitle() }

        hotkeys.onScreenshot = { [weak self] cursor in self?.plusOneShot(cursor: cursor) }
        hotkeys.onLocalToggle = { [weak self] in
            DispatchQueue.main.async { self?.toggleLocalRecording() }
        }
        // ⇧ + the wheel. **Ending is the same call as ever** — the destination
        // belongs to the press that opened the microphone, not to the one that
        // closes it — so the shift only means anything when nothing is running.
        hotkeys.onSpawnToggle = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.localRecording { self.stopLocalRecording() }
                else { self.startLocalRecording(spawn: true) }
            }
        }
        picker.onPick = { [weak self] pick in self?.record(pick) }
        picker.onBind = { [weak self] in self?.bindFrontmostTerminal() }
        // The same call the loopback route makes, from the key Victor actually
        // presses. Already off the main thread — the tap dispatches globally —
        // which this needs: it spends several subprocesses working out what it
        // is looking at.
        hotkeys.onBindHotkey = { [weak self] in _ = self?.bindFrontmostTerminal() }
        hotkeys.onMouse5Double = { [weak self] in
            guard let self = self else { return }
            // The first click of the pair has already opened the microphone if
            // the local engine is up. Close it: a double click is by definition
            // faster than `MicRecorder.minimumDuration`, so the recording is
            // dropped by the guard there rather than transcribed and sent.
            if self.localRecording { self.stopLocalRecording() }
            _ = self.bindFrontmostTerminal()
        }
        hotkeys.onPromptEnter = { [weak self] in self?.overlay.sendHeldPrompt() }
        hotkeys.onPromptEscape = { [weak self] in self?.overlay.cancelHeldPrompt() }
        picker.onUnbind = { [weak self] in self?.unbindTerminal() }
        picker.describeTarget = { [weak self] in self?.terminal.target.map { Self.describe($0) } }
        // Enters exactly where a real dictation does, so what it exercises is
        // the real path and not a shortcut through it.
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
        // The spawn's transcript, entering where a spoken one does — with the
        // destination armed first, exactly as the ⇧-wheel press arms it.
        picker.onTestSpawn = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spawnPending = true
                self.send(kind: "dictation", text: text, app: "test")
            }
        }
        picker.describeEngine = { [weak self] in
            ["engine": "whisper", "ready": self?.whisper.ready ?? false]
        }

        let trusted = AXIsProcessTrusted()
        let tapped = hotkeys.start()
        Log.info("accessibility trusted=\(trusted) eventTap=\(tapped)")
        if !trusted || !tapped {
            DispatchQueue.main.async { [weak self] in
                self?.overlay.flash("⚠️ grant Accessibility to Walkie Talkie", duration: 15)
            }
        }
        startListeningForSnapshots()

        picker.start()
        music.start()

        Log.info("ready — label \(SessionLabel.value), outbox at \(Outbox.outboxURL.path)")
        Log.info("voice corpus at \(VoiceCorpus.root.path)")

        if ProcessInfo.processInfo.environment["RELAY_DEMO"] == "1" { runDemo() }
    }

    /// **A wheel hold is waiting on the model**, and the microphone opens the
    /// instant it is up. See where it is set, in `startLocalRecording`.
    ///
    /// It used to be the *bind* that set this, on the reading that ⌘⌃D means "I
    /// am about to talk to this agent". It does not: binding is how Victor points
    /// the relay at a terminal on his way into a session, often several minutes
    /// before he says anything, and a bind that opened the microphone by itself
    /// was recording a room that had not been asked. Only the gesture that means
    /// "record" may arm this — the bind's remaining job is to bring the model up
    /// so the hold does not have to wait for it.
    private var recordWhenModelReady = false

    /// A note the next panel should carry under its transcript — set by the
    /// confidence gate, consumed by the `showSentPrompt` that follows it.
    private var pendingPromptWarning: String?

    /// Bring the model up, if it is not already.
    ///
    /// It takes ten seconds to load 1.5 GB of weights and can fail outright —
    /// for a missing `mlx_whisper`, most likely — so nothing may assume it is
    /// there, and a failure has to say so out loud: this is the only recogniser
    /// the relay has, and a dictation started against a model that never loaded
    /// is a sentence with nowhere to go.
    private func startWhisper() {
        guard !whisper.ready, !engineLoading else { return }

        setEngineLoading(true)
        // No duration: it ends when the model does, not when a timer says so.
        // A banner that expires after twelve seconds on a load that took
        // fourteen is worse than none — it says "ready" by disappearing.
        // **Only when there is no chip to say it.** Bound, the state sits in the
        // status row under the destination, where every other "what is happening
        // now" lives; flashing it as well would put the same hourglass twice on
        // one small panel. Unbound — the model brought up from the menu — there
        // is no row, and this is the only thing that would say anything at all.
        if !isBound {
            overlay.flash("⏳ preparing", duration: 600)
        }
        whisper.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setEngineLoading(false)
                if let error = error {
                    self.recordWhenModelReady = false
                    self.overlay.flash("⚠️ Whisper unavailable — \(error)", duration: 12)
                    Log.error("whisper failed to start: \(error)")
                    self.syncLocalCapture()
                    return
                }
                self.syncLocalCapture()
                // Asked here rather than at the first press: the grant dialog is
                // modal and a refusal takes a trip through System Settings, and
                // the moment to find that out is while the model is loading —
                // not mid-sentence with an agent waiting.
                MicRecorder.requestAccess { ok in
                    guard !ok else { return }
                    self.overlay.flash("⚠️ grant Microphone to Walkie Talkie — the relay cannot record", duration: 15)
                    Log.error("microphone access denied — local recording will not work")
                }
                // **A wheel pressed against a cold model records the moment it
                // is up.** On a cold model that press was costing him ten seconds
                // of waiting followed by a second press he had to remember to
                // make, with nothing on screen counting the seconds down — and
                // the ready-flash then said "go ahead" to a relay that was not
                // listening. Only the *dictate* press arms this: a load started
                // by a bind is Victor pointing the relay at a terminal, which is
                // a different sentence and must not open the microphone.
                if self.recordWhenModelReady {
                    self.recordWhenModelReady = false
                    // The ⏳ was a promise about this moment; it is being kept, so
                    // it comes down rather than sitting over a live dictation for
                    // whatever its timer had left.
                    self.overlay.clearFlash()
                    Log.info("model up after a press that had to wait — opening the microphone")
                    // **The gesture is kept whole, ⇧ included.** A spawn that had
                    // to wait ten seconds for the weights is still a spawn; going
                    // back through the bare path would have started a dictation
                    // with nowhere to go and then dropped it at `send`.
                    self.startLocalRecording(spawn: self.spawnPending)
                    return
                }
                // **Nothing is said.** This used to flash "local Whisper ready —
                // go ahead", which was the right answer while a bind opened the
                // microphone by itself and he was waiting for permission to talk.
                // He is not waiting any more: a hold made during the load is
                // remembered and fires above, and a load nobody held the wheel
                // into is just the model coming up in the background. So the ⏳ is
                // taken down — it promised this moment — and the chip, which goes
                // back to reading `🖱️ dictate`, is the whole message.
                self.overlay.clearFlash()
                Log.info("whisper ready")
            }
        }
    }

    // MARK: - The relay's own microphone

    /// Whether the wheel may open the microphone.
    ///
    /// **Off while nothing is bound**, and that is the whole of it: with no
    /// destination there is nowhere for a transcript to go, so a recording would
    /// be a room taped for nobody. Off while paused too — pause is what Victor
    /// presses to hand the mouse back to the app underneath.
    private func syncLocalCapture() {
        hotkeys.localCapture = isBound && !paused
    }

    /// Start recording, or finish the one that is open.
    ///
    /// A **toggle**, not a push-to-talk: the dictations that go to an agent run
    /// to a minute or more, and a mouse button held for a minute is a hand that
    /// cannot do anything else — including take the screenshots (mouse 4, F3)
    /// that the same minute is for.
    private func toggleLocalRecording() {
        if localRecording { stopLocalRecording() } else { startLocalRecording() }
    }

    /// `spawn` is ⇧ + the wheel: this dictation carries its own destination, so
    /// it is allowed through the one gate a bare one is not — having a binding.
    private func startLocalRecording(spawn: Bool = false) {
        // Set before the gate below and before anything reads `hasDestination`:
        // it *is* the answer for a spawn, and `captureContext` a few lines down
        // asks the same question about the screenshot it is deciding to take.
        spawnPending = spawn
        // Unreachable in practice for a bare wheel — it is only the relay's while
        // `syncLocalCapture` says so, and that needs a binding — but the gate is
        // repeated here for the same reason `paused` is: this is the path that
        // opens the microphone.
        guard hasDestination, !paused else { return }
        if spawn { overlay.setSpawnDestination("✨ \(Self.spawnFolderName)") }
        guard whisper.ready else {
            // Not an error, since the helper is deliberately down until something
            // says a dictation is coming — this press is one of the two things
            // that say it. It still costs him this sentence, which is why the
            // banner is worded as a wait rather than as a failure.
            Log.info("wheel clicked with the model down — bringing it up now")
            startWhisper()
            // **The gesture is kept.** Telling him to say it again was making him
            // watch for a banner and then remember to repeat a gesture he had
            // already made — the ten seconds cost him the sentence *and* the
            // gesture. The intention is unambiguous, so it is held and honoured
            // when the weights land.
            recordWhenModelReady = true
            // Nothing to flash: the wheel means he is bound, so the status row
            // under the destination is already showing `⏳ preparing`, and it
            // stays until the model is up — which is exactly when the click he
            // just made turns into a recording.
            return
        }

        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        if let why = mic.start(to: wav) {
            overlay.flash("⚠️ \(why)", duration: 6)
            Log.error("local recording did not start: \(why)")
            return
        }

        localRecording = true
        localRecordingApp = NSWorkspace.shared.frontmostApplication?.localizedName
        Log.info("🎙️ local recording started — \(wav.lastPathComponent)")

        // The context shot is booked synchronously first, because
        // `setListening(true)` zeroes the count the shot has to appear in.
        captureContext()
        listening = true
        syncBorrowedGestures()
        overlay.setListening(true)
        overlay.setListeningModel(whisper.modelName)
        publishShotCount()
        publishPicks()
    }

    /// End the open dictation and throw it away — no decode, nothing delivered.
    ///
    /// Deliberately not `stopLocalRecording` with a flag: that one's whole body
    /// after the microphone closes is about getting a transcript somewhere, and
    /// the difference here is that none of it should happen. What the two share
    /// is closing the microphone and putting the overlay back, which is the part
    /// written out again rather than shared, because a `cancel` that fell through
    /// into the send path by accident is the one bug this must not have.
    ///
    /// Everything the dictation had gathered goes with it. Shots and picks are
    /// stamped against `dictationStartedAt`, so leaving them behind would attach
    /// them to the *next* sentence, timed from a clock that no longer exists.
    private func cancelLocalRecording() {
        guard localRecording else { return }
        localRecording = false
        clearSpawn()
        localRecordingApp = nil
        let recording = mic.stop()

        listening = false
        syncBorrowedGestures()
        overlay.setListening(false)

        if let (wav, duration) = recording {
            try? FileManager.default.removeItem(at: wav)
            Log.info(String(format: "🗑️ dictation cancelled — %.1fs of audio discarded", duration))
        } else {
            Log.info("🗑️ dictation cancelled — nothing had been recorded yet")
        }

        stateLock.lock()
        pendingPicks = []
        pendingShots = []
        pendingShotOffsets = []
        pendingSelection = nil
        pendingExtraSelections = []
        shotSources = [:]
        dictationStartedAt = nil
        pendingScreen = nil
        dictationInFlight = false
        contextShotPending = false
        stateLock.unlock()

        publishShotCount()
        publishPicks()
        overlay.flash("🗑️ dictation cancelled", duration: 3)
    }

    private func stopLocalRecording() {
        localRecording = false
        let app = localRecordingApp
        localRecordingApp = nil
        let recording = mic.stop()

        listening = false
        syncBorrowedGestures()
        overlay.setListening(false)

        guard let (wav, duration) = recording else {
            Log.info("local recording discarded — under \(MicRecorder.minimumDuration)s")
            clearSpawn()
            return
        }
        Log.info(String(format: "🎙️ local recording stopped — %.1fs", duration))
        overlay.setTranscribing(true)

        whisper.transcribe(wav: wav.path) { [weak self] result in
            guard let self = self else { return }
            guard let r = result, !r.text.isEmpty else {
                DispatchQueue.main.async {
                    self.overlay.setTranscribing(false)
                    self.clearSpawn()
                    self.overlay.flash("⚠️ the model returned nothing — that dictation is lost", duration: 8)
                }
                Log.error("local recording produced no transcript")
                try? FileManager.default.removeItem(at: wav)
                return
            }
            Log.info(String(format: "local whisper: %@ (%.2f) — %d chars",
                            r.language ?? "?", r.avgLogprob, r.text.count))
            // **Sent even below the confidence floor.** There is one reading of
            // this audio and no second opinion to fall back on, so the
            // alternative to a shaky transcript is silence — and silence is the
            // one outcome Victor cannot notice and correct. The banner says so,
            // and the panel holds it long enough for him to fix it.
            // **The ⏳ comes down here, on both paths.** `transcribing…` is a
            // promise about this exact moment, and it is flashed with a 30s
            // duration precisely because it is meant to be taken down by whatever
            // arrives rather than to expire. It used to be *replaced* by the
            // low-confidence flash; now that the warning goes to the panel
            // instead, nothing was left to take it down, and it sat at the foot
            // of the pre-send panel — a stale "transcribing…" under the finished
            // transcript.
            DispatchQueue.main.async { self.overlay.setTranscribing(false) }
            // Handed to the panel rather than flashed: a flash lands in the hint
            // row, which is the last row of the panel, and this is a note about
            // the transcript — it belongs under the words it qualifies.
            self.pendingPromptWarning = r.avgLogprob < LocalWhisper.confidenceFloor
                ? String(format: "⚠️ low confidence %.2f — check what was sent", r.avgLogprob)
                : nil
            // Reads the bytes on this thread and files the sample on its own, so
            // the staged copy can go immediately after — the corpus keeps its own.
            self.corpus.captureLocal(wav: wav, text: r.text, language: r.language,
                                     duration: duration, app: app)
            try? FileManager.default.removeItem(at: wav)
            self.send(kind: "dictation", text: r.text, app: app)
        }
    }

    /// One switch for both places the ⏳ shows, so they can never disagree — the
    /// chip beside the cursor and the menu bar glyph. Both are needed and
    /// neither is enough: the chip is where he is looking, and the menu bar is
    /// the half that survives him typing, since macOS hides the pointer then and
    /// the chip goes with it.
    /// Whether the helper is on its way up right now — asked by the two gestures
    /// that can kick the load off, so neither starts a second one on top of it.
    private var engineLoading = false

    private func setEngineLoading(_ loading: Bool) {
        engineLoading = loading
        status.setEngineLoading(loading)
        overlay.setEngineLoading(loading)
    }

    /// Register the app as a login item, once, quietly.
    ///
    /// **The relay has to be up before Victor starts talking**, and since ⌘⌃D
    /// moved into this app there is nothing else left to launch it: the key that
    /// starts a session is served by the very process that has to be running to
    /// hear it. A login item is the whole of what that requires — the app is an
    /// accessory with no window, so starting it costs a menu bar icon and 56 MB,
    /// and the model it could load is deliberately not loaded until a session
    /// begins (see `applicationDidFinishLaunching`).
    ///
    /// `SMAppService` rather than a LaunchAgent plist: it registers the bundle
    /// that is running, so a copy moved or renamed cannot leave a stale plist
    /// pointing at a path with nothing behind it — and Victor can turn it off in
    /// System Settings → General → Login Items, which is where he would look.
    /// Already-registered is not an error, and a failure is logged rather than
    /// shown: an app that cannot register is still an app that runs.
    private static func startAtLogin() {
        guard #available(macOS 13, *) else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            Log.info("already a login item")
            return
        }
        do {
            try service.register()
            Log.info("registered as a login item")
        } catch {
            Log.error("could not register as a login item: \(error.localizedDescription)")
        }
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
        // Nothing bound is the same answer as paused, one step earlier: a
        // picture of the screen at the moment he starts talking is only worth
        // taking when there is somebody it is being taken *for*. A spawn counts
        // as somebody — the session it is about to open reads the same line.
        guard hasDestination, !paused else { return }

        // Where he was pointing when he started talking. Taken here and carried
        // down: by the time the capture actually runs, a clipboard probe and a
        // subprocess later, the pointer has moved on.
        let cursor = NSEvent.mouseLocation
        // And what he was looking at, for the same reason and at the same
        // instant. This is the frame he means by "uite ce e aici" — reading the
        // title after the subprocess would name whatever he switched to while
        // still talking about this.
        let source = WindowContext.describe()

        stateLock.lock()
        let alreadyOpen = dictationInFlight
        dictationInFlight = true
        // A new dictation is a new subject. Clear the old one before probing, so
        // a selection stranded by a dictation that never produced a transcript
        // cannot ride along with the next thing he says.
        if !alreadyOpen {
            pendingSelection = nil
            pendingExtraSelections = []
            contextShotPending = true
            // The zero of every offset in this dictation. Set here because this
            // is the moment the context shot is booked, and that shot has to come
            // out at 0:00 exactly.
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
            if let path = path, let source = source { self.shotSources[path] = source }
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
        pendingExtraSelections = []
        shotSources = [:]
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
        // Pausing mid-recording finishes it rather than abandoning it: he said
        // the words, and the ordinary reason to pause here is that he is done
        // and on his way into another app.
        if paused && localRecording { stopLocalRecording() }
        overlay.setPaused(paused)
        status.setPaused(paused)
        syncBorrowedGestures()
        syncLocalCapture()
        Log.info(paused ? "paused via \(reason) — nothing is recorded or relayed"
                        : "resumed via \(reason)")
    }

    /// The two gestures the relay **borrows from other software**, handed over and
    /// handed back together.
    ///
    /// Mouse 4 is Victor's Return key (LinearMouse types one with it) and ⌘-click
    /// is how a link opens in a new tab; the relay takes both **only while there is
    /// a dictation for them to add to**. Outside that window — at rest, the whole
    /// time forwarding is paused, and the whole time nothing is bound — they must
    /// go back to doing what every other app expects, so this is called from all
    /// three edges that can change the answer: a dictation starting or stopping,
    /// pause being toggled, and a binding appearing or going away (`showBound`).
    ///
    /// One switch for both, so the recording row can never be on screen advertising
    /// a gesture that is no longer live, or off while one still is. Main thread only.
    private func syncBorrowedGestures() {
        let live = hasDestination && listening && !paused
        hotkeys.dictating = live
        picker.dictating = live
        // The music is pausing for the same window and for the same reason: it
        // is the span in which Victor is talking rather than using the machine.
        // Hanging it here rather than off `listening` alone is deliberate — a
        // dictation that is not being relayed anywhere (unbound, or forwarding
        // paused) is Victor talking into some other app, and silencing his music
        // for that would be the relay reaching outside its own session.
        music.setActive(live)
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
    /// Keep `HotkeyTap.frontIsBindable` current, so the menu can decide whether
    /// a tap is a bind or a plain middle click **without asking the main thread**
    /// — an event tap that blocks is a mouse that stops moving.
    ///
    /// Pushed on every activation rather than polled: app switches are rare and
    /// the notification is exact, where a poll would be a timer running all day
    /// to answer a question that changes a few dozen times.
    /// The browser the pick extension lives in. One id, deliberately: the
    /// extension is loaded in Victor's Chrome and nowhere else, and a list of
    /// Chromium bundle ids would be a row promising a gesture that no extension
    /// is there to serve.
    private static let chromeBundleID = "com.google.Chrome"

    private func startWatchingFrontApp() {
        let update: (NSRunningApplication?) -> Void = { [weak self] app in
            let bundle = app?.bundleIdentifier ?? ""
            self?.hotkeys.frontIsBindable = TerminalBinding.isBindable(bundleID: bundle)
            // …and whether the ⌘⇧-pick row has a page to be about. The same
            // notification answers both questions, and it is the only place
            // either is asked — see `RelayWindow.chromeFront`.
            self?.overlay.setChromeFront(bundle == Self.chromeBundleID)
        }
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { note in
            update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private func bindFrontmostTerminal() -> [String: Any]? {
        var front: NSRunningApplication?
        DispatchQueue.main.sync { front = NSWorkspace.shared.frontmostApplication }
        // Read before binding: `bind` replaces the target, and what decides
        // between "point somewhere new" and "stop" is what it *was*.
        let previous = terminal.target?.handle
        guard let front = front, let bound = terminal.bind(app: front) else {
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("⚠️ nothing bindable in front", duration: 3) }
            return nil
        }

        // **⌘⌃D on the target it is already pointed at lets go of it.**
        //
        // The key had no off. Starting the relay is a keystroke and stopping it
        // was a trip to the menu bar — and the menu bar is a moving target when
        // the reason you are stopping is that you are already elsewhere. Making
        // the same key the off switch also makes it reachable without aiming:
        // whatever app is in front, two quick presses bind it and then stop,
        // because the second press finds the first one's target.
        //
        // Compared by **handle**, not by app: two tabs of Terminal are two ttys,
        // so pressing in a different tab re-points rather than stops. That is the
        // more useful reading of "again" — the thing bound is a session, not an
        // application.
        //
        // **It unbinds; it does not quit.** It used to quit, and the argument was
        // that ⌘⌃D is what *starts* the relay, so its off switch should not leave
        // a process running. That argument died with the two changes underneath
        // it: the app now **starts at login** and is up all day whether or not
        // anything is bound (*⌘⌃D is this app's own key*), and *unbound is inert*
        // made an idle relay cost nothing — it touches no dictation at all. So
        // quitting no longer undoes a launch, it undoes a **binding** plus a
        // login item, and the second half has to be put back by hand before the
        // key works again. The opposite of "point this at that terminal" is
        // "stop pointing at it", which is exactly `unbindTerminal` — the same
        // call `POST /unbind` and the menu's Disconnect make, so all three routes
        // out of a binding now end in the same state instead of two of them
        // leaving the app running and one killing it.
        if let previous = previous, previous == bound.handle {
            DispatchQueue.main.async { [weak self] in
                BindFlight.cancel()
                Log.info("⌘⌃D on the bound target — unbinding")
                self?.unbindTerminal()
            }
            return ["unbound": true, "label": bound.label, "address": bound.address]
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // **`walkie: started in petclinic@main`** — the folder, and nothing
            // else. The flash used to name the `ttysNNN` address as well, on the
            // grounds that it settles "did it grab the right tab?"; it never was
            // the question Victor asks at this moment, and the device file is
            // noise on a projector. Addons' banner for the same press says the
            // same words, so the two panels read as one event rather than as two
            // announcements of it.
            //
            // It is still where the shell guard's absence is reported, now that
            // the chip no longer distinguishes ⌨️ from 🎯: binding is the moment
            // that fact can still change what Victor does about it, and a warning
            // is not a label — it survives the shortening.
            // **Only the warning survives.** The flash used to read
            // `walkie: started in <folder>`, and the chip beside the cursor
            // changes to that same folder at this exact instant — so it was the
            // one fact said twice, in two places, one of which then sat over his
            // work for three seconds. The missing shell guard has nowhere else
            // to be said, and it is the one thing here that can still change what
            // Victor does about it, so it flashes on its own.
            let unguarded = bound.isGuarded ? nil : "⚠️ no shell guard"

            // **The rectangle hands over to the chip.** It flies from the window
            // that was captured to the cursor, and the label appears there the
            // instant it arrives — so the two are one gesture rather than two
            // announcements, and the shape that lands *becomes* the thing now
            // sitting under his hand.
            //
            // The flash is sized to the flight for the same reason: a flash is a
            // panel, and a panel is not the chip, so an overlay still showing one
            // in the corner has nowhere to put a label beside the pointer. Ending
            // them together is what leaves the cursor free at the exact moment
            // the rectangle gets there.
            //
            // With no window to fly from — nothing resolved a frame — there is no
            // arrival to wait for and the chip is set at once.
            // A bind means a dictation is coming, which is the moment to pay for
            // the model if it is not up — ten seconds that overlap him settling
            // into the session, rather than ten seconds in the middle of the
            // first sentence.
            // **The load only.** Arming the microphone here was wrong: a bind is
            // Victor pointing the relay at a terminal, not Victor starting to
            // talk, and the two can be minutes apart. The wheel remains the only
            // thing that opens it — and if he holds it while this load is still
            // running, `startLocalRecording` remembers the gesture and it fires
            // the moment the weights land.
            self.startWhisper()
            // **The chip is set first, and the rectangle flies into it.** It used
            // to be the other way round — the label appeared when the rectangle
            // landed — which meant the flight ended on empty screen and the
            // answer arrived a frame later. Showing it up front gives the
            // rectangle something to aim at, and it now slides underneath and
            // disappears there: the window that was captured is *this* label.
            self.showBound(bound)
            guard let frame = bound.sourceFrame else {
                if let unguarded = unguarded { self.overlay.flash(unguarded, duration: 3) }
                return
            }
            // Still sized to the flight when there is one: a flash is a panel,
            // and a panel is not the chip, so an overlay still showing one has
            // nowhere to put a label beside the pointer.
            if let unguarded = unguarded {
                self.overlay.flash(unguarded, duration: BindFlight.duration)
            }
            BindFlight.fly(from: frame, to: { [weak self] in
                self?.overlay.chipFrame ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
            })
        }
        return Self.describe(bound)
    }

    private func unbindTerminal() {
        terminal.unbind()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // **Read before the chip goes**, or the burst is aimed at whatever
            // shape the overlay has already shrunk to.
            let chip = self.overlay.chipFrame
            self.showBound(nil)
            // No sentence any more. `unbound — nothing is relayed now` was a
            // panel appearing in order to announce a disappearance, a few pixels
            // from the thing that disappeared. The chip coming apart where it
            // stood says it in the place it happened, and leaves nothing behind,
            // which is the whole of the message.
            UnbindPop.burst(at: chip)
        }
    }

    /// The bound terminal has been renamed by whatever is running in it. Called
    /// off the overlay's 10s tick — and doing the work on a background queue,
    /// because reading the title is an `osascript` round trip and the caller is
    /// the main thread in the middle of a timer.
    private func refreshBoundTitle() {
        guard terminal.target != nil else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, let updated = self.terminal.refreshBinding() else { return }
            DispatchQueue.main.async { self.showBound(updated) }
        }
    }

    /// The one place the binding is put on screen, so the chip and the menu can
    /// never disagree about where the words are going.
    ///
    /// Both show the same line — `walkie-talkie@main` behind the destination app's
    /// own icon — because they answer the same question in two places: the chip is
    /// where he is looking while he talks, and the menu bar is what is left when
    /// the pointer (and with it the chip) is hidden because he started typing.
    /// Main thread only: it draws.
    private func showBound(_ target: TerminalBinding.Target?) {
        // Binding is also the switch that decides whether the relay touches a
        // dictation at all, and this is the one place every route into it passes
        // through — ⌘⌃D, `/unbind`, and a target found gone at delivery. Doing it
        // here is what keeps a relay that lost its terminal mid-session from
        // going on holding the wheel and the microphone.
        defer { syncLocalCapture(); syncBorrowedGestures() }
        guard let target = target else {
            overlay.setBound(label: nil)
            status.setDestination(nil, icon: nil)
            return
        }
        // A target with no readable directory (a blind-paste app) says its own
        // name instead. That is the one case where the icon is not enough on its
        // own — there is nothing else on the line to give it a subject.
        let line = target.folder ?? target.appName
        overlay.setBound(label: target.label, folder: line,
                         icon: Self.appIcon(target.bundleID, height: 18))
        status.setDestination(line, icon: Self.appIcon(target.bundleID, height: 20))
    }

    /// The destination app's icon, drawn down to the row height it has to sit in.
    ///
    /// Asked of the installed application rather than of the running one: a
    /// running app answers `nil` for its icon often enough (it is loaded lazily,
    /// and an app that is busy launching has none yet), and the bundle on disk is
    /// the same picture with no timing to it.
    private static func appIcon(_ bundleID: String, height: CGFloat) -> NSImage? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: height, height: height)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
    }

    private static func describe(_ target: TerminalBinding.Target) -> [String: Any] {
        var obj: [String: Any] = ["label": target.label, "address": target.address,
                                  "guarded": target.isGuarded]
        if let folder = target.folder { obj["folder"] = folder }
        if let title = target.title { obj["title"] = title }
        return obj
    }

    /// **Open the destination and hand it the words in one gesture.** ⇧ + the
    /// wheel ends here: a new Terminal window, an interactive Claude Code in the
    /// folder that was current when he started talking, and the dictation as its
    /// first prompt.
    ///
    /// **The prompt goes in `argv`, not through the keyboard.** Every other
    /// delivery in this app types into a session that already exists and has to
    /// prove first that a shell is not sitting at the prompt (`wouldRunAsShell`).
    /// Here there is nothing to prove and nothing to wait for — the words are an
    /// argument to the process being started, so they cannot be executed by a
    /// shell, cannot land in an editor window, and cannot arrive before the agent
    /// is ready to read them. That is also why this does not wait for the session
    /// to come up before reporting: there is no readiness to wait for.
    ///
    /// **The binding does not move.** The new window is where *this* sentence
    /// went, not where the relay now lives: Victor asked for it explicitly, and
    /// the reason holds on its own — the wheel is a gesture he makes dozens of
    /// times a day at the session he is working in, and a spawn silently
    /// re-pointing it would mean the next ordinary dictation lands in a session
    /// that has existed for four seconds. Two more spawns in a row still each
    /// get their own window, and the terminal he was aimed at is still the one
    /// he is aimed at. Unbound, it stays unbound — a spawn is a one-shot
    /// destination, not a way of acquiring one.
    private func spawnClaude(_ m: Message) {
        let line = Self.terminalLine(m)
        guard !line.isEmpty else { return clearSpawn() }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = SpawnTerminal.launchClaude(prompt: line, directory: Self.spawnDirectory)
            DispatchQueue.main.async {
                self.clearSpawn()
                switch outcome {
                // **Silent**, like every other delivery that landed: the window
                // is in front with the session running in it, which is a whole
                // screen of evidence, and a flash would be a panel thrown over
                // his work to repeat what it already shows.
                case .opened:
                    break
                case .failed(let why):
                    // The outbox already has the line — `commit` wrote it before
                    // this ran — so what is lost is the delivery, and this is the
                    // only place he would learn that.
                    Log.error("✨ spawn failed: \(why)")
                    self.overlay.flash("⚠️ \(why)", duration: 8)
                }
            }
        }
    }

    /// The dictation that was going to open a terminal is over — delivered,
    /// cancelled, or never transcribed. Main thread only: it draws.
    private func clearSpawn() {
        spawnPending = false
        overlay.setSpawnDestination(nil)
    }

    /// **Always `~/workspace`, and nothing is inferred.** Victor's call, and the
    /// three reasons line up behind it: it is where he starts every session by
    /// hand, so it is the one folder Claude Code already trusts — a spawn into a
    /// sub-repo stops on the "do you trust this folder" question instead of
    /// working — every repo he has is a folder inside it, so the agent can still
    /// be told which one, and a destination that is always the same is one he
    /// never has to check before he starts talking.
    ///
    /// The alternative was resolving it from the bound target or the terminal in
    /// front. It was written, and it is what surfaced the trust prompt: an answer
    /// that is right four times out of five is worse here than one that is fixed,
    /// because the fifth is only discovered after the sentence is spoken.
    private static let spawnDirectory = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("workspace").path

    /// What the chip calls that folder while he is talking at it.
    private static let spawnFolderName = (spawnDirectory as NSString).lastPathComponent

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
            showBound(nil)
            overlay.flash("⚠️ \(what) — unbound", duration: 6)
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
    /// **The agent is told the words were spoken, and in which two languages
    /// they might have been spoken.** This is the one clause here written to
    /// change how the text is *read* rather than to add something to read.
    ///
    /// A transcript arrives looking exactly like something Victor typed, so a
    /// mis-heard word reads as a word he chose. Measured on his own corpus, a
    /// local recogniser turned `Wispr Relay` — what this app was called then —
    /// into `risparerile ei`; an agent that knows the input came through a
    /// microphone sounds that out, one that does not has no reason to try.
    ///
    /// **`RO or EN`, fixed, rather than the language the recogniser detected.**
    /// It did carry the detected code for one commit, and the reason it no
    /// longer does is that the code is not reliable enough to assert: a sentence
    /// of Victor's plain Romanian came back labelled `en` in the very recording
    /// used to test it. A clause naming the wrong language is worse than one naming
    /// neither — it points the phonetics of a mis-heard word in a direction it
    /// was never said in. Both, always, is true on every dictation and is still
    /// the useful half: *which* two languages to sound a word out in. He asked
    /// for exactly this, twice, and the second time after being shown the
    /// mislabel: *"RO or EN"*.
    ///
    /// **Everything else went, also on his instruction** — *"skip the rest of
    /// details - are obvious"*. The clause used to spell out what to do about a
    /// word that makes no sense; a reader capable of acting on that advice does
    /// not need it spelled out, and this rides on every single dictation.
    ///
    /// Only `dictation` gets it. A screenshot or a typed message was not spoken,
    /// and a hint that invites phonetic guessing at text nobody dictated is an
    /// invitation to misread it.
    ///
    /// **Its other failure mode is not a mis-heard word, it is a fluent invention.**
    /// Measured over 442 dictations, 11 came back semantically broken — not
    /// garbled, but confident sentences that were never said ("Nu uitați să vă
    /// abonați" for a sentence about an invoice). The confidence gate catches 7
    /// of them before they are sent; the other 4, and everything the relay's own
    /// microphone path deliberately sends *below* the gate rather than
    /// swallowing, arrive looking exactly like a correct transcript. That is the
    /// one failure an agent cannot defend itself against by reading, so it is
    /// told instead — which is what Victor asked for.
    private static let dictatedHint =
        "[this text was dictated in RO or EN and transcribed by a local Whisper — "
        + "it can hallucinate a fluent sentence that was never said]"

    private static func terminalLine(_ m: Message) -> String {
        var parts: [String] = []
        if let text = m.text, !text.isEmpty { parts.append(text) }
        if m.kind == "dictation", let text = m.text, !text.isEmpty {
            parts.append(dictatedHint)
        }
        if let selection = m.selection, !selection.isEmpty {
            parts.append("[selected: \(clampForTerminal(selection))]")
        }
        // **Stamped, because that is the only thing that distinguishes them.**
        // A bare second `[selected: …]` beside the first is two highlights with
        // no way to tell which came from where in the sentence — and the reason
        // to record them at all is that he said something different while each
        // one was on screen. `0:31` is what lets "the one I mentioned after the
        // tax bit" resolve to a string.
        for extra in m.extraSelections {
            parts.append("[selected \(stamp(extra.at)): \(clampForTerminal(extra.text))]")
        }
        // **What was in front of him is not a caption for a picture.**
        // It used to ride inside the context frame's clause, as
        // `shot-00:00(…).jpg = Terminal — ✳ walkie-talkie`, which made a fact
        // about the dictation readable only by an agent that had decided to open
        // an image — and that clause says in the same breath that opening it is
        // usually unnecessary. The title is the cheapest context here and the one
        // most often enough on its own: it names the app he is talking about and
        // the file, page or session inside it, in a dozen characters, with no
        // megabyte attached. So it is its own block, delivered whether or not any
        // frame is ever opened. He asked for exactly this: *"it has nothing to do
        // with the images"*.
        //
        // The manual shots keep their `= title` — there it genuinely is a caption,
        // the thing that says which picture is which in an enumeration of five.
        if let screen = m.screen, let front = m.sources[screen],
           !front.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("[Focused window: \(front)]")
        }
        // `look at` and `context` stay separate, exactly as `paths` and `screen`
        // do: one is what he deliberately photographed and wants opened, the
        // other is the frame that happened to be on screen when he started
        // talking. Collapsing them would have every dictation drag a megabyte of
        // desktop into a context window nobody asked to spend.
        parts.append(contentsOf: shotsClause(paths: m.paths, screen: m.screen, sources: m.sources))
        if !m.elements.isEmpty {
            let named = m.elements.map { pick -> String in
                guard let text = pick.text, !text.isEmpty else { return pick.path }
                return "\(pick.path) (\(clampForTerminal(text, 60)))"
            }
            parts.append("[pointed at: \(named.joined(separator: " · "))]")
        }
        return parts.joined(separator: " ")
    }

    /// How the pictures are handed over: the folder once, then the frames by
    /// name, oldest first.
    ///
    /// **The small copies travel, not the retina frames.** `ScreenCapture.handover`
    /// picks the downscaled sibling, which the evals in `evals/` measured as
    /// costing a fraction of the tokens for the same answers. The originals are named in
    /// the clause too, because "I can't read that" has to have an answer that is
    /// not "take the picture again".
    ///
    /// **The order is stated, because nothing else states it.** Every one of
    /// these messages is a sequence — he says "ăsta … și ăsta … și ăsta" and
    /// presses the shutter between clauses — and until now the only thing
    /// carrying that was the order of paths inside `[look at:]`, which is an
    /// ordering something has to *guess* is meaningful rather than incidental.
    /// The frames are named by their offset into the sentence (`shot-00:38…`),
    /// so once the list is known to be chronological the names locate each one
    /// inside what he was saying.
    ///
    /// **The context frame is offered, not withheld, and is not called a spare.**
    /// Dropping it scored worse in the evals for a reason worth remembering: he
    /// starts talking about what is already on his screen, so it is routinely
    /// picture *one* of the enumeration rather than a fallback nobody needs.
    /// What it gets is a hint that it can be skipped — a "Test, test, test"
    /// dictation had the agent open a megabyte of desktop for nothing.
    ///
    /// Factoring the directory out saves ~90 characters a frame. That is worth
    /// having and is **not** where the tokens are: measured, the addressing is a
    /// rounding error beside the pixels, which is why this method is short and
    /// `handoverWidth` has an essay over it.
    private static func shotsClause(paths: [String], screen: String?,
                                    sources: [String: String] = [:]) -> [String] {
        guard paths.first != nil || screen != nil else { return [] }
        let dir = ((paths.first ?? screen!) as NSString).deletingLastPathComponent

        /// `shot-00:18(…).jpg = IntelliJ IDEA — OwnerController.java`
        ///
        /// **The title goes here and not into the file name**, which is where
        /// the offset and the pointer already live. Those two are short,
        /// machine-generated readings that survive being made into a filename.
        /// A window title is arbitrary text — it carries `/`, quotes, colons and
        /// eighty characters of headline — so putting it in a name means
        /// sanitising away exactly the characters that identify the page, and
        /// leaves Victor, who reads these names himself, with something he
        /// cannot read. The evals settled the cost question: the addressing is a
        /// rounding error beside the pixels, so the line has room.
        ///
        /// **Only the deliberate shots are described this way.** The automatic
        /// context frame gets `handed` instead: what was in front of him then is
        /// now its own `[Focused window: …]` block in the envelope, because it is
        /// a fact about the dictation rather than a caption identifying one
        /// picture among several — and burying it here hid it behind a clause
        /// that tells you not to open the file.
        func handed(_ original: String) -> String {
            ((ScreenCapture.handover(for: original)) as NSString).lastPathComponent
        }
        func described(_ original: String) -> String {
            guard let source = sources[original] else { return handed(original) }
            return "\(handed(original)) = \(source)"
        }

        // **A clause each, rather than one sentence with the context tacked on.**
        // Written as one, it came out `… = Google Chrome — Netflix. shot-00:00(…)
        // is the screen when I started talking` — and a window title can itself
        // end in a full stop, so the separator between the last shot and the
        // context frame stopped being a separator. Titles are arbitrary text;
        // the brackets are the only delimiter here that they cannot forge.
        let note = "Each is \(ScreenCapture.handoverWidth)px wide; "
            + "drop the -small for the full-resolution original."

        // Nothing but the automatic frame — 168 of the 180 dictations in the
        // outbox look like this. One short clause and no ceremony.
        guard !paths.isEmpty else {
            guard let screen = screen else { return [] }
            return ["[the screen when I started talking, open only if the words need it: "
                    + "\(dir)/\(handed(screen)). \(note)]"]
        }

        var clauses = ["[the shots I took, in \(dir)/, oldest first, each named by what was in front of me: "
                       + paths.map(described).joined(separator: "; ") + ". \(note)]"]
        if let screen = screen {
            clauses.append("[and \(handed(screen)) is the screen when I started talking, "
                           + "open it only if the words need it]")
        }
        return clauses
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
    /// apps to look something up: none of that changes what he is talking about.
    /// Later probes exist only to fill a blank the first one left.
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

    /// The shutter's other half: whatever is highlighted **at this moment**,
    /// filed under where in the sentence he is.
    ///
    /// He points at things by highlighting them as much as by photographing
    /// them, and until now only the first of those survived — the selection was
    /// frozen at the start of the dictation and every later highlight was
    /// dropped. Now the same press that says "look at this" also records what
    /// "this" was selected as, which is the half a picture cannot carry: a
    /// screenshot shows a line of code, the selection *is* the line of code, in
    /// characters something can grep for.
    ///
    /// **Three things are skipped, and each of them would be noise:**
    /// nothing highlighted at all; the same text the frozen selection already
    /// holds (he never let go of it, which is the common case and says nothing
    /// new); and the same text as the previous extra, for shots taken in quick
    /// succession over one highlight.
    ///
    /// Accessibility only (`readQuiet`) — the clipboard fallback posts a ⌘C into
    /// whatever app is under his hand, and doing that on every shutter press is
    /// a bill the gesture never agreed to pay.
    private func stashExtraSelection(at offset: TimeInterval) {
        guard let text = SelectionCapture.readQuiet(), !text.isEmpty else { return }

        stateLock.lock()
        let isFrozen = pendingSelection == text
        let isRepeat = pendingExtraSelections.last?.text == text
        let novel = !isFrozen && !isRepeat
        // A dictation that opened with nothing highlighted has an empty frozen
        // slot, and the first thing he highlights mid-sentence belongs *there* —
        // it is the subject, arriving late. Only once that slot is taken does a
        // highlight become an extra.
        let fillsTheBlank = novel && pendingSelection == nil
        if fillsTheBlank {
            pendingSelection = text
        } else if novel {
            pendingExtraSelections.append((at: offset, text: text))
        }
        let total = (pendingSelection != nil ? 1 : 0) + pendingExtraSelections.count
        stateLock.unlock()

        guard novel else { return }
        Log.info("↪ selection at \(Self.stamp(offset)) — \(text.count) chars (\(total) in this dictation)")
        DispatchQueue.main.async { [weak self] in self?.overlay.setSelection(text, count: total) }
    }

    /// `m:ss`, the one clock this app measures anything in.
    private static func stamp(_ offset: TimeInterval) -> String {
        let s = max(0, Int(offset.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// F3, or mouse 4 while dictating — one more shot for the dictation in
    /// progress, with the cursor recorded so the agent can see what he was
    /// pointing at when he pressed.
    private func plusOneShot(cursor: NSPoint) {
        guard hasDestination, !paused else { return }
        // Sampled at the gesture, like the cursor and for the same reason: by the
        // time `screencapture` returns, a subprocess later, the moment he pressed
        // at is a second in the past — and a second is a whole sentence.
        let takenAt = Date()
        // Sampled here with the moment and the cursor, not in the background
        // block below: this is the window he pressed the shutter *at*.
        let source = WindowContext.describe()
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

            // **Before `screencapture`, for the same reason the cursor is.** The
            // shutter is pressed at a moment, and by the time a subprocess has
            // run and returned, the caret and the highlight it sat in have both
            // moved on. A selection read after the picture would be a selection
            // from after the picture.
            if let offset = offset { self.stashExtraSelection(at: offset) }

            guard let path = ScreenCapture.grab(cursor: cursor, offset: offset) else {
                DispatchQueue.main.async { self.overlay.flash("⚠️ screenshot failed") }
                return
            }

            self.stateLock.lock()
            let attaching = self.dictationInFlight
            if let source = source { self.shotSources[path] = source }
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
    /// **The type, not the selector.** These lines used to carry `pick.short` —
    /// the last two steps of the path, `div#cart > span.price` — which is the
    /// right thing to *send* and the wrong thing to show here. Three of them turn
    /// the panel into a wall of punctuation to be read at the exact moment the
    /// Cancel clock is running, and the question he is answering is not "which
    /// selector" but "did my three clicks land". `button`, `div`, `a` answers that
    /// in a glance. The full selector still travels in the message; nothing is
    /// lost, it is just not shouted at him. Bulleted for the same reason: a list
    /// of three is read as a count when it looks like a list.
    ///
    /// **Negative stamps are the point, not an edge case.** Pointing usually comes
    /// *before* the sentence — he finds the thing, then says what to do with it —
    /// so `−0:08` reads exactly as it should: you pointed at this eight seconds
    /// before you started talking.
    private static func pickLines(_ picks: [ElementPick], since: Date?) -> [String] {
        let shown = picks.prefix(maxPickLines)
        var lines = shown.map { pick -> String in
            guard let since = since else { return "• \(pick.tag)" }
            let seconds = Int(pick.at.timeIntervalSince(since).rounded())
            let sign = seconds < 0 ? "−" : ""
            let abs = Swift.abs(seconds)
            return String(format: "• %@%d:%02d %@", sign, abs / 60, abs % 60, pick.tag)
        }
        if picks.count > shown.count { lines.append("• +\(picks.count - shown.count) more") }
        return lines
    }

    /// Enough to check the ones he is likely to still be holding in his head. Past
    /// that the panel is a list he has to read instead of a prompt he has to
    /// approve, and the countdown is running.
    private static let maxPickLines = 3

    /// Same bargain as `maxPickLines`, and the same countdown behind it: past
    /// two or three the panel is a document rather than a prompt to approve.
    private static let maxExtraSelectionLines = 3

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
        // **No 📸 and no count.** The strip of thumbnails under this line says
        // both, in the picture rather than in a number, and the panel is read in
        // the few seconds the clock is running. What the strip cannot say is
        // *when* each frame was taken, so the stamps stay — in the same order the
        // frames are drawn, which is what lets them read as captions for it.
        guard !stamps.isEmpty else { return nil }
        return stamps.joined(separator: " · ")
    }

    /// What to render in the overlay as "this is what the agent got". Returns nil
    /// for messages with no words in them (a bare screenshot), which fall back
    /// to the one-line flash.
    private static func promptPreview(text: String?, selection: String?,
                                      extraSelections: [(at: TimeInterval, text: String)] = [],
                                      shotOffsets: [TimeInterval],
                                      picks: [ElementPick], since: Date?) -> String? {
        var parts: [String] = []
        if let text = text, !text.isEmpty { parts.append(text) }
        // **The selection counts as something to show, but is not shown here.**
        // It goes to the panel separately and is drawn above the words, quoted —
        // so this string must not carry it, and must still refuse to return nil
        // for a message that has one. Getting only the first half of that right
        // would send a highlighted-with-no-words message straight out, past the
        // Cancel button that exists for it.
        let hasSelection = !(selection ?? "").isEmpty
        guard !parts.isEmpty || hasSelection else { return nil }
        // Stamped, and after the words rather than before them: the frozen
        // selection is what he was talking *about* and belongs at the top, while
        // these are things he reached for part-way through and read back in the
        // order he reached for them. Cancel is still running while he reads this,
        // which is the only moment noticing a wrong highlight is free.
        for extra in extraSelections.prefix(maxExtraSelectionLines) {
            parts.append("↪ \(stamp(extra.at)) " + extra.text)
        }
        if extraSelections.count > maxExtraSelectionLines {
            parts.append("↪ +\(extraSelections.count - maxExtraSelectionLines) more")
        }
        if let shots = shotLine(shotOffsets) { parts.append(shots) }
        parts.append(contentsOf: pickLines(picks, since: since))
        return parts.joined(separator: "\n")
    }

    /// The ✕ and the menu bar's Quit both end the session. Announce it through the
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
        // Let the ~2.5 GB go on the way out. It would go anyway — the helper sees
        // EOF on stdin when the relay's pipes close and exits on its own, measured
        // at nine seconds even after a SIGKILL — but nine seconds of a model
        // nobody is using is nine seconds of a laptop that is not his to spend.
        whisper.stop()
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
        // Before either branch: a relay that quits mid-sentence must not leave
        // Chrome silent. The extension also resumes on a dead socket, but that is
        // the safety net for a crash, not the way an orderly quit should look.
        music.stop()
        guard !SingleInstance.beingReplaced() else {
            Log.info("terminating to make way for a new instance — no session_end")
            return
        }
        announceEnd("app terminate")
    }

    private func send(kind: String, text: String? = nil, paths: [String] = [], app: String? = nil) {
        // **The outbox is not written either.** It used to be, on the grounds
        // that an agent might be watching the queue without a binding — the
        // `/relay` skill's original mode. Victor settled it on 2026-08-27: with
        // the app running from login, that meant every sentence he spoke all day
        // was being filed for a watcher that mostly is not there. Unbound now
        // means inert, and `/relay` gets its destination by binding like
        // everything else. `session_end` is unaffected: it goes to `Outbox`
        // directly, not through here.
        // Taken here and cleared here, so the flag never outlives the dictation
        // that set it: from this point the destination travels on the `Message`.
        //
        // **Only a dictation may claim it.** `flushOrphaned` comes through here
        // with a bag of screenshots when no transcript arrived — and, since its
        // timer is armed at the start of the dictation rather than at the end of
        // it, also in the middle of a sentence that has run past two minutes. A
        // spawn consumed there would open a session holding nothing but pictures
        // and leave the words that were still being spoken with nowhere to go.
        let spawn = spawnPending && kind == "dictation"
        if kind == "dictation" { spawnPending = false }
        guard isBound || spawn else {
            Log.info("unbound — dropped \(kind)")
            return
        }
        guard !paused else {
            Log.info("paused — dropped \(kind)")
            return
        }
        stateLock.lock()
        let selection = pendingSelection
        pendingSelection = nil
        let extraSelections = pendingExtraSelections
        pendingExtraSelections = []
        let sources = shotSources
        shotSources = [:]
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
                              extraSelections: extraSelections,
                              paths: attached, screen: screen, sources: sources,
                              app: app, elements: picks, spawn: spawn)

        // Show what is about to go out — selection included, since that is part
        // of the prompt the agent receives, not a separate thing.
        let shown = Self.promptPreview(text: text, selection: selection,
                                       extraSelections: extraSelections, shotOffsets: offsets,
                                       picks: picks, since: since)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlay.clearSelection()

            // Nothing to read is nothing to cancel: a bare screenshot goes
            // straight out, and so does the goodbye.
            guard let shown = shown else {
                self.pendingPromptWarning = nil
                self.commit(message)
                if kind == "dictation" {
                    // `offsets`, not `attached`: same total the recording row was
                    // showing a second ago, context shot included.
                    self.overlay.flash(offsets.isEmpty ? "🎙️ sent" : "🎙️ sent + \(offsets.count) 📸")
                }
                return
            }

            let warning = self.pendingPromptWarning
            self.pendingPromptWarning = nil
            let words = shown.split(whereSeparator: { $0.isWhitespace }).count
            let hold = min(max(Self.minHold, Double(words) / 3.0), Self.maxHold)
            // Oldest first, context frame included — it is picture one of the
            // enumeration far more often than it is a spare, and a strip that
            // skipped it would disagree with the count in the row above.
            let frames = ([screen] + attached).compactMap { $0 }
            if self.overlay.showSentPrompt(shown, hold: hold, shots: frames,
                                           selection: selection,
                                           front: screen.flatMap { sources[$0] },
                                           // What he said, apart from what the
                                           // preview adds to it — the panel needs
                                           // the seam to know what is editable.
                                           words: text, warning: warning) {
                self.held = message
                self.hotkeys.promptHeld = true
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
                    selections: m.extraSelections.map {
                        ["at": Self.stamp($0.at), "text": $0.text]
                    },
                    paths: m.paths, screen: m.screen,
                    sources: m.sources.reduce(into: [String: String]()) { out, pair in
                        out[(pair.key as NSString).lastPathComponent] = pair.value
                    },
                    app: m.app, elements: m.elements.map { $0.json })
        guard m.kind != "session_end" else { return }
        guard !m.spawn else { return spawnClaude(m) }
        deliverToTerminal(m)
    }

    /// The countdown ran out (or he clicked the overlay away) → write it. He hit
    /// Cancel → drop it, and say so, because a message that silently disappears
    /// is indistinguishable from an overlay that has stopped working.
    ///
    /// Cancelling is cheap precisely because nothing was written: the agent polls
    /// the outbox every couple of seconds, so a line already in the file may
    /// already be a tool call in flight.
    /// `edited` is the transcript as it stands on the panel — the same words
    /// unless he clicked into them and fixed something, which is the whole reason
    /// it travels back here rather than the panel being trusted to have shown
    /// what was already in `held`.
    private func releaseHeld(send: Bool, edited: String? = nil) {
        hotkeys.promptHeld = false
        guard var m = held else { return }
        held = nil
        if let edited = edited, edited != m.text {
            Log.info("✎ transcript edited before sending — \(m.text?.count ?? 0) → \(edited.count) chars")
            m.text = edited
        }
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
            if m.spawn { clearSpawn() }
            overlay.flash("✕ cancelled", duration: 2.0)
            return
        }
        commit(m)
    }
}
