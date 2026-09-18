import Foundation

/// **The relay's own microphone, read by a language model** — the fifth
/// recogniser behind `DictationSource` (2026-09-18), and the first one that can
/// be *told what it is about to hear* in a sentence rather than in a field.
///
/// Its shape is `ElevenLabsSource`'s: this app opens the microphone, writes one
/// 16 kHz mono WAV, and posts that file. Markers are **spliced**, the audio the
/// corpus files is the audio that was transcribed, and there is no wrap. What is
/// swapped out is the recogniser and, with it, one assumption the other four
/// share — that a recogniser is a thing you *configure*.
///
/// ## Why a fifth, when there are already two in the cloud
///
/// Victor, 2026-09-18, after Speechmatics landed: *"un model de voice-to-text
/// care să suporte în română și engleză bine, cu un preț bun, rulat în cloud,
/// care merge cu latență mică, mai ieftin decât celălalt pe care l-am
/// implementat deja"*. Three constraints, and the two cloud engines already here
/// each fail one:
///
/// | | română + engleză | $/h | at the release |
/// |---|---|---|---|
/// | `ElevenLabsSource` | detected, and the best published Romanian number | **0.22** | one upload |
/// | `SpeechmaticsSource` | **one pinned language**, no auto | 0.13 | the tail only |
/// | this | **native code-switching, and promptable** | **~0.09** | one upload |
///
/// ## The prompt is the feature
///
/// Speechmatics could not be told *"Romanian, but leave the English words in
/// English"* — it takes one `language` and a word list, and there is no
/// Romanian-English pack (→ `SpeechmaticsSource`, the note on the dictionary).
/// A language model takes the instruction directly, in Romanian, and the same
/// `~/.walkie-talkie/vocab.txt` rides along inside it.
///
/// **This was measured before the file was written**, on four corpus samples
/// through the nearest equivalent (OpenAI's `gpt-4o-mini-transcribe`, which
/// takes the same kind of prompt): *"preluat automat de **Cloud Code**"* without
/// the terms, *"preluat automat de **Claude Code**"* with them, same audio, same
/// model, 1.1 s. That is the whole argument for this engine.
///
/// ## And the failure mode that comes with it, which is not Whisper's
///
/// The same measurement caught the thing to be afraid of. `gpt-4o-transcribe`
/// (the larger one) was handed 25 seconds of Romanian and returned **one and a
/// half sentences** — not garbled, not hallucinated: *shortened*, fluently,
/// with no marker anywhere that anything was missing. An acoustic model that
/// cannot hear a word writes the wrong word and Victor sees it; a language model
/// that cannot hear a passage can write a **tidier version of it**.
///
/// So this source does two things no other one here needs to: the prompt says
/// *verbatim, do not summarise* in as many words, and `warnIfShort` measures the
/// text against the **voiced** seconds of the recording — not the wall-clock
/// ones, which cannot tell a truncation from a man thinking between sentences —
/// and hangs a note on anything too short to be the whole thing. The note is the
/// only defence available: the audio is kept either way, and a paragraph quietly
/// trimmed to its gist is the one failure he cannot see and correct.
final class GeminiSource: DictationSource {

    let name = "Gemini"

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    let meter = MicRecorder()

    private(set) var isRecording = false
    private(set) var phase: DictationPhase = .idle

    private(set) var apiKey: String?
    var isReady: Bool { apiKey != nil }

    // MARK: - Configuration

    /// **`gemini-3.8-flash`, the newest stable Flash**, and the pick is a
    /// price-per-quality one rather than a top-of-the-range one: audio bills at
    /// the model's input rate, so an hour of 32-tokens-per-second audio is
    /// ~115k tokens — about **$0.09** on this model.
    ///
    /// Two alternates, both one variable away and both worth an A/B on his own
    /// corpus before anything here is called settled:
    ///
    /// | `WT_GEMINI_MODEL=` | $/h | what it is |
    /// |---|---|---|
    /// | `gemini-3.5-flash-lite` | ~0.035 | audio at $0.30/1M — **six times cheaper than Scribe v2** |
    /// | `gemini-3.5-transcribe` | 0.18 | Google's **purpose-built** speech-to-text model, billed per minute |
    /// | `gemini-3.5-transcribe-live` | 0.30 | the streaming twin of it; this source does not stream |
    ///
    /// The transcribe models are not the default precisely because the prompt is
    /// the feature here: a dedicated STT model is the one least likely to take
    /// an instruction about which words to leave in English.
    static var model: String { env("WT_GEMINI_MODEL") ?? "gemini-3.8-flash" }

    /// **Published rates, per model, and the arithmetic behind the token-priced
    /// ones is in `model`'s table.** In the menu for `ElevenLabsSource.rate`'s
    /// reason. **If the row and the invoice disagree, the invoice is right.**
    static var rate: String {
        switch model {
        case "gemini-3.8-flash": return "~$0.09/h"
        case "gemini-3.5-flash-lite", "gemini-3.1-flash-lite": return "~$0.035/h"
        case "gemini-3.5-transcribe": return "$0.18/h"
        case "gemini-3.5-transcribe-live": return "$0.30/h"
        default: return "billed per token"
        }
    }

    var displayModelName: String { Self.model }

    /// **Thinking is on by default on Gemini 3 Flash, and it must not be.**
    ///
    /// `MEDIUM` is the default and the minimum accepted is `LOW` — there is no
    /// *off* on these models, and `MINIMAL` is documented to be **rejected**
    /// with a 400. For a transcription there is nothing to reason about, and
    /// every token of it is latency in front of a man standing with his finger
    /// off the key.
    ///
    /// It is deliberately **not** sent to a model whose name says `transcribe`:
    /// a purpose-built speech model has no thinking to configure, and a field it
    /// does not know is a 400 for the whole request. → `optionalFields`
    static var thinkingLevel: String? {
        guard !model.contains("transcribe") else { return nil }
        return env("WT_GEMINI_THINKING") ?? "LOW"
    }

    /// **What it is told, before the audio.**
    ///
    /// Two jobs in one paragraph, both learnt the hard way and both aimed at a
    /// language model rather than an acoustic one: *leave the English in
    /// English* (the thing Speechmatics could not be asked) and *do not tidy
    /// this up* (the thing `gpt-4o-transcribe` did to 25 seconds of his voice in
    /// the measurement above).
    ///
    /// It is written **in Romanian** on purpose — it is an instruction about a
    /// Romanian sentence, and the model is being asked to stay in that register.
    /// `WT_GEMINI_PROMPT` replaces it wholesale for an experiment.
    static func prompt() -> String {
        if let custom = env("WT_GEMINI_PROMPT") { return custom }
        var text = """
        Transcrie cuvânt cu cuvânt ce se aude în înregistrare.

        Vorbitorul dictează în română cu termeni tehnici în engleză. Păstrează \
        termenii englezești scriși corect în engleză — nu îi traduce și nu îi \
        scrie fonetic.

        Reguli stricte:
        - Redă exact ce s-a spus. NU rezuma, NU scurta, NU repara fraze \
        neterminate. Dacă vorbitorul se repetă sau se bâlbâie, scrie repetiția.
        - Răspunde DOAR cu transcrierea. Fără introduceri, fără ghilimele, fără \
        comentarii despre calitatea audio.
        - Dacă nu se aude nicio vorbă, răspunde cu un rând gol.
        """
        let terms = DictationVocabulary.promptTerms()
        if !terms.isEmpty {
            text += "\n\nTermeni care apar des și trebuie scriși așa: \(terms)."
        }
        return text
    }

    /// Generous, and bounded for the hotel Wi-Fi that accepts the connection and
    /// then stops — `ElevenLabsSource.requestTimeout`'s reason exactly.
    private static let requestTimeout: TimeInterval = 60

    /// **20 MB is the whole request**, base64 included, and base64 is four bytes
    /// for every three. That leaves ~14 MB of WAV, which at 16 kHz mono is about
    /// **seven minutes** — more than twice the longest dictation in the corpus
    /// (197 s). It is checked anyway, because the alternative is a 400 whose
    /// message is about JSON.
    private static let inlineCeiling = 14 * 1024 * 1024

    // MARK: - The key

    /// `~/.walkie-talkie/gemini.env`, `GEMINI_API_KEY=…`, environment first,
    /// following `--home`, re-read whenever the menu opens. The third file of
    /// this shape; see `ElevenLabsSource.configURL` for why it is a file and not
    /// the Keychain.
    static var configURL: URL { Outbox.home.appendingPathComponent("gemini.env") }

    private static var config: [String: String] = [:]

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
        // `GOOGLE_API_KEY` too, because that is what half of Google's own
        // examples export and a key that works everywhere else in his shell
        // should not be invisible here.
        let key = Self.env("GEMINI_API_KEY") ?? Self.env("GOOGLE_API_KEY")
        apiKey = (key?.isEmpty ?? true) ? nil : key
        return apiKey != nil
    }

    // MARK: - DictationSource

    func prepare() {
        if reloadKey() {
            let terms = DictationVocabulary.entries().count
            Log.info("Gemini ready — \(Self.model), \(Self.rate)"
                     + (terms > 0 ? ", \(terms) terms in the prompt" : ", no vocabulary file"))
        } else {
            Log.error("Gemini: no API key — put GEMINI_API_KEY=… in \(Self.configURL.path)")
        }
    }

    /// Yes, and spliced — `ElevenLabsSource.mark`'s mechanism, for its reason:
    /// the file this records is the file it uploads.
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

    private var markersInAudio = false

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard apiKey != nil else {
            return "no Gemini API key — see \(Self.configURL.lastPathComponent)"
        }
        let wav = Outbox.shotsDir.appendingPathComponent("mic-\(Int(Date().timeIntervalSince1970)).wav")
        if let why = meter.start(to: wav) { return why }
        markersInAudio = false
        isRecording = true
        phase = .listening
        Log.info("🎙️ recording started for Gemini — \(Self.model), \(wav.lastPathComponent)")
        didBegin?()
        return nil
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        phase = .transcribing("uploading")
        didStopListening?()

        // Read **before** anything else touches the recorder: `voicedSeconds`
        // describes the recording that just ended and is reset by the next
        // `start()`, and it is the denominator `warnIfShort` needs.
        let voiced = meter.voicedSeconds
        guard let (wav, duration) = meter.stop() else {
            Log.info("recording discarded — under \(MicRecorder.minimumDuration)s")
            phase = .done("empty")
            didEnd?(.silent(""))
            return
        }
        guard let key = apiKey else {
            return finishWithFailure(wav, duration, "the Gemini key went away mid-sentence")
        }
        Log.info(String(format: "🎙️ recording stopped — %.1fs, uploading to %@", duration, Self.model))

        let startedAt = Date()
        Self.transcribe(wav: wav, key: key) { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                switch outcome {
                case .failure(let why):
                    self.finishWithFailure(wav, duration, why)
                case .success(let text) where text.isEmpty:
                    Log.error("Gemini returned no words")
                    try? FileManager.default.removeItem(at: wav)
                    self.phase = .done("empty")
                    self.didEnd?(.silent("No words detected"))
                case .success(let text):
                    Log.info(String(format: "gemini: %d chars in %.2fs (%.2f× audio)",
                                    text.count, elapsed, elapsed / max(duration, 0.01)))
                    self.didTranscribe?(DictationResult(
                        text: text, language: nil, audio: wav, duration: duration,
                        engine: "gemini", warning: Self.warnIfShort(text, voiced: voiced),
                        delivery: .route, via: "gemini-generatecontent",
                        markersInAudio: self.markersInAudio,
                        engineLabel: self.displayModelName))
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
        didStopListening?()
        let taken = meter.stop()
        didEnd?(.cancelled(audio: taken?.url, duration: taken?.duration ?? 0))
    }

    /// `ElevenLabsSource.finishWithFailure`, word for word and for its reason: a
    /// sentence that could not be uploaded is not a sentence that was never said.
    private func finishWithFailure(_ wav: URL, _ duration: TimeInterval, _ why: String) {
        Log.error("Gemini: \(why)")
        phase = .done("error")
        didEnd?(.failed(why: "Gemini: \(why)", audio: wav, duration: duration))
    }

    // MARK: - The note that only a language model needs

    /// **Does this look like the whole sentence, or like the gist of it?**
    ///
    /// Nothing else in this app can catch a language model that shortens: there
    /// is no confidence to fall, no language probability to slip, and the text
    /// itself is fluent. The only signal left is *how much text came back for
    /// how much speech*, and getting that right took a measurement, because the
    /// obvious version of it does not work.
    ///
    /// **Against wall-clock seconds it is useless.** Over the 2,039 corpus
    /// samples longer than six seconds, characters per second runs: median 9.9,
    /// p10 5.7, **p5 4.3**. The measured truncation — `gpt-4o-transcribe` handed
    /// 24.8 s of Romanian and returning one and a half sentences — sits at
    /// **3.1**, which is inside his own ordinary tail. A floor that catches it
    /// fires on **3.9%** of good dictations, and a warning that cries wolf one
    /// time in twenty-five is a warning he stops reading.
    ///
    /// **Against *voiced* seconds it works**, because the legitimate slow
    /// dictations are the ones full of pauses and this divides the pauses out.
    /// Same corpus, replayed through `MicRecorder`'s own voiced meter
    /// (`evals/voiced-seconds.py`): median **25.9** characters per voiced
    /// second, p1 12.4, and not one sample of 440 under 6. The same truncation
    /// scores **12.7** — 5.8 s of voice, 74 characters, against the 222 the
    /// engine that recorded it produced from the same audio.
    ///
    /// So the floor is **13**: just above the one failure measured, and it fires
    /// on **1.1%** of his real dictations (5 of 440). That is one observed
    /// failure, not a distribution of them — the number moves when there are
    /// more. → `evals/`
    ///
    /// It never withholds the text. The alternative to a suspicious transcript
    /// is silence, and silence is the one outcome he cannot notice.
    static let charactersPerVoicedSecondFloor = 13.0

    static func warnIfShort(_ text: String, voiced: TimeInterval) -> String? {
        // Under three seconds of actual voice nothing is claimed: *"da"* is a
        // legitimate answer to an agent and is two characters.
        guard voiced >= 3 else { return nil }
        let rate = Double(text.count) / voiced
        guard rate < charactersPerVoicedSecondFloor else { return nil }
        return String(format: "⚠️ %.0f s of speech came back as %d characters — "
                      + "a language model can shorten instead of mishearing; check the end",
                      voiced, text.count)
    }

    // MARK: - The call

    enum Outcome {
        case success(String)
        case failure(String)
    }

    /// **One `generateContent`, and one retry that drops the optional fields.**
    ///
    /// The retry is not the network's — that one is here too — it is for the
    /// **400 that names a field**. `thinking_level` is a Gemini 3 spelling that
    /// older and purpose-built models do not take, and the whole request is
    /// rejected for it. Rather than pin this file to one model generation, an
    /// invalid-argument reply is retried once with nothing optional in it, and
    /// the log says what was dropped — so a model this file has never seen still
    /// transcribes, one round trip later.
    static func transcribe(wav: URL, key: String, bare: Bool = false, attempt: Int = 0,
                           _ done: @escaping (Outcome) -> Void) {
        guard let audio = try? Data(contentsOf: wav) else {
            return done(.failure("the recording could not be read — \(wav.lastPathComponent)"))
        }
        guard audio.count <= inlineCeiling else {
            return done(.failure(String(format: "the recording is %.1f MB and the inline limit is "
                                        + "20 MB with the base64 — that is over seven minutes",
                                        Double(audio.count) / 1_048_576)))
        }

        var body: [String: Any] = [
            "contents": [["parts": [["text": prompt()],
                                    ["inline_data": ["mime_type": "audio/wav",
                                                     "data": audio.base64EncodedString()]]]]]
        ]
        var generation: [String: Any] = ["maxOutputTokens": 8192]
        if !bare, let level = thinkingLevel {
            // Gemini 3 replaced `thinking_budget` with `thinking_level`, and
            // says the two may not both be sent. Only the new spelling goes out.
            generation["thinking_config"] = ["thinking_level": level]
        }
        body["generationConfig"] = generation

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure("the request could not be encoded"))
        }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
            + "\(model):generateContent"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.timeoutInterval = requestTimeout
        // **The header, not `?key=`.** Both are accepted; a key in a query
        // string is a key in every proxy log and every crash report between here
        // and Google.
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let retriable = error != nil || code == 429 || (500...599).contains(code)
            if retriable, attempt == 0 {
                Log.error("Gemini attempt 1 failed (\(error?.localizedDescription ?? "HTTP \(code)")) — retrying")
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                    transcribe(wav: wav, key: key, bare: bare, attempt: 1, done)
                }
                return
            }
            if let error { return done(.failure(error.localizedDescription)) }
            guard let data else { return done(.failure("HTTP \(code) with no body")) }
            let detail = String(data: data.prefix(500), encoding: .utf8) ?? ""

            // **A 400 is retried bare — unless the 400 is about the key.**
            // Google answers an invalid key with a 400 too, and re-sending the
            // whole recording to be told the same thing is a second upload and a
            // second second of his settle for nothing.
            let aboutTheKey = ["API_KEY", "UNAUTHENTICATED", "PERMISSION_DENIED"]
                .contains { detail.contains($0) }
            if code == 400, !bare, !aboutTheKey {
                Log.error("Gemini rejected the request (\(detail.prefix(200))) — "
                          + "retrying with no thinking configuration")
                return transcribe(wav: wav, key: key, bare: true, attempt: 0, done)
            }
            guard code == 200 else { return done(.failure("HTTP \(code) \(detail)")) }
            done(read(data))
        }.resume()
    }

    /// **The reply, and the two ways it can be empty without being an error.**
    ///
    /// `promptFeedback.blockReason` is the request refused outright; a
    /// `finishReason` that is not `STOP` is the answer cut short — `MAX_TOKENS`
    /// on a very long dictation, `SAFETY` on a sentence that tripped a filter.
    /// Both are said out loud rather than returned as no words, because *nothing
    /// was heard* and *it would not tell me* are different things to him: the
    /// first is a misfire he shrugs at, the second is a sentence he has to say
    /// again a different way.
    private static func read(_ data: Data) -> Outcome {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("unreadable reply from Gemini")
        }
        if let feedback = json["promptFeedback"] as? [String: Any],
           let blocked = feedback["blockReason"] as? String {
            return .failure("the request was blocked (\(blocked))")
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first else {
            return .failure("no candidates in the reply")
        }
        let finish = first["finishReason"] as? String ?? "STOP"
        let parts = (first["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty, finish != "STOP" { return .failure("the model stopped early (\(finish))") }
        var cleaned = clean(text)
        if finish != "STOP", !cleaned.isEmpty {
            // Text and a bad finish reason together: keep the text — it is his
            // sentence — and let the short-text note downstream say it looks
            // truncated, which is exactly what it is.
            Log.error("Gemini finished as \(finish) with \(cleaned.count) characters")
        }
        if cleaned.isEmpty { cleaned = "" }
        return .success(cleaned)
    }

    /// **The three things a language model wraps a transcript in**, and nothing
    /// more than those.
    ///
    /// A fenced block, a pair of quotes round the whole thing, and a `Transcriere:`
    /// label — each of them is a wrapper the prompt already asks it not to add,
    /// and each of them has to be survivable anyway, because a transcript that
    /// arrives inside ```` ``` ```` is pasted into his terminal as ```` ``` ````.
    ///
    /// Deliberately timid: it strips only a wrapper that encloses the **whole**
    /// reply. A quotation mark in the middle of a sentence is his.
    private static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for label in ["Transcriere:", "Transcript:", "Transcriere："] where text.hasPrefix(label) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\""),
           !text.dropFirst().dropLast().contains("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func describe() -> [String: Any] {
        ["ready": isReady, "model": Self.model, "rate": Self.rate,
         "thinking": Self.thinkingLevel ?? "n/a",
         "vocab": DictationVocabulary.entries().count,
         "vocabFile": DictationVocabulary.url.path,
         "keyFile": Self.configURL.path]
    }
}
