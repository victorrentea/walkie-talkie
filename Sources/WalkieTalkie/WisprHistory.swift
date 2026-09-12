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
        let pastedText: String
        let e2eLatency: Double
        let app: String
        /// Unix time of the gesture that opened it — the row is created then.
        let startedAt: TimeInterval
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wispr Flow/flow.sqlite")

    private static var db: OpaquePointer?
    private static let lock = NSLock()

    /// The newest row, or nil when the file is missing or cannot be read.
    static func newest() -> Entry? {
        lock.lock(); defer { lock.unlock() }
        guard let db = open() else { return nil }
        let sql = """
            select rowid, coalesce(status, ''), coalesce(pastedText, ''), coalesce(e2eLatency, 0),
                   coalesce(app, ''), coalesce(strftime('%s', timestamp), '0')
            from History order by rowid desc limit 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            Log.error("wispr history: \(String(cString: sqlite3_errmsg(db)))")
            reset()
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        return Entry(rowid: sqlite3_column_int64(stmt, 0), status: text(1), pastedText: text(2),
                     e2eLatency: sqlite3_column_double(stmt, 3), app: text(4),
                     startedAt: Double(text(5)) ?? 0)
    }

    private static func open() -> OpaquePointer? {
        if let db { return db }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var handle: OpaquePointer?
        // `mode=ro` in the URI on top of the flag: neither the journal nor the
        // shm may be created by this process if they are somehow absent.
        let uri = "file:" + url.path.replacingOccurrences(of: " ", with: "%20") + "?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let h = handle { sqlite3_close(h) }
            Log.error("wispr history: could not open \(url.path) read-only")
            return nil
        }
        sqlite3_busy_timeout(handle, 50)
        db = handle
        return handle
    }

    private static func reset() {
        if let db { sqlite3_close(db) }
        db = nil
    }
}
