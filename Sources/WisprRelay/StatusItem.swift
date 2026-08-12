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

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")

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

        // No ⌘Q key equivalent: the app never becomes key, so the hint would
        // advertise a shortcut that does nothing outside the open menu.
        let exit = NSMenuItem(title: "Exit", action: #selector(exitClicked), keyEquivalent: "")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
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
}
