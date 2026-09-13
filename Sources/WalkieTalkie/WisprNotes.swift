import CoreGraphics
import Foundation
import SQLite3

/// **The shared read-only handle on Wispr Flow's `flow.sqlite`.**
///
/// Two readers now — `WisprHistory` for the row's status, `WisprNotes` for the
/// Scratchpad — and one handle between them, because the alternative is two
/// connections opened and dropped independently against a 3.5 GB WAL file that
/// another process is writing. The discipline is the one `WisprHistory` shipped
/// with and is unchanged: `mode=ro` in the URI *on top of* the read-only flag, so
/// neither the journal nor the shm can be created by this process; a 50 ms busy
/// timeout; and the handle dropped on any error so the next call reopens it.
///
/// **Nothing here transcribes.** The 2026-08-29 rule — *never Wispr Flow's
/// database as a recogniser or a fallback* — is about this app taking words out
/// of another app's store and passing them off as its own recognition. What these
/// two readers take is *Wispr's own answer to a dictation this app asked Wispr
/// for*, which is the same thing the ⌘V carries and the only thing left when
/// Wispr's delivery is deliberately aimed somewhere no tap can see.
enum WisprFlowDB {

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Wispr Flow/flow.sqlite")

    private static var handle: OpaquePointer?
    static let lock = NSLock()

    /// Caller holds `lock`.
    static func open() -> OpaquePointer? {
        if let handle { return handle }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        let uri = "file:" + url.path.replacingOccurrences(of: " ", with: "%20") + "?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK, let db else {
            if let d = db { sqlite3_close(d) }
            Log.error("wispr db: could not open \(url.path) read-only")
            return nil
        }
        sqlite3_busy_timeout(db, 50)
        handle = db
        return db
    }

    /// Caller holds `lock`.
    static func reset() {
        if let handle { sqlite3_close(handle) }
        handle = nil
    }
}

/// **Wispr Flow's Scratchpad, read and never written** — the `Notes` and
/// `NoteVersions` tables of `flow.sqlite`.
///
/// ## Why this is the delivery the wrap was looking for
///
/// Three candidates for *take Wispr's words without letting Wispr put them
/// anywhere* were tried on 2026-09-13 and two were rejected by Victor:
///
/// - **The sink** — a borderless window that takes the key focus for the length
///   of the dictation. It works (measured 3/3: Wispr picks its insertion target
///   at the *end*, and taking key 1–5 ms after the stop chord is enough), and he
///   rejected it because it steals focus from a man who may be clicking or typing
///   at that instant.
/// - **Revoking Wispr's Accessibility grant** — it cannot write through AX or
///   post a synthetic ⌘V without one. Rejected because Wispr has to go on working
///   as a standalone tool.
/// - **The Scratchpad** — Wispr's own *Open Scratchpad* shortcut, **held**, which
///   per Wispr's docs is push-to-talk dictating into its own note. Measured the
///   same evening, F18 held 20 s: the text landed in `Notes` (a **new note per
///   dictation**, with a `NoteVersions` row beside it), the victim TextEdit
///   document was untouched, **focus never moved**, no ⌘V was posted, the
///   pasteboard was written and then restored by Wispr, and the round trip was
///   **432 ms**. The Scratchpad window opened in the background.
///
/// So the product path is: hold the chord for the sentence, read the note, close
/// nothing. This file is the reading half.
///
/// ## The `History` row is not the witness here
///
/// Measured in the same run and worth writing down because it is the obvious
/// thing to reach for: on a Scratchpad dictation the `History` row's `app` column
/// names **the front app**, not the destination. It said TextEdit for a sentence
/// that went into Wispr's own note. `app` answers *what was in front*, which for
/// every other kind of dictation happens to be the same thing as *where the words
/// went* and here is not. The note is the only place the destination is written.
///
/// ## Newest since the chord, and a modified note counts
///
/// The run measured a new note per dictation, but the Scratchpad is a *notepad* —
/// nothing promises it will not append to an existing one, and a reader that only
/// looked for new `id`s would silently report nothing for ever the day it starts.
/// So the test is `max(createdAt, modifiedAt) >= since`, which catches both, and
/// the `NoteVersions` row is carried alongside: its `source` (`initial` on the
/// measured run) is Wispr's own word for how that content arrived.
enum WisprNotes {

    struct Note {
        let id: String
        let title: String
        /// The whole note. For a new note this is the sentence; for one Wispr
        /// appended to it is the sentence **and everything before it**, which is
        /// why `versionContent` exists.
        let content: String
        /// Unix seconds. `createdAt` and `modifiedAt` differ by ~400 ms on a
        /// fresh note (Wispr writes the row, then fills it).
        let createdAt: TimeInterval
        let modifiedAt: TimeInterval
        /// The newest `NoteVersions` row for this note — the increment rather
        /// than the accumulated note, which is what a delivery wants.
        let versionId: String
        let versionContent: String
        /// Wispr's own word for how the content arrived: `initial` on the
        /// measured run. Never parsed here; recorded, and named in the log.
        let versionSource: String
        let versionAt: TimeInterval

        /// **The words** — the version's content when there is one, the note's
        /// otherwise. A dictation appended to an existing note would otherwise
        /// deliver the whole notepad.
        var text: String { versionContent.isEmpty ? content : versionContent }
    }

    /// The newest note touched at or after `since` (unix seconds), or nil.
    ///
    /// - Parameter since: the chord's wall clock, less whatever slack the caller
    ///   wants. `Notes.createdAt` is stored to the millisecond but compared here
    ///   at second resolution, the same as `WisprHistory`'s `startedAt`.
    static func newest(since: TimeInterval) -> Note? {
        WisprFlowDB.lock.lock(); defer { WisprFlowDB.lock.unlock() }
        guard let db = WisprFlowDB.open() else { return nil }
        // One statement, and the version is joined rather than fetched in a
        // second round trip — this runs on a 150 ms poll beside the `History`
        // one and the file is Wispr's, not ours, to keep busy.
        let sql = """
            select n.id, coalesce(n.title, ''), coalesce(n.content, ''),
                   coalesce(strftime('%s', n.createdAt), '0'),
                   coalesce(strftime('%s', n.modifiedAt), '0'),
                   coalesce(v.id, ''), coalesce(v.content, ''), coalesce(v.source, ''),
                   coalesce(strftime('%s', v.createdAt), '0')
            from Notes n
            left join NoteVersions v on v.id = (
                select id from NoteVersions where noteId = n.id order by createdAt desc limit 1)
            where coalesce(n.isDeleted, 0) = 0
            order by max(coalesce(n.modifiedAt, ''), coalesce(n.createdAt, '')) desc
            limit 1
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            Log.error("wispr notes: \(String(cString: sqlite3_errmsg(db)))")
            WisprFlowDB.reset()
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        func text(_ i: Int32) -> String {
            sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
        }
        let note = Note(id: text(0), title: text(1), content: text(2),
                        createdAt: Double(text(3)) ?? 0, modifiedAt: Double(text(4)) ?? 0,
                        versionId: text(5), versionContent: text(6), versionSource: text(7),
                        versionAt: Double(text(8)) ?? 0)
        // **The `since` test is applied here rather than in the `where`**, so a
        // caller asking *what is the newest note at all* (the loopback's read)
        // gets an answer instead of a silence it cannot tell from a failure.
        guard max(note.createdAt, note.modifiedAt) >= since else { return nil }
        return note
    }

    /// The newest note, whenever it was written — `GET /test/wispr-notes`, so a
    /// run can read the baseline before it holds the chord.
    static func newest() -> Note? { newest(since: 0) }

    /// For `GET /test/wispr-notes` and for the log.
    static func describe(_ note: Note?) -> [String: Any] {
        guard let note else { return ["note": NSNull()] }
        return ["note": [
            "id": note.id,
            "title": note.title,
            "text": note.text,
            "chars": note.text.count,
            "createdAt": Outbox.iso(Date(timeIntervalSince1970: note.createdAt)),
            "modifiedAt": Outbox.iso(Date(timeIntervalSince1970: note.modifiedAt)),
            "versionId": note.versionId,
            "versionSource": note.versionSource,
        ]]
    }
}

/// **Wispr Flow's Scratchpad window, and the one precondition the wrap has.**
///
/// Measured by the loop over four runs on 2026-09-13, and it is the whole reason
/// this type exists:
///
/// - With the Scratchpad window **closed** at the start, a held chord dictates
///   into a note — 3/3: a new `Notes` row with its `NoteVersions` row, the victim
///   document untouched, the focus unchanged, and the window opening in the
///   background afterwards.
/// - With the window **already open**, Wispr transcribes normally (`formatted`
///   in `History`) and **writes no note at all**. The sentence is lost, and
///   closing the window afterwards does not commit it.
///
/// So *close the window* is not tidying up after the wrap, it is the wrap's
/// precondition, and the window Wispr opens at the end of every dictation is the
/// thing that would break the next one. The cycle is: check, close, hold,
/// dictate, release, read the note, close again, verify.
///
/// A ~250 ms press-and-release of the same chord closes it inside 1.5 s and does
/// not move the focus. A 60 ms one does nothing at all — Wispr is telling a tap
/// from a hold by duration.
enum WisprScratchpad {

    /// Wispr's own title for it. Matched by name because the window has no other
    /// distinguishing property from outside: it is an ordinary Electron window
    /// among Wispr's several, and its number changes every time it opens.
    static let windowName = "Scratchpad"

    /// **Is it up right now?** — the window server, not Accessibility.
    ///
    /// `CGWindowListCopyWindowInfo` at `.optionOnScreenOnly`, filtered to Wispr's
    /// processes by owner name. Window *titles* need the Screen Recording grant
    /// this app already holds for its screenshots; without it the list still
    /// arrives and the names are simply absent, which reads as *no Scratchpad* —
    /// so the check says so once rather than silently answering no for ever.
    static func windowIsOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        var sawAnyName = false
        for w in windows {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            guard owner.localizedCaseInsensitiveContains("Wispr") else { continue }
            guard let name = w[kCGWindowName as String] as? String else { continue }
            sawAnyName = true
            if name == windowName { return true }
        }
        if !sawAnyName, !warnedAboutNames {
            warnedAboutNames = true
            Log.error("wispr scratchpad: no window titles readable — grant Screen Recording, or the wrap cannot tell whether its precondition holds")
        }
        return false
    }
    private static var warnedAboutNames = false

    /// Post the toggle and **wait until the window is actually gone**.
    ///
    /// Verified rather than assumed, because the failure is silent and expensive:
    /// a window left open costs the *next* sentence, not this one, so nothing at
    /// the time of the mistake looks wrong.
    ///
    /// - Parameter done: on the main queue, with whether the window went.
    static func closeWindow(_ done: @escaping (Bool) -> Void) {
        guard windowIsOpen() else { return DispatchQueue.main.async { done(true) } }
        HotkeyTap.tapWisprScratchpad()
        poll(deadline: Date().addingTimeInterval(closeCeiling), done)
    }

    /// 2.5 s — measured at "within 1.5 s", with room over it for a busy Electron.
    private static let closeCeiling: TimeInterval = 2.5

    /// **Wait for the window to appear, then close it** — and the waiting is the
    /// whole point (2026-09-13, 23:26).
    ///
    /// Wispr opens the Scratchpad window when it *writes the note*, which is a
    /// second or two after the words have already been delivered. A close fired
    /// at the delivery therefore finds nothing open, does nothing, and reports
    /// success — and the window appears immediately afterwards and is still
    /// there at the start of the next dictation, which is exactly the state that
    /// costs a sentence. Measured: run 2's close ran at 23:24:34 and Wispr opened
    /// the window at 23:24:36, so run 3 dictated into an open Scratchpad and its
    /// text was **appended** to run 2's note with `source = typed` rather than
    /// becoming a note of its own.
    ///
    /// - Parameter done: on the main queue, with whether a window appeared at all
    ///   and whether it is closed now.
    static func closeWhenItAppears(within: TimeInterval = 4,
                                   _ done: @escaping (_ appeared: Bool, _ closed: Bool) -> Void) {
        let deadline = Date().addingTimeInterval(within)
        func look() {
            if windowIsOpen() {
                return closeWindow { closed in done(true, closed) }
            }
            if Date() >= deadline { return done(false, true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { look() }
        }
        DispatchQueue.main.async { look() }
    }

    private static func poll(deadline: Date, _ done: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !windowIsOpen() { return done(true) }
            if Date() >= deadline { return done(false) }
            poll(deadline: deadline, done)
        }
    }
}
