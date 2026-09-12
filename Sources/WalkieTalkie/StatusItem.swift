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
    /// **Replace Wispr** — see `AppDelegate.replaceWispr`. A mode, not a command:
    /// the forward side button becomes the microphone and every dictation is
    /// pasted at the caret instead of being typed at an agent.
    var onToggleReplaceWispr: ((Bool) -> Void)?
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

    /// **Is there a dictation to cancel** — which is not the same question as
    /// `isRecording`. Since 2026-09-12 the row kills a Wispr Flow dictation too,
    /// and that one is nothing this app is *recording*: every other row that
    /// reads `isRecording` (Start Dictation, New Session, Recover) is asking
    /// about the relay's own microphone and must go on asking only about that.
    /// Absent, it falls back to `isRecording`, which is what it used to be.
    var isDictationCancellable: (() -> Bool)?

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
    /// 2026-09-07 that drawing is a **`checkmark`**, the same mark
    /// `Replace WisprFlow` carries one row up (Victor: *"autosend să aibă bifă
    /// în față, nu ⏩ când e activ"*).
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
    ///
    /// **`Replace WisprFlow` persists too**, since 2026-09-07 — the note on
    /// `replaceWisprOn` says what it cost to give up the argument that kept it
    /// from doing so.
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
    /// **The mode row.** It sits beside `Autosend` because the two are the only
    /// switches in this menu — everything above them is something that happens
    /// once, when clicked.
    ///
    /// The title names both halves of what changes, because both are surprising:
    /// a button that did nothing for this app starts recording, and the words
    /// stop going to the terminal the header above still names.
    ///
    /// **The icon column is the tick** (Victor, 2026-09-07): nothing at all when
    /// the mode is off, a `checkmark` in front of the words when it is on. It
    /// carried `⌨️` in that column and its state in `NSMenuItem.state`, which is
    /// the arrangement `Autosend` had already given up one row below and for the
    /// same reason — a ticked row makes AppKit reserve the state column for the
    /// **whole** menu, so switching this one mode on shoved every other row
    /// sideways. The `⌨️` is what pays for the tick, and it is the cheaper half:
    /// it said *the destination is wherever the caret is*, which is what the
    /// title says in words, while the tick is the only place the mode can be
    /// read at all.
    ///
    /// **Off is blank, not an ✕.** Asked for as either — *"un X când e dezactivat
    /// … sau mai bine chiar … nimic"* — and blank is the one that leaves the row
    /// looking like the commands above it when the mode is doing nothing. It is
    /// still an image, transparent and exactly the size of the others, so the
    /// title does not step left the moment the tick goes.
    private let replaceWispr = NSMenuItem(title: "Replace WisprFlow", action: nil, keyEquivalent: "")
    /// Mirrors what the `replaceWispr` row means, since the row no longer carries
    /// a `state` to read it back from — the same shape `autosendOn` has.
    ///
    /// **It survives a restart** (Victor, 2026-09-07), and it is the second of
    /// the two switches to give that argument up. The argument was the stronger
    /// one of the pair: autosend changes *how long* the panel waits, while this
    /// changes **where the words go**, so a tick that came back on its own would
    /// put a dictation meant for a bound agent into whatever field held the
    /// caret, weeks after he had forgotten it was set. What overrules it is that
    /// the mode is not a setting he drifts into — it is how he dictates for a
    /// whole stretch of work, and re-ticking it every launch is a tax charged on
    /// the one gesture that exists to save typing. The tick is still one click
    /// away and the chip still says `⌨️ at the caret` on every sentence it
    /// takes, so a mode left on is visible before a word is spoken.
    private var replaceWisprOn = UserDefaults.standard.bool(forKey: StatusItem.replaceWisprKey)

    /// **Use Logi Gestures** — which mouse the app thinks it is holding.
    ///
    /// Ticked (the default): the side buttons arrive as ⌃⌥⌘F3…F12 from Logi
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
    /// rebuilt. The tick is the way back in the meantime.
    ///
    /// **Defaults to on, and that needs saying** because `bool(forKey:)` answers
    /// false for a key that was never written, which would have shipped the old
    /// gestures to a Mac already configured for the new ones.
    private let logiGestures = NSMenuItem(title: "Use Logi Gestures", action: nil, keyEquivalent: "")
    private var logiGesturesOn: Bool =
        UserDefaults.standard.object(forKey: StatusItem.logiGesturesKey) as? Bool ?? true
    private static let logiGesturesKey = "useLogiGestures"

    /// What the row is set to right now — read once at launch by `AppDelegate`,
    /// like `isReplaceWispr`.
    var isLogiGestures: Bool { logiGesturesOn }
    /// The tap has to be told; `AppDelegate` owns that wire.
    var onToggleLogiGestures: ((Bool) -> Void)?

    // ── Wrap Wispr Flow ─────────────────────────────────────────────────────

    /// **Wrap Wispr Flow** — whether the relay takes Wispr's paste and delivers
    /// the words itself (ticked, the default since 2026-09-12) or lets Wispr
    /// insert them wherever the focus is and only draws the ring.
    ///
    /// It is the switch the whole *Wispr Flow everywhere* change rests on, and
    /// it is in the menu for the reason the mode it replaces is: if a Wispr
    /// update changes how it delivers, the failure is a dictation that lands
    /// nowhere, and the way back has to be one click rather than a rebuild.
    ///
    /// **Defaults to on, and that needs saying** because `bool(forKey:)` answers
    /// false for a key that was never written.
    private let wrapWispr = NSMenuItem(title: "Wrap Wispr Flow", action: nil, keyEquivalent: "")
    private var wrapWisprOn: Bool =
        UserDefaults.standard.object(forKey: StatusItem.wrapWisprKey) as? Bool ?? true
    private static let wrapWisprKey = "wrapWispr"
    /// Read once at launch by `AppDelegate`, like `isReplaceWispr`.
    var isWrapWispr: Bool { wrapWisprOn }
    var onToggleWrapWispr: ((Bool) -> Void)?

    @objc private func wrapWisprClicked() {
        wrapWisprOn.toggle()
        UserDefaults.standard.set(wrapWisprOn, forKey: Self.wrapWisprKey)
        applyWrapWisprIcon()
        onToggleWrapWispr?(wrapWisprOn)
    }

    private func applyWrapWisprIcon() {
        wrapWispr.image = wrapWisprOn ? Self.symbolIcon("checkmark") : Self.blankIcon
    }
    /// The other preference key — see the note on `autosendKey`.
    private static let replaceWisprKey = "replaceWispr"

    /// What the row is set to right now — read once at launch by `AppDelegate`,
    /// so the restored tick and the behaviour behind it start out agreeing, the
    /// same shape `isAutosend` has.
    var isReplaceWispr: Bool { replaceWisprOn }
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
    private let messageLog = NSMenuItem(title: "Prompt Log", action: nil, keyEquivalent: "")
    /// The one recogniser row — a readout, not a switch. See `applyWhisperTitle`.
    private let whisperItem = NSMenuItem(title: "Local Whisper", action: nil, keyEquivalent: "")
    /// **The app, named and dated, one row above Quit.** It carries the build
    /// stamp Quit used to, and clicking it opens a small page with the repository
    /// the code came from — the one fact about this app that is nowhere on the
    /// machine it runs on.
    private let about = NSMenuItem(title: "Victor's Walkie Talkie (\(StatusItem.buildStamp))",
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

        bind.image = Self.symbolIcon("mappin", tint: Self.pinRed)
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
        disconnect.image = Self.symbolIcon("mappin.slash", tint: Self.pinRed)
        disconnect.action = #selector(disconnectClicked)
        disconnect.target = self
        disconnect.isEnabled = false
        menu.addItem(disconnect)

        // **Under Disconnect, because it is the third answer to the same
        // question.** Connect points at what is in front, Disconnect lets go, and
        // this one points at something that is *not* in front — the case neither
        // of the other two can express, and the common one by the afternoon.
        rebind.image = Self.symbolIcon("clock.arrow.circlepath", tint: Self.pinRed)
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
        cancelDictation.image = Self.emojiIcon("🗑️")
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
        newSession.image = Self.emojiIcon("✨")
        newSession.action = #selector(newSessionClicked)
        newSession.target = self

        // **Under the dictation commands, because it is about the last one.**
        // Not a gesture that happens *during* a sentence like the two rows below,
        // and not a destination like the rows above: it is what he reaches for
        // once the words have landed somewhere and he wants them somewhere else
        // too — a commit message, a chat, a form.
        pasteLast.image = Self.emojiIcon("📋")
        pasteLast.action = #selector(pasteLastClicked)
        pasteLast.target = self
        pasteLast.isEnabled = false
        menu.addItem(pasteLast)

        shot.image = Self.emojiIcon("📷")
        // **A legend, not a command — permanently disabled** (Victor, 2026-09-04),
        // the same rendering `pickLegend` uses for "this is something you do, not
        // something you pick". The shutter itself lives on the back button while
        // dictating; F3, its keyboard route, was never pressed and is gone.
        shot.action = #selector(shotClicked)
        shot.target = self
        shot.isEnabled = false
        areaShot.image = Self.emojiIcon("✂️")
        areaShot.isEnabled = false
        pickLegend.image = Self.emojiIcon("✋")
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
        // **A line between the verbs that end a dictation and the two legends.**
        // Take Screenshot and Pick Element are both disabled rows now — gestures
        // written down, not commands — so they sit apart from the three rows
        // above that actually do something when clicked (Victor, 2026-09-04).
        menu.addItem(.separator())
        menu.addItem(shot)
        menu.addItem(areaShot)
        menu.addItem(pickLegend)

        menu.addItem(.separator())

        replaceWispr.action = #selector(replaceWisprClicked)
        replaceWispr.target = self
        applyReplaceWisprIcon()
        menu.addItem(replaceWispr)

        wrapWispr.action = #selector(wrapWisprClicked)
        wrapWispr.target = self
        applyWrapWisprIcon()
        menu.addItem(wrapWispr)

        logiGestures.action = #selector(logiGesturesClicked)
        logiGestures.target = self
        applyLogiGesturesIcon()
        menu.addItem(logiGestures)

        autosend.action = #selector(autosendClicked)
        autosend.target = self
        applyAutosendIcon()
        menu.addItem(autosend)

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
        messageLog.image = Self.emojiIcon("📜")
        messageLog.action = #selector(messageLogClicked)
        messageLog.target = self
        menu.addItem(messageLog)

        whisperItem.isEnabled = false
        menu.addItem(whisperItem)
        applyWhisperTitle()

        menu.addItem(.separator())

        // **The build stamp moved onto About**, which is the row it was always
        // describing: it is read once a session, when the question is "am I
        // looking at what I just built?", and that is a question about the app
        // rather than about quitting. Quit is left saying the one thing it does.
        about.image = Self.emojiIcon("ℹ️")
        about.action = #selector(aboutClicked)
        about.target = self
        menu.addItem(about)

        // No ⌘Q key equivalent: the app never becomes key, so the hint would
        // advertise a shortcut that does nothing outside the open menu.
        let exit = NSMenuItem(title: "Quit", action: #selector(exitClicked), keyEquivalent: "")
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
        // ⌘⌃P moved in here with the wheel. What is drawn is the whole legend.
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
            // **The caret dictation finally has a legend.** It never had one: it
            // lived on mouse 5, which the menu had no glyph for, so the only
            // place the gesture was written down was a doc comment. It is a plain
            // click of the forward button, and it only means anything while this
            // row is ticked.
            (replaceWispr, replaceWispr.title, "🔼", "🖱️5"),
            (pasteLast, pasteLast.title, "⌘⌃P", "⌘⌃P"),
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
    /// Where that column's right edge sits, measured once from the widest row.
    private var gestureTab: CGFloat = 0

    /// **One tab stop for the whole menu**, so the chords line up with each other
    /// rather than each floating at the end of its own label. It is the widest
    /// of two things: the longest plain row in the menu, and the longest
    /// label + gap + chord — whichever it is, no row can then need more width
    /// than the column gives it, and none of them collide.
    private func layOutGestures(in menu: NSMenu) {
        let font = NSFont.menuFont(ofSize: 0)
        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        // Wide enough that the chord reads as a second column and not as the end
        // of the sentence — the same distance AppKit leaves before its own.
        let gap: CGFloat = 28
        var tab: CGFloat = 0
        for item in menu.items where !item.isSeparatorItem { tab = max(tab, width(item.title)) }
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
        // **The bare model name, and nothing else.** `Local Whisper` named a
        // category back when there were two recognisers to choose between; with
        // one left, the category is the half that says nothing and the id is the
        // half a comparison is written down against. The org prefix goes with it
        // — `mlx-community/` is where the weights were downloaded from, not what
        // is doing the listening.
        let name = whisperModel?().map { $0.split(separator: "/").last.map(String.init) ?? $0 }
            ?? "Local Whisper"
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
        startDictation.isEnabled = !recording
        stopRecording.isEnabled = recording
        cancelDictation.isEnabled = isDictationCancellable?() ?? recording
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

    /// Google Maps' own marker red, because that is the picture Victor named when
    /// he asked for the pin — and a red pin among a column of monochrome symbols
    /// is also the one row the eye finds without reading.
    private static let pinRed = NSColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1)

    /// **The icon column, and why it has two sources.**
    ///
    /// Emoji are what was asked for and they carry their own colour, but Unicode
    /// has no crossed-out map pin and no crossed-out microphone. Both of those are
    /// the *off* half of a pair, and a pair whose halves come from two different
    /// alphabets reads as two unrelated rows — so **Connect/Disconnect and
    /// Start/End are SF Symbols on both sides**, where the slash exists and is
    /// drawn by the same hand as the thing it crosses, and every row without an
    /// off state is an emoji.
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
    private static func emojiIcon(_ emoji: String) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        let text = emoji as NSString
        let ink = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: ((size.width - ink.width) / 2).rounded(),
                              y: ((size.height - ink.height) / 2).rounded()),
                  withAttributes: attrs)
        image.unlockFocus()
        return image
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

    @objc private func aboutClicked() { AboutPage.openInBrowser() }

    private var destination: String?

    /// The label is read when the menu opens rather than pushed on a timer: it
    /// changes with the branch, and the only moment it has to be right is the
    /// moment he is looking at it.
    func menuWillOpen(_ menu: NSMenu) {
        // **Only the menu itself.** AppKit sends this to any menu this object is
        // the delegate of, and every line below is about the top-level rows — a
        // popped-up list re-running the header and the gesture column would be
        // work done for nothing, on the one path this feature promised to keep
        // cheap.
        guard menu === item.menu else { return }
        SessionLabel.refresh()
        applyHeader()
        applyWhisperTitle()
        applyStopRecording()
        pasteLast.isEnabled = hasLastDictation?() ?? false
        restyleGestures()
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

    /// **The state lives here, not in `AppDelegate`.** It is a property of the
    /// checkbox — nothing else in the app has any use for it except the one call
    /// that reads it back — and keeping it on the row is what makes the tick and
    /// the behaviour impossible to disagree about.
    /// Push the mode in from outside — the loopback test route. The tick is the
    /// only place Victor can read the answer, so anything that changes the mode
    /// has to come through here.
    func setReplaceWispr(_ on: Bool) {
        replaceWisprOn = on
        UserDefaults.standard.set(on, forKey: Self.replaceWisprKey)
        applyReplaceWisprIcon()
    }

    @objc private func replaceWisprClicked() {
        setReplaceWispr(!replaceWisprOn)
        onToggleReplaceWispr?(replaceWisprOn)
    }

    /// The tick, or the space where one would be. See the note on the row.
    private func applyReplaceWisprIcon() {
        replaceWispr.image = replaceWisprOn ? Self.symbolIcon("checkmark") : Self.blankIcon
    }

    /// Push the mode in from outside, the shape `setReplaceWispr` has.
    func setLogiGestures(_ on: Bool) {
        logiGesturesOn = on
        UserDefaults.standard.set(on, forKey: Self.logiGesturesKey)
        applyLogiGesturesIcon()
        // **The legend column is rewritten, not just the tick.** The menu is
        // where every gesture is written down, and a row saying `🔼 →` on a Mac
        // whose forward button does nothing is worse than no legend at all.
        restyleGestures()
    }

    @objc private func logiGesturesClicked() {
        setLogiGestures(!logiGesturesOn)
        onToggleLogiGestures?(logiGesturesOn)
    }

    /// The tick, or the space where one would be. See the note on the row.
    private func applyLogiGesturesIcon() {
        logiGestures.image = logiGesturesOn ? Self.symbolIcon("checkmark") : Self.blankIcon
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
