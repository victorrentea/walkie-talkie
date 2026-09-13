import AppKit
import ApplicationServices
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

    // MARK: - Parking it out of the way

    /// **Where the parked window went, and whether Wispr kept it there.**
    ///
    /// Victor's ask: the Scratchpad is a side effect of the wrap, not something
    /// he asked to look at, so it goes to the bottom-right corner of the second
    /// display (the main one's corner when there is only one), as small as Wispr
    /// will allow and mostly off the edge — a sliver, so that it is visible
    /// enough to notice and small enough to ignore.
    private(set) static var parkedFrame: CGRect?
    /// What Wispr's own layout allows, measured by asking for 1×1 and reading
    /// back what it settled on. Nil until a window has been parked once.
    private(set) static var minimumSize: CGSize?
    /// The frame the window had the last time it was seen, whatever that was.
    private(set) static var lastSeenFrame: CGRect?
    /// **Has it ever had the keyboard?** Victor's real worry about this wrap is
    /// one of his own keystrokes landing in Wispr's note, so the answer is
    /// measured rather than asserted — polled at 50 ms for the whole of every
    /// Scratchpad dictation.
    private(set) static var everBecameKey = false
    /// When it did, for the log.
    private(set) static var lastKeyAt: Date?
    /// Whether the window came back somewhere other than where it was parked —
    /// the answer to *does Wispr remember the frame*, which decides whether
    /// parking is a one-off or a thing to do on every open.
    private(set) static var reopenedElsewhere = 0
    private(set) static var reopenCount = 0

    /// How much of it is left on screen. Eight points: enough to see, not enough
    /// to read, and far too little to click in by accident.
    private static let sliver: CGFloat = 8

    /// Wispr's application element, or nil when it is not running.
    private static func appElement() -> (AXUIElement, pid_t)? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.electron.wispr-flow").first
                ?? NSWorkspace.shared.runningApplications.first(where: {
                    $0.bundleIdentifier == "com.electron.wispr-flow" })
        else { return nil }
        return (AXUIElementCreateApplication(app.processIdentifier), app.processIdentifier)
    }

    /// The Scratchpad's own window element, by title.
    private static func windowElement() -> AXUIElement? {
        guard let (app, _) = appElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for w in windows {
            var t: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success,
                  (t as? String) == windowName else { continue }
            return w
        }
        return nil
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var p: CFTypeRef?
        var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    private static func set(_ window: AXUIElement, position: CGPoint) -> Bool {
        var p = position
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    private static func set(_ window: AXUIElement, size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    /// **The screen to park on, in Accessibility's coordinates.**
    ///
    /// The second display when one is attached — a training Mac spends its day
    /// mirrored or extended onto a projector, and the corner of *that* is the
    /// one place a stray window costs nothing. AppKit measures from the bottom
    /// left of the main screen with y up; Accessibility measures from its top
    /// left with y down, and getting that backwards puts the window off the top
    /// of the world rather than off the bottom.
    private static func parkingRectAX() -> CGRect? {
        let screens = NSScreen.screens
        guard let main = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
        else { return nil }
        let target = screens.first(where: { $0 !== main }) ?? main
        let f = target.visibleFrame
        return CGRect(x: f.minX, y: main.frame.maxY - f.maxY, width: f.width, height: f.height)
    }

    /// **Park it**: smallest Wispr allows, bottom-right of the chosen screen, all
    /// but a sliver off the edge. Answers what it did, for `/test/state` and for
    /// `POST /test/scratchpad/park`.
    @discardableResult
    static func park() -> [String: Any] {
        guard AXIsProcessTrusted() else {
            Log.error("🗒️ cannot park the Scratchpad — no Accessibility grant")
            return ["parked": false, "why": "no Accessibility grant"]
        }
        guard let window = windowElement() else {
            return ["parked": false, "why": "no Scratchpad window"]
        }
        let before = frame(of: window)

        // **Ask for 1×1 and read back what Wispr allows.** There is no
        // `AXMinimumSize`; the window simply refuses to go below its own layout
        // minimum, and the number it settles on is the measurement.
        set(window, size: CGSize(width: 1, height: 1))
        let shrunk = frame(of: window)?.size ?? .zero
        if minimumSize == nil, shrunk != .zero {
            minimumSize = shrunk
            Log.info(String(format: "🗒️ the Scratchpad's smallest size is %.0f×%.0f", shrunk.width, shrunk.height))
        }

        guard let screen = parkingRectAX() else { return ["parked": false, "why": "no screen"] }
        let size = shrunk == .zero ? CGSize(width: 200, height: 120) : shrunk
        // Bottom-right, all but `sliver` past the edge. Read back rather than
        // assumed: macOS clamps a window it thinks is escaping, and what matters
        // is where it ended up.
        let wanted = CGPoint(x: screen.maxX - sliver, y: screen.maxY - sliver)
        set(window, position: wanted)
        let after = frame(of: window)
        parkedFrame = after
        lastSeenFrame = after
        Log.info(String(format: "🗒️ Scratchpad parked: %@ → %@ (asked for %.0f,%.0f on a %.0f×%.0f screen)",
                        describe(before), describe(after), wanted.x, wanted.y, screen.width, screen.height))
        return ["parked": true,
                "frame": rect(after),
                "was": rect(before),
                "minimumSize": ["w": Int(size.width), "h": Int(size.height)],
                "screens": NSScreen.screens.count]
    }

    private static func describe(_ r: CGRect?) -> String {
        guard let r else { return "nowhere" }
        return String(format: "%.0f,%.0f %.0f×%.0f", r.minX, r.minY, r.width, r.height)
    }

    private static func rect(_ r: CGRect?) -> Any {
        guard let r else { return NSNull() }
        return ["x": Int(r.minX), "y": Int(r.minY), "w": Int(r.width), "h": Int(r.height)]
    }

    // MARK: - Watching it, at 50 ms

    private static var watch: Timer?
    private static var sawWindow = false
    /// **Close it the instant it appears.** Armed at the release, because the
    /// window is only dangerous while it is up and the measured danger is real:
    /// a `z` typed 1.5 s into the settle landed in the note and was delivered
    /// inside the sentence.
    private static var closeASAP = false
    private static var closeRequested = false
    private static var appearedAt: Date?
    private static var armedAt: Date?
    /// Called the moment the window is confirmed gone, with how long it was up,
    /// or nil when it never appeared inside the ceiling.
    static var onWindowGone: ((Double?) -> Void)?
    /// Called the moment the window is first seen, so the keyboard can be taken
    /// for exactly the stretch it is up and not a millisecond longer.
    static var onWindowSeen: (() -> Void)?
    /// The longest the watcher waits for a window that may never come.
    private static let appearCeiling: TimeInterval = 8
    /// What a whole open→closed cycle has cost, most recent first.
    private(set) static var lastOpenMs: Double?

    /// **Watch, and shut it on sight** — from the release until it is confirmed
    /// closed. The 50 ms tick is the danger window's own resolution: the runner
    /// measured the window shut again within 0.1–0.4 s once it is asked, and a
    /// slower poll would spend more of that window unarmed than armed.
    static func armCloseOnSight() {
        closeASAP = true
        closeRequested = false
        appearedAt = nil
        armedAt = Date()
        beginWatch()
    }

    /// **On for the length of a Scratchpad dictation, and off the rest of the
    /// day.** What it is watching for is the one thing Victor is actually
    /// worried about: the note taking the keyboard while he is typing.
    static func beginWatch() {
        guard watch == nil else { return }
        sawWindow = false
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in tick() }
        watch = t
        RunLoop.main.add(t, forMode: .common)
    }

    static func endWatch() {
        watch?.invalidate()
        watch = nil
    }

    private static func tick() {
        guard let window = windowElement() else {
            if sawWindow, closeRequested {
                let ms = appearedAt.map { Date().timeIntervalSince($0) * 1000 }
                lastOpenMs = ms
                Log.info(String(format: "🗒️ the Scratchpad window is gone — it was up for %.0f ms",
                                ms ?? 0))
                finishCloseOnSight(ms)
            } else if closeASAP, let armed = armedAt, Date().timeIntervalSince(armed) > appearCeiling {
                Log.info("🗒️ no Scratchpad window appeared within \(Int(appearCeiling)) s — nothing to close")
                finishCloseOnSight(nil)
            }
            sawWindow = false
            return
        }
        let f = frame(of: window)
        if !sawWindow {
            sawWindow = true
            reopenCount += 1
            let moved = parkedFrame.map { p in
                abs((f?.minX ?? 0) - p.minX) > 2 || abs((f?.minY ?? 0) - p.minY) > 2
            } ?? true
            if moved, parkedFrame != nil { reopenedElsewhere += 1 }
            Log.info("🗒️ scratchpad reopened at \(describe(f))"
                     + (parkedFrame == nil ? "" : moved ? " — NOT where it was parked, so it is parked again"
                                                        : " — where it was parked; Wispr remembers"))
            if parkedFrame == nil || moved { park() }
            appearedAt = Date()
        }
        // **Ask for it to go the instant it is seen.** The press is 250 ms of
        // held key and the window takes another beat to go, so the sooner this
        // is asked the shorter the stretch in which a keystroke of his can land
        // in Wispr's note.
        if closeASAP, !closeRequested {
            closeRequested = true
            onWindowSeen?()
            Log.info("🗒️ the Scratchpad window appeared — closing it on sight")
            HotkeyTap.tapWisprScratchpad()
        }
        lastSeenFrame = f
        // **Does it have the keyboard?** And the obvious test is the wrong one.
        //
        // The first version of this asked *is Wispr frontmost and is this its
        // main window*, on the reasoning that a background window cannot take a
        // key. The loop disproved it the same hour (2026-09-13, `wrap-bound`): a
        // `z` typed 1.5 s into the settle went **into the Scratchpad** while
        // `NSWorkspace.frontmostApplication` was TextEdit for the whole run —
        // the victim document stayed empty and the character turned up in the
        // note. **The Scratchpad takes key focus without becoming frontmost.**
        //
        // So the test is the system-wide focused element's owner, which is the
        // question actually being asked — *where would a keystroke go* — with the
        // window's own `AXFocused` beside it as the second reading. Frontmost is
        // not consulted at all any more, because it is the thing that lied.
        var why: String?
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),
                                         kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() {
            var owner: pid_t = 0
            if AXUIElementGetPid(element as! AXUIElement, &owner) == .success,
               let (_, wispr) = appElement(), owner == wispr {
                why = "the system-wide focused element belongs to Wispr Flow"
            }
        }
        if why == nil {
            var isFocused: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXFocusedAttribute as CFString, &isFocused) == .success,
               (isFocused as? Bool) == true {
                why = "the window reports AXFocused"
            }
        }
        guard let why else { return }
        if !everBecameKey {
            everBecameKey = true
            lastKeyAt = Date()
            Log.error("🗒️ THE SCRATCHPAD WINDOW HAS THE KEYBOARD (\(why), frontmost is \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")) — a keystroke now lands in Wispr's note, not in his work")
        }
    }

    private static func finishCloseOnSight(_ openMs: Double?) {
        closeASAP = false
        closeRequested = false
        armedAt = nil
        let done = onWindowGone
        onWindowGone = nil
        onWindowSeen = nil
        endWatch()
        done?(openMs)
    }

    /// `GET /test/state` → `scratchpad`.
    static func describe() -> [String: Any] {
        [
            "windowOpen": windowIsOpen(),
            "frame": rect(lastSeenFrame),
            "parkedFrame": rect(parkedFrame),
            "minimumSize": minimumSize.map { ["w": Int($0.width), "h": Int($0.height)] } ?? NSNull(),
            "everBecameKey": everBecameKey,
            "lastKeyAt": lastKeyAt.map { Outbox.iso($0) } ?? NSNull(),
            "opens": reopenCount,
            "lastOpenMs": lastOpenMs.map { Int($0.rounded()) } ?? NSNull(),
            "reopenedElsewhere": reopenedElsewhere,
            "screens": NSScreen.screens.count,
        ]
    }

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
