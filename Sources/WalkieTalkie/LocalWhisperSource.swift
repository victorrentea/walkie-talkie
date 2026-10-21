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

    // MARK: - Live captions (2026-10-05) — see `LocalLiveCaption`

    private lazy var live: LocalLiveCaption = {
        let l = LocalLiveCaption(meter: meter)
        l.onCaption = { [weak self] committed, partial in self?.didHearLive?(committed, partial, false) }
        return l
    }()
    var streamsLive: Bool { LocalLive.isOn }
    /// **Set by `AppDelegate` while this is the engine, nilled when it stops
    /// being one** (`setEngine` / `swapSource`) — which is also when the live
    /// helper's second copy of the weights is let go: a caption nobody can see
    /// is not worth ~2 GB.
    var didHearLive: ((_ committed: String, _ partial: String, _ gentle: Bool) -> Void)? {
        didSet { if didHearLive == nil { live.shutDown() } }
    }
    var didOpenLive: (() -> Void)?
    private(set) var liveOpen = false
    var liveHelperDescription: [String: Any] {
        ["on": LocalLive.isOn, "ready": live.ready, "active": live.active, "pid": live.whisper.pid.map { Int($0) } ?? NSNull()]
    }
    /// The menu's switch moved: up or down with it.
    func liveSettingChanged() {
        if !LocalLive.isOn { live.end(); live.shutDown() }
        else if didHearLive != nil { live.warm() }   // only while this is the engine
    }

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
    /// The model's one name (`WhisperModels.Option.title`, 2026-10-07) — what
    /// the prompt panel's `Local Whisper (…)` line says.
    static var modelLabel: String { WhisperModels.displayName(configuredModel) }

    /// Since 2026-10-03 the pick from the Engine list (`WhisperModels.selected`),
    /// which falls back to `RELAY_WHISPER_MODEL` and then the published turbo.
    static var configuredModel: String { WhisperModels.selected }
    /// The model's one name — `WhisperModels.Option.title`.
    var displayModelName: String { WhisperModels.displayName(whisper.modelName ?? Self.configuredModel) }
    /// The id the running helper reported — nil while it is down.
    var loadedModel: String? { whisper.modelName }
    var isLoading: Bool { loading }
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
    func prepare() {
        bringUpModel()
        live.warm()
    }

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

    /// **The file this decodes is the file this recorded** (2026-10-04) — so a
    /// shutter press and a word's `start` from the helper are two readings of
    /// one ruler, exactly as on `ElevenLabsSource`. Until this the local engine
    /// answered the protocol's default nil: no cue was ever reserved and every
    /// picture of 135 local dictations went to the footer.
    /// → `MicRecorder.offset(of:)`, `ShotMarker.place`
    func audioOffset(of moment: Date) -> TimeInterval? { meter.offset(of: moment) }

    /// **Whether this take's decode should carry word timings** — asked at the
    /// decode; `AppDelegate` answers *a marker was cued*. They cost +45 % decode
    /// time (60 clips, `evals/local-word-timing/`), so a take with no picture,
    /// highlight or pick does not pay for them.
    var wantsWordTimings: (() -> Bool)?

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
        // **A take of its own** (Q12 for the local model, 2026-10-21): an
        // earlier take may still be decoding — the relay keeps the order.
        Self.takeSerial += 1
        take = Self.takeSerial
        let job = Job(take: take)
        recordingJob = job
        DecodeRate.noteLeft(nil)
        phase = .listening
        // Known now, before `didBegin`: the relay opens the band on it. The
        // caption itself starts once the microphone is open (below) — before
        // that `takeEnd` is still the last take's.
        liveOpen = LocalLive.isOn && live.ready
        if LocalLive.isOn && !live.ready {
            live.warm()
            Log.info("💬 live: the live helper is not up — no caption for this sentence")
        }
        Log.info("🎙️ local recording started — \(wav.lastPathComponent) (take \(take)"
                 + (unanswered.isEmpty ? ")" : ", \(unanswered.count) earlier still decoding)"))
        // **Opened on `audioQueue`, never on main** (2026-09-24) — the shape
        // `ElevenLabsSource` has had since 2026-09-19. `MicRecorder.start` and
        // `.stop` are synchronous CoreAudio calls that wait on the engine's own
        // mutex; a device change in flight (the DJI receiver dropping out) holds
        // it, and a cancel on the main thread then froze the whole app.
        let withCaption = liveOpen
        let t = take
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            guard let why = self.meter.start(to: wav) else {
                DispatchQueue.main.async {
                    guard self.isRecording, self.take == t else { return }
                    // `takeEnd` is this take's from here on.
                    job.open = true
                    if withCaption {
                        self.live.begin()
                        self.didOpenLive?()
                    }
                }
                return
            }
            Log.error("🎙️ local: the microphone would not open — \(why)")
            DispatchQueue.main.async {
                guard self.isRecording, self.take == t else { return }
                self.isRecording = false
                self.recordingJob = nil
                self.settlePhase(.done("error"))
                self.answer(t) { self.didEnd?(.failed(why: why, audio: nil, duration: 0)) }
            }
        }
        startChunkWatch()
        didBegin?()
        return nil
    }

    /// Open, stop and cancel all go through it, in order — a close queued
    /// behind an open cannot overtake it.
    private let audioQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.local-mic")

    func stop() {
        guard isRecording, let job = recordingJob else { return }
        // **First**: a window still decoding is killed before the final decode
        // is even asked for (Victor: *"instantaneu anulezi orice"*).
        live.end()
        liveOpen = false
        isRecording = false
        recordingJob = nil
        stopChunkWatch()
        phase = .transcribing("")
        let t = job.take
        unanswered.insert(t)
        jobs[t] = job
        job.stoppedAt = Date()
        job.markers = markersInAudio
        // Before the relay hears the close: everything that times the wait from
        // here on asks `DecodeRate` about this engine (2026-09-23) — and, for a
        // chunked take, about what is left of it, not the whole (2026-10-21).
        DecodeRate.activeEngine = DecodeRate.whisperLocal
        if !job.pieces.isEmpty {
            let tail = Double(max(0, meter.takeEnd - job.lastCut)) / Self.rate
            let owed = job.pieces.filter { !$0.answered }.reduce(0) { $0 + $1.seconds }
            job.leftAtStop = tail + owed
            DecodeRate.noteLeft(tail + owed)
        }
        didStopListening?()
        let from = job.lastCut
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let closed = self.meter.stop()
            // **The tail, read here** — on the queue that closed the take and
            // before a next take's `start` (queued behind this) resets `take`.
            let end = self.meter.takeEnd
            let tail = job.pieces.isEmpty ? [] : self.meter.takeSlice(from: from, to: end)
            let hops = job.pieces.isEmpty ? [] : self.meter.meterHops
            DispatchQueue.main.async {
                self.finishRecording(closed, job: job, tail: tail, tailEnd: end, hops: hops)
            }
        }
    }

    /// The tail of `stop()`, on the main queue, exactly as it always ran.
    private func finishRecording(_ closed: (url: URL, duration: TimeInterval)?, job: Job,
                                 tail: [Int16], tailEnd: Int, hops: [MeterHop]) {
        let t = job.take
        guard let (wav, duration) = closed else {
            Log.info("local recording discarded — under \(MicRecorder.minimumDuration)s")
            jobs[t] = nil
            job.cancelled = true
            job.dropPieces()
            answer(t) { settlePhase(.done("empty")); didEnd?(.silent("")) }
            return
        }
        job.wav = wav
        job.duration = duration
        guard !job.cancelled else { return }
        Log.info(String(format: "🎙️ local recording stopped — %.1fs (take %d)", duration, t))
        // **Chunked** (2026-10-21): the pieces already asked for, plus the tail.
        if !job.pieces.isEmpty {
            let expected = tailEnd - job.lastCut
            let tailVoiced = ChunkPlanner.voiced(hops, from: Double(job.lastCut) / Self.rate)
            if tail.count != expected || job.markers {
                // A tail no longer in memory (the take's 120 s cap) or a marker
                // spliced into the file: the WAV is the only whole truth.
                Log.info("✂️ local: the chunks are let go — "
                         + (job.markers ? "a marker was spliced into the WAV" : "the tail is not in memory any more")
                         + "; the whole take is decoded")
                job.dropPieces()
            } else if tailVoiced < Self.tailVoicedFloor {
                Log.info(String(format: "✂️ local: the %.1f s tail has %.2f s voiced — not decoded",
                                Double(tail.count) / Self.rate, tailVoiced))
                job.tailDone = true
                assembleIfDone(job)
                return
            } else {
                Log.info(String(format: "✂️ local: %d chunk(s) asked for while he spoke; %.1f s tail to go "
                                + "(%.2f s voiced), %.1f s still owed in all",
                                job.pieces.count, Double(tail.count) / Self.rate, tailVoiced, job.leftAtStop))
                whenModelUp(job) { [weak self] in
                    guard let self else { return }
                    self.ask(job, samples: tail, from: job.lastCut, words: self.wantsWordTimings?() ?? false, isTail: true)
                }
                return
            }
        }
        // **The audio waits for the model, not the other way round** — see
        // `start()`. Registered in `jobs` first, so a cancel in the wait
        // disowns it exactly as it disowns a decode (batch 1's R2).
        whenModelUp(job) { [weak self] in self?.decodeNow(job) }
    }

    /// Up to `modelWait`, polled on main (the load's own completion is
    /// `bringUpModel`'s, and the gesture's start already asked for it). A load
    /// that ends without the weights is tried once more, then the sentence ends
    /// `.failed` with the WAV for *Recover*. The chip says `Transcribing...`
    /// throughout; only the log and `phaseStatus` say what it is waiting on.
    static let modelWait: TimeInterval = 90

    private func whenModelUp(_ job: Job, _ go: @escaping () -> Void) {
        guard !whisper.ready else { return go() }
        phase = .transcribing("loading the model")
        Log.info(String(format: "⏳ the local model is not up yet — the %.1fs recording waits for it (up to %.0f s)",
                        job.duration, Self.modelWait))
        let asked = Date()
        var retried = false
        func poll() {
            guard !job.cancelled else { return }
            if whisper.ready {
                Log.info(String(format: "⏳ the local model came up %.1f s after the stop — decoding", Date().timeIntervalSince(asked)))
                if !isRecording { phase = .transcribing("") }
                return go()
            }
            if !loading {
                // The load ended without the weights (or none was running).
                guard !retried else {
                    return fail(job, lastLoadFailure.map { "the local model could not be loaded — \($0)" }
                                    ?? "the local model could not be loaded")
                }
                retried = true
                bringUpModel()
            }
            guard Date().timeIntervalSince(asked) < Self.modelWait else {
                return fail(job, "the local model did not come up in \(Int(Self.modelWait)) s")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { poll() }
        }
        poll()
    }

    private func fail(_ job: Job, _ why: String) {
        guard jobs[job.take] === job else { return }
        jobs[job.take] = nil
        job.dropPieces()
        Log.error("local recording not transcribed — \(why); the audio is kept")
        answer(job.take) {
            settlePhase(.done("error"))
            didEnd?(.failed(why: why, audio: job.wav, duration: job.duration))
        }
    }

    private func decodeNow(_ job: Job) {
        guard !job.cancelled, let wav = job.wav else { return }
        let duration = job.duration
        // What this decode actually costs, against the audio it was handed — the
        // pair `DecodeRate` learns the countdown's factor from. Started here
        // rather than inside `LocalWhisper`, because what the row promised covers
        // the whole round trip: the JSON out, the helper's answer, and the queue
        // hop back. **After the wait for the weights**, which is not a decode.
        let decodeStartedAt = Date()
        whisper.transcribe(wav: wav.path, words: wantsWordTimings?() ?? false) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                // The live helper, if the close killed it, comes back now that
                // the sentence's own decode is over.
                self.live.warmLater()
                guard !job.cancelled, self.jobs[job.take] === job else {
                    Log.info("🗑️ the local model answered a cancelled decode — dropped")
                    return
                }
                self.jobs[job.take] = nil
                if let r = result, !r.text.isEmpty {
                    // Filed on the success path only: a decode that returned nothing
                    // says nothing about how long a decode takes.
                    DecodeRate.record(audio: duration, decode: Date().timeIntervalSince(decodeStartedAt),
                                      chars: r.text.count, compression: r.compressionRatio)
                }
                self.answered(job, result)
            }
        }
    }

    /// One take's words — whole or assembled from its chunks — on main.
    private func answered(_ job: Job, _ result: LocalWhisper.Result?) {
        let t = job.take
        guard let wav = job.wav else { return }
        let duration = job.duration
        guard let r = result, !r.text.isEmpty else {
            // **The WAV is kept** (2026-09-26, §3.8): an empty answer and
            // a helper that answered nothing (dead, hung, timed out) are
            // the same sentence lost if the file goes — so `.failed` with
            // the audio, staged for *Recover*, where it used to be
            // `.silent("No words detected")` and `removeItem`.
            let why = result == nil ? (whisper.lastFailure ?? "the local model gave no answer")
                                    : DictationEnd.heardNothing
            Log.error("local recording produced no transcript — \(why); the audio is kept")
            // **A helper that died or overran its budget is replaced now**
            // (2026-09-26, TL31), not at the next gesture: `readLine`
            // killed it, and the next sentence should find it warming.
            if result == nil, !whisper.ready { bringUpModel() }
            answer(t) {
                settlePhase(.done("empty"))
                didEnd?(.failed(why: why, audio: wav, duration: duration))
            }
            return
        }
        Log.info(String(format: "local whisper: %@ (%.2f, cr %.2f) — %d chars",
                        r.language ?? "?", r.avgLogprob, r.compressionRatio, r.text.count)
                 + Self.coverageNote(r.coverage))
        answer(t) {
            didTranscribe?(DictationResult(
                text: r.text, language: r.language, audio: wav, duration: duration,
                engine: "whisper-local", warning: Self.warning(for: r), delivery: .route,
                via: "local-whisper", markersInAudio: job.markers,
                engineLabel: Self.modelLabel, words: r.words))
            settlePhase(.done("formatted"))
            didEnd?(.delivered)
        }
    }

    // MARK: - Takes (Q12 for the local model, 2026-10-21)

    /// **One recording, from its start to its answer.** Main queue only.
    /// `pieces` are the chunks asked for while he was still speaking (and the
    /// tail, last); empty for a take decoded whole.
    private final class Job {
        let take: Int
        var wav: URL?
        var duration: TimeInterval = 0
        var cancelled = false
        var markers = false
        var stoppedAt: Date?
        /// The microphone is open and `takeEnd` is this take's.
        var open = false
        /// Sample index on the take's ruler where the next chunk starts.
        var lastCut = 0
        var pieces: [Piece] = []
        var tailDone = false
        var leftAtStop: TimeInterval = 0
        init(take: Int) { self.take = take }

        /// Chunks abandoned: answers still coming are dropped, files removed.
        func dropPieces() {
            for p in pieces { p.dropped = true; p.removeFile() }
            pieces = []
            tailDone = false
        }
    }

    /// One chunk of a take, cut at a pause and sent to the helper as raw PCM.
    private final class Piece {
        let from: Int
        let to: Int
        let file: URL
        let isTail: Bool
        let askedAt = Date()
        var answered = false
        var dropped = false
        var result: LocalWhisper.Result?
        var seconds: TimeInterval { Double(to - from) / LocalWhisperSource.rate }
        init(from: Int, to: Int, file: URL, isTail: Bool) {
            self.from = from; self.to = to; self.file = file; self.isTail = isTail
        }
        func removeFile() { try? FileManager.default.removeItem(at: file) }
    }

    static let rate = 16000.0
    /// A tail with less speech than this after the last cut is not decoded —
    /// Whisper on near-silence invents a sentence (`www.clu.com.br`).
    static let tailVoicedFloor: TimeInterval = 0.3

    private var recordingJob: Job?
    /// Every take stopped and not answered yet, by take.
    private var jobs: [Int: Job] = [:]
    private(set) var take = 0
    private static var takeSerial = 0
    private(set) var answeringTake: Int?
    private var unanswered: Set<Int> = []
    var answersPending: Int { unanswered.count }
    func isPending(take t: Int) -> Bool { unanswered.contains(t) || jobs[t] != nil }
    /// **The local model takes the next sentence while the last one decodes**
    /// (2026-10-21, Victor: *"the ability to record immediately another … even
    /// though you are currently transcribing the old snippet"*). The recording
    /// is ours and the helper queues requests, so nothing here stops a second
    /// take; `WT_LOCAL_QUEUE=0` puts the one-at-a-time rule back.
    let queuesSentences: Bool = {
        let v = ProcessInfo.processInfo.environment["WT_LOCAL_QUEUE"] ?? ElevenLabsSource.fileValue("WT_LOCAL_QUEUE")
        return v != "0"
    }()

    /// Runs one take's `didTranscribe` / `didEnd`, labelled with the take.
    private func answer(_ t: Int, _ body: () -> Void) {
        let outer = answeringTake
        answeringTake = t
        unanswered.remove(t)
        body()
        answeringTake = outer
    }

    /// `phase` after one take's answer: another take still recording or
    /// decoding keeps its own phase.
    private func settlePhase(_ p: DictationPhase) {
        if isRecording { return }
        if !jobs.isEmpty || !unanswered.isEmpty { phase = .transcribing(""); return }
        phase = p
    }

    func cancelTake(_ t: Int) {
        if isRecording, t == take { return cancel() }
        guard let job = jobs[t] else { return }
        disown(job)
    }

    private func disown(_ job: Job) {
        jobs[job.take] = nil
        job.cancelled = true
        job.dropPieces()
        answer(job.take) {
            settlePhase(.done("dismissed"))
            didEnd?(.cancelled(audio: job.wav, duration: job.duration))
        }
    }

    func cancel() {
        live.end()
        liveOpen = false
        if !isRecording {
            // **The microphone is shut and the words are on their way** — the
            // newest take in flight is this sentence now, and a cancel disowns it.
            if let t = jobs.keys.max(), let job = jobs[t] { disown(job) }
            return
        }
        guard let job = recordingJob else { return }
        isRecording = false
        recordingJob = nil
        stopChunkWatch()
        job.cancelled = true
        job.dropPieces()
        let t = job.take
        settlePhase(.done("dismissed"))
        didStopListening?()
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let taken = self.meter.stop()
            DispatchQueue.main.async {
                self.answer(t) { self.didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0)) }
            }
        }
    }

    // MARK: - Chunks: decoding while he still speaks (2026-10-21)

    /// `WT_LOCAL_CHUNKS=0` decodes every take whole, as before.
    static var chunksOn: Bool {
        (ProcessInfo.processInfo.environment["WT_LOCAL_CHUNKS"] ?? ElevenLabsSource.fileValue("WT_LOCAL_CHUNKS")) != "0"
    }
    private var chunkTimer: Timer?
    private var chunkTuning = ChunkPlanner.Tuning()

    private func startChunkWatch() {
        stopChunkWatch()
        guard Self.chunksOn else { return }
        chunkTuning = ChunkPlanner.Tuning.configured
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.chunkTick() }
        RunLoop.main.add(t, forMode: .common)
        chunkTimer = t
    }

    private func stopChunkWatch() {
        chunkTimer?.invalidate()
        chunkTimer = nil
    }

    /// Every 0.5 s while recording: is there a pause worth cutting at?
    private func chunkTick() {
        guard isRecording, let job = recordingJob, job.open, !markersInAudio, whisper.ready else { return }
        let end = meter.takeEnd
        let now = Double(end) / Self.rate
        let from = Double(job.lastCut) / Self.rate
        guard now - from >= chunkTuning.trigger else { return }
        let hops = meter.meterHops
        guard let cut = ChunkPlanner.cut(hops: hops, from: from, now: now, tuning: chunkTuning) else { return }
        let to = min(end, Int(cut * Self.rate))
        let samples = meter.takeSlice(from: job.lastCut, to: to)
        guard samples.count == to - job.lastCut else {
            // Older than the take's 120 s in memory: no chunks for this take.
            Log.info("✂️ local: the audio since the last cut is no longer all in memory — chunks off for this take")
            job.dropPieces()
            stopChunkWatch()
            return
        }
        let voiced = ChunkPlanner.voiced(hops, from: from, to: cut)
        Log.info(String(format: "✂️ local: chunk %d cut at %.1f s — %.1f s of audio, %.1f s voiced, decoding while he speaks",
                        job.pieces.count + 1, cut, cut - from, voiced))
        ask(job, samples: samples, from: job.lastCut, words: true, isTail: false)
        job.lastCut = to
    }

    /// One chunk to the helper. Background chunks always carry word timings —
    /// a shutter pressed later must still find words around its moment, and
    /// their cost is paid while he speaks; the tail asks only with a cue.
    private func ask(_ job: Job, samples: [Int16], from: Int, words: Bool, isTail: Bool) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkie-chunk-\(job.take)-\(job.pieces.count).pcm")
        do {
            try samples.withUnsafeBufferPointer { try Data(buffer: $0).write(to: file) }
        } catch {
            Log.error("✂️ local: could not write a chunk — \(error.localizedDescription); the whole take will be decoded")
            if isTail { job.dropPieces(); decodeNow(job) } else { job.dropPieces(); stopChunkWatch() }
            return
        }
        let piece = Piece(from: from, to: from + samples.count, file: file, isTail: isTail)
        job.pieces.append(piece)
        if isTail { job.tailDone = true }
        whisper.transcribe(wav: file.path, words: words, pcm: true) { [weak self] result in
            DispatchQueue.main.async {
                piece.removeFile()
                guard let self, !piece.dropped, !job.cancelled else { return }
                piece.answered = true
                piece.result = result
                Log.info(String(format: "✂️ local: chunk %@ of take %d answered in %.1f s — %@",
                                isTail ? "tail" : "\(job.pieces.firstIndex { $0 === piece }.map { $0 + 1 } ?? 0)",
                                job.take, Date().timeIntervalSince(piece.askedAt),
                                result.map { "\($0.text.count) chars" } ?? "no answer"))
                if !isTail { self.live.warmLater() }
                self.assembleIfDone(job)
            }
        }
    }

    /// Once the take is stopped and every piece has answered: the words, in
    /// order. A piece that failed sends the whole WAV to the model instead —
    /// a chunk is a speed-up, never a reason to lose a sentence.
    private func assembleIfDone(_ job: Job) {
        guard job.wav != nil, job.tailDone, !job.cancelled, jobs[job.take] === job,
              job.pieces.allSatisfy({ $0.answered }) else { return }
        let results = job.pieces.compactMap { $0.result }
        guard results.count == job.pieces.count else {
            Log.error("✂️ local: a chunk of take \(job.take) got no answer — decoding the whole take")
            job.dropPieces()
            // **Through the wait for the weights** (2026-10-21, found in the lab): a
            // chunk with no answer is most often a helper killed at its 300 s budget,
            // so `ready` is false here and a bare `decodeNow` failed at once — the
            // take went to Recover instead of being decoded whole.
            return whenModelUp(job) { [weak self] in self?.decodeNow(job) }
        }
        jobs[job.take] = nil
        let waited = job.stoppedAt.map { Date().timeIntervalSince($0) } ?? 0
        let r = Self.join(job.pieces.map { ($0.result!, Double($0.from) / Self.rate) })
        if !r.text.isEmpty, job.leftAtStop > 0 {
            // The wait he saw, against what was left at the stop — the line the
            // chip's estimate for a chunked take is read from (`noteLeft`).
            DecodeRate.record(audio: job.leftAtStop, decode: waited, chars: r.text.count,
                              compression: r.compressionRatio)
        }
        Log.info(String(format: "✂️ local: take %d assembled from %d piece(s) — %.1f s after the stop "
                        + "(%.1f s of %.1f were left to decode)",
                        job.take, job.pieces.count, waited, job.leftAtStop, job.duration))
        live.warmLater()
        answered(job, r)
    }

    /// The pieces' answers as one: texts joined with a space, words moved onto
    /// the take's ruler (only if every piece has them), the worst confidence and
    /// the worst loop, the language of the longest piece.
    static func join(_ parts: [(LocalWhisper.Result, TimeInterval)]) -> LocalWhisper.Result {
        let texts = parts.map { $0.0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let text = texts.joined(separator: " ")
        var words: [TimedWord]? = []
        for (r, offset) in parts {
            guard let w = r.words else { words = nil; break }
            if !(words?.isEmpty ?? true), let first = w.first, !first.text.hasPrefix(" ") {
                words?.append(TimedWord(text: " ", start: offset, end: offset, isSpacing: true))
            }
            words?.append(contentsOf: w.map {
                TimedWord(text: $0.text, start: $0.start + offset, end: $0.end + offset, isSpacing: $0.isSpacing)
            })
        }
        if let w = words, w.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) != text {
            words = nil
        }
        let longest = parts.max { $0.0.text.count < $1.0.text.count }?.0
        return LocalWhisper.Result(
            text: text, language: longest?.language,
            avgLogprob: parts.map { $0.0.avgLogprob }.min() ?? 0,
            compressionRatio: parts.map { $0.0.compressionRatio }.max() ?? 0,
            coverage: nil,
            words: words.flatMap { $0.isEmpty ? nil : $0 })
    }

    // MARK: - The model

    /// **Two gates, and the second one is not a second threshold on the first.**
    /// A hallucination is the model unsure and fluent, which is what
    /// `avg_logprob` sees; a loop is the model certain and stuck, which it
    /// cannot see and `compression_ratio` can. Neither is allowed to swallow the
    /// dictation — there is one reading of this audio and the alternative to a
    /// shaky transcript is silence, the one outcome Victor cannot notice and
    /// correct — so both come back as a note under the words.
    /// ` · 3 segments over 31.0 of 35.4 s, longest gap 2.6 s at 8.6 s` — the
    /// numbers that tell a transcript missing its middle from one that is only
    /// short (2026-09-29: Victor saw a middle go missing; nothing logged where
    /// the words came from). `(retried without the prompt)` when a loop was redone.
    static func coverageNote(_ c: [String: Any]?) -> String {
        guard let c, let dur = c["duration"] as? Double else { return "" }
        var note = String(format: " · %d segments over %.1f of %.1f s, longest gap %.1f s at %.1f s",
                          (c["segments"] as? Int) ?? 0, (c["covered"] as? Double) ?? 0, dur,
                          (c["gap"] as? Double) ?? 0, (c["gap_at"] as? Double) ?? 0)
        if let t = c["temperature"] as? Double, t > 0 { note += String(format: ", temperature %.1f", t) }
        if (c["retried"] as? Bool) == true { note += " (looped; retried without the prompt)" }
        if let cut = c["cut"] as? Int, cut > 0 { note += " · loop cut: \(cut) chars" }
        return note
    }

    private static func warning(for r: LocalWhisper.Result) -> String? {
        // The helper cuts a loop out of the words (`cut_loops`, 2026-10-04) — what
        // is left reads, but whatever was said under the loop is not in it.
        if let cut = r.coverage?["cut"] as? Int, cut > 0 {
            return String(format: "⚠️ the model looped (%.1f) — the repeats were cut, check what was sent", r.compressionRatio)
        }
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
        if didHearLive != nil { live.restart() }
    }

    func describe() -> [String: Any] {
        var out: [String: Any] = ["ready": whisper.ready, "loading": loading,
                                  "alive": whisper.alive, "pid": whisper.pid.map { Int($0) } ?? NSNull()]
        if let m = whisper.modelName { out["model"] = m }
        if let b = whisper.footprintBytes { out["bytes"] = b }
        out["live"] = liveHelperDescription
        return out
    }

    /// **Let the ~2.5 GB go on the way out.** It would go anyway — the helper
    /// sees EOF on stdin when the relay's pipes close and exits on its own,
    /// measured at nine seconds even after a SIGKILL — but nine seconds of a
    /// model nobody is using is nine seconds of a laptop that is not his.
    func shutDown() {
        whisper.stop()
        live.shutDown()
    }

    /// The five-minute recovery's re-read. The one place outside `stop()` that
    /// still asks the model for anything.
    func transcribe(wav: String, words: Bool = false, _ done: @escaping (LocalWhisper.Result?) -> Void) {
        whisper.transcribe(wav: wav, words: words, done)
    }
}
