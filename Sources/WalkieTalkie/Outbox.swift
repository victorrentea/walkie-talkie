import Foundation

/// Append-only JSONL queue read by the agent side (a blocking `wc -l`
/// watcher armed by the skill). One line = one message from Victor.
///
/// Appends are serialised on a private queue and written with a single
/// `write(2)` of a newline-terminated blob, so a watcher that wakes mid-append
/// can never read half a line.
enum Outbox {

    /// `~/.walkie-talkie` unless overridden with `--home`.
    static var home = defaultHome

    static let defaultHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".walkie-talkie")

    static var outboxURL = home.appendingPathComponent("outbox.jsonl")

    /// **Where the bound tty is published**, for the status line to read.
    ///
    /// The chip says which session the words go to, and it says it beside the
    /// cursor — which is the one place Victor is not looking while an agent
    /// works, and which macOS hides the moment he touches the keyboard. In a
    /// screen of identical terminals that left *which of these is bound?* with
    /// no answer anywhere in the window itself. The status line is the row that
    /// is always at the bottom of the right terminal, so a microphone in front
    /// of it is the receipt that cannot be missed.
    ///
    /// A file rather than the `GET /target` route that already answers this: the
    /// bar re-renders every second in every open session, and an HTTP call on
    /// that beat is exactly the per-second cost this repo's status line is
    /// written to avoid. Reading a small file that is usually absent is a failed
    /// `read`, no subprocess at all.
    static var boundTTYURL = home.appendingPathComponent("bound-tty")

    /// Write the bound tty, or take the file away when nothing is bound.
    ///
    /// **Removed rather than emptied**, so the reader's fast path is a file that
    /// does not exist — and so a relay that dies leaves no marker claiming a
    /// binding that went with it. `AppDelegate` clears it at launch and at
    /// termination for the same reason; a stale microphone on somebody else's
    /// row is worse than none, since the whole point is that it can be trusted.
    /// **Two facts, one line: `ttys006` or `ttys006 listening`.** The status
    /// line wears a yellow badge for the first and a red one for the second —
    /// *the words would come here* against *the microphone is open right now* —
    /// which is the same split the chip draws with a folder name against a
    /// pulsing 🔴, said in the one place that is always on screen.
    ///
    /// A second word rather than a second file: the reader is a shell loop doing
    /// one builtin `read`, and two files would be two of them plus a state that
    /// can be half-written.
    static func publishBound(tty: String?, listening: Bool = false) {
        guard let tty = tty else {
            try? FileManager.default.removeItem(at: boundTTYURL)
            return
        }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? Data((listening ? "\(tty) listening" : tty).utf8).write(to: boundTTYURL)
    }

    /// **Screenshots live in Caches, not next to the outbox, and not in `/tmp`.**
    ///
    /// They are a staging area, never an archive: each retina JPG is a megabyte
    /// or two, Victor dictates all day, and what any of them is *for* is over
    /// within the turn that reads it. Caches is the one folder that emptying the
    /// Trash, Storage Management and every cleaner tool actually reach, and macOS
    /// may purge it under disk pressure — all of which is welcome here. `/tmp`
    /// only clears on reboot and on a 3-day sweep, neither of which is "when the
    /// disk is full". It is the same call `ScreenshotManager` makes in Victor
    /// Addons, for the same reason.
    ///
    /// The **outbox stays where it is**: it is the log of what Victor said, the
    /// record that outlives the session, and a log the system may delete under
    /// pressure is not a log.
    static let cacheRoot = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // **The old bundle id, on purpose.** The app is Walkie Talkie now, but its
        // identity to macOS is unchanged — see `build-app.sh` — because TCC keys
        // Accessibility, Screen Recording and the microphone to that string, and
        // a new one costs three grants Victor has to re-tick in System Settings.
        // The Caches folder follows the bundle id rather than the name, so it is
        // the one place the old name survives, and it survives for a reason.
        .appendingPathComponent("ro.victorrentea.wispr-relay/shots")

    /// One folder per relay session, stamped with when it started.
    ///
    /// Shots are named by **where in the dictation** they were taken, so two
    /// sessions produce `shot-00:00(…)` over and over; without a folder between
    /// them the second run would overwrite the first's pictures — including ones
    /// an outbox line still points at. The stamp is taken once, at launch, so a
    /// session's shots stay together however long it runs.
    static let sessionStamp: String = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return f.string(from: Date())
    }()

    static var shotsDir = cacheRoot.appendingPathComponent(sessionStamp)

    private static let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.outbox")

    static func prepare() {
        adoptLegacyHome()
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: outboxURL.path) {
            FileManager.default.createFile(atPath: outboxURL.path, contents: Data())
        }
        retireLegacyShots()
    }

    /// The home folder was `~/.wispr-relay` until the app was renamed, and it is
    /// **moved rather than recreated**: it holds the voice corpus — 300 MB of
    /// Victor's own speech paired with transcripts, and the one thing in this app
    /// that cannot be regenerated at any price. Starting fresh beside it would
    /// have orphaned every sample.
    ///
    /// **A merge, not a rename, and that distinction was not theoretical.** The
    /// first version moved the whole folder and skipped itself if the new one
    /// already existed — which it did within the minute: the VS Code extension
    /// publishes its listener into `~/.walkie-talkie/ide/` and creates the folder
    /// doing so, and the skill's `install.sh` does the same with `mkdir -p`. Both
    /// run before the first renamed relay ever starts, so a rename-if-absent would
    /// have skipped forever and left the corpus stranded under a name nothing
    /// reads any more.
    ///
    /// So each entry moves only when the destination has no entry of that name,
    /// and a directory present on both sides is merged one level down instead of
    /// being refused whole. Nothing is ever overwritten: where both sides have a
    /// file, the new one wins and the old one is left where it is, which is the
    /// safe direction — the only files that can collide are the ones something has
    /// already written under the new name, i.e. the current truth.
    ///
    /// **A `--home` override skips it**, and that has to be checked rather than
    /// assumed: without the guard, a test instance pointed at a scratch directory
    /// would drag Victor's real corpus into it — the one folder here that cannot
    /// be regenerated, moved somewhere he would never think to look.
    ///
    /// This is the one place the old name is allowed to appear in a path, and it
    /// is here precisely so that it appears nowhere else.
    private static func adoptLegacyHome() {
        guard home == defaultHome else { return }
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".wispr-relay")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let moved = merge(from: legacy, into: home)
        if moved > 0 { Log.info("adopted \(moved) item(s) from \(legacy.lastPathComponent)") }
        // Only when it is genuinely empty — an entry that could not move is a
        // reason to keep the folder, not to delete it.
        if (try? FileManager.default.contentsOfDirectory(atPath: legacy.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    /// Moves everything in `source` into `destination`, recursing only where a
    /// directory of the same name exists on both sides. Returns how many entries
    /// actually moved.
    @discardableResult
    private static func merge(from source: URL, into destination: URL) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: source.path) else { return 0 }
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var moved = 0
        for name in entries {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            var fromIsDir: ObjCBool = false
            var toIsDir: ObjCBool = false
            fm.fileExists(atPath: from.path, isDirectory: &fromIsDir)

            guard fm.fileExists(atPath: to.path, isDirectory: &toIsDir) else {
                if (try? fm.moveItem(at: from, to: to)) != nil { moved += 1 }
                else { Log.error("could not move \(from.path)") }
                continue
            }
            guard fromIsDir.boolValue, toIsDir.boolValue else { continue }
            moved += merge(from: from, into: to)
            if (try? fm.contentsOfDirectory(atPath: from.path))?.isEmpty == true {
                try? fm.removeItem(at: from)
            }
        }
        return moved
    }

    /// Shots used to live in `~/.wispr-relay/shots`, and moving them to Caches
    /// left the old pile behind with **nothing that would ever clean it**.
    ///
    /// `ScreenCapture.prune` walks `cacheRoot` and only `cacheRoot`, so the cap
    /// of 300 has never applied there; Storage Management and every cleaner tool
    /// reach Caches and not a dotfolder in `$HOME`; and nothing writes there any
    /// more, so it cannot even shrink by being overwritten. Measured before this
    /// was written: **382 MB in 209 retina JPGs**, going back to the first day
    /// the relay ran, sitting where no amount of tidying would find them.
    ///
    /// **To the Trash, not to `rm`.** Old outbox lines still name these files,
    /// and a picture Victor might still want to open is not something to delete
    /// out from under him on a launch he did not ask a question with. The Trash
    /// is also literally the answer he asked for — they go when he empties it —
    /// and it is the one destination that needs no new habit.
    ///
    /// One-shot by nature: nothing recreates the folder, so the second launch
    /// finds nothing to do.
    private static func retireLegacyShots() {
        let legacy = home.appendingPathComponent("shots")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: legacy.path, isDirectory: &isDir),
              isDir.boolValue else { return }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: legacy, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles])) ?? []
        let bytes = files.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        do {
            try FileManager.default.trashItem(at: legacy, resultingItemURL: nil)
            Log.info("retired the pre-Caches shot folder to the Trash — \(files.count) file(s), \(bytes / 1_048_576) MB")
        } catch {
            Log.error("could not retire \(legacy.path): \(error)")
        }
    }

    /// `kind` is one of `dictation` / `typed` / `screenshot` / `selection`.
    /// `text` carries the message; `selection` the screen text stashed before
    /// dictation started (nil when there was none); `paths` any screenshots that
    /// belong to this message — always an array, because shots taken while
    /// dictating are delivered together with that dictation.
    /// `screen` is the automatic capture of the display Victor was looking at
    /// when he started talking — offered as context to consult if the words need
    /// it, as opposed to `paths`, which are shots he deliberately took.
    /// `elements` are the DOM nodes he ⌘-clicked in Chrome while this message was
    /// being assembled: each one is a CSS selector plus what the thing said, so
    /// "this button" in the transcript has something to resolve to.
    /// `selections` are highlights he made **later in the same dictation**, each
    /// `{at, text}` with `at` as `m:ss` from the moment he started talking.
    ///
    /// `selection` above is untouched and still carries the first one, so
    /// nothing that reads this queue today has to learn a key to keep working —
    /// which matters, because the `relay` skill documents these fields by name.
    /// A reader that wants the whole sequence takes `selections`; one that wants
    /// the subject takes `selection`, exactly as before.
    static func send(kind: String,
                     text: String? = nil,
                     selection: String? = nil,
                     selections: [[String: String]] = [],
                     paths: [String] = [],
                     screen: String? = nil,
                     /// File name → what was in front when that frame was taken,
                     /// `Chrome — Gmail – Inbox` / `IntelliJ IDEA — OwnerController.java`.
                     /// Keyed by the **base name** rather than the full path: the
                     /// folder is already in `paths` and `screen`, and repeating
                     /// it as a JSON key would double the longest string in the
                     /// line to say nothing new.
                     sources: [String: String] = [:],
                     app: String? = nil,
                     elements: [[String: Any]] = []) {
        var obj: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "kind": kind,
            // Which session this belongs to — `folder@branch`, exactly what the
            // overlay is showing on screen and what the agent sees in its own
            // status line. One outbox is shared by whoever is watching it, and a
            // message with no return address is a message the wrong agent can act
            // on: this already happened once, a dictation about one project
            // arriving in a queue nobody was reading for it.
            "session": SessionLabel.value,
        ]
        if let text = text, !text.isEmpty { obj["text"] = text }
        if let selection = selection, !selection.isEmpty { obj["selection"] = selection }
        if !selections.isEmpty { obj["selections"] = selections }
        if !paths.isEmpty { obj["paths"] = paths }
        if let screen = screen { obj["screen"] = screen }
        if !sources.isEmpty { obj["sources"] = sources }
        if let app = app, !app.isEmpty { obj["app"] = app }
        if !elements.isEmpty { obj["elements"] = elements }

        queue.async {
            // JSONSerialization (never string interpolation): dictated text and
            // screen selections are arbitrary and would otherwise forge JSON.
            guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
            data.append(0x0A)
            guard let handle = try? FileHandle(forWritingTo: outboxURL) else {
                Log.error("outbox unavailable at \(outboxURL.path)")
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            Log.info("→ sent \(kind) (\(data.count) bytes)")
        }
    }
}

/// Every line goes to stderr **and** to `~/.walkie-talkie/relay.log`.
///
/// **The file half was added on 2026-08-28, and it closed a hole that had been
/// open since the app started at login.** Logging was stderr only, and the file
/// existed only because whatever launched the relay redirected stderr into it —
/// true of the old per-session launcher, false of `open`, of Finder, and of the
/// login item the app now is. So the app that runs all day wrote nothing at all,
/// and `relay.log` sat there looking current while being hours stale: worse than
/// no log, because it answers questions about a session that ended long ago.
/// Every "why did that not work?" since has been unanswerable for want of two
/// lines the app was already producing.
///
/// Stamped, unlike the old lines: the file now spans days rather than one
/// session, so "when" is the first thing asked of any line in it.
enum Log {
    static func info(_ msg: String)  { write("[relay] \(msg)") }
    static func error(_ msg: String) { write("[relay] ⚠️ \(msg)") }

    private static let lock = NSLock()

    /// Opened once, appended to for the life of the process. Failing to open it
    /// is not worth reporting anywhere — the only place a complaint could go is
    /// the log that could not be opened.
    private static let file: FileHandle? = {
        let url = Outbox.home.appendingPathComponent("relay.log")
        let fm = FileManager.default
        try? fm.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    private static func write(_ line: String) {
        let stamped = "\(clock.string(from: Date())) \(line)\n"
        let data = Data(stamped.utf8)
        FileHandle.standardError.write(data)
        lock.lock()
        file?.write(data)
        lock.unlock()
    }
}
