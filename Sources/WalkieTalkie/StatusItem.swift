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

    /// Whether a screen recording is running right now. Asked when the menu
    /// opens, like the footprint and the key beside it: it flips twice a
    /// sentence, and the one moment its answer has to be right is the moment
    /// the row is drawn.
    var isFilming: (() -> Bool)?

    /// **Whether the cloud engine could transcribe a sentence this instant** —
    /// which, for a recogniser with nothing to load, is only ever *is there an
    /// API key*. Asked when the menu opens, like the two above and for their
    /// reason: the key is a file Victor can create while the app is running, and
    /// a row that answered from launch would go on saying *no API key* after he
    /// had put one there.
    var elevenReady: (() -> Bool)?



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

    /// Picked from **Start / Stop Screen Recording** — the same call 🔽 ↑
    /// makes, so the row and the gesture cannot drift apart.
    var onToggleScreenRecording: (() -> Void)?

    /// **Undo for the one verdict that could not be undone.** A cancel keeps its
    /// audio in Caches for five minutes; this transcribes it and sends it where a
    /// sentence would go now. Greyed out when there is nothing within the five
    /// minutes, which is nearly always — see `isRecoverable`.
    var onRecoverDictation: (() -> Void)?
    /// Is there a cancelled sentence still inside its five minutes? Asked when
    /// the menu opens, like every other flag here, because that is the one
    /// moment the answer has to be right.
    var isRecoverable: (() -> Bool)?

    /// Picked from **Start Dictation** — open the microphone, the same thing
    /// mouse 5 does. The other end of the pair that already had two ways out and
    /// only one way in.
    var onStartDictation: (() -> Void)?

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

    /// Picked from **Start dictation to new claude** — open the microphone with
    /// the spawn destination armed, exactly as the wheel clicked twice does.
    var onNewSession: (() -> Void)?

    /// Picked from **Take Screenshot** — the same picture the back button
    /// takes while dictating. The row is a disabled legend, so this is
    /// unreachable in practice; kept so the row is wired like the rest.
    var onShot: (() -> Void)?

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
    /// ⌘⌃B is not written on this row at all any more (Victor, 2026-09-06): it
    /// is the one gesture with a mouse route on the very same row, and a key
    /// equivalent for it existed only to be read — see `gestureRows`, where the
    /// single shortcut column now lives.
    ///
    /// **The gestures are drawn, not spelled.** `hold left, click the wheel` is
    /// six words describing two objects, and it was read in a menu opened for a
    /// second: `hold ⬅️ + 🛞` is the same sentence in the shape of the mouse it is
    /// about. Right-aligning them into the shortcut column was the first ask and
    /// is not something `NSMenuItem` offers — the column belongs to
    /// `keyEquivalent`, and a wheel is not a key — so it is drawn as one: the
    /// chord rides in an attributed title right-aligned to a tab stop set just
    /// left of the shortcut column, and the two columns line up. See
    /// `layOutGestures`, and `restyleGestures` for the price it costs.
    private let bind = NSMenuItem(title: "Connect Terminal", action: nil, keyEquivalent: "")

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
    /// spends its right-hand side on the gesture column that `layOutGestures`
    /// lines up. One arrow moved all of it (Victor, 2026-09-10: *"a fugit toată
    /// coloana de meniuri din cauza >"*).
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
    /// Opens the microphone from the menu — see `onStartDictation`. The wheel is
    /// the gesture written on the row; ⌘⌃D, which does the same thing from the
    /// keyboard, went off the menu with ⌘⌃B (Victor, 2026-09-06).
    private let startDictation = NSMenuItem(title: "Start Dictation", action: nil, keyEquivalent: "")
    private let stopRecording = NSMenuItem(title: "End Dictation", action: nil, keyEquivalent: "")
    /// Same row, opposite verdict — see `onCancelDictation`.
    private let cancelDictation = NSMenuItem(title: "Cancel Dictation", action: nil, keyEquivalent: "")
    /// **Start / Stop Screen Recording** (2026-09-18) — the film's own row, and
    /// it exists for the reason `Start Dictation` does: *"the wheel is one button
    /// on one specific mouse whose battery goes."* 🔽 ↑ is worse than the wheel
    /// on that count — it is a side button whose chord lives in a Logi Options+
    /// profile, so a fresh install, a flat battery or a profile that did not
    /// sync leaves the gesture silent and the feature with no way in at all.
    ///
    /// **One row that renames itself, not two.** The dictation rows are a pair
    /// because Start and End are different verbs with different gestures and
    /// `Cancel` sits between them; a recording has one verb and one gesture, and
    /// two rows of which one is always greyed would be saying *the other thing is
    /// impossible* twice over.
    private let screenRecording = NSMenuItem(title: "Start Screen Recording",
                                             action: nil, keyEquivalent: "")

    /// The undo of the row above it, and directly under it for that reason.
    private let recoverDictation = NSMenuItem(title: "Recover Cancelled Dictation",
                                              action: nil, keyEquivalent: "")
    /// A dictation whose destination is a terminal that does not exist yet — it
    /// opens in `~/workspace`, which the title no longer spells out: the folder
    /// never varies, so it was a word the row spent on something already known,
    /// where *what happens* is the half worth the width.
    ///
    /// **One gesture now, and it is the bare wheel clicked twice.** ⌘ + the
    /// wheel went on 2026-09-03 — a modifier claimed machine-wide for as long as
    /// the app runs was a steep price for a way in that needs the keyboard
    /// anyway — and ➡️ + 🛞 held a second went on 2026-09-06, because a chord
    /// that had to be told apart from itself made **Disconnect** wait for the
    /// finger to come up and put a session Victor had not asked for one timer
    /// away from every hurried tap.
    ///
    /// **The title says "start dictation" for the same reason the row sits
    /// under `Start Dictation`** (Victor, 2026-09-06): what it does is open the
    /// microphone, exactly like the row above it — the only difference is where
    /// the sentence lands, and a new session is the one destination that does
    /// not exist yet when the words start.
    private let newSession = NSMenuItem(title: "Start dictation to new claude", action: nil, keyEquivalent: "")
    /// The shutter. Its one route is named: the back button, only while a dictation
    /// is running — which is also the only window in which it stops typing
    /// Return.
    /// The last dictation, again — see `AppDelegate.pasteLastDictation`. Greyed
    /// until there is one, like every other row that cannot act right now.
    private let pasteLast = NSMenuItem(title: "Paste last prompt", action: nil, keyEquivalent: "")
    private let shot = NSMenuItem(title: "Take Screenshot", action: nil, keyEquivalent: "")
    /// **The other half of the shutter, and the only reason the wheel is
    /// touched at all in Logi mode.** A legend like the two rows around it: the
    /// gesture is a drag, which is not a thing a menu can perform.
    private let areaShot = NSMenuItem(title: "Select Screen Area", action: nil, keyEquivalent: "")
    /// **A legend row, and the only one here that is not a command.** ⌘⇧-click
    /// happens inside Chrome, in a page this app cannot reach from a menu — but
    /// it is a gesture the relay takes over, it used to be advertised on the chip
    /// while dictating, and with the chip silent there is nowhere else it could
    /// be said. Permanently disabled, which is the honest rendering of "this is
    /// something you do, not something you pick".
    private let pickLegend = NSMenuItem(title: "Pick Element in Chrome", action: nil, keyEquivalent: "")
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
    ///   Engine: Wispr Flow…
    ///        ✓ Wispr Flow
    ///          whisper-large-v3-turbo — 1.6 GB RAM
    /// ```
    ///
    /// **It is an ordinary submenu, with the arrow** — *"tre submeniu obișnuit
    /// cu >, nu un modal"* (Victor, 2026-09-14, having looked at the other one).
    ///
    /// It was a dispatched `popUp` for one build, on `Rebind to…`'s reasoning:
    /// one disclosure arrow makes AppKit reserve the gutter on *every* row and
    /// the gesture column `layOutGestures` lines up shifts with it (2026-09-10:
    /// *"a fugit toată coloana de meniuri din cauza >"*). That argument was
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

    /// **The two rows under the arrow**, rebuilt by `applyEngineRow` rather than
    /// by a delegate of its own: the names change only with the model's
    /// footprint, which `menuWillOpen` already re-reads for the row above.
    private let engineSubmenu = NSMenu()

    /// Which engine is live, as `AppDelegate` last reported it — `wispr` or
    /// `whisper`.
    ///
    /// **The tick is drawn from the app's answer, never from the click.** A
    /// switch asked for mid-sentence is refused, and a row that had ticked
    /// itself optimistically would be the only thing in the app claiming an
    /// engine that is not listening.
    private var engineId = "wispr"

    /// Victor picked one. `AppDelegate` swaps the source and calls `setEngine`
    /// back with whatever is actually running afterwards.
    var onPickEngine: ((String) -> Void)?

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
    private let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")

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

    /// `Microphone: 🎙️ Elgato Wave XLR` — **the device that would record right
    /// now**, which is not always the one ticked: a pick whose device has been
    /// unplugged falls back to automatic (`InputDevice.resolve`), and the row
    /// has to say what would actually happen rather than what was once asked
    /// for. The tick below stays on his choice, so the two together read as
    /// *you asked for the receiver, you are on the built-in* — which is the
    /// sentence he needs when a cable has come out.
    private func applyMicRow() {
        micItem.title = "Microphone: \(micCurrentLabel?() ?? "—")"
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
    private let logiGestures = NSMenuItem(title: "Mouse Gestures", action: nil, keyEquivalent: "")

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
    private let haloItem = NSMenuItem(title: "Halo fx", action: nil, keyEquivalent: "")
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
        let shared = picks.dropFirst().allSatisfy { $0 == picks[0] } ? picks[0] : nil
        // No readout while the three differ: the row would have to name one of
        // them, and naming one is exactly the claim that is not true.
        haloItem.title = shared.map { "Halo fx: \($0.menuTitle)" } ?? "Halo fx"
        haloSubmenu.removeAllItems()
        haloSubmenu.autoenablesItems = false
        for (destination, pick) in zip(HaloDestination.allCases, picks) {
            let row = NSMenuItem(title: "\(destination.title): \(pick.menuTitle)", action: nil, keyEquivalent: "")
            let list = NSMenu()
            list.autoenablesItems = false
            fillStyleRows(into: list, ticked: pick, destination: destination)
            row.submenu = list
            haloSubmenu.addItem(row)
        }
        // **`Fx engine`, last row of the same submenu** (Victor, 2026-09-21:
        // *"pune fx engine sub halo effects (în submeniu)"*) — one level down
        // from the styles, not a sibling row in the main menu.
        haloSubmenu.addItem(.separator())
        haloEngineItem.submenu = haloEngineSubmenu
        applyHaloEngineRow()
        haloSubmenu.addItem(haloEngineItem)
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
            // The film first and apart: the default, and the one drawn natively.
            if style == .lightning { menu.addItem(.separator()) }
        }
    }

    /// **`Halo engine: Web`, the shape `Engine` has** (the `projectm` branch,
    /// 2026-09-21): which engine draws a MilkDrop preset — butterchurn in a
    /// web view, or projectM natively. A readout with the two under the
    /// arrow, the tick drawn from `HaloEngine.current` on every open, so a
    /// `WT_HALO_ENGINE` run shows what is running. The film and the page
    /// effects are unaffected by it; the row says so.
    private let haloEngineItem = NSMenuItem(title: "Fx engine", action: nil, keyEquivalent: "")
    private let haloEngineSubmenu = NSMenu()
    var onPickHaloEngine: ((HaloEngine) -> Void)?

    private func applyHaloEngineRow() {
        let current = HaloEngine.current
        haloEngineItem.title = "Fx engine: \(Self.haloEngineTitle(current))"
        haloEngineSubmenu.removeAllItems()
        haloEngineSubmenu.autoenablesItems = false
        for engine in [HaloEngine.web, .native] {
            let row = NSMenuItem(title: Self.haloEngineTitle(engine), action: #selector(haloEnginePicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = engine.rawValue
            row.image = engine == current ? Self.symbolIcon("checkmark") : Self.blankIcon
            haloEngineSubmenu.addItem(row)
        }
        haloEngineSubmenu.addItem(.separator())
        let note = NSMenuItem(title: "For the MilkDrop presets only", action: nil, keyEquivalent: "")
        note.isEnabled = false
        haloEngineSubmenu.addItem(note)
    }

    private static func haloEngineTitle(_ e: HaloEngine) -> String {
        switch e {
        case .web:    return "Web (butterchurn)"
        case .native: return "Native (projectM)"
        }
    }

    @objc private func haloEnginePicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let engine = HaloEngine(rawValue: raw),
              engine != HaloEngine.current else { return }
        onPickHaloEngine?(engine)
        applyHaloEngineRow()
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

    /// **The build stamp, on a disabled row of its own, one row above Quit**
    /// (2026-09-13). It was the clickable About row (`Victor's Walkie Talkie
    /// (<build>)`, opening `AboutPage`) until Victor asked for the same plain
    /// `Version: <build>` readout in all three menu bar apps, for cleanliness.
    /// The About page is still one click away from the Dock tile's main menu.
    private let version = NSMenuItem(title: "Version: \(StatusItem.buildStamp)",
                                     action: nil, keyEquivalent: "")
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
        // could not begin. **Enabled with nothing bound too, since 2026-09-11**:
        // it was `isBound`, because unbound the relay was inert and
        // `startLocalRecording` would have refused anyway — and it no longer
        // does. A sentence spoken now is held for the terminal Victor is about to
        // point at (`AppDelegate.holdsForBind`), so the one row that begins a
        // dictation must not be the one thing still saying it cannot.
        startDictation.image = Self.symbolIcon("mic")
        startDictation.action = #selector(startDictationClicked)
        startDictation.target = self
        startDictation.isEnabled = false

        stopRecording.image = Self.symbolIcon("mic.slash")
        stopRecording.action = #selector(stopRecordingClicked)
        stopRecording.target = self
        stopRecording.isEnabled = false

        // **Directly under Stop, because it is the same moment with the other
        // answer.** Stopping sends what was said; this throws it away — the
        // sentence that came out wrong, the interruption, the dictation started
        // by accident. Without it the only way out of a bad recording was to
        // stop it, watch it transcribe, and cancel the panel — three steps and a
        // model run for something he already knew he did not want.
        recoverDictation.image = Self.symbolIcon("arrow.uturn.backward")
        recoverDictation.action = #selector(recoverDictationClicked)
        recoverDictation.target = self
        recoverDictation.isEnabled = false
        screenRecording.image = Self.symbolIcon("video")
        screenRecording.action = #selector(screenRecordingClicked)
        screenRecording.target = self
        screenRecording.isEnabled = false

        cancelDictation.image = Self.symbolIcon("trash")
        cancelDictation.action = #selector(cancelDictationClicked)
        cancelDictation.target = self
        cancelDictation.isEnabled = false

        // **Directly under `Start Dictation`, because it is the same verb**
        // (Victor, 2026-09-06). It was up with the destination rows, beside Bind
        // and Disconnect, on the argument that a new session is a destination —
        // but the row does not *make* one, it opens the microphone, and the
        // window appears when the sentence is over. Read as a pair with the row
        // above it, the two say the whole choice at the moment it is made: start
        // talking to the terminal that is bound, or to one that is not there
        // yet. Added to the menu further down, with that block.
        //
        // Enabled whether or not anything is bound — unlike every other row in
        // the block — because that is the whole point of the gesture: it carries
        // its own destination.
        // **`mic.badge.plus`, not 🆕** (Victor, 2026-09-21: *"să fie toate
        // monocrome"*). It was the last colour in the column beside ✨, and the
        // badge says the same thing the emoji did while reading as a pair with
        // `mic` above it and `mic.slash` below: the same verb, into one that is
        // not there yet.
        newSession.image = Self.symbolIcon("mic.badge.plus")
        newSession.action = #selector(newSessionClicked)
        newSession.target = self

        // **Under the dictation commands, because it is about the last one.**
        // Not a gesture that happens *during* a sentence like the two rows below,
        // and not a destination like the rows above: it is what he reaches for
        // once the words have landed somewhere and he wants them somewhere else
        // too — a commit message, a chat, a form.
        pasteLast.image = Self.symbolIcon("doc.on.clipboard")
        pasteLast.action = #selector(pasteLastClicked)
        pasteLast.target = self
        pasteLast.isEnabled = false
        menu.addItem(pasteLast)

        shot.image = Self.symbolIcon("camera")
        // **A legend, not a command — permanently disabled** (Victor, 2026-09-04),
        // the same rendering `pickLegend` uses for "this is something you do, not
        // something you pick". The shutter itself lives on the back button while
        // dictating; F3, its keyboard route, was never pressed and is gone.
        shot.action = #selector(shotClicked)
        shot.target = self
        shot.isEnabled = false
        areaShot.image = Self.symbolIcon("scissors")
        areaShot.isEnabled = false
        pickLegend.image = Self.symbolIcon("hand.raised")
        pickLegend.isEnabled = false
        // **A line between where the words go and what happens while they are
        // being said.** Victor's ask, and the regrouping is the half that makes
        // the line mean anything: the three rows above it are about a
        // *destination* — point at one, let it go, or paste the last sentence
        // somewhere by hand — and every row below it is a gesture made with a
        // dictation already open, or one of the two that open one.
        //
        // They were interleaved before, in the order each was written: the two
        // that are only live mid-sentence sat at the bottom, under `New Claude
        // Code` and `Paste the Last Dictation`, three rows below the dictation
        // block they belong to. A menu that is now the app's only legend
        // (*The chip teaches nothing; the menu does*) has to group by what a row
        // is *for*, since that is the question somebody reading it is asking.
        //
        // `Start Dictation` heads the block rather than sitting above the line.
        // It is not itself "while dictating" — it is the door into everything
        // that is, and a block whose first row is missing reads as four gestures
        // with no way in.
        menu.addItem(.separator())
        menu.addItem(startDictation)
        menu.addItem(newSession)
        menu.addItem(stopRecording)
        menu.addItem(cancelDictation)
        menu.addItem(recoverDictation)
        // **Under the dictation verbs, because it is one of them.** A recording
        // only exists inside a sentence, so the row belongs with the rows that
        // open and close one rather than down with the two gesture legends.
        menu.addItem(screenRecording)
        // **A line between the verbs that end a dictation and the two legends.**
        // Take Screenshot and Pick Element are both disabled rows now — gestures
        // written down, not commands — so they sit apart from the three rows
        // above that actually do something when clicked (Victor, 2026-09-04).
        menu.addItem(.separator())
        menu.addItem(shot)
        menu.addItem(areaShot)
        menu.addItem(pickLegend)

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
        applyEngineRow()
        menu.addItem(engineItem)

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

        messageLog.image = Self.symbolIcon("scroll")
        // **The row itself does nothing** — AppKit gives a parent row's click to
        // its submenu, so `Full Log` inside is the one way to the page. The
        // submenu is filled on hover; see `menuNeedsUpdate`.
        messageLog.submenu = promptHistorySubmenu
        promptHistorySubmenu.delegate = self
        applyPromptHistoryRow()
        menu.addItem(messageLog)

        menu.addItem(.separator())

        // **The build stamp is a disabled readout, not a row that does anything**:
        // it is read once a session, when the question is "am I looking at what
        // I just built?", and that is a question about the app rather than about
        // quitting. Quit is left saying the one thing it does.
        version.image = Self.symbolIcon("info.circle")
        version.isEnabled = false
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

        // **One column for every shortcut, mouse or key.**
        // Victor asked twice for the mouse chords to be right-aligned; the first
        // answer was that `NSMenuItem` does not offer it, which is true only of
        // the shortcut column itself. A right tab stop in an attributed title is
        // the same right edge drawn by hand. It sat *beside* AppKit's own ⌘⌃
        // column for a day — two columns, and rows with an entry in neither
        // straddling the gap — until (2026-09-06) the key equivalents went and
        // ⌘⇧P moved in here with the wheel. What is drawn is the whole legend.
        // **The vocabulary: an emoji for the button, a plain arrow for the
        // movement.** The emoji ones name a button by where it sits on the mouse
        // — `⬅️` and `➡️` are the left and right buttons, and since the two side
        // buttons are stacked, `🔼` is the forward one and `🔽` the back one.
        // A gesture made by holding a side button and moving the mouse writes the
        // button first and the direction after it as a text arrow (`🔼 →`), which
        // is a different weight and colour on screen from the boxed emoji and so
        // cannot be misread as a second button.
        //
        // The wheel's `🛞` went from every row here on 2026-09-09, along with
        // the chord rows `⬅️ + 🛞` and `➡️ + 🛞` — see *The side buttons speak in
        // function keys*. It is back in exactly one, `Select Screen Area`, and
        // the distinction that lets it be is that a **drag** is not a click:
        // middle-click-to-close-a-tab is untouched.
        // **The vocabulary: an emoji for the button, a thin arrow for the
        // movement.** The emoji names a button by where it sits on the mouse —
        // `◀️` and `▶️` are the left and right buttons, and because the two side
        // buttons are stacked, `🔼` is the forward one and `🔽` the back one. A
        // gesture made by holding a side button and moving the mouse writes the
        // button first and the direction after it as a text arrow (`🔼 →`).
        // Victor picked the filled triangles over `⬆️`/`⬇️` for exactly that
        // reason: against a thin `↑` the difference has to be visible at a
        // glance, and a boxed arrow next to a bare one is not.
        //
        // **Two legends per row**, because both gesture sets are live: the first
        // is what the row is performed with while *Use Logi Gestures* is ticked,
        // the second what it was before — the wheel's own vocabulary, where `🛞`
        // is the wheel and `+` joins a held modifier button to it. `restyleGestures`
        // picks, and it runs whenever the tick changes as well as on every open.
        gestureRows = [
            (bind, bind.title, "◀️ + 🔼", "◀️ + 🛞"),
            (disconnect, disconnect.title, "🔽 ↓", "▶️ + 🛞"),
            (startDictation, startDictation.title, "🔼 →", "🛞"),
            // Right under `Start Dictation`'s own gesture, which is the pair the
            // order is for: one talks to what is bound, the one above it talks to
            // a session that is not open yet.
            (newSession, newSession.title, "🔼 ↑", "🛞🛞"),
            // The same gesture as Start: it is one toggle, and writing it twice
            // is how the menu says so without a sentence.
            (stopRecording, stopRecording.title, "🔼 →", "🛞"),
            // The mirror direction of the one that starts it — the two gestures
            // that open and abandon a sentence are one hand movement, reversed.
            // The wheel had no mirror to offer and used a 2s hold instead.
            (cancelDictation, cancelDictation.title, "🔼 ←", "🛞 2s"),
            // **The same gesture in both columns**, because it is a side button
            // either way: the wheel set has nothing to offer here, and inventing a
            // wheel chord for it would walk into the two conflicts that sent this
            // gesture to a free row in the first place.
            (screenRecording, screenRecording.title, "🔽 ↑", "🔽 ↑"),
            (pasteLast, pasteLast.title, "⌘⇧P", "⌘⇧P"),
            (shot, shot.title, "🔽", "🔽"),
            // **The wheel is back in this column, in one row.** Everything else
            // it used to say is gone from Logi mode — but a *drag* is not a
            // click, so this one costs the middle click nothing. Written as the
            // button and then the movement, the vocabulary the side-button rows
            // already use, except that the direction is whichever way he draws
            // the box.
            (areaShot, areaShot.title, "🛞 drag", "🛞 drag"),
            // **No `+`, and the button drawn rather than spelled** (Victor,
            // 2026-09-09): the modifiers and the click are one continuous
            // gesture — hold ⌘⇧ and click — not two things added together, and
            // the chord column is narrow enough that a `+` is a character spent
            // on punctuation.
            (pickLegend, pickLegend.title, "⌘⇧◀️", "⌘⇧◀️"),
        ]
        layOutGestures(in: menu)

        item.menu = menu
        mirror.start()
    }

    /// The item, **its label**, and the chord it is performed with.
    ///
    /// **The label is stored and not read back off the item**, which is the bug
    /// that shipped: setting `attributedTitle` also rewrites `title`, so the
    /// second pass built `label \t chord \t chord` out of a title that already
    /// carried one, and every gesture row in the menu printed its chord twice on
    /// two lines. `restyleGestures` runs on every `menuWillOpen`, so it was the
    /// second open that broke it, not the first.
    private var gestureRows: [(item: NSMenuItem, label: String, logi: String, wheel: String)] = []
    /// The legend for the mode that is on right now.
    private func gesture(_ row: (item: NSMenuItem, label: String, logi: String, wheel: String)) -> String {
        logiGesturesOn ? row.logi : row.wheel
    }
    /// Where that column's right edge sits, measured from the widest row.
    private var gestureTab: CGFloat = 0

    /// **One tab stop for the whole menu**, so the chords line up with each other
    /// rather than each floating at the end of its own label. It is the widest
    /// of two things: the longest plain row in the menu, and the longest
    /// label + gap + chord — whichever it is, no row can then need more width
    /// than the column gives it, and none of them collide.
    ///
    /// **Re-measured on every open, not once at build** (2026-09-14). Half the
    /// rows get their real title long after the menu is assembled — `Engine:
    /// Local (2.6 GB)`, `Mouse Gestures: Wheel`, and above all `Bound to:
    /// <folder>@<branch>`, which is as long as the branch name is. A title wider
    /// than the tab widens the menu without moving the tab, and the chords then
    /// hang in the middle of a menu that has grown to the right of them.
    ///
    /// **The plain rows are read off `item.title`, the gesture rows off the
    /// stored label** — never off the item. A gesture row's `title` is the
    /// attributed one AppKit wrote back, `label \t chord`, so measuring *that*
    /// would add the chord a second time and push the column right on every
    /// open, one chord's width at a time.
    private func layOutGestures(in menu: NSMenu) {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        // Wide enough that the chord reads as a second column and not as the end
        // of the sentence — the same distance AppKit leaves before its own.
        let gap: CGFloat = 28
        var tab: CGFloat = 0
        let drawn = Set(gestureRows.map { ObjectIdentifier($0.item) })
        for item in menu.items
        where !item.isSeparatorItem && !drawn.contains(ObjectIdentifier(item)) {
            tab = max(tab, width(item.title))
        }
        // **Measured against the widest of *both* legend sets**, not just the one
        // showing: the tick can be flipped with the menu open, and a column that
        // resized under the pointer would move every chord on screen.
        for row in gestureRows {
            tab = max(tab, width(row.label) + gap + width(row.logi))
            tab = max(tab, width(row.label) + gap + width(row.wheel))
        }
        gestureTab = tab
        restyleGestures()
    }

    /// **The price of an attributed title: AppKit stops dimming the row.** A
    /// disabled item is greyed by the menu only while it is drawing the title
    /// itself; hand it an attributed string and the colours in that string are
    /// the last word, so a disabled `End Dictation` came out as black as a live
    /// one. The colour is therefore chosen here, and this runs from
    /// `menuWillOpen` — the one moment every `isEnabled` in the file is known to
    /// be current.
    private func restyleGestures() {
        let font = NSFont.menuFont(ofSize: 0)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: gestureTab)]
        for row in gestureRows {
            let ink: NSColor = row.item.isEnabled ? .labelColor : .disabledControlTextColor
            row.item.attributedTitle = NSAttributedString(
                string: "\(row.label)\t\(gesture(row))",
                attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: style])
        }
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

    /// `Engine: Local (2.6 GB)` while the local model is the one listening;
    /// `Engine: Wispr Flow` while the other one is.
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
        // **Wispr, local, then the two that upload — and it is the order of
        // trust** (2026-09-18). The default first, the offline fallback second,
        // and the ones that leave the Mac last: a list he scans while the menu
        // is open over his work should not put a billed, networked engine where
        // his eye lands first. Between the two cloud rows the order is the same
        // rule one level down — the one that uploads a file after the fact
        // before the one that streams while he speaks.
        for id in ["wispr", "whisper", "eleven"] {
            let row = NSMenuItem(title: engineTitle(id),
                                 action: #selector(enginePicked(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = id
            // The tick where every other switch in this menu draws it — never
            // `NSMenuItem.state`, which would reserve a second column.
            row.image = id == engineId ? Self.symbolIcon("checkmark") : Self.blankIcon
            engineSubmenu.addItem(row)
        }
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
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        Log.info("📋 a prompt from the history is on the clipboard (\(text.count) chars)")
    }

    /// **What one engine is called** — in the list, and in the row above it when
    /// it is the one running.
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
        // **The cloud engine's cost is its key, the way the local one's is its
        // weights** — and the row says which is missing for the same reason the
        // footprint is shown above: a number nobody can check belongs in a
        // comment, and *this engine cannot run right now* belongs in the list he
        // picks from. `$0.40/h` is there because it is the half of the trade a
        // menu can state and a comment cannot make him feel.
        if id == "eleven" {
            let model = ElevenLabsSource.model
            return elevenReady?() == true
                ? "ElevenLabs \(model) — \(ElevenLabsSource.rate), audio leaves this Mac"
                : "ElevenLabs \(model) — no API key"
        }
        guard id == "whisper" else { return "Wispr Flow" }
        let name = whisperModel?() ?? LocalWhisperSource.configuredModel
        if engineLoading { return "\(name) — loading…" }
        if let bytes = whisperFootprint?() {
            return String(format: "%@ — %.1f GB RAM", name, Double(bytes) / 1_073_741_824)
        }
        return name
    }

    /// **What the top-level row calls the same engine** — `Wispr Flow`, or
    /// `Local (2.6 GB)` with the footprint kept and the model id dropped.
    ///
    /// The size stays because it is the half that changes: it says the helper is
    /// alive and what it is costing right now, which is the whole argument for
    /// letting it go between dictations. The name goes because it does not —
    /// it is the same string every launch, and `engineTitle` has it in the list
    /// below for the one moment somebody asks.
    private func engineShortTitle(_ id: String) -> String {
        // ⚠️ rather than the price, because the top-level row is read out of the
        // corner of the eye: what he needs from it there is *the cloud one is
        // live and it cannot work*, and the reason is one hover away.
        if id == "eleven" { return elevenReady?() == true ? "ElevenLabs" : "ElevenLabs ⚠️" }
        guard id == "whisper" else { return "Wispr Flow" }
        if engineLoading { return "Local (loading…)" }
        guard let bytes = whisperFootprint?() else { return "Local" }
        return String(format: "Local (%.1f GB)", Double(bytes) / 1_073_741_824)
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
        startDictation.isEnabled = !recording
        stopRecording.isEnabled = recording
        cancelDictation.isEnabled = isDictationCancellable?() ?? recording
        // **Live only while a sentence is open**, which is the whole gate on the
        // gesture too — a film has to have something to belong to. The title is
        // the state readout: greyed it still says which of the two it would do,
        // so the row never claims a recording is running when none is.
        let filming = isFilming?() ?? false
        screenRecording.isEnabled = recording || filming
        screenRecording.title = filming ? "Stop Screen Recording" : "Start Screen Recording"
        // Not while one is running: two transcripts arriving at one panel is an
        // ordering problem there is no reason to create from a menu.
        recoverDictation.isEnabled = !recording && (isRecoverable?() ?? false)
        // The one row that does not ask about a binding — it brings its own
        // destination. Only a dictation already running takes it away: the row
        // *starts* one, and the sentence already open is re-aimed by the wheel's
        // second click, not from here.
        newSession.isEnabled = !recording
        // Take Screenshot is a legend now (disabled at construction), so there
        // is nothing to re-enable here.
    }

    private func refreshGlyph() {
        // The picture says bound; the badge in front of it says the one state
        // that is *not* about where the words go — whether the next sentence will
        // have a recogniser to reach. ⏸️ used to share this slot; there is no
        // pause any more.
        let badge = engineLoading ? "⏳" : ""
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
    private static let buildStamp: String = {
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
    @objc private func screenRecordingClicked() { onToggleScreenRecording?() }
    @objc private func recoverDictationClicked() { onRecoverDictation?() }
    @objc private func startDictationClicked() { onStartDictation?() }
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
    @objc private func newSessionClicked() { onNewSession?() }
    @objc private func shotClicked() { onShot?() }
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
        applyEngineRow()
        // Devices come and go while the app runs, and the only moment this list
        // has to be right is the moment he is looking at it.
        applyMicRow()
        applyHaloRow()
        applyHaloEngineRow()
        applyStopRecording()
        pasteLast.isEnabled = hasLastDictation?() ?? false
        // Re-measured, not just re-inked: `applyHeader` and `applyEngineRow`
        // above have just written the titles that are longest, and the column
        // has to be laid out against the menu he is about to see.
        layOutGestures(in: menu)
    }

    /// **`Bound to: petclinic@main`**, not the bare line the chip shows.
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
        header.title = destination.map { "Bound to: \($0)" } ?? "Unbound"
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




    /// Push the mode in from outside, the shape `setReplaceWispr` has.
    func setLogiGestures(_ on: Bool) {
        logiGesturesOn = on
        UserDefaults.standard.set(on, forKey: Self.logiGesturesKey)
        applyLogiGesturesRow()
        // **The legend column is rewritten, not just the tick.** The menu is
        // where every gesture is written down, and a row saying `🔼 →` on a Mac
        // whose forward button does nothing is worse than no legend at all.
        restyleGestures()
    }

    @objc private func gesturesPicked(_ sender: NSMenuItem) {
        guard let on = sender.representedObject as? Bool, on != logiGesturesOn else { return }
        setLogiGestures(on)
        onToggleLogiGestures?(logiGesturesOn)
    }

    /// `Mouse Gestures: Logi` or `: Wheel`, and the tick beside whichever of the
    /// two rows is the one wired up. See the note on the row.
    private func applyLogiGesturesRow() {
        logiGestures.title = "Mouse Gestures: \(logiGesturesOn ? "Logi" : "Wheel")"
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

}
