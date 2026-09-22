import Foundation
import SQLite3

/// **Wispr Flow's own record of a dictation, read and never written** — the
/// `History` table of `~/Library/Application Support/Wispr Flow/flow.sqlite`.
///
/// One row per dictation, created at the gesture with an empty `status` and
/// filled in when Wispr is done: `formatted` (and `pastedText`, the exact text
/// it inserted), `dismissed`, `empty`, `no_audio`, `error`. `e2eLatency` is its
/// own measurement of the round trip — over 589 dictations in the 30 days to
/// 2026-09-12: p50 2.2 s, p90 3.5 s, p99 7.1 s, max 13.7 s.
///
/// **Why this file exists at all, given the rule against it.** *Never Wispr
/// Flow's database as a recogniser or fallback* (2026-08-29, restated
/// 2026-09-12) stands: nothing here transcribes anything. What the wrap could
/// not answer was *is Wispr finished* — its delivery is a ⌘V the tap swallows,
/// and on the evenings of 2026-09-12 two dictations were inserted with **no ⌘V
/// and no pasteboard change at all** (an Accessibility insertion, as far as
/// anything outside Wispr can tell), so the relay waited its whole timeout for
/// a key that was never coming, with the ring's lightning on screen the whole
/// time. Every other signal was tried and is dead: Wispr's unified log is
/// silent, its pill's window frame and AX tree never change, `config.json` has
/// no insertion-method setting to pin it to ⌘V. The row is the one place the
/// answer is written, and Victor asked for it to be read: *"let's run a bunch
/// of experiments … including looking into its own files on disk (or perhaps
/// where else stuff gets saved in the database)"* — then *"ok. build"*.
///
/// **Read-only, and cheap.** The file is in WAL mode, so a reader never blocks
/// Wispr's writer; `newest()` is `order by rowid desc limit 1` and measured at
/// 6 ms on the 3.5 GB file. The handle is kept open for the process and dropped
/// on any error so the next call reopens it.
enum WisprHistory {

    struct Entry {
        let rowid: Int64
        /// `""` while Wispr is still working on it.
        let status: String
        /// **What the recogniser heard, before any formatting pass** — the
        /// column that tells *Wispr is still thinking* from *Wispr heard
        /// nothing*. Two seconds of digital silence left row 12814 in
        /// `raw_transcript` for ever with every text column empty, and the relay
        /// waited out its whole 30 s capture on it (adversarial round 2).
        let asrText: String
        /// **What Wispr actually inserted** — empty when it inserted nothing.
        let pastedText: String
        /// **What Wispr made of the audio, whether or not it ever inserted it**
        /// (2026-09-13). `pastedText` is a record of an *insertion*, so a Wispr
        /// that cannot insert — one whose Accessibility grant has been taken
        /// away, which is the shape the wrap is heading for — fills this column
        /// and leaves that one empty. The words are the same words; the
        /// difference between the two columns is whether they reached the screen.
        let formattedText: String
        /// Whichever of the two carries the sentence, insertion first: a row that
        /// was pasted says so in `pastedText`, and `formattedText` is what a row
        /// has when nothing was pasted.
        var text: String { pastedText.isEmpty ? formattedText : pastedText }
        let e2eLatency: Double
        let app: String
        /// **Which microphone Wispr recorded through** — the column that ended
        /// two hours of "Wispr is not completing transcriptions" on 2026-09-13 by
        /// answering `Built-in mic (recommended)` six times while the rig was
        /// playing a WAV into a virtual device. Read here so the relay can say it
        /// without a second SQLite client.
        let micDevice: String
        /// Wispr's own reading of the language, for the corpus.
        let language: String
        /// Unix time of the gesture that opened it — the row is created then.
        let startedAt: TimeInterval
    }

    /// The same file `WisprNotes` reads. Kept here as well because every rule
    /// and every journal entry names `WisprHistory.url`.
    static var url: URL { WisprFlowDB.url }

    private static var lock: NSLock { WisprFlowDB.lock }

    /// The newest row, or nil when the file is missing or cannot be read.
    static func newest() -> Entry? {
        read("from History order by rowid desc limit 1")
    }

    /// **The microphone Wispr last named** — the newest row that names one.
    /// A row is created at the gesture with the column empty, so between the
    /// chord and Wispr filling it in, this is the best guess there is: Wispr
    /// switches devices far less often than he dictates.
    static func lastNamedMic() -> String {
        read("from History where coalesce(micDevice, '') != '' order by rowid desc limit 1")?.micDevice ?? ""
    }

    /// **One row by its rowid**, which `newest()` stops being able to answer the
    /// moment a second dictation starts (2026-09-14).
    ///
    /// A sentence Victor cancelled during the settle keeps a claim on the
    /// swallow until Wispr has finished with it, and a new gesture may open the
    /// next dictation on top of that — so *is the cancelled row done yet* has to
    /// be asked about **that** row and not about whatever is on top now, which
    /// by then is the new dictation's. `status(of:)` compared against
    /// `newest()` and silently answered `""` for ever.
    static func entry(rowid: Int64) -> Entry? {
        read("from History where rowid = \(rowid) limit 1")
    }

    /// The one query, with the column list stated once: two readers that select
    /// different columns in the same order are a bug waiting for a schema change.
    private static func read(_ tail: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        guard let db = WisprFlowDB.open() else { return nil }
        let sql = """
            select rowid, coalesce(status, ''), coalesce(pastedText, ''), coalesce(formattedText, ''),
                   coalesce(e2eLatency, 0), coalesce(app, ''), coalesce(micDevice, ''),
                   coalesce(language, ''), coalesce(strftime('%s', timestamp), '0'),
                   coalesce(asrText, '')
            \(tail)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            Log.error("wispr history: \(String(cString: sqlite3_errmsg(db)))")
            WisprFlowDB.reset()
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        return Entry(rowid: sqlite3_column_int64(stmt, 0), status: text(1), asrText: text(9),
                     pastedText: text(2),
                     formattedText: text(3), e2eLatency: sqlite3_column_double(stmt, 4),
                     app: text(5), micDevice: text(6), language: text(7),
                     startedAt: Double(text(8)) ?? 0)
    }

}
