import Foundation

/// **The spawn menu's first row: the agents already running, one hover away**
/// (Victor, 2026-09-23: *"In the project pop-up … when I open a new terminal, I
/// want the first option to be a menu that says 'Recent', or 'Active
/// Terminals', and then when I hover over it, a submenu opens that lets me bind
/// this prompt to that terminal."*).
///
/// A spawn says *the session I want does not exist yet*. Half the time, half a
/// sentence in, it turns out it does — and the way back used to be a second
/// gesture (the left-plus-wheel chord) aimed at a window that may be on another
/// monitor. This is the same answer given from where the hand already is.
///
/// **Found by looking, not remembered.** A row is a Terminal.app tab
/// (`TerminalBinding.liveTitles()`) on whose tty a process owns a fresh
/// `~/.claude/cwd/.last-<pid>` — the status line's per-session file, the same
/// test `frontClaudePromptTTY` and the chip's folder label already rely on. So a
/// session he never spoke to is offered too, which is the difference from the
/// *Rebind to…* log, and a closed window or a plain shell never is.
///
/// This file is the **pure half**: what the rows say, in which order, which one
/// is ticked. It touches no process and no disk, so `swift test` can hold it to
/// its word (`Tests/WalkieTalkieTests/ActiveTerminalsTests.swift`).
enum ActiveTerminals {

    /// The row that opens the submenu — always drawn, first in the menu.
    static let label = "Active Terminals"
    /// **The same row with nothing behind it: drawn, dimmed, not hidden.** A row
    /// that comes and goes moves every folder under it by a row's height between
    /// two openings, and the menu's whole promise is that the row he reached for
    /// last time is where he left it.
    static let emptyLabel = "Active Terminals — none"
    /// The submenu's one row while the answer is still coming (an `osascript`
    /// plus one `ps`, ~100 ms) — reached only by a hand faster than that.
    static let loadingLabel = "Looking…"

    /// One Claude Code session found in a Terminal.app tab.
    struct Session: Equatable {
        /// `ttys014` — short, as `liveTitles()` keys it.
        let tty: String
        /// The session directory Claude Code published — where the agent is
        /// **working**, which is what the chip's folder label shows too.
        let directory: String
        /// The tab's title as the agent last set it, if any.
        let title: String?
        /// **Working right now** — Claude Code's own `status: "busy"` in
        /// `~/.claude/sessions/<pid>.json`; drawn as a ⏳ in front of the row
        /// (2026-10-07, Victor: *"to have a hourglass in front of them if you
        /// detect that Claude session to be active right now"*).
        var busy: Bool = false
    }

    /// One submenu row, already decided.
    struct Item: Equatable {
        let tty: String
        let name: String
        /// The terminal the relay is pointed at now — ticked, and still
        /// clickable: during a spawn, picking it takes the sentence back from the
        /// new session to the terminal it was already going to.
        let bound: Bool
        var busy: Bool = false
    }

    /// **Sessions → rows.** The folder name alone when it is unique; when two
    /// sessions share a folder, each gets what tells them apart — the task the
    /// agent wrote into its tab title, else the tty — and a tty on top of that
    /// if the tasks read the same. Sorted by what is drawn, alphabetically, the
    /// menu's own rule (*"alfabetic"*), ties broken by tty so the order never
    /// depends on how Terminal happened to list its windows.
    static func items(_ sessions: [Session], boundTTY: String?) -> [Item] {
        let bound = boundTTY.map(short)
        let folders = sessions.map { folder(of: $0.directory) }
        var count: [String: Int] = [:]
        for f in folders { count[f, default: 0] += 1 }

        var names: [String] = []
        for (i, s) in sessions.enumerated() {
            let f = folders[i]
            guard count[f, default: 0] > 1 else { names.append(f); continue }
            if let t = task(fromTitle: s.title, folder: f) { names.append("\(f) — \(t)") }
            else { names.append("\(f) · \(short(s.tty))") }
        }
        // Two sessions in one folder whose titles also say the same thing.
        var seen: [String: Int] = [:]
        for n in names { seen[n, default: 0] += 1 }
        for i in names.indices where seen[names[i], default: 0] > 1 && !names[i].hasSuffix(short(sessions[i].tty)) {
            names[i] += " · \(short(sessions[i].tty))"
        }

        return rows(sessions, names: names, bound: bound)
    }

    private static func rows(_ sessions: [Session], names: [String], bound: String?) -> [Item] {
        sessions.indices
            .map { Item(tty: short(sessions[$0].tty), name: names[$0],
                        bound: short(sessions[$0].tty) == bound, busy: sessions[$0].busy) }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.tty < $1.tty : order == .orderedAscending
            }
    }

    // MARK: - Under the folder rows (2026-10-07)

    /// **Each session goes under the folder row it is working in; the rest stay
    /// under *Active Terminals*.** Victor, 2026-10-07: *"to have the active
    /// session grouped under [the projects] … And the remaining terminals that
    /// are not bound to any, should stay in the first, other active
    /// terminals."* A session belongs to a row when its directory is the row's
    /// folder or inside it (`petclinic/petclinic-backend` → `petclinic`, the
    /// rollup `recent_projects.py` makes); with two rows nested, the deeper one
    /// wins. Keys are the rows' paths as given.
    static func grouped(_ sessions: [Session], under folders: [String])
        -> (byFolder: [String: [Session]], rest: [Session]) {
        var byFolder: [String: [Session]] = [:], rest: [Session] = []
        for s in sessions {
            let dir = trimmed(s.directory)
            let owner = folders
                .filter { let f = trimmed($0); return dir == f || dir.hasPrefix(f + "/") }
                .max { trimmed($0).count < trimmed($1).count }
            if let owner { byFolder[owner, default: []].append(s) } else { rest.append(s) }
        }
        return (byFolder, rest)
    }

    /// **The rows of one folder's submenu.** The folder is already the parent
    /// row, so what is left to say is the task the agent wrote into its tab
    /// title — else the subfolder it works in, else the folder itself — and a
    /// tty on top when two rows would still read the same.
    static func folderItems(_ sessions: [Session], folder: String, boundTTY: String?) -> [Item] {
        let root = trimmed(folder)
        var names = sessions.map { s -> String in
            let dir = trimmed(s.directory)
            if let t = task(fromTitle: s.title, folder: self.folder(of: dir)) { return t }
            if dir.hasPrefix(root + "/") { return String(dir.dropFirst(root.count + 1)) }
            return self.folder(of: root)
        }
        var seen: [String: Int] = [:]
        for n in names { seen[n, default: 0] += 1 }
        for i in names.indices where seen[names[i], default: 0] > 1 { names[i] += " · \(short(sessions[i].tty))" }
        return rows(sessions, names: names, bound: boundTTY.map(short))
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// **A prompt that told its session to close when done** — the line
    /// `kamikaze` on its own, which is how 🔼 ↓ ends a prompt (`\n\nkamikaze`)
    /// and how the word goes alone after one (`AppDelegate.sendKamikaze`). Such
    /// a session is on its way out and is not offered (2026-10-07, *"only if
    /// you've never sent Kamikaze to that session yet"*). The word inside a
    /// sentence is not the gesture.
    static func isKamikaze(prompt: String) -> Bool {
        prompt.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "kamikaze"
        }
    }

    /// **The task out of a Claude Code tab title**, or nil when it carries none.
    ///
    /// Titles look like `✳ petclinic — Spring Security upgrade changes`,
    /// `◑ Message body toggle in UI zone` (a spinner glyph while it works) or
    /// just `✳ human-review`. The leading status glyph goes, then the folder the
    /// row already prints, and whatever is left is the part that tells two
    /// sessions in one folder apart. Only the folder itself left is no task.
    static func task(fromTitle title: String?, folder: String) -> String? {
        guard var t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        while let c = t.unicodeScalars.first, !CharacterSet.alphanumerics.contains(c) {
            t = String(t.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        for dash in [" — ", " – ", " - "] where t.hasPrefix(folder + dash) {
            t = String(t.dropFirst(folder.count + dash.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard !t.isEmpty, t != folder else { return nil }
        return t
    }

    private static func folder(of directory: String) -> String {
        let name = (directory as NSString).lastPathComponent
        return name.isEmpty ? directory : name
    }

    /// `/dev/ttys014` and `ttys014` are the same terminal.
    static func short(_ tty: String) -> String { (tty as NSString).lastPathComponent }
}
