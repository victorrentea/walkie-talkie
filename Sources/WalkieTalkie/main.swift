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
        Walkie Talkie — floating overlay that records what you dictate,
        transcribes it locally, and relays it with the text you had selected
        and your screenshots to a waiting agent.

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
// **`.regular`, so it is in the Dock with a running dot under it** (Victor,
// 2026-09-07). It was `.accessory` for two months on the argument that an
// overlay is not an app you switch to — true, and beside the point the day the
// app deadlocks: an `.accessory` app has no Dock tile, so there is no ⌥-click →
// **Force Quit**, and the only way out of a frozen relay is Activity Monitor or
// a terminal that may itself be the thing being typed into. The tile is the
// escape hatch, and it costs nothing the rest of the time: the overlay is a
// `.nonactivatingPanel`, so nothing here starts taking focus.
//
// What it does cost is a menu bar whenever the app *is* frontmost — a Dock click
// is enough — and an app with no main menu shows an empty one. Hence
// `installAppMenu` below: ⌘Q, and the About row the status item already has.
app.setActivationPolicy(.regular)
installAppMenu(app)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

/// The minimum a `.regular` app owes its menu bar: the app menu, About, Hide and
/// Quit. Everything the relay actually does is in the status item — this is here
/// so the one moment the app is frontmost does not look broken.
private func installAppMenu(_ app: NSApplication) {
    let name = "Walkie Talkie"
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "About \(name)", action: #selector(AppMenuActions.about), keyEquivalent: "")
        .target = AppMenuActions.shared
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let appItem = NSMenuItem()
    appItem.submenu = appMenu
    let main = NSMenu()
    main.addItem(appItem)
    app.mainMenu = main
}

/// A target for the About row. `NSMenuItem` needs an object to send to, and the
/// status item's own controller does not exist yet at this point in launch.
private final class AppMenuActions: NSObject {
    static let shared = AppMenuActions()
    @objc func about() { AboutPage.openInBrowser() }
}
