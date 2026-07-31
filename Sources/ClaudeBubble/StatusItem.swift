import AppKit

/// The one fixed place the bubble can always be found.
///
/// The chip belongs to the pointer and hides when there is none; the panel comes
/// and goes with what is happening. Neither is a reliable answer to "is this
/// thing still running, and how do I stop it?" — the ✕ only exists on the panel,
/// which at rest means pausing first just to reach it. A menu bar item sits in
/// the same pixels for the whole life of the process.
///
/// It carries the session label as a disabled header, for the same reason the
/// title does: with two bubbles up, two identical 🤖 in the menu bar say nothing
/// about which session a click is about to end.
final class StatusItem: NSObject, NSMenuDelegate {

    var onExit: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    override init() {
        super.init()

        // Emoji rather than an SF Symbol: the bubble already says 🤖 in the
        // chip, and the eye pairs the two without reading either.
        item.button?.title = "🤖"

        let menu = NSMenu()
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // No ⌘Q key equivalent: the app never becomes key, so the hint would
        // advertise a shortcut that does nothing outside the open menu.
        let exit = NSMenuItem(title: "Exit", action: #selector(exitClicked), keyEquivalent: "")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
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
}
