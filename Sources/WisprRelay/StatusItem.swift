import AppKit

/// The one fixed place the overlay can always be found.
///
/// The chip belongs to the pointer and hides when there is none; the panel comes
/// and goes with what is happening. Neither is a reliable answer to "is this
/// thing still running, and how do I stop it?" — the ✕ only exists on the panel,
/// which at rest means pausing first just to reach it. A menu bar item sits in
/// the same pixels for the whole life of the process.
///
/// It carries **where the words go** as a disabled header — the bound session's
/// `folder@branch` behind the destination app's icon, or the launch label while
/// nothing is bound. Same reason the chip's top line does: with two overlays up,
/// two identical 🤖 in the menu bar say nothing about which session a click is
/// about to end, and nothing at all about which terminal is receiving sentences.
///
/// Two commands: **Pause/Resume** and **Quit**. Pause is here and not only on the
/// chip because the chip is a moving target — it rides the cursor and disappears
/// while he types — and pausing is something he does *on his way into another
/// app*, i.e. exactly when he has no patience to chase a label around.
final class StatusItem: NSObject, NSMenuDelegate {

    var onExit: (() -> Void)?
    var onTogglePause: (() -> Void)?
    /// Picked from the two engine rows in the menu. `AppDelegate` owns what happens
    /// next — bringing the model up or letting it go — and calls `setEngine`
    /// back, so the tick never claims something that has not happened.
    var onPickEngine: ((TranscriptionEngine) -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pause = NSMenuItem(title: "Pause", action: nil, keyEquivalent: "")
    private var engineItems: [TranscriptionEngine: NSMenuItem] = [:]
    private var isPaused = false
    private var engineLoading = false

    /// The same 🤖, on every other screen. `NSStatusItem` only ever appears in the
    /// menu bar of the display with the focus, and that is the one display Victor
    /// is *not* looking at whenever this matters.
    private let mirror = MenuBarMirror()

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

        // Pause above Quit, because it is the one he reaches for repeatedly: the
        // relay is paused whenever he wants to dictate into something *other* than
        // the agent, which happens many times a session, whereas Quit happens once.
        pause.action = #selector(pauseClicked)
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        // Two ticked items rather than one "Use local Whisper" checkbox. The
        // choice is between two named recognisers, and a checkbox would name only
        // one of them — leaving the other as "not that", which is exactly the
        // thing worth being explicit about while the local one is still being
        // evaluated.
        //
        // Laid out flat in the main menu, one under the other, rather than behind
        // a "Transcription" submenu: two items are not worth a hover-and-wait, and
        // flat means the tick — which engine is live right now — is readable the
        // moment the menu opens, instead of only after the submenu unfurls. The
        // separator above is what a submenu was really providing: a visible break
        // from the commands, so a row that *sets a mode* is never mistaken for one
        // that *does something*.
        for engine in [TranscriptionEngine.wispr, .whisper] {
            let mi = NSMenuItem(title: engine.label, action: #selector(engineClicked(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = engine.rawValue
            menu.addItem(mi)
            engineItems[engine] = mi
        }
        setEngine(TranscriptionEngine.current)

        menu.addItem(.separator())

        // No ⌘Q key equivalent: the app never becomes key, so the hint would
        // advertise a shortcut that does nothing outside the open menu.
        let exit = NSMenuItem(title: "Quit", action: #selector(exitClicked), keyEquivalent: "")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
        mirror.start()
    }

    /// The tick follows the engine that is actually in use, which is why
    /// `AppDelegate` calls this rather than the click handler doing it: choosing
    /// Local Whisper starts a model that takes ten seconds to load and can fail
    /// outright, and a tick that moved on the click would say the switch had
    /// happened while the weights were still loading — or after it had failed.
    func setEngine(_ engine: TranscriptionEngine) {
        for (e, mi) in engineItems { mi.state = (e == engine) ? .on : .off }
    }

    /// Shown beside the name in the menu **and** in the menu bar itself.
    ///
    /// The in-menu half only helps a menu that is already open, which is not
    /// where he will be looking: he clicks Local Whisper, the menu closes, and
    /// then he wants to know when he may start talking. The menu bar is the one
    /// place that is always in the same pixels — and the only one still visible
    /// while he types, since the chip rides the pointer and macOS hides the
    /// pointer while typing.
    ///
    /// ⏳ takes the same slot as ⏸️ and outranks it for the ten seconds it is up:
    /// paused is a state he chose and can read at leisure, while this one is
    /// about whether the *next* sentence will reach the engine he just picked.
    func setEngineLoading(_ loading: Bool) {
        engineLoading = loading
        engineItems[.whisper]?.title = loading
            ? "\(TranscriptionEngine.whisper.label) — loading…"
            : TranscriptionEngine.whisper.label
        refreshGlyph()
    }

    private func refreshGlyph() {
        let glyph: String
        if engineLoading      { glyph = "⏳🤖" }
        else if isPaused      { glyph = "⏸️🤖" }
        else                  { glyph = "🤖" }
        item.button?.title = glyph
        // The same glyph, repeated on the displays macOS will not put a status
        // item on. One call site, so the copies cannot say something the original
        // does not — see `MenuBarMirror`.
        mirror.setGlyph(glyph)
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
        isPaused = value
        pause.title = value ? "Resume" : "Pause"
        // Same order as the chip: ⏸️ in front of the robot, never instead of it.
        // Routed through `refreshGlyph` so it cannot stomp on a ⏳ that is up —
        // the two states are set from different places and both own this glyph.
        refreshGlyph()
    }

    /// Where the words are going: the bound session's `folder@branch`, behind the
    /// destination app's own icon.
    ///
    /// The same line the chip shows, and here for the reason the chip cannot
    /// cover: it rides the pointer, and macOS hides the pointer the moment he
    /// starts typing. The menu is then the only place left that can be asked
    /// *which* terminal is about to receive the next sentence — and with two
    /// relays running, two identical 🤖 in the menu bar is exactly the confusion
    /// this answers.
    ///
    /// nil puts it back to the launch label, which is what an unbound relay is:
    /// an outbox in a directory, with some agent watching it.
    func setDestination(_ line: String?, icon: NSImage?) {
        destination = line
        header.image = icon
        applyHeader()
    }

    private var destination: String?

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    func menuWillOpen(_ menu: NSMenu) {
        SessionLabel.refresh()
        applyHeader()
    }

    private func applyHeader() {
        header.title = destination ?? "🤖 \(SessionLabel.value)"
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
