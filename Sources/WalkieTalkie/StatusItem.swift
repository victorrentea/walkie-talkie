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
/// **Since 2026-08-30 it is also the only place the gestures are written down.**
/// The chip beside the cursor used to carry a legend — `ReBind`, `dictate`, the
/// shutter, `⌘⇧🖱️` — and Victor had it taken off: it rides over his actual work
/// all day, and a legend is read once and paid for forever. So every action this
/// app has now has a row here, **always visible**, naming the mouse or key that
/// performs it. A row greys out when it cannot act *right now*; it never
/// disappears, because a menu that hid what he cannot do this second would be
/// useless for learning what he can do at all.
final class StatusItem: NSObject, NSMenuDelegate {

    var onExit: (() -> Void)?
    var onTogglePause: (() -> Void)?
    /// What the local model is holding right now, in bytes — nil while it is not
    /// up. Asked when the menu opens, like the header, because that is the only
    /// moment the answer has to be right.
    var whisperFootprint: (() -> UInt64?)?

    /// Which model the helper actually loaded — `RELAY_WHISPER_MODEL`, or the
    /// default it fell back to — nil while it is not up. Asked when the menu
    /// opens, like the footprint beside it.
    ///
    /// **This is the only place the id is written.** It used to ride the overlay,
    /// beside the pulse, all through every dictation; but the model is a setting,
    /// not an event, and the row beside the cursor is read mid-sentence. A menu
    /// is where a setting is looked up on purpose — and this row is already the
    /// engine's row, so the id lands beside the RAM it is costing.
    var whisperModel: (() -> String?)?

    /// Whether the relay's own microphone is open right now. Asked when the menu
    /// opens, for the same reason the footprint is: it is a fact that changes
    /// with every dictation, and the one moment it has to be right is the moment
    /// the row that ends it is on screen.
    var isRecording: (() -> Bool)?

    /// ⌘⌃P from the menu, and whether there is anything to paste. Asked when the
    /// menu opens, like the two above: it becomes true with the first dictation
    /// of the session and never goes back, but the moment it has to be right is
    /// the moment the row is on screen.
    var onPasteLast: (() -> Void)?
    var hasLastDictation: (() -> Bool)?

    /// Whether the frontmost app is one the relay could bind. Asked when the menu
    /// opens, like the rest — it changes with every app switch, and the moment it
    /// has to be right is the moment the row is on screen.
    var frontIsBindable: (() -> Bool)?

    /// Picked from **Stop Recording** — end the open dictation and send it, the
    /// same thing a second mouse 5 does.
    var onStopRecording: (() -> Void)?

    /// Picked from **Cancel Dictation** — end the open dictation and throw it
    /// away: no transcript, nothing delivered, and the shots and picks it had
    /// gathered go with it. The counterpart of Stop, for the sentence that came
    /// out wrong before it was ever worth transcribing.
    var onCancelDictation: (() -> Void)?

    /// Picked from **Start Dictation** — open the microphone, the same thing
    /// mouse 5 does. The other end of the pair that already had two ways out and
    /// only one way in.
    var onStartDictation: (() -> Void)?

    /// Picked from **Bind This Window** — the same call ⌘⌃D and the left-plus-wheel
    /// chord make.
    var onBind: (() -> Void)?

    /// Picked from **New Claude Code** — open the microphone with the spawn
    /// destination armed, exactly as ⌘ + the wheel does.
    var onNewSession: (() -> Void)?

    /// Picked from **One More Screenshot** — the same picture F3 and the back
    /// button take.
    var onShot: (() -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// **The menu is where the gestures are written down.** Every one of these
    /// commands also has a mouse or keyboard route, and none of those routes
    /// announces itself anywhere else: ⌘⌃D shadows a system shortcut, and the
    /// wheel means one thing alone, another held, and a third with the left
    /// button already down — none of which anybody guesses. A menu row is read
    /// while reaching for the thing it does, which makes it the one place a
    /// gesture can be learned without being taught.
    ///
    /// ⌘⌃D rides as a real key equivalent so macOS right-aligns it; the wheel
    /// gestures have no key equivalent to be, so they are said in the title.
    private let bind = NSMenuItem(title: "Bind This Window — or hold left, click the wheel", action: nil, keyEquivalent: "d")

    /// Let go of the terminal without ending the session — the menu's answer to
    /// ⌘⌃D pressed on the bound target, minus the quitting.
    private let disconnect = NSMenuItem(title: "Disconnect", action: nil, keyEquivalent: "")
    /// Ends the dictation the relay is recording itself — Local Whisper only,
    /// see the comment at the row's construction.
    /// Opens the microphone from the menu — see `onStartDictation`.
    private let startDictation = NSMenuItem(title: "Start Dictation — click the wheel", action: nil, keyEquivalent: "")
    private let stopRecording = NSMenuItem(title: "End Dictation — click the wheel", action: nil, keyEquivalent: "")
    /// Same row, opposite verdict — see `onCancelDictation`.
    private let cancelDictation = NSMenuItem(title: "Cancel Dictation — hold the wheel 2s", action: nil, keyEquivalent: "")
    /// ⌘ + the wheel: a dictation whose destination is a terminal that does not
    /// exist yet. Spelled with the folder in it because that is the one thing
    /// about it he cannot see beforehand — the window opens after he has spoken.
    private let newSession = NSMenuItem(title: "New Claude Code in ~/workspace — ⌘ + click the wheel", action: nil, keyEquivalent: "")
    /// The shutter. Both routes are named: F3 works whenever there is a
    /// destination, the back button only while a dictation is running — which is
    /// also the only window in which it stops typing Return.
    /// The last dictation, again — see `AppDelegate.pasteLastDictation`. Greyed
    /// until there is one, like every other row that cannot act right now.
    private let pasteLast = NSMenuItem(title: "Paste the Last Dictation — at the caret, and onto the clipboard",
                                       action: nil, keyEquivalent: "p")
    private let shot = NSMenuItem(title: "One More Screenshot — F3, or the back button while dictating", action: nil, keyEquivalent: "")
    /// **A legend row, and the only one here that is not a command.** ⌘⇧-click
    /// happens inside Chrome, in a page this app cannot reach from a menu — but
    /// it is a gesture the relay takes over, it used to be advertised on the chip
    /// while dictating, and with the chip silent there is nowhere else it could
    /// be said. Permanently disabled, which is the honest rendering of "this is
    /// something you do, not something you pick".
    private let pickLegend = NSMenuItem(title: "Pick an Element in Chrome — ⌘⇧ + click, while dictating", action: nil, keyEquivalent: "")
    /// Hand the mouse and the microphone back — the same toggle a click on the
    /// chip makes. **Back in the menu since 2026-08-30**: it was taken out when
    /// Disconnect turned out to be the row he reached for, and the argument
    /// against it (two commands that both mean "stop relaying") is outranked by
    /// the new rule that every action has to be listed somewhere. The chip is
    /// still the fast way, and the row is where that is written down.
    private let pause = NSMenuItem(title: "Pause — click the chip", action: nil, keyEquivalent: "")
    /// The one recogniser row — a readout, not a switch. See `applyWhisperTitle`.
    private let whisperItem = NSMenuItem(title: "Local Whisper", action: nil, keyEquivalent: "")
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
        // **Every `isEnabled` in this file was inert until 2026-08-29.** AppKit
        // auto-enables an item whenever its target responds to the action, unless
        // the menu says otherwise or the target implements `validateMenuItem` —
        // and this one does neither. So `Disconnect` with nothing bound, and
        // `End Dictation` with nothing recording, both looked disabled in the
        // source and were fully clickable on screen. (The header only ever
        // greyed out because it has no action at all.) The flags are set from
        // `menuWillOpen`, which is the moment they have to be right, so turning
        // auto-enabling off makes them mean what they say.
        menu.autoenablesItems = false
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        bind.keyEquivalentModifierMask = [.command, .control]
        bind.action = #selector(bindClicked)
        bind.target = self
        menu.addItem(bind)

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

        // The wheel already ends a recording — this is the same call, for the
        // case the mouse is not where the hand is: a dictation started at the
        // desk has to be closable from the trackpad, from another room's
        // Bluetooth mouse, or after the mouse's battery has gone. Recording is
        // the one state where being unable to reach the button costs the
        // dictation *and* keeps the microphone open.
        //
        // Disabled while nothing is being recorded, the way Disconnect is while
        // nothing is bound: the row is the only place in the menu that says
        // whether the microphone is open at all, so it stays visible and answers
        // that question even when there is nothing to click.
        // **Above Stop, because it comes first.** The wheel was the only way in,
        // and it is one button on one specific mouse — the same argument that put
        // Stop here, which had been keeping the menu able to end a dictation it
        // could not begin. Enabled only while something is bound: unbound the
        // relay is inert and `startLocalRecording` would refuse anyway, and a row
        // that silently does nothing is worse than one that says it cannot.
        startDictation.action = #selector(startDictationClicked)
        startDictation.target = self
        startDictation.isEnabled = false
        menu.addItem(startDictation)

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

        // **Under the three that end a dictation, because it starts one.** It
        // sits with them rather than beside Bind — which is where a reader
        // looking for "how do I get a session" would expect it — because what it
        // actually does is open the microphone; the window is what happens when
        // the sentence is over. Enabled whether or not anything is bound: that is
        // the whole point of the gesture.
        newSession.action = #selector(newSessionClicked)
        newSession.target = self
        menu.addItem(newSession)

        // **Under the dictation commands, because it is about the last one.**
        // Not a gesture that happens *during* a sentence like the two rows below,
        // and not a destination like the rows above: it is what he reaches for
        // once the words have landed somewhere and he wants them somewhere else
        // too — a commit message, a chat, a form.
        pasteLast.keyEquivalentModifierMask = [.command, .control]
        pasteLast.action = #selector(pasteLastClicked)
        pasteLast.target = self
        pasteLast.isEnabled = false
        menu.addItem(pasteLast)

        shot.action = #selector(shotClicked)
        shot.target = self
        shot.isEnabled = false
        menu.addItem(shot)

        pickLegend.isEnabled = false
        menu.addItem(pickLegend)

        menu.addItem(.separator())

        pause.action = #selector(pauseClicked)
        pause.target = self
        menu.addItem(pause)

        // **One row, and it is a readout rather than a switch.** There used to be
        // two — Wispr Flow and Local Whisper, ticked — from the months the relay
        // read another app's database. It records for itself now, so there is
        // nothing to choose between; what is left is the one question the row was
        // really being read for, which is whether the model is up and what it is
        // holding.
        //
        // Kept in the menu rather than deleted: it is the only place that says
        // the weights are resident, and the only place `— loading…` is visible
        // when the chip is not on screen.
        whisperItem.isEnabled = false
        menu.addItem(whisperItem)
        applyWhisperTitle()

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

    /// Shown beside the name in the menu **and** in the menu bar itself.
    ///
    /// The in-menu half only helps a menu that is already open, which is not
    /// where he will be looking: he binds a terminal, the menu closes, and then
    /// he wants to know when he may start talking. The menu bar is the one place
    /// that is always in the same pixels — and the only one still visible while
    /// he types, since the chip rides the pointer and macOS hides the pointer
    /// while typing.
    ///
    /// ⏳ takes the same slot as ⏸️ and outranks it for the ten seconds it is up:
    /// paused is a state he chose and can read at leisure, while this one is
    /// about whether the *next* sentence has a recogniser to reach.
    func setEngineLoading(_ loading: Bool) {
        engineLoading = loading
        applyWhisperTitle()
        refreshGlyph()
    }

    /// `Local Whisper (mlx-community/whisper-large-v3-turbo) — 1.6 GB RAM` while
    /// the model is up.
    ///
    /// **The cost is shown, because the weights are the whole argument** for
    /// starting the helper only when a dictation is coming and letting it go
    /// afterwards; until this row existed that cost was a number in a comment,
    /// which is exactly where a fact nobody can check belongs. It doubles as
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
        // **The id in parentheses, in full.** `Local Whisper` names a category and
        // the category is not the interesting half: `RELAY_WHISPER_MODEL` swaps
        // the model, and the id is what a comparison between recognisers is
        // written down against. It is parenthetical rather than a second dashed
        // clause so that the row still reads as `<engine> — <cost>`.
        let name = whisperModel?().map { "Local Whisper (\($0))" } ?? "Local Whisper"
        if engineLoading {
            whisperItem.title = "\(name) — loading…"
        } else if let bytes = whisperFootprint?() {
            whisperItem.title = String(format: "%@ — %.1f GB RAM", name,
                                       Double(bytes) / 1_073_741_824)
        } else {
            whisperItem.title = name
        }
    }

    /// Live only while the microphone is open.
    ///
    /// The title does not change with the state — greyed is the whole of "there
    /// is nothing being recorded", the same way Disconnect is greyed while
    /// nothing is bound. A row that renamed itself would be claiming to *be* the
    /// state readout, and the readout that matters (🔴, and the model's name
    /// beside it) is on the chip and in the overlay already.
    /// Bound already, the row is how he lets go — `bind` toggles on its own
    /// target — so it stays enabled either way and only goes dead when the
    /// frontmost window is not something a dictation could be typed into.
    private func applyBind() {
        bind.isEnabled = isBound || (frontIsBindable?() ?? true)
    }

    private func applyStopRecording() {
        let recording = isRecording?() ?? false
        startDictation.isEnabled = isBound && !recording
        stopRecording.isEnabled = recording
        cancelDictation.isEnabled = recording
        // The one row that does not ask about a binding — it brings its own
        // destination. Only a dictation already running takes it away, and then
        // only because ⌘ + the wheel would end that one rather than start this.
        newSession.isEnabled = !recording
        // The same gate `plusOneShot` applies: a picture is worth taking when
        // there is somewhere for it to go.
        shot.isEnabled = (isBound || recording) && !isPaused
    }

    private func refreshGlyph() {
        // The picture says bound; the badge in front of it says the two states
        // that are *not* about where the words go. ⏳ outranks ⏸️ for the ten
        // seconds it is up, since "will the next sentence have a recogniser" is
        // the more urgent of the two questions.
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
        // Worded as the verb the click performs, not as the state it reports —
        // a menu open for one second should say what happens next.
        pause.title = value ? "Resume — click the chip" : "Pause — click the chip"
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
    @objc private func startDictationClicked() { onStartDictation?() }
    @objc private func bindClicked() { onBind?() }
    @objc private func newSessionClicked() { onNewSession?() }
    @objc private func shotClicked() { onShot?() }
    @objc private func pasteLastClicked() { onPasteLast?() }

    private var destination: String?

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    func menuWillOpen(_ menu: NSMenu) {
        SessionLabel.refresh()
        applyHeader()
        applyWhisperTitle()
        applyStopRecording()
        pasteLast.isEnabled = hasLastDictation?() ?? false
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

}
