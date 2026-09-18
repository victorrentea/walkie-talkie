import AVFoundation
import Foundation

/// **The relay's own microphone, transcribed *while he is still speaking*** —
/// the fourth recogniser behind `DictationSource` (2026-09-18).
///
/// Every other engine in this app is a **round trip after the fact**: the
/// microphone closes, and only then does something start reading the sentence —
/// a `POST` with a WAV in it (`ElevenLabsSource`), a daemon handed a file
/// (`LocalWhisperSource`), another application's own pipeline
/// (`WisprFlowSource`). The wait Victor watches at the end of a dictation is
/// that whole reading, and it is proportional to how long he spoke.
///
/// Speechmatics is the first one here that does not work that way. It is a
/// **WebSocket that is fed his voice as it is recorded**, and the transcript is
/// already largely written by the time he lets the key go: what is left at the
/// release is the tail — the last words, plus whatever the recogniser was
/// holding back to see how the sentence ended. That is the thing being bought,
/// and it is a different thing from a faster server.
///
/// | | this | `ElevenLabsSource` | `LocalWhisperSource` | `WisprFlowSource` |
/// |---|---|---|---|---|
/// | audio goes out | as it is spoken | in one upload at the end | never | never |
/// | work starts | at the first syllable | at the release | at the release | at the release |
/// | left to do at the release | the tail | all of it | all of it | all of it |
/// | fails when | the network does | the network does | never | Wispr changes how it delivers |
///
/// ## The WAV is still written, and it is not a leftover
///
/// This source streams **and** records, which looks like belt and braces and is
/// not. `VoiceCorpus` needs the audio of every sample it files, and a stream is
/// not audio anybody kept; and when the socket dies mid-sentence the WAV is the
/// **only** copy of words he has already said — that is what `DictationEnd`
/// `.failed` carries, and it is why a broken connection here costs him a retry
/// and never a paragraph.
///
/// The recorder is also what makes the markers work: they are **spliced** into
/// the same buffer sequence (`MicRecorder.onBuffer` delivers markers in the
/// order they were inserted), so a `Screenshot one.` that is in the file is also
/// in what the recogniser heard. → `ShotMarker`
///
/// ## The one thing it cannot do, and it must be said at the top
///
/// **There is no language auto-detection in real time.** Speechmatics detects a
/// language only in batch mode, so a streaming session has to be told what it is
/// about to hear, once, before the first word. Every other engine in this app
/// is free to work it out — `ElevenLabsSource` deliberately does not pin a
/// language, because Victor dictates Romanian with English technical words in
/// it, and that is the transcript this repo is tuned on.
///
/// So this engine is **pinned to `ro` by default**, the language of most of his
/// dictation, `WT_SM_LANG=en` swaps it for a session, and the menu row says
/// which one is loaded so the pick is never made blind. That is a real step down
/// from the other three and it is the price of the latency, not an oversight.
final class SpeechmaticsSource: DictationSource {

    let name = "Speechmatics"

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    let meter = MicRecorder()

    private(set) var isRecording = false
    private(set) var phase: DictationPhase = .idle

    /// **The key, and whether there is one** — `ElevenLabsSource.apiKey`'s twin,
    /// for its reasons. Re-read by `prepare()` and by the menu, so the file can
    /// be created while the app is running.
    private(set) var apiKey: String?
    var isReady: Bool { apiKey != nil }

    // MARK: - Configuration

    /// **The EU endpoint, because that is the near one and the lawful one.**
    ///
    /// Speechmatics publishes `eu`, `us` and a `global` front door, and for a
    /// stream the choice is audible in a way it is not for an upload: every
    /// buffer pays the round trip, not just the request. Frankfurt from
    /// Bucharest is tens of milliseconds; Virginia is not. `WT_SM_URL` is the
    /// override, and it is a whole URL rather than a region code so a
    /// self-hosted container is the same switch.
    static var endpoint: String {
        env("WT_SM_URL") ?? "wss://eu.rt.speechmatics.com/v2"
    }

    /// **`ro`, pinned, because real time has no detector** — see the note at the
    /// top of this file. `WT_SM_LANG=en` for a session of English.
    static var language: String { env("WT_SM_LANG") ?? "ro" }

    /// **`enhanced`, the accurate one, not `standard`, the cheap one.**
    ///
    /// The whole reason to send his voice off this Mac is that the transcript
    /// comes back better than the local model's; an engine that uploads *and*
    /// runs the cheaper acoustic model would be paying the network for nothing.
    /// `WT_SM_OPERATING_POINT=standard` is the A/B, and the menu row says which
    /// one is loaded because the two do not cost the same.
    static var operatingPoint: String { env("WT_SM_OPERATING_POINT") ?? "enhanced" }

    /// **How long the recogniser may hold a word back to see what follows it**,
    /// in seconds — Speechmatics' `max_delay`, valid from 0.7 to 4.
    ///
    /// It is the knob this engine exists for and it is **not** the knob that
    /// decides the wait Victor sees. At the release the client sends
    /// `EndOfStream` and the server flushes everything it is holding, so the
    /// tail arrives regardless; `max_delay` sets the cadence *during* the
    /// sentence — how far behind his voice the finals run. 1.0 rather than the
    /// floor of 0.7 because a recogniser given a little more context punctuates
    /// better, and a comma is worth more here than 300 ms nobody is waiting on.
    ///
    /// **Not measured on his voice yet.** → `evals/`
    static var maxDelay: Double {
        guard let raw = env("WT_SM_MAX_DELAY"), let value = Double(raw) else { return 1.0 }
        return min(max(value, 0.7), 4.0)
    }

    /// **What this engine costs per hour of audio.**
    ///
    /// In the menu for `ElevenLabsSource.rate`'s reason: the price is half the
    /// trade the row exists to state. Published rate for the Pro tier at the
    /// time of writing, and **real-time is historically billed above batch** at
    /// this vendor — so this is the number that is most likely to be wrong first.
    /// **If the row and the invoice disagree, the invoice is right**, and the
    /// fix is this line.
    static var rate: String { env("WT_SM_RATE") ?? "~$0.13/h" }

    /// **The acoustic model, when it is not the endpoint's own** — today that
    /// means `linden-1`, the model behind their **Agent STT** (2026-09-17), and
    /// it is here for one reason: Speechmatics say full **multilingual** support
    /// is coming to it, and multilingual is the thing this engine cannot do.
    ///
    /// Setting it is two switches rather than one, and they have to agree — the
    /// model only answers on `/v2/agent`, so `WT_SM_MODEL=linden-1` moves the
    /// endpoint too unless `WT_SM_URL` has already been said out loud. What
    /// Agent STT adds beyond that — turn signals, start and end of speech,
    /// diarization — is worth **nothing** here: this app already knows when the
    /// sentence ended, because he let go of the key.
    static var model: String? { env("WT_SM_MODEL") }

    /// `/v2/agent` when a model needs it and nothing else was asked for. The
    /// preview host is theirs, not a typo: that is where Agent STT answers.
    static var resolvedEndpoint: String {
        if let explicit = env("WT_SM_URL") { return explicit }
        if model != nil { return "wss://preview.rt.speechmatics.com/v2/agent" }
        return endpoint
    }

    /// **What the menu row and the envelope call it.** The operating point and
    /// the language both ride in it, because both change what comes back and
    /// neither is visible anywhere else at the moment of the pick.
    var displayModelName: String { "Speechmatics \(Self.operatingPoint) (\(Self.language))" }

    /// **How long the tail may take after the release**, before the relay stops
    /// waiting for `EndOfTranscript`.
    ///
    /// Six seconds, against `AppDelegate.settleTimeout`'s eight: the settle must
    /// not be the thing that gives up first, or the words arrive after the ring
    /// has gone and land nowhere. And a timeout here is **not** a failure when
    /// finals have already arrived — see `finish(timedOut:)`: the sentence minus
    /// its last clause is worth far more than a banner saying the network was
    /// slow.
    private static let tailTimeout: TimeInterval = 6

    /// A stream that is never answered still fills memory at 32 KB/s. Two
    /// minutes of it is the ceiling — past any dictation in the corpus (the
    /// longest is 197 s, and this cap only applies to audio recorded *before*
    /// the session was confirmed, which is normally a fifth of a second).
    private static let pendingCeiling = 16_000 * 2 * 120

    // MARK: - The custom dictionary — the nearest thing to a second language

    /// **`~/.walkie-talkie/vocab.txt`, and why it is not optional
    /// polish** (Victor, 2026-09-18: *"poți să setezi și română, și engleză ca
    /// limbi de output așteptate?"*).
    ///
    /// No — and the API is unambiguous about it. A real-time session takes
    /// exactly **one** `language`; auto-detection is batch-only; the seven
    /// bilingual packs that do exist (`ar_en`, `cmn_en`, `en_ms`, `en_ta`,
    /// `cmn_en_ms_ta`, `tl`, and `es` + `domain: bilingual-en`) have **no
    /// Romanian**; and `melia-1`, the model that switches languages by itself,
    /// does not list Romanian either and is not offered on this endpoint.
    ///
    /// So the session is Romanian, and the English inside his Romanian is
    /// exactly what a Romanian pack is worst at. A custom dictionary is the
    /// mechanism that vendor gives for that, it works in real time, and it is
    /// cached on their side after the first session — so this is not the
    /// consolation prize, it is the actual answer to the question.
    ///
    /// The file is read **fresh at every dictation**, deliberately: it is a list
    /// he will edit the moment a word comes back wrong, and a restart between
    /// noticing and fixing is how a list like this stops being maintained.
    static var vocabURL: URL { DictationVocabulary.url }

    /// Speechmatics' `additional_vocab`, out of the shared list —
    /// `DictationVocabulary`, which is where the *why* lives. It moved there the
    /// moment a second engine wanted the same words (`GeminiSource`, the same
    /// day): the list is a fact about Victor, not about this vendor.
    static func additionalVocab() -> [[String: Any]] {
        DictationVocabulary.speechmaticsVocab()
    }

    // MARK: - The key

    /// **`~/.walkie-talkie/speechmatics.env`**, `SPEECHMATICS_API_KEY=…`,
    /// environment first — the same shape, the same file layout and the same
    /// reasons as `ElevenLabsSource.configURL`: launchd starts this app so it
    /// inherits no shell, the Keychain would prompt at the one moment a sentence
    /// is waiting, and it follows `--home` so a test relay cannot bill the real
    /// account.
    static var configURL: URL { Outbox.home.appendingPathComponent("speechmatics.env") }

    private static var config: [String: String] = [:]

    /// Environment first, then the file. Both are re-read on every
    /// `reloadKey()`, which is every time the menu opens — pasting a key in is
    /// the whole of the setup, no restart.
    private static func env(_ name: String) -> String? {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
        if let value = config[name], !value.isEmpty { return value }
        return nil
    }

    private static func loadConfig() {
        config = [:]
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let row = line.trimmingCharacters(in: .whitespaces)
            guard !row.isEmpty, !row.hasPrefix("#"), let eq = row.firstIndex(of: "=") else { continue }
            let key = String(row[row.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(row[row.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            config[key] = value
        }
    }

    @discardableResult
    func reloadKey() -> Bool {
        Self.loadConfig()
        let key = Self.env("SPEECHMATICS_API_KEY")
        apiKey = (key?.isEmpty ?? true) ? nil : key
        return apiKey != nil
    }

    // MARK: - The session

    /// Everything the socket touches lives here and is only ever read or written
    /// on `net`. The audio tap hands buffers in from CoreAudio's thread, the
    /// receive loop hands messages in from URLSession's, and the gesture arrives
    /// on the main one — three threads, one queue, no locks.
    private let net = DispatchQueue(label: "ro.victorrentea.walkie.speechmatics")

    private var socket: URLSessionWebSocketTask?
    /// `RecognitionStarted` has come back: the server has the configuration and
    /// audio may flow. Until then buffers wait in `pending` — audio sent ahead
    /// of it is a protocol error and ends the session.
    private var confirmed = false
    private var pending: [Data] = []
    private var pendingBytes = 0
    /// Frames accepted by the socket, which is what `EndOfStream.last_seq_no`
    /// means: *this many `AddAudio` messages were sent*.
    private var seq = 0

    /// The finals, in order. Speechmatics' `transcript` field already carries
    /// its own leading space, so these are concatenated and not joined.
    private var finals: [String] = []
    /// The newest partial, kept for the log and the word count only — nothing on
    /// screen draws it, and Victor asked for it to stay that way (2026-09-18):
    /// *"nu mi se pare un câștig prea mare … mă va face să mă opresc și să tot
    /// corectez ce am scris"*. The field stays because `GET /engine` is how a
    /// live session is debugged, not because a chip is coming.
    private var partial = ""
    /// Per-word confidences off the finals, for `warning(for:)`.
    private var confidences: [Double] = []

    /// **The session broke, and this is what to tell him.** Set on the socket's
    /// thread and read at the release: a connection that dies mid-sentence must
    /// not interrupt the recording — the microphone stays open, the WAV goes on
    /// being written, and the failure is reported once, at the end, with the
    /// audio attached.
    private var dead: String?

    /// Fired once per session, from whichever of the three arrives first —
    /// `EndOfTranscript`, the timeout, or a broken socket.
    private var finished = false

    /// **He let go before the handshake came back.** Set at the release when the
    /// session is not up yet, cleared by `RecognitionStarted`, which then sends
    /// the `EndOfStream` the release could not.
    private var endAfterStart = false

    /// Set at `start()`, read at the release.
    private var recordingURL: URL?
    private var markersInAudio = false
    private var tailTimer: DispatchWorkItem?
    private var releasedAt: Date?

    // MARK: - DictationSource

    func prepare() {
        if reloadKey() {
            Log.info("Speechmatics ready — \(Self.operatingPoint), \(Self.language), "
                     + "max_delay \(Self.maxDelay)s, \(Self.endpoint)")
        } else {
            Log.error("Speechmatics: no API key — put SPEECHMATICS_API_KEY=… in \(Self.configURL.path)")
        }
    }

    /// **Yes, and spliced** — `ElevenLabsSource.mark`'s mechanism exactly, and it
    /// reaches the recogniser here by the same route it reaches the file:
    /// `MicRecorder` hands the marker to `onBuffer` in sequence, so the socket
    /// gets it between two of his buffers rather than over them.
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
            Log.info(String(format: "📣 marker spliced into the stream: %@ %d (%.0f ms for a gap)",
                            kind.words, index, waited * 1000))
        }
    }

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard let key = apiKey else {
            return "no Speechmatics API key — see \(Self.configURL.lastPathComponent)"
        }

        // **The socket first, the microphone immediately after — and the
        // microphone does not wait for it.** Opening a WebSocket is a round trip
        // and a handshake, and a gesture that held the recording until it
        // finished would eat the first syllable of every sentence on a slow
        // network. So the audio starts at once and waits in `pending`; the cost
        // of the connection is paid out of the buffer, not out of his words.
        resetSession()
        connect(key: key)

        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        // Set before `start(to:)`, which is `MicRecorder.onBuffer`'s contract.
        meter.onBuffer = { [weak self] buffer in
            guard let self, let data = Self.pcm(buffer) else { return }
            self.net.async { self.send(audio: data) }
        }
        if let why = meter.start(to: wav) {
            meter.onBuffer = nil
            net.async { self.closeSocket() }
            return why
        }

        recordingURL = wav
        markersInAudio = false
        isRecording = true
        phase = .listening
        Log.info("🎙️ streaming to Speechmatics — \(Self.operatingPoint)/\(Self.language), "
                 + wav.lastPathComponent)
        didBegin?()
        return nil
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        phase = .transcribing("tail")
        releasedAt = Date()
        didStopListening?()

        let taken = meter.stop()
        meter.onBuffer = nil

        guard let (wav, duration) = taken else {
            Log.info("recording discarded — under \(MicRecorder.minimumDuration)s")
            net.async { self.closeSocket() }
            phase = .done("empty")
            didEnd?(.silent(""))
            return
        }
        recordingURL = wav
        self.duration = duration

        // **`EndOfStream` goes on the same queue the audio went on**, so it
        // cannot overtake the last buffers — which is the whole of what
        // `last_seq_no` is checked against on the other end.
        net.async {
            if let why = self.dead {
                // The socket died while he was talking. The words exist; only
                // the transcript does not.
                return self.fail(why)
            }
            // **A sentence can be over before the session is up.** The socket
            // costs a round trip and a short dictation costs less — release at
            // 0.4 s on a cold connection and `RecognitionStarted` has not
            // arrived, so there is nothing to flush into and an `EndOfStream`
            // sent now would be a protocol error against a session that never
            // started. The audio is already safe in `pending`; the release is
            // remembered instead, and the handshake finishes the job.
            guard self.confirmed else {
                self.endAfterStart = true
                Log.info("Speechmatics: released before the session was up — "
                         + "the buffer goes out when it is")
                let timer = DispatchWorkItem { [weak self] in self?.finish(timedOut: true) }
                self.tailTimer = timer
                self.net.asyncAfter(deadline: .now() + Self.tailTimeout, execute: timer)
                return
            }
            self.flushPending()
            self.sendJSON(["message": "EndOfStream", "last_seq_no": self.seq])
            Log.info(String(format: "🎙️ released after %.1fs — %d finals so far, waiting for the tail",
                            duration, self.finals.count))
            let timer = DispatchWorkItem { [weak self] in self?.finish(timedOut: true) }
            self.tailTimer = timer
            self.net.asyncAfter(deadline: .now() + Self.tailTimeout, execute: timer)
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        phase = .done("dismissed")
        didStopListening?()
        let taken = meter.stop()
        meter.onBuffer = nil
        net.async {
            self.finished = true
            self.closeSocket()
        }
        didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
    }

    /// How long the microphone was open — set at the release, read when the tail
    /// lands, on `net`.
    private var duration: TimeInterval = 0

    // MARK: - The socket

    private func resetSession() {
        net.sync {
            confirmed = false
            pending = []
            pendingBytes = 0
            seq = 0
            finals = []
            partial = ""
            confidences = []
            dead = nil
            finished = false
            endAfterStart = false
            tailTimer?.cancel()
            tailTimer = nil
        }
    }

    /// **Everything below happens on `net`**, including building the task —
    /// `socket` is read by the audio pump and by the receive loop, and a
    /// reference written from the gesture thread while those two are running is
    /// a race that would show up once a month as a dictation that streamed
    /// nowhere.
    private func connect(key: String) {
        net.async { self.openSocket(key: key) }
    }

    private func openSocket(key: String) {
        guard let url = URL(string: Self.resolvedEndpoint) else {
            return die("bad endpoint \(Self.resolvedEndpoint)")
        }
        var request = URLRequest(url: url)
        // **The API key straight in the handshake header.** The temporary-JWT
        // dance Speechmatics documents is for browsers, where the long-lived key
        // would be shipped to the end user; this app *is* the server, the key is
        // in a file only he can read, and a token mint would be a second round
        // trip in front of every dictation.
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        socket = task
        task.resume()
        receive(on: task)

        var config: [String: Any] = [
            "language": Self.language,
            "operating_point": Self.operatingPoint,
            "max_delay": Self.maxDelay,
            // **Partials on, and nothing draws them yet.** They cost nothing
            // extra on the wire, they are what makes the word count in the log
            // honest while he is speaking, and they are the hook the live chip
            // will hang off — see `describe()`.
            "enable_partials": true,
            // One microphone, one speaker. Diarization here would tag every word
            // `S1` and bill for the privilege.
            "diarization": "none"
        ]
        if let model = Self.model { config["model"] = model }
        // **The English inside his Romanian, told to a Romanian session.** The
        // one mechanism this API offers for a second language, and it is sent
        // only when the file has something in it — an empty `additional_vocab`
        // is a field the server has to parse for nothing.
        let vocab = Self.additionalVocab()
        if !vocab.isEmpty {
            config["additional_vocab"] = vocab
            Log.info("Speechmatics: \(vocab.count) custom-dictionary entries from "
                     + Self.vocabURL.lastPathComponent)
        }

        sendJSON([
            "message": "StartRecognition",
            "audio_format": ["type": "raw", "encoding": "pcm_s16le", "sample_rate": 16000],
            "transcription_config": config
        ])
    }

    /// One receive at a time, re-armed from its own completion — URLSession's
    /// WebSocket API is a pump, not a stream, and a missed re-arm is a session
    /// that goes quiet with no error anywhere.
    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // **The close frame first, the transport error second.**
                // Measured against the live endpoint on 2026-09-18: a rejected
                // key does **not** fail the handshake — the WebSocket opens,
                // `StartRecognition` goes out, and the server closes with
                // `4001 not_authorised`. What URLSession hands back for that is
                // a generic *Socket is not connected*, which sends whoever reads
                // the banner looking at the network instead of at the key.
                let reason = task.closeReason
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let closed = (reason?.isEmpty == false)
                    ? "\(reason!) (\(task.closeCode.rawValue))" : nil
                self.net.async { self.die(closed ?? error.localizedDescription) }
            case .success(let message):
                self.net.async { self.handle(message) }
                self.receive(on: task)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = json["message"] as? String else { return }

        switch kind {
        case "RecognitionStarted":
            confirmed = true
            flushPending()
            if endAfterStart {
                endAfterStart = false
                sendJSON(["message": "EndOfStream", "last_seq_no": seq])
            }
        case "AudioAdded":
            break
        case "AddPartialTranscript":
            partial = json["transcript"] as? String ?? ""
        case "AddTranscript":
            let text = json["transcript"] as? String ?? ""
            if !text.isEmpty { finals.append(text) }
            confidences.append(contentsOf: Self.wordConfidences(json))
            partial = ""
        case "EndOfTranscript":
            finish(timedOut: false)
        case "Error":
            let type = json["type"] as? String ?? "error"
            let reason = json["reason"] as? String ?? ""
            die("\(type) — \(reason)")
        case "Warning":
            Log.error("Speechmatics warning: \(json["reason"] as? String ?? "?")")
        default:
            break
        }
    }

    /// Buffers while the session is being set up, sends once it is confirmed.
    /// Called on `net` only.
    private func send(audio data: Data) {
        guard dead == nil, !finished else { return }
        guard confirmed else {
            guard pendingBytes < Self.pendingCeiling else { return }
            pending.append(data)
            pendingBytes += data.count
            return
        }
        emit(data)
    }

    private func flushPending() {
        guard confirmed, !pending.isEmpty else { return }
        let queued = pending
        pending = []
        pendingBytes = 0
        for chunk in queued { emit(chunk) }
        Log.info(String(format: "Speechmatics session up — %.2fs of audio flushed from the buffer",
                        Double(queued.reduce(0) { $0 + $1.count }) / 32_000))
    }

    private func emit(_ data: Data) {
        guard let socket else { return }
        seq += 1
        socket.send(.data(data)) { [weak self] error in
            guard let error else { return }
            self?.net.async { self?.die(error.localizedDescription) }
        }
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard let error else { return }
            self?.net.async { self?.die(error.localizedDescription) }
        }
    }

    private func closeSocket() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    // MARK: - How it ends

    /// **The session broke.** On `net`.
    ///
    /// While the microphone is open this only records the reason — the recording
    /// must not be interrupted, because the WAV is about to be the only copy of
    /// the sentence. After the release it is a failure he is told about, once.
    private func die(_ why: String) {
        guard dead == nil, !finished else { return }
        dead = why
        closeSocket()
        Log.error("Speechmatics: \(why)")
        guard !isRecording else { return }   // reported at the release
        fail(why)
    }

    /// On `net`.
    private func fail(_ why: String) {
        guard !finished else { return }
        finished = true
        tailTimer?.cancel()
        closeSocket()
        let wav = recordingURL
        let duration = self.duration
        // A stream that broke after some of the sentence had already come back
        // is still a failure — half a paragraph delivered as if it were the
        // whole one is worse than a banner, because he cannot see what is
        // missing. The finals go in the log so nothing said is lost entirely.
        if !finals.isEmpty {
            Log.error("Speechmatics had, before it broke: \(finals.joined())")
        }
        DispatchQueue.main.async {
            self.phase = .done("error")
            self.didEnd?(.failed(why: "Speechmatics: \(why)", audio: wav, duration: duration))
        }
    }

    /// **The tail landed, or it did not come.** On `net`, once.
    ///
    /// A timeout with finals in hand is **not** treated as a failure: the
    /// sentence minus its last clause is worth far more than a banner, and the
    /// note under the transcript says the end may be missing so he can see for
    /// himself. A timeout with nothing in hand is the network, and takes the
    /// `.failed` path with the WAV attached.
    private func finish(timedOut: Bool) {
        guard !finished else { return }
        guard !finals.isEmpty else {
            return timedOut ? fail("nothing came back in \(Int(Self.tailTimeout))s")
                            : finishEmpty()
        }
        finished = true
        tailTimer?.cancel()
        closeSocket()

        let text = finals.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = releasedAt.map { Date().timeIntervalSince($0) } ?? 0
        let wav = recordingURL
        let duration = self.duration
        var note = Self.warning(confidences)
        if timedOut {
            note = "⚠️ the recogniser never said it was finished — the end of this may be missing"
        }
        Log.info(String(format: "speechmatics: %d chars, tail %.2fs after the release%@",
                        text.count, tail, timedOut ? " (timed out)" : ""))

        DispatchQueue.main.async {
            guard !text.isEmpty else { return self.finishEmptyOnMain() }
            self.didTranscribe?(DictationResult(
                text: text, language: Self.language, audio: wav, duration: duration,
                engine: "speechmatics", warning: note, delivery: .route,
                via: "speechmatics-rt", markersInAudio: self.markersInAudio,
                engineLabel: self.displayModelName))
            self.phase = .done("formatted")
            self.didEnd?(.delivered)
        }
    }

    private func finishEmpty() {
        finished = true
        tailTimer?.cancel()
        closeSocket()
        DispatchQueue.main.async { self.finishEmptyOnMain() }
    }

    private func finishEmptyOnMain() {
        Log.error("Speechmatics returned no words")
        if let wav = recordingURL { try? FileManager.default.removeItem(at: wav) }
        phase = .done("empty")
        // `LocalWhisperSource`'s wording, and for Victor's reason (2026-09-08):
        // what the recogniser did with the audio is the app's business; the one
        // thing he acts on is that nothing was heard.
        didEnd?(.silent("No words detected"))
    }

    // MARK: - Reading what came back

    private static func wordConfidences(_ json: [String: Any]) -> [Double] {
        guard let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard result["type"] as? String == "word",
                  let alternatives = result["alternatives"] as? [[String: Any]],
                  let confidence = alternatives.first?["confidence"] as? Double else { return nil }
            return confidence
        }
    }

    /// **The note under a transcript the recogniser was unsure of.**
    ///
    /// Speechmatics gives a confidence per word, which is a better signal than
    /// `ElevenLabsSource` has — it has only *what language was that* — and a
    /// worse one than the local model's two gates. The mean is used rather than
    /// the minimum because one hesitant word in forty is a normal sentence,
    /// while a whole sentence at 0.4 is a microphone problem or the **wrong
    /// pinned language**, which is this engine's own failure mode and the one
    /// worth a note.
    ///
    /// **0.6 is a starting point, not a measurement.** → `evals/`
    static let confidenceFloor = 0.6

    private static func warning(_ confidences: [Double]) -> String? {
        guard confidences.count >= 3 else { return nil }
        let mean = confidences.reduce(0, +) / Double(confidences.count)
        guard mean < confidenceFloor else { return nil }
        return String(format: "⚠️ the recogniser averaged %.0f%% on these words — "
                      + "is it still listening for %@?", mean * 100, language)
    }

    private static func pcm(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return nil }
        return Data(bytes: samples, count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
    }

    /// `GET /engine`'s half of the answer, the same shape the other two give —
    /// plus `partial`, which is the only place in this app a half-written
    /// sentence is visible at all. Nothing on screen draws it yet: the chip says
    /// `Transcribing…` for every engine, and making it say his words as they
    /// arrive is a change to the overlay, not to a recogniser.
    func describe() -> [String: Any] {
        var out: [String: Any] = ["ready": isReady,
                                  "endpoint": Self.resolvedEndpoint,
                                  "operatingPoint": Self.operatingPoint,
                                  "model": Self.model ?? "",
                                  "language": Self.language,
                                  "maxDelay": Self.maxDelay,
                                  // **The count, not the list.** How many words
                                  // the session was taught is the thing that
                                  // answers *did my edit take*; seventy entries
                                  // in a health check is a health check nobody
                                  // reads.
                                  "vocab": Self.additionalVocab().count,
                                  "vocabFile": Self.vocabURL.path,
                                  "keyFile": Self.configURL.path]
        net.sync {
            out["confirmed"] = confirmed
            out["finals"] = finals.count
            out["partial"] = partial
            if let dead { out["error"] = dead }
        }
        return out
    }
}
