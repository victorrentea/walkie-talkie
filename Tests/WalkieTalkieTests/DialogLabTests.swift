import XCTest
@testable import WalkieTalkie

/// **End to end, opt-in: Walkie's real tmux delivery into a real Claude Code that shows a
/// dialog** (2026-11-25). Skipped unless `WT_DIALOG_LAB_PANE` names a pane (`%0`) of a
/// lab tmux server, reached through `TMUX_TMPDIR` — never the installed app, never his
/// Terminal. The session runs the `walkie-inbox` mod (`--plugin-dir`), which flags its
/// dialogs in `~/.walkie-talkie/inbox/<pane tty>/.dialog`. The lab script raises an
/// AskUserQuestion, starts this test, answers the question by hand some seconds later and
/// checks that the sentence went in only afterwards — and that the question got *his*
/// answer, not option 1 from Walkie's Return.
final class DialogLabTests: XCTestCase {

    func testHeldUntilTheQuestionIsAnsweredThenDelivered() throws {
        let env = ProcessInfo.processInfo.environment
        guard let pane = env["WT_DIALOG_LAB_PANE"], let tty = env["WT_DIALOG_LAB_TTY"] else {
            throw XCTSkip("the dialog lab is not running (WT_DIALOG_LAB_PANE / WT_DIALOG_LAB_TTY)")
        }
        let text = env["WT_DIALOG_LAB_TEXT"] ?? "Reply with the single word LAB-OK and nothing else."
        let target = TerminalBinding.Target(
            handle: .tmux(pane: pane, tty: tty), label: "dialog-lab", address: pane,
            appName: "Terminal", bundleID: "com.apple.Terminal", folder: nil, title: nil,
            sourceFrame: nil, boundAt: Date())
        var holds: [Bool] = []
        TerminalBinding.onDialogHold = { _, held in holds.append(held) }
        defer { TerminalBinding.onDialogHold = nil }
        let started = Date()
        let outcome = TerminalBinding().deliver(text, to: target)
        let waited = Date().timeIntervalSince(started)
        print("DIALOG-LAB outcome=\(outcome) waited=\(String(format: "%.2f", waited)) s holds=\(holds)")
        XCTAssertEqual(holds, [true, false], "held, then released")
        // `refused`: the session was killed while its question stood (the Fable review, H1)
        // — the guard, asked again after the wait, must find the shell and type nothing.
        if env["WT_DIALOG_LAB_EXPECT"] == "refused" {
            guard case .wouldRunAsShell = outcome else { return XCTFail("\(outcome)") }
            return
        }
        guard case .delivered = outcome else { return XCTFail("\(outcome)") }
        if let min = env["WT_DIALOG_LAB_MIN_WAIT"].flatMap(Double.init) {
            XCTAssertGreaterThanOrEqual(waited, min, "nothing sent before the question was answered")
        }
    }
}
