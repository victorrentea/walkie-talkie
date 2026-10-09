import AppKit
import Foundation

/// **Test hooks for Wispr Flow as the engine** (2026-09-28) — the gaps the four
/// reviews in `evals/plan/wispr/` listed (A's H2, C's pasteboard timeline),
/// behind the loopback routes like every other `/test/*`. Nothing here runs
/// unless a route asks, and nothing here is read by a delivery path.

/// **`POST /test/wispr-proc {"stop"｜"cont"｜"kill"｜"relaunch": true, "afterMs"?, "forMs"?, "pid"?}`**
/// (A's H2) — SIGSTOP / SIGCONT / SIGKILL on Wispr Flow's **main** process
/// (the anchored executable, never the nested helper), or a relaunch.
///
/// - `afterMs`: the signal goes out that many ms from now (the answer is
///   immediate), so a case can land it after its own gesture.
/// - `forMs` (stop only, default 10 000, ceiling 60 000): the SIGCONT that
///   follows on its own — a harness that dies mid-case must not leave his
///   Wispr frozen.
/// - `pid`: the caller's idea of Wispr's pid; anything but the main process's
///   own is refused (409), so the route can never signal another process.
/// - `relaunch`: SIGKILL if running, wait ≤ 3 s for it to go, then
///   `open "/Applications/Wispr Flow.app"` **by path** — the bundle id resolves
///   to the nested helper as well (`dictation-source.md`, *Do not*).
enum WisprProc {
    static let appPath = "/Applications/Wispr Flow.app"

    static func handle(_ body: [String: Any]) -> (Int, [String: Any]) {
        let verbs = ["stop", "cont", "kill", "relaunch"].filter { body[$0] as? Bool == true || body["do"] as? String == $0 }
        guard verbs.count == 1, let verb = verbs.first else {
            return (400, ["ok": false, "error": "exactly one of stop｜cont｜kill｜relaunch"])
        }
        let main = WisprFlowSource.wisprMainPid
        if let asked = (body["pid"] as? NSNumber)?.int32Value, asked != main {
            return (409, ["ok": false, "error": "pid \(asked) is not Wispr Flow's main process",
                          "wisprPid": Int(main)])
        }
        if verb != "relaunch", main == 0 {
            return (409, ["ok": false, "error": "Wispr Flow is not running", "wisprPid": 0])
        }
        let after = max(0, min((body["afterMs"] as? NSNumber)?.intValue ?? 0, 60_000))
        let hold = max(100, min((body["forMs"] as? NSNumber)?.intValue ?? 10_000, 60_000))
        Log.info("🧪 POST /test/wispr-proc — \(verb) pid \(main)"
                 + (after > 0 ? " in \(after) ms" : "") + (verb == "stop" ? ", SIGCONT \(hold) ms later" : ""))
        let q = DispatchQueue.global()
        q.asyncAfter(deadline: .now() + .milliseconds(after)) {
            // The pid is re-checked at the signal: a Wispr relaunched in between
            // is a different process and is not the one the caller meant.
            guard verb == "relaunch" || WisprFlowSource.wisprMainPid == main else {
                Log.info("🧪 /test/wispr-proc: pid \(main) is gone — \(verb) not sent")
                return
            }
            switch verb {
            case "stop":
                kill(main, SIGSTOP)
                q.asyncAfter(deadline: .now() + .milliseconds(hold)) {
                    if kill(main, SIGCONT) == 0 { Log.info("🧪 /test/wispr-proc: pid \(main) resumed after \(hold) ms") }
                }
            case "cont":
                kill(main, SIGCONT)
            case "kill":
                kill(main, SIGKILL)
            default:
                if main != 0 {
                    kill(main, SIGKILL)
                    for _ in 0..<60 where WisprFlowSource.wisprMainPid != 0 { usleep(50_000) }
                }
                DispatchQueue.main.async {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath),
                                                       configuration: NSWorkspace.OpenConfiguration()) { app, error in
                        Log.info("🧪 /test/wispr-proc: relaunched — "
                                 + (error.map { "failed: \($0.localizedDescription)" } ?? "pid \(app?.processIdentifier ?? 0)"))
                    }
                }
            }
        }
        return (200, ["ok": true, "did": verb, "wisprPid": Int(main), "afterMs": after,
                      "forMs": verb == "stop" ? hold : NSNull()])
    }
}

/// **`GET /test/state.pasteboard`** (C's missing hook, W-C2/W-C3): the
/// clipboard's change count and a timeline of its moves — when, whether this
/// app wrote it (`noteOwnWrite` at each of its writes), and which app was in
/// front — **never the text, never the types** (reading those from another
/// process's write is the crash `WisprFlowSource.beginCapture` documents).
/// The 20 Hz sampler reads one integer, and starts on the first `/test/state`
/// read, so an app nobody is testing never runs it.
enum PasteboardTimeline {
    private static let lock = NSLock()
    private static var events: [[String: Any]] = []
    private static var own: [Int: String] = [:]
    private static var last = -1
    private static var timer: Timer?

    /// Right after a write of this app's own, with the reason.
    static func noteOwnWrite(_ why: String) {
        let count = Clipboard.changeCount
        lock.lock(); own[count] = why; ownWriteAt = Date(); ownCount = count; lock.unlock()
    }

    /// **The change count of this app's last own write** — a clipboard still at
    /// it holds the relay's sentence (Q17), not Wispr's promised item
    /// (`WisprFlowSource.claimForeignPaste`, batch 3). -1 before any write.
    static var lastOwnCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ownCount
    }
    private static var ownCount = -1

    /// **The last clipboard write of this app's own** — an insert, to the
    /// restart gate (`lastInsertAt`, 2026-09-28).
    static var lastOwnWriteAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return ownWriteAt
    }
    private static var ownWriteAt: Date?

    /// Main thread (the `/test/state` builder).
    static func describe() -> [String: Any] {
        if timer == nil {
            last = Clipboard.changeCount
            let t = Timer(timeInterval: 0.05, repeats: true) { _ in tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        // The count before the lock: `Clipboard`'s lock is always taken first
        // (`noteOwnWrite` runs inside a held write), never inside this one.
        let count = Clipboard.changeCount
        lock.lock(); defer { lock.unlock() }
        return ["changeCount": count, "events": events]
    }

    private static func tick() {
        let count = Clipboard.changeCount
        guard count != last else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        lock.lock()
        let mine = own.removeValue(forKey: count)
        var e: [String: Any] = ["changeCount": count, "at": Outbox.iso(Date()),
                                "writer": mine != nil ? "walkie" : "other", "front": front]
        if let mine { e["why"] = mine }
        // Several writes inside one 50 ms tick (a write and its restore) are one
        // event here; `skipped` says how many were folded into it.
        if count - last > 1 { e["skipped"] = count - last - 1 }
        events.append(e)
        if events.count > 40 { events.removeFirst(events.count - 40) }
        if own.count > 40 { own.removeAll() }
        lock.unlock()
        last = count
    }
}
