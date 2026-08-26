import AppKit

// `--home <dir>` relocates the outbox (one directory per agent session when
// several run at once). Defaults to ~/.walkie-talkie. Screenshots are not part of
// it — they go to Caches, under a folder per relay session.
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--home":
        if let path = args.next() {
            Outbox.home = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            Outbox.outboxURL = Outbox.home.appendingPathComponent("outbox.jsonl")
            // Shots are deliberately **not** relocated with it. They live in
            // Caches so the system can reclaim them, and the per-session folder
            // there already does the separating that `--home` was doing for them.
        }
    case "--label":
        if let label = args.next() { SessionLabel.override(label) }
    case "--help", "-h":
        print("""
        Walkie Talkie — floating overlay that relays what Wispr Flow hears,
        the text you had selected, and screenshots to a waiting agent.

          --home <dir>   outbox directory (default ~/.walkie-talkie). Screenshots
                         always go to ~/Library/Caches/ro.victorrentea.wispr-relay,
                         under a folder per relay session, so the system can
                         reclaim them.
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
