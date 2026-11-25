import AppKit

/// **Orca (onorca.dev) as the terminal host — experimental, behind one switch** (2026-11-19).
///
/// Victor: *"let's put a toggle in the menu which, if enabled, switches from the Terminal thing to
/// integration with Orca: for starting a new terminal, for giving another prompt to an existing
/// terminal running in there, and for binding a terminal in OrcaDev. These many terminals I'm
/// running right now can be a bit hard to track which are which."*
///
/// **Everything goes through Orca's own CLI** (`orca … --json`, ~0.35 s a call — a node process
/// talking to the running app over its local socket). No AppleScript (Orca has no dictionary), no
/// keystrokes, no focus moved to type.
///
/// **An Orca terminal is a real local tty**: Orca's daemon starts each pane as
/// `/usr/bin/login … orca-tcc-login /bin/zsh -l` on a `/dev/ttysNNN`, the shape of a Terminal.app
/// tab. So the binding is the **tty** (`TerminalBinding.Handle.orca`), and everything the relay
/// already asks of a tty — the shell guard, liveness, the tab's owner (`login` by pid and start),
/// the session's folder, ⏳ / 💀 — works unchanged. Only three things need Orca: typing into the
/// pane, bringing it forward, and opening a new one. The Orca handle (`term_…`) is runtime-scoped
/// (a new one after an Orca restart), so it is never stored: it is looked up from the tty at each use.
///
/// **tty ↔ handle**: `terminal list` gives handle + `ptyId`; `diagnostics memory` gives
/// `sessionId` (= ptyId) + the pane's root pid; `ps` gives that pid's tty. No other call names a pid.
enum OrcaBridge {
    static let bundleID = "com.stablyai.orca"
    static let appName = "Orca"
    static let menuTitle = "Send to Orca IDE (experimental)"
    static let defaultsKey = "orcaIntegration"
    static let cli = "/Applications/Orca.app/Contents/Resources/bin/orca"

    /// The menu's switch. Off by default; off, nothing here is reached except to deliver to an
    /// Orca pane bound while it was on.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var installed: Bool { FileManager.default.isExecutableFile(atPath: cli) }

    static var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    /// One pane of an Orca terminal tab.
    struct Pane: Equatable {
        let handle: String
        let ptyID: String
        let worktreePath: String
        let title: String?
        /// `/dev/ttysNNN`, or nil when its pid could not be read.
        let tty: String?
    }

    // MARK: - The CLI

    /// `orca <args>` → its `result` object, or nil (logged) on a refusal, a timeout or no Orca.
    /// Off the main thread.
    static func call(_ args: [String], timeout: TimeInterval = 8) -> [String: Any]? {
        guard installed else { return nil }
        let outcome = TerminalBinding.runOutcome(cli, args, timeout: timeout)
        let what = args.prefix(2).joined(separator: " ")
        guard case .ok(let out) = outcome else {
            Log.error("🐋 orca \(what) failed — \(outcome.reason)")
            return nil
        }
        guard let data = out.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.error("🐋 orca \(what) answered no JSON")
            return nil
        }
        guard json["ok"] as? Bool == true else {
            let error = (json["error"] as? [String: Any])?["message"] as? String ?? "\(json["error"] ?? "not ok")"
            Log.error("🐋 orca \(what) refused — \(error.prefix(200))")
            return nil
        }
        return json["result"] as? [String: Any] ?? [:]
    }

    // MARK: - Panes

    /// Every live Orca terminal pane with its tty, plus the visual layouts when asked for.
    static func snapshot(layouts: Bool = false) -> (panes: [Pane], layouts: [[String: Any]]) {
        guard app != nil else { return ([], []) }
        var args = ["terminal", "list", "--json"]
        if layouts { args.insert("--include-visual-layouts", at: 2) }
        guard let list = call(args), let rows = list["terminals"] as? [[String: Any]] else { return ([], []) }
        var pidByPty: [String: Int32] = [:]
        if let memory = call(["diagnostics", "memory", "--json"]) {
            for worktree in memory["worktrees"] as? [[String: Any]] ?? [] {
                for session in worktree["sessions"] as? [[String: Any]] ?? [] {
                    if let id = session["sessionId"] as? String, let pid = (session["pid"] as? NSNumber)?.int32Value {
                        pidByPty[id] = pid
                    }
                }
            }
        }
        let ttys = ttys(ofPIDs: Array(pidByPty.values))
        let panes = rows.compactMap { row -> Pane? in
            guard let handle = row["handle"] as? String, row["connected"] as? Bool != false else { return nil }
            let pty = row["ptyId"] as? String ?? ""
            let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Pane(handle: handle, ptyID: pty, worktreePath: row["worktreePath"] as? String ?? "",
                        title: title, tty: pidByPty[pty].flatMap { ttys[$0] })
        }
        return (panes, list["visualLayouts"] as? [[String: Any]] ?? [])
    }

    static func panes() -> [Pane] { snapshot().panes }

    /// The pane on this tty (either spelling), or nil — what `bind(tty:)` asks.
    static func pane(tty: String) -> Pane? {
        let device = tty.hasPrefix("/") ? tty : "/dev/" + (tty as NSString).lastPathComponent
        return panes().first { $0.tty == device }
    }

    /// `ps -o pid=,tty= -p a,b,c` → pid → `/dev/ttysNNN`.
    private static func ttys(ofPIDs pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty,
              case .ok(let out) = TerminalBinding.runOutcome("/bin/ps", ["-o", "pid=,tty=", "-p",
                                                                        pids.map(String.init).joined(separator: ",")])
        else { return [:] }
        var map: [Int32: String] = [:]
        for line in out.components(separatedBy: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count == 2, let pid = Int32(f[0]), f[1] != "??" else { continue }
            map[pid] = f[1].hasPrefix("/dev/") ? f[1] : "/dev/" + f[1]
        }
        return map
    }

    /// **The pane Victor is looking at in Orca** — what ⌘⌃B binds with Orca in front: the active
    /// workspace (`worktree ps`'s `isActive`), its layout's active tab, that tab's active leaf. A
    /// layout split into several tab groups names an active tab in each and nothing says which
    /// group has the keyboard — then the first group's, and the log says so.
    static func frontPane() -> Pane? {
        guard let ps = call(["worktree", "ps", "--json"]),
              let active = (ps["worktrees"] as? [[String: Any]])?.first(where: { $0["isActive"] as? Bool == true }),
              let worktreeID = active["worktreeId"] as? String else {
            Log.error("🐋 bind: Orca names no active workspace")
            return nil
        }
        let (panes, layouts) = snapshot(layouts: true)
        let inWorktree = panes.filter { $0.worktreePath == (active["path"] as? String ?? "") }
        func collect(_ node: Any, _ keep: ([String: Any]) -> Bool, into out: inout [[String: Any]]) {
            if let d = node as? [String: Any] {
                if keep(d) { out.append(d) }
                for v in d.values { collect(v, keep, into: &out) }
            } else if let a = node as? [Any] {
                for v in a { collect(v, keep, into: &out) }
            }
        }
        guard let layout = layouts.first(where: { $0["worktreeId"] as? String == worktreeID }),
              let root = layout["root"] else {
            return inWorktree.count == 1 ? inWorktree[0] : nil
        }
        var groups: [[String: Any]] = []
        collect(root, { $0["tabs"] != nil && $0["activeTabId"] != nil }, into: &groups)
        if groups.count > 1 { Log.info("🐋 bind: \(groups.count) tab groups in the active Orca workspace — the first one's active tab") }
        guard let group = groups.first, let tabID = group["activeTabId"] as? String,
              let tab = (group["tabs"] as? [[String: Any]])?.first(where: { $0["tabId"] as? String == tabID }) else {
            return inWorktree.count == 1 ? inWorktree[0] : nil
        }
        var leaves: [[String: Any]] = []
        collect(tab, { $0["type"] as? String == "terminal" && $0["handle"] != nil }, into: &leaves)
        let leafID = tab["activeLeafId"] as? String
        let leaf = leaves.first { $0["leafId"] as? String == leafID }
            ?? leaves.first { $0["active"] as? Bool == true } ?? leaves.first
        guard let handle = leaf?["handle"] as? String else {
            Log.error("🐋 bind: the active Orca tab is not a terminal (a chat, an editor, a browser?)")
            return nil
        }
        return panes.first { $0.handle == handle }
    }

    // MARK: - Typing

    /// Raw bytes into the pane, no Enter — Orca writes `--text` verbatim when `--enter` is absent,
    /// which is the Terminal.app path's `do script` chunk. **Never Orca's `--enter` with text**: it
    /// bracketed-pastes into a recognised agent, and Claude Code then wraps the words in
    /// `<pasted_content>` and reads them as data (`terminal-binding.md`, *Never reintroduce*).
    static func type(_ text: String, handle: String) -> Bool {
        // `--text=`, one argument: a separate value that starts with `-` is read as a
        // flag (`--version is what I meant` was refused, measured 2026-11-19).
        call(["terminal", "send", "--terminal", handle, "--text=" + text, "--json"]) != nil
    }

    /// A bare Enter — Orca's direct-input path, one carriage return.
    static func pressReturn(handle: String) -> Bool {
        call(["terminal", "send", "--terminal", handle, "--enter", "--json"]) != nil
    }

    /// The pane's screen as it is drawn now, rows joined by newlines.
    static func screen(handle: String) -> String? {
        guard let r = call(["terminal", "read", "--terminal", handle, "--screen", "--json"]),
              let t = r["terminal"] as? [String: Any], let tail = t["tail"] as? [String] else { return nil }
        return tail.joined(separator: "\n")
    }

    /// **Type a dictation into the pane on `tty` and submit it** — the Orca twin of
    /// `TerminalBinding.writeToTerminalApp`, on the same readings of Claude Code's screen
    /// (`waitsToSendNow`, `asksForReview`, `stillInPrompt`, `submitted`): the chunk, 0.5 s, a Return,
    /// then up to four more Returns watched for 4 s, and ⌃X ⌃S on a sentence queued behind a turn.
    /// A copy rather than a shared loop, so the Terminal.app path is not touched by an experiment.
    ///
    /// **Never into an open dialog** (2026-11-25, `DialogGate`): the mod's flag before the
    /// text, before the first Return and before every watched one; the screen reads this
    /// loop already makes before every watched Return. `.dialog(typed:)` — nothing more
    /// was sent; `resume` — a try after one stopped past its text: the pane is read first.
    enum Delivery { case delivered, noPane, refused, dialog(typed: Bool) }

    /// `.noPane` = no Orca pane on that tty (the caller's `targetGone`); `.refused` =
    /// Orca would not take the line (nothing typed).
    static func deliver(_ text: String, tty: String,
                        interrupt: Bool = false, sentNow: (() -> Void)? = nil,
                        resume: Bool = false) -> Delivery {
        guard let pane = pane(tty: tty) else { return .noPane }
        let h = pane.handle
        if resume, let seen = screen(handle: h), TerminalBinding.stillInPrompt(tail: seen, sent: text) {
            Log.info("▶️ 🐋 \((tty as NSString).lastPathComponent): the sentence is still in the box — only its Return")
        } else {
            if DialogGate.flagUp(tty: tty) { return .dialog(typed: false) }
            guard type(text, handle: h) else { return .refused }
            usleep(500_000)
        }
        if DialogGate.flagUp(tty: tty) { return .dialog(typed: true) }
        // A refused Return is not a delivery (2026-11-25, Fable review): the watch
        // below reads the pane and presses again while the sentence is still in the box.
        if !pressReturn(handle: h) { Log.error("⌨️ 🐋 the first Return was refused — watching the pane to press it again") }
        usleep(350_000)
        var tail = screen(handle: h) ?? ""
        var presses = 0, reads = 1, lookedAgain = false
        let deadline = Date().addingTimeInterval(4)
        while true {
            let shown = String(tail.suffix(600))
            // 🛑 An interrupt sentence: on the queue itself too (`TerminalBinding.sendsNow`).
            let dialog = DialogGate.flagUp(tty: tty) || DialogGate.screenShowsDialog(tail: tail, sent: text)
            if TerminalBinding.sendsNow(tail: tail, sent: text, interrupt: interrupt) {
                // Queued already: a dialog now only costs the chord.
                if dialog { Log.info("⏸ 🐋 ⌃X ⌃S not pressed — a dialog is open; the sentence stays queued"); break }
                if type(TerminalBinding.sendNowChord, handle: h) {
                    _ = pressReturn(handle: h)
                    Log.info("⌨️ 🐋 ⌃X ⌃S — the sentence was queued behind a running turn, sent now\(interrupt ? " (🛑 interrupt)" : "")")
                    sentNow?()
                }
                break
            }
            var why: String?
            if TerminalBinding.asksForReview(tail: shown, sent: text) { why = "Claude Code read the block as a paste and asked to review it" }
            else if TerminalBinding.stillInPrompt(tail: tail, sent: text) { why = "the sentence was still in the prompt box" }
            if let why, presses < 4 {
                if dialog { return .dialog(typed: true) }
                guard pressReturn(handle: h) else { break }
                presses += 1
                Log.info("⌨️ 🐋 Return #\(presses + 2) — \(why)")
                usleep(500_000)
            } else {
                if why == nil, TerminalBinding.submitted(tail: shown, sent: text) {
                    if lookedAgain { break }
                    lookedAgain = true
                    usleep(400_000)
                    reads += 1
                    guard let more = screen(handle: h) else { break }
                    tail = more
                    continue
                }
                guard Date() < deadline else { break }
                usleep(why == nil ? 900_000 : 500_000)
            }
            reads += 1
            guard let more = screen(handle: h) else { break }
            tail = more
        }
        Log.info("⌨️ 🐋 \(h.prefix(13))… on \((tty as NSString).lastPathComponent): \(presses) extra Return(s), \(reads) read-back(s)")
        return .delivered
    }

    // MARK: - Front

    /// Switch Orca's view to the pane (`terminal switch` — it does not activate the app; the
    /// caller raises Orca's window).
    static func show(tty: String) -> Bool {
        guard let pane = pane(tty: tty) else { return false }
        return call(["terminal", "switch", "--terminal", pane.handle, "--json"]) != nil
    }

    /// Orca's focused window, Cocoa coordinates — what a flight lands on. A pane has no frame of
    /// its own that anything outside Orca can read.
    static func windowFrame() -> CGRect? {
        app.flatMap { TerminalBinding.focusedWindow(pid: $0.processIdentifier).frame }
    }

    // MARK: - A new session

    /// **Walkie's own launcher in a new Orca terminal tab, in `directory`** — the same
    /// `start-<stamp>.sh` `SpawnTerminal` hands Terminal.app (`claude
    /// --allow-dangerously-skip-permissions --permission-mode auto "<prompt>"`), so the session is
    /// the one Victor knows, its prompt in its argv. Not `orca agent launch`: that follows Orca's
    /// own agent settings.
    ///
    /// **The main checkout, never a worktree**: the folder is registered as an Orca project when it
    /// is not one (`repo add`, git or plain folder) and the tab opens in that project's own
    /// checkout (`--worktree path:`). Victor deploys from local; Orca's per-agent worktrees are its
    /// `worktree create`, never called here.
    ///
    /// The new pane's tty (`/dev/ttysNNN`), or why not. Off the main thread.
    static func open(launcher: String, directory: String) -> Result<String, OrcaError> {
        guard installed else { return .failure(OrcaError("Orca is not installed")) }
        if app == nil {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Orca.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
            for _ in 0..<40 {
                let runtime = call(["status", "--json"], timeout: 3)?["runtime"] as? [String: Any]
                if runtime?["state"] as? String == "ready" { break }
                usleep(500_000)
            }
        }
        let path = (directory as NSString).standardizingPath
        let known = (call(["repo", "list", "--json"])?["repos"] as? [[String: Any]] ?? [])
            .contains { ($0["path"] as? String).map { ($0 as NSString).standardizingPath } == path }
        if !known {
            let git = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
            let add = ["repo", "add", "--path", path] + (git ? [] : ["--kind", "folder"]) + ["--json"]
            guard call(add) != nil else { return .failure(OrcaError("Orca would not add \(path) as a project")) }
            Log.info("🐋 \(path) added to Orca as a \(git ? "git" : "folder") project")
        }
        // No `--title`: a custom title freezes the tab on the folder's name; the
        // session's own title is what the tab should wear (`syncTabTitles`).
        guard let created = call(["terminal", "create", "--worktree", "path:\(path)",
                                  "--command", launcher, "--focus", "--json"], timeout: 15),
              let terminal = created["terminal"] as? [String: Any],
              let handle = terminal["handle"] as? String else {
            return .failure(OrcaError("Orca would not open a terminal in \(path)"))
        }
        // The create answers the pane's process id; its tty is one `ps` away.
        if let pid = (terminal["processId"] as? NSNumber)?.int32Value, let tty = TerminalBinding.tty(ofPID: pid) {
            Log.info("🐋 new Orca tab \(handle.prefix(13))… in \(path) on \(tty)")
            return .success(tty)
        }
        for _ in 0..<10 {
            if let tty = panes().first(where: { $0.handle == handle })?.tty { return .success(tty) }
            usleep(300_000)
        }
        return .failure(OrcaError("the new Orca tab never showed its tty"))
    }

    struct OrcaError: Error { let why: String; init(_ why: String) { self.why = why } }

    // MARK: - Tab titles (2026-11-19, evening)

    /// **Each Claude Code tab named like its Terminal.app window: `walkie-talkie — <the task>`**
    /// (Victor: *"Îmi plăcea foarte mult la terminal că am arătat titlul cu tot cu … ce a făcut cât de
    /// cât. Acum, în Orca îmi apare doar proiectul în care este"*). Orca names a tab by its custom
    /// title, else by a title it generates **once** from the first prompt — never by the title the
    /// program sets (Claude Code's `✳ folder — task`, kept current by the title hook). So Walkie
    /// copies the pane's own title onto its tab as the custom title, every `titleSyncEvery` while
    /// the switch is on, renaming only a tab whose name differs. The leading state glyph (✳, the
    /// braille spinner) is dropped: Orca draws its own busy/idle mark on the tab, and a glyph that
    /// spins would be a rename every tick. Only panes whose title has Claude Code's shape (a glyph,
    /// then `folder — task`) are touched; a shell tab keeps whatever Orca calls it. A tab renamed by
    /// hand in Orca is renamed back while a session runs in it.
    static let titleSyncEvery: TimeInterval = 10
    private static var titleTimer: DispatchSourceTimer?

    static func startTitleSync() {
        guard titleTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + titleSyncEvery, repeating: titleSyncEvery, leeway: .seconds(2))
        timer.setEventHandler { if enabled, app != nil { syncTabTitles() } }
        titleTimer = timer
        timer.resume()
    }

    /// `✳ walkie-talkie — Orca` → `walkie-talkie — Orca`; nil for a title not shaped like a session's.
    static func sessionTabTitle(_ paneTitle: String) -> String? {
        let t = paneTitle.trimmingCharacters(in: .whitespaces)
        guard let first = t.unicodeScalars.first, !CharacterSet.alphanumerics.contains(first),
              first != "~", first != "/", t.contains(" — ") else { return nil }
        let body = t.unicodeScalars.drop { !CharacterSet.alphanumerics.contains($0) && $0 != "~" }
        let text = String(String.UnicodeScalarView(body)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    static func syncTabTitles() {
        guard let list = call(["terminal", "list", "--include-visual-layouts", "--json"]),
              let rows = list["terminals"] as? [[String: Any]] else { return }
        var tabs: [[String: Any]] = []
        func collect(_ node: Any) {
            if let d = node as? [String: Any] {
                if d["tabId"] != nil, d["panes"] != nil { tabs.append(d) }
                for v in d.values { collect(v) }
            } else if let a = node as? [Any] { for v in a { collect(v) } }
        }
        collect(list["visualLayouts"] ?? [])
        var renamed = 0
        for tab in tabs {
            guard let tabID = tab["tabId"] as? String else { continue }
            let inTab = rows.filter { $0["tabId"] as? String == tabID }
            let pane = inTab.first { $0["leafId"] as? String == tab["activeLeafId"] as? String } ?? inTab.first
            guard let pane, let handle = pane["handle"] as? String,
                  let want = (pane["title"] as? String).flatMap(sessionTabTitle),
                  tab["title"] as? String != want else { continue }
            if call(["terminal", "rename", "--terminal", handle, "--title=" + want, "--json"]) != nil {
                renamed += 1
                Log.info("🐋 tab \(tabID.prefix(8)) named «\(want)» (was «\(tab["title"] as? String ?? "")»)")
            }
        }
        _ = renamed
    }

    // MARK: - Sessions under the spawn menu

    /// `ttysNNN` → title for every Orca pane — the Orca half of `TerminalBinding.liveTitles`.
    /// Empty while the switch is off.
    static func liveTitles() -> [String: String] {
        guard enabled else { return [:] }
        var map: [String: String] = [:]
        for pane in panes() {
            guard let tty = pane.tty else { continue }
            map[(tty as NSString).lastPathComponent] = pane.title ?? ""
        }
        return map
    }
}
