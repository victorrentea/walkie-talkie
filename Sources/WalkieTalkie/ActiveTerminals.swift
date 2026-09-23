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
    }

    /// One submenu row, already decided.
    struct Item: Equatable {
        let tty: String
        let name: String
        /// The terminal the relay is pointed at now — ticked, and still
        /// clickable: during a spawn, picking it takes the sentence back from the
        /// new session to the terminal it was already going to.
        let bound: Bool
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

        return sessions.indices
            .map { Item(tty: short(sessions[$0].tty), name: names[$0], bound: short(sessions[$0].tty) == bound) }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.tty < $1.tty : order == .orderedAscending
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
