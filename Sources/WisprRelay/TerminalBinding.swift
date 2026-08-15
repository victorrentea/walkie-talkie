import AppKit

/// The terminal a dictation is typed into, once Victor has pointed the relay at
/// one — and the machinery that puts the words there.
///
/// **Why this exists.** Without it, attaching a session costs a trip into the
/// terminal to type `/relay`, an agent turn to arm a watcher on `outbox.jsonl`,
/// and a label filter that has to match. That is three things to get right
/// before the first word, in a workflow whose entire premise is that Victor is
/// away from the keyboard. Bound, the same dictation is typed straight into the
/// session he was looking at when he pressed the key, and the outbox goes back
/// to being what it always was underneath: the log.
///
/// **The binding is a handle, never a window.** Windows get reordered, tabs get
/// dragged between them, Spaces move underneath all of it — a reference to the
/// front window at bind time is stale by the second dictation. Every case of
/// `Handle` is instead something the terminal itself can be asked to resolve:
/// a tty, a tmux pane id, a process id. Delivery re-finds the target every
/// time, and says so plainly when it cannot.
///
/// **Nothing here steals focus except the fallback that has no choice.**
/// `do script … in <tab>` writes into a Terminal.app tab that is behind other
/// windows, on another Space, or minimised, without activating anything —
/// verified against a raw-mode reader, which is the shape a TUI actually has.
/// tmux `send-keys` is the same story one level down. Only `.keystroke` has to
/// bring the app forward, and it puts the focus back afterwards.
final class TerminalBinding {

    /// How the bound terminal is addressed at delivery time.
    enum Handle: Equatable {
        /// A Terminal.app tab, found by the tty it is showing. The tty survives
        /// tab reordering, being dragged into another window, and everything
        /// else Victor might do to the window between binding and speaking —
        /// which a tab index or a window id does not.
        case terminalApp(tty: String)

        /// A tmux pane, by its `%id`. Bound in preference to the tty whenever
        /// the tty turns out to be running tmux, because a tty binding there is
        /// quietly wrong: tmux hands the input to whichever pane is *active*
        /// when it arrives, so splitting the window after binding sends the
        /// next sentence somewhere Victor never pointed at.
        case tmux(pane: String, tty: String)

        /// Anything with no scripting surface — VS Code's integrated terminal,
        /// IntelliJ's, a terminal emulator nobody has taught this app about.
        /// Addressed by process id and driven with a paste and a Return.
        case keystroke(pid: pid_t, app: String)
    }

    struct Target {
        let handle: Handle
        /// `petclinic@main` when a Claude Code was found on the bound tty and
        /// its working directory is a git repo — the same `folder@branch` the
        /// status line shows. Falls back to the app's own name.
        let label: String
        /// The address, spelled out: `ttys004`, `%3`, `IntelliJ IDEA`. Two
        /// sessions in one repo produce the same label and nothing else tells
        /// them apart.
        let address: String
        /// **What the terminal is currently calling itself** — the title the
        /// agent sets and keeps updating as it works (`✳ fixing the tax bug`),
        /// read from Terminal.app's `custom title` or tmux's `pane_title`.
        ///
        /// `folder@branch` says which *repo* the words are going to, and with
        /// two sessions open on the same branch that is not an answer. The title
        /// is the only thing that distinguishes them, and unlike everything else
        /// in the binding it moves — which is exactly why it is worth showing:
        /// a title that is still changing is a session that is still working.
        var title: String?
        let boundAt: Date

        /// Whether delivery to this target can be checked before it happens.
        /// `.keystroke` cannot — see `foregroundIsShell`.
        var isGuarded: Bool {
            if case .keystroke = handle { return false }
            return true
        }
    }

    /// What a delivery did, for the flash that reports it.
    enum Outcome {
        case delivered
        case noTarget
        /// The tab, pane or process is gone. The binding is dropped: a target
        /// that cannot be found again will not come back, and a stale one is
        /// worse than none — it makes every later dictation look delivered.
        case targetGone(String)
        /// The foreground process is a shell, so the words would have been
        /// **executed** rather than typed at an agent. Nothing is sent.
        case wouldRunAsShell(String)
        case failed(String)
    }

    private var current: Target?
    private let lock = NSLock()

    var target: Target? {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    // MARK: - Binding

    /// Bind the terminal Victor is looking at.
    ///
    /// The app is passed in rather than read here because this runs on the
    /// listener queue, several `osascript` and `ps` subprocesses deep, while
    /// "which app is in front" is a main-thread question whose answer has to be
    /// taken at the keypress — before any of that work has had a chance to move
    /// the focus.
    @discardableResult
    func bind(app: NSRunningApplication) -> Target? {
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? bundleID

        let bound: Target?
        if bundleID == "com.apple.Terminal" {
            bound = bindTerminalApp(fallbackName: name)
        } else {
            // No scripting surface worth the name: VS Code and IntelliJ both
            // host their terminal inside a window nothing outside can address —
            // and with it goes any way to read what that terminal is calling
            // itself, so these targets carry no title.
            bound = Target(handle: .keystroke(pid: app.processIdentifier, app: name),
                           label: name, address: name, title: nil, boundAt: Date())
        }

        guard let bound = bound else { return nil }
        lock.lock(); current = bound; lock.unlock()
        Log.info("🎯 bound to \(bound.label) (\(bound.address))")
        return bound
    }

    /// Terminal.app: ask it for the tty of the tab in front, then find out what
    /// is actually running there.
    private func bindTerminalApp(fallbackName: String) -> Target? {
        guard let front = Self.frontTerminalTab() else {
            Log.error("bind: Terminal.app would not name its front tab's tty")
            return nil
        }
        let tty = front.tty

        // tmux first: the tty is the *client's*, and everything typed at it goes
        // to whichever pane happens to be active. Pinning the pane at bind time
        // is the only way the binding means what Victor pointed at.
        if let pane = Self.tmuxPane(clientTTY: tty) {
            let label = Self.tmuxPaneLabel(pane) ?? fallbackName
            return Target(handle: .tmux(pane: pane, tty: tty), label: label,
                          address: pane, title: Self.tmuxPaneTitle(pane), boundAt: Date())
        }

        let short = (tty as NSString).lastPathComponent
        let label = Self.sessionLabel(onTTY: tty) ?? fallbackName
        return Target(handle: .terminalApp(tty: tty), label: label,
                      address: short, title: front.title, boundAt: Date())
    }

    /// Re-read what the bound terminal is calling itself.
    ///
    /// The title is the one part of a binding that legitimately changes while
    /// nothing else about it does — the agent rewrites it as it moves between
    /// tasks — so it is the one part worth polling. Returns the updated target
    /// only when the title actually moved, so a caller can skip a relayout it
    /// does not need.
    func refreshTitle() -> Target? {
        guard let existing = target else { return nil }
        let fresh: String?
        switch existing.handle {
        case .terminalApp(let tty): fresh = Self.title(forTTY: tty)
        case .tmux(let pane, _): fresh = Self.tmuxPaneTitle(pane)
        case .keystroke: return nil          // nothing to ask
        }
        guard fresh != existing.title else { return nil }

        lock.lock()
        // Another bind may have landed while the subprocesses above were running.
        guard current?.handle == existing.handle else { lock.unlock(); return nil }
        current?.title = fresh
        let updated = current
        lock.unlock()
        return updated
    }

    func unbind() {
        lock.lock()
        let had = current
        current = nil
        lock.unlock()
        if let had = had { Log.info("🎯 unbound from \(had.label) (\(had.address))") }
    }

    // MARK: - Delivery

    /// Type one dictation into the bound terminal and press Return.
    ///
    /// **The shell guard is the load-bearing part of this method.** If the
    /// foreground process on the target is a shell, the dictation is not typed
    /// at an agent — it is *run*. "Șterge tot ce e în folderul de build" said
    /// out loud becomes a real `rm` against a real directory. So the check runs
    /// on **every delivery**, not once at bind: Victor hits Escape, quits, or
    /// the session crashes, and the tab goes back to being a prompt with the
    /// binding still pointing at it. It fails **closed** — a target we cannot
    /// interrogate is treated as a shell.
    func deliver(_ text: String) -> Outcome {
        guard let target = target else { return .noTarget }
        let line = Self.singleLine(text)
        guard !line.isEmpty else { return .failed("nothing to send") }

        switch target.handle {
        case .terminalApp(let tty):
            let foreground = Self.foregroundCommand(onTTY: tty)
            Log.info("⌨️ \(target.address) foreground=\(foreground ?? "nothing") — \(line.count) chars")
            switch foreground {
            case .none:
                unbind()
                return .targetGone("\(target.address) is gone")
            case .some(let command) where Self.isShell(command):
                return .wouldRunAsShell(command)
            case .some:
                break
            }
            guard Self.writeToTerminalApp(line, tty: tty) else {
                unbind()
                return .targetGone("no Terminal.app tab on \(target.address)")
            }
            return .delivered

        case .tmux(let pane, _):
            switch Self.tmuxPaneCommand(pane) {
            case .none:
                unbind()
                return .targetGone("tmux pane \(pane) is gone")
            case .some(let command) where Self.isShell(command):
                return .wouldRunAsShell(command)
            case .some:
                break
            }
            guard Self.writeToTmux(line, pane: pane) else {
                return .failed("tmux send-keys failed")
            }
            return .delivered

        case .keystroke(let pid, let app):
            guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
                unbind()
                return .targetGone("\(app) is gone")
            }
            // No guard is possible here and none is pretended: nothing outside
            // VS Code or IntelliJ can say which pane inside them owns the caret,
            // let alone what is running in it. The overlay marks these targets
            // differently for exactly that reason.
            return Self.paste(line, into: running) ? .delivered : .failed("paste into \(app) failed")
        }
    }

    // MARK: - Terminal.app

    /// The tty and title of the frontmost Terminal.app tab.
    ///
    /// Both in one round trip: they are read at the same instant for the same
    /// tab, and asking twice leaves room for the answer to be about two
    /// different tabs. The title comes from `custom title`, which is where
    /// Terminal.app files what a program sets with the OSC escape — i.e. exactly
    /// what an agent writes there while it works.
    private static func frontTerminalTab() -> (tty: String, title: String?)? {
        let script = """
        tell application "Terminal"
            if (count of windows) is 0 then return ""
            set t to selected tab of front window
            set theTitle to ""
            try
                set theTitle to custom title of t
            end try
            return (tty of t) & "\t" & theTitle
        end tell
        """
        guard let out = osascript(script) else { return nil }
        let parts = out.components(separatedBy: "\t")
        guard let tty = parts.first, tty.hasPrefix("/dev/") else { return nil }
        return (tty, clean(parts.count > 1 ? parts[1] : nil))
    }

    /// The title of whichever tab is showing this tty — the refresh counterpart
    /// of `frontTerminalTab`, which cannot be reused because by then the tab is
    /// very often not the one in front.
    private static func title(forTTY tty: String) -> String? {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(escape(tty))" then return custom title of t
                    end try
                end repeat
            end repeat
            return ""
        end tell
        """
        return clean(osascript(script))
    }

    /// An empty or whitespace-only title is not a title, and it must not push a
    /// bare separator onto the chip.
    private static func clean(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// `do script … in <that tab>` — which, despite the name, types the string
    /// into the tab and presses Return rather than starting anything. That is
    /// exactly the gesture wanted here, and it reaches a tab that is not in
    /// front, not on this Space, and not in the active window.
    private static func writeToTerminalApp(_ text: String, tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(escape(tty))" then
                            do script "\(escape(text))" in t
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
            return "gone"
        end tell
        """
        return osascript(script) == "ok"
    }

    // MARK: - tmux

    /// The pane a tmux client on this tty is looking at — or nil, which is the
    /// answer for every ordinary terminal tab.
    ///
    /// **`display-message -c` is asked only after the tty is known to be a
    /// client, because on its own it does not refuse.** Handed a tty attached to
    /// nothing it silently falls back to tmux's own current client and answers
    /// with *that* pane, so a plain Terminal tab binds to whichever pane some
    /// unrelated background session happens to have focused — which is exactly
    /// what happened the first time this ran on a Mac with a detached `claude-rc`
    /// session alive. A wrong pane is the worst possible failure here: it is
    /// indistinguishable from a correct bind until a sentence lands in somebody
    /// else's window.
    private static func tmuxPane(clientTTY tty: String) -> String? {
        guard let clients = tmux(["list-clients", "-F", "#{client_tty}"]) else { return nil }
        let attached = clients.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard attached.contains(tty) else { return nil }

        guard let out = tmux(["display-message", "-p", "-c", tty, "#{pane_id}"]),
              out.hasPrefix("%") else { return nil }
        return out
    }

    private static func tmuxPaneCommand(_ pane: String) -> String? {
        guard let out = tmux(["display-message", "-p", "-t", pane, "#{pane_current_command}"]),
              !out.isEmpty else { return nil }
        return out
    }

    /// tmux's own record of what the pane called itself — the same OSC title,
    /// caught one layer down.
    private static func tmuxPaneTitle(_ pane: String) -> String? {
        clean(tmux(["display-message", "-p", "-t", pane, "#{pane_title}"]))
    }

    private static func tmuxPaneLabel(_ pane: String) -> String? {
        guard let dir = tmux(["display-message", "-p", "-t", pane, "#{pane_current_path}"]),
              !dir.isEmpty else { return nil }
        return label(forDirectory: dir)
    }

    /// `-l` sends the text **literally**, so a dictation containing the word
    /// "Enter" or a `;` cannot turn into a key name or a command separator.
    /// The Return is a second call for the same reason.
    private static func writeToTmux(_ text: String, pane: String) -> Bool {
        guard tmux(["send-keys", "-t", pane, "-l", "--", text]) != nil else { return false }
        return tmux(["send-keys", "-t", pane, "Enter"]) != nil
    }

    private static func tmux(_ args: [String]) -> String? {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return run(path, args)
        }
        return nil
    }

    // MARK: - The fallback: clipboard, ⌘V, Return

    /// Bring the app forward, paste, submit, and put the focus back.
    ///
    /// Every part of this is a compromise the other two paths do not have to
    /// make, and it exists only because VS Code and IntelliJ host their
    /// terminals inside windows nothing outside the app can address. The focus
    /// does move — for about a fifth of a second — which is survivable because
    /// by the time this runs Wispr has long finished pasting its transcript
    /// wherever it was going to.
    ///
    /// The clipboard is restored, because the relay must not cost Victor
    /// whatever he was carrying on it.
    private static func paste(_ text: String, into app: NSRunningApplication) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let previous = NSWorkspace.shared.frontmostApplication
        guard app.activate(options: []) else { return false }

        // Activation is asynchronous and a paste into the app that *was* in
        // front is the one outcome worth spending 200ms to avoid.
        var waited = 0
        while !app.isActive && waited < 40 { usleep(5_000); waited += 1 }
        guard app.isActive else {
            if let saved = saved { restore(saved, to: pasteboard) }
            return false
        }

        tap(key: 0x09, command: true)     // ⌘V
        usleep(60_000)
        tap(key: 0x24, command: false)    // Return
        usleep(80_000)

        // Back where he was, so the relay is not also a window manager.
        if previous?.processIdentifier != app.processIdentifier { previous?.activate(options: []) }
        if let saved = saved {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { restore(saved, to: pasteboard) }
        }
        return true
    }

    private static func restore(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func tap(key: CGKeyCode, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        if command {
            down?.flags = .maskCommand
            up?.flags = .maskCommand
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - What is running there

    /// The command in the tty's **foreground** process group — the one that
    /// would receive what we type. BSD `ps` marks it with `+` in `STAT`.
    ///
    /// Returns nil when the tty has no processes left at all, which is how a
    /// closed tab announces itself.
    private static func foregroundCommand(onTTY tty: String) -> String? {
        let device = (tty as NSString).lastPathComponent
        guard let out = run("/bin/ps", ["-t", device, "-o", "stat=,comm="]), !out.isEmpty else { return nil }
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0].contains("+") else { continue }
            return (String(parts[1]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        }
        return nil
    }

    /// Would typing here run a command rather than talk to a program?
    ///
    /// Deliberately a **shell** test and not a "is this Claude Code" test. What
    /// makes a delivery dangerous is precisely and only that a shell is reading
    /// the line; everything else — `claude`, `node`, an editor, a REPL — merely
    /// receives text on stdin, which is the intended behaviour and is not the
    /// relay's business to police. Naming the agent instead would also have to
    /// guess how it appears in `ps`, and guess again on every release.
    private static func isShell(_ command: String) -> Bool {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "fish", "csh", "tcsh", "-zsh", "-bash", "login"]
        return shells.contains(command) || shells.contains(command.replacingOccurrences(of: "-", with: ""))
    }

    /// `folder@branch` for whatever Claude Code is running on this tty, taken
    /// from its working directory — the same answer `SessionLabel` derives for
    /// the relay's own, and the reason the chip can finally name the session it
    /// is about to talk to rather than the one it was launched from.
    private static func sessionLabel(onTTY tty: String) -> String? {
        let device = (tty as NSString).lastPathComponent
        guard let out = run("/bin/ps", ["-t", device, "-o", "pid=,stat="]) else { return nil }
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts[1].contains("+"), let pid = Int32(parts[0]) else { continue }
            guard let dir = workingDirectory(ofPID: pid) else { return nil }
            return label(forDirectory: dir)
        }
        return nil
    }

    /// `lsof -p <pid> -a -d cwd` is the only way to read another process's
    /// working directory without being it.
    private static func workingDirectory(ofPID pid: Int32) -> String? {
        guard let out = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]) else { return nil }
        for line in out.components(separatedBy: "\n") where line.hasPrefix("n/") {
            return String(line.dropFirst())
        }
        return nil
    }

    private static func label(forDirectory dir: String) -> String {
        let folder = (dir as NSString).lastPathComponent
        guard let branch = run("/usr/bin/git", ["-C", dir, "rev-parse", "--abbrev-ref", "HEAD"]),
              !branch.isEmpty, branch != "HEAD" else { return folder }
        return "\(folder)@\(branch)"
    }

    // MARK: - Text

    /// **One line, always.** Whatever carries this to the terminal ends with a
    /// Return, so an embedded newline is not formatting — it is an early submit
    /// that cuts the sentence in half and sends the rest as a second prompt.
    /// Tabs go for a related reason: in a TUI they are a completion key.
    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// AppleScript string literals understand exactly two escapes, and a
    /// dictation is arbitrary text: without this a spoken quotation mark ends
    /// the string and the rest of the sentence is parsed as code.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Subprocesses

    private static func osascript(_ script: String) -> String? {
        run("/usr/bin/osascript", ["-e", script])
    }

    /// Trimmed stdout, or nil on a non-zero exit — so every caller can treat
    /// "it failed" and "it said nothing" as the same thing, which for all of
    /// them it is.
    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.error("\(path) would not run: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
