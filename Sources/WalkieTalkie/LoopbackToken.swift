import Foundation
import Security

/// **The loopback's key** (2026-11-25, Victor: the `/test/*` routes must require a
/// token). `BrowserGate` keeps web pages out; it never kept out a local process —
/// a Docker container that sets `Host: 127.0.0.1`, a sandboxed agent, any script —
/// and every one of them could spawn Claude in auto mode, type into the bound
/// terminal, write files through a `png` path or kill Wispr. Now every route but
/// four asks for `X-Walkie-Token: <home>/test-token`.
///
/// - **Its own file, not `reply-token`**: an agent that may answer through
///   `walkie-reply` must not hold the power to drive the app.
/// - **New at every launch**, 256 random bits, written atomically 0600 into the
///   *active* home (`--home` moves it, so a test instance and the Tart guest each
///   read their own). A caller reads the file at every request, so a relaunch
///   needs nothing from it.
/// - **Open without it**: `GET /engine` and `GET /target` (configuration, device
///   names, the bound tab — no transcript, no clipboard, nothing that acts) and
///   `POST /reply` / `POST /ask`, which check `reply-token` in their body.
///   `GET /test/state`, `/test/sink`, `/test/wispr-notes` carry his words and the
///   chip's rows, so they are gated like every other `/test/*` route.
enum LoopbackToken {
    static let header = "x-walkie-token"
    static let fileName = "test-token"

    /// The routes that answer without the token. Everything else — `/bind`,
    /// `/unbind`, `POST /engine`, every `/test/*`, and paths that do not exist —
    /// is refused with 401 first.
    static let openRoutes: Set<String> = ["GET /engine", "GET /target", "POST /reply", "POST /ask"]

    static func isOpen(method: String, path: String) -> Bool {
        openRoutes.contains("\(method.uppercased()) \(path)")
    }

    /// May this request through? `own` is the token this process issued;
    /// `onDisk` what its home's file holds now — accepted too, so a second
    /// process that shares the home (the overlay-states shoot, a debug build
    /// without `--home`) and rewrote the file does not lock the callers out
    /// of this one. Whoever can read the file is who the token admits.
    static func allows(method: String, path: String, presented: String?, own: String, onDisk: () -> String?) -> Bool {
        if isOpen(method: method, path: path) { return true }
        guard let presented, presented.utf8.count >= 32 else { return false }
        if equal(presented, own) { return true }
        guard let disk = onDisk(), disk.utf8.count >= 32 else { return false }
        return equal(presented, disk)
    }

    /// Constant-time in the length of the longer string: no early exit on the
    /// first differing byte, so the answer's timing says nothing about a prefix.
    static func equal(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        for i in 0..<max(x.count, y.count) {
            diff |= (i < x.count ? x[i] : 0) ^ (i < y.count ? y[i] : 0)
        }
        return diff == 0
    }

    /// 32 bytes from the system's CSPRNG, as 64 hex characters.
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255, using: &rng) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func url(home: URL) -> URL { home.appendingPathComponent(fileName) }

    /// The file's token, or nil when it is missing or empty.
    static func read(home: URL) -> String? {
        guard let s = try? String(contentsOf: url(home: home), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Writes `token` to `<home>/test-token`: a 0600 temp file created with
    /// `O_EXCL` beside it, then `rename(2)` — a reader sees the old token or the
    /// new one, never half of one, and never a moment of looser permissions.
    /// The home is created 0700 if it is not there.
    @discardableResult
    static func write(_ token: String, home: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: home.path) {
            do {
                try fm.createDirectory(at: home, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            } catch { return false }
        }
        let target = url(home: home)
        let temp = home.appendingPathComponent(".\(fileName).\(getpid()).\(UInt32.random(in: 0...UInt32.max))")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let data = Array((token + "\n").utf8)
        let wrote = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard wrote == data.count, synced, rename(temp.path, target.path) == 0 else {
            unlink(temp.path)
            return false
        }
        return true
    }

    /// A fresh token for this launch, written into `home` unless `persist` is
    /// false (the overlay-states shoot, which must not replace the installed
    /// app's file). Returned either way: a write that failed leaves the gate
    /// shut, never open.
    static func issue(home: URL, persist: Bool = true) -> String {
        let token = make()
        if persist {
            if write(token, home: home) {
                Log.info("🔑 loopback token written to \(url(home: home).path)")
            } else {
                Log.error("🔑 could not write \(url(home: home).path) — every gated loopback route will answer 401")
            }
        }
        return token
    }
}
