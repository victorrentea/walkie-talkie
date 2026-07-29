import Foundation

/// Append-only JSONL queue read by the Claude Code side (a blocking `wc -l`
/// watcher armed by the skill). One line = one message from Victor.
///
/// Appends are serialised on a private queue and written with a single
/// `write(2)` of a newline-terminated blob, so a watcher that wakes mid-append
/// can never read half a line.
enum Outbox {

    /// `~/.claude-bubble` unless overridden with `--home`.
    static var home = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-bubble")

    static var outboxURL = home.appendingPathComponent("outbox.jsonl")
    static var shotsDir  = home.appendingPathComponent("shots")

    private static let queue = DispatchQueue(label: "ro.victorrentea.claude-bubble.outbox")

    static func prepare() {
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: outboxURL.path) {
            FileManager.default.createFile(atPath: outboxURL.path, contents: Data())
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
    static func send(kind: String,
                     text: String? = nil,
                     selection: String? = nil,
                     paths: [String] = [],
                     screen: String? = nil,
                     app: String? = nil) {
        var obj: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "kind": kind,
        ]
        if let text = text, !text.isEmpty { obj["text"] = text }
        if let selection = selection, !selection.isEmpty { obj["selection"] = selection }
        if !paths.isEmpty { obj["paths"] = paths }
        if let screen = screen { obj["screen"] = screen }
        if let app = app, !app.isEmpty { obj["app"] = app }

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
    static func info(_ msg: String)  { FileHandle.standardError.write(Data("[bubble] \(msg)\n".utf8)) }
    static func error(_ msg: String) { FileHandle.standardError.write(Data("[bubble] ⚠️ \(msg)\n".utf8)) }
}
