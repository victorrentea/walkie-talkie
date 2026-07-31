import Foundation
import SQLite3

/// Picks up finished Wispr Flow dictations by polling its local history DB.
///
/// Why the DB and not the keyboard: Wispr pastes the transcript wherever the
/// caret happens to be. Victor dictates *about* what he is looking at (a
/// browser, a PDF), so there is often no caret worth pasting into — but the
/// transcript still has to reach the agent. `flow.sqlite` is the one place the
/// text always lands, regardless of focus.
///
/// `~/Library/Application Support/Wispr Flow/flow.sqlite`, table `History`:
///   `timestamp`      TEXT, `YYYY-MM-DD HH:MM:SS.SSS +00:00` (UTC, fixed width
///                    → lexicographic compare == chronological compare)
///   `status`         `formatted` once Wispr has finished post-processing;
///                    `raw_transcript` when only ASR ran
///   `formattedText`  the polished text (always present when `formatted`)
///   `asrText`        raw ASR, the fallback
///   `app`            app that had focus during dictation
///
/// Opened **read-only** while Wispr keeps writing; the `-wal`/`-shm` siblings
/// are readable by the same user, so committed rows are visible immediately.
/// Query is served by Wispr's own `idx_history_timestamp_archived_status`.
final class WisprWatcher {

    /// Called on a background queue for each newly completed dictation.
    var onTranscript: ((_ text: String, _ app: String?) -> Void)?

    private let dbPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wispr Flow/flow.sqlite").path

    private var watermark: String = ""
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr")

    var isAvailable: Bool { FileManager.default.fileExists(atPath: dbPath) }

    func start(pollInterval: TimeInterval = 1.0) {
        guard isAvailable else {
            Log.error("Wispr Flow DB not found — dictation capture disabled")
            return
        }
        // Baseline at the newest existing row so launching the tool never
        // replays 11k historical dictations into the session.
        watermark = latestTimestamp() ?? Self.nowUTC()
        Log.info("watching Wispr transcripts newer than \(watermark)")

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    // MARK: - Polling

    private func poll() {
        guard let db = openReadOnly() else { return }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT timestamp, COALESCE(NULLIF(formattedText,''), asrText), app
            FROM History
            WHERE timestamp > ? AND status IN ('formatted','raw_transcript')
            ORDER BY timestamp ASC
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, watermark, -1, SQLITE_TRANSIENT)

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let ts = column(stmt, 0) else { continue }
            watermark = ts
            guard let text = column(stmt, 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            let app = column(stmt, 2)
            onTranscript?(text, app)
        }
    }

    private func latestTimestamp() -> String? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MAX(timestamp) FROM History", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? column(stmt, 0) : nil
    }

    private func openReadOnly() -> OpaquePointer? {
        var db: OpaquePointer?
        // URI form so `mode=ro` applies; SQLITE_OPEN_READONLY alone would still
        // want to create/extend the -shm file on some volumes.
        let uri = "file://\(dbPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbPath)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 200)
        return db
    }

    private func column(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    private static func nowUTC() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS +00:00"
        return f.string(from: Date())
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
