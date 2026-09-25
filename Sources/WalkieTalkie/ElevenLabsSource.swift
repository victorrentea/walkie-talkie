import Foundation

/// **The relay's own microphone, transcribed in the cloud by ElevenLabs
/// Scribe** — the third recogniser behind `DictationSource` (2026-09-18).
///
/// Its shape is `LocalWhisperSource`'s, deliberately and almost line for line:
/// this app opens the microphone, writes one 16 kHz mono WAV, and hands that
/// file to a recogniser. The only thing swapped out is the recogniser — a
/// `POST` to `api.elevenlabs.io` where the local one has a Python daemon on the
/// other end of a pipe. Everything that follows from *the file is ours* follows
/// here too: markers are **spliced** rather than played, the audio the corpus
/// files is the audio that was transcribed, and there is no second application
/// whose focus, window or paste has to be worked around.
///
/// ## Why a third one at all
///
/// Wispr Flow is the best transcript in this app and cannot be called: it is a
/// desktop application, so the relay drives it by posting its shortcuts and
/// reads its delivery back out of a window it has to park (`WisprFlowSource`,
/// the wrap, the Scratchpad, the swallow — the largest single mechanism in this
/// repo, and all of it is the cost of not having an API). The local model can
/// be called and works offline, and is a bigger step down on Romanian than it
/// is on English.
///
/// Scribe is the middle term: an HTTP call with no wrap behind it, and the one
/// published Romanian number among the hosted recognisers — 3.0% WER on FLEURS,
/// against Whisper large-v3's own results on the same benchmark. What it costs
/// is **the network and $0.40 an hour**, which is why it is a pick and not a
/// default.
///
/// | | this | `LocalWhisperSource` | `WisprFlowSource` |
/// |---|---|---|---|
/// | microphone | ours | ours | Wispr's |
/// | transcript | one HTTPS round trip | a local daemon | a window, a chord and a ⌘V |
/// | markers | spliced into the WAV | spliced into the WAV | played into a Loopback device |
/// | fails when | the network does | never | Wispr changes how it delivers |
///
/// ## The audio is sent off this Mac, and that is the whole of what is new
///
/// Nothing else in this app has ever put Victor's voice on a wire. Two things
/// follow and both are enforced below: the engine is **never** the default
/// (`AppDelegate.source` picks Wispr unless a preference says otherwise, and
/// this one has to be chosen by hand), and a dictation that could not be
/// uploaded **keeps its WAV and says where it is** rather than disappearing —
/// a lost sentence is the one failure Victor cannot see and correct.
final class ElevenLabsSource: DictationSource {

    var name: String { live ? "ElevenLabs Scribe + Live" : "ElevenLabs Scribe" }

    /// **`☁️ ElevenLabs + Live`** (2026-09-25): the same recording, the same
    /// batch transcript delivered, plus `ElevenLabsLive` streaming the buffers
    /// so the chip can show the words while he says them. A second instance
    /// rather than a flag on the one the menu already has, so the pick is a
    /// source like every other and `AppDelegate` never asks which kind it holds.
    let live: Bool
    var streamsLive: Bool { live }
    var didHearLive: ((String) -> Void)?
    /// One per sentence — its committed text belongs to that sentence.
    private var stream: ElevenLabsLive?

    init(live: Bool = false) { self.live = live }

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    let meter = MicRecorder()

    private(set) var isRecording = false
    private(set) var phase: DictationPhase = .idle

    /// **The key, and whether there is one.** `isReady` is the menu's ⏳
    /// question and `start()`'s refusal, and for a recogniser with no weights to
    /// load it is only ever *has he put the key in*. Re-read by `prepare()`, so
    /// the file can be created while the app is running.
    private(set) var apiKey: String?
    var isReady: Bool { apiKey != nil }

    // MARK: - Configuration

    /// **`scribe_v1`, and `scribe_v2` is one environment variable away.**
    ///
    /// v1 is the model the 3.0% Romanian WER was published against, which is the
    /// number this whole source was chosen on; v2 is newer, faster and
    /// documented for 90+ languages rather than 99, with no per-language figures
    /// out for it. Picking the one with the measurement behind it is the same
    /// rule the rest of this repo runs on — and `WT_ELEVEN_MODEL=scribe_v2` is
    /// how the two get compared on Victor's own corpus rather than on a blog.
    static var model: String {
        ProcessInfo.processInfo.environment["WT_ELEVEN_MODEL"]
            ?? config["WT_ELEVEN_MODEL"] ?? "scribe_v1"
    }

    /// **The language is not pinned, on purpose.** Victor dictates Romanian with
    /// English technical words inside it — *"fac un commit pe branch-ul de
    /// test"* — and `language_code: "ro"` tells the recogniser those words are
    /// Romanian too. Auto-detection is what keeps `git rebase` spelled the way
    /// he said it. `WT_ELEVEN_LANG=ro` forces it back for a comparison run.
    static var language: String? {
        ProcessInfo.processInfo.environment["WT_ELEVEN_LANG"] ?? config["WT_ELEVEN_LANG"]
    }

    /// Generous, and still bounded. A minute of 16 kHz mono is 1.9 MB and
    /// uploads in under a second on anything he teaches from; the ceiling is
    /// here for the hotel Wi-Fi that accepts the connection and then stops,
    /// which is the failure that would otherwise hang the settle until
    /// `AppDelegate.settleTimeout` gives up without ever saying why.
    private static let requestTimeout: TimeInterval = 45

    /// **What this engine costs per hour of audio, per model.**
    ///
    /// It is in the menu because the price is half the trade the row exists to
    /// state, and it is a **function of the model** because the two do not cost
    /// the same and the cheaper one is the newer one: `scribe_v2` is $0.22/h
    /// against `scribe_v1`'s $0.40. A hardcoded `$0.40/h` was in this row for
    /// one build and it would have started lying the moment
    /// `WT_ELEVEN_MODEL=scribe_v2` was set — which is exactly the switch the
    /// rest of this file invites him to flip.
    ///
    /// Published rates, not measured ones, and the only numbers in this repo
    /// that can change without anything here changing. **If the row and the
    /// invoice disagree, the invoice is right.**
    static var rate: String {
        switch model {
        case "scribe_v1": return "$0.40/h"
        case "scribe_v2": return "$0.22/h"
        default: return "billed per hour"
        }
    }

    /// **What the menu row and the envelope call it.** The model id rather than
    /// the brand, for `LocalWhisperSource.modelLabel`'s reason: the row's job is
    /// to say what is about to be believed, and two Scribe versions that
    /// disagree about a sentence must not look the same here.
    var displayModelName: String { "Scribe (\(Self.model))" }

    // MARK: - The key

    /// **`~/.walkie-talkie/elevenlabs.env`, and the environment on top of it.**
    ///
    /// A file rather than a variable because this app is a login item: launchd
    /// starts it, so it inherits no shell — the same reason `WT_KEY_TRACE` had
    /// to grow a `POST /test/key-trace` twin. A file rather than the Keychain
    /// because a Keychain item prompts, and the one moment this key is read is
    /// the moment a sentence is waiting on it.
    ///
    /// It follows `--home`, so a test relay pointed at a scratch home does not
    /// quietly bill his account.
    static var configURL: URL { Outbox.home.appendingPathComponent("elevenlabs.env") }

    /// Parsed on every `reloadKey()` — the file is three lines and neither the
    /// menu opening nor an engine pick is a hot path, and re-reading is what
    /// lets him paste the key in without restarting the app.
    private static var config: [String: String] = [:]

    private static func loadConfig() {
        config = [:]
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces)
            guard !row.isEmpty, !row.hasPrefix("#"), let eq = row.firstIndex(of: "=") else { continue }
            let key = String(row[row.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(row[row.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            // Tolerate `KEY="sk_…"`, because that is how a key pasted out of a
            // dashboard usually arrives.
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            config[key] = value
        }
    }

    // MARK: - DictationSource

    /// **There is nothing to warm up, so this is the key check** — and it is the
    /// one the menu's ⏳ and the first gesture of the day both rest on. A
    /// recogniser that will refuse should refuse before he has said anything.
    func prepare() {
        if reloadKey() {
            Log.info("ElevenLabs ready — \(Self.model)"
                     + (Self.language.map { ", language pinned to \($0)" } ?? ", language auto"))
        } else {
            Log.error("ElevenLabs: no API key — put ELEVENLABS_API_KEY=… in \(Self.configURL.path)")
        }
    }

    /// **Re-read the file and answer whether there is a key** — silently,
    /// because this also runs every time the menu bar is opened (`isReady`
    /// through `StatusItem.elevenReady`) and a log line per menu open is a log
    /// nobody can read on the day it matters. `prepare()` is the one that says
    /// it out loud, and it is called when the engine is chosen.
    ///
    /// Re-reading rather than caching from launch is the whole point: the key is
    /// a file Victor creates while the app is running, and a menu that went on
    /// saying *no API key* after he had put one there would send him looking for
    /// a bug in the wrong place.
    @discardableResult
    func reloadKey() -> Bool {
        Self.loadConfig()
        let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            ?? Self.config["ELEVENLABS_API_KEY"]
        apiKey = (key?.isEmpty ?? true) ? nil : key
        return apiKey != nil
    }

    /// **Yes, by the mechanism that cannot collide** — the file this records is
    /// the file it uploads, so the marker goes *into* it. → `ShotMarker`, and
    /// `LocalWhisperSource.mark`, which this is a copy of for the reason that
    /// docstring gives: splicing overwrites nothing, so the only thing the gap
    /// gate buys is *where* the clip lands, and his own pause is the better
    /// place.
    var acceptsAudioMarkers: Bool { true }

    func mark(_ kind: ShotMarker.Kind, index: Int) {
        guard let pcm = ShotMarker.pcm(kind, index: index, in: MicRecorder.fileFormat) else {
            Log.error("marker: no samples for \(kind.rawValue) \(index) — is the clip loaded?")
            return
        }
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

    /// **Yes — the file this uploads is the file this recorded**, so a moment on
    /// the wall clock and a `start` in the reply are two readings of one ruler.
    /// This is the half that makes `ShotMarker.place` possible here and not in
    /// `WisprFlowSource`. → `MicRecorder.offset(of:)`
    func audioOffset(of moment: Date) -> TimeInterval? { meter.offset(of: moment) }

    /// **Where the microphone is opened and closed — off the main thread**
    /// (2026-09-19). `WisprFlowSource` has had this since the day its meter
    /// went in (`meterQueue`, *"`MicRecorder.start(to:)` is a synchronous device
    /// open and it was being run on the edge, in front of the ring"*); this
    /// source did not, because it was never the default and never ran on a
    /// machine whose audio stack was busy.
    ///
    /// **What it costs when it is wrong, measured today**: the relay froze,
    /// whole, on the first gesture after ElevenLabs became the default. `sample`
    /// on the wedged process:
    ///
    /// ```
    /// AppDelegate.startDictation → ElevenLabsSource.start()
    ///   → MicRecorder.start(to:) → -[AVAudioEngine inputNode]
    ///     → dispatch_sync → AVAudioIOUnit queue → AUHALOutputUnit setDeviceID:
    ///       → CoreAudio HALC_ProxyObject::HasProperty → mach_msg  (never returns)
    /// ```
    ///
    /// The main thread was inside CoreAudio waiting on a device bind that never
    /// came back, so every menu, every route and the whole overlay were gone
    /// with it — no crash, no log line, nothing to see. A device open is an IPC
    /// to another daemon and can hang for reasons that have nothing to do with
    /// this app; it may not be on the thread the app is drawn on.
    ///
    /// **The ring does not wait for it**, and never did: this repo's own rule is
    /// that a dictation opens on the *gesture*, the microphone only confirms it
    /// (`speculativeGrace`). So `start()` still answers immediately.
    private let audioQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.eleven-mic")

    /// Written on `audioQueue` only — the stop queued behind an open cannot
    /// overtake it, which is the same reason `WisprFlowSource.recording` lives
    /// on its queue.
    private var opening: URL?

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard apiKey != nil else {
            // Said in full, because the fix is a file he has to create and the
            // relay is the only thing that knows where.
            return "no ElevenLabs API key — see \(Self.configURL.lastPathComponent)"
        }
        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        markersInAudio = false
        isRecording = true
        phase = .listening
        Log.info("🎙️ recording started for ElevenLabs — \(wav.lastPathComponent)")
        var stream: ElevenLabsLive?
        if live, let key = apiKey {
            let opened = ElevenLabsLive()
            opened.onText = { [weak self, weak opened] text in
                guard let self, let opened, self.stream === opened, self.isRecording else { return }
                self.didHearLive?(text)
            }
            opened.start(key: key, language: Self.language)
            stream = opened
        }
        self.stream = stream
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.opening = wav
            // **Set on this queue, never on main** — the setter takes
            // `MicRecorder.lock` (*Never open or close a microphone on the main
            // thread*). Before `start(to:)`, so the first buffer is streamed too.
            if let stream { self.meter.onBuffer = { [weak stream] in stream?.feed($0) } }
            guard let why = self.meter.start(to: wav) else { return }
            // A device that will not open is a sentence that cannot be spoken,
            // and the ring is already up — so it is said out loud rather than
            // left to the settle's timeout.
            Log.error("🎙️ ElevenLabs: the microphone would not open — \(why)")
            self.opening = nil
            self.meter.onBuffer = nil
            stream?.stop()
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

    /// When the microphone closed — what the round trip filed with `DecodeRate`
    /// is measured from.
    private var stoppedAt: Date?

    func stop() {
        guard isRecording else { return }
        isRecording = false
        phase = .transcribing("uploading")
        // Before the relay hears the close — see `DecodeRate.activeEngine` — and
        // the clock the round trip is filed against starts here, at the close,
        // because that is the wait the relay shows (2026-09-23).
        DecodeRate.activeEngine = DecodeRate.elevenLabs
        stoppedAt = Date()
        closeStream()
        didStopListening?()
        // **Closed on the same queue it was opened on** — `MicRecorder.stop()`
        // tears the same audio engine down and can block for the same reason,
        // and a close that overtook its own open would find nothing recording.
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let closed = self.meter.stop()
            self.meter.onBuffer = nil
            self.opening = nil
            DispatchQueue.main.async { self.finishRecording(closed) }
        }
    }

    /// The tail of `stop()`, on the main queue, exactly as it always ran.
    private func finishRecording(_ closed: (url: URL, duration: TimeInterval)?) {
        guard let (wav, duration) = closed else {
            Log.info("recording discarded — under \(MicRecorder.minimumDuration)s")
            phase = .done("empty")
            didEnd?(.silent(""))
            return
        }
        guard let key = apiKey else {
            // Only reachable if the key was taken away mid-sentence — and the
            // audio still stays, for `finishWithFailure`'s reason.
            finishWithFailure(wav, duration, "the ElevenLabs key went away mid-sentence")
            return
        }
        Log.info(String(format: "🎙️ recording stopped — %.1fs, uploading to ElevenLabs", duration))

        let startedAt = Date()
        Self.transcribe(wav: wav, key: key) { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                switch outcome {
                case .failure(let why):
                    self.finishWithFailure(wav, duration, why)
                case .success(let r) where r.text.isEmpty:
                    Log.error("ElevenLabs returned no words")
                    try? FileManager.default.removeItem(at: wav)
                    self.phase = .done("empty")
                    // The local model's wording, and for its reason (Victor,
                    // 2026-09-08): what the recogniser did with the audio is the
                    // app's business; the one thing he acts on is that nothing
                    // was heard.
                    self.didEnd?(.silent("No words detected"))
                case .success(let r):
                    Log.info(String(format: "elevenlabs: %@ (%.2f) — %d chars in %.2fs (%.2f× audio)",
                                    r.language ?? "?", r.languageProbability, r.text.count,
                                    elapsed, elapsed / max(duration, 0.01)))
                    // **Scribe learns its own round trip** (2026-09-23) — it never
                    // did: `DecodeRate` had been timing every Scribe sentence
                    // against the local model's curve since the day it became the
                    // engine. From the close, not from the upload: the stop's
                    // audio-queue hop is part of the wait he watches.
                    DecodeRate.record(audio: duration, decode: Date().timeIntervalSince(self.stoppedAt ?? startedAt),
                                      engine: DecodeRate.elevenLabs, chars: r.text.count)
                    self.didTranscribe?(DictationResult(
                        text: r.text, language: r.language, audio: wav, duration: duration,
                        engine: "elevenlabs", warning: Self.warning(for: r), delivery: .route,
                        via: "elevenlabs-scribe", markersInAudio: self.markersInAudio,
                        engineLabel: self.displayModelName, words: r.words))
                    self.phase = .done("formatted")
                    self.didEnd?(.delivered)
                }
            }
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        phase = .done("dismissed")
        closeStream()
        didStopListening?()
        // On `audioQueue` for `stop()`'s reason: the close is a device
        // teardown, and a cancel is the one path where the app is already
        // being asked to get out of his way quickly.
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let taken = self.meter.stop()
            self.meter.onBuffer = nil
            self.opening = nil
            DispatchQueue.main.async {
                self.didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
            }
        }
    }

    // MARK: - When the network is the thing that broke

    /// **A sentence that could not be uploaded is not a sentence that was never
    /// said.** This is the one recogniser in the app that can fail for a reason
    /// outside the Mac, and the wrong answer to that — the one every other
    /// failure path here takes — is `.silent`, which files nothing and leaves
    /// him to notice that his paragraph never arrived.
    ///
    /// So it ends on `DictationEnd.failed`, which is the case that carries
    /// **both** halves — the sentence why, shown for twelve seconds, and the
    /// WAV, staged in `cancelled/` for five minutes where *Recover Cancelled
    /// Dictation* can re-read it through whichever engine is live by then. That
    /// recovery path already existed, already has a menu row, and already knows
    /// how long to hold the file; what it did not have was a way to be reached
    /// by something other than Victor's own cancel.
    /// The caption ends with the microphone: the words after this point are the
    /// batch transcript's to say.
    private func closeStream() {
        stream?.stop()
        stream = nil
    }

    private func finishWithFailure(_ wav: URL, _ duration: TimeInterval, _ why: String) {
        Log.error("ElevenLabs: \(why)")
        phase = .done("error")
        didEnd?(.failed(why: "ElevenLabs: \(why)", audio: wav, duration: duration))
    }

    /// **The one number Scribe gives back that says *I might be wrong*.**
    ///
    /// The local model has two gates and neither of them exists here — there is
    /// no `avg_logprob` and no `compression_ratio` over an HTTP boundary. What
    /// there is, is `language_probability`, and a low one is the failure that
    /// actually happens on this corpus: a short Romanian clip read as Italian
    /// comes back fluent, confident and wrong. Shown as a note under the words
    /// rather than swallowing them, for `LocalWhisperSource.warning`'s reason —
    /// the alternative to a shaky transcript is silence, which is the one
    /// outcome he cannot notice.
    ///
    /// **0.5 is a starting point, not a measurement.** It has not been scored
    /// against the corpus yet; when it is, the number moves and this line says
    /// so. → `evals/`
    static let languageFloor = 0.5

    private static func warning(for r: Result) -> String? {
        guard r.languageProbability > 0, r.languageProbability < languageFloor else { return nil }
        return String(format: "⚠️ heard as %@ with %.0f%% confidence — check what was sent",
                      r.language ?? "?", r.languageProbability * 100)
    }

    // MARK: - The call

    struct Result {
        let text: String
        let language: String?
        let languageProbability: Double
        /// **Every token with the second it was said at**, straight out of
        /// `words[]` (2026-09-19). The thing that lets a screenshot reference
        /// land at the word he pressed the shutter at without a marker ever
        /// having been in the audio. → `ShotMarker.place`
        let words: [TimedWord]
    }

    enum Outcome {
        case success(Result)
        case failure(String)
    }

    /// **One retry, and only for the failures a retry can fix.**
    ///
    /// A transport error, a 429 and a 5xx are the network having a bad second;
    /// a 401 is a wrong key and a 400 is a bad request, and repeating either one
    /// costs a second of his settle to arrive at the same answer. The backoff is
    /// short for the same reason the timeout is bounded: he is standing there
    /// with the chip saying `Transcribing...`.
    static func transcribe(wav: URL, key: String, attempt: Int = 0,
                           _ done: @escaping (Outcome) -> Void) {
        let boundary = "walkie-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model_id", model)
        if let lang = language, !lang.isEmpty { field("language_code", lang) }
        // **Both off.** Diarization is a second speaker's problem and there is
        // one microphone here; the audio-event tags would put `(laughs)` in the
        // middle of a prompt bound for an agent.
        field("diarize", "false")
        field("tag_audio_events", "false")
        // **Asked for by name although it is the default.** It is the input the
        // whole marker mechanism rests on, and a default is a thing a vendor may
        // change; a transcript that quietly stopped carrying timings would show
        // up as markers silently falling back to the list at the end, which is
        // the failure nobody notices. Free — timings are not billed.
        field("timestamps_granularity", "word")

        guard let audio = try? Data(contentsOf: wav) else {
            return done(.failure("the recording could not be read — \(wav.lastPathComponent)"))
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(wav.lastPathComponent)\"\r\n"
                        .data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        req.httpMethod = "POST"
        req.timeoutInterval = requestTimeout
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retriable = error != nil || code == 429 || (500...599).contains(code)
            if retriable, attempt == 0 {
                Log.error("ElevenLabs attempt 1 failed (\(error?.localizedDescription ?? "HTTP \(code)")) — retrying")
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                    transcribe(wav: wav, key: key, attempt: 1, done)
                }
                return
            }
            if let error { return done(.failure(error.localizedDescription)) }
            guard let data else { return done(.failure("HTTP \(code) with no body")) }
            guard code == 200 else {
                // The API's own message, when it sent one — a 401 says *invalid
                // api key* and a 422 names the field, and both are the whole fix.
                let detail = String(data: data.prefix(400), encoding: .utf8) ?? ""
                return done(.failure("HTTP \(code) \(detail)"))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = json["text"] as? String else {
                return done(.failure("unreadable reply from ElevenLabs"))
            }
            // **Not trimmed, unlike `text`.** The tokens are the ruler the
            // markers are placed against, and dropping the leading whitespace
            // from the string while leaving it in the list would put every
            // insertion a token out. `place` trims the result at the end.
            let words: [TimedWord] = ((json["words"] as? [[String: Any]]) ?? []).compactMap { w in
                guard let text = w["text"] as? String,
                      let start = w["start"] as? Double,
                      let end = w["end"] as? Double else { return nil }
                return TimedWord(text: text, start: start, end: end,
                                 isSpacing: (w["type"] as? String) == "spacing")
            }
            done(.success(Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                 language: json["language_code"] as? String,
                                 languageProbability: json["language_probability"] as? Double ?? 0,
                                 words: words)))
        }.resume()
    }

    /// `GET /engine`'s half of the answer, the same shape `LocalWhisperSource`
    /// gives: what is configured and whether it could be used this instant.
    func describe() -> [String: Any] {
        ["ready": isReady, "model": Self.model, "live": live ? ElevenLabsLive.model : "off",
         "language": Self.language ?? "auto",
         "keyFile": Self.configURL.path]
    }
}
