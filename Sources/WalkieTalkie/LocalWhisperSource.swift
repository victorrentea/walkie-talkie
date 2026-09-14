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
    /// business and is why nothing here is ever `warming`: `start()` refuses on a
    /// cold model rather than opening a dictation against one.
    private(set) var phase: DictationPhase = .idle

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
        meter.insert(pcm)
        markersInAudio = true
        Log.info("📣 marker spliced into the recording: \(kind.words) \(index)")
    }

    /// Reset at `start()`, because it describes one recording.
    private var markersInAudio = false

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard whisper.ready else {
            bringUpModel()
            return "the local model is still loading"
        }
        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        if let why = meter.start(to: wav) { return why }
        markersInAudio = false
        isRecording = true
        phase = .listening
        Log.info("🎙️ local recording started — \(wav.lastPathComponent)")
        didBegin?()
        return nil
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        phase = .transcribing("")
        didStopListening?()

        guard let (wav, duration) = meter.stop() else {
            Log.info("local recording discarded — under \(MicRecorder.minimumDuration)s")
            phase = .done("empty")
            didEnd?(.silent(""))
            return
        }
        Log.info(String(format: "🎙️ local recording stopped — %.1fs", duration))

        // What this decode actually costs, against the audio it was handed — the
        // pair `DecodeRate` learns the countdown's factor from. Started here
        // rather than inside `LocalWhisper`, because what the row promised covers
        // the whole round trip: the JSON out, the helper's answer, and the queue
        // hop back.
        let decodeStartedAt = Date()
        whisper.transcribe(wav: wav.path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let r = result, !r.text.isEmpty else {
                    Log.error("local recording produced no transcript")
                    try? FileManager.default.removeItem(at: wav)
                    // **`No words detected`, and nothing else** (Victor,
                    // 2026-09-08): what the recogniser did with the audio is the
                    // app's business, and the one thing he acts on is that
                    // nothing was heard.
                    self.phase = .done("empty")
                    self.didEnd?(.silent("No words detected"))
                    return
                }
                Log.info(String(format: "local whisper: %@ (%.2f, cr %.2f) — %d chars",
                                r.language ?? "?", r.avgLogprob, r.compressionRatio, r.text.count))
                // Filed on the success path only: a decode that returned nothing
                // says nothing about how long a decode takes.
                DecodeRate.record(audio: duration, decode: Date().timeIntervalSince(decodeStartedAt))
                self.didTranscribe?(DictationResult(
                    text: r.text, language: r.language, audio: wav, duration: duration,
                    engine: "whisper-local", warning: Self.warning(for: r), delivery: .route,
                    via: "local-whisper", markersInAudio: self.markersInAudio))
                self.phase = .done("formatted")
                self.didEnd?(.delivered)
            }
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        phase = .done("dismissed")
        didStopListening?()
        let taken = meter.stop()
        didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
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

    func bringUpModel() {
        guard !loading, !whisper.ready else { return }
        loading = true
        onLoadingChanged?(true)
        whisper.start { [weak self] why in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.onLoadingChanged?(false)
                if let why { Log.error("local model did not come up — \(why)") }
                else { Log.info("local model ready — \(self.whisper.modelName ?? "?")") }
            }
        }
    }

    /// `GET /engine`, unchanged in shape: which model is loaded and whether it
    /// is ready.
    func describe() -> [String: Any] {
        var out: [String: Any] = ["ready": whisper.ready, "loading": loading]
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
