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

    /// Keeps every dictation's **recording** beside Wispr's reading of it, so a
    /// local ASR model can one day be measured against Wispr on Victor's own
    /// voice. It transcribes nothing and changes nothing about what the agent
    /// receives — see `VoiceCorpus`, including why Wispr's audio is copied
    /// rather than recorded again.
    private let corpus = VoiceCorpus()

    /// The local recogniser, when Victor has chosen it. Idle and costing nothing
    /// until then — the weights are 1.5 GB resident, and the ordinary case is a
    /// relay running all day on Wispr.
    private let whisper = LocalWhisper()

    /// The microphone, held by the relay itself while Local Whisper is the engine.
    /// Wispr is then out of the loop entirely: it never hears the sentence, so it
    /// never pastes it either. See `MicRecorder` for why a second capture is now
    /// wanted after the corpus argued so hard against one.
    private let mic = MicRecorder()

    /// A local recording is open. Main thread only — it is written and read from
    /// the mouse-5 toggle and the engine switch, both of which hop to main.
    private var localRecording = false

    /// What was in front when the local recording started, for the `app` field a
    /// Wispr dictation gets from Wispr's own row. Read at the press, not at the
    /// end: by the time the model answers he has usually switched away.
    private var localRecordingApp: String?

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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Outbox.prepare()
        overlay = RelayWindow()

        overlay.onTogglePause = { [weak self] in self?.togglePause(reason: "chip click") }
        overlay.onEndSession = { [weak self] in self?.endSession(reason: "✕ button") }

        status = StatusItem()
        status.onExit = { [weak self] in self?.endSession(reason: "menu bar Quit") }
        status.onTogglePause = { [weak self] in self?.togglePause(reason: "menu bar") }
        status.onPickEngine = { [weak self] engine in self?.pickEngine(engine) }
        status.whisperFootprint = { [weak self] in self?.whisper.footprintBytes }

        // The setting outlives the process, so a relay that starts up already set
        // to Local Whisper brings the model up **now** rather than on the first
        // dictation. Otherwise the choice would silently cost ten seconds at the
        // worst possible moment — mid-sentence, with an agent waiting — and the
        // fallback would quietly hand that dictation to Wispr, which is exactly
        // the confusion this feature must not create.
        if TranscriptionEngine.current == .whisper { pickEngine(.whisper) }
        status.setPaused(paused)
        syncLocalCapture()
        overlay.onPromptResolved = { [weak self] send in self?.releaseHeld(send: send) }
        overlay.onRefreshBound = { [weak self] in self?.refreshBoundTitle() }

        hotkeys.onScreenshot = { [weak self] cursor in self?.plusOneShot(cursor: cursor) }
        hotkeys.onLocalToggle = { [weak self] in
            DispatchQueue.main.async { self?.toggleLocalRecording() }
        }
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
        picker.onTestCorpus = { [weak self] id, origin in self?.corpus.capture(id: id, origin: origin) }
        picker.onPickEngine = { [weak self] name in
            guard let engine = TranscriptionEngine(rawValue: name) else { return }
            DispatchQueue.main.async { self?.pickEngine(engine) }
        }
        picker.describeEngine = { [weak self] in
            ["engine": TranscriptionEngine.current.rawValue,
             "ready": TranscriptionEngine.current == .wispr || (self?.whisper.ready ?? false)]
        }
        // Enters where `wispr.onTranscript` does, so it exercises the engine
        // switch itself rather than the delivery below it.
        picker.onTestTranscript = { [weak self] id in
            guard let self = self else { return }
            guard let row = FlowDB.transcriptRow(forID: id) else {
                Log.error("test/transcript: no such row \(id)")
                return
            }
            self.corpus.capture(id: id, origin: "backfill")
            switch TranscriptionEngine.current {
            case .wispr:   self.send(kind: "dictation", text: row.text, app: row.app)
            case .whisper: self.sendLocallyTranscribed(id: id, fallback: row.text, app: row.app)
            }
        }
        // Mouse 5 is only a hint; DictationMonitor is the authority. Kept because
        // it fires a beat before CoreAudio reports the stream, which makes the
        // selection snapshot land closer to the moment Victor pressed.
        hotkeys.onDictationStarted = { [weak self] in self?.captureContext() }

        // Two independent things happen to a finished dictation, and the corpus
        // is deliberately the one that does **not** go through `send`: `send`
        // bails while paused, is subject to Cancel, and is where a message
        // becomes something an agent acts on. Collecting the recording is none
        // of those — it is a file on Victor's disk either way, and a sample
        // dropped because he happened to be dictating into a browser is a sample
        // that cannot be taken again.
        //
        // **The corpus is collected under both engines**, and that is the point:
        // it is Wispr's audio either way, so the samples keep accumulating while
        // the local model is on trial, and switching back and forth does not
        // punch holes in the record.
        wispr.onTranscript = { [weak self] text, app, id in
            guard let self = self else { return }
            self.corpus.capture(id: id)
            switch TranscriptionEngine.current {
            case .wispr:
                self.send(kind: "dictation", text: text, app: app)
            case .whisper:
                self.sendLocallyTranscribed(id: id, fallback: text, app: app)
            }
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
                self?.overlay.flash("⚠️ grant Accessibility to Walkie Talkie", duration: 15)
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
        Log.info("voice corpus at \(VoiceCorpus.root.path)")

        if ProcessInfo.processInfo.environment["RELAY_DEMO"] == "1" { runDemo() }
    }

    /// Transcribe Wispr's recording with the local model and send **that**.
    ///
    /// `fallback` is Wispr's own reading of the same audio, and it is what goes
    /// out whenever the local path cannot answer — the model not up, the helper
    /// dead, the audio not in the row yet, or a transcript the model itself is
    /// not confident in. **A dictation is never dropped for the sake of a
    /// setting**: Victor said something, an agent is waiting, and "the
    /// experimental engine had a bad minute" is not a reason for his words to
    /// vanish. Every fallback says so in the log and in a flash, because an
    /// engine silently not being used is the one way this feature could mislead
    /// the very evaluation it exists for.
    ///
    /// The confidence floor is the measured one (`LocalWhisper.confidenceFloor`):
    /// over 442 real dictations, a gate at −0.6 caught 7 of the 11 semantically
    /// broken outputs and falsely rejected none of 40 good ones. Those 11 are
    /// not mildly wrong — they are fluent inventions ("Nu uitați să vă abonați
    /// la revedere!" for a sentence about an invoice), which is the one failure
    /// an agent cannot defend itself against, since nothing about the text looks
    /// wrong. Almost all of them are clips under five seconds.
    private func sendLocallyTranscribed(id: String, fallback: String, app: String?) {
        func useWispr(_ why: String) {
            Log.error("local whisper → falling back to Wispr: \(why)")
            DispatchQueue.main.async { [weak self] in
                self?.overlay.flash("🤖 Wispr — \(why)", duration: 4)
            }
            send(kind: "dictation", text: fallback, app: app)
        }

        guard whisper.ready else { return useWispr("local model not ready") }
        guard let audio = FlowDB.audio(forID: id) else { return useWispr("no audio on the row") }

        // Written under the session's shots folder rather than beside the
        // corpus: this copy exists only to hand the helper a path, the corpus
        // keeps its own, and Caches is where things whose purpose expires within
        // the turn belong.
        let tmp = Outbox.shotsDir.appendingPathComponent("asr-\(id.prefix(8)).wav")
        do { try audio.write(to: tmp) } catch { return useWispr("could not stage the audio") }

        whisper.transcribe(wav: tmp.path) { [weak self] result in
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let self = self else { return }
            guard let r = result, !r.text.isEmpty else { return useWispr("the model returned nothing") }
            guard r.avgLogprob >= LocalWhisper.confidenceFloor else {
                return useWispr(String(format: "low confidence %.2f", r.avgLogprob))
            }
            Log.info(String(format: "local whisper: %@ (%.2f) — %d chars",
                            r.language ?? "?", r.avgLogprob, r.text.count))
            self.send(kind: "dictation", text: r.text, app: app)
        }
    }

    /// Bring the local model up or let it go, and only then move the tick.
    ///
    /// The order matters in both directions. Choosing Local Whisper starts a
    /// process that takes ten seconds to load 1.5 GB of weights and can fail
    /// outright — for a missing `mlx_whisper`, most likely — so the setting is
    /// only written once the model has actually answered, and a failure leaves
    /// Victor on Wispr with a banner saying why rather than on an engine that
    /// does not exist. Choosing Wispr stops the helper, because the weights are
    /// resident and a relay left running all day must not hold them for an
    /// engine nobody selected.
    private func pickEngine(_ engine: TranscriptionEngine) {
        guard engine != TranscriptionEngine.current || (engine == .whisper && !whisper.ready) else { return }

        guard engine == .whisper else {
            // A recording still open when he switches back would have nobody left
            // to transcribe it — the helper is about to be terminated — so it is
            // finished first, on the engine that is still up.
            if localRecording { stopLocalRecording() }
            whisper.stop()
            setEngineLoading(false)
            TranscriptionEngine.current = .wispr
            status.setEngine(.wispr)
            syncLocalCapture()
            // Instant, unlike the other direction — nothing to load, and the
            // ~2.5 GB the model was holding goes back as the helper exits. Said
            // out loud anyway, because "did that take?" is the same question in
            // both directions and only one of them answers itself.
            overlay.flash("🎙️ Wispr Flow — ready", duration: 3)
            Log.info("engine → wispr")
            return
        }

        setEngineLoading(true)
        // No duration: it ends when the model does, not when a timer says so.
        // A banner that expires after twelve seconds on a load that took
        // fourteen is worse than none — it says "ready" by disappearing.
        overlay.flash("⏳ loading the local model — keep using Wispr until this clears", duration: 600)
        whisper.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.setEngineLoading(false)
                if let error = error {
                    TranscriptionEngine.current = .wispr
                    self.status.setEngine(.wispr)
                    self.overlay.flash("⚠️ local Whisper unavailable — \(error)", duration: 12)
                    Log.error("engine → whisper failed: \(error)")
                    self.syncLocalCapture()
                    return
                }
                TranscriptionEngine.current = .whisper
                self.status.setEngine(.whisper)
                self.syncLocalCapture()
                // Asked here rather than at the first press: the grant dialog is
                // modal and a refusal takes a trip through System Settings, and
                // the moment to find that out is while picking an engine from a
                // menu — not mid-sentence with an agent waiting.
                MicRecorder.requestAccess { ok in
                    guard !ok else { return }
                    self.overlay.flash("⚠️ grant Microphone to Walkie Talkie — mouse 5 cannot record", duration: 15)
                    Log.error("microphone access denied — local recording will not work")
                }
                // The one message he is actually waiting for. Worded as
                // permission rather than as a state, because the question he has
                // been holding for ten seconds is "can I talk yet".
                self.overlay.flash("🎙️ local Whisper ready — go ahead", duration: 4)
                Log.info("engine → whisper")
            }
        }
    }

    // MARK: - The relay's own microphone

    /// Who owns mouse 5, and whether Wispr's typing is allowed through — the two
    /// answers that change together with the engine and with pause.
    ///
    /// One function for both because they are the same fact seen from two sides:
    /// while the relay is forwarding, the transcript belongs to the agent and not
    /// to whatever holds the caret — and on Local Whisper the *microphone* belongs
    /// to the relay too, so the button that would start Wispr must never reach it.
    /// Paused, both go back: pause is what Victor does in order to dictate **into**
    /// an app, and the app getting the text is then the whole point.
    private func syncLocalCapture() {
        hotkeys.localCapture = TranscriptionEngine.current == .whisper && !paused
        hotkeys.blockInjection = !paused
    }

    /// Mouse 5 on Local Whisper: start recording, or finish the one that is open.
    ///
    /// A **toggle**, not a push-to-talk. Wispr's own button is held down for the
    /// length of the sentence, which is fine for a sentence; the dictations that
    /// go to an agent run to a minute or more, and a mouse button held for a
    /// minute is a hand that cannot do anything else — including take the
    /// screenshots (mouse 4, F3) that the same minute is for.
    private func toggleLocalRecording() {
        if localRecording { stopLocalRecording() } else { startLocalRecording() }
    }

    private func startLocalRecording() {
        guard !paused else { return }
        guard whisper.ready else {
            overlay.flash("⚠️ the local model is not up — nothing was recorded", duration: 5)
            Log.error("mouse 5 pressed with no local model ready")
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

        // Exactly what `dictation.onChange(true)` does for a Wispr dictation, and
        // in the same order: the context shot is booked synchronously first,
        // because `setListening(true)` zeroes the count the shot has to appear in.
        captureContext()
        listening = true
        syncBorrowedGestures()
        overlay.setListening(true)
        overlay.setLocalListening(true)
        publishShotCount()
        publishPicks()
    }

    private func stopLocalRecording() {
        localRecording = false
        let app = localRecordingApp
        localRecordingApp = nil
        let recording = mic.stop()

        listening = false
        syncBorrowedGestures()
        overlay.setListening(false)
        overlay.setLocalListening(false)

        guard let (wav, duration) = recording else {
            Log.info("local recording discarded — under \(MicRecorder.minimumDuration)s")
            return
        }
        Log.info(String(format: "🎙️ local recording stopped — %.1fs", duration))
        overlay.flash("⏳ transcribing…", duration: 30)

        whisper.transcribe(wav: wav.path) { [weak self] result in
            guard let self = self else { return }
            guard let r = result, !r.text.isEmpty else {
                DispatchQueue.main.async {
                    self.overlay.flash("⚠️ the model returned nothing — that dictation is lost", duration: 8)
                }
                Log.error("local recording produced no transcript")
                try? FileManager.default.removeItem(at: wav)
                return
            }
            Log.info(String(format: "local whisper: %@ (%.2f) — %d chars",
                            r.language ?? "?", r.avgLogprob, r.text.count))
            // **Sent even below the confidence floor**, unlike the Wispr-recorded
            // path, and for the one reason that path had a choice: there, a low
            // score meant falling back to Wispr's own reading of the same audio.
            // Here there is no second reading — Wispr never heard this — so the
            // alternative to a shaky transcript is silence, and silence is the
            // one outcome Victor cannot notice and correct. The banner says so.
            if r.avgLogprob < LocalWhisper.confidenceFloor {
                DispatchQueue.main.async {
                    self.overlay.flash(String(format: "⚠️ low confidence %.2f — check what was sent", r.avgLogprob),
                                       duration: 8)
                }
            } else {
                DispatchQueue.main.async { self.overlay.clearFlash() }
            }
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
    private func setEngineLoading(_ loading: Bool) {
        status.setEngineLoading(loading)
        overlay.setEngineLoading(loading)
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
        // Read before binding: `bind` replaces the target, and what decides
        // between "point somewhere new" and "stop" is what it *was*.
        let previous = terminal.target?.handle
        guard let front = front, let bound = terminal.bind(app: front) else {
            DispatchQueue.main.async { [weak self] in self?.overlay.flash("⚠️ nothing bindable in front", duration: 3) }
            return nil
        }

        // **⌘⌃D on the target it is already pointed at ends the session.**
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
        // It quits rather than unbinding, because ⌘⌃D is what *starts* the relay
        // and a gesture whose off switch left a process running would not be the
        // opposite of the gesture that made one. `endSession` is the same route
        // the ✕ takes, so the outbox still gets its `session_end` and any agent
        // watching the queue learns the overlay is gone rather than waiting on it.
        if let previous = previous, previous == bound.handle {
            DispatchQueue.main.async { [weak self] in
                BindFlight.cancel()
                self?.endSession(reason: "⌘⌃D on the bound target")
            }
            return ["stopped": true, "label": bound.label, "address": bound.address]
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // The flash names the **address**, which the chip then drops: this is
            // the one moment the answer to "did it grab the right tab?" is worth
            // a panel, and `ttys004` is what settles it. Afterwards the chip's
            // job is to say which session, not which device file.
            //
            // It is also where the shell guard's absence is reported, now that
            // the chip no longer distinguishes ⌨️ from 🎯: binding is the moment
            // that fact can still change what Victor does about it.
            let unguarded = bound.isGuarded ? "" : " — no shell guard"

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
            guard let frame = bound.sourceFrame else {
                self.showBound(bound)
                self.overlay.flash("→ \(bound.label) · \(bound.address)\(unguarded)", duration: 3)
                return
            }
            self.overlay.flash("→ \(bound.label) · \(bound.address)\(unguarded)",
                               duration: BindFlight.duration)
            BindFlight.fly(from: frame) { [weak self] in
                self?.showBound(bound)
            }
        }
        return Self.describe(bound)
    }

    private func unbindTerminal() {
        terminal.unbind()
        DispatchQueue.main.async { [weak self] in
            self?.showBound(nil)
            self?.overlay.flash("unbound — back to the outbox", duration: 3)
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
                         icon: Self.appIcon(target.bundleID, height: 14))
        status.setDestination(line, icon: Self.appIcon(target.bundleID, height: 16))
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
    /// **The agent is told the words were spoken, not typed**, and that is the
    /// one clause here written to change how the text is *read* rather than to
    /// add something to read.
    ///
    /// A transcript arrives looking exactly like something Victor typed, so a
    /// mis-heard word reads as a word he chose. Measured on his own corpus, a
    /// local recogniser turned `Wispr Relay` — what this app was called then —
    /// into `risparerile ei`, and an agent
    /// that does not know the input came through a microphone has no reason to
    /// try sounding that out, while one that does resolves it immediately. The
    /// same failure exists with Wispr, which is merely rarer, not absent.
    ///
    /// It rides every dictation, so it is one short clause and not a paragraph:
    /// the fact that it was spoken is what the agent cannot infer, and what to do
    /// about it follows from that fact for any capable reader.
    ///
    /// Only `dictation` gets it. A screenshot or a typed message was not spoken,
    /// and a hint that invites phonetic guessing at text nobody dictated is an
    /// invitation to misread it.
    private static let dictatedHint =
        "[dictated aloud — if a word makes no sense, it was mis-heard: try what it sounds like]"

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
        func described(_ original: String) -> String {
            let handed = ((ScreenCapture.handover(for: original)) as NSString).lastPathComponent
            guard let source = sources[original] else { return handed }
            return "\(handed) = \(source)"
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
                    + "\(dir)/\(described(screen)). \(note)]"]
        }

        var clauses = ["[the shots I took, in \(dir)/, oldest first, each named by what was in front of me: "
                       + paths.map(described).joined(separator: "; ") + ". \(note)]"]
        if let screen = screen {
            clauses.append("[and \(described(screen)) is the screen when I started talking, "
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
        guard !paused else { return }
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
        guard !stamps.isEmpty else { return "📸 ×\(offsets.count)" }
        return "📸 ×\(offsets.count) " + stamps.joined(separator: " · ")
    }

    /// What to render in the overlay as "this is what the agent got". Returns nil
    /// for messages with no words in them (a bare screenshot), which fall back
    /// to the one-line flash.
    private static func promptPreview(text: String?, selection: String?,
                                      extraSelections: [(at: TimeInterval, text: String)] = [],
                                      shotOffsets: [TimeInterval],
                                      picks: [ElementPick], since: Date?) -> String? {
        var parts: [String] = []
        if let selection = selection, !selection.isEmpty { parts.append("↪ " + selection) }
        if let text = text, !text.isEmpty { parts.append(text) }
        guard !parts.isEmpty else { return nil }
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
                              app: app, elements: picks)

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
                    selections: m.extraSelections.map {
                        ["at": Self.stamp($0.at), "text": $0.text]
                    },
                    paths: m.paths, screen: m.screen,
                    sources: m.sources.reduce(into: [String: String]()) { out, pair in
                        out[(pair.key as NSString).lastPathComponent] = pair.value
                    },
                    app: m.app, elements: m.elements.map { $0.json })
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
