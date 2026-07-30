import AppKit

// `--home <dir>` relocates the outbox + screenshots (one directory per Claude
// session when several run at once). Defaults to ~/.claude-bubble.
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--home":
        if let path = args.next() {
            Outbox.home = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            Outbox.outboxURL = Outbox.home.appendingPathComponent("outbox.jsonl")
            Outbox.shotsDir = Outbox.home.appendingPathComponent("shots")
        }
    case "--label":
        if let label = args.next() { SessionLabel.override(label) }
    case "--help", "-h":
        print("""
        Claude Bubble — floating input bubble that relays dictation, typed text
        and screenshots to a Claude Code session.

          --home <dir>   outbox + screenshot directory (default ~/.claude-bubble)
          --label <s>    what the title calls this session (default: folder@branch
                         of the working directory it was launched in)

        Messages are appended as JSON lines to <dir>/outbox.jsonl.
        """)
        exit(0)
    default:
        break
    }
}

let app = NSApplication.shared
// Accessory: no Dock icon, no menu bar — it is an overlay, not an app you switch to.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
