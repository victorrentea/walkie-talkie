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

    /// What the local model is holding right now, in bytes — nil while it is not
    /// up. Asked when the menu opens, like the header, because that is the only
    /// moment the answer has to be right.
    var whisperFootprint: (() -> UInt64?)?

    /// Whether the relay's own microphone is open right now. Asked when the menu
    /// opens, for the same reason the footprint is: it is a fact that changes
    /// with every dictation, and the one moment it has to be right is the moment
    /// the row that ends it is on screen.
    var isRecording: (() -> Bool)?

    /// Picked from **Stop Recording** — end the open dictation and send it, the
    /// same thing a second mouse 5 does.
    var onStopRecording: (() -> Void)?

    /// Picked from **Cancel Dictation** — end the open dictation and throw it
    /// away: no transcript, nothing delivered, and the shots and picks it had
    /// gathered go with it. The counterpart of Stop, for the sentence that came
    /// out wrong before it was ever worth transcribing.
    var onCancelDictation: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// Let go of the terminal without ending the session — the menu's answer to
    /// ⌘⌃D pressed on the bound target, minus the quitting.
    private let disconnect = NSMenuItem(title: "Disconnect", action: nil, keyEquivalent: "")
    /// Ends the dictation the relay is recording itself — Local Whisper only,
    /// see the comment at the row's construction.
    private let stopRecording = NSMenuItem(title: "Stop Dictation", action: nil, keyEquivalent: "")
    /// Same row, opposite verdict — see `onCancelDictation`.
    private let cancelDictation = NSMenuItem(title: "Cancel Dictation", action: nil, keyEquivalent: "")
    private var engineItems: [TranscriptionEngine: NSMenuItem] = [:]
    private var engine = TranscriptionEngine.current
    private var isPaused = false
    private var engineLoading = false
    /// Whether the relay is pointed at a terminal, which is what the two icons
    /// distinguish. Set from the same `setDestination` the header uses, so the
    /// picture in the menu bar and the line inside the menu cannot disagree.
    private var isBound = false

    /// The same 🤖, on every other screen. `NSStatusItem` only ever appears in the
    /// menu bar of the display with the focus, and that is the one display Victor
    /// is *not* looking at whenever this matters.
    private let mirror = MenuBarMirror()

    override init() {
        super.init()

        // **A drawing of a walkie-talkie, in two states, replacing the 🤖.**
        //
        // The robot was inherited from the overlay's chip, and it said what the
        // app *did* rather than what it is — fine while the app was started per
        // session by another app's shortcut, and wrong now that this one runs
        // from login and is the thing Victor looks for in the bar. The two
        // pictures are the same drawing: at rest the device alone, and bound the
        // full icon, ring and all. So "is it pointed at a terminal?" is answered
        // by the ring appearing round something already in that spot, which is a
        // faster read than a glyph swap and needs no colour vocabulary.
        item.button?.image = Self.idleIcon
        item.button?.imagePosition = .imageLeading
        item.button?.title = ""

        let menu = NSMenu()
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // **No Pause row.** It was the first command in the menu on the reading
        // that pausing is what he does whenever he wants to dictate into
        // something other than the agent. Disconnect turned out to be the thing
        // he actually reaches for — it says which terminal, where pause says only
        // "not now" — and two commands that both mean "stop relaying" are one
        // question the menu should not be asking. The state itself is still
        // there, and clicking the chip still toggles it.

        // **Under Pause, because it is the other half of the same question.**
        // Pause stops the words going *anywhere*; this one stops them going to
        // *that terminal* and hands them back to the outbox, which is what the
        // relay does when nothing is bound. ⌘⌃D on the bound target already
        // does something adjacent and stronger — it ends the session — and there
        // was no way to simply let go of a tab: he had to quit the relay and
        // start it again somewhere else. Disabled while nothing is bound, since
        // it would then be a command with nothing to act on.
        disconnect.action = #selector(disconnectClicked)
        disconnect.target = self
        disconnect.isEnabled = false
        menu.addItem(disconnect)

        // **Only on Local Whisper, because only then does the relay hold the
        // microphone.** With Wispr Flow the recording is Wispr's — it starts and
        // ends on Wispr's own button, and a row here claiming to stop it would be
        // a lie the app cannot make true. So the row is hidden outright rather
        // than shown greyed: a permanently dead command is a question ("why can't
        // I?") the menu then has to answer, and there is no answer that fits in a
        // menu.
        //
        // Mouse 5 already ends a recording — this is the same call, for the case
        // the mouse is not where the hand is: mouse 5 is a thumb button on one
        // specific mouse, and a dictation started at the desk has to be closable
        // from the trackpad, from another room's Bluetooth mouse, or after the
        // mouse's battery has gone. Recording is the one state where being unable
        // to reach the button costs the dictation *and* keeps the microphone open.
        //
        // Disabled while nothing is being recorded, the way Disconnect is while
        // nothing is bound: the row is the only place in the menu that says
        // whether the microphone is open at all, so it stays visible and answers
        // that question even when there is nothing to click.
        stopRecording.action = #selector(stopRecordingClicked)
        stopRecording.target = self
        stopRecording.isEnabled = false
        menu.addItem(stopRecording)

        // **Directly under Stop, because it is the same moment with the other
        // answer.** Stopping sends what was said; this throws it away — the
        // sentence that came out wrong, the interruption, the dictation started
        // by accident. Without it the only way out of a bad recording was to
        // stop it, watch it transcribe, and cancel the panel — three steps and a
        // model run for something he already knew he did not want.
        cancelDictation.action = #selector(cancelDictationClicked)
        cancelDictation.target = self
        cancelDictation.isEnabled = false
        menu.addItem(cancelDictation)

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
        //
        // The build stamp rides on this row rather than taking a line of its own,
        // the way Victor Addons does it: it is read once a session, when the
        // question is "am I looking at what I just built?" — and that question is
        // asked while reaching for Quit anyway, since the answer to "no" is to
        // quit and relaunch.
        let exit = NSMenuItem(title: "Quit — built \(Self.buildStamp)",
                              action: #selector(exitClicked), keyEquivalent: "")
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
        self.engine = engine
        for (e, mi) in engineItems { mi.state = (e == engine) ? .on : .off }
        applyStopRecording()
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
        applyWhisperTitle()
        refreshGlyph()
    }

    /// `Local Whisper — 1.6 GB RAM` while the model is up.
    ///
    /// **The cost is shown where the choice is made.** The weights are the whole
    /// argument for starting the helper only when the engine is selected and
    /// killing it the moment it is not; until now that cost was a number in this
    /// file's comments, which is exactly where a fact nobody can check belongs.
    /// Beside the row that turns it on, it is the answer to "what am I paying for
    /// this?" at the moment the question can still be acted on — and it doubles as
    /// proof the helper is actually alive, since a dead one has no footprint and
    /// the row goes back to its bare name.
    ///
    /// **`RAM` is spelled out after the number** because a size in a menu is
    /// read as a download by default — the one thing this number is not. It is
    /// what the helper is holding *right now*, and the row is the switch that
    /// gives it back.
    ///
    /// `phys_footprint`, i.e. Activity Monitor's "Memory" — see
    /// `LocalWhisper.footprintBytes` for why not RSS.
    private func applyWhisperTitle() {
        let name = TranscriptionEngine.whisper.label
        if engineLoading {
            engineItems[.whisper]?.title = "\(name) — loading…"
        } else if let bytes = whisperFootprint?() {
            engineItems[.whisper]?.title = String(format: "%@ — %.1f GB RAM", name,
                                                  Double(bytes) / 1_073_741_824)
        } else {
            engineItems[.whisper]?.title = name
        }
    }

    /// Present only on Local Whisper, live only while the microphone is open.
    ///
    /// The title does not change with the state — greyed is the whole of "there
    /// is nothing being recorded", the same way Disconnect is greyed while
    /// nothing is bound. A row that renamed itself would be claiming to *be* the
    /// state readout, and the readout that matters (🔴, and the model's name
    /// beside it) is on the chip and in the overlay already.
    private func applyStopRecording() {
        let recording = isRecording?() ?? false
        stopRecording.isHidden = engine != .whisper
        stopRecording.isEnabled = recording
        cancelDictation.isHidden = engine != .whisper
        cancelDictation.isEnabled = recording
    }

    private func refreshGlyph() {
        // The picture says bound; the badge in front of it says the two states
        // that are *not* about where the words go. ⏳ outranks ⏸️ for the ten
        // seconds it is up, since "will the next sentence reach the engine I just
        // picked" is the more urgent of the two questions.
        let badge: String
        if engineLoading      { badge = "⏳" }
        else if isPaused      { badge = "⏸️" }
        else                  { badge = "" }
        let icon = isBound ? Self.boundIcon : Self.idleIcon
        item.button?.image = icon
        item.button?.title = badge
        // The same picture and badge, repeated on the displays macOS will not put
        // a status item on. One call site, so the copies cannot say something the
        // original does not — see `MenuBarMirror`.
        mirror.set(icon: icon, badge: badge)
    }

    /// The two menu-bar pictures, scaled to the bar's height once.
    ///
    /// Not templates: the ring is the whole signal in the bound one, and a
    /// template image is drawn as a silhouette in a single colour. macOS dims
    /// them on an inactive display either way, which is the behaviour that was
    /// asked for.
    /// When this binary was put in place, for the Quit row.
    ///
    /// **Taken from the executable's own mtime, not from a constant stamped into
    /// the source.** Victor Addons seds a `BUILD_TIME` literal into its Swift file
    /// on every build, which works but dirties a tracked file on each run and
    /// lands in commits as noise. The file date says the same thing for free and
    /// cannot go stale: `build-app.sh` copies the binary into the bundle with a
    /// plain `cp`, so the date is the moment of install even when `swift build`
    /// had nothing to recompile — and a `swift build` run from the terminal gets
    /// its own honest date the same way.
    private static let buildStamp: String = {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attrs?[.modificationDate] as? Date
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date ?? Date())
    }()

    private static let idleIcon = loadIcon("walkie-idle")
    private static let boundIcon = loadIcon("walkie-bound")

    private static func loadIcon(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        let height: CGFloat = 18
        let size = NSSize(width: (image.size.width / image.size.height * height).rounded(),
                          height: height)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
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
        isBound = line != nil
        disconnect.isEnabled = isBound
        refreshGlyph()
        applyHeader()
    }

    /// Called when he picks Disconnect — release the terminal, keep the session.
    var onDisconnect: (() -> Void)?

    @objc private func disconnectClicked() { onDisconnect?() }

    @objc private func stopRecordingClicked() { onStopRecording?() }
    @objc private func cancelDictationClicked() { onCancelDictation?() }

    private var destination: String?

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    func menuWillOpen(_ menu: NSMenu) {
        SessionLabel.refresh()
        applyHeader()
        applyWhisperTitle()
        applyStopRecording()
    }

    /// **`Bound to: petclinic@main`**, not the bare line the chip shows.
    ///
    /// The chip can afford to be bare: it rides the cursor, it appears when a
    /// binding does, and beside a pointer there is nothing else it could be
    /// naming. In the menu the same line sits above `Pause` / `Disconnect` /
    /// `Stop Recording`, and a folder name on its own between an icon and a
    /// stack of commands reads as the title of a section — i.e. as what the
    /// commands are *for*, rather than as where the words are going. The two
    /// words say which of the two it is.
    ///
    /// Only the bound form takes the prefix. Unbound the row falls back to the
    /// launch label, and "Bound to:" in front of that would be a plain lie: with
    /// nothing bound the relay is inert, which is the state this row is most
    /// often read in.
    private func applyHeader() {
        header.title = destination.map { "Bound to: \($0)" } ?? "🤖 \(SessionLabel.value)"
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
