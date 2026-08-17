import AppKit

/// The one fixed place the overlay can always be found.
///
/// The chip belongs to the pointer and hides when there is none; the panel comes
/// and goes with what is happening. Neither is a reliable answer to "is this
/// thing still running, and how do I stop it?" — the ✕ only exists on the panel,
/// which at rest means pausing first just to reach it. A menu bar item sits in
/// the same pixels for the whole life of the process.
///
/// It carries the session label as a disabled header, for the same reason the
/// title does: with two overlays up, two identical 🤖 in the menu bar say nothing
/// about which session a click is about to end.
///
/// Two commands: **Pause/Resume** and **Exit**. Pause is here and not only on the
/// chip because the chip is a moving target — it rides the cursor and disappears
/// while he types — and pausing is something he does *on his way into another
/// app*, i.e. exactly when he has no patience to chase a label around.
final class StatusItem: NSObject, NSMenuDelegate {

    var onExit: (() -> Void)?
    var onTogglePause: (() -> Void)?
    /// Picked from the Transcription submenu. `AppDelegate` owns what happens
    /// next — bringing the model up or letting it go — and calls `setEngine`
    /// back, so the tick never claims something that has not happened.
    var onPickEngine: ((TranscriptionEngine) -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private var engineItems: [TranscriptionEngine: NSMenuItem] = [:]

    override init() {
        super.init()

        // Emoji rather than an SF Symbol: the overlay already says 🤖 in the
        // chip, and the eye pairs the two without reading either.
        item.button?.title = "🤖"

        let menu = NSMenu()
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Pause above Exit, because it is the one he reaches for repeatedly: the
        // relay is paused whenever he wants to dictate into something *other* than
        // the agent, which happens many times a session, whereas Exit happens once.
        pause.action = #selector(pauseClicked)
        pause.target = self
        menu.addItem(pause)

        // A submenu, and two ticked items rather than one "Use local Whisper"
        // checkbox. The choice is between two named recognisers, and a checkbox
        // would name only one of them — leaving the other as "not that", which
        // is exactly the thing worth being explicit about while the local one is
        // still being evaluated. Tucked behind a submenu because it is set once
        // and then left alone, unlike Pause, which is the item he reaches for
        // many times a session and which must stay one click away.
        let engineItem = NSMenuItem(title: "Transcription", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for engine in [TranscriptionEngine.wispr, .whisper] {
            let mi = NSMenuItem(title: engine.label, action: #selector(engineClicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = engine.rawValue
            engineMenu.addItem(mi)
            engineItems[engine] = mi
        }
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)
        setEngine(TranscriptionEngine.current)

        menu.addItem(.separator())

        // No ⌘Q key equivalent: the app never becomes key, so the hint would
        // advertise a shortcut that does nothing outside the open menu.
        let exit = NSMenuItem(title: "Exit", action: #selector(exitClicked), keyEquivalent: "")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
    }

    /// The tick follows the engine that is actually in use, which is why
    /// `AppDelegate` calls this rather than the click handler doing it: choosing
    /// Local Whisper starts a model that takes ten seconds to load and can fail
    /// outright, and a tick that moved on the click would say the switch had
    /// happened while the weights were still loading — or after it had failed.
    func setEngine(_ engine: TranscriptionEngine) {
        for (e, mi) in engineItems { mi.state = (e == engine) ? .on : .off }
    }

    /// Shown beside the name while the model is coming up, so a menu opened
    /// during those ten seconds explains the wait instead of looking stuck.
    func setEngineLoading(_ loading: Bool) {
        engineItems[.whisper]?.title = loading
            ? "\(TranscriptionEngine.whisper.label) — loading…"
            : TranscriptionEngine.whisper.label
    }

    /// Kept in step with the app's state by `AppDelegate`, not read on demand: the
    /// menu bar glyph has to be right *before* the menu is opened, since while he
    /// is typing the chip is hidden (macOS hides the pointer, so the chip goes with
    /// it) and this is then the only thing on screen saying forwarding is off.
    ///
    /// The item is worded as the verb it performs — "Pause" while running,
    /// "Resume" while paused — rather than as a checkbox of the current state. A
    /// menu he opens for one second should say what the click will do.
    func setPaused(_ value: Bool) {
        pause.title = value ? "Resume" : "Pause"
        // Same order as the chip: ⏸️ in front of the robot, never instead of it.
        item.button?.title = value ? "⏸️🤖" : "🤖"
    }

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    func menuWillOpen(_ menu: NSMenu) {
        SessionLabel.refresh()
        header.title = SessionLabel.value
    }

    @objc private func exitClicked() {
        onExit?()
    }

    @objc private func pauseClicked() {
        onTogglePause?()
    }

    @objc private func engineClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = TranscriptionEngine(rawValue: raw) else { return }
        onPickEngine?(engine)
    }
}
