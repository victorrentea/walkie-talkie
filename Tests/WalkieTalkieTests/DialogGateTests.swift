import XCTest
@testable import WalkieTalkie

/// **Never type into an open dialog** (2026-11-25): the mod's flag (trusted only beside a
/// fresh beat), the screen reading in Swift and in its AppleScript twin, and the hold that
/// waits for the flag and lets the sentence go when it clears.
final class DialogGateTests: XCTestCase {

    private var dir: URL!
    private let tty = "ttys901"
    private var savedRoot: URL!

    override func setUp() {
        super.setUp()
        savedRoot = DialogGate.root
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dialog-gate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(tty), withIntermediateDirectories: true)
        DialogGate.root = dir
        DialogGate.forgetGiveUp(tty: tty)
    }

    override func tearDown() {
        DialogGate.root = savedRoot
        TerminalBinding.onDialogHold = nil
        DialogGate.forgetGiveUp(tty: tty)
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func beat(ageSeconds: Double = 0, dialog: Int? = 1) {
        var obj: [String: Any] = ["pid": 1, "session": "s", "at": (Date().timeIntervalSince1970 - ageSeconds) * 1000, "rules": 3]
        if let dialog { obj["dialog"] = dialog }
        let data = try! JSONSerialization.data(withJSONObject: obj)
        try! data.write(to: dir.appendingPathComponent(tty).appendingPathComponent(".alive"))
    }
    private var flag: URL { dir.appendingPathComponent(tty).appendingPathComponent(".dialog") }
    private func raise() { try! Data("{\"tool\":\"AskUserQuestion\"}\n".utf8).write(to: flag) }
    private func lower() { try? FileManager.default.removeItem(at: flag) }

    // MARK: the flag

    /// Only an AskUserQuestion takes a pasted sentence into its own field (2026-11-27,
    /// measured on 2.1.332): the plain dictation's Return then submits it. A permission
    /// drops the paste, so its Return would approve — held, as an unreadable flag is.
    func testOnlyAnAskUserQuestionTakesThePastedWords() {
        func flag(_ tool: String) -> String { #"{"tool":"\#(tool)","at":1795782525000,"session":"s"}"# + "\n" }
        XCTAssertEqual(DialogGate.flaggedTool(flag("AskUserQuestion")), "AskUserQuestion")
        XCTAssertTrue(DialogGate.pasteFillsDialog(flagText: flag("AskUserQuestion")))
        for tool in ["Bash", "Write", "ExitPlanMode", "mcp:github"] {
            XCTAssertFalse(DialogGate.pasteFillsDialog(flagText: flag(tool)), tool)
        }
        XCTAssertFalse(DialogGate.pasteFillsDialog(flagText: nil))
        XCTAssertFalse(DialogGate.pasteFillsDialog(flagText: "{\"tool\":"), "half-written")
    }

    func testTheFlagCountsOnlyBesideAFreshBeat() {
        let now = 1_000_000_000.0
        XCTAssertTrue(DialogGate.flagCounts(flagExists: true, beatAt: now - 2_000, now: now))
        XCTAssertFalse(DialogGate.flagCounts(flagExists: true, beatAt: now - 11_000, now: now), "a crashed session's leftover")
        XCTAssertFalse(DialogGate.flagCounts(flagExists: true, beatAt: nil, now: now), "no beat at all")
        XCTAssertFalse(DialogGate.flagCounts(flagExists: false, beatAt: now, now: now))
    }

    /// An `.alive` caught half-written is read by its mtime: a flag beside it still counts.
    func testAHalfWrittenBeatStillCounts() throws {
        raise()
        let alive = dir.appendingPathComponent(tty).appendingPathComponent(".alive")
        try Data("{\"pid\":1,\"ses".utf8).write(to: alive)
        XCTAssertTrue(DialogGate.flagUp(tty: tty))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: alive.path)
        XCTAssertFalse(DialogGate.flagUp(tty: tty), "an old, broken beat is a dead session")
    }

    func testTheFilesOnDisk() {
        XCTAssertFalse(DialogGate.flagUp(tty: "/dev/\(tty)"), "nothing there")
        raise()
        XCTAssertFalse(DialogGate.flagUp(tty: "/dev/\(tty)"), "a flag without a beat")
        beat(ageSeconds: 30)
        XCTAssertFalse(DialogGate.flagUp(tty: "/dev/\(tty)"), "a stale beat")
        beat()
        XCTAssertTrue(DialogGate.flagUp(tty: "/dev/\(tty)"), "the device path reads the same folder")
        XCTAssertTrue(DialogGate.flagUp(tty: tty))
        lower()
        XCTAssertFalse(DialogGate.flagUp(tty: tty))
    }

    func testAnOlderModIsToldApart() {
        beat(dialog: nil)
        XCTAssertFalse(DialogGate.modFlags(tty: tty))
        beat(dialog: 1)
        XCTAssertTrue(DialogGate.modFlags(tty: tty))
        beat(ageSeconds: 30, dialog: 1)
        XCTAssertFalse(DialogGate.modFlags(tty: tty))
    }

    // MARK: the screen (from the 2026-11-25 lab captures, Claude Code 2.1.332)

    static let bashPermission = """
    ❯ Use the Bash tool to run exactly: touch approved.txt   (nothing else, no explanation)
    ⏺ Bash(touch approved.txt)
      ⎿  Waiting…
    ────────────────────────────────────────
     Bash command
     touch approved.txt
     Do you want to proceed?
     ❯ 1. Yes
       2. Yes, and always allow access to dialog-lab from this project
       3. Yes, and switch to auto mode · auto mode handles these prompts for you
       4. No
     Esc to cancel · Tab to amend
    """
    static let planApproval = """
    ❯ Plan: create a file plan-approved.txt with the word yes.
     Claude has written up a plan and is ready to execute. Would you like to proceed?
     ❯ 1. Yes, and use auto mode
       2. Yes, manually approve edits
       3. Tell Claude what to change
          shift+tab to approve with this feedback
     ctrl+g to edit in VS Code · ~/.claude/plans/plan-create.md
    """
    static let askMoved = """
    ❯ Use the AskUserQuestion tool to ask me which color I prefer.
    ────────────────────────────────────────
     ☐ Color
    Which color do you prefer?
      1. Red
         Pick red
    ❯ 12. Blue
         Pick blue
      3. Type something.
    ────────────────────────────────────────
      4. Chat about this
    """
    static let trust = """
    ❯ Yes, I trust this folder
      No, exit
    Enter to confirm · Esc to cancel
    """
    static let idle = """
    ⏺ Answered Claude's questions:
      ⎿  · Which color do you prefer? → Red
    ⏺ The dialog said ❯ 1. Yes and Esc to cancel, quoted here.
    ✻ Cooked for 2s · done 10:44 PM
    ────────────────────────────────────────
    ❯\u{00A0}
    ────────────────────────────────────────
      ⏸ manual mode on · ? for shortcuts
    """
    static let longPaste = """
    ❯ [Pasted text #1 +6 lines]
    ────────────────────────────────────────
      ctrl+g to edit in VS Code
    """
    /// The usage-limit wait (`cli_wait_footer`), drawn under an ordinary box.
    static let usageWait = """
    ⏺ Done.
    ────────────────────────────────────────
    ❯\u{00A0}
    ────────────────────────────────────────
      Continuing automatically in 2h 13m · Esc to cancel
    """
    static let draftList = """
    ⏺ Done.
    ────────────────────────────────────────
    ❯ 1. fix the header
    ────────────────────────────────────────
    """

    static let cases: [(name: String, tail: String, sent: String?, dialog: Bool)] = [
        ("Bash permission", bashPermission, nil, true),
        ("plan approval", planApproval, nil, true),
        ("AskUserQuestion, moved to a two-digit option", askMoved, nil, true),
        ("folder trust: its footer", trust, nil, true),
        ("idle box; the dialog quoted above it does not count", idle, nil, false),
        ("a collapsed paste, ctrl+g hint under it", longPaste, "a long sentence\n\n[📁=x]", false),
        ("his own draft starting 1.: held, the safe side", draftList, nil, true),
        ("the dictated sentence itself starts 1.", draftList, "1. fix the header", false),
        ("no ❯ at all", "$ ls\nfoo bar\n1. not a box\n", nil, false),
        ("the sentence typed into a dialog that just opened", bashPermission, "please look at it", true),
        ("the usage-limit wait's Esc to cancel is not a dialog", usageWait, nil, false),
        ("a dictated 1. under a dialog with its footer is still the dialog", bashPermission, "1.", true),
    ]

    func testTheScreen() {
        for c in Self.cases {
            XCTAssertEqual(DialogGate.screenShowsDialog(tail: c.tail, sent: c.sent), c.dialog, c.name)
        }
    }

    /// **The AppleScript twin answers alike** — the handler as `writeToTerminalApp` embeds
    /// it, run by `osascript` on each case (no Terminal involved).
    func testTheAppleScriptTwinAgrees() throws {
        let script = dir.appendingPathComponent("twin.applescript")
        try (DialogGate.appleScript + """

        on run argv
            if (count argv) is 1 then
                if flagged(item 1 of argv) then return "flagged"
                return "clear"
            end if
            if dialogShown(item 1 of argv, item 2 of argv) then return "dialog"
            return "clear"
        end run
        """).write(to: script, atomically: true, encoding: .utf8)
        for c in Self.cases {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = [script.path, c.tail, c.sent.map(DialogGate.opening) ?? ""]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(said, c.dialog ? "dialog" : "clear", c.name)
        }
        // `flagged`, the in-script test of the flag file right before a keystroke.
        func flagged(_ path: String) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = [script.path, path]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(try flagged(flag.path), "clear")
        raise()
        XCTAssertEqual(try flagged(flag.path), "flagged")
        XCTAssertEqual(try flagged(""), "clear", "no path: the beat was not fresh")
    }

    // MARK: the hold

    func testNoFlagNoWait() {
        var calls = 0
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10) { resume in
            calls += 1
            XCTAssertFalse(resume)
            return .done(.delivered)
        }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(calls, 1)
    }

    func testAStaleFlagDoesNotHold() {
        beat(ageSeconds: 60)
        raise()
        let started = Date()
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10) { _ in .done(.delivered) }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.1)
    }

    /// The flag stands: nothing is tried; it goes, the sentence goes within ~150 ms.
    func testHeldWhileTheFlagStandsThenReleased() {
        beat()
        raise()
        var holds: [Bool] = []
        TerminalBinding.onDialogHold = { _, held in holds.append(held) }
        var triedAt: Date?
        let loweredAt = Date().addingTimeInterval(0.6)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { self.lower() }
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10) { _ in
            triedAt = Date()
            return .done(.delivered)
        }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        let tried = try! XCTUnwrap(triedAt)
        XCTAssertGreaterThanOrEqual(tried.timeIntervalSince(loweredAt), -0.05, "nothing tried while the flag stood")
        XCTAssertLessThan(tried.timeIntervalSince(loweredAt), 0.4, "sent soon after it cleared")
        XCTAssertEqual(holds, [true, false])
    }

    /// A dialog between the text and its Return: the next try is a resume (the box is read,
    /// only the Return pressed when the sentence is still there).
    func testADialogBetweenTextAndReturnResumes() {
        beat()
        var tries: [Bool] = []
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { self.lower() }
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10) { resume in
            tries.append(resume)
            if tries.count == 1 { self.raise(); return .dialog(typed: true) }
            return .done(.delivered)
        }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(tries, [false, true])
    }

    /// Only the screen saw it (no mod): tried again every `screenPoll` until it is gone.
    func testScreenOnlyRetries() {
        var tries = 0
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, screenPoll: 0.05) { resume in
            tries += 1
            XCTAssertFalse(resume, "nothing was typed")
            return tries < 3 ? .dialog(typed: false) : .done(.delivered)
        }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(tries, 3)
    }

    /// **The guard is asked again after a wait, before the first try** (the Fable review,
    /// H1): he killed the session while its question stood — `session.end` deleted the
    /// flag — and the sentence must not be typed at the shell that is in front now.
    func testTheGuardIsAskedAgainAfterAFlagFirstHold() {
        beat()
        raise()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { self.lower() }
        var tried = false, rechecked = false
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, recheck: {
            rechecked = true
            return .wouldRunAsShell("zsh")
        }) { _ in
            tried = true
            return .done(.delivered)
        }
        guard case .wouldRunAsShell("zsh") = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(rechecked)
        XCTAssertFalse(tried, "nothing typed at the shell")
    }

    /// **The flag went with its session** (the H1 lab): `session.end` deleted `.dialog` and
    /// `.alive` while `claude` was still dying, so the guard still passes — nothing is typed.
    func testAFlagThatClearedWithItsSessionTypesNothing() {
        beat()
        raise()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            self.lower()
            try? FileManager.default.removeItem(at: self.dir.appendingPathComponent(self.tty).appendingPathComponent(".alive"))
        }
        var tried = false
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, recheck: { nil }) { _ in
            tried = true
            return .done(.delivered)
        }
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(tried)
    }

    /// No wait, no second guard: the caller's own check stands for a first try.
    func testNoWaitNoRecheck() {
        var rechecked = false
        _ = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, recheck: { rechecked = true; return nil }) { _ in .done(.delivered) }
        XCTAssertFalse(rechecked)
    }

    /// **A tab that just gave up gives up at once** while the same dialog stands (H2), and
    /// waits again for a new one.
    func testAGiveUpSticksWhileTheSameDialogStands() {
        beat()
        raise()
        let first = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, limit: 0.3) { _ in .done(.delivered) }
        guard case .heldTooLong = first else { return XCTFail("\(first)") }
        let started = Date()
        let second = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, limit: 5) { _ in .done(.delivered) }
        guard case .heldTooLong = second else { return XCTFail("\(second)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.2, "kept at once, not five more seconds")
        // Another question (another flag): waited for afresh.
        try! Data("{\"tool\":\"Bash\",\"at\":2}\n".utf8).write(to: flag)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { self.lower() }
        let third = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, limit: 5) { _ in .done(.delivered) }
        guard case .delivered = third else { return XCTFail("\(third)") }
    }

    /// A question never answered: nothing sent, `heldTooLong` for the undelivered path.
    func testGivesUpAfterTheLimit() {
        beat()
        raise()
        var tried = false
        var holds: [Bool] = []
        TerminalBinding.onDialogHold = { _, held in holds.append(held) }
        let outcome = TerminalBinding.holdingForDialogs(tty: tty, chars: 10, limit: 0.5) { _ in
            tried = true
            return .done(.delivered)
        }
        guard case .heldTooLong = outcome else { return XCTFail("\(outcome)") }
        XCTAssertFalse(tried)
        XCTAssertEqual(holds, [true, false])
    }
}
