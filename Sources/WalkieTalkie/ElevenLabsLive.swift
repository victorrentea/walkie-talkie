import AVFoundation
import Foundation

/// **The words while he is still saying them** — ElevenLabs' realtime
/// recogniser over a websocket, fed the same 16 kHz mono buffers the recording
/// is made of (2026-09-25, `☁️ ElevenLabs + Live`).
///
/// Victor: *"the option+streaming will display +1 line in the mouse caption 💬
/// <the last 7 words of dictation live-transcribed> … to show me what I'm
/// talking about"*. It is a **caption, never the delivery**: the sentence that
/// reaches the destination is still the batch transcript of the WAV
/// (`ElevenLabsSource.transcribe`), with its word timings, its spliced markers
/// and its retry. A stream that drops mid-sentence costs the caption and
/// nothing else — which is why every failure here is a log line and not a
/// `DictationEnd`.
///
/// Protocol (`api.elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime`,
/// read 2026-09-25): `wss://…/v1/speech-to-text/realtime`, `xi-api-key` header,
/// `model_id=scribe_v2_realtime`, `audio_format=pcm_16000`. Up:
/// `{"message_type":"input_audio_chunk","audio_base_64":…,"sample_rate":16000}`.
/// Down: `session_started`, `partial_transcript` (the segment being spoken,
/// revised as it goes) and `committed_transcript` (a segment closed by the
/// server's VAD at a pause). Billed separately from the batch call — $0.39/h
/// published the same day.
final class ElevenLabsLive {

    static let model = "scribe_v2_realtime"
    static let rate = "$0.39/h"
    /// The languages the live recogniser may answer in: Romanian first, English
    /// as the secondary. `WT_ELEVEN_LIVE_LANGS=ro,en` overrides.
    static var languages: [String] {
        let raw = ProcessInfo.processInfo.environment["WT_ELEVEN_LIVE_LANGS"]
            ?? ElevenLabsSource.config["WT_ELEVEN_LIVE_LANGS"] ?? "ro,en"
        return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// What was heard so far, on the main queue: the segments the server has
    /// committed, and the one still being spoken (revised every partial).
    /// `gentle` marks a batch correction (below), which the band shows softer.
    var onText: ((_ committed: String, _ partial: String, _ gentle: Bool) -> Void)?

    /// **The batch model corrects the live words behind him** (2026-09-26,
    /// Victor: *"implementează și 5 … trimite doar bucata care mai apare pe
    /// ecran; la final de tot oricum trimitem tot"*). **At every segment the
    /// server commits** (its VAD closes one after 1.5 s of silence), the audio
    /// since the previous cut is uploaded to `ElevenLabsSource.transcribe` and
    /// its text replaces the live segments committed in that span; the cut
    /// moves to the end of the span, so every second of the sentence is
    /// uploaded once here (and once more, whole, at the stop — that one is the
    /// delivery). A failure leaves the cut where it was: the next commit
    /// covers the longer span. The first version waited for a 3 s pause
    /// instead; by then the eraser had wiped the words the correction was for
    /// (Victor, 07:20: *"the correction at pause finds no text on screen as it
    /// fades out — drop the silence rule, this thing is too dynamic"*). The
    /// 0.5 s timer stays only as the catch-up for a commit that arrived while
    /// an upload was in flight.
    static let minSpan: TimeInterval = 1.0

    /// **A socket fault the harness asked for** (gap G3): `drop` closes the
    /// socket 1 s after it opened, `never-open` never resumes it, `error:<type>`
    /// feeds one synthetic `<type>` message once the session is open. One use.
    private static let faultLock = NSLock()
    private static var _fault: String?
    static var fault: String? {
        get { faultLock.withLock { _fault } }
        set { faultLock.withLock { _fault = newValue } }
    }
    private var chunksSent = 0
    private var corrections = 0

    /// `GET /test/state.live` (gap G7).
    func describe() -> [String: Any] {
        queue.sync {
            ["socket": closed ? "closed" : (open ? "open" : (task == nil ? "never-opened" : "connecting")),
             "chunksSent": chunksSent, "pending": pending.count,
             "seconds": Double(pcm.count) / 32_000, "cutSeconds": Double(cutByte) / 32_000,
             "segments": segments.count, "correctedSegments": correctedSegments, "corrections": corrections,
             "correcting": correcting, "committedChars": segments.joined(separator: " ").count,
             "partialChars": partial.count, "keyterms": keytermCount]
        }
    }
    private var pcm = Data()
    private var cutByte = 0
    private var correctedSegments = 0
    private var lastTextAt = CACurrentMediaTime()
    private var correcting = false
    /// After a failed correction, no retry before this — the 0.5 s timer would
    /// otherwise hammer a server that is down (seen 2026-09-26 with an
    /// injected 401: a second upload 0.3 s after the first failed).
    private var correctionHoldUntil: CFTimeInterval = 0
    private var pauseTimer: DispatchSourceTimer?
    private var key = ""
    private var keytermCount = 0

    /// **Silence before a segment is committed** (2026-09-26, was the server's
    /// default). Committed text is frozen; the model only revises the segment
    /// still open, so a longer pause before the freeze means more context per
    /// revision — the caption may be provisional a little longer, which the
    /// band shows as a fade. Docs: "longer values result in fewer commits but
    /// longer segments".
    static let vadSilence = 1.5

    /// **Up to 50 `keyterms` to bias the model toward** (2026-09-26): the first
    /// column of `~/.walkie-talkie/vocab.txt` — the English words that actually
    /// occur inside his Romanian, ranked by the corpus (the file says how). A 20 %
    /// premium on $0.39/h. Re-read at every session, so the file is live.
    static func keyterms() -> [String] {
        let url = Outbox.home.appendingPathComponent("vocab.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { String($0.split(separator: ":", maxSplits: 1)[0]).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(50).map { $0 }
    }

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.eleven-live")
    private var task: URLSessionWebSocketTask?
    /// Chunks that arrived before `session_started` — the recording opens the
    /// microphone and the socket at the same moment, and the first words are
    /// the ones a caption most needs.
    private var pending: [Data] = []
    private var open = false
    private var closed = false
    /// Segments the server committed, in order; a batch correction collapses
    /// the span it covered into one.
    private var segments: [String] = []
    private var partial = ""

    /// Opens the socket. Called on the main queue at `start()`.
    func start(key: String, language: String?) {
        var parts = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var query = [URLQueryItem(name: "model_id", value: Self.model),
                     URLQueryItem(name: "audio_format", value: "pcm_16000"),
                     URLQueryItem(name: "commit_strategy", value: "vad"),
                     URLQueryItem(name: "vad_silence_threshold_secs", value: String(Self.vadSilence))]
        let terms = Self.keyterms()
        for term in terms { query.append(URLQueryItem(name: "keyterms", value: term)) }
        self.key = key
        self.keytermCount = terms.count
        // **The caption is pinned to his two languages** (2026-09-26, after a
        // sentence came back Turkish): `language_code` is the first of
        // `languages`, the rest go as `secondary_languages`, which the docs
        // (read 2026-09-26) say makes identification "only focus on a certain
        // set of languages". The batch transcript stays auto-detected — see
        // `ElevenLabsSource.language` for why pinning it costs the English
        // terms. `WT_ELEVEN_LANG` still wins when set, for a comparison run.
        let pinned = language.flatMap { $0.isEmpty ? nil : [$0] } ?? Self.languages
        if let first = pinned.first {
            query.append(URLQueryItem(name: "language_code", value: first))
            for extra in pinned.dropFirst() {
                query.append(URLQueryItem(name: "secondary_languages", value: extra))
            }
        }
        parts.queryItems = query
        var req = URLRequest(url: parts.url!)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        let task = URLSession.shared.webSocketTask(with: req)
        queue.async {
            self.task = task
            if Self.fault == "never-open" {
                Self.fault = nil
                Log.info("🧪 live caption: never-open — the socket is not resumed")
            } else {
                task.resume()
            }
            self.receive(task)
            self.lastTextAt = CACurrentMediaTime()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
            timer.setEventHandler { [weak self] in self?.correctIfDue() }
            timer.resume()
            self.pauseTimer = timer
        }
        Log.info("💬 live caption: connecting to ElevenLabs \(Self.model), languages \(pinned.joined(separator: "+")), \(terms.count) keyterms, commit after \(Self.vadSilence) s")
    }

    /// **On the audio thread** — `MicRecorder.onBuffer`. Copies the samples out
    /// and hops; the base64 and the send happen on `queue`.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return }
        let data = Data(bytes: samples, count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
        queue.async {
            guard !self.closed else { return }
            self.pcm.append(data)
            if self.open { self.send(data) } else { self.pending.append(data) }
        }
    }

    /// Closes the socket; nothing it says afterwards reaches the chip.
    func stop() {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.pending.removeAll()
            self.pauseTimer?.cancel()
            self.pauseTimer = nil
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.task = nil
            ElevenLabsCost.addLive(seconds: Double(self.pcm.count) / 32_000, keyterms: self.keytermCount > 0)
            self.pcm = Data()
        }
    }

    private func send(_ pcm: Data) {
        let message: [String: Any] = ["message_type": "input_audio_chunk",
                                      "audio_base_64": pcm.base64EncodedString(),
                                      "sample_rate": 16000]
        guard let json = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: json, encoding: .utf8) else { return }
        chunksSent += 1
        task?.send(.string(text)) { error in
            if let error { Log.error("💬 live caption: send failed — \(error.localizedDescription)") }
        }
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard !self.closed, self.task === task else { return }
                switch result {
                case .failure(let error):
                    Log.error("💬 live caption: \(error.localizedDescription)")
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(task)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["message_type"] as? String else { return }
        switch type {
        case "session_started":
            open = true
            let waiting = pending
            pending.removeAll()
            waiting.forEach(send)
            Log.info("💬 live caption: session open, \(waiting.count) chunk(s) caught up")
            if let f = Self.fault {
                Self.fault = nil
                if f == "drop" {
                    queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self, let task = self.task else { return }
                        Log.info("🧪 live caption: drop — cancelling the socket")
                        task.cancel(with: .goingAway, reason: nil)
                    }
                } else if f.hasPrefix("error:") {
                    let type = String(f.dropFirst(6))
                    Log.info("🧪 live caption: injecting a \(type) message")
                    handle(#"{"message_type":"\#(type)","error":"injected by /test/eleven"}"#)
                }
            }
        case "partial_transcript":
            let text = (json["text"] as? String) ?? ""
            if text != partial { lastTextAt = CACurrentMediaTime() }
            partial = text
            publish()
        case "committed_transcript", "committed_transcript_with_timestamps":
            let segment = ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty { segments.append(segment); lastTextAt = CACurrentMediaTime() }
            partial = ""
            publish()
            correctIfDue()
        default:
            // `error`, `auth_error`, `quota_exceeded`, `rate_limited`, … — the
            // caption stops, the sentence does not.
            if type.contains("error") || type.contains("exceeded") || type.contains("limited")
                || type.contains("overflow") {
                Log.error("💬 live caption: \(type) — \(text.prefix(300))")
            }
        }
    }

    private func publish(gentle: Bool = false) {
        let committed = segments.joined(separator: " ")
        let partial = self.partial.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.async { [weak self] in self?.onText?(committed, partial, gentle) }
    }

    /// On `queue`: live segments not yet corrected and at least `minSpan` of
    /// audio since the cut → upload the span. Called at every commit, and by
    /// the 0.5 s timer for a commit that arrived while an upload was running.
    private func correctIfDue() {
        guard !closed, !correcting, segments.count > correctedSegments,
              CACurrentMediaTime() >= correctionHoldUntil,
              pcm.count > cutByte + Int(Self.minSpan * 32_000) else { return }
        let from = cutByte, to = pcm.count, upTo = segments.count
        let span = pcm[from..<to]
        let wav = Outbox.shotsDir.appendingPathComponent("live-correct-\(Int(Date().timeIntervalSince1970)).wav")
        do { try Self.wav(pcm: span).write(to: wav) } catch {
            Log.error("💬 live correction: could not stage the audio — \(error.localizedDescription)")
            return
        }
        correcting = true
        let seconds = Double(to - from) / 32_000
        Log.info(String(format: "💬 live correction: %.1fs since the last cut, %d live segment(s) → %@", seconds, upTo - correctedSegments, ElevenLabsSource.model))
        ElevenLabsSource.transcribe(wav: wav, key: key, purpose: "correction") { [weak self] outcome in
            try? FileManager.default.removeItem(at: wav)
            guard let self else { return }
            self.queue.async {
                self.correcting = false
                guard !self.closed else { return }
                switch outcome {
                case .failure(let why):
                    self.correctionHoldUntil = CACurrentMediaTime() + 5
                    Log.error("💬 live correction failed — \(why); the next commit after 5 s covers the span again")
                case .success(let r):
                    guard !r.text.isEmpty, upTo <= self.segments.count else { return }
                    let before = self.segments[self.correctedSegments..<upTo].joined(separator: " ")
                    self.segments.replaceSubrange(self.correctedSegments..<upTo, with: [r.text])
                    self.correctedSegments += 1
                    self.corrections += 1
                    self.cutByte = to
                    Log.info("💬 live correction: \(before.count) → \(r.text.count) chars" + (before == r.text ? " (identical)" : ""))
                    self.publish(gentle: true)
                }
            }
        }
    }

    /// A 16 kHz mono 16-bit RIFF/WAVE around raw PCM.
    static func wav(pcm: Data) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
