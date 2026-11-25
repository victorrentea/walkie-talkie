import Foundation
import Security

/// **The loopback's key** (2026-11-25, Victor: the `/test/*` routes must require a
/// token). `BrowserGate` keeps web pages out; it never kept out a local process —
/// a Docker container that sets `Host: 127.0.0.1`, a sandboxed agent, any script —
/// and every one of them could spawn Claude in auto mode, type into the bound
/// terminal, write files through a `png` path or kill Wispr. Now every route but
/// two asks for `X-Walkie-Token: <home>/test-token`.
///
/// - **Its own file, not `reply-token`**: an agent that may answer through
///   `walkie-reply` must not hold the power to drive the app.
/// - **New at every launch**, 256 random bits, written atomically 0600 into the
///   *active* home (`--home` moves it, so a test instance and the Tart guest each
///   read their own). A caller reads the file at every request, so a relaunch
///   needs nothing from it.
/// - **Open without it**: `POST /reply` / `POST /ask` only, which check
///   `reply-token` in their body. `GET /engine` and `GET /target` were open until
///   the Fable review the same evening: the bound tab's title, folder and owner
///   told a container what he works on, and each `GET /engine` rebuilt a menu on
///   main. Every caller already sent the token.
/// - **Pinned to the port the app bound** (same review): `<home>/test-port` holds
///   it, written beside the token, and a caller sends the header **only there** —
///   a process squatting 8918 while the app sits on 8917, or grabbing 8917 between
///   a quit and a relaunch, never gets the token handed to it. At launch the file
///   says `starting` *before* the new token is written, so a caller that read the
///   new token reads either `starting` (send nothing, retry) or the new port.
///   No file at all = an app from before (callers fall back to 8917 alone).
/// - **The files are trusted only when they are his** (same review): read with
///   `O_NOFOLLOW`, a regular file owned by this uid and closed to group/other; the
///   home is `chmod 700`ed at launch, so nobody else can plant one either.
enum LoopbackToken {
    static let header = "x-walkie-token"
    static let fileName = "test-token"
    static let portFileName = "test-port"
    /// What `test-port` says between the launch and the listener's `.ready`.
    static let portPending = "starting"

    /// The routes that answer without the token. Everything else — `/bind`,
    /// `/unbind`, `GET`/`POST /engine`, `GET /target`, every `/test/*`, and paths
    /// that do not exist — is refused with 401 first.
    static let openRoutes: Set<String> = ["POST /reply", "POST /ask"]

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

    static func portURL(home: URL) -> URL { home.appendingPathComponent(portFileName) }

    /// The file's token, or nil when it is missing, empty or not his (`readPrivate`).
    static func read(home: URL) -> String? {
        guard let t = readPrivate(url(home: home)) else { return nil }
        return t.isEmpty ? nil : t
    }

    /// The contents of a file this process may trust, trimmed — nil unless it is a
    /// **regular file, not a symlink** (`O_NOFOLLOW`), **owned by this uid** and
    /// **closed to group and other** (`mode & 077 == 0`), checked on the open
    /// descriptor (`fstat`), so nothing can be swapped in between the check and
    /// the read. Write access to the home must not equal holding the token.
    static func readPrivate(_ file: URL) -> String? {
        let fd = Darwin.open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(),
              st.st_mode & 0o077 == 0, st.st_size <= 4096 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(st.st_size))
        let got = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard got >= 0 else { return nil }
        return String(decoding: bytes.prefix(got), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `chmod 700` the home when it is his and looser than that (2026-11-25, the
    /// Fable review): it holds `outbox.jsonl`, the voice corpus and `relay.log` —
    /// his words — and `~/.walkie-talkie` had been 0755 since it was made, so any
    /// other account in `staff` could read them off disk. Everything that reads it
    /// (Victor Mac, the hooks, the mods, the Tart share) runs as him.
    @discardableResult
    static func secureHome(_ home: URL) -> Bool {
        var st = stat()
        guard lstat(home.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else {
            return false
        }
        guard st.st_mode & 0o077 != 0 else { return true }
        guard chmod(home.path, 0o700) == 0 else {
            Log.error("🔑 could not chmod 700 \(home.path) — errno \(errno)")
            return false
        }
        Log.info("🔑 \(home.path) was \(String(st.st_mode & 0o777, radix: 8)) — now 700")
        return true
    }

    /// Writes `token` to `<home>/test-token`: a 0600 temp file created with
    /// `O_EXCL` beside it, then `rename(2)` — a reader sees the old token or the
    /// new one, never half of one, and never a moment of looser permissions.
    /// The home is created 0700 if it is not there.
    @discardableResult
    static func write(_ token: String, home: URL) -> Bool {
        write(token, to: url(home: home), home: home)
    }

    /// The same atomic 0600 write for any file of the home (`test-port`).
    @discardableResult
    static func write(_ contents: String, to target: URL, home: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: home.path) {
            do {
                try fm.createDirectory(at: home, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
            } catch { return false }
        }
        let temp = home.appendingPathComponent(".\(target.lastPathComponent).\(getpid()).\(UInt32.random(in: 0...UInt32.max))")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let data = Array((contents + "\n").utf8)
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
    /// app's file). Returned either way. Order matters to the callers, who read
    /// the token first and the port second: `test-port` is set to `starting`
    /// before the new token lands, so the new token is never paired with the
    /// last launch's port.
    static func issue(home: URL, persist: Bool = true) -> String {
        let token = make()
        if persist {
            secureHome(home)
            if !write(portPending, to: portURL(home: home), home: home) {
                // A caller would pair the new token with the old port: take the
                // old port away instead.
                unlink(portURL(home: home).path)
            }
            if write(token, home: home) {
                Log.info("🔑 loopback token written to \(url(home: home).path)")
            } else {
                // The previous launch's token would still be on disk: remove it,
                // and `trustsDisk` keeps the gate from reading it if even that
                // fails — so a failed write leaves every gated route answering 401.
                unlink(url(home: home).path)
                Log.error("🔑 could not write \(url(home: home).path) — every gated loopback route will answer 401")
            }
        }
        return token
    }

    /// May the gate accept what the home's file holds (`allows`' `onDisk`)? Only
    /// when this launch's own write landed — a failed one leaves an older launch's
    /// token there (when even the `unlink` failed), and that must not be
    /// honoured. The shoot writes nothing and keeps the old behaviour.
    static func trustsDisk(issued: String, persist: Bool, home: URL) -> Bool {
        !persist || read(home: home).map { equal($0, issued) } == true
    }

    /// The port the listener is on, for the callers to send the token there and
    /// nowhere else. Written at `.ready`, after the token.
    static func publishPort(_ port: UInt16, home: URL) {
        if !write(String(port), to: portURL(home: home), home: home) {
            Log.error("🔑 could not write \(portURL(home: home).path) — callers will not find port \(port)")
        }
    }

    /// `POST /reply` and `POST /ask`: the body's `reply-token` against the file's,
    /// in constant time like the header (Fable review, 2026-11-25), with the
    /// refusal logged through the same throttle as a 401 — a container posting
    /// wrong tokens must not be able to fill `relay.log`.
    static func replyTokenMatches(_ presented: Any?, expected: String, route: String) -> Bool {
        if let presented = presented as? String, !expected.isEmpty, equal(presented, expected) { return true }
        replyLock.lock()
        let verdict = replyThrottle.admit(RefusalThrottle.key("POST", route))
        replyLock.unlock()
        if let verdict {
            Log.error("🔑 POST \(route) refused — wrong or missing reply-token"
                      + (verdict.suppressed > 0 ? " (\(verdict.suppressed) more refusal(s) not logged)" : ""))
        }
        return false
    }

    private static let replyLock = NSLock()
    private static var replyThrottle = RefusalThrottle()
}

/// **Which refusals get a log line** (Fable review, 2026-11-25). The 401 used to be
/// throttled per full `"METHOD path"`, kept for ever: 2,000 tokenless requests
/// with distinct 500 KB paths pinned ~1 GB in the app and wrote 2,000 lines. Now
/// the key is the method and the path's first 60 characters, printable ASCII only
/// (a `\n` in a path cannot forge a log line); the table holds at most `maxKeys`;
/// and at most `maxLinesPerWindow` lines are written a minute whatever the keys —
/// the next line says how many were swallowed.
struct RefusalThrottle {
    static let window: TimeInterval = 60
    static let maxKeys = 64
    static let maxLinesPerWindow = 20

    private(set) var lastByKey: [String: Date] = [:]
    private var windowStart = Date.distantPast
    private var linesInWindow = 0
    private(set) var suppressed = 0

    /// `GET /test/state` → `GET /test/state`; a long or hostile path → its first
    /// 60 characters with anything outside printable ASCII made `?`.
    static func key(_ method: String, _ path: String) -> String {
        func clean<S: StringProtocol>(_ s: S, _ n: Int) -> String {
            String(String.UnicodeScalarView(s.unicodeScalars.prefix(n).map {
                (0x21...0x7E).contains($0.value) ? $0 : "?"
            }))
        }
        return clean(method, 10) + " " + clean(path, 60)
    }

    /// The line to write now and how many refusals went unlogged before it, or nil
    /// to stay quiet.
    mutating func admit(_ key: String, now: Date = Date()) -> (key: String, suppressed: Int)? {
        if now.timeIntervalSince(windowStart) >= Self.window {
            windowStart = now
            linesInWindow = 0
        }
        if let last = lastByKey[key], now.timeIntervalSince(last) < Self.window {
            suppressed += 1
            return nil
        }
        guard linesInWindow < Self.maxLinesPerWindow else {
            suppressed += 1
            return nil
        }
        if lastByKey.count >= Self.maxKeys {
            lastByKey = lastByKey.filter { now.timeIntervalSince($0.value) < Self.window }
            if lastByKey.count >= Self.maxKeys { lastByKey.removeAll() }
        }
        lastByKey[key] = now
        linesInWindow += 1
        defer { suppressed = 0 }
        return (key, suppressed)
    }
}
