import Foundation

/// **The relay's own microphone and the local model**, behind the same
/// interface Wispr Flow now wears.
///
/// Nothing here is new. It is `startLocalRecording`'s microphone half,
/// `stopLocalRecording`'s decode half and `cancelLocalRecording`'s teardown,
/// lifted out of `AppDelegate` and put behind `DictationSource` so that the
/// chip, the halo, the settle, the corpus and the destination routing stop
/// being able to tell which recogniser they are serving.
///
/// ## It is retired, not deleted (2026-09-12)
///
/// No gesture starts this any more — Victor's decision is that Wispr Flow is
/// the microphone for everything, and the weights are no longer loaded at
/// launch. It stays selectable — `WT_SOURCE=whisper`, and since 2026-09-14 the
/// menu's **Engine** row, which brings the weights up as it picks — for three
/// reasons that are all the same reason:
///
/// - **A Wispr update can change how it delivers.** The wrap rests on
///   intercepting a ⌘V from another process. The day that stops being a ⌘V is a
///   day with no dictation at all unless there is something to fall back to.
/// - **It is the only recogniser that works with no network.**
/// - **The corpus is scored against it.** `evals/` replays
///   `~/.walkie-talkie/voice-corpus/` through this model, and a model that
///   cannot be run is a baseline that cannot be measured.
///
/// Deleting it would have saved a file and cost all three.
final class LocalWhisperSource: DictationSource {

    let name = "Whisper (local)"

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    let meter = MicRecorder()
    private let whisper = LocalWhisper()

    private(set) var isRecording = false
    var isReady: Bool { whisper.ready }

    /// **The same five phases, with no status string in them.** The local model
    /// has a warm-up (the weights) and a round trip (the decode) exactly as Wispr
    /// does; what it has not got is a *vocabulary* for what it is doing in the
    /// middle, which is why `DictationPhase`'s payload is a string and not an
    /// enum of Wispr's statuses. `warming` is the load, which is the source's own
    /// business and is why nothing here is ever `warming`: the microphone opens
    /// on a cold model too (2026-09-26), and the wait for the weights is part of
    /// `transcribing` — after the stop, where it costs him nothing he can see.
    private(set) var phase: DictationPhase = .idle

    /// **The WAV is ours, so the microphone may open before the weights are up**
    /// (2026-09-26, Victor: *"eu nu trebuie să am nicio întârziere vizibilă în
    /// vorbă; trebuie să pot vorbi direct; le bufferizezi tu"*). The same answer
    /// the cloud engine gives, for the same reason — `AppDelegate`'s start gate
    /// is `isReady || recordsOwnAudio`. It is never offered to the local
    /// fallback: that is this model already (`fallBackToLocal`).
    var recordsOwnAudio: Bool { true }

    /// For the menu bar's ⏳ and the About row — asked, never pushed, because
    /// the one moment the answer has to be right is the moment the row is drawn.
    ///
    /// **The helper's own answer, so nil until it has spoken.** Everything that
    /// asks *what did this transcript come out of* wants exactly that and must
    /// not be given a guess.
    var modelName: String? { whisper.modelName }

    /// **What the Engine row shows, which is never nothing** (2026-09-14).
    ///
    /// The row read `Local Whisper` whenever the weights were down — which is
    /// most of the time, since they are only brought up by a gesture that asks
    /// for them — and Victor's answer to that was *"în loc de local wispr trece
    /// numele modelului: mlx…"*. A row whose whole job is to name what he is
    /// dictating with may not fall back to naming a *category*.
    ///
    /// So: the helper's answer while it is up, and the id it **would** load
    /// otherwise. That is a second copy of a constant that lives in
    /// `helpers/whisper_helper.py`, which `Transcriber.modelName`'s note argues
    /// against — rightly, for the question *what produced this transcript*. This
    /// is the other question, *what is about to be believed*, and it has to have
    /// an answer before the model is up. **Keep it in step with
    /// `whisper_helper.py`'s `MODEL`.**
    /// The weights without the account in front — `mlx-community/` is who
    /// published them, not what they are.
    static var modelLabel: String {
        configuredModel.contains("/")
            ? String(configuredModel.split(separator: "/").last!) : configuredModel
    }

    static let configuredModel = ProcessInfo.processInfo.environment["RELAY_WHISPER_MODEL"]
        ?? "mlx-community/whisper-large-v3-turbo"
    var displayModelName: String { whisper.modelName ?? Self.configuredModel }
    var footprintBytes: UInt64? { whisper.footprintBytes }
    /// Whether the weights are on their way up, so two gestures cannot stack two
    /// loads on one another.
    private(set) var loading = false
    /// Raised while the model comes up, so the menu bar can show its ⏳.
    var onLoadingChanged: ((Bool) -> Void)?

    // MARK: - DictationSource

    /// **Not at launch any more.** The preload existed so the first dictation of
    /// the day cost nothing, and there is no first dictation of the day on this
    /// path now. It is brought up by the gesture that asks for it, which is the
    /// arrangement this app had before 2026-09-04 and is the right one for a
    /// recogniser that is a fallback.
    /// **The weights come up when this source becomes the live one** (2026-09-14).
    ///
    /// It was an empty body for as long as the local model was retired — nothing
    /// started it, so loading it at launch was 2 GB spent on a recogniser nobody
    /// was going to use. Since the `Engine` row put it back within one click, and
    /// Victor went back to it (*"we'll keep on using the local model for a
    /// while"*), the cost has reversed: every restart left the first ⌘⌃D
    /// answering *the local model is still loading*, and a dictation helper whose
    /// first sentence of the session is refused is one he has to think about.
    ///
    /// `prepare()` is called from `wireDictationSource`, so this loads when the
    /// source is **chosen** — at launch if it is the default, at the click if he
    /// switches — and never when Wispr is the one listening.
    func prepare() { bringUpModel() }

    /// **Yes, and by the mechanism that cannot collide.** The file this records
    /// *is* the file it transcribes, so the marker goes **into** it rather than
    /// over him — no mixing, no gap to wait for, no masking. → `ShotMarker`
    var acceptsAudioMarkers: Bool { true }

    /// Splice it between two of his buffers — `MicRecorder.insert(_:)`. The flag
    /// travels to `deliver` on the result, because it is the corpus that has to
    /// know: this WAV contains words he did not say, and its transcript must be
    /// the one that still names them.
    func mark(_ kind: ShotMarker.Kind, index: Int) {
        guard let pcm = ShotMarker.pcm(kind, index: index, in: MicRecorder.fileFormat) else {
            Log.error("marker: no samples for \(kind.rawValue) \(index) — is the clip loaded?")
            return
        }
        // **Into a breath, not into a word** — the same gate the played path has
        // always had, shared since 2026-09-14 (`ShotMarker.afterGap`). Splicing
        // overwrites nothing, so the wait costs only *where* the clip lands, and
        // his own pause is the better place: it does not cut a word in half, and
        // it hands the recogniser a segment boundary it was going to make anyway.
        markersInAudio = true
        ShotMarker.afterGap({ [weak self] in
            (self?.meter.quietSeconds ?? 0) >= ShotMarker.gapNeeded
        }) { [weak self] waited in
            self?.meter.insert(pcm)
            Log.info(String(format: "📣 marker spliced into the recording: %@ %d (%.0f ms for a gap)",
                            kind.words, index, waited * 1000))
        }
    }

    /// Reset at `start()`, because it describes one recording.
    private var markersInAudio = false

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        // **A cold model never delays the microphone** (2026-09-26). It used to
        // refuse here, and `AppDelegate` banked the gesture and opened the
        // microphone ten seconds later (`recordWhenSourceReady`) — ten seconds
        // of a sentence he was already saying, a bank no cancel could reach
        // (TL22, TG3) and a resumed start that forgot what the gesture was
        // (TG4). Now the weights come up beside the recording and the WAV waits
        // for them at the stop (`finishRecording`).
        if !whisper.ready {
            bringUpModel()
            Log.info("🎙️ the local model is not up — recording anyway; the audio waits for it at the stop")
        }
        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        markersInAudio = false
        isRecording = true
        phase = .listening
        Log.info("🎙️ local recording started — \(wav.lastPathComponent)")
        // **Opened on `audioQueue`, never on main** (2026-09-24) — the shape
        // `ElevenLabsSource` has had since 2026-09-19. `MicRecorder.start` and
        // `.stop` are synchronous CoreAudio calls that wait on the engine's own
        // mutex; a device change in flight (the DJI receiver dropping out) holds
        // it, and a cancel on the main thread then froze the whole app.
        audioQueue.async { [weak self] in
            guard let self = self, let why = self.meter.start(to: wav) else { return }
            Log.error("🎙️ local: the microphone would not open — \(why)")
            DispatchQueue.main.async {
                guard self.isRecording else { return }
                self.isRecording = false
                self.phase = .done("error")
                self.didEnd?(.failed(why: why, audio: nil, duration: 0))
            }
        }
        didBegin?()
        return nil
    }

    /// Open, stop and cancel all go through it, in order — a close queued
    /// behind an open cannot overtake it.
    private let audioQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.local-mic")

    func stop() {
        guard isRecording else { return }
        isRecording = false
        phase = .transcribing("")
        // Before the relay hears the close: everything that times the wait from
        // here on asks `DecodeRate` about this engine (2026-09-23).
        DecodeRate.activeEngine = DecodeRate.whisperLocal
        didStopListening?()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let closed = self.meter.stop()
            DispatchQueue.main.async { self.finishRecording(closed) }
        }
    }

    /// The tail of `stop()`, on the main queue, exactly as it always ran.
    private func finishRecording(_ closed: (url: URL, duration: TimeInterval)?) {
        guard let (wav, duration) = closed else {
            Log.info("local recording discarded — under \(MicRecorder.minimumDuration)s")
            phase = .done("empty")
            didEnd?(.silent(""))
            return
        }
        Log.info(String(format: "🎙️ local recording stopped — %.1fs", duration))
        let decode = Decode(wav: wav, duration: duration)
        decoding = decode
        // **The audio waits for the model, not the other way round** — see
        // `start()`. Registered in `decoding` first, so a cancel in the wait
        // disowns it exactly as it disowns a decode (batch 1's R2).
        whenModelUp(decode) { [weak self] in self?.decodeNow(decode) }
    }

    /// Up to `modelWait`, polled on main (the load's own completion is
    /// `bringUpModel`'s, and the gesture's start already asked for it). A load
    /// that ends without the weights is tried once more, then the sentence ends
    /// `.failed` with the WAV for *Recover*. The chip says `Transcribing...`
    /// throughout; only the log and `phaseStatus` say what it is waiting on.
    static let modelWait: TimeInterval = 90

    private func whenModelUp(_ decode: Decode, _ go: @escaping () -> Void) {
        guard !whisper.ready else { return go() }
        phase = .transcribing("loading the model")
        Log.info(String(format: "⏳ the local model is not up yet — the %.1fs recording waits for it (up to %.0f s)",
                        decode.duration, Self.modelWait))
        let asked = Date()
        var retried = false
        func poll() {
            guard !decode.cancelled else { return }
            if whisper.ready {
                Log.info(String(format: "⏳ the local model came up %.1f s after the stop — decoding", Date().timeIntervalSince(asked)))
                phase = .transcribing("")
                return go()
            }
            if !loading {
                // The load ended without the weights (or none was running).
                guard !retried else {
                    return fail(decode, lastLoadFailure.map { "the local model could not be loaded — \($0)" }
                                    ?? "the local model could not be loaded")
                }
                retried = true
                bringUpModel()
            }
            guard Date().timeIntervalSince(asked) < Self.modelWait else {
                return fail(decode, "the local model did not come up in \(Int(Self.modelWait)) s")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() }
        }
        poll()
    }

    private func fail(_ decode: Decode, _ why: String) {
        if decoding === decode { decoding = nil }
        Log.error("local recording not transcribed — \(why); the audio is kept")
        phase = .done("error")
        didEnd?(.failed(why: why, audio: decode.wav, duration: decode.duration))
    }

    private func decodeNow(_ decode: Decode) {
        guard !decode.cancelled else { return }
        let wav = decode.wav, duration = decode.duration
        // What this decode actually costs, against the audio it was handed — the
        // pair `DecodeRate` learns the countdown's factor from. Started here
        // rather than inside `LocalWhisper`, because what the row promised covers
        // the whole round trip: the JSON out, the helper's answer, and the queue
        // hop back. **After the wait for the weights**, which is not a decode.
        let decodeStartedAt = Date()
        whisper.transcribe(wav: wav.path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.decoding === decode { self.decoding = nil }
                guard !decode.cancelled else {
                    Log.info("🗑️ the local model answered a cancelled decode — dropped")
                    return
                }
                guard let r = result, !r.text.isEmpty else {
                    // **The WAV is kept** (2026-09-26, §3.8): an empty answer and
                    // a helper that answered nothing (dead, hung, timed out) are
                    // the same sentence lost if the file goes — so `.failed` with
                    // the audio, staged for *Recover*, where it used to be
                    // `.silent("No words detected")` and `removeItem`.
                    let why = result == nil ? (self.whisper.lastFailure ?? "the local model gave no answer")
                                            : DictationEnd.heardNothing
                    Log.error("local recording produced no transcript — \(why); the audio is kept")
                    // **A helper that died or overran its budget is replaced now**
                    // (2026-09-26, TL31), not at the next gesture: `readLine`
                    // killed it, and the next sentence should find it warming.
                    if result == nil, !self.whisper.ready { self.bringUpModel() }
                    self.phase = .done("empty")
                    self.didEnd?(.failed(why: why, audio: wav, duration: duration))
                    return
                }
                Log.info(String(format: "local whisper: %@ (%.2f, cr %.2f) — %d chars",
                                r.language ?? "?", r.avgLogprob, r.compressionRatio, r.text.count))
                // Filed on the success path only: a decode that returned nothing
                // says nothing about how long a decode takes.
                DecodeRate.record(audio: duration, decode: Date().timeIntervalSince(decodeStartedAt),
                                  chars: r.text.count, compression: r.compressionRatio)
                self.didTranscribe?(DictationResult(
                    text: r.text, language: r.language, audio: wav, duration: duration,
                    engine: "whisper-local", warning: Self.warning(for: r), delivery: .route,
                    via: "local-whisper", markersInAudio: self.markersInAudio,
                    engineLabel: Self.modelLabel))
                self.phase = .done("formatted")
                self.didEnd?(.delivered)
            }
        }
    }

    /// **The decode in flight, and the way to disown it** (2026-09-26, R2 — the
    /// same as `ElevenLabsSource.Upload`). The helper cannot be interrupted, so a
    /// cancel after the close marks this, ends the sentence `.cancelled` with the
    /// WAV for *Recover*, and the answer is dropped when it comes. Main queue only.
    private final class Decode {
        let wav: URL
        let duration: TimeInterval
        var cancelled = false
        init(wav: URL, duration: TimeInterval) { self.wav = wav; self.duration = duration }
    }
    private var decoding: Decode?

    func cancel() {
        if !isRecording, let d = decoding {
            decoding = nil
            d.cancelled = true
            phase = .done("dismissed")
            didEnd?(.cancelled(audio: d.wav, duration: d.duration))
            return
        }
        guard isRecording else { return }
        isRecording = false
        phase = .done("dismissed")
        didStopListening?()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let taken = self.meter.stop()
            DispatchQueue.main.async {
                self.didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
            }
        }
    }

    // MARK: - The model

    /// **Two gates, and the second one is not a second threshold on the first.**
    /// A hallucination is the model unsure and fluent, which is what
    /// `avg_logprob` sees; a loop is the model certain and stuck, which it
    /// cannot see and `compression_ratio` can. Neither is allowed to swallow the
    /// dictation — there is one reading of this audio and the alternative to a
    /// shaky transcript is silence, the one outcome Victor cannot notice and
    /// correct — so both come back as a note under the words.
    private static func warning(for r: LocalWhisper.Result) -> String? {
        if r.compressionRatio > LocalWhisper.loopCeiling {
            return String(format: "⚠️ the model looped (%.1f) — check what was sent", r.compressionRatio)
        }
        if r.avgLogprob < LocalWhisper.confidenceFloor {
            return String(format: "⚠️ low confidence %.2f — check what was sent", r.avgLogprob)
        }
        return nil
    }

    /// Why the last load ended without the weights — the banner of a sentence
    /// that waited for them (`whenModelUp`).
    private var lastLoadFailure: String?

    func bringUpModel() {
        guard !loading, !whisper.ready else { return }
        loading = true
        onLoadingChanged?(true)
        whisper.start { [weak self] why in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.onLoadingChanged?(false)
                self.lastLoadFailure = why
                if let why { Log.error("local model did not come up — \(why)") }
                else { Log.info("local model ready — \(self.whisper.modelName ?? "?")") }
            }
        }
    }

    /// `GET /engine`, unchanged in shape: which model is loaded and whether it
    /// is ready.
    /// Gap G4: a signal to the helper, and a replacement of it.
    @discardableResult
    func signalHelper(_ sig: Int32) -> Bool { whisper.signalHelper(sig) }
    func restartHelper() {
        whisper.stop()
        loading = false
        bringUpModel()
    }

    func describe() -> [String: Any] {
        var out: [String: Any] = ["ready": whisper.ready, "loading": loading,
                                  "alive": whisper.alive, "pid": whisper.pid.map { Int($0) } ?? NSNull()]
        if let m = whisper.modelName { out["model"] = m }
        if let b = whisper.footprintBytes { out["bytes"] = b }
        return out
    }

    /// **Let the ~2.5 GB go on the way out.** It would go anyway — the helper
    /// sees EOF on stdin when the relay's pipes close and exits on its own,
    /// measured at nine seconds even after a SIGKILL — but nine seconds of a
    /// model nobody is using is nine seconds of a laptop that is not his.
    func shutDown() { whisper.stop() }

    /// The five-minute recovery's re-read. The one place outside `stop()` that
    /// still asks the model for anything.
    func transcribe(wav: String, _ done: @escaping (LocalWhisper.Result?) -> Void) {
        whisper.transcribe(wav: wav, done)
    }
}
