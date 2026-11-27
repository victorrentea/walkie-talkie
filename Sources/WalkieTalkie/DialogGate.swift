import Foundation

/// **Never type into an open dialog** (2026-11-25) — the decisions of that rule as
/// pure functions and two file reads, so they are tested without an app
/// (`DialogGateTests`).
///
/// Measured that night in a tmux lab (Claude Code 2.1.332, Haiku): a sentence typed
/// into a session that shows a dialog — a Bash or Write permission, the plan's
/// *Would you like to proceed?*, an AskUserQuestion — is **dropped**, and the chunk's
/// own `\r` or the bare Return 0.5 s later **picks option 1**. Three real cases in
/// relay.log: 2026-10-07 (an AUQ answered *Both (Recommended)*), 10-22 (a wiki
/// published on *Away from it*) and 11-23 (a **public repo created and pushed** on
/// option 1 — *"ce nume pun pe repo-ul public nou"*); each time the sentence was lost.
///
/// Two readings, both before **every** keystroke script (the text, the Return 0.5 s
/// later, every watched Return, ⌃X ⌃S):
///
/// 1. **The `walkie-inbox` mod's flag** — `inbox/<tty>/.dialog`, written at
///    `classic.PermissionRequest` / `classic.Elicitation`, *before* the dialog is
///    drawn, deleted the moment `$.prompt.fill` is no longer refused for a dialog.
///    Trusted only beside a fresh `.alive` beat (a crashed session leaves it behind).
///    One `stat`, any target with a tty.
/// 2. **The screen** (Terminal.app, inside the very AppleScript that would type or
///    press — no extra `osascript`; Orca on the reads it already makes): after the
///    last `❯` a dialog starts with its highlighted option (`❯ 1. Yes`) or carries
///    its footer (`Esc to cancel`, `Enter to select`, `Enter to confirm`). Catches
///    what the mod cannot: no mod, an older one, a dialog that is not a permission
///    (the usage-limit menu).
///
/// Either says *open* → nothing is sent; the sentence waits on the delivery queue
/// (`TerminalBinding.holdingForDialogs`) and goes by itself when both clear, or after
/// `holdLimit` is kept undelivered (Prompt History, clipboard).
enum DialogGate {

    // MARK: The mod's flag

    /// `~/.walkie-talkie/inbox` — the folder the mod's `.alive` and `.dialog` sit in,
    /// one subfolder per tty. Tests point it elsewhere.
    static var root = Outbox.defaultHome.appendingPathComponent("inbox")

    /// The mod beats every 2 s; 10 s of silence is a session gone or a mod stopped
    /// (`AgentRules.claudeBeat` reads the same file with the same bound).
    static let beatFresh: TimeInterval = 10

    /// **Whether the flag counts** — it exists, and the session's beat is fresh.
    /// `beatAt` and `now` in epoch milliseconds (the mod's `$.clock.now()`).
    static func flagCounts(flagExists: Bool, beatAt: Double?, now: Double) -> Bool {
        guard flagExists, let beatAt else { return false }
        return abs(now - beatAt) < beatFresh * 1000
    }

    /// The beat's `at` and its `dialog` capability (nil: an older mod, no flags).
    static func beat(tty: String) -> (at: Double, dialog: Int?)? {
        let url = folder(tty).appendingPathComponent(".alive")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let at = (obj["at"] as? NSNumber)?.doubleValue else { return nil }
        return (at, (obj["dialog"] as? NSNumber)?.intValue)
    }

    /// **A dialog holds the keys of the session on `tty`**, by the mod's flag.
    /// An `.alive` caught half-written (the mod rewrites it in place) is read by its
    /// mtime instead (the Fable review, L1): unparsable must not mean *no flag*.
    static func flagUp(tty: String, now: Date = Date()) -> Bool {
        let flag = folder(tty).appendingPathComponent(".dialog")
        guard FileManager.default.fileExists(atPath: flag.path) else { return false }
        return beatFresh(tty: tty, now: now)
    }

    /// The session's beat is fresh (parsed, or by the file's mtime when caught half-written).
    static func beatFresh(tty: String, now: Date = Date()) -> Bool {
        let ms = now.timeIntervalSince1970 * 1000
        if let at = beat(tty: tty)?.at { return flagCounts(flagExists: true, beatAt: at, now: ms) }
        let alive = folder(tty).appendingPathComponent(".alive")
        let touched = (try? FileManager.default.attributesOfItem(atPath: alive.path))?[.modificationDate] as? Date
        return flagCounts(flagExists: true, beatAt: touched.map { $0.timeIntervalSince1970 * 1000 }, now: ms)
    }

    /// The flag's path, for the in-script test (`appleScript`'s `flagged`), and what it says.
    static func flagPath(tty: String) -> String { folder(tty).appendingPathComponent(".dialog").path }
    static func flagText(tty: String) -> String? { try? String(contentsOfFile: flagPath(tty: tty), encoding: .utf8) }

    /// The tool whose dialog the flag stands for (`{"tool": "AskUserQuestion", …}`;
    /// `mcp:<server>` for an elicitation), nil when unreadable.
    static func flaggedTool(_ text: String?) -> String? {
        guard let data = text?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["tool"] as? String
    }

    /// **A paste lands in this dialog's own text field** (2026-11-27, measured on 2.1.332
    /// in a tmux lab): a bracketed paste into an AskUserQuestion jumps to its `Type
    /// something.` row and fills it — option 1 highlighted, `❯ 3. green with a hint of
    /// teal` a beat later — and the Return then submits those words as the answer. Into
    /// a Bash permission the same paste is **dropped**, `❯ 1. Yes` stays, and a Return
    /// would approve. So only AskUserQuestion; every other dialog, and an unreadable
    /// flag, still holds the Return.
    static func pasteFillsDialog(flagText: String?) -> Bool {
        flaggedTool(flagText) == "AskUserQuestion"
    }

    // MARK: One tab at a time, and a give-up that sticks

    private static let books = NSLock()
    private static var locks: [String: NSRecursiveLock] = [:]
    private static var givenUp: [String: (flag: String?, at: Date)] = [:]

    /// The lock that keeps one sentence at a time typing into this tab (`holdingForDialogs`).
    static func lock(_ short: String) -> NSRecursiveLock? {
        guard !short.isEmpty else { return nil }
        books.lock(); defer { books.unlock() }
        if let l = locks[short] { return l }
        let l = NSRecursiveLock()
        locks[short] = l
        return l
    }

    /// A sentence for this tab just gave up: remember which dialog it waited for.
    static func noteGiveUp(tty: String) {
        let short = (tty as NSString).lastPathComponent
        let flag = flagUp(tty: tty) ? flagText(tty: tty) : nil
        books.lock(); givenUp[short] = (flag, Date()); books.unlock()
    }

    static func forgetGiveUp(tty: String) {
        let short = (tty as NSString).lastPathComponent
        books.lock(); givenUp[short] = nil; books.unlock()
    }

    /// **The dialog an earlier sentence gave up on still stands** — the same flag (its
    /// text names the tool and the instant it was raised), or, seen on the screen alone,
    /// a give-up less than `limit` ago.
    static func stillGivenUp(tty: String, limit: TimeInterval, now: Date = Date()) -> Bool {
        let short = (tty as NSString).lastPathComponent
        books.lock(); let record = givenUp[short]; books.unlock()
        guard let record else { return false }
        if let flag = record.flag { return flagUp(tty: tty, now: now) && flagText(tty: tty) == flag }
        return now.timeIntervalSince(record.at) < limit
    }

    /// The session's mod flags its dialogs (a fresh beat saying `dialog: 1`+) —
    /// logged beside a hold, so a screen-only catch is told from a flagged one.
    static func modFlags(tty: String, now: Date = Date()) -> Bool {
        guard let b = beat(tty: tty), (b.dialog ?? 0) >= 1 else { return false }
        return flagCounts(flagExists: true, beatAt: b.at, now: now.timeIntervalSince1970 * 1000)
    }

    private static func folder(_ tty: String) -> URL {
        root.appendingPathComponent((tty as NSString).lastPathComponent)
    }

    // MARK: The screen

    /// Removed before matching, on both sides — exactly the set the AppleScript
    /// twin removes, so the two answer alike (`DialogGateTests` runs both).
    static func squash(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { !" \t\n\r\u{A0}".unicodeScalars.contains($0) }))
    }

    /// The footers of Claude Code's dialogs, squashed: permission (`Esc to cancel ·
    /// Tab to amend`), AskUserQuestion (`Enter to select · ↑/↓ to navigate · Esc to
    /// cancel`), folder trust (`Enter to confirm · Esc to cancel`). **Not the bare `Esc to
    /// cancel`** (the Fable review, M3): 2.1.332 also draws `Continuing automatically
    /// {when} · Esc to cancel` while a session waits out its usage limit
    /// (`cli_wait_footer`), likely under the box — every sentence would be held. The
    /// numbered option catches permission, plan and AskUserQuestion anyway. **Not `ctrl+g to
    /// edit`**: the plan dialog shows it, but so does the ordinary prompt — Claude Code
    /// 2.1.332 draws `ctrl+g to edit in <editor>` as a 5 s hint under the box
    /// (`external-editor-hint`), right after a long sentence is typed; the plan dialog
    /// is caught by its `❯ 1. Yes, and use auto mode` anyway.
    static let footers = ["Tabtoamend", "Entertoselect", "Entertoconfirm"]

    /// The squashed opening of the sentence — its first line's first 20 characters,
    /// as `TerminalBinding.submitted` reads it.
    static func opening(_ sent: String) -> String {
        let first = sent.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? sent
        return String(squash(first).prefix(20))
    }

    /// **Does this read of the tab show a dialog?** What follows the last `❯`: a
    /// dialog's highlighted row is `❯ 1. Yes` (`❯ 2. Blue` once moved), so the box
    /// starts with a numbered option; or it carries a dialog's footer. Text that
    /// *quotes* `❯ 1. Yes` sits above the input box, never after its `❯`. The box
    /// starting with the sentence's own opening is the sentence, not a dialog (a
    /// dictated `1. …` list, or one that says *Esc to cancel*) — `sent` is nil before
    /// the text is typed. A draft of his own that starts `1.` holds the sentence: the
    /// safe direction.
    static func screenShowsDialog(tail: String, sent: String? = nil) -> Bool {
        guard let mark = tail.range(of: "❯", options: .backwards) else { return false }
        let box = squash(String(tail[mark.upperBound...]))
        // A footer is a dialog whatever the box starts with (L3: a dictated `1.` is a
        // prefix of `1.Yes…`).
        if footers.contains(where: { box.range(of: $0, options: .caseInsensitive) != nil }) { return true }
        if let sent {
            let open = opening(sent)
            if !open.isEmpty, box.lowercased().hasPrefix(open.lowercased()) { return false }
        }
        let head = Array(box.prefix(3))
        guard let first = head.first, first.isASCII, first.isNumber else { return false }
        if head.count > 1, head[1] == "." { return true }
        return head.count > 2 && head[1].isASCII && head[1].isNumber && head[2] == "."
    }

    /// **The same reading in AppleScript**, for the Terminal.app scripts: they read
    /// the tab and decide before they type or press, in one `osascript` (a separate
    /// read would cost ~0.35 s a sentence). `my dialogShown(c, "<opening>")`; the
    /// opening squashed and escaped by the caller, `""` before the text is typed.
    /// `my flagged("<path>")` tests the mod's flag file inside the script, right before
    /// the keystroke (L2: the `stat` before the launch is ~0.3 s earlier); the caller
    /// passes the path only while the session's beat is fresh, so a crashed session's
    /// leftover cannot hold anything.
    /// AppleScript's `contains` / `starts with` ignore case, like the Swift twin.
    static let appleScript = """
    on dialogShown(c, opening)
        set AppleScript's text item delimiters to "❯"
        set parts to text items of c
        set AppleScript's text item delimiters to ""
        if (count parts) < 2 then return false
        set box to item -1 of parts
        set AppleScript's text item delimiters to {space, tab, linefeed, return, character id 160}
        set bits to text items of box
        set AppleScript's text item delimiters to ""
        set box to bits as text
        if box contains "Tabtoamend" or box contains "Entertoselect" or box contains "Entertoconfirm" then return true
        if opening is not "" and box starts with opening then return false
        if (count box) < 2 then return false
        set digits to "0123456789"
        if digits does not contain (character 1 of box) then return false
        if character 2 of box is "." then return true
        if (count box) > 2 and digits contains (character 2 of box) and character 3 of box is "." then return true
        return false
    end dialogShown

    on flagged(p)
        if p is "" then return false
        try
            (POSIX file p) as alias
            return true
        end try
        return false
    end flagged
    """

    // MARK: The hold

    /// How often a held sentence looks at the flag (the mod clears it within 150 ms
    /// of the close), and at the screen when only the screen saw the dialog (an
    /// `osascript` is ~0.35 s; once a second is plenty for a person answering).
    static let flagPoll: TimeInterval = 0.15
    static let screenPoll: TimeInterval = 1

    /// **Five minutes, then kept undelivered.** He answers a question he sees within
    /// a minute or two; one he never saw (11-23: he thought the repo was already
    /// made) must not swallow the sentence for ever, nor stand in front of every
    /// later delivery on the queue.
    static let holdLimit: TimeInterval = 300

    /// The flash when a sentence starts waiting. English, short (a flash is ~60
    /// characters).
    static let held = "⏸ A question is open — answer it first"
    /// `BoundPromptGate.undelivered`'s `lost` after `holdLimit`.
    static let gaveUp = "Question still open"
    /// A caret prompt kept out by a question: it has no outbox row, only the clipboard.
    static let gaveUpCaret = "⚠️ A question is open — the prompt is on ⌘V"

    enum Wait: Equatable { case clear, gaveUp }

    /// Blocks while the flag stands, looking every `flagPoll`, until `deadline`.
    /// Off the main thread (the delivery queue).
    static func waitWhileFlagged(tty: String, until deadline: Date,
                                 poll: TimeInterval = flagPoll) -> Wait {
        while flagUp(tty: tty) {
            if Date() >= deadline { return .gaveUp }
            Thread.sleep(forTimeInterval: poll)
        }
        return .clear
    }
}
