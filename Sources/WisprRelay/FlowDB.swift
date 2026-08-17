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
