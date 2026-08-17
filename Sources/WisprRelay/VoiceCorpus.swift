import Foundation
import SQLite3

/// Keeps the **recording beside the transcript**, so that one day a local ASR
/// model can be measured against Wispr Flow on Victor's own voice.
///
/// This is groundwork and nothing else: the relay does not transcribe anything
/// and does not intend to yet. What it cannot do later is go back in time and
/// collect the samples — Wispr keeps the audio for a while and then drops it
/// (measured when this was written: **495 rows still had audio out of 11,999**,
/// i.e. roughly the last fortnight, the rest text-only forever). Every day the
/// relay runs without this is a day of paired data that cannot be recovered.
///
/// ## The audio is Wispr's own, not a second recording
///
/// `History.audio` is a **complete `.wav` file** — RIFF header and all, 16 kHz
/// mono 16-bit PCM (verified from the blob's first 48 bytes; the byte counts
/// match `duration × 32000` on every row checked). So the relay copies bytes; it
/// never opens the microphone.
///
/// That matters beyond convenience. A parallel recording made by this app would
/// be a *different* signal from the one Wispr scored — different device
/// selection, different gain, different start and end points — and a benchmark
/// where the two models heard different audio measures nothing. Taking Wispr's
/// own bytes is the only way the comparison is like-for-like.
///
/// ## It lives outside Caches, deliberately
///
/// `~/.wispr-relay/voice-corpus/`, next to the outbox and by the outbox's
/// argument: screenshots are a staging area whose purpose expires within the
/// turn that reads them, and Caches is right for those. This is the opposite —
/// a corpus that is worthless unless it accumulates, and a folder the system may
/// purge under disk pressure is not a corpus. `--home` moves it, exactly as it
/// moves the outbox and unlike the shots.
///
/// ## What a sample is
///
/// ```
/// voice-corpus/2026-08-17/14-30-22-a1b2c3d4.wav   ← what Victor said
/// voice-corpus/2026-08-17/14-30-22-a1b2c3d4.txt   ← what Wispr made of it
/// voice-corpus/corpus.jsonl                        ← one line per sample
/// ```
///
/// Day folders because he dictates 40–90 times a day (measured over the fortnight
/// this was written in), and a flat folder stops being listable within a week.
///
/// **The `.txt` holds the formatted text** — what Wispr actually handed over and
/// what Victor saw. The manifest carries `asr` beside it, and that distinction is
/// the whole point of having a manifest: `formattedText` has been through Wispr's
/// LLM post-processing (punctuation, casing, the user dictionary), so scoring a
/// local Whisper against it charges the model for work an ASR does not do. `asr`
/// is the apples-to-apples reference; the formatted text is the bar the *product*
/// has to clear. Both are worth keeping and they answer different questions.
///
/// ## Everything the watcher sees, paused included
///
/// Pause stops the relay *acting* on a dictation — it is documented as touching
/// exactly four places and this is not one of them. A paused dictation is still
/// Victor's voice with Wispr's reading of it, which is the only thing this
/// collects, and the corpus is a file on his own disk rather than something sent
/// anywhere. Narrowing it to unpaused would throw away the minutes he spends
/// dictating into a browser — some of his longest, and the ones with the least
/// technical vocabulary, which is precisely the coverage a corpus of agent
/// prompts would otherwise lack.
final class VoiceCorpus {

    /// Beside the outbox, and moved by `--home` with it.
    static var root: URL { Outbox.home.appendingPathComponent("voice-corpus") }
    static var manifestURL: URL { root.appendingPathComponent("corpus.jsonl") }

    /// Wispr writes the row's text and its audio blob in its own order, and the
    /// watcher can win that race by a poll or two. Re-asking a few times costs
    /// nothing and is the difference between a sample and a gap.
    private static let retryDelays: [TimeInterval] = [0, 1.5, 4.0]

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.corpus", qos: .utility)

    /// Called with the id the watcher just delivered a transcript for. Returns
    /// immediately: the blob is megabytes, and nothing about collecting it may
    /// delay getting the words to the agent.
    ///
    /// `origin` overrides what lands in the manifest's `session`. Live capture
    /// leaves it nil and the sample is stamped with the relay session that heard
    /// it, which is the truth. A **back-fill** reaches back to rows dictated days
    /// ago, from sessions long gone — stamping those with whatever session
    /// happens to be running now would not be a useless field, it would be a
    /// wrong one, and the corpus is meant to be read months from now.
    func capture(id: String, origin: String? = nil) {
        queue.async { [weak self] in self?.attempt(id: id, origin: origin, step: 0) }
    }

    // MARK: - Fetch

    private func attempt(id: String, origin: String?, step: Int) {
        guard step < Self.retryDelays.count else {
            Log.info("corpus: no audio for \(id.prefix(8)) — sample skipped")
            return
        }
        if Self.retryDelays[step] > 0 { Thread.sleep(forTimeInterval: Self.retryDelays[step]) }

        guard let row = readRow(id: id) else {
            attempt(id: id, origin: origin, step: step + 1)
            return
        }
        write(row, origin: origin)
    }

    private struct Row {
        let id: String
        let timestamp: String
        let audio: Data
        let formatted: String
        let asr: String
        let app: String?
        let language: String?
        let detectedLanguage: String?
        let duration: Double?
        let words: Int?
        let micDevice: String?
    }

    private func readRow(id: String) -> Row? {
        guard let db = FlowDB.openReadOnly() else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT timestamp, audio, formattedText, asrText, app, language,
                   detectedLanguage, duration, numWords, micDevice
            FROM History WHERE transcriptEntityId = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        // No audio yet (or ever) is the one thing worth retrying for; everything
        // else on the row is already there by the time the text is.
        guard let audio = FlowDB.blob(stmt, 1), audio.count > 44 else { return nil }

        return Row(id: id,
                   timestamp: FlowDB.text(stmt, 0) ?? "",
                   audio: audio,
                   formatted: FlowDB.text(stmt, 2) ?? "",
                   asr: FlowDB.text(stmt, 3) ?? "",
                   app: FlowDB.text(stmt, 4),
                   language: FlowDB.text(stmt, 5),
                   detectedLanguage: FlowDB.text(stmt, 6),
                   duration: FlowDB.double(stmt, 7),
                   words: FlowDB.int(stmt, 8),
                   micDevice: FlowDB.text(stmt, 9))
    }

    // MARK: - Write

    private func write(_ row: Row, origin: String?) {
        let when = Self.parse(row.timestamp) ?? Date()
        let short = String(row.id.prefix(8))
        let dir = Self.root.appendingPathComponent(Self.dayFormatter.string(from: when))
        let stem = "\(Self.timeFormatter.string(from: when))-\(short)"
        let wav = dir.appendingPathComponent(stem + ".wav")
        let txt = dir.appendingPathComponent(stem + ".txt")

        // Two relays run at once often enough (one per session), and both watch
        // the same DB — so both are handed the same id. The sample is keyed by
        // Wispr's own row id, so whoever gets there first has written the whole
        // truth and the second has nothing to add.
        guard !FileManager.default.fileExists(atPath: wav.path) else { return }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try row.audio.write(to: wav)
            // The transcript alone, ending in a newline: this file is meant to be
            // diffed against another model's output, and metadata mixed into it
            // would have to be stripped by everything that reads it. The metadata
            // is in the manifest, which is the thing built to carry it.
            let reference = row.formatted.isEmpty ? row.asr : row.formatted
            try Data((reference + "\n").utf8).write(to: txt)
        } catch {
            Log.error("corpus: could not write \(stem): \(error)")
            return
        }

        appendManifest(row, when: when, wav: wav, txt: txt, origin: origin)
        Log.info("corpus: \(stem) — \(row.audio.count / 1024) KB, \(String(format: "%.1f", row.duration ?? 0))s")
    }

    /// One JSON object per line, paths **relative to the corpus root** so the
    /// whole folder can be moved or copied to another machine and still read.
    private func appendManifest(_ row: Row, when: Date, wav: URL, txt: URL, origin: String?) {
        var obj: [String: Any] = [
            "id": row.id,
            "ts": ISO8601DateFormatter().string(from: when),
            "wisprTs": row.timestamp,
            "wav": Self.relative(wav),
            "txt": Self.relative(txt),
            "bytes": row.audio.count,
            // Both readings, and they are not the same claim — see the note on
            // this type. `text` is what Wispr handed over; `asr` is what its
            // recogniser heard before the post-processing.
            "text": row.formatted,
            "asr": row.asr,
            "session": origin ?? SessionLabel.value,
        ]
        if let v = row.duration { obj["duration"] = v }
        if let v = row.words { obj["words"] = v }
        if let v = row.app, !v.isEmpty { obj["app"] = v }
        if let v = row.language, !v.isEmpty { obj["language"] = v }
        if let v = row.detectedLanguage, !v.isEmpty { obj["detectedLanguage"] = v }
        if let v = row.micDevice, !v.isEmpty { obj["mic"] = v }

        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        data.append(0x0A)

        // Same single-`write(2)` discipline as the outbox: two relays may append
        // here, and a reader must never meet half a line.
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
    }

    private static func relative(_ url: URL) -> String {
        let base = root.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    // MARK: - Time

    /// Wispr stamps UTC (`2026-08-17 14:30:22.123 +00:00`); the folders and names
    /// are **local**, because they are read by Victor against his own day.
    private static func parse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS XXX"
        return f.date(from: s)
    }

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
