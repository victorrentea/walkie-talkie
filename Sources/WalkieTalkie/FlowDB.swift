import Foundation
import SQLite3

/// Read-only access to Wispr Flow's own history database.
///
/// `~/Library/Application Support/Wispr Flow/flow.sqlite`, table `History` —
/// see `WisprWatcher` for the columns that matter and why the DB is the signal
/// rather than the keyboard.
///
/// This exists because **two** things now read that file: `WisprWatcher` polls
/// it for finished transcripts, and `VoiceCorpus` goes back for the recording
/// that produced one. Opening it correctly is not obvious — the URI form and
/// `mode=ro` are load-bearing, and the busy timeout matters while Wispr is
/// writing — so the opener is shared rather than remembered twice.
enum FlowDB {

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wispr Flow/flow.sqlite").path

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: path) }

    /// Opened **read-only** while Wispr keeps writing; the `-wal`/`-shm` siblings
    /// are readable by the same user, so committed rows are visible immediately.
    ///
    /// URI form so `mode=ro` applies: `SQLITE_OPEN_READONLY` alone would still
    /// want to create/extend the `-shm` file on some volumes.
    static func openReadOnly() -> OpaquePointer? {
        var db: OpaquePointer?
        let uri = "file://\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        sqlite3_busy_timeout(db, 200)
        return db
    }

    /// The recording behind one row, as the complete 16 kHz mono WAV Wispr
    /// stored — the same bytes Wispr's own recogniser scored.
    ///
    /// Used by the local-Whisper engine, which is why it is here and not private
    /// to `VoiceCorpus`: the corpus wants the audio *and* the metadata in order
    /// to file a sample, while transcription wants only the audio and wants it
    /// as fast as the row can be found.
    static func audio(forID id: String) -> Data? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT audio FROM History WHERE transcriptEntityId = ?",
                                 -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let data = blob(stmt, 0), data.count > 44 else { return nil }
        return data
    }

    /// Wispr's own reading of one row, the way the watcher would have delivered
    /// it — same `COALESCE`, so a replay is the transcript that really was sent.
    static func transcriptRow(forID id: String) -> (text: String, app: String?)? {
        guard let db = openReadOnly() else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT COALESCE(NULLIF(formattedText,''), asrText), app FROM History WHERE transcriptEntityId = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let t = text(stmt, 0), !t.isEmpty else { return nil }
        return (t, text(stmt, 1))
    }

    static func text(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstr)
    }

    static func double(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    static func int(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    /// Copies the blob out before the statement is finalised — SQLite's pointer
    /// dies with the step, and every caller here outlives it.
    static func blob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
