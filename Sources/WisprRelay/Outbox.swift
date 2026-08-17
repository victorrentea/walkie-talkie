import Foundation

/// Append-only JSONL queue read by the agent side (a blocking `wc -l`
/// watcher armed by the skill). One line = one message from Victor.
///
/// Appends are serialised on a private queue and written with a single
/// `write(2)` of a newline-terminated blob, so a watcher that wakes mid-append
/// can never read half a line.
enum Outbox {

    /// `~/.wispr-relay` unless overridden with `--home`.
    static var home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".wispr-relay")

    static var outboxURL = home.appendingPathComponent("outbox.jsonl")

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
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: outboxURL.path) {
            FileManager.default.createFile(atPath: outboxURL.path, contents: Data())
        }
        retireLegacyShots()
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
        let legacy = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".wispr-relay/shots")
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

enum Log {
    static func info(_ msg: String)  { FileHandle.standardError.write(Data("[relay] \(msg)\n".utf8)) }
    static func error(_ msg: String) { FileHandle.standardError.write(Data("[relay] ⚠️ \(msg)\n".utf8)) }
}
