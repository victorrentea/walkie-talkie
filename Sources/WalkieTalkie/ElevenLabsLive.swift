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

    /// The whole sentence heard so far, on the main queue.
    var onText: ((String) -> Void)?

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.eleven-live")
    private var task: URLSessionWebSocketTask?
    /// Chunks that arrived before `session_started` — the recording opens the
    /// microphone and the socket at the same moment, and the first words are
    /// the ones a caption most needs.
    private var pending: [Data] = []
    private var open = false
    private var closed = false
    private var committed = ""
    private var partial = ""

    /// Opens the socket. Called on the main queue at `start()`.
    func start(key: String, language: String?) {
        var parts = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var query = [URLQueryItem(name: "model_id", value: Self.model),
                     URLQueryItem(name: "audio_format", value: "pcm_16000"),
                     URLQueryItem(name: "commit_strategy", value: "vad")]
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
            task.resume()
            self.receive(task)
        }
        Log.info("💬 live caption: connecting to ElevenLabs \(Self.model)")
    }

    /// **On the audio thread** — `MicRecorder.onBuffer`. Copies the samples out
    /// and hops; the base64 and the send happen on `queue`.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return }
        let data = Data(bytes: samples, count: Int(buffer.frameLength) * MemoryLayout<Int16>.size)
        queue.async {
            guard !self.closed else { return }
            if self.open { self.send(data) } else { self.pending.append(data) }
        }
    }

    /// Closes the socket; nothing it says afterwards reaches the chip.
    func stop() {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.pending.removeAll()
            self.task?.cancel(with: .normalClosure, reason: nil)
            self.task = nil
        }
    }

    private func send(_ pcm: Data) {
        let message: [String: Any] = ["message_type": "input_audio_chunk",
                                      "audio_base_64": pcm.base64EncodedString(),
                                      "sample_rate": 16000]
        guard let json = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: json, encoding: .utf8) else { return }
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
        case "partial_transcript":
            partial = (json["text"] as? String) ?? ""
            publish()
        case "committed_transcript", "committed_transcript_with_timestamps":
            let segment = ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if !segment.isEmpty { committed += (committed.isEmpty ? "" : " ") + segment }
            partial = ""
            publish()
        default:
            // `error`, `auth_error`, `quota_exceeded`, `rate_limited`, … — the
            // caption stops, the sentence does not.
            if type.contains("error") || type.contains("exceeded") || type.contains("limited")
                || type.contains("overflow") {
                Log.error("💬 live caption: \(type) — \(text.prefix(300))")
            }
        }
    }

    private func publish() {
        let heard = [committed, partial.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        DispatchQueue.main.async { [weak self] in self?.onText?(heard) }
    }
}
