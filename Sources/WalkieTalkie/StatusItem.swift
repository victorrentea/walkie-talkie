import AppKit

/// The one fixed place the overlay can always be found.
///
/// The chip belongs to the pointer and hides when there is none; the panel comes
/// and goes with what is happening. Neither is a reliable answer to "is this
/// thing still running, and how do I stop it?" — the ✕ only exists on the panel,
/// which at rest is not on screen at all. A menu bar item sits in the same pixels
/// for the whole life of the process.
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

    /// Picked from **Autosend** — the checkbox that takes the pre-send panel out
    /// of the way. See the row's construction for what it actually changes.
    var onToggleAutosend: ((Bool) -> Void)?
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

    /// **Whether the cloud engine could transcribe a sentence this instant** —
    /// which, for a recogniser with nothing to load, is only ever *is there an
    /// API key*. Asked when the menu opens, like the two above and for their
    /// reason: the key is a file Victor can create while the app is running, and
    /// a row that answered from launch would go on saying *no API key* after he
    /// had put one there.
    var elevenReady: (() -> Bool)?

    /// **The engine that wrote the last sentence delivered** — the route its
    /// words came by (`AppDelegate.engineName(via:engineLabel:)`), nil before
    /// the first one this run. Asked when the menu opens, like the rows above.
    var lastEngineUsed: (() -> String?)?



    /// Whether the relay's own microphone is open right now. Asked when the menu
    /// opens, for the same reason the footprint is: it is a fact that changes
    /// with every dictation, and the one moment it has to be right is the moment
    /// the row that ends it is on screen.
    var isRecording: (() -> Bool)?

    /// **Is there a dictation to cancel** — which is not the same question as
    /// `isRecording`. Since 2026-09-12 the row kills a Wispr Flow dictation too,
    /// and that one is nothing this app is *recording*: every other row that
    /// reads `isRecording` (Start Dictation, New Session, Recover) is asking
    /// about the relay's own microphone and must go on asking only about that.
    /// Absent, it falls back to `isRecording`, which is what it used to be.
    var isDictationCancellable: (() -> Bool)?

    /// ⌘⇧P from the menu, and whether there is anything to paste. Asked when the
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

    /// **Undo for the one verdict that could not be undone.** A cancel keeps its
    /// audio in Caches for five minutes; this transcribes it and sends it where a
    /// sentence would go now. Greyed out when there is nothing within the five
    /// minutes, which is nearly always — see `isRecoverable`.
    var onRecoverDictation: (() -> Void)?
    /// Is there a cancelled sentence still inside its five minutes? Asked when
    /// the menu opens, like every other flag here, because that is the one
    /// moment the answer has to be right.
    var isRecoverable: (() -> Bool)?

    /// Play the last dictation's audio, or stop it if it is playing.
    var onReplayLast: (() -> Void)?
    /// Is there a finished take to play? Only ever one — the last.
    var isReplayable: (() -> Bool)?
    var isReplaying: (() -> Bool)?

    /// Picked from **Connect Terminal** — the same call ⌘⌃B and the left-plus-wheel
    /// chord make.
    var onBind: (() -> Void)?

    /// **The rows of *Rebind to*, asked for at the instant the list is opened.**
    ///
    /// Asked and not told, like the footprint and the recording flag above — but
    /// for a stronger reason than either: building these costs an AppleScript
    /// round trip across every Terminal.app window, and Victor's condition on the
    /// whole feature was that the *menu bar* stay instant (*"se poate calcula
    /// conținutul acelui meniu doar când apăs pe el să-l expandezi"*). Clicking
    /// the row is the moment that honours it; `menuWillOpen` on the menu that
    /// carries the row is already too early.
    var rebindRows: (() -> [RebindHistory.Row])?

    /// Picked from a row of *Rebind to* — point the relay back at that tty.
    var onRebind: ((String) -> Void)?

    /// **`ttysNNN` → the title that tab is showing now**, for the panel's second
    /// half: a session found in a transcript is only bindable if the tab it ran
    /// in is still that session's, and the title is what says so. Asked at the
    /// opening, like the rows above it and for the same AppleScript reason.
    var liveTitles: (() -> [String: String])?

    /// A word for the overlay, from the panel — the beat between ⏎ and a window
    /// appearing is the one moment it has nothing else to show.
    var onRebindMessage: ((String) -> Void)?

    /// **Picked a session whose terminal is closed** — open it again with
    /// `claude --resume <id>` in the folder it belongs to, and bind to it.
    var onResumeSession: ((_ session: String, _ cwd: String) -> Void)?

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// **The menu is where the gestures are written down.** Every one of these
    /// commands also has a mouse or keyboard route, and none of those routes
    /// announces itself anywhere else: ⌘⌃B shadows a system shortcut, and the
    /// wheel means one thing alone, another held, and a third with the left
    /// button already down — none of which anybody guesses. A menu row is read
    /// while reaching for the thing it does, which makes it the one place a
    /// gesture can be learned without being taught.
    ///
    /// **Since 2026-11-12 no row carries a chord** — the shortcut column of
    /// one-glyph gestures went with the legend rows, and the gestures are taught
    /// by `GestureGuide`, drawn on his mouse.
    private let bind = NSMenuItem(title: "Bind Terminal", action: nil, keyEquivalent: "")

    /// **Rebind to** — every destination the relay has spoken to, most recent
    /// first, with how long ago it let go of each.
    ///
    /// **Why a list of the past rather than a search of the present.** Victor
    /// runs fifteen to twenty Claude Code sessions a day and loses track of which
    /// window did what; the first design here was a Spotlight-style box that
    /// described a session out loud and had a model pick it. This replaced it
    /// because the answer turned out not to need a model: the destinations he
    /// might mean are exactly the ones he has already spoken to, they are few,
    /// and each one already carries a title its agent keeps rewriting to say what
    /// it is doing. See `RebindHistory`.
    /// **It pops the list up rather than carrying it as a submenu, and the reason
    /// is the rest of the menu.** Attached as a submenu this row was correct and
    /// cost nothing to open — but AppKit reserves the disclosure-arrow gutter on
    /// **every row of the menu** the moment one item has a submenu, and this menu
    /// spends its right-hand side on the gesture column. One arrow moved all of
    /// it (Victor, 2026-09-10: *"a fugit toată coloana de meniuri din cauza >"*).
    /// The chords have since left the menu altogether (2026-11-12), so an arrow
    /// costs nothing any more. The row stays a pop-up on its own merits, below.
    ///
    /// A popped-up menu keeps everything the submenu was for — it is still built
    /// at the instant it is asked for, never when the menu bar is clicked — and
    /// the `…` is what the row says instead of the arrow.
    private let rebind = NSMenuItem(title: "Rebind to…", action: nil, keyEquivalent: "")

    /// **The list itself** (2026-09-12): a panel with a search field, because a
    /// menu could not be typed into and *"trebuie să pot să încep să tastez
    /// direct"*. Kept as one object rather than made per click — it holds the
    /// scan it started, and that has to be cancellable from the next keystroke.
    private let rebindPanel = RebindPanel()

    /// Let go of the terminal without ending the session — the menu's answer to
    /// ⌘⌃B pressed on the bound target, minus the quitting.
    ///
    /// The gesture is in the title for the reason **Connect Terminal** carries
    /// its own: a wheel chord has no key equivalent to be right-aligned as, and
    /// the menu is now the only place any gesture is written down. Right mirrors
    /// left the way disconnecting mirrors binding — that is the whole of what has
    /// to be remembered, and drawn as `➡️` against `⬅️` it is the whole of what
    /// has to be read.
    private let disconnect = NSMenuItem(title: "Disconnect", action: nil, keyEquivalent: "")
    /// Ends the dictation the relay is recording itself — Local Whisper only,
    /// see the comment at the row's construction.
    private let stopRecording = NSMenuItem(title: "End Dictation", action: nil, keyEquivalent: "")
    /// Same row, opposite verdict — see `onCancelDictation`.
    private let cancelDictation = NSMenuItem(title: "Cancel Dictation", action: nil, keyEquivalent: "")
    /// The undo of the row above it, and directly under it for that reason.
    private let recoverDictation = NSMenuItem(title: "Recover Dictation",
                                              action: nil, keyEquivalent: "")
    /// One row that renames itself, like `Record Screen`: one verb, one thing playing.
    private let replayLast = NSMenuItem(title: "Replay Last Dictation",
                                        action: nil, keyEquivalent: "")
    /// The last dictation, again — see `AppDelegate.pasteLastDictation`. Greyed
    /// until there is one, like every other row that cannot act right now.
    private let pasteLast = NSMenuItem(title: "Paste last prompt", action: nil, keyEquivalent: "")
    /// **Send without asking.** Off at every launch, and deliberately not
    /// remembered: the panel is the thing that catches a transcript the model got
    /// wrong, and a checkbox that survived a restart would quietly take that
    /// safety net away weeks after it was ticked, in a session where he had
    /// forgotten it existed.
    ///
    /// Ticked, the panel still opens — it is the receipt, and a dictation that
    /// vanished into a terminal with nothing shown would be the one state where
    /// he cannot tell a delivery from a drop — but it opens for a second, with no
    /// buttons on it. A flash, then it goes.
    ///
    /// **The mode rides in the icon column, not in the checkmark column.** A
    /// ticked `NSMenuItem` makes AppKit reserve the state column for the whole
    /// menu, which pushes every other row — all of them already carrying an
    /// emoji — sideways the moment this one row is switched on. The layout
    /// shifting under him is a worse readout than the tick was a good one, so
    /// the state is drawn where the other rows draw their identity — and since
    /// 2026-09-07 that drawing is a **`checkmark`**, the same mark `Wrap Wispr
    /// Flow` carries (Victor: *"autosend să aibă bifă în față, nu ⏩ când e
    /// activ"*).
    ///
    /// It was `⏩` for an afternoon, on the argument that the icon column is
    /// where a row draws *what it is* — and that is right for a row like
    /// `Take Screenshot`, whose picture never changes. These two are not that:
    /// they are the menu's only **switches**, so the one fact their column has
    /// to carry is on or off. A glyph that illustrates the behaviour makes the
    /// reader decode a picture to answer a yes/no question, and it makes the two
    /// switches look like two unrelated rows when they are the same kind of
    /// thing. A tick is read without being read.
    ///
    /// **And nothing at all when it is off** (Victor, 2026-09-07 — *"by default
    /// să nu aibă nimic în față"*). It was `⏸️` for the off half, which is the
    /// same mistake the ✕ would have been one row up: a picture in the column
    /// claims the row is *doing* something, and off is precisely the state in
    /// which this row does nothing — the panel holding for its three seconds is
    /// the app's ordinary behaviour, not a mode. Blank is still an image of the
    /// column's exact size (`blankIcon`), so the title does not step sideways
    /// when the mode comes on.
    private let autosend = NSMenuItem(title: "Autosend", action: nil, keyEquivalent: "")
    /// Mirrors what the `autosend` row means, since the row itself no longer
    /// carries a `state` to read it back from.
    ///
    /// **It survives a restart** (Victor, 2026-09-07). It deliberately did not,
    /// for two weeks, and the argument was a real one: the panel is what catches
    /// a transcript the model got fluently wrong, and a tick that came back on
    /// its own would quietly take that away weeks later, in a session where he
    /// had forgotten it was set. He has now ticked it back on after enough
    /// restarts to overrule that — the reading it was protecting against is one
    /// he makes deliberately, and re-making the same choice every launch is a
    /// worse tax than the risk it was buying off.
    private var autosendOn = UserDefaults.standard.bool(forKey: StatusItem.autosendKey)
    /// One of the two keys this app keeps in `UserDefaults`. They are
    /// *preferences* rather than data, so they do not belong in
    /// `~/.walkie-talkie` beside the outbox and the corpus, and `--home` has no
    /// business moving them.
    private static let autosendKey = "autosend"

    /// What the row is set to right now — read once at launch by `AppDelegate`,
    /// so the restored tick and the behaviour behind it start out agreeing.
    /// Every later change arrives through `onToggleAutosend`.
    var isAutosend: Bool { autosendOn }
    // ── Dictation engine ────────────────────────────────────────────────────

    /// **Which recogniser is listening — a choice, not a tick** (2026-09-14).
    ///
    /// The row this replaces was `Replace WisprFlow`: one checkbox that read, to
    /// the hand on the mouse, as *Wispr Flow — yes or no*. Victor asked for the
    /// distinction a boolean cannot draw — *"nu mai trebuie să fie un checkbox
    /// «Wispr» sau nu, ci un submeniu din care să aleg modelul de utilizat …
    /// așa se vede și numele modelului, dacă mă întreabă cineva ce folosesc"*.
    /// A tick names one of the two engines and leaves the other one unnamed,
    /// and the unnamed one is exactly what he is asked about in a room.
    ///
    /// So the row **says which engine is running**, and opens the list of both:
    ///
    /// ```
    ///   Engine: ElevenLabs
    ///          whisper-large-v3-turbo — 1.6 GB RAM
    ///        ✓ ElevenLabs scribe_v1 — $0.40/h ☁️
    /// ```
    ///
    /// **Wispr Flow is not one of them since 2026-09-22** — Victor:
    /// *"scoate wisprflow ca sursă de dictare din lista de Engine — n-am reușit
    /// niciodată să-l integrăm ca lumea în fluxul nostru să-i preluăm ce text
    /// injectează."* See `applyEngineRow` for why, and for what Wispr keeps.
    ///
    /// **It is an ordinary submenu, with the arrow** — *"tre submeniu obișnuit
    /// cu >, nu un modal"* (Victor, 2026-09-14, having looked at the other one).
    ///
    /// It was a dispatched `popUp` for one build, on `Rebind to…`'s reasoning:
    /// one disclosure arrow makes AppKit reserve the gutter on *every* row and
    /// the gesture column shifted with it (2026-09-10: *"a fugit toată coloana de
    /// meniuri din cauza >"*; the chords live inside that gutter since
    /// 2026-09-22, so the argument no longer holds anywhere). That argument was
    /// carried over rather than re-tested, and what it bought here is a list
    /// that appears detached from the row it came from — which reads as a modal,
    /// not as a branch of the menu. The gutter is the cheaper of the two costs
    /// when the list is **two rows he picks between**, and `Rebind to…` keeps
    /// its pop-up because its list is long, live and searched.
    ///
    /// **The caret-paste mode went with the row it replaced.** It is still the
    /// forward button's meaning and still `AppDelegate.replaceWispr`, read from
    /// the same preference key — what it has not got any more is a place in this
    /// menu to be ticked, which is Victor's call of 2026-09-14.
    private let engineItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")

    /// **`Last used: ☁️ ElevenLabs Scribe (scribe_v2)`, directly under `Engine`**
    /// (2026-10-29, Victor: *"vreau să văd în meniu Last used ce engine a fost
    /// folosit la ultima dictare sau promptare"*). The row above says what is
    /// picked; this one what actually wrote the last sentence — they differ
    /// exactly when the local model stood in (fallback, ⌘⌃X, the countdown).
    /// A readout, never clickable.
    private let lastUsedItem = NSMenuItem(title: "Last used: —", action: nil, keyEquivalent: "")

    /// **The two rows under the arrow**, rebuilt by `applyEngineRow` rather than
    /// by a delegate of its own: the names change only with the model's
    /// footprint, which `menuWillOpen` already re-reads for the row above.
    private let engineSubmenu = NSMenu()

    /// Which engine is live, as `AppDelegate` last reported it — `whisper` or
    /// `eleven`.
    ///
    /// **The tick is drawn from the app's answer, never from the click.** A
    /// switch asked for mid-sentence is refused, and a row that had ticked
    /// itself optimistically would be the only thing in the app claiming an
    /// engine that is not listening.
    private var engineId = "eleven"

    /// Victor picked one. `AppDelegate` swaps the source and calls `setEngine`
    /// back with whatever is actually running afterwards.
    var onPickEngine: ((String) -> Void)?

    /// **`Prepare local transcript (p95)`** (2026-09-28 as *Auto fallback to local (p98)*; renamed 2026-09-29) — the checkbox under the
    /// engines; the new value. `AutoLocal.isOn` is the truth, read at every build.
    var onToggleAutoLocal: ((Bool) -> Void)?

    // MARK: - Microphone (2026-09-19)

    /// **`Microphone: 🎙️ Elgato Wave XLR`, with the four devices under the
    /// arrow** — Victor's ask of 2026-09-19, the half of it that is not the
    /// chip: *"and source should be selectable via menu too. those unavailable
    /// disabled"*.
    ///
    /// **Directly under `Engine`, and that is the whole of the placement
    /// argument.** The row above answers *what is listening to me*; this one
    /// answers *through what*. They are the same question one level apart, they
    /// are the two halves of the mark the chip now wears (`Listening(🎙️/E)...`),
    /// and a man who has just read one of them off the chip and come to the menu
    /// to change it should not have to hunt for the second.
    ///
    /// **The list is the four he named, never the whole of CoreAudio.** This Mac
    /// answers with fifteen inputs, eleven of them virtual — Loopback's three,
    /// Wave Link's two, Zoom's, Teams', Webex's, Iriun's — and a menu that
    /// offered all of them would be a device chooser, which System Settings
    /// already is and does better. What it would not be is *readable at a
    /// glance while he is teaching*, which is the one thing this menu is for.
    private let micItem = NSMenuItem(title: "Mic", action: nil, keyEquivalent: "")

    private let micSubmenu = NSMenu()

    /// What he picked — `auto` or one of `InputDevice.known`'s ids. Pushed in by
    /// `AppDelegate`, never set from the click, for the tick's reason under
    /// `engineId`.
    private var micChosen = "auto"

    /// Which of the four are plugged in **right now**, and what the top row
    /// should say. Both asked when the menu opens rather than remembered: a
    /// receiver goes into the port between two openings of this menu, and a list
    /// that greys a device he is holding in his hand is worse than no list.
    var micAvailable: (() -> Set<String>)?
    var micCurrentLabel: (() -> String)?

    /// Victor picked one. `AppDelegate` stores it and calls `setMic` back.
    var onPickMic: ((String) -> Void)?

    func setMic(_ id: String) {
        micChosen = id
        applyMicRow()
    }

    /// The row's title alone — what `DjiBattery`'s answer repaints. The DJI's
    /// transmitter battery rides after its name, as in Victor Addons' menu
    /// (2026-10-07): `Mic: 🎤 DJI 80 %`.
    private func applyMicTitle() {
        var title = "Mic: \(micCurrentLabel?() ?? "—")"
        if InputDevice.resolve().known?.id == "rx", let battery = DjiBattery.suffix { title += " \(battery)" }
        micItem.title = title
    }

    /// `Microphone: 🎙️ Elgato Wave XLR` — **the device that would record right
    /// now**, which is not always the one ticked: a pick whose device has been
    /// unplugged falls back to automatic (`InputDevice.resolve`), and the row
    /// has to say what would actually happen rather than what was once asked
    /// for. The tick below stays on his choice, so the two together read as
    /// *you asked for the receiver, you are on the built-in* — which is the
    /// sentence he needs when a cable has come out.
    private func applyMicRow() {
        applyMicTitle()
        micSubmenu.removeAllItems()
        let available = micAvailable?() ?? []

        // **Automatic first, and it spells the ladder out**: `Automatic — 🎙️ ▸
        // 🎤 ▸ 🎧 ▸ 💻` is the same order as the four rows under it, which is
        // the point — the list he reads *is* the preference (`InputDevice.known`).
        // Never disabled: it is the one row that is true whatever is on the desk.
        let auto = NSMenuItem(title: "Automatic — \(InputDevice.ladder)",
                              action: #selector(micPicked(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = "auto"
        auto.image = micChosen == "auto" ? Self.symbolIcon("checkmark") : Self.blankIcon
        micSubmenu.addItem(auto)
        micSubmenu.addItem(.separator())

        for device in InputDevice.known {
            let here = available.contains(device.id)
            // **The absent ones say why they are grey.** A disabled row with no
            // explanation is indistinguishable from a broken one, and the
            // explanation is the only thing he can act on — it is a cable.
            let row = NSMenuItem(title: here ? "\(device.glyph) \(device.label)"
                                             : "\(device.glyph) \(device.label) — not connected",
                                 action: #selector(micPicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = device.id
            row.isEnabled = here
            row.image = device.id == micChosen ? Self.symbolIcon("checkmark") : Self.blankIcon
            micSubmenu.addItem(row)
        }
    }

    /// **The rows as AppKit actually holds them**, for `GET /engine.mic.rows`.
    ///
    /// It exists because *unavailable devices are greyed* is a claim about a
    /// menu, and a menu is the one surface in this app that cannot be
    /// photographed from a shell — `NSMenu` draws in the window server, on a
    /// click, over whatever is in front. The flag AppKit is holding is the whole
    /// of the fact, and reading it back is the difference between having set
    /// `isEnabled` and having a disabled row (`autoenablesItems`, above, is
    /// exactly the gap between those two).
    func micRowsForTest() -> [[String: Any]] {
        micSubmenu.items.filter { !$0.isSeparatorItem }.map {
            ["title": $0.title,
             "enabled": $0.isEnabled,
             "ticked": ($0.representedObject as? String) == micChosen]
        }
    }

    /// `GET /engine.engineRows` — the Engine list as AppKit holds it after a
    /// rebuild: every row's title and whether it wears the tick (2026-10-03).
    func engineRowsForTest() -> [[String: Any]] {
        applyEngineRow()
        return engineSubmenu.items.map { item -> [String: Any] in
            if item.isSeparatorItem { return ["title": "—"] }
            return ["title": item.title, "ticked": item.image != nil && item.image !== Self.blankIcon]
        }
    }

    @objc private func micPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != micChosen else { return }
        onPickMic?(id)
    }

    /// Push the live engine in — at launch, from `WT_SOURCE`, or after a switch
    /// that was refused and left the old one in place.
    func setEngine(_ id: String) {
        engineId = id
        applyEngineRow()
    }

    /// **Mouse Gestures: Logi / Wheel** — which mouse the app thinks it is
    /// holding, said as a choice rather than as a tick (2026-09-14).
    ///
    /// It was the checkbox `Use Logi Gestures`, and it had `Engine`'s old
    /// problem: a tick names one of the two wirings and leaves the other one
    /// unnamed, so *off* was a state with no word for it — the row could not say
    /// that the alternative is the wheel carrying the dictation, only that Logi
    /// is not doing it. Victor asked for the shape the engine row already has
    /// (*"cu submeniu din care aleg cele 2 variante (ca la Engine)"*), and the
    /// two rows under the arrow are where each wiring gets its name.
    ///
    /// Logi (the default): the side buttons arrive as ⌃⌥⌘F3…F12 from Logi
    /// Options+ custom gestures, and every mouse button is passed straight
    /// through — the wheel included, which is what gives middle-click back to
    /// Chrome and VS Code. Unticked: the pre-2026-09-09 wiring, where the wheel
    /// carries the dictation and the left and right buttons are chord modifiers.
    ///
    /// **Both sets are live code.** Victor asked for the old one kept rather than
    /// deleted (*"tine-le pt moment comentate pe cele vechi, sau cu feat togle"*),
    /// and the case it is kept for is a real one: the Logi gestures live in an
    /// Options+ profile, and a Mac without that profile — a fresh install, a
    /// machine in a training room — has no side buttons at all until it is
    /// rebuilt. The second row is the way back in the meantime.
    ///
    /// **Defaults to Logi, and that needs saying** because `bool(forKey:)`
    /// answers false for a key that was never written, which would have shipped
    /// the old gestures to a Mac already configured for the new ones.
    private let logiGestures = NSMenuItem(title: "Gestures", action: nil, keyEquivalent: "")

    /// **The two wirings under the arrow**, rebuilt by `applyLogiGesturesRow`
    /// for `applyEngineRow`'s reason: there are two of them, they are short, and
    /// keeping the tick honest is one loop rather than a delegate.
    private let gesturesSubmenu = NSMenu()
    private var logiGesturesOn: Bool =
        UserDefaults.standard.object(forKey: StatusItem.logiGesturesKey) as? Bool ?? true
    private static let logiGesturesKey = "useLogiGestures"

    /// What the row is set to right now — read once at launch by `AppDelegate`,
    /// like `isReplaceWispr`.
    var isLogiGestures: Bool { logiGesturesOn }

    // MARK: - Halo (2026-09-20)

    /// **`Halo: Lightning ring`, with the nine effects ported from the
    /// `voice-halo` page under the arrow** — the shape `Engine` and `Mouse
    /// Gestures` have: the row says what is drawn round the pointer, the list
    /// is where it is changed, the tick is on the chosen row and drawn as an
    /// icon rather than `NSMenuItem.state`, for the column's sake.
    ///
    /// **The first row is today's ring and the default**; the rest are in the
    /// order Victor ranked them. The preference is `HaloStyle`'s own
    /// (`UserDefaults`, `haloStyle`), written by `CaretHalo.setStyle` — this
    /// row reads it back on every open, so the tick is what is running.
    /// **One list** (Victor, 2026-09-20: *"implement in Walkie Talkie the
    /// effects you have … As a new menu, call it Halo fx"* — his spelling,
    /// lowercase `fx` — and then *"there must be ONE menu, not 2: and the
    /// MilkDrop ones should have a lightning bolt in the name"*). The film
    /// first and apart, the page's hand-written effects, a line, the presets
    /// with their ⚡ (`HaloStyle.menuTitle`). The row reads out the pick.
    /// **`fx` in a mathematical script** (2026-09-22) — Victor: *"mi-ar plăcea
    /// un font matematic mai elegant pt fx"*, picked off six rendered options:
    /// bold script 𝓯 (U+1D4EF) and bold fraktur 𝔁 (U+1D501). Unicode rather than
    /// an attributed title, because `title` is rewritten from `applyHaloRow` and
    /// a font run would have to be rebuilt with it every time.
    /// **Just `𝓯𝔁` since 2026-09-28** — Victor: *"instead of Halo FX, let's say
    /// FX. No ellipses, no other words, just the FX stylish font"*. The
    /// `sparkles` icon beside it says what kind of effect.
    static let haloFx = "𝓯𝔁"
    private let haloItem = NSMenuItem(title: StatusItem.haloFx, action: nil, keyEquivalent: "")
    private let haloSubmenu = NSMenu()

    /// Victor picked one — for one destination, or, from the top-level list,
    /// for all three at once (`nil`). `AppDelegate` hands it to the halo.
    var onPickHalo: ((HaloStyle, HaloDestination?) -> Void)?

    /// **Five rows, every one of them a submenu** (Victor, 2026-09-21 evening:
    /// *"să aibă doar cinci subcopii, care copiii să fie, la rândul lor,
    /// submeniuri … despre ce efect, în ce moment, și apoi motorul"*): one per
    /// destination — the *moment* a dictation happens — and `Fx engine` last.
    /// Each reads out its own pick and carries the one list under its arrow.
    ///
    /// **The flat list of styles that used to sit on top is gone with it.** It
    /// was the *set all of them at once* shortcut (2026-09-21 morning: *"dacă îl
    /// selectez precis, atunci toate trei sunt puse pe același"*), and it was
    /// also the reason this submenu opened onto a dozen rows of effects with
    /// the four destinations buried under them. Four destinations is four
    /// picks; the shortcut is not worth the wall.
    ///
    /// Each row is rebuilt on every open for `applyEngineRow`'s reason: the
    /// tick has to be what is running, and a preference can change from the
    /// wheel between two opens.
    private func applyHaloRow() {
        let picks = HaloDestination.allCases.map { HaloStyle.current(for: $0) }
        // **`Halo 𝓯𝔁 when…`, and the rows finish the sentence** (2026-09-22,
        // Victor) — `At caret: Tunnel`, `Bounded: Tendrils`. No readout on the
        // parent any more: the four are four answers, and the one shared answer
        // it used to print has not been the case since each destination got its own.
        // **Since 2026-09-28 the row is `𝓯𝔁` alone** — no `Halo`, no `when…`
        // (*"no ellipses, no other words"*); the rows under it still read
        // `At caret: Tunnel`.
        haloItem.title = Self.haloFx
        haloSubmenu.removeAllItems()
        haloSubmenu.autoenablesItems = false
        // **`Disable on Battery`, first and ticked by default** (2026-10-20,
        // Victor: *"On the battery I should not see any animation on my
        // desktop. It eats the battery."*) — `BatteryFx`. The tooltip says
        // whether it is holding them right now.
        let battery = NSMenuItem(title: "Disable on Battery", action: #selector(batteryFxClicked), keyEquivalent: "")
        battery.target = self
        battery.image = BatteryFx.isOn ? Self.symbolIcon("checkmark") : Self.blankIcon
        battery.toolTip = BatteryFx.holdsEffects
            ? "On battery now — no effects are drawn until the Mac is plugged in."
            : "No effects are drawn while the Mac runs on battery\(BatteryFx.onBattery ? " (it is on battery now)" : "")."
        haloSubmenu.addItem(battery)
        haloSubmenu.addItem(.separator())
        for (destination, pick) in zip(HaloDestination.allCases, picks) {
            let row = NSMenuItem(title: "\(destination.title): \(pick.menuTitle)", action: nil, keyEquivalent: "")
            let list = NSMenu()
            list.autoenablesItems = false
            fillStyleRows(into: list, ticked: pick, destination: destination)
            row.submenu = list
            haloSubmenu.addItem(row)
        }
        // **`Transcribing: Dust`** (2026-11-13) — what stands in the prompt's
        // corner while the words are transcribed (`CornerTunnel.Dress`).
        let corner = CornerTunnel.dress
        let cornerRow = NSMenuItem(title: "Transcribing: \(corner.title)", action: nil, keyEquivalent: "")
        cornerRow.toolTip = "What plays in the top-left corner, where the prompt rests, while the words are transcribed."
        let cornerList = NSMenu()
        cornerList.autoenablesItems = false
        for dress in CornerTunnel.Dress.allCases {
            let pick = NSMenuItem(title: dress.title, action: #selector(cornerFxPicked(_:)), keyEquivalent: "")
            pick.target = self
            pick.representedObject = dress.rawValue
            pick.image = dress == corner ? Self.symbolIcon("checkmark") : Self.blankIcon
            cornerList.addItem(pick)
        }
        cornerRow.submenu = cornerList
        haloSubmenu.addItem(cornerRow)
        // **`Fx engine`, last row of the same submenu** (Victor, 2026-09-21:
        // *"pune fx engine sub halo effects (în submeniu)"*) — one level down
        // from the styles, not a sibling row in the main menu.
        haloSubmenu.addItem(.separator())
        haloEngineItem.submenu = haloEngineSubmenu
        applyHaloEngineRow()
        haloSubmenu.addItem(haloEngineItem)
        // **`Fx voice`, lângă `Fx engine`** — ce AUDE motorul, nu ce desenează.
        haloVoiceItem.submenu = haloVoiceSubmenu
        applyHaloVoiceRow()
        haloSubmenu.addItem(haloVoiceItem)
    }

    /// The one list of effects, drawn into a menu. A row is greyed, and says
    /// why, while the page or the engine is not bundled (`HaloPage.available`,
    /// `MilkDropHalo.engineAvailable`) — `autoenablesItems` off for the mic
    /// submenu's reason. One list, no group line; a preset carries a bolt
    /// after its name. `destination` nil means *the pick sets all three*.
    private func fillStyleRows(into menu: NSMenu, ticked: HaloStyle?, destination: HaloDestination?) {
        for style in HaloStyle.offered {
            let row = NSMenuItem(title: style.unavailableReason.map { "\(style.menuTitle) — \($0)" } ?? style.menuTitle,
                                 action: #selector(haloPicked(_:)), keyEquivalent: "")
            if style.isPreset && style.isAvailable { row.attributedTitle = Self.boltedTitle(style.menuTitle) }
            row.target = self
            row.representedObject = "\(destination?.rawValue ?? "all"):\(style.rawValue)"
            row.isEnabled = style.isAvailable
            row.image = style == ticked ? Self.symbolIcon("checkmark") : Self.blankIcon
            menu.addItem(row)
            // The films first and apart: the two drawn natively.
            if style == .questionMark { menu.addItem(.separator()) }
        }
    }

    /// **`Halo engine: Web`, the shape `Engine` has** (the `projectm` branch,
    /// 2026-09-21): which engine draws a MilkDrop preset — butterchurn in a
    /// web view, or projectM natively. A readout with the two under the
    /// arrow, the tick drawn from `HaloEngine.current` on every open, so a
    /// `WT_HALO_ENGINE` run shows what is running. The film and the page
    /// effects are unaffected by it; the row says so.
    private let haloEngineItem = NSMenuItem(title: "Engine", action: nil, keyEquivalent: "")
    private let haloEngineSubmenu = NSMenu()
    var onPickHaloEngine: ((HaloEngine) -> Void)?

    private func applyHaloEngineRow() {
        let current = HaloEngine.current
        // **`Engine ⚡: projectM`** (2026-09-22) — the bolt the presets wear,
        // saying *this is about them* where a disabled `For the MilkDrop presets
        // only` row under the list used to (*"scoate din submeniu «for the …»"*).
        let engineTitle = NSMutableAttributedString(attributedString: Self.boltedTitle("Engine"))
        engineTitle.append(NSAttributedString(string: ": \(Self.haloEngineShortTitle(current))",
                                              attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        haloEngineItem.attributedTitle = engineTitle
        haloEngineSubmenu.removeAllItems()
        haloEngineSubmenu.autoenablesItems = false
        for engine in [HaloEngine.web, .native] {
            let row = NSMenuItem(title: Self.haloEngineTitle(engine), action: #selector(haloEnginePicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = engine.rawValue
            row.image = engine == current ? Self.symbolIcon("checkmark") : Self.blankIcon
            haloEngineSubmenu.addItem(row)
        }
    }

    /// The readout's word for the same engine — the detail in the parentheses
    /// belongs to the list, where the two stand side by side (Victor,
    /// 2026-09-22: *"doar «projectM», că deja știu cine e"*).
    private static func haloEngineShortTitle(_ e: HaloEngine) -> String {
        switch e {
        case .web:    return "Web"
        case .native: return "projectM"
        }
    }

    private static func haloEngineTitle(_ e: HaloEngine) -> String {
        switch e {
        case .web:    return "Web (butterchurn)"
        case .native: return "projectM (native)"
        }
    }

    /// **`Halo voice`, sub `Halo engine`** (2026-09-21): ce se face cu vocea
    /// ÎNAINTE să ajungă la motor. Presetele MilkDrop sunt desenate pentru muzică
    /// și el vorbește — măsurat pe corpusul lui, doar 3,2% din energia vocii stă
    /// sub 120 Hz, unde o tobă pune 30–50%. Rândul e al rutei NATIVE: acolo se
    /// așează efectele adevărate, web view-ul e doar previzualizarea din care își
    /// alege efectul.
    private let haloVoiceItem = NSMenuItem(title: "Filter", action: nil, keyEquivalent: "")
    private let haloVoiceSubmenu = NSMenu()
    var onPickHaloVoice: ((HaloVoice) -> Void)?

    private func applyHaloVoiceRow() {
        let current = HaloVoice.current
        haloVoiceItem.title = "Filter: \(current.title)"
        haloVoiceSubmenu.removeAllItems()
        haloVoiceSubmenu.autoenablesItems = false
        for voice in HaloVoice.allCases {
            let row = NSMenuItem(title: voice.title, action: #selector(haloVoicePicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = voice.rawValue
            row.image = voice == current ? Self.symbolIcon("checkmark") : Self.blankIcon
            haloVoiceSubmenu.addItem(row)
        }
    }

    @objc private func cornerFxPicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let dress = CornerTunnel.Dress(rawValue: raw) else { return }
        CornerTunnel.setDress(dress)
        applyHaloRow()
    }

    @objc private func batteryFxClicked() {
        BatteryFx.set(!BatteryFx.isOn)
        applyHaloRow()
    }

    @objc private func haloVoicePicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let voice = HaloVoice(rawValue: raw),
              voice != HaloVoice.current else { return }
        onPickHaloVoice?(voice)
        applyHaloVoiceRow()
    }

    @objc private func haloEnginePicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let engine = HaloEngine(rawValue: raw),
              engine != HaloEngine.current else { return }
        onPickHaloEngine?(engine)
        applyHaloEngineRow()
        applyHaloVoiceRow()
    }

    @objc private func haloPicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let style = HaloStyle(rawValue: parts[1]) else { return }
        // `all` is the top-level list: it sets the three together, and it is
        // worth running even when one of them already holds this style.
        let destination = HaloDestination(rawValue: parts[0])
        if let destination = destination, style == HaloStyle.current(for: destination) { return }
        onPickHalo?(style, destination)
        applyHaloRow()
    }
    /// The tap has to be told; `AppDelegate` owns that wire.
    var onToggleLogiGestures: ((Bool) -> Void)?

    // ── Wrap Wispr Flow: gone from the menu (2026-09-14) ────────────────────
    //
    // **"elimina *Wrap Wispr Flow* din meniu. e redundant vs submeniul introdus
    // de curand"** (Victor). The tick asked *does the relay take Wispr's paste
    // and deliver the words itself*, and with `Engine` under an arrow the two
    // rows read as one question asked twice: picking **Wispr Flow** as the
    // engine is picking the wrap, because the wrap is how this app talks to
    // Wispr — the Scratchpad, the swallow, the row-first delivery. There is no
    // product left in the *off* half of that tick; it is the control the loop
    // uses (`wrap-off`), and a control belongs in `POST /test/wrap-mode` and
    // `WT_WRAP_WISPR=0`, both of which stay.
    //
    // `WisprFlowSource.wrapWispr` is untouched and still defaults to **on**.
    // What is gone is the menu row, its `wrapWispr` preference key — a stale
    // `false` in it would now be unreachable from the UI, so it is no longer
    // read at all — and the two accessors `AppDelegate` drove it through.

    // ── Close Wispr Scratchpad: gone from the menu (2026-09-14) ─────────────
    //
    // **"Close wisprflow scratchpad menu < sterge!"** (Victor). It was a row he
    // clicked because the relay had not been given leave to close another app's
    // window on its own — and by now it closes it on its own anyway, at the end
    // of every wrapped dictation (`closeScratchpadAfterwards`) and through the
    // idle sweep. What was left in the menu was a button for a job already done,
    // whose only remaining use was clicking it after the automatic close had
    // failed — and a failed close reopens the window on the next click, because
    // the chord is a toggle.
    //
    // `WisprScratchpad.ensureClosed` is untouched; what is gone is the row, its
    // callback, and `AppDelegate`'s wire into it.

    /// **The outbox, read back as a page.** Renders the last two days of
    /// `outbox.jsonl` into one self-contained HTML file and opens it in the
    /// browser — see `MessageLog`.
    ///
    /// It sits under the two switches rather than with the commands at the top:
    /// everything above the first separator is about *where the next sentence
    /// goes*, and everything under the second is about the app itself — its
    /// modes, its engine, its build. A log of what was already said is a fact
    /// about the app, not a destination.
    ///
    /// **It carries no callback.** Every other row hands its click to
    /// `AppDelegate` because it needs state only the delegate has; this one needs
    /// nothing but the file on disk, and a hop through the delegate would exist
    /// only to be consistent with rows that had a reason.
    ///
    /// **`Prompt History`, with the page one row inside it** (Victor,
    /// 2026-09-17). The row used to be `Prompt Log` and its only act was to open
    /// the HTML page — a click that leaves the menu, opens a browser and lands
    /// on a file, for the question that is usually *what did I just say?*. Under
    /// the arrow the last sentences are their own rows, first words and an
    /// ellipsis, and the page is the row above the line: the whole log is still
    /// exactly one click away, and reading back the last dozen prompts no longer
    /// costs a browser.
    private let messageLog = NSMenuItem(title: "Prompt History", action: nil, keyEquivalent: "")

    /// **The page, a line, and the last sentences** — rebuilt on
    /// `menuNeedsUpdate` rather than kept in step, for `applyEngineRow`'s reason
    /// twice over: the list is short, and its source is a file another process
    /// appends to all day, so the only reading that can be trusted is the one
    /// taken at the moment the arrow is hovered.
    private let promptHistorySubmenu = NSMenu()

    /// **The build stamp, one row above Quit**, reading `Version: <build>` — the
    /// same plain readout all three menu bar apps end with (2026-09-13), which is
    /// why it stopped being the old `Victor's Walkie Talkie (<build>)` About row.
    ///
    /// **It opens the About page again since 2026-09-22**, and the title stayed
    /// plain: the row is still the version readout, it has simply stopped being
    /// the only dead row in the menu. What made it worth clicking is what the page
    /// now holds — a drawing of the mouse with every button named — which is the
    /// legend the gesture rows themselves gave up when their chords moved into
    /// AppKit's shortcut column, where a row gets one glyph and no more. The
    /// vocabulary has to live somewhere it can be drawn full size; this is the
    /// row that leads there, and the `info.circle` beside it already promised as
    /// much.
    private let version = NSMenuItem(title: "Built \(StatusItem.buildStamp)",
                                     action: nil, keyEquivalent: "")
    /// Opens `GestureGuide` (2026-11-12).
    private let guide = NSMenuItem(title: "Gesture Guide", action: nil, keyEquivalent: "")

    /// **The engine switches, top level since 2026-11-12** — they sat under
    /// `Engine` beside the engines; `applySwitchRows` ticks them at every open.
    private let autoLocalRow = NSMenuItem(title: AutoLocal.menuTitle, action: nil, keyEquivalent: "")
    private let liveRow = NSMenuItem(title: LocalLive.menuTitle, action: nil, keyEquivalent: "")
    private let editorRow = NSMenuItem(title: "✍️ Edit plain dictation (Haiku)", action: nil, keyEquivalent: "")
    private let wakeRow = NSMenuItem(title: WakeWord.menuTitle, action: nil, keyEquivalent: "")
    private let faceRow = NSMenuItem(title: FaceRead.menuTitle, action: nil, keyEquivalent: "")
    private var engineLoading = false
    /// Whether the relay is pointed at a terminal, which is what the two icons
    /// distinguish. Set from the same `setDestination` the header uses, so the
    /// picture in the menu bar and the line inside the menu cannot disagree.
    private var isBound = false

    override init() {
        super.init()
        // The states shooter shows nothing, the menu bar included (`Offstage`).
        if RelayWindow.shooting { item.isVisible = false }

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
        item.button?.image = Self.boundIcon
        GestureGuide.logiGesturesOn = logiGesturesOn
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

        bind.image = Self.symbolIcon("link")
        bind.action = #selector(bindClicked)
        bind.target = self
        menu.addItem(bind)

        // **Directly under Connect, because it is the same question answered the
        // other way.** It stops the words going to *that terminal* and hands them
        // back to the outbox, which is what the relay does when nothing is bound.
        // ⌘⌃B on the bound target already does something adjacent and stronger —
        // it ends the session — and there was no way to simply let go of a tab:
        // he had to quit the relay and start it again somewhere else. Disabled
        // while nothing is bound, since it would then be a command with nothing
        // to act on.
        disconnect.image = Self.brokenChainIcon
        disconnect.action = #selector(disconnectClicked)
        disconnect.target = self
        disconnect.isEnabled = false
        menu.addItem(disconnect)

        // **Under Disconnect, because it is the third answer to the same
        // question.** Connect points at what is in front, Disconnect lets go, and
        // this one points at something that is *not* in front — the case neither
        // of the other two can express, and the common one by the afternoon.
        rebind.image = Self.symbolIcon("clock.arrow.circlepath")
        rebind.action = #selector(rebindListClicked)
        rebind.target = self
        menu.addItem(rebind)

        // **The menu holds commands and settings, not the gestures** (2026-11-12,
        // Victor: *"The Walkie Talkie menu is huge and useless … prefer to have a
        // page to teach schematically the gestures"*). Every row that was only a
        // legend — `Prompt at caret`, `Prompt to bound`, `Prompt to new`,
        // `Dictate (no Enter)`, `Transcribe Locally Now`, `Record Screen`,
        // `Take Screenshot`, `Select Screen Area`, `Pick from Chrome` — and the
        // one-glyph chords in the shortcut column went; `Gesture Guide` opens
        // `GestureGuide`, which draws them on his mouse. What stays is what a click
        // does that no gesture does better: the rescue pair for an open sentence
        // (End / Cancel, for the mouse whose battery died), the two that bring a
        // past sentence back, and the destination rows.
        stopRecording.image = Self.symbolIcon("mic.slash")
        stopRecording.action = #selector(stopRecordingClicked)
        stopRecording.target = self
        stopRecording.isEnabled = false

        cancelDictation.image = Self.symbolIcon("trash")
        cancelDictation.action = #selector(cancelDictationClicked)
        cancelDictation.target = self
        cancelDictation.isEnabled = false

        recoverDictation.image = Self.symbolIcon("arrow.up.trash")
        recoverDictation.action = #selector(recoverDictationClicked)
        recoverDictation.target = self
        recoverDictation.isEnabled = false
        replayLast.image = Self.symbolIcon("play.circle")
        replayLast.action = #selector(replayLastClicked)
        replayLast.target = self
        replayLast.isEnabled = false

        pasteLast.image = Self.symbolIcon("doc.on.clipboard")
        pasteLast.action = #selector(pasteLastClicked)
        pasteLast.target = self
        pasteLast.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(pasteLast)

        // **Prompt History under Paste last prompt** (2026-09-22, Victor). The
        // row itself does nothing — AppKit gives a parent row's click to its
        // submenu, so `Full Log` inside is the one way to the page. The submenu
        // is filled on hover; see `menuNeedsUpdate`.
        messageLog.image = Self.symbolIcon("scroll")
        messageLog.submenu = promptHistorySubmenu
        promptHistorySubmenu.delegate = self
        applyPromptHistoryRow()
        menu.addItem(messageLog)
        menu.addItem(recoverDictation)
        menu.addItem(replayLast)

        menu.addItem(.separator())
        menu.addItem(stopRecording)
        menu.addItem(cancelDictation)

        menu.addItem(.separator())

        // **First of the block, where the mode row used to be.** Everything
        // under this separator is about the app rather than about a destination,
        // and the first thing to say about the app is which recogniser is
        // listening: it is the row that answers *what am I dictating with*, and
        // the row under it — the Scratchpad — is a qualification of the answer.
        // The wrap used to be the other one; it went in the same change that
        // gave this row its arrow, as the same question asked twice.
        // **Microphone first, then the engine, Halo fx last** (Victor,
        // 2026-09-20): what is listening, what is transcribing it, and the
        // pickers about what is drawn after them.
        micItem.image = Self.symbolIcon("mic")
        // **A submenu auto-enables on its own**, and this is the one list in the
        // app whose whole point is that some rows are dead. The trap is the one
        // written twenty lines above for the top-level menu — AppKit re-enables
        // any item with a valid target and action unless the *menu* says
        // otherwise — and it bites per `NSMenu`, so turning it off up there buys
        // this list nothing. Without this the `— not connected` rows are fully
        // clickable and the greying is a decoration.
        micSubmenu.autoenablesItems = false
        micItem.submenu = micSubmenu
        applyMicRow()
        menu.addItem(micItem)

        engineItem.image = Self.symbolIcon("waveform")
        engineItem.submenu = engineSubmenu
        // 🧾 the account's quota, drawn at the foot of the list — fetched off
        // the main thread; a fetch that lands while the list is open repaints
        // the row in place (`applyQuotaRow`).
        ElevenLabsQuota.shared.onChange = { [weak self] in self?.applyQuotaRow() }
        ElevenLabsQuota.shared.start()
        applyEngineRow()
        menu.addItem(engineItem)

        lastUsedItem.image = Self.symbolIcon("clock.arrow.circlepath")
        lastUsedItem.isEnabled = false
        applyLastUsedRow()
        menu.addItem(lastUsedItem)

        logiGestures.image = Self.symbolIcon("computermouse")
        logiGestures.submenu = gesturesSubmenu
        applyLogiGesturesRow()
        menu.addItem(logiGestures)

        // **`Halo fx`, last of the pickers**, above Autosend. `sparkles` is ✨'s
        // own SF Symbol, so the row keeps its picture and loses only the colour.
        haloItem.image = Self.symbolIcon("sparkles")
        haloItem.submenu = haloSubmenu
        applyHaloRow()
        menu.addItem(haloItem)

        autosend.action = #selector(autosendClicked)
        autosend.target = self
        applyAutosendIcon()
        menu.addItem(autosend)

        // **📎 What a prompt picks up by itself** (2026-10-15) — three switches
        // under one arrow: the highlight, the frame at the start, anything copied.
        autoAttachItem.image = Self.symbolIcon("paperclip")
        autoAttachItem.submenu = autoAttachSubmenu
        autoAttachSubmenu.autoenablesItems = false
        applyAutoAttachRows()
        menu.addItem(autoAttachItem)

        // **📻 A squelch burst when the microphone opens** (2026-10-01), a
        // switch like Autosend, so the same tick-or-blank; off until he ticks it.
        squelch.action = #selector(squelchClicked)
        squelch.target = self
        squelch.toolTip = "A short burst of radio static each time dictation starts listening."
        applySquelchIcon()
        menu.addItem(squelch)

        // **The switches that lived under `Engine`, out where they can be seen**
        // (2026-11-12, Victor: *"bring the options that are right now in engine
        // top level"*). The Engine list is the engines and the quota again;
        // these are ticks like Autosend, drawn the same way, re-read at every
        // open (`applySwitchRows`).
        for row in [autoLocalRow, liveRow, editorRow, wakeRow, faceRow] {
            row.target = self
            menu.addItem(row)
        }
        autoLocalRow.action = #selector(autoLocalClicked)
        liveRow.action = #selector(localLiveClicked)
        editorRow.action = #selector(editorClicked)
        wakeRow.action = #selector(wakeClicked)
        faceRow.action = #selector(faceClicked)
        applySwitchRows()

        menu.addItem(.separator())

        // **The gestures are taught on a page, not listed here** (2026-11-12) —
        // `GestureGuide`: his mouse drawn, each gesture animated on it.
        guide.image = Self.symbolIcon("computermouse")
        guide.action = #selector(guideClicked)
        guide.target = self
        menu.addItem(guide)

        // The stamp answers "am I looking at what I just built?" without a click;
        // the click opens the guide at its foot, where the build and the
        // repository are written.
        version.image = Self.symbolIcon("info.circle")
        version.action = #selector(versionClicked)
        version.target = self
        menu.addItem(version)

        // ⌘Q as a key equivalent (2026-09-13), for the same reason it sits on the
        // other two apps' Quit rows: Victor asked for the three menus to end the
        // same way. It fires only while the menu is open — a status-item app
        // never becomes key — and the main menu `main.swift` installs already
        // carries the real ⌘Q for the Dock-tile case.
        let exit = NSMenuItem(title: "Quit", action: #selector(exitClicked), keyEquivalent: "q")
        exit.image = Self.symbolIcon("power")
        exit.target = self
        menu.addItem(exit)

        item.menu = menu
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
    /// ⏳ is the only badge that ever rides the glyph — ⏸️ shared the slot until
    /// pause was removed — and it is up for ten seconds at a time, saying whether
    /// the *next* sentence will have a recogniser to reach.
    func setEngineLoading(_ loading: Bool) {
        engineLoading = loading
        applyEngineRow()
        refreshGlyph()
    }

    /// `Engine: 💻 v3-turbo 1.5 GB` while the local model is the one listening;
    /// `Engine: ☁️ Wispr Flow` while the other one is.
    ///
    /// **The row is short and the submenu is long** (Victor, 2026-09-14): the
    /// top-level row is read out of the corner of the eye while the menu bar is
    /// open over his work, and `mlx-community/whisper-large-v3-turbo — 2.6 GB
    /// RAM` there stretched the whole menu to the width of a model id nobody
    /// reads at that moment. The full id is still one hover away, in the list
    /// under the arrow — which is where the question *what exactly are you
    /// running* is actually asked.
    private func applyEngineRow() {
        // **No `…` on the title** — the arrow says there is more, and a row
        // carrying both says it twice.
        engineItem.title = "Engine: \(engineShortTitle(engineId))"
        engineSubmenu.removeAllItems()
        // **Local first, then the one that uploads — and it is the order of
        // trust** (2026-09-18). The offline engine before the one that leaves
        // the Mac: a list he scans while the menu is open over his work should
        // not put a billed, networked engine where his eye lands first.
        //
        // **Wispr Flow left this list on 2026-09-22** — Victor: *"scoate
        // wisprflow ca sursă de dictare din lista de Engine — n-am reușit
        // niciodată să-l integrăm ca lumea în fluxul nostru să-i preluăm ce
        // text injectează."* It is not a ranking, it is a capability: the
        // other two hand this app a transcript, Wispr pastes into whatever has
        // focus and the wrap spent a month failing to intercept that reliably
        // (`WisprFlowSource.wrapMode`). A row offering an engine whose words
        // the relay cannot be sure of catching is a row that loses sentences.
        // Wispr Flow keeps the one job that never needed interception — 🔽 →
        // posts its chord raw, and Wispr pastes where he is typing, which is
        // the whole point of that gesture.
        // **Wispr Flow is the third row again since the evening of 2026-09-22**,
        // behind the firewall in `HotkeyTap`: its ⌘V is dropped at the tap and
        // the relay reads the `History` row, so the words it hands over are as
        // sure as the other two engines'.
        //
        // **Since 2026-09-25 the order is Victor's, and the names are short** —
        // *"☁️ ElevenLabs + Live, ☁️ ElevenLabs, 💻 Local … move the details of
        // what models into the tooltips"*. The row is the choice; the model id,
        // the price and the RAM are what he hovers for. The order of trust
        // above gave way to the order of use: the streaming one is the pick.
        //
        // **Wispr Flow is hidden "for the moment"** (same day) — the engine and
        // its firewall stay whole, `POST /engine {"id":"wispr"}` still picks
        // it, and the row comes back only while it *is* the engine, so the tick
        // is never missing from the list.
        //
        // **`WT_WISPR_ENGINE=1` puts it back, last, where it was** (2026-09-28,
        // pending the lab verdict) — Victor: *"once you're convinced, restore
        // Wispr Flow as a transcription engine"*. The VM runs decide; the
        // restore is then a one-line flip of `wisprEngineDefault`.
        let ids = Self.engineRowIds(wisprSwitch: Self.wisprEngineSwitch, current: engineId)
        for id in ids {
            let row = NSMenuItem(title: engineTitle(id),
                                 action: #selector(enginePicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = id
            row.toolTip = engineDetails(id)
            // The tick where every other switch in this menu draws it — never
            // `NSMenuItem.state`, which would reserve a second column.
            row.image = id == engineId ? Self.symbolIcon("checkmark") : Self.blankIcon
            // **One row per local model, siblings of the cloud engines** (2026-10-03,
            // Victor: one radio group, one tick, short titles) — `Local 💻` is not a
            // row of its own any more; picking one of these is the engine *and* the
            // weights in one click.
            if id == "whisper" { addLocalModelRows(); continue }
            engineSubmenu.addItem(row)
        }
        // **🧾 What the account has left, under a line of its own** (2026-09-28,
        // moved here from Victor Addons the same morning — *"quota lui 11labs
        // are sens doar in walkie"*). Below the rows he picks from, because it
        // is a readout, not a choice. Since 2026-09-28 it is the only money in
        // the list — the `$x.xx` the ElevenLabs rows carried went (*"îmi ajunge
        // quota consumată"*). `used / total / reset`, coloured by the trend.
        engineSubmenu.addItem(.separator())
        let quota = NSMenuItem(title: "", action: #selector(quotaClicked), keyEquivalent: "")
        quota.target = self
        quota.image = Self.blankIcon
        quotaRow = quota
        applyQuotaRow()
        engineSubmenu.addItem(quota)
    }

    /// **Whether the list offers Wispr Flow as a row of its own** — hidden since
    /// 2026-09-25 (*"ascunde pt moment wispr flow"*), back behind
    /// `WT_WISPR_ENGINE=1` since 2026-09-28 while the VM lab decides whether its
    /// words are caught as surely as the other engines'. **On since 2026-09-29
    /// 05:10** — the lab's wave 5 said YES on all seven criteria (build 5661ca4:
    /// relay delivery 96.8 %, 0 cross-destination pastes, 0 doubled, his own
    /// sentences 19/19; `evals/plan/vm/wispr/report-wave5-2026-09-29.md`), and
    /// Victor's order was *"once you're convinced, restore Wispr Flow as a
    /// transcription engine"*. `WT_WISPR_ENGINE=0` hides it again.
    static let wisprEngineDefault = true

    /// `WT_WISPR_ENGINE` — the environment, then `elevenlabs.env` **re-read on
    /// every call**, so the menu built next shows what the file says now, the
    /// way the ⚠️ follows the key. `1` shows the row, `0` hides it, absent is
    /// `wisprEngineDefault`.
    static var wisprEngineSwitch: Bool {
        let raw = ProcessInfo.processInfo.environment["WT_WISPR_ENGINE"]
            ?? ElevenLabsSource.freshValue("WT_WISPR_ENGINE")
        switch raw?.lowercased() {
        case "1", "true", "on", "yes": return true
        case "0", "false", "off", "no": return false
        default: return wisprEngineDefault
        }
    }

    /// The Engine list's ids, top to bottom. Wispr Flow is last — its place
    /// before it was hidden — when the switch is on, or while it *is* the engine
    /// (a `POST /engine {"id":"wispr"}` from the harness), so the tick is never
    /// missing from the list.
    static func engineRowIds(wisprSwitch: Bool, current: String) -> [String] {
        ["eleven-live", "eleven", "whisper"] + (wisprSwitch || current == "wispr" ? ["wispr"] : [])
    }

    /// `GET /engine.wisprRowShown` — the Wispr row is in the list he would see
    /// if he opened the menu now.
    var wisprRowShown: Bool {
        Self.engineRowIds(wisprSwitch: Self.wisprEngineSwitch, current: engineId).contains("wispr")
    }

    /// **The local engine, one row per model** (2026-10-03, flattened the same
    /// day). Victor: every engine/model a sibling in one list, one tick, short
    /// titles — `💻 Local Turbo`, `💻 Local Turbo LoRA ★`, `💻 Local Large LoRA` since 2026-10-21;
    /// the model, accuracy, speed on this Mac and training are on the sectioned
    /// tooltip, read from the folder's `model-card.json` (`WhisperModels.tooltip`),
    /// never written twice. The tick needs both: the local engine live **and**
    /// this model picked.
    private func addLocalModelRows() {
        let picked = WhisperModels.selected
        let options = WhisperModels.options()
        let best = Self.starred(options)
        for option in options {
            let mine = option.id == picked
            let row = NSMenuItem(title: Self.localRowTitle(option, loading: mine && engineLoading),
                                 action: #selector(localModelPicked(_:)), keyEquivalent: "")
            if option.id == best {
                let title = NSMutableAttributedString(string: row.title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                title.append(NSAttributedString(string: " ★", attributes: [.font: NSFont.menuFont(ofSize: 0),
                                                                          .foregroundColor: NSColor.secondaryLabelColor]))
                row.attributedTitle = title
            }
            row.target = self
            row.representedObject = option.id
            row.toolTip = option.details + (mine ? "\n" + localNowLine() : "")
            row.image = engineId == "whisper" && mine ? Self.symbolIcon("checkmark") : Self.blankIcon
            engineSubmenu.addItem(row)
        }
    }

    /// **A grey ★ after the recommended local model — `"recommended": true` on its card**
    /// (2026-10-21, Victor: *"change the star to the local LoRA … emphasize the turbo side"*):
    /// `Local Turbo LoRA`, Turbo's speed with most of Large's accuracy gain (WER 15.3 % vs
    /// 14.0 %, at half the decode time). Supersedes 2026-10-15's *most accurate*, which put it
    /// on the Large LoRA; with no card flagged, that rule is still the fallback. Never more than
    /// one star, never depends on which row is picked.
    static func starred(_ options: [WhisperModels.Option]) -> String? {
        if let flagged = options.first(where: { $0.card?.recommended == true }) { return flagged.id }
        return options.compactMap { o in o.card?.werAfter.map { (o.id, $0) } }.min { $0.1 < $1.1 }?.0
    }

    /// The picked local row's last tooltip line: what the helper holds now.
    private func localNowLine() -> String {
        if engineLoading { return "Now: loading…" }
        if let bytes = whisperFootprint?() {
            return String(format: "Now: loaded, %.1f GB RAM · runs offline", Double(bytes) / 1_073_741_824)
        }
        return "Now: not loaded — comes up for the next sentence · runs offline"
    }

    /// `💻 <model name>` — `💻 v3-turbo`, `💻 v3-turbo-victor` (2026-10-03, Victor:
    /// the model's name, no `Local`; **the laptop first since 2026-10-09**, see
    /// `cloud`/`local`), with the ⏳ while the picked model loads.
    static func localRowTitle(_ option: WhisperModels.Option, loading: Bool) -> String {
        "\(local) \(option.title)" + (loading ? " ⏳" : "")
    }

    /// **Every engine name starts with where it runs** (2026-10-09, Victor: *"be
    /// sure to start with the laptop emoji everywhere … so it's clear from the
    /// first character if this is a local"*) — the menu, the launch and green
    /// tabs, the prompt panel's `Engine:` row. Reverses 2026-09-30's *after the
    /// name*.
    static let cloud = "☁️", local = "💻"

    /// Victor picked a local model (a repo id or a folder). `AppDelegate` stores
    /// it and replaces the helper at the next idle moment.
    var onPickWhisperModel: ((String) -> Void)?

    /// The weights first, so the engine switch that follows brings up these.
    @objc private func localModelPicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onPickWhisperModel?(id)
        if engineId != "whisper" { onPickEngine?("whisper") }
    }

    /// `GET /engine.whisperModels` — the local rows of the Engine list, as data.
    static func whisperModelRows(engineId: String) -> [[String: Any]] {
        let picked = WhisperModels.selected
        return WhisperModels.options().map {
            ["id": $0.id, "title": localRowTitle($0, loading: false), "tooltip": $0.details,
             "selected": $0.id == picked, "ticked": engineId == "whisper" && $0.id == picked]
        }
    }

    /// The 🧾 row, rebuilt with the list and repainted in place when a fetch lands.
    private var quotaRow: NSMenuItem?

    /// Repainted when the ⏱ switch moves from elsewhere (`POST /test/local-auto`).
    func refreshAutoLocal() { applySwitchRows() }

    private static func tick(_ on: Bool) -> NSImage? { on ? symbolIcon("checkmark") : blankIcon }

    /// The five engine switches' ticks and tooltips, read from their own stores
    /// at every open — the tick is whatever is running, never the click.
    private func applySwitchRows() {
        autoLocalRow.image = Self.tick(AutoLocal.isOn)
        let ram = whisperFootprint?().map { String(format: "%.1f GB", Double($0) / 1_073_741_824) }
        autoLocalRow.toolTip = "While ElevenLabs or Wispr Flow transcribes, this Mac decodes the sentence too, "
            + "timed to be ready by the engine's p95 for that length (at least 1.5 s, at most 0.3 × the audio + 1 s).\n"
            + "The chip counts down to that moment and at zero the local words go in; "
            + "⌘⌃X puts them in sooner, and the engine's words landing first discard them.\n"
            + "Uses \(WhisperModels.option(for: WhisperModels.selected).map { Self.localRowTitle($0, loading: false) } ?? "\(Self.local) Local").\n"
            + "Keeps the local model loaded while another engine is picked"
            + (ram.map { " (\($0) now)" } ?? "") + "."
        liveRow.image = Self.tick(LocalLive.isOn)
        liveRow.toolTip = "With a local model as the engine, the subtitle band shows what it hears while you talk: "
            + "at every half-second pause the take since the last settled sentence is decoded again "
            + "and the band rewritten.\n"
            + "A second copy of the model runs it (~2 GB more), so the final transcription never waits: "
            + "a window still decoding when you stop is killed."
        editorRow.image = Self.tick(DictationEditor.enabled)
        editorRow.toolTip = "A plain dictation from ElevenLabs or a local model is read once more by Haiku "
            + "before it is pasted, with what is on screen: the app, the text around the caret, the names in the window. "
            + "It fixes misheard words and names, drops fillers and keeps only a self-correction.\n"
            + "Wispr Flow's words are already edited by Wispr. Waits at most \(Int(DictationEditor.budget)) s, then pastes the raw words."
        // Grey and unticked on battery, whatever the switch says (`WakeWord.listens`).
        wakeRow.isEnabled = !BatteryFx.onBattery
        wakeRow.image = Self.tick(WakeWord.listens)
        wakeRow.toolTip = (BatteryFx.onBattery ? "Off on battery — it listens again when the Mac is plugged in.\n" : "") + "Say \"Hey Claude\", then the task: it starts a new Claude Code session in ~/workspace with your words. "
            + "Open with \"I have a question\" and it is a ⚡ quick question instead, answered in the pop-up. "
            + "The sentence ends when you stop talking.\n"
            + "A small model listens all the time on this Mac (nothing leaves it); macOS shows the microphone as in use."
        faceRow.image = Self.tick(FaceRead.enabled)
        faceRow.toolTip = "While a prompt records, the camera takes two frames a second, read on this Mac and thrown away. "
            + "The prompt gets a tag only for what the words lose: you smiled, you look tired, or you were away from the screen.\n"
            + "Nothing is stored but the numbers in the outbox. Never on a plain dictation."
    }

    @objc private func autoLocalClicked() {
        onToggleAutoLocal?(!AutoLocal.isOn)
    }

    /// The `Live captions (local)` row's new value (the menu is rebuilt on open).
    var onToggleLocalLive: ((Bool) -> Void)?

    @objc private func localLiveClicked() {
        onToggleLocalLive?(!LocalLive.isOn)
    }

    /// The `Hey Claude` row's new value.
    var onToggleWakeWord: ((Bool) -> Void)?

    @objc private func wakeClicked() {
        guard !BatteryFx.onBattery else { return }
        onToggleWakeWord?(!WakeWord.enabled)
    }

    @objc private func faceClicked() {
        FaceRead.enabled.toggle()
        applySwitchRows()
        Log.info("🙂 face reading \(FaceRead.enabled ? "on" : "off") from the menu")
    }

    @objc private func editorClicked() {
        DictationEditor.enabled.toggle()
        applySwitchRows()
        Log.info("✍️ dictation editor \(DictationEditor.enabled ? "on" : "off") from the menu")
        DictationEditor.shared.warm()
    }

    private func applyQuotaRow() {
        guard let row = quotaRow else { return }
        let q = ElevenLabsQuota.shared
        row.title = q.title
        row.toolTip = q.tooltip
        // Tinted through `attributedTitle`, like the Halo presets' bolt: a tint
        // on the title is the only colour a menu row takes. **The colour is the
        // trend** (`ElevenLabsQuotaPolicy.pace`, 2026-09-28): green while the
        // burn lands inside the plan by the reset, orange over it, red far
        // over or spent. Plain before the first answer.
        let tint: NSColor?
        switch q.pace {
        case .green?: tint = .systemGreen
        case .orange?: tint = .systemOrange
        case .red?: tint = .systemRed
        case nil: tint = nil
        }
        row.attributedTitle = tint.map {
            NSAttributedString(string: q.title, attributes: [.foregroundColor: $0,
                                                             .font: NSFont.menuFont(ofSize: 0)])
        }
    }

    @objc private func quotaClicked() {
        NSWorkspace.shared.open(ElevenLabsQuota.shared.clickURL)
    }

    /// **`POST /test/engine-menu`** — the Engine list popped up on its own, in a
    /// forced appearance, closing itself after `seconds`. A submenu cannot be
    /// opened from code, and the 🧾 row has to be reviewed in both themes
    /// without flipping his desktop; a copy of the rows is what AppKit draws
    /// under the arrow, row for row. The close is armed before the pop-up,
    /// because the tracking loop does not drain the main queue.
    /// `main` (`{"menu": "main"}`, 2026-09-28) pops the whole top-level menu the
    /// same way, refreshed as `menuWillOpen` would — for a row renamed there
    /// (`𝓯𝔁`) to be reviewed in both themes too.
    func popEngineMenuForTest(appearance: String?, seconds: TimeInterval, at point: NSPoint,
                              main: Bool = false) {
        applyEngineRow()
        var source = engineSubmenu
        if main, let menu = item.menu {
            menuWillOpen(menu)
            source = menu
        }
        let copy = NSMenu()
        copy.autoenablesItems = false
        for row in source.items { copy.addItem(row.copy() as! NSMenuItem) }
        if let appearance {
            copy.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in copy.cancelTracking() }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        copy.popUp(positioning: nil, at: point, in: nil)
    }

    /// **`Full Log`, a line, then the last sentences he dictated.**
    ///
    /// The order is Victor's (2026-09-17): the page above the line, the snippets
    /// below it. The line is what makes the two halves readable as two things —
    /// one row that leaves the app, and a list that is the app's own memory of
    /// what was said. Newest first, the same way the page is ordered and for the
    /// same reason: the sentence being looked for is almost always the last one.
    ///
    /// **A row is the first words and an ellipsis**, never the whole prompt: a
    /// dictated paragraph is three hundred characters and a menu that wide is
    /// unreadable and covers the work. The full text is on the row's tooltip and
    /// on the clipboard once it is clicked.
    ///
    /// **Clicking copies; it does not send.** Everything else in this menu that
    /// touches text puts it somewhere — the destination, the caret — and a row
    /// that fired an old sentence at whatever is focused would be the one
    /// irreversible click in the menu. The clipboard is where the page's own
    /// Copy button puts it, and `⌘V` is his to press.
    private func applyPromptHistoryRow() {
        promptHistorySubmenu.removeAllItems()

        let full = NSMenuItem(title: "Full Log", action: #selector(messageLogClicked),
                              keyEquivalent: "")
        full.image = Self.symbolIcon("scroll")
        full.target = self
        promptHistorySubmenu.addItem(full)
        promptHistorySubmenu.addItem(.separator())

        // Words only. A line with nothing but a screenshot on it has no snippet
        // to show, and a row reading `…` is noise in a list read at a glance;
        // the page still has every one of them.
        let spoken = MessageLog.recent().filter { !$0.text.isEmpty }.prefix(Self.promptHistoryRows)
        guard !spoken.isEmpty else {
            let empty = NSMenuItem(title: "Nothing dictated in the last two days",
                                   action: nil, keyEquivalent: "")
            empty.image = Self.blankIcon
            empty.isEnabled = false
            promptHistorySubmenu.addItem(empty)
            return
        }

        for entry in spoken {
            let row = NSMenuItem(title: MessageLog.snippet(entry.text),
                                 action: #selector(promptPicked(_:)), keyEquivalent: "")
            row.image = Self.blankIcon
            row.target = self
            row.toolTip = entry.text
            row.representedObject = MessageLog.envelope(entry)
            promptHistorySubmenu.addItem(row)
        }
    }

    /// **Twelve.** Two days of dictation is a hundred sentences and a menu is not
    /// a scrollable list; twelve covers the session he is in, which is the span
    /// the row is opened for. Everything older is one click up, in the page.
    private static let promptHistoryRows = 12

    /// The envelope of the sentence he picked, on the clipboard — exactly the
    /// string the page's Copy button hands over, and the one `⌘⇧P` pastes for
    /// the newest sentence.
    @objc private func promptPicked(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, !text.isEmpty else { return }
        Clipboard.write(text)
        Log.info("📋 a prompt from the history is on the clipboard (\(text.count) chars)")
    }

    /// **What one engine is called** in the list: a cloud or a laptop, and a
    /// name (2026-09-25). Everything below this paragraph describes what the row
    /// *used* to carry and now lives on its tooltip (`engineDetails`) — the
    /// reasons still hold there, one hover away.
    ///
    /// **The cost is shown, because the weights are the whole argument** for
    /// starting the helper only when a dictation is coming and letting it go
    /// afterwards; until this number was in the menu that cost was a figure in a
    /// comment, which is exactly where a fact nobody can check belongs. It
    /// doubles as proof the helper is actually alive, since a dead one has no
    /// footprint and the name goes back to being bare.
    ///
    /// **`RAM` is spelled out after the number** because a size in a menu is
    /// read as a download by default — the one thing this number is not. It is
    /// what the helper is holding *right now*.
    ///
    /// `phys_footprint`, i.e. Activity Monitor's "Memory" — see
    /// `LocalWhisper.footprintBytes` for why not RSS.
    ///
    /// **The model id in full, org prefix included** — `mlx-community/whisper-
    /// large-v3-turbo`, which is how Victor names it (*"trece numele modelului:
    /// mlx…"*, 2026-09-14). The prefix was stripped for one build on the
    /// argument that it says where the weights were downloaded from rather than
    /// what is doing the listening; that is true and beside the point — it is
    /// the half he says out loud, and a name he has to reassemble to repeat is
    /// not the name.
    ///
    /// **Never `Local Whisper`.** The category was the fallback while
    /// `whisperModel` answered nil, which is whenever the weights are down —
    /// i.e. most of the time this row is read. `LocalWhisperSource` now answers
    /// the configured id instead; see its note.
    private func engineTitle(_ id: String) -> String {
        // ⚠️ stays on the row, not only in the tooltip: *this engine cannot run
        // right now* belongs in the list he picks from.
        let keyless = elevenReady?() == true ? "" : " ⚠️"
        switch id {
        // **No `$x.xx` after the name since 2026-09-28** — Victor: *"în
        // submeniul ElevenLabs, scoate $ de după nume. Îmi ajunge quota
        // consumată."* The 🧾 row at the foot of the list says what the
        // account has used; `ElevenLabsCost` still counts, for
        // `/test/state.elevenCost` only.
        // **`💸x3` on the Live row** (2026-09-28, Victor: *"mention 💸x3 on … +
        // Live in model choice"*): measured on the account, a dictated second
        // with captions bills three times — the live stream, the corrections
        // and the final upload, 1.06 credits/s against 0.29 batch-only
        // (`evals/elevenlabs-cost.md`). The tooltip carries the figures.
        // **The ☁️ / 💻 first** (2026-10-09 — `cloud`/`local`; after the name
        // from 2026-09-30 until then).
        case "eleven-live": return "\(Self.cloud) ElevenLabs + Live 💸x3" + keyless
        case "eleven": return "\(Self.cloud) ElevenLabs" + keyless
        case "wispr": return "\(Self.cloud) Wispr Flow"
        default: return engineLoading ? "\(Self.local) Local ⏳" : "\(Self.local) Local"
        }
    }

    /// **The details the row used to carry, on its tooltip** (2026-09-25) —
    /// every fact `engineTitle` spelled out until then, still read live on every
    /// open: the model id in full, the published price, the key, the RAM.
    private func engineDetails(_ id: String) -> String {
        let key = elevenReady?() == true ? nil
            : "No API key — put ELEVENLABS_API_KEY=… in ~/.walkie-talkie/elevenlabs.env"
        // **Sectioned like the local rows' cards** (2026-10-21): a headline, WHAT,
        // SPEED (the typical round trip fitted to his own sentences on that engine,
        // `DecodeRate.typical`, read at every open), PRIVACY.
        func sections(_ s: [[String?]]) -> String {
            s.map { $0.compactMap { $0 } }.filter { !$0.isEmpty }
                .map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        }
        func speed(_ engine: String) -> [String?] {
            let fmt = { (v: Double) in String(format: v < 10 ? "%.1f s" : "%.0f s", v) }
            return ["SPEED — fitted to your recent sentences on it",
                    "10 s of speech → ≈ \(fmt(DecodeRate.typical(for: 10, engine: engine))) to text",
                    "1 min of speech → ≈ \(fmt(DecodeRate.typical(for: 60, engine: engine))) to text"]
        }
        let cloudOnly = ["PRIVACY", "Audio leaves this Mac", key]
        switch id {
        case "eleven-live":
            return sections([
                ["\(engineTitle(id)) — the words on screen while you talk"],
                ["WHAT",
                 "Live: ElevenLabs \(ElevenLabsLive.model) · \(ElevenLabsLive.rate) (+20 % with keyterms)",
                 "Final: ElevenLabs \(ElevenLabsSource.model) · \(ElevenLabsSource.rate), from the recording",
                 "It corrects the live words at every committed segment",
                 "💸x3: each second billed three times (live, corrections, final upload)",
                 "Measured 1.06 credits/s vs 0.29 on ☁️ ElevenLabs alone (28 Sep)"],
                speed(DecodeRate.elevenLabs),
                cloudOnly])
        case "eleven":
            return sections([
                ["\(engineTitle(id)) — cloud recogniser, the default engine"],
                ["WHAT",
                 "Model: ElevenLabs \(ElevenLabsSource.model)",
                 "Price: \(ElevenLabsSource.rate) of audio",
                 "Sent: the recording, once you stop"],
                speed(DecodeRate.elevenLabs),
                cloudOnly])
        case "wispr":
            return sections([
                ["\(Self.cloud) Wispr Flow — its own app and microphone"],
                ["WHAT",
                 "Wispr Flow's cloud recogniser and its AI edit",
                 "Its paste is blocked; the relay reads its History row and delivers the words",
                 "Price: its own subscription, not billed per hour here"],
                speed(DecodeRate.wisprFlow),
                ["PRIVACY", "Audio leaves this Mac"]])
        default:
            let name = whisperModel?() ?? WhisperModels.displayName(LocalWhisperSource.configuredModel)
            let memory: String
            if engineLoading { memory = "loading…" }
            else if let bytes = whisperFootprint?() {
                memory = String(format: "%.1f GB RAM", Double(bytes) / 1_073_741_824)
            } else { memory = "not loaded — comes up for the next sentence" }
            return "\(name) — \(memory)\nRuns on this Mac, offline"
        }
    }

    /// **What the top-level row calls the same engine** — `Wispr Flow`, or
    /// `Local (2.6 GB)` with the footprint kept and the model id dropped.
    ///
    /// The size stays because it is the half that changes: it says the helper is
    /// alive and what it is costing right now, which is the whole argument for
    /// letting it go between dictations. The name goes because it does not —
    /// it is the same string every launch, and `engineTitle` has it in the list
    /// below for the one moment somebody asks.
    /// The launch tab's words (2026-09-28): the emoji the submenu row wears in
    /// right after the engine's name in the top-level row's title — `ElevenLabs ☁️
    /// + Live`, `Local 💻 (1.5 GB)` (after the name since 2026-09-30, as in the list).
    func engineBannerTitle(_ id: String) -> String {
        // **`Wispr Flow` on the tab, as in the Engine menu** (2026-10-20, Victor:
        // *"instead of just Whisper in the badge popping from below, put the
        // name of the full product"*) — reverses 2026-10-06's `Wispr`.
        if id == "wispr" { return "\(Self.cloud) Wispr Flow" }
        // **No RAM on the tab** (2026-10-14, Victor: *"I don't want to see the
        // gigabytes"*) — the footprint stays in the menu's Engine row.
        if id == "eleven" || id == "eleven-live" { return engineShortTitle(id) }
        // **`Whisper V3 Turbo +LoRA`, no `Local`** (2026-11-12) — `WhisperModels.tabName`.
        return "\(Self.local) " + WhisperModels.tabName(WhisperModels.selected)
    }

    private func engineShortTitle(_ id: String) -> String {
        // ⚠️ rather than the price, because the top-level row is read out of the
        // corner of the eye: what he needs from it there is *the cloud one is
        // live and it cannot work*, and the reason is one hover away.
        let ok = elevenReady?() == true
        if id == "eleven" { return "\(Self.cloud) ElevenLabs" + (ok ? "" : " ⚠️") }
        if id == "eleven-live" { return "\(Self.cloud) ElevenLabs + Live" + (ok ? "" : " ⚠️") }
        if id == "wispr" { return "\(Self.cloud) Wispr Flow" }
        // **The picked model's name, the 💻 against it, then the RAM** —
        // `v3-turbo💻 1.5 GB`, `v3-turbo-victor💻 1.5 GB`, `v3-victor💻 2.9 GB`:
        // the same name as everywhere else since 2026-10-07 (`Turbo LoRA Victor`
        // 2026-10-05, `V3t…` 2026-10-04, *"fara ( ) in jurul GB"*).
        let name = "\(Self.local) " + WhisperModels.displayName(WhisperModels.selected)
        if engineLoading { return name + " loading…" }
        guard let bytes = whisperFootprint?() else { return name }
        return name + String(format: " %.1f GB", Double(bytes) / 1_073_741_824)
    }

    private func applyLastUsedRow() {
        lastUsedItem.title = "Last used: " + (lastEngineUsed?() ?? "—")
    }

    @objc private func enginePicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != engineId else { return }
        onPickEngine?(id)
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
        stopRecording.isEnabled = recording
        cancelDictation.isEnabled = isDictationCancellable?() ?? recording
        // Not while one is running: two transcripts arriving at one panel is an
        // ordering problem there is no reason to create from a menu.
        recoverDictation.isEnabled = !recording && (isRecoverable?() ?? false)
        let replaying = isReplaying?() ?? false
        replayLast.isEnabled = replaying || (isReplayable?() ?? false)
        replayLast.title = replaying ? "Stop Replay" : "Replay Last Dictation"
        replayLast.image = Self.symbolIcon(replaying ? "stop.circle" : "play.circle")
    }

    private func refreshGlyph() {
        // The picture says bound; the badge in front of it says the one state
        // that is *not* about where the words go — whether the next sentence will
        // have a recogniser to reach. ⏸️ used to share this slot; there is no
        // pause any more.
        let badge = engineLoading ? "⏳" : ""
        // **Always the same device** (2026-09-28). The bare device meant *unbound*
        // from 2026-08-28; the chip's `📍 Unbound` row and the menu's Bind row say
        // that now.
        let icon = Self.boundIcon
        item.button?.image = icon
        item.button?.title = badge
        // No copy of this on the other screens: `MenuBarMirror` drew one at the
        // centre of every inactive display's menu bar until 2026-10-26, on the
        // belief that an `NSStatusItem` shows only on the focused display. It
        // shows on every display, so the mirror was a second robot in every
        // bar Victor was not typing on (*"iconița … de două ori, fix pe centru"*).
    }

    /// The two menu-bar pictures, scaled to the bar's height once.
    ///
    /// Not templates: the ring is the whole signal in the bound one, and a
    /// template image is drawn as a silhouette in a single colour. macOS dims
    /// them on an inactive display either way, which is the behaviour that was
    /// asked for.
    /// When this binary was put in place, for the Version row.
    ///
    /// **Taken from the executable's own mtime, not from a constant stamped into
    /// the source.** Victor Addons seds a `BUILD_TIME` literal into its Swift file
    /// on every build, which works but dirties a tracked file on each run and
    /// lands in commits as noise. The file date says the same thing for free and
    /// cannot go stale: `build-app.sh` copies the binary into the bundle with a
    /// plain `cp`, so the date is the moment of install even when `swift build`
    /// had nothing to recompile — and a `swift build` run from the terminal gets
    /// its own honest date the same way.
    static let buildStamp: String = {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attrs?[.modificationDate] as? Date
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date ?? Date())
    }()

    /// Google Maps' own marker red, because that is the picture Victor named when
    /// he asked for the pin — and a red pin among a column of monochrome symbols
    /// is also the one row the eye finds without reading.
    private static let pinRed = NSColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1)

    /// **The icon column: SF Symbols, one source, no colour** (Victor,
    /// 2026-09-21: *"să fie toate monocrome"*).
    ///
    /// Emoji were what was asked for first and they came with their own colour,
    /// but two rows kept it while every other row had given it up — 🆕 beside
    /// `mic`, ✨ at the head of the pickers — and two coloured rows in a
    /// monochrome column read as two rows that are special rather than two rows
    /// that are different. They are `mic.badge.plus` and `sparkles` now, which
    /// are the same pictures in the menu's own ink. The argument that put the
    /// symbols there in the first place still holds and is why the swap is free:
    /// Unicode has no crossed-out map pin and no crossed-out microphone, both of
    /// those are the *off* half of a pair, and a pair whose halves come from two
    /// alphabets reads as two unrelated rows — so Connect/Disconnect and
    /// Start/End were SF Symbols on both sides from the start.
    ///
    /// **Nothing here is tinted.** `tint` is kept for a caller that has a reason;
    /// it costs the image its template flag, and with it the menu's highlight and
    /// dark mode.
    ///
    /// 📍 in particular is `ROUND PUSHPIN` — a thumbtack stuck in at an angle, not
    /// the teardrop marker everybody means by a pin on a map. `mappin` is the
    /// marker. Same objection `Glyphs.pin` was drawn to answer, one column over.
    private static func symbolIcon(_ name: String, tint: NSColor? = nil) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let tint = tint {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        let sized = image.withSymbolConfiguration(config) ?? image
        // A tinted symbol has to stop being a template, or AppKit paints it in the
        // menu's own text colour and the palette is thrown away.
        sized.isTemplate = tint == nil
        return sized
    }

    /// An emoji drawn into the same box the symbols land in, so the two sources
    /// share one column rather than one row's glyph sitting a few points off the
    /// next one's.
    /// **A broken chain for Disconnect** (Victor: *"for bind/unbind put a
    /// chain / broken chain"*). macOS 15 has `link` but no `link.slash`, so
    /// the slash is drawn: the symbol, then a bar across it in the same
    /// template ink, a knocked-out gap either side so the break reads.
    private static let brokenChainIcon: NSImage? = {
        guard let link = symbolIcon("link") else { return nil }
        let size = link.size
        let image = NSImage(size: size, flipped: false) { rect in
            link.draw(in: rect)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let gap = NSBezierPath()
            gap.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1)); gap.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            gap.lineWidth = 4.5; NSColor.black.setStroke(); gap.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1)); bar.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            bar.lineWidth = 1.6; bar.lineCapStyle = .round; NSColor.black.setStroke(); bar.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// **A name with a bolt after it**, for the presets: the symbol as a text
    /// attachment, so it takes the row's colour like every other icon and
    /// follows the name with no separator (Victor: *"just a lightning bolt
    /// after their name, no separator bar"*).
    private static func boltedTitle(_ name: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: name + " ", attributes: [.font: font])
        if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize - 1, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))) {
            // A template image inside an attributed title is not re-tinted by
            // the menu (drawn black on dark, measured headlessly), so the
            // label colour is set on it; on a highlighted row it stays label
            // colour rather than turning white — the one visible compromise.
            bolt.isTemplate = false
            let attachment = NSTextAttachment()
            attachment.image = bolt
            attachment.bounds = NSRect(x: 0, y: font.descender + 1, width: bolt.size.width, height: bolt.size.height)
            title.append(NSAttributedString(attachment: attachment))
        }
        return title
    }

    /// The icon column's own width, drawn and empty. A row whose state is *off*
    /// still has to occupy the column, or its title steps left the moment the
    /// tick appears — which is the layout shifting under him that put both
    /// switches in this column in the first place.
    private static let blankIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16))
        image.lockFocus()
        image.unlockFocus()
        return image
    }()

    /// The device, monochrome, at every state (2026-11-05; its orange disc from
    /// 2026-09-28). `walkie-bound.png` stays the app's and the extension's icon.
    private static let boundIcon = Glyphs.walkie(height: 18)

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
        destinationIcon = icon
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
    @objc private func recoverDictationClicked() { onRecoverDictation?() }
    @objc private func replayLastClicked() { onReplayLast?() }
    @objc private func bindClicked() { onBind?() }

    /// **The list, shown where the pointer already is.**
    ///
    /// Dispatched rather than run inline, which is the pop-up menu's old reason
    /// kept for its replacement: the click that gets here is still closing the
    /// menu it came from, and anything put up inside that closing lands under it
    /// and takes no clicks.
    ///
    /// **It is a panel and no longer an `NSMenu`** (2026-09-12) — the list has a
    /// search field on it now, and a menu cannot be typed into. See
    /// `RebindPanel`; everything that used to be in `buildRebindMenu` — the app
    /// icon per row, the plain dimmed title for a row that cannot be clicked, the
    /// list built at the instant it is asked for — moved there whole.
    @objc private func rebindListClicked() {
        let at = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in self?.showRebindPanel(at: at) }
    }

    /// **The one door into the panel**, for the row above and for
    /// `POST /test/rebind-panel`. The closures are handed over at the opening
    /// rather than at construction, for `rebindRows`' reason: what they answer is
    /// only right at the instant the list goes up.
    func showRebindPanel(at point: NSPoint, query: String = "") {
        rebindPanel.rows = rebindRows
        rebindPanel.liveTitles = liveTitles
        rebindPanel.onRebind = { [weak self] tty in self?.onRebind?(tty) }
        rebindPanel.onMessage = { [weak self] text in self?.onRebindMessage?(text) }
        rebindPanel.onResume = { [weak self] session, cwd in self?.onResumeSession?(session, cwd) }
        rebindPanel.show(at: point, query: query)
    }
    @objc private func pasteLastClicked() { onPasteLast?() }
    @objc private func messageLogClicked() { MessageLog.openInBrowser() }

    private var destination: String?

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    /// **The history is read when its arrow is hovered, not when the menu
    /// opens.** `MessageLog.recent` reads and parses the whole outbox; doing
    /// that on every menu open would put a file read on the path of every glance
    /// at the destination, for a list most of those glances never unfold.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === promptHistorySubmenu else { return }
        applyPromptHistoryRow()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // **Only the menu itself.** AppKit sends this to any menu this object is
        // the delegate of, and every line below is about the top-level rows — a
        // popped-up list re-running the header and the gesture column would be
        // work done for nothing, on the one path this feature promised to keep
        // cheap.
        guard menu === item.menu else { return }
        SessionLabel.refresh()
        applyHeader()
        applyAutoAttachRows()
        // 🧾 cached for 5 min; a stale one refreshes in the background and the
        // row repaints while the menu is still open.
        ElevenLabsQuota.shared.refreshIfStale()
        // 🎤 the DJI's battery, asked of Victor Addons; the row repaints in the open menu.
        DjiBattery.refresh { [weak self] _ in self?.applyMicTitle() }
        applyEngineRow()
        applyLastUsedRow()
        // Devices come and go while the app runs, and the only moment this list
        // has to be right is the moment he is looking at it.
        applyMicRow()
        applyHaloRow()
        applyHaloEngineRow()
        applyHaloVoiceRow()
        applyStopRecording()
        pasteLast.isEnabled = hasLastDictation?() ?? false
        applySwitchRows()
    }

    /// **The bare `petclinic@main` since 2026-10-03** (Victor: *"prima linie, nu
    /// mai zice bound to, direct"*) — the app icon beside it says it is a
    /// destination. Until then it read `Bound to: petclinic@main`, for this reason:
    ///
    /// The chip can afford to be bare: it rides the cursor, it appears when a
    /// binding does, and beside a pointer there is nothing else it could be
    /// naming. In the menu the same line sits above `Connect Terminal` /
    /// `Disconnect` / `End Dictation`, and a folder name on its own between an icon and a
    /// stack of commands reads as the title of a section — i.e. as what the
    /// commands are *for*, rather than as where the words are going. The two
    /// words say which of the two it is.
    ///
    /// Only the bound form takes the prefix. **Unbound the row says `Unbound`,
    /// behind the same map pin the chip wears** (Victor, 2026-09-14) — it used
    /// to be `🤖 ` plus `SessionLabel.value`, and since the relay became a login
    /// item that label is `/`: a robot and a slash, naming the directory
    /// `launchd` happened to start the app in. It read as a destination, which
    /// is the one thing it was not. The same line was taken off the chip for the
    /// same reason (`RelayWindow`, *"no title row while nothing is bound"*); the
    /// menu keeps a row because a header that disappears leaves the commands
    /// under it with nothing to be about.
    ///
    /// **`Glyphs.mapPin`, not 📍** — the drawn teardrop marker, the same image
    /// the chip's title row and the *bind to send* hint carry, so the two places
    /// the binding is named wear one mark. See `Glyphs`.
    private func applyHeader() {
        header.title = destination ?? "Unbound"
        header.image = destination == nil ? Self.unboundIcon : destinationIcon
    }

    /// The pin drawn once, at the icon column's height. `Glyphs.mapPin` is a
    /// `CGContext` trace per call and this row is re-applied on every menu open.
    private static let unboundIcon = Glyphs.mapPin(height: 16)

    /// The bound destination's app icon, kept so `applyHeader` can put it back
    /// after an unbound spell has borrowed the slot for the pin.
    private var destinationIcon: NSImage?

    @objc private func exitClicked() {
        onExit?()
    }

    /// The guide, opened at its foot — the build and the repository.
    @objc private func versionClicked() {
        GestureGuide.logiGesturesOn = logiGesturesOn
        GestureGuide.show(at: .about)
    }

    @objc private func guideClicked() {
        GestureGuide.logiGesturesOn = logiGesturesOn
        GestureGuide.show()
    }

    /// Push the mode in from outside, the shape `setReplaceWispr` has.
    func setLogiGestures(_ on: Bool) {
        logiGesturesOn = on
        UserDefaults.standard.set(on, forKey: Self.logiGesturesKey)
        applyLogiGesturesRow()
        // The hint bar and the guide read the vocabulary from here.
        GestureGuide.logiGesturesOn = on
    }

    @objc private func gesturesPicked(_ sender: NSMenuItem) {
        guard let on = sender.representedObject as? Bool, on != logiGesturesOn else { return }
        setLogiGestures(on)
        onToggleLogiGestures?(logiGesturesOn)
    }

    /// `Mouse Gestures: Logi` or `: Wheel`, and the tick beside whichever of the
    /// two rows is the one wired up. See the note on the row.
    private func applyLogiGesturesRow() {
        logiGestures.title = "Gestures: \(logiGesturesOn ? "Logi" : "Wheel")"
        gesturesSubmenu.removeAllItems()
        // **Named by the hardware each one needs**, not by what it does to the
        // wheel: the question this list answers is *which mouse am I on*, and
        // the answer is either the one with the Options+ profile behind it or
        // any mouse at all.
        for (on, title) in [(true, "Logi — side buttons from Options+"),
                            (false, "Wheel — the wheel carries the dictation")] {
            let row = NSMenuItem(title: title,
                                 action: #selector(gesturesPicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = on
            // The tick where every other choice in this menu draws it — never
            // `NSMenuItem.state`, which would reserve a second column.
            row.image = on == logiGesturesOn ? Self.symbolIcon("checkmark") : Self.blankIcon
            gesturesSubmenu.addItem(row)
        }
    }

    /// `POST /test/autosend` (G6): the same toggle as the row, optionally not
    /// written to the defaults.
    func setAutosend(_ on: Bool, persist: Bool) {
        autosendOn = on
        if persist { UserDefaults.standard.set(on, forKey: Self.autosendKey) }
        applyAutosendIcon()
        onToggleAutosend?(on)
    }

    @objc private func autosendClicked() {
        autosendOn.toggle()
        UserDefaults.standard.set(autosendOn, forKey: Self.autosendKey)
        applyAutosendIcon()
        onToggleAutosend?(autosendOn)
    }

    /// A tick when it sends straight through, and **nothing** when it does not —
    /// the same pair `applyReplaceWisprIcon` draws. See the note on the row.
    private func applyAutosendIcon() {
        autosend.image = autosendOn ? Self.symbolIcon("checkmark") : Self.blankIcon
    }

    private let squelch = NSMenuItem(title: StartChime.menuTitle, action: nil, keyEquivalent: "")

    private let autoAttachItem = NSMenuItem(title: "Auto-attach", action: nil, keyEquivalent: "")
    private let autoAttachSubmenu = NSMenu()

    /// The tick is read from the defaults at every open, so `POST /test/auto-attach`
    /// and the menu cannot disagree; drawn like every switch here (`checkmark` /
    /// `blankIcon`, never `NSMenuItem.state`).
    private func applyAutoAttachRows() {
        autoAttachSubmenu.removeAllItems()
        for kind in AutoAttach.Kind.allCases {
            let row = NSMenuItem(title: kind.title, action: #selector(autoAttachClicked(_:)),
                                 keyEquivalent: "")
            row.target = self
            row.representedObject = kind.rawValue
            row.toolTip = kind.tooltip
            row.image = AutoAttach.isOn(kind) ? Self.symbolIcon("checkmark") : Self.blankIcon
            autoAttachSubmenu.addItem(row)
        }
    }

    @objc private func autoAttachClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = AutoAttach.Kind(rawValue: raw) else { return }
        AutoAttach.set(kind, !AutoAttach.isOn(kind))
        applyAutoAttachRows()
    }

    @objc private func squelchClicked() {
        StartChime.isOn.toggle()
        applySquelchIcon()
        StartChime.play()   // ticking it on plays it once, so he hears what he chose
        Log.info("Radio squelch \(StartChime.isOn ? "on" : "off") from the menu")
    }

    private func applySquelchIcon() {
        squelch.image = StartChime.isOn ? Self.symbolIcon("checkmark") : Self.blankIcon
    }

}
