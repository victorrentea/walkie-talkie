import AppKit

/// **What the turn Walkie fired cost, rising from the pointer when it ends** (2026-11-19, Victor:
/// *"I'd like to see the amount of money that the last turn costed … a delicate, gentle
/// notification from the Walkie Talkie itself … the amount of money paid for the last turn fired
/// by the Walkie Talkie … in dollars … followed by the model name, and then saying in, and the
/// project … or the name of the terminal … float up from the cursor … if I hover my mouse over it,
/// it stops in its path upwards … comes back full opacity … the total time should be like two
/// seconds … for twenty percent of the height of the screen should raise up until completely
/// fading out"*).
///
/// **When.** Every prompt Walkie puts into a Claude Code session — a bound delivery, a spawn, a
/// caret prompt into Claude Code in Terminal or VS Code — arms `watch(tty:)`. The session is the one
/// the `walkie-inbox` mod names in `~/.walkie-talkie/inbox/<tty>/.alive` (Codex, Copilot and a
/// session without the mod have none: nothing is shown). Its transcript is read forward, once a
/// second, from the end of the turn before the prompt; Claude Code closes every turn with a
/// `{"type":"system","subtype":"turn_duration"}` line, and that line is the trigger. A prompt typed
/// into a running turn is folded into it, so the figure is that whole turn's — as the status line's
/// `+x.x` is.
///
/// **How much.** Every assistant response between the two `turn_duration` lines, once per message
/// id (each content block is its own line with the same usage), plus the subagents' transcripts
/// (`<session>/subagents/*.jsonl`) stamped inside the turn, at the API list prices of the model that
/// answered — the table and formula of `victor-statusline`'s `week-spend.py`, kept in step by hand.
/// On a subscription nothing is billed; this is what the turn *would* cost on a key, the unit the
/// bar uses.
///
/// **The float** (`CostFloat`): `💰 $1.40 · Opus 5.5 in walkie-talkie — <task>`, white on a solid black
/// pill, just above the pointer, **standing still** while it fades out over 4 s (ease-in: legible
/// first, gone fast at the end). It rose 20 % of the screen's height until 2026-11-20, Victor: *"it
/// should not float up, but stay next to the mouse while fading out so that I can read it"*. The
/// pointer over it holds it at full opacity; leaving resumes the fade from full over what is left. It
/// never takes a click (`ignoresMouseEvents`, the hover is geometry) and is out of screen shares
/// (`sharingType = .none`). The menu's **💸 Turn cost** tick turns it off (`enabled`).
enum TurnCost {

    // MARK: - Prices (victor-statusline/claude/hooks/week-spend.py, 2026-09-30)

    /// (substring of the model id, base input $/MTok, cache-read multiplier). Output is 5× input,
    /// a 5-minute cache write 1.25×, a 1-hour one 2×. Order matters: `opus-5-5` before `opus`.
    static let rates: [(key: String, input: Double, read: Double)] = [
        ("fable-5-1", 10, 0.025), ("mythos-5-1", 10, 0.025),
        ("fable", 10, 0.1), ("mythos", 10, 0.1),
        ("opus-5-5", 4, 0.05),
        ("opus-4-1", 15, 0.1), ("opus-4-0", 15, 0.1), ("opus-4-2025", 15, 0.1),
        ("opus", 5, 0.1),
        ("sonnet-5", 2, 0.1), ("sonnet", 3, 0.1),
        ("haiku-3", 0.8, 0.1), ("haiku", 1, 0.1),
    ]
    static let webSearchUSD = 0.01

    static func rate(_ model: String) -> (input: Double, read: Double) {
        for r in rates where model.contains(r.key) { return (r.input, r.read) }
        return (5, 0.1)
    }

    /// Dollars of one response's `usage`.
    static func cost(model: String, usage u: [String: Any]) -> Double {
        let (inp, rd) = rate(model)
        func n(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
        let cc = u["cache_creation"] as? [String: Any]
        var w5 = n(cc?["ephemeral_5m_input_tokens"]), w1 = n(cc?["ephemeral_1h_input_tokens"])
        if cc?["ephemeral_5m_input_tokens"] == nil, cc?["ephemeral_1h_input_tokens"] == nil {
            w5 = n(u["cache_creation_input_tokens"]); w1 = 0
        }
        let tokens = n(u["input_tokens"]) * inp + w5 * inp * 1.25 + w1 * inp * 2
            + n(u["cache_read_input_tokens"]) * inp * rd + n(u["output_tokens"]) * inp * 5
        let web = n((u["server_tool_use"] as? [String: Any])?["web_search_requests"]) * webSearchUSD
        return tokens / 1e6 + web
    }

    // MARK: - One turn, line by line

    /// What a turn's lines add up to. Fed one complete JSONL line at a time; `feed` answers true
    /// on the line that closes the turn.
    struct Turn {
        var usd = 0.0
        var subagentUSD = 0.0
        var responses = 0
        var model: String?
        var cwd: String?
        var start: String?
        var end: String?
        var durationMs: Double?
        var seen = Set<String>()
        var sawPrompt = false

        private static let markEnd = Data(#""subtype":"turn_duration""#.utf8)
        private static let markAssistant = Data(#""type":"assistant""#.utf8)
        private static let markUsage = Data(#""usage""#.utf8)
        private static let markUser = Data(#""type":"user""#.utf8)

        /// - Parameter window: a subagent's own file — its responses count toward `subagentUSD`,
        ///   only those stamped inside the turn.
        mutating func feed(_ line: Data, window: (String, String)? = nil) -> Bool {
            if line.range(of: Self.markEnd) != nil {
                guard window == nil, let o = Self.object(line), o["type"] as? String == "system",
                      o["subtype"] as? String == "turn_duration", o["isSidechain"] as? Bool != true else { return false }
                end = o["timestamp"] as? String
                durationMs = (o["durationMs"] as? NSNumber)?.doubleValue
                if cwd == nil { cwd = o["cwd"] as? String }
                return true
            }
            if line.range(of: Self.markAssistant) != nil, line.range(of: Self.markUsage) != nil {
                guard let o = Self.object(line), o["type"] as? String == "assistant",
                      let m = o["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
                      let id = (m["id"] as? String) ?? (o["requestId"] as? String) else { return false }
                let model = m["model"] as? String ?? ""
                guard model != "<synthetic>", !model.isEmpty else { return false }
                let ts = o["timestamp"] as? String ?? ""
                if let (lo, hi) = window, !(lo <= ts && ts <= hi) { return false }
                guard seen.insert(id).inserted else { return false }
                let usd = TurnCost.cost(model: model, usage: u)
                if window != nil { subagentUSD += usd } else {
                    self.usd += usd
                    if o["isSidechain"] as? Bool != true { self.model = model }
                }
                responses += 1
                if start == nil, window == nil { start = ts }
                if cwd == nil { cwd = o["cwd"] as? String }
                return false
            }
            if window == nil, line.range(of: Self.markUser) != nil, let o = Self.object(line),
               o["type"] as? String == "user", o["isMeta"] as? Bool != true, o["isSidechain"] as? Bool != true,
               Self.isPrompt((o["message"] as? [String: Any])?["content"]) {
                sawPrompt = true
                if start == nil { start = o["timestamp"] as? String }
                if cwd == nil { cwd = o["cwd"] as? String }
            }
            return false
        }

        /// A typed prompt: a string, or text blocks with no tool result among them.
        static func isPrompt(_ content: Any?) -> Bool {
            if content is String { return true }
            guard let blocks = content as? [[String: Any]], !blocks.isEmpty else { return false }
            return !blocks.contains { $0["type"] as? String == "tool_result" }
                && blocks.contains { $0["type"] as? String == "text" }
        }

        static func object(_ line: Data) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        }

        var total: Double { usd + subagentUSD }

        /// Wall time of the turn: Claude Code's own `durationMs`, else start → end.
        var seconds: Double? {
            if let ms = durationMs { return ms / 1000 }
            guard let s = start.flatMap(TurnCost.date), let e = end.flatMap(TurnCost.date) else { return nil }
            return e.timeIntervalSince(s)
        }
    }

    // MARK: - Reading the transcript

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    static func stamp(_ d: Date) -> String { iso.string(from: d) }
    static func date(_ s: String) -> Date? { iso.date(from: s) }

    /// The last non-sidechain `turn_duration` line that ends before `end` and is stamped before
    /// `before` (an ISO string; transcripts are UTC with milliseconds, so strings compare), as
    /// (its first byte, the byte after its newline). Read backwards a megabyte at a time, 64 MB at
    /// most; nil when there is none (a new session: its first turn starts at byte 0).
    static func lastTurnEnd(in url: URL, before end: UInt64, stampedBefore before: String = "~")
        -> (lineStart: UInt64, next: UInt64)? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let chunk: UInt64 = 1 << 20, cap: UInt64 = 64 << 20
        var hi = end
        var carry = Data()
        let mark = Data(#""subtype":"turn_duration""#.utf8)
        while hi > 0, end - hi < cap {
            let lo = hi > chunk ? hi - chunk : 0
            try? fh.seek(toOffset: lo)
            var data = (try? fh.read(upToCount: Int(hi - lo))) ?? Data()
            data.append(carry)
            var newlines: [Int] = []
            data.withUnsafeBytes { raw in
                for i in 0..<raw.count where raw[i] == 0x0A { newlines.append(i) }
            }
            // A line is (previous newline, this newline]; the head before the first newline is
            // partial unless this chunk starts the file, and an unterminated tail is a line too.
            var bounds: [(Int, Int)] = []
            var prev = -1
            for nl in newlines { bounds.append((prev + 1, nl)); prev = nl }
            if prev + 1 < data.count { bounds.append((prev + 1, data.count)) }
            for (i, (s, e)) in bounds.enumerated().reversed() {
                if i == 0, lo > 0 { break }
                let line = data.subdata(in: s..<e)
                guard line.range(of: mark) != nil, let o = Turn.object(line),
                      o["type"] as? String == "system", o["isSidechain"] as? Bool != true,
                      let ts = o["timestamp"] as? String, ts < before else { continue }
                return (lo + UInt64(s), lo + UInt64(min(e + 1, data.count)))
            }
            if lo == 0 { return nil }
            carry = newlines.first.map { data.prefix($0 + 1) } ?? data
            hi = lo
        }
        return nil
    }

    /// The complete lines of `url` in [from, to), each with the byte after it; `body` answering
    /// true stops the read.
    static func forEachLine(in url: URL, from: UInt64, to: UInt64, _ body: (Data, UInt64) -> Bool) {
        guard to > from, let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? fh.close() }
        try? fh.seek(toOffset: from)
        var offset = from              // the byte after what has been read
        var pending = Data()           // read, not yet a whole line
        while offset < to {
            let want = Int(min(to - offset, 1 << 20))
            guard let data = try? fh.read(upToCount: want), !data.isEmpty else { return }
            offset += UInt64(data.count)
            pending.append(data)
            let base = offset - UInt64(pending.count)   // file offset of pending's first byte
            var lineStart = 0
            var stop = false
            let bytes = [UInt8](pending)
            for i in 0..<bytes.count where bytes[i] == 0x0A {
                let line = Data(bytes[lineStart..<i])
                lineStart = i + 1
                if body(line, base + UInt64(lineStart)) { stop = true; break }
            }
            if stop { return }
            pending = Data(bytes[lineStart...])
        }
    }

    /// Adds the subagents' responses stamped inside the turn.
    static func addSubagents(of transcript: URL, to turn: inout Turn) {
        guard let lo = turn.start, let hi = turn.end else { return }
        let dir = transcript.deletingPathExtension().appendingPathComponent("subagents")
        let floor = date(lo)?.addingTimeInterval(-60) ?? .distantPast
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        for f in files where f.pathExtension == "jsonl" {
            let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard (v?.contentModificationDate ?? .distantPast) >= floor, let size = v?.fileSize else { continue }
            forEachLine(in: f, from: 0, to: UInt64(size)) { line, _ in
                _ = turn.feed(line, window: (lo, hi)); return false
            }
        }
    }

    /// The last finished turn of a transcript — `POST /test/turn-cost {"transcript": …}`.
    static func lastTurn(of url: URL) -> Turn? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
              let last = lastTurnEnd(in: url, before: size) else { return nil }
        let from = lastTurnEnd(in: url, before: last.lineStart)?.next ?? 0
        var turn = Turn()
        forEachLine(in: url, from: from, to: last.next) { line, _ in turn.feed(line) }
        addSubagents(of: url, to: &turn)
        return turn
    }

    // MARK: - Which session a tty holds

    static let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    /// The interactive Claude Code session on this tty: Claude Code's own registry
    /// (`~/.claude/sessions/<pid>.json`, one per running process: `sessionId`, `kind`, `startedAt`),
    /// asked for every process on the tty, newest interactive one first; else the mod's beat. A
    /// `claude -p` a session runs from Bash shares its tty and is not interactive, so it never wins.
    /// The registry follows a process that switches session (a `/clear`, a `/resume`); the beat can
    /// be another session's whose process inherited the tty.
    static func session(onTTY short: String) -> String? {
        registrySession(onTTY: short) ?? aliveSession(onTTY: short)
    }

    static let registry = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

    static func registrySession(onTTY short: String) -> String? {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-t", short, "-o", "pid="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return nil }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var best: (at: Double, id: String)?
        for pid in String(decoding: out, as: UTF8.self).split(whereSeparator: \.isWhitespace) {
            let f = registry.appendingPathComponent("\(pid).json")
            guard let data = try? Data(contentsOf: f), let o = Turn.object(data),
                  o["kind"] as? String == "interactive", let id = o["sessionId"] as? String else { continue }
            let at = (o["startedAt"] as? NSNumber)?.doubleValue ?? 0
            if best == nil || at > best!.at { best = (at, id) }
        }
        return best?.id
    }

    /// The session the `walkie-inbox` mod reports on this tty, if its beat is fresh.
    static func aliveSession(onTTY short: String) -> String? {
        let alive = Outbox.defaultHome.appendingPathComponent("inbox/\(short)/.alive")
        guard let at = (try? FileManager.default.attributesOfItem(atPath: alive.path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(at) < 8,
              let data = try? Data(contentsOf: alive), let o = Turn.object(data) else { return nil }
        return o["session"] as? String
    }

    static func transcript(ofSession id: String) -> URL? {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projects.path) else { return nil }
        for d in dirs {
            let f = projects.appendingPathComponent(d).appendingPathComponent("\(id).jsonl")
            if fm.fileExists(atPath: f.path) { return f }
        }
        return nil
    }

    // MARK: - Watching a turn

    /// **💸 Turn cost**, a tick in the menu (2026-11-20, Victor: *"cost tracking-ul trebuie să fie o
    /// opțiune pe care o pot activa sau dezactiva … din meniu"*). On unless he turns it off;
    /// `WT_TURN_COST=0|1` (env → `elevenlabs.env`) wins for a test. Off stops new watches, and a
    /// turn already watched ends without a float.
    static var enabled: Bool {
        get {
            if let v = ProcessInfo.processInfo.environment["WT_TURN_COST"] ?? ElevenLabsSource.fileValue("WT_TURN_COST") {
                return v != "0"
            }
            return UserDefaults.standard.object(forKey: "turnCost") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "turnCost") }
    }

    /// The ttys being watched → whether another prompt went in meanwhile. Main only.
    private static var watching: [String: Bool] = [:]

    /// **The watches outlive a restart** (2026-11-19 — the first real one was lost to another
    /// session's deploy 29 s before its turn ended). `~/.walkie-talkie/turn-watch.json` holds
    /// `{tty: {since, why}}` while a watch runs; `resume()` at launch arms them again, and the
    /// transcript is read from the turn before `since`, so a turn that ended while the app was down
    /// is found at once (and floated only if it ended under `lateFloat` ago).
    private static var armed: [String: [String: Any]] = [:]
    private static var armedFile: URL { Outbox.home.appendingPathComponent("turn-watch.json") }
    static let lateFloat: TimeInterval = 90

    private static func saveArmed() {
        if armed.isEmpty { try? FileManager.default.removeItem(at: armedFile); return }
        if let data = try? JSONSerialization.data(withJSONObject: armed) { try? data.write(to: armedFile, options: .atomic) }
    }

    /// Arms again the watches a previous run left (launch, main thread).
    static func resume() {
        guard let data = try? Data(contentsOf: armedFile),
              let left = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else { return }
        try? FileManager.default.removeItem(at: armedFile)
        for (short, o) in left {
            guard let at = (o["since"] as? NSNumber)?.doubleValue else { continue }
            let since = Date(timeIntervalSince1970: at)
            guard Date().timeIntervalSince(since) < turnWait else { continue }
            Log.info("💸 \(short): watching again after a restart (prompt at \(stamp(since)))")
            watch(tty: short, since: since, why: (o["why"] as? String ?? "?") + ", resumed")
        }
    }
    static let sessionWait: TimeInterval = 90
    static let turnWait: TimeInterval = 4 * 3600

    /// Arms the float for the turn a prompt just put into `tty`. `since`: when the prompt left
    /// (a spawn: its launch). Main thread.
    static func watch(tty: String, since: Date = Date(), why: String) {
        guard enabled else { return }
        let short = (tty as NSString).lastPathComponent
        guard !short.isEmpty else { return }
        if watching[short] != nil {
            watching[short] = true
            return
        }
        watching[short] = false
        armed[short] = ["since": since.timeIntervalSince1970, "why": why]
        saveArmed()
        DispatchQueue.global(qos: .utility).async {
            let switched = run(short: short, since: since, why: why)
            DispatchQueue.main.async {
                // A prompt that came in meanwhile went to the session now on the tty.
                let pending = watching[short] == true
                watching[short] = nil; armed[short] = nil; saveArmed()
                if switched, pending { watch(tty: short, why: why + ", new session") }
            }
        }
    }

    /// True when the watch ended because another session took the tty.
    @discardableResult
    private static func run(short: String, since: Date, why: String) -> Bool {
        // The session: the mod's beat, fresh. A spawn's comes up a few seconds after its launch.
        var transcript: URL?
        var watched: String?
        let deadline = Date().addingTimeInterval(sessionWait)
        while transcript == nil, Date() < deadline {
            if let id = session(onTTY: short) { transcript = self.transcript(ofSession: id); watched = id }
            if transcript == nil { Thread.sleep(forTimeInterval: 1) }
        }
        guard let url = transcript else {
            Log.info("💸 \(short): no Claude Code session there — no cost float (\(why))")
            return false
        }
        // **Still that session on the tty?** A turn that
        // never writes `turn_duration` (the session closed, or was interrupted and
        // left) parked this watch for `turnWait` and swallowed every later prompt
        // to the tty — a new session's in a new tab with the same number too.
        var checkedAt = Date()
        var gone = 0
        func stillThere() -> Bool? {
            guard Date().timeIntervalSince(checkedAt) >= 10 else { return true }
            checkedAt = Date()
            let now = session(onTTY: short)
            if now == watched { gone = 0; return true }
            if now != nil { return nil }       // another session
            gone += 1
            return gone < 3                    // ~30 s with no session at all
        }
        let fm = FileManager.default
        func size() -> UInt64? { (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64 }
        guard let now = size() else { return false }
        // From the end of the last turn that closed before the prompt left.
        var from = lastTurnEnd(in: url, before: now, stampedBefore: stamp(since.addingTimeInterval(-1)))?.next ?? 0
        var mustSeePrompt = false
        let give = Date().addingTimeInterval(turnWait)
        while Date() < give {
            var turn = Turn()
            var end: UInt64?
            var read = from
            let promptBy = Date().addingTimeInterval(6)
            while end == nil, Date() < give {
                if let s = size(), s > read {
                    forEachLine(in: url, from: read, to: s) { line, after in
                        read = after
                        if turn.feed(line) { end = after; return true }
                        return false
                    }
                }
                if end == nil {
                    if mustSeePrompt, !turn.sawPrompt, Date() > promptBy { return false }
                    switch stillThere() {
                    case true?: break
                    case false?:
                        Log.info("💸 \(short): the session is gone, its turn never closed — watch ended")
                        return false
                    case nil:
                        Log.info("💸 \(short): another session took the tty — watch ended")
                        return true
                    }
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            guard let closed = end else {
                Log.info("💸 \(short): no turn ended in \(Int(turnWait / 3600)) h — given up")
                return false
            }
            addSubagents(of: url, to: &turn)
            if turn.responses > 0 { report(turn, short: short) }
            // A second prompt during the watch that started a turn of its own: watch that one too.
            var again = false
            DispatchQueue.main.sync { again = watching[short] == true; watching[short] = false }
            guard again else { return false }
            from = closed
            mustSeePrompt = true
            DispatchQueue.main.async { armed[short]?["since"] = Date().timeIntervalSince1970; saveArmed() }
        }
        return false
    }

    // MARK: - Saying it

    static func money(_ usd: Double) -> String {
        if usd < 0.005 { return "<$0.01" }
        if usd >= 100 { return String(format: "$%.0f", usd) }
        return String(format: "$%.2f", usd)
    }

    static func text(_ turn: Turn, place: String?) -> (amount: String, rest: String) {
        var rest = ""
        if let m = turn.model { rest += " · " + QuickAsk.displayName(m) }
        if let place, !place.isEmpty { rest += " in " + place }
        return (money(turn.total), rest)
    }

    /// `walkie-talkie — <task>` off the tab's title, else the folder.
    static func place(short: String, cwd: String?) -> String? {
        let folder = cwd.map { ($0 as NSString).lastPathComponent }
        let titles = TerminalBinding.liveTitles().merging(OrcaBridge.liveTitles()) { terminal, _ in terminal }
        let title = titles[short]
        if let folder, let task = ActiveTerminals.task(fromTitle: title, folder: folder) {
            return "\(folder) — \(task)"
        }
        if let folder { return folder }
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? short
    }

    private static func report(_ turn: Turn, short: String) {
        let place = place(short: short, cwd: turn.cwd)
        let (amount, rest) = text(turn, place: place)
        let secs = turn.seconds.map { String(format: ", %.0f s", $0) } ?? ""
        let sub = turn.subagentUSD > 0 ? String(format: " (subagents $%.2f)", turn.subagentUSD) : ""
        Log.info("💸 \(short): the turn cost \(amount)\(sub) — \(turn.responses) responses\(secs)\(rest)")
        // A turn that ended while the app was down is told in the log only: a float minutes late
        // would be about nothing he is looking at.
        if let end = turn.end.flatMap(date), Date().timeIntervalSince(end) > lateFloat {
            Log.info("💸 \(short): that turn ended \(Int(Date().timeIntervalSince(end))) s ago — no float")
            return
        }
        DispatchQueue.main.async { if enabled { CostFloat.show(amount: amount, rest: rest) } }
    }
}

// MARK: - The float

/// The label that appears by the pointer and fades where it stands (see `TurnCost`). Main thread only.
final class CostFloat {
    static let duration: TimeInterval = 4.0
    static let gapAbovePointer: CGFloat = 18

    private static var live: [CostFloat] = []

    private let window: NSPanel
    private let start: NSPoint          // the window's origin, fixed
    private var p: CGFloat = 0          // the share of the fade done
    private var segP: CGFloat = 0       // where the current fade began
    private var segAt = CACurrentMediaTime()
    private var hovered = false
    private var armed = false           // the pointer has been outside it once
    private var timer: Timer?

    /// The pill: white text on solid black, the amount semibold (2026-11-20: black from 45 %, the type
    /// 20 % smaller — 16/15 → 13/12).
    static func view(amount: String, rest: String) -> NSView {
        // 💰 before the figure (2026-11-20, Victor: *"pune acest emoji înainte de cifre"*).
        let text = NSMutableAttributedString(string: "💰 " + amount, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
        text.append(NSAttributedString(string: rest, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)]))
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.sizeToFit()
        let maxText: CGFloat = 640
        let size = NSSize(width: min(ceil(label.frame.width), maxText) + 18, height: ceil(label.frame.height) + 8)
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.cgColor
        box.layer?.cornerRadius = size.height / 2
        label.frame = NSRect(x: 9, y: 4, width: size.width - 18, height: size.height - 8)
        box.addSubview(label)
        return box
    }

    /// A picture of the pill on a light grey ground, for review (`POST /test/turn-cost {"png"}`).
    static func png(amount: String, rest: String, to path: String) -> Bool {
        let v = view(amount: amount, rest: rest)
        let backing = NSView(frame: NSRect(x: 0, y: 0, width: v.frame.width + 24, height: v.frame.height + 24))
        backing.wantsLayer = true
        backing.layer?.backgroundColor = NSColor(white: 0.85, alpha: 1).cgColor
        v.setFrameOrigin(NSPoint(x: 12, y: 12))
        backing.addSubview(v)
        let w = NSWindow(contentRect: backing.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.contentView = backing
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(backing.frame.width * 2),
                                         pixelsHigh: Int(backing.frame.height * 2), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = backing.frame.size
        backing.cacheDisplay(in: backing.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    @discardableResult
    static func show(amount: String, rest: String, at point: NSPoint? = nil, capturable: Bool = false) -> CostFloat {
        let f = CostFloat(amount: amount, rest: rest, at: point ?? NSEvent.mouseLocation, capturable: capturable)
        live.append(f)
        f.begin()
        return f
    }

    var report: [String: Any] {
        ["frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
         "alpha": window.alphaValue, "faded": p, "hovered": hovered]
    }
    static var state: [[String: Any]] { live.map(\.report) }

    private init(amount: String, rest: String, at pointer: NSPoint, capturable: Bool) {
        let content = Self.view(amount: amount, rest: rest)
        let size = content.frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = (pointer.x - size.width / 2).rounded()
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        // Just above the pointer; a pointer at the top puts it lower (it may then sit under the
        // pointer: `armed` waits for the pointer to leave before a hover counts).
        var y = (pointer.y + Self.gapAbovePointer).rounded()
        y = min(y, visible.maxY - size.height - 4)
        // Floats still showing stand where they are: this one goes under them.
        let crowd = Self.live.count
        y -= CGFloat(crowd) * (size.height + 6)
        y = max(y, visible.minY + 4)
        start = NSPoint(x: x, y: y)

        window = NSPanel(contentRect: NSRect(origin: start, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = capturable ? .readOnly : .none
        window.contentView = content
        window.alphaValue = 1
    }

    private func begin() {
        window.orderFrontRegardless()
        segAt = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let inside = window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if !inside { armed = true }
        if armed && inside {
            hovered = true
            window.alphaValue = min(1, window.alphaValue + (1 - window.alphaValue) * 0.35 + 0.02)
            return
        }
        if hovered {
            // Left it: the rest of the fade, from full.
            hovered = false
            segP = p
            segAt = now
        }
        let span = max(0.5, Self.duration * Double(1 - segP))
        let u = CGFloat(min(1, (now - segAt) / span))
        p = segP + (1 - segP) * u
        window.alphaValue = 1 - u * u       // ease-in: stays legible, then goes
        if u >= 1 { finish() }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        window.orderOut(nil)
        Self.live.removeAll { $0 === self }
    }
}
