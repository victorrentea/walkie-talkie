import Foundation

/// Keeps the **recording beside the transcript** — every dictation the relay
/// takes, as the audio it captured and the words the local model made of it.
///
/// This is the record the recogniser is judged against. The relay does its own
/// recording and its own transcription, so there is exactly one reading of each
/// sample and no second opinion baked in: a later evaluation scores another
/// model against these WAVs, it does not read a verdict out of the manifest.
///
/// ## It lives outside Caches, deliberately
///
/// `~/.walkie-talkie/voice-corpus/`, next to the outbox and by the outbox's
/// argument: screenshots are a staging area whose purpose expires within the
/// turn that reads them, and Caches is right for those. This is the opposite —
/// a corpus that is worthless unless it accumulates, and a folder the system may
/// purge under disk pressure is not a corpus. `--home` moves it, exactly as it
/// moves the outbox and unlike the shots.
///
/// ## What a sample is
///
/// ```
/// voice-corpus/2026-08-17/14-30-22-local123.wav   ← what Victor said
/// voice-corpus/2026-08-17/14-30-22-local123.txt   ← what the model made of it
/// voice-corpus/corpus.jsonl                        ← one line per sample
/// ```
///
/// Day folders because he dictates 40–90 times a day (measured over the fortnight
/// this was written in), and a flat folder stops being listable within a week.
///
/// ## Everything the microphone hears, whatever the relay then does with it
///
/// Filing a recording is not *acting* on a dictation, so nothing that stops a
/// delivery stops this: a dictation refused at a shell prompt is still Victor's
/// voice with the model's reading of it, which is the only thing this collects,
/// and the corpus is a file on his own disk rather than something sent anywhere.
/// It is what kept this running through pause for as long as pause existed.
final class VoiceCorpus {

    /// Beside the outbox, and moved by `--home` with it.
    static var root: URL { Outbox.home.appendingPathComponent("voice-corpus") }
    static var manifestURL: URL { root.appendingPathComponent("corpus.jsonl") }

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.corpus", qos: .utility)

    /// File one dictation: the audio the relay recorded and the local model's
    /// reading of it.
    ///
    /// The manifest stamps `engine: "whisper-local"` and carries no second
    /// reference transcript, deliberately. There is one reading of this sample
    /// and scoring the model that produced it against itself would measure
    /// nothing — the reference for an evaluation is a human, or another model,
    /// run over these WAVs later. An absent field is a question a reader asks,
    /// where a duplicated one is an answer they believe.
    ///
    /// The bytes are read on the caller's thread on purpose: the staged WAV is
    /// deleted as soon as this returns, and a copy queued for later would race it.
    func captureLocal(wav: URL, text: String, language: String?, duration: TimeInterval, app: String?) {
        guard let audio = try? Data(contentsOf: wav), audio.count > 44 else {
            Log.error("corpus: local recording vanished before it could be filed")
            return
        }
        let when = Date()
        queue.async { [weak self] in
            self?.writeLocal(audio: audio, text: text, language: language,
                             duration: duration, app: app, when: when)
        }
    }

    private func writeLocal(audio: Data, text: String, language: String?,
                            duration: TimeInterval, app: String?, when: Date) {
        let dir = Self.root.appendingPathComponent(Self.dayFormatter.string(from: when))
        // The clock is the key. Two relays recording the same second is not a
        // thing — there is one microphone and one hand on the button — but the
        // millisecond keeps a retry from overwriting a sample.
        let stem = "\(Self.timeFormatter.string(from: when))-local\(Int(when.timeIntervalSince1970 * 1000) % 1000)"
        let wav = dir.appendingPathComponent(stem + ".wav")
        let txt = dir.appendingPathComponent(stem + ".txt")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try audio.write(to: wav)
            try Data((text + "\n").utf8).write(to: txt)
        } catch {
            Log.error("corpus: could not write \(stem): \(error)")
            return
        }

        var obj: [String: Any] = [
            "id": stem,
            "ts": ISO8601DateFormatter().string(from: when),
            "wav": Self.relative(wav),
            "txt": Self.relative(txt),
            "bytes": audio.count,
            "text": text,
            "engine": "whisper-local",
            "duration": duration,
            "session": SessionLabel.value,
        ]
        if let v = app, !v.isEmpty { obj["app"] = v }
        if let v = language, !v.isEmpty { obj["detectedLanguage"] = v }

        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)
        if !FileManager.default.fileExists(atPath: Self.manifestURL.path) {
            FileManager.default.createFile(atPath: Self.manifestURL.path, contents: Data())
        }
        guard let handle = try? FileHandle(forWritingTo: Self.manifestURL) else {
            Log.error("corpus: manifest unavailable at \(Self.manifestURL.path)")
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        Log.info(String(format: "corpus: %@ — %d KB, %.1fs (local)", stem, audio.count / 1024, duration))
    }

    private static func relative(_ url: URL) -> String {
        let base = root.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    // MARK: - Time

    /// The folders and names are **local time**, because they are read by Victor
    /// against his own day; the manifest's `ts` is ISO 8601 for whoever reads it
    /// with a machine.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH-mm-ss"
        return f
    }()
}
