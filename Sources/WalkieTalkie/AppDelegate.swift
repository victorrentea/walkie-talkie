import AppKit
import ServiceManagement
import ApplicationServices
import VictorMacKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlay: RelayWindow!
    private var status: StatusItem!
    private var snapshotSignal: DispatchSourceSignal?
    private let hotkeys = HotkeyTap()
    private let picker = ElementPicker()

    /// Pauses whatever Chrome is playing for the length of a dictation, and
    /// resumes exactly that afterwards. Driven from `syncBorrowedGestures`, the
    /// one place that already knows when the window opens and closes.
    private let music = MusicBridge()
    /// **The ring round the pointer for the whole of every dictation**, breathing
    /// on his voice — see `CaretHalo`. Since 2026-09-11 it is also the answer to
    /// *is it still hearing me?*, which the chip gives beside the cursor and
    /// therefore in the one place he is not looking while he talks. The 84pt
    /// microphone on the bottom edge that used to answer it is gone: *"în loc de
    /// microfonul care apare jos pe centrul ecranului, aș dori ca fulgerele să
    /// pulseze în același ritm al discuției"*.
    private let caretHalo = CaretHalo()

    /// Keeps every dictation's **recording** beside the model's reading of it,
    /// so a recogniser can be measured on Victor's own voice later. It changes
    /// nothing about what the agent receives — see `VoiceCorpus`.
    private let corpus = VoiceCorpus()

    /// **The local recogniser, retired from every gesture on 2026-09-12** and
    /// kept as a fallback — see `LocalWhisperSource`. The weights are no longer
    /// loaded at launch; nothing below names it except the menu row that selects
    /// it and the five-minute recovery that re-reads a cancelled WAV.
    private let whisperSource = LocalWhisperSource()

    /// **Wispr Flow, driven and read as if it were this app's own microphone** —
    /// see `WisprFlowSource`. `lazy`, because it takes the event tap: the wrap
    /// rests on seeing the ⌘V Wispr posts before the front app does.
    private lazy var wisprSource = WisprFlowSource(hotkeys: hotkeys)

    /// **Where the words come from, and the only thing below this line that
    /// knows there is more than one answer.**
    ///
    /// Victor, 2026-09-12: *Wispr Flow is the dictation source for everything*,
    /// the bound relay included. Everything downstream — the chip, the halo, the
    /// settle, the corpus, the held prompt, the caret paste — reads
    /// `DictationSource` and cannot tell which recogniser it is serving, which
    /// is the whole point: the Wispr path spent a month with no transcript in it
    /// precisely because it was a second branch nobody exercised.
    ///
    /// `WT_SOURCE=whisper` (or the menu's *Dictation source* row) picks the
    /// local model instead.
    private lazy var source: DictationSource = {
        let wanted = ProcessInfo.processInfo.environment["WT_SOURCE"]?.lowercased()
            ?? UserDefaults.standard.string(forKey: "dictationSource")
        return wanted == "whisper" || wanted == "local" ? whisperSource : wisprSource
    }()

    /// **The dictation is over but the words have not landed yet.**
    ///
    /// Victor, 2026-09-12: the ring and the chevrons go away when the text is
    /// *inserted*, not when the microphone closes. Between those two is the whole
    /// of the transcription — another app's round trip for Wispr Flow, the
    /// model's for the local one — and it is exactly the stretch in which he is
    /// waiting and has nothing to look at.
    ///
    /// **The source ends it**, and there is no pasteboard poll here any more:
    /// waiting for a transcript is the recogniser's business, and the settle is
    /// over when `didTranscribe` or `didEnd` says so. `settleTimeout` is the
    /// backstop for a source that answers neither.
    private var settling = false
    /// What the ring was saying about the destination when the microphone closed,
    /// so the chevrons do not disarm underneath the settle.
    private var settlingAtCaret = false
    private var settlingFrom: CFAbsoluteTime = 0
    private var settleGiveUp: DispatchWorkItem?
    /// **The longest the ring waits for words that may never come — 20 s.**
    ///
    /// It was 6, which is the *average* of Wispr's round trip (2.6 s) with room
    /// over it, and on 2026-09-12 Victor watched the ring go dark while the
    /// words were still coming: measured that evening, 5.9 s on one sentence and
    /// past six on another, against a fleet maximum of 22.8 s. The ring's whole
    /// job in this stretch is *they are on their way*, so ending it early is the
    /// one thing it must not do.
    ///
    /// Shorter than `WisprFlowSource.captureTimeout` on purpose: the capture
    /// costs a flag and can afford to wait 30 s, the ring is on screen and a
    /// beacon standing for half a minute over nothing would stop meaning
    /// anything.
    private static let settleTimeout: TimeInterval = 20

    /// **The gesture that opens a microphone has been seen and the microphone
    /// has not.** Only a source whose recorder lives in another process has a
    /// gap here worth drawing — see `DictationSource.didMaybeBegin`.
    private var speculative = false

    /// What was in front when the dictation started, for the message's `app`
    /// field. Read at the press, not at the end: by the time the words come back
    /// he has usually switched away.
    private var localRecordingApp: String?

    /// The terminal dictations are typed into, when Victor has pointed the relay
    /// at one. Unbound, everything below behaves exactly as it did before this
    /// existed — the outbox is still written, and the skill's watcher still
    /// reads it.
    private let terminal = TerminalBinding()

    /// Text that happened to be selected when the dictation opened. There is
    /// no shortcut for this any more and none is needed: if something was
    /// selected, it is simply picked up — Victor dictates *about* what he has
    /// highlighted, so the selection is the subject of the sentence.
    private var pendingSelection: String?

    /// Text he highlighted **later in the same dictation**, each stamped with
    /// where in the sentence he was when he took the shot that carried it.
    ///
    /// `pendingSelection` above is still frozen at the first non-empty read and
    /// still means what it always meant: the subject he started talking about.
    /// This is the other thing that happens in a long dictation — he keeps
    /// talking, highlights a second line, presses the shutter, highlights a
    /// third. Overwriting the frozen one with each of those would lose the
    /// subject; ignoring them loses everything he pointed at after the first
    /// sentence. So they accumulate beside it, in order, with their offsets.
    ///
    /// Only the shutter fills this (`plusOneShot`), which is what keeps it
    /// honest: a selection lands here because he deliberately took a picture
    /// while it was highlighted, not because the caret happened to be somewhere
    /// when a timer fired.
    private var pendingExtraSelections: [(at: TimeInterval, text: String)] = []

    /// The screen Victor was looking at when he started talking, captured
    /// automatically. Offered as context ("look if you need to"), unlike the
    /// deliberate ⌃⌥P shots which are things he wants seen.
    private var pendingScreen: String?

    /// Deliberate ⌃⌥P shots taken while a dictation is in flight.
    private var pendingShots: [String] = []

    /// What was in front when each picture was taken — `Chrome — Gmail – Inbox`,
    /// `IntelliJ IDEA — OwnerController.java` — keyed by the path of the frame it
    /// belongs to.
    ///
    /// **A dictionary and not a fourth parallel array.** `pendingShots` and
    /// `pendingShotOffsets` already run alongside each other under one lock, and
    /// the automatic context screen lives in a field of its own rather than in
    /// either of them; a third list would have to be kept in step with two
    /// different things at once. Keyed by path, the source travels with the
    /// picture no matter which of those two routes the picture took.
    private var shotSources: [String: String] = [:]
    /// When each deliberate shot was taken, in seconds since this dictation
    /// opened — parallel to `pendingShots`, written under the same lock.
    ///
    /// Wall-clock times would say nothing: what makes a shot findable in a
    /// three-minute dictation is *where in the sentence* it was taken, and the
    /// only clock that measures that starts when he starts talking.
    private var pendingShotOffsets: [TimeInterval] = []
    /// Elements ⌘-clicked in Chrome, waiting for the sentence they belong to.
    ///
    /// Taken **during** the dictation, like the deliberate shots — ⌘ in Chrome is
    /// the relay's only while the recording row is up (`syncBorrowedGestures`), so
    /// a pick is always something he did mid-sentence, while pointing at what he
    /// was in the middle of saying.
    ///
    /// Unlike shots they are still **not** cleared when a dictation opens, because
    /// Cancel puts them back: a cancelled prompt leaves the picks in the queue for
    /// the next attempt, and those legitimately predate the dictation they end up
    /// riding — which is why the stamps can still come out negative.
    private var pendingPicks: [ElementPick] = []

    /// A pick nobody ever spoke about is not context, it is litter — a queue left
    /// behind by a cancelled prompt he never retried. Ten minutes is longer than
    /// any gap between cancelling and saying it again, and short enough that this
    /// morning's browsing cannot ride into this afternoon's prompt.
    private let pickTTL: TimeInterval = 600

    /// When the current dictation opened, i.e. the zero of those offsets.
    private var dictationStartedAt: Date?
    private var dictationInFlight = false
    private var orphanFlush: DispatchWorkItem?

    /// The context shot is promised but `screencapture` has not come back yet.
    ///
    /// It counts as a picture from the instant the dictation opens, because that
    /// is when he took it — by starting to talk. Waiting for the file meant the
    /// row appeared saying `📸 ×0` and only became `×1` the best part of a second
    /// later, once a clipboard probe and a subprocess had both finished: a count
    /// that reads zero while a picture is being taken is simply wrong, and it is
    /// wrong in the one moment he looks at the row. It drops back to zero if the
    /// capture actually fails, which is the only case where zero is the truth.
    private var contextShotPending = false
    /// The bare-wheel dictation whose context shot is taken at the wheel's
    /// release rather than at the press (`startLocalRecording(deferContext:)`,
    /// consumed by `onWheelRelease`). **Only ever set with *Use Logi Gestures*
    /// off** — a Logi gesture ends with the mouse already moved, so there is no
    /// release worth waiting for and the shot is taken at the press.
    private var contextAtWheelRelease = false

    // MARK: - The cancelled sentence, kept for five minutes

    /// **A cancel throws the audio away, and for five minutes it does not.**
    ///
    /// Victor's ask, 2026-09-10: *"reține înregistrarea audio respectivă pe disk
    /// după cancel 5 minute, în caz că vreau totuși s-o recuperez + menu entry
    /// de rigoare."*
    ///
    /// Cancelling is the one verdict in this app that cannot be taken back —
    /// which is why it costs a two-second hold, and why that hold is described
    /// as the confirmation dialog the gesture does not have. The hold protects
    /// against the *slip*; it does nothing about the change of mind, and a
    /// sentence spoken once is gone in a way a screenshot never is. Five minutes
    /// is long enough to notice and short enough that this is a safety net
    /// rather than a second outbox: the file lives in Caches and is deleted by
    /// the clock whether or not he looks.
    ///
    /// What comes back is **the words and nothing else**. The shots, the picked
    /// elements and the highlights the cancelled dictation had gathered are
    /// cleared at the cancel and stay cleared: those are cheap to take again and
    /// the screen has moved on, which is the same reasoning `releaseHeld` uses
    /// when it restores picks but not frames.
    private var cancelledAudio: (url: URL, at: Date, duration: TimeInterval)?
    private var cancelledSweep: DispatchWorkItem?
    private static let cancelledGrace: TimeInterval = 300

    private let stateLock = NSLock()

    /// A dictation that never arrives (nothing was said, or the model returned
    /// nothing) must not strand the shots. After this long with no transcript
    /// they are released as a message of their own.
    private let orphanTimeout: TimeInterval = 120

    /// **Send the transcript without asking.** Held here and nowhere else, and
    /// **restored from the last launch** — see the menu row it comes from
    /// (`StatusItem.autosendOn`), which owns the stored value; this is seeded
    /// from it once the menu exists and then only ever moves through
    /// `onToggleAutosend`, so there is one writer and no second copy to drift.
    ///
    /// The panel still opens; it opens for `autosendHold` with no buttons on it.
    /// The receipt is the half of it that survives, because a dictation that
    /// vanished into a terminal with nothing shown would be the one state where he
    /// cannot tell a delivery from a drop.
    private var autosend = false
    private var endAnnounced = false

    /// **There is a destination, so a dictation is the relay's business.**
    ///
    /// Unbound the app does nothing at all: no dictation can be started, mouse 4
    /// and mouse 5 and ⌘⇧-click stay with the software they belong to, no picture
    /// is taken, and no line is written. It bails out of `captureContext`,
    /// `plusOneShot`, `send` and `syncBorrowedGestures` — plus `syncLocalCapture`,
    /// which is where the microphone's claim on the wheel lives. **It is the only
    /// such gate now**: pause used to bail out of the same four and is gone.
    ///
    /// Why this became necessary: the relay was started per session and lived
    /// only as long as Victor was dictating at an agent, so "running" and "aimed
    /// at something" were the same fact. Since 2026-08-26 it is a login item and
    /// sits there all day — and every one of those behaviours was being applied
    /// to every sentence he spoke into a browser, a chat or a commit message,
    /// with nowhere for the words to go. That is what pause existed to stop, and
    /// he was having to press it against an app that had no destination anyway —
    /// which is why, once this gate was in, pause had nothing left to do.
    ///
    /// Read off `TerminalBinding`, which locks, so this is safe from any thread.
    private var isBound: Bool { terminal.target != nil }

    /// **The dictation being spoken right now is going to open its own
    /// terminal** — ⇧ + the wheel. Set at the press that starts it and carried
    /// on the `Message`, so a prompt held on screen for five seconds cannot be
    /// overtaken by whatever the flag has become by the time it commits.
    ///
    /// It is the second half of *Unbound is inert*: every gate there asks "is
    /// there anywhere for these words to go", and until now a binding was the
    /// only way to answer yes. A spawn is the other way — the destination does
    /// not exist yet, but it is going to, which is the same answer for every
    /// purpose those gates have.
    private var spawnPending = false

    /// **Which folder that new session opens in, if he said.** Nil is the whole
    /// of the old behaviour — `spawnDirectory`, i.e. `~/workspace`.
    ///
    /// Set by a click on `SpawnFolderMenu`, which is up for the first three
    /// seconds of a spawn dictation, and read exactly once: `send` moves it onto
    /// the `Message` beside `spawn` itself and clears it, for that flag's reason
    /// — the panel holds a prompt for seconds, and the next dictation may have
    /// started by the time this one is delivered.
    private var spawnFolder: String?

    /// **Replace Wispr — the relay as a way to type, not a way to talk to an
    /// agent.** Ticked in the menu, the forward side button opens the microphone
    /// and closes it, and what was said is pasted at the caret: no outbox line,
    /// no terminal, no screenshots, no picked elements, no prompt panel. The back
    /// button is handed back to LinearMouse, which types Return with it.
    ///
    /// It is named after the app it replaces. Victor dictates into chats, commit
    /// messages and forms all day through Wispr Flow, and this app already has
    /// the two expensive halves of that — a warm local Whisper and a mouse button
    /// — pointed at agents only.
    ///
    /// **Restored from the last launch** (Victor, 2026-09-07), the same call
    /// `autosend` makes and for the same reason — see the note on
    /// `StatusItem.replaceWisprOn` for what the argument against it was and what
    /// overruled it. The menu row is where the answer is, and it is one click
    /// away.
    private var replaceWispr = false

    /// The one place the mode is written, so the tick in the menu, the flag the
    /// tap reads and the flash on screen cannot say three different things.
    private func setReplaceWispr(_ on: Bool, fromMenu: Bool = true) {
        replaceWispr = on
        hotkeys.replaceWispr = on
        if !fromMenu { status.setReplaceWispr(on) }
        Log.info("Replace Wispr \(on ? "on — the forward button dictates at the caret" : "off")")
        overlay.flash(on ? "Replace Wispr on — forward button dictates at the caret"
                         : "Replace Wispr off", duration: 2.5)
    }

    /// This dictation is going to the caret — decided at the press that opened
    /// the microphone, like `spawnPending`, and for the same reason: the mode may
    /// be switched off while a sentence is still being spoken, and the
    /// destination must not change halfway through.
    private var pasteMode = false

    /// Somewhere for this dictation to go: a terminal already bound, one it is
    /// about to open for itself, the caret — or, since 2026-09-11, one he has
    /// not pointed at yet (`holdsForBind`).
    private var hasDestination: Bool { isBound || spawnPending || pasteMode || Self.holdsForBind }

    /// **Whether a dictation spoken with nothing bound is kept for the binding
    /// that follows it, instead of being refused.**
    ///
    /// Victor's ask, 2026-09-11: *"tot ce pot să fac când sunt legat de un
    /// terminal să pot să fac și atunci când sunt nelegat, urmând a mă lega
    /// ulterior"*. It is the fourth answer to *where do these words go*, and the
    /// answer is **later** — see `awaitingBind`.
    ///
    /// It retires most of *Unbound is inert*, and it is worth being exact about
    /// what that rule was and was not. It was written on 2026-08-27 because the
    /// relay had just become a login item: it sat there all day, so every
    /// sentence Victor spoke into a browser, a chat or a commit message was
    /// costing him a screenshot, mouse 4 and ⌘⇧-click, **with nowhere for the
    /// words to go**. The premise is the last clause, not the binding: a
    /// destination that arrives two minutes late is still a destination, which
    /// is the same reading that already exempted the spawn (`spawnPending`, a
    /// session that does not exist yet) and the caret (`pasteMode`).
    ///
    /// **What the 2026-08-27 decision genuinely settled stands untouched**: the
    /// outbox does not fill up with dictations nobody asked for. A held sentence
    /// is in memory and nothing else — `commit` writes the JSONL line at the
    /// moment of delivery and not before — so a relay left unbound all day still
    /// leaves no log of his private dictation behind it.
    ///
    /// A constant rather than a setting: this is how the app behaves now, and a
    /// menu tick for it would be *Pause* coming back under another name. It is
    /// here as one word to flip if the hold turns out to be worse than the
    /// refusal was.
    static let holdsForBind = true

    /// **When the last bind Victor actually pressed for landed**, and the grace
    /// it buys the sentence that follows it.
    ///
    /// Pointing the relay at a terminal is a statement about where the next
    /// words go, so words said a breath later belong to it — even when the
    /// gesture that opened the microphone was the forward button's, which in
    /// Replace Wispr means *the caret*. Measured over his own afternoon
    /// (`relay.log`, 2026-09-09): every dictation opened 2–3s after a bind came
    /// out at the caret and had to be pasted by hand — 11:51:32 bound ttys014
    /// and 11:51:34 dictated at the caret, 11:55:45 bound ttys009 and 11:55:48
    /// the same — while the one opened nine seconds later was the bound gesture
    /// and went where he meant. His ask: *"rezolvă race-ul ăsta ca să pot
    /// imediat ce am legat terminalul să pot și începe dictarea"*.
    ///
    /// It is the rule *A bind mid-sentence changes the recipient* already runs
    /// on, reaching a few seconds **earlier**: there the chord lands while the
    /// words are being spoken and takes the destination back; here it landed
    /// just before the first of them, which the sentence could not otherwise
    /// know about.
    ///
    /// **Consumed by the first dictation that reads it** (`takeBindGrace`), so a
    /// caret dictation started deliberately a minute later is untouched, and so
    /// is the second one inside the same window. One sentence inherits a bind —
    /// it is not a mode, and Replace Wispr's tick is never touched.
    private var boundAt: Date?

    /// How long a bind speaks for the sentence after it. Long enough for the
    /// hand to travel from the chord to the gesture that opens the microphone
    /// (2–3s, measured), short enough that it cannot be lived in.
    private static let bindGrace: TimeInterval = 5

    /// **A bind is still resolving.** `bindFrontmostTerminal` spends one to two
    /// seconds of `osascript` working out what it is looking at (measured:
    /// 11:50:15 pressed, 11:50:17 bound), and for the whole of that `isBound` is
    /// false — so a dictate gesture made in that window fell through
    /// `hasDestination` and did nothing at all, with nothing said about it. That
    /// is the other half of the same complaint, and the literal race in it.
    private var bindInFlight = false

    /// A dictate gesture that arrived while a bind was still resolving. Banked
    /// exactly as `recordWhenModelReady` banks one made against a model that is
    /// still loading, and for that flag's reason: the intention is unambiguous,
    /// and asking him to make it again means noticing nothing happened first.
    private var recordWhenBound = false

    /// Does the bind he just made speak for the sentence about to start?
    ///
    /// Reading it **consumes** it, which is what keeps this a grace and not a
    /// mode. A bind still in flight answers yes without spending anything: the
    /// caller then opens an ordinary dictation, which banks itself on
    /// `recordWhenBound` and starts when the terminal is known.
    private func takeBindGrace() -> Bool {
        if bindInFlight { return true }
        guard isBound, let at = boundAt, Date().timeIntervalSince(at) < Self.bindGrace else { return false }
        boundAt = nil
        return true
    }

    /// A dictation is running. Main thread only, and kept here rather than read
    /// back off the overlay because it is half of what decides whether mouse 4 and
    /// ⌘-click belong to the relay or to the software they were borrowed from
    /// (`syncBorrowedGestures`).
    ///
    /// **It is not `source.isRecording`** (2026-09-12). That one answers *is a
    /// microphone open*, which for a source living in another process becomes
    /// true a beat after the gesture and stays true through a close this app has
    /// not processed yet. This is *the relay has a sentence in flight*, which is
    /// what every gate below means — and it is what `localRecording` was called
    /// while the relay's own microphone was the only one that could be open.
    private var listening = false

    /// A message that is built, shown, and *not yet written*. It lives here for
    /// the few seconds the overlay displays it, so Cancel has something to stop.
    /// Main thread only.
    private var held: Message?

    /// Long enough to see the prompt, read it, and get a hand to the mouse.
    /// Started at 3–5s and went to 4–7s the first time Victor tried to cancel a
    /// real dictation and didn't make it. Scaled up with length so a long
    /// dictation is still readable, and capped so it never parks over his work.
    private static let minHold: TimeInterval = 4.0
    private static let maxHold: TimeInterval = 7.0

    /// What Autosend leaves of that: one second, flat, and not scaled by length —
    /// it is not there to be read to the end, it is there so a delivery is
    /// something he saw happen.
    private static let autosendHold: TimeInterval = 1.0

    /// Everything one outbox line is made of, kept together so it can be held
    /// back, released, or dropped as a unit.
    private struct Message {
        let kind: String
        /// `var`, because the panel can hand back a corrected transcript: a local
        /// Whisper line is occasionally fluent nonsense, and the hold exists so
        /// that is catchable before it reaches an agent.
        var text: String?
        let selection: String?
        /// Highlighted later in the same dictation, each with its offset. Empty
        /// in the ordinary case, which is why `selection` above stays exactly
        /// what it was rather than becoming element zero of a list.
        var extraSelections: [(at: TimeInterval, text: String)] = []
        let paths: [String]
        let screen: String?
        /// Path → what was in front when that frame was taken. Covers both
        /// `paths` and `screen`, which is the reason it is keyed rather than
        /// ordered.
        var sources: [String: String] = [:]
        let app: String?
        let elements: [ElementPick]
        /// When the microphone opened, kept so `terminalLine` can stamp each
        /// picked element with *where in the sentence* he clicked it.
        ///
        /// Carried rather than looked up at delivery, for `spawn`'s reason: the
        /// panel holds every prompt for seconds and the next dictation may have
        /// started — and `dictationStartedAt` is cleared the moment this message
        /// is built. It is optional because a `screenshot` message has no
        /// dictation behind it, and an unstamped pick is better than a wrong one.
        var startedAt: Date?
        /// This one opens its own terminal instead of being typed into a bound
        /// one. Carried here rather than read off `spawnPending` at delivery,
        /// because the two are seconds apart — the panel holds every prompt — and
        /// the next dictation may have started by then.
        var spawn: Bool = false
        /// Where that terminal opens. Carried for `spawn`'s reason and not read
        /// off `spawnFolder` at delivery: the menu that sets it is long gone by
        /// then, and a second dictation may have chosen differently since.
        var directory: String = AppDelegate.spawnDirectory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstance.enforce()
        Self.startAtLogin()
        Outbox.prepare()
        overlay = RelayWindow()

        // **The ✕ cancels the dictation before it ends anything.** It ended the
        // session outright until 2026-09-12, which is the wrong verb at the one
        // moment the ✕ is actually reachable: it is hidden until the pointer is
        // over the overlay, and the overlay is a panel he can reach *during a
        // dictation*. Victor, dictating into Wispr Flow with the ring up: the ✕
        // beside it has to mean **stop this sentence and throw it away**, not
        // quit the app that drew the ring. With nothing being dictated it still
        // means what it always did.
        overlay.onEndSession = { [weak self] in
            guard let self else { return }
            if self.cancelDictationInFlight(reason: "✕ button") { return }
            self.endSession(reason: "✕ button")
        }

        status = StatusItem()
        status.onExit = { [weak self] in self?.endSession(reason: "menu bar Quit") }
        // **Replace Wispr.** One flag, pushed to the tap in the same breath, so
        // the mode and the button that performs it cannot disagree — and flashed,
        // because it is the one setting that changes where every sentence lands.
        status.onToggleReplaceWispr = { [weak self] on in self?.setReplaceWispr(on) }
        // **Use Logi Gestures** — pushed into the tap, which is the only thing
        // that acts on it. No flash and no overlay: it is a wiring switch, not
        // something that happens to a dictation.
        status.onToggleLogiGestures = { [weak self] on in
            self?.hotkeys.useLogiGestures = on
            Log.info(on ? "🖱️ Logi gestures on — the wheel is the browser's"
                        : "🖱️ Logi gestures off — the wheel is the relay's again")
        }
        status.onToggleAutosend = { [weak self] on in
            self?.autosend = on
            Log.info(on ? "autosend on — the panel is a one-second receipt, no buttons"
                        : "autosend off — the panel waits for Send or the countdown")
        }
        // **Seeded from the menu, not read from the defaults again here.** The
        // row is where the setting lives and where it is written; a second read
        // of the same key would be a second source of truth, and the two would
        // disagree the first time one of them changed key or meaning.
        autosend = status.isAutosend
        if autosend { Log.info("autosend restored on from the last launch") }
        // Seeded from the menu for `autosend`'s reason — the row is the one
        // source of truth — but pushed **through the flag and the tap by hand**
        // rather than through `setReplaceWispr`: that call flashes the overlay,
        // and a mode restored from the last launch is not an event to announce.
        // The tick is already drawn, so nothing has to be pushed back to the row.
        // **The wrap, restored from the last launch** — see
        // `StatusItem.isWrapWispr`. `WT_WRAP_WISPR=0` overrides it for one run,
        // which is what the harness uses to watch Wispr paste for itself.
        let wrapOverride = ProcessInfo.processInfo.environment["WT_WRAP_WISPR"]
        wisprSource.wrapWispr = wrapOverride.map { $0 != "0" } ?? status.isWrapWispr
        status.onToggleWrapWispr = { [weak self] on in self?.wisprSource.wrapWispr = on }
        // The ⏳ in the menu bar belongs to whichever source is slow to come up,
        // and only one of them ever is.
        whisperSource.onLoadingChanged = { [weak self] loading in
            self?.status.setEngineLoading(loading)
        }
        replaceWispr = status.isReplaceWispr
        hotkeys.replaceWispr = replaceWispr
        // Seeded the same way, and for the same reason: the row is the one
        // source of truth, and the tick is already drawn.
        hotkeys.useLogiGestures = status.isLogiGestures
        if !status.isLogiGestures { Log.info("🖱️ Logi gestures off from the last launch — the wheel is the relay's") }
        if replaceWispr { Log.info("Replace Wispr restored on from the last launch") }
        // The same call `POST /unbind` makes: the words go back to the outbox and
        // the relay keeps running, which is the difference between this and ⌘⌃B
        // on the bound target.
        status.onDisconnect = { [weak self] in self?.unbindTerminal() }
        // **Both halves run when the submenu opens, not when the menu does.**
        // `liveTitles` is an AppleScript round trip over every Terminal.app
        // window — cheap once, and paid on the gesture that asks for the list.
        status.rebindRows = { [weak self] in
            guard let self = self else { return [] }
            return RebindHistory.shared.rows(live: TerminalBinding.liveTitles(),
                                             boundAddress: self.terminal.target?.address)
        }
        // The same round trip a second time, for the panel's other half: a
        // session found in a transcript is bindable only if the tab it ran in is
        // still showing it. Two calls at one opening rather than a cached map
        // passed between them — 30 ms against a list that would otherwise be
        // deciding liveness from a snapshot it did not take.
        status.liveTitles = { TerminalBinding.liveTitles() }
        status.onRebindMessage = { [weak self] text in
            DispatchQueue.main.async { self?.overlay.flash(text, duration: 3) }
        }
        // **A session found in the transcripts whose window has been closed.**
        // The spawn is the one ⇧ + wheel makes, minus the prompt: same tiling,
        // same flight, same bind at the end — `adoptSpawnedWindow` does not care
        // that the session inside the window is an old one.
        //
        // The flash is not decoration here. `do script` plus a Claude Code
        // starting up is a couple of seconds in which the panel has closed, the
        // window is not on a screen he is looking at, and the only alternative is
        // a gesture that appears to have done nothing.
        status.onResumeSession = { [weak self] session, cwd in
            self?.resumeSession(session, in: cwd)
        }
        // **The same route the restart takes** (`picker.onBindTTY`), and for the
        // same reason: this is a binding being *restored*, not a gesture pointing
        // at the window in front. So no toggle — finding it already bound must not
        // let go of it — and the bind runs off the main thread, because it spends
        // itself in `osascript`.
        status.onRebind = { [weak self] tty in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let self = self else { return }
                guard let bound = self.terminal.bind(tty: tty) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.overlay.flash("⚠️ no terminal on \(tty)", duration: 3)
                    }
                    return
                }
                Log.info("📍 re-bound to \(bound.address) from the menu")
                DispatchQueue.main.async { [weak self] in self?.showBound(bound) }
            }
        }
        status.whisperFootprint = { [weak self] in self?.whisperSource.footprintBytes }
        // The id the overlay used to carry beside the pulse. Same shape as the
        // footprint: asked when the menu opens, because that is the one moment
        // its answer has to be right.
        status.whisperModel = { [weak self] in self?.whisperSource.modelName }
        // The menu asks rather than being told, like the footprint above: the flag
        // flips on every dictation, and the only moment its answer has to be right
        // is the moment the row is on screen.
        status.isRecording = { [weak self] in self?.listening ?? false }
        status.hasLastDictation = { [weak self] in self?.lastDictation?.isEmpty == false }
        status.onPasteLast = { [weak self] in self?.pasteLastDictation(fromMenu: true) }
        // Deliberately the *same* call mouse 5 makes rather than a quieter variant:
        // a recording ended from the menu is still a dictation, and it is
        // transcribed and sent exactly as if the button had ended it.
        status.onStopRecording = { [weak self] in self?.endDictation() }
        // **Cancel Dictation means whichever microphone is open**, not only the
        // relay's — same reason the ✕ does, and the same one call.
        status.onCancelDictation = { [weak self] in
            _ = self?.cancelDictationInFlight(reason: "menu bar Cancel Dictation")
        }
        status.isDictationCancellable = { [weak self] in
            guard let self else { return false }
            return self.listening || self.source.isRecording || self.speculative
        }
        status.onRecoverDictation = { [weak self] in self?.recoverCancelledDictation() }
        // Wispr Flow's microphone, faked — the only way the ⚡ ring, the
        // chevrons and the ✕'s cancel are reachable without talking into
        // another app. Straight onto main: everything it reaches is AppKit's.
        picker.onTestWispr = { [weak self] on in
            DispatchQueue.main.async { self?.wisprSource.simulateEdge(on) }
        }
        picker.onTestWisprHotkey = { [weak self] in
            DispatchQueue.main.async { self?.wisprSource.simulateHotkey() }
        }
        // The real chord on the wire, for the end-to-end harness — see
        // `tools/wispr-test.sh`. Only useful from the installed build: a
        // `.build/debug` binary has no Accessibility grant, so `CGEventPost`
        // does nothing and does it silently.
        picker.onTestInputDevice = { name in
            let was = InputDevice.systemDefaultName() ?? ""
            guard !name.isEmpty else { return ["input": was, "inputs": InputDevice.inputNames()] }
            guard let now = InputDevice.setSystemDefault(matching: name) else {
                return ["input": was, "changed": false, "inputs": InputDevice.inputNames()]
            }
            return ["input": now, "was": was, "changed": true]
        }
        picker.onTestWisprHandsFree = { [weak self] in
            DispatchQueue.main.async {
                Log.info("POST /test/wispr-handsfree — posting fn ⌃ Space")
                self?.wisprSource.postStartChord()
            }
        }
        picker.onTestCancelDictation = { [weak self] in
            DispatchQueue.main.async {
                _ = self?.cancelDictationInFlight(reason: "POST /test/cancel")
            }
        }
        picker.onTestRecover = { [weak self] in
            // The listener's thread; everything this touches is the main queue's.
            DispatchQueue.main.async { self?.recoverCancelledDictation() }
        }
        status.isRecoverable = { [weak self] in
            guard let kept = self?.cancelledAudio else { return false }
            return FileManager.default.fileExists(atPath: kept.url.path)
        }
        status.onStartDictation = { [weak self] in self?.startDictation() }
        // **On main, like the toggle two lines down.** It was not, and the
        // asymmetry is the whole bug: the tap dispatches globally, so cancelling
        // reached `RelayWindow.layoutContent` → `NSWindow.setFrame` on
        // `com.apple.root.default-qos` and AppKit trapped. Crash log
        // 2026-08-29 11:04:40, EXC_BREAKPOINT, one frame under
        // `cancelLocalRecording`.
        // **⬅️ — the forward button held and the mouse flicked left** (and the
        // wheel held, with Logi gestures off) — and since 2026-09-12 it throws a
        // **Wispr Flow** dictation away too, through the same one call the ✕ and
        // the menu row make. Victor's ask: the gesture that abandons a sentence
        // must not depend on which app happens to be hearing it. Local behaviour
        // is untouched — `cancelDictationInFlight` tries `localRecording` first.
        hotkeys.onLocalCancel = { [weak self] in
            DispatchQueue.main.async {
                _ = self?.cancelDictationInFlight(reason: "⬅️ forward button flicked left")
            }
        }
        // `onWisprMaybeStarting` belongs to `WisprFlowSource` now — it is the
        // source that decides what a gesture on the wire means, and it takes the
        // callback in its own initialiser.
        // ⬆️ held, mouse moved down. **No toggle**, exactly as the left-plus-wheel
        // chord it replaces: the gesture is made while pointing at the terminal he
        // means, and making it twice means "again", never "let go".
        hotkeys.onGestureBind = { [weak self] in self?.bindFrontmostTerminal(toggle: false) != nil }
        // ⬇️ held on the **back** button, mouse moved down. **The same call the
        // menu's Disconnect row makes**, so the gesture cannot end up meaning
        // something subtly other than the row that documents it — including the
        // chip's burst, which is the only thing on screen that says it happened.
        hotkeys.onGestureUnbind = { [weak self] in self?.unbindTerminal() }
        // The menu's copy of the spawn chord. The same call, so the window it opens
        // and the destination it arms cannot drift from the gesture's.
        status.onNewSession = { [weak self] in
            DispatchQueue.main.async { self?.startDictation(spawn: true) }
        }
        // The menu's shutter row. **After a beat**, because the menu is dismissed
        // by AppKit and the screen redrawn a frame or two later — a capture fired
        // on the click would photograph the menu that ordered it.
        status.onShot = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.plusOneShot(cursor: NSEvent.mouseLocation)
            }
        }
        status.onBind = { [weak self] in
            // Off the main thread: `bindFrontmostTerminal` asks it for the front
            // app with `main.sync`, and a menu action arrives already on main.
            DispatchQueue.global().async { [weak self] in _ = self?.bindFrontmostTerminal() }
        }
        status.frontIsBindable = { [weak self] in self?.hotkeys.frontIsBindable ?? false }
        startWatchingFrontApp()

        // **The model is brought up at launch again** (2026-09-06, Victor's ask),
        // and the actual load is at the end of this method.
        //
        // It has been both ways. Lazy loading was argued from memory: since
        // 2026-08-26 the relay starts at **login** and sits there all day, so
        // eager weights mean 2.5 GB of unified memory held from breakfast for a
        // dictation that may not come until the afternoon — on a Mac whose GPU
        // memory is also what the training demos run in. What that costs is the
        // other side of the trade, and it is charged to the one moment that
        // cannot absorb it: the first sentence of the day waits ten seconds
        // between the wheel and the microphone. Held memory is a number in
        // Activity Monitor; ten seconds mid-gesture is the app being broken in
        // front of a room. The memory loses.
        syncLocalCapture()
        overlay.onPromptResolved = { [weak self] send, edited in
            self?.releaseHeld(send: send, edited: edited)
        }
        overlay.onRefreshBound = { [weak self] in self?.refreshBoundTitle() }

        hotkeys.onScreenshot = { [weak self] cursor in self?.plusOneShot(cursor: cursor) }
        hotkeys.onAreaShot = { [weak self] anchor, at in self?.areaShot(from: anchor, at: at) }
        // One line per selection, in the app's own log: how many frames the box
        // was actually drawn in, and the longest it went without one. It took a
        // bug report to ask that question the first time.
        CropSelectionOverlay.log = { Log.info($0) }
        // Main, because it touches the overlay's own state; and `async`, because
        // this arrives on the tap thread mid-gesture.
        hotkeys.onAreaEnd = { DispatchQueue.main.async { CropSelectionOverlay.endDrag() } }
        hotkeys.onLocalToggle = { [weak self] in
            DispatchQueue.main.async { self?.toggleDictation() }
        }
        // ⬆️ held, mouse moved up — **dictate at a session that does not exist
        // yet.** A gesture of its own, where from 2026-09-05 it was the wheel
        // clicked twice converting a dictation already in flight: the wheel had
        // one press to spend and no working hold, so the second click was the
        // only spare gesture on it. This button has four directions, so the spawn
        // gets one outright and needs nothing to reinterpret.
        //
        // The context shot is taken at the press like every other dictation's.
        // `deferContext` went with the wheel: it existed because the wheel's
        // *release* was the moment the picture wanted — the screen his finger had
        // left, before a second click could land — and a gesture that ends with
        // the mouse already moved has no such moment.
        hotkeys.onGestureSpawn = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !self.listening, !self.recordWhenSourceReady else { return }
                self.startDictation(spawn: true)
            }
        }
        // ── Only reachable with *Use Logi Gestures* off ─────────────────────
        // **The bare wheel at rest** — distinct from the toggle above because its
        // press is only half a verdict: a second click on its heels turns the
        // dictation into a spawn, so the context shot waits for the release
        // (`onWheelRelease`) and pictures the screen his finger left.
        hotkeys.onWheelDictate = { [weak self] in
            DispatchQueue.main.async { self?.startDictation(deferContext: true) }
        }
        // **The wheel clicked a second time: convert the dictation to a spawn.**
        // Same recording, same words — only the destination changes: the terminal
        // it opens in does not exist yet, so the folder menu is offered exactly
        // as at a fresh spawn press.
        // **The same double click made at rest** — nothing bound, no dictation
        // to convert, so this one *opens* one that is a spawn from its first
        // sample. `startLocalRecording(spawn:)` is the whole implementation:
        // `spawnPending` is set before the `hasDestination` gate is read, which
        // is exactly how a spawn is allowed through the gate a bare dictation is
        // not — see its doc comment. `deferContext` is on for the same reason it
        // is on the bare wheel: the picture wanted is the screen his finger
        // *left*, so the second click's release is what asks for it.
        hotkeys.onWheelIdleDoubleSpawn = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard !self.listening, !self.recordWhenSourceReady else { return }
                self.startDictation(spawn: true, deferContext: true)
            }
        }
        hotkeys.onWheelDoubleSpawn = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // **`recordWhenModelReady` counts as a dictation.** On a cold
                // model the first click has not opened the microphone yet — it
                // banked the gesture and is waiting on the weights — and the
                // second click lands half a second later, long before that. The
                // resumed start reads `spawnPending`, so setting it here is
                // exactly how the conversion survives the wait.
                guard self.listening || self.recordWhenSourceReady else { return }
                guard !self.spawnPending, !self.pasteMode else { return }
                self.spawnPending = true
                self.spawnFolder = nil
                self.overlay.setSpawnDestination("✨ \(Self.spawnFolderName)", mark: "✨")
                self.offerSpawnFolders()
            }
        }
        // The deferred context shot's cue — see `onWheelDictate`.
        hotkeys.onWheelRelease = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.contextAtWheelRelease else { return }
                self.contextAtWheelRelease = false
                // Ended under the finger (menu, ⌘⌃D) — no sentence, no picture.
                guard self.listening else { return }
                self.captureContext()
            }
        }
        // The forward side button **clicked** — a dictation at the caret, in
        // every mode and whatever is bound (2026-09-12). Shaped exactly like a
        // spawn dictation, and ending the same way: whichever gesture opened
        // the microphone, closing it is closing it, and the destination was
        // decided at the press.
        //
        // **The bind grace is gone from here.** For three days the click made
        // within five seconds of a bind went to the terminal instead, on the
        // argument that a bind is him naming a precise destination and the
        // caret is the vaguest one. Victor's vocabulary, restated 2026-09-12:
        // *"butonul forward pornește dictare la caret (indiferent dacă e legat
        // ceva); forward + right move: dictare legată"*. The two gestures are
        // the two destinations, and a click that sometimes means the other one
        // is a click he cannot trust. `takeBindGrace` still serves the
        // left-held chord's own dictation.
        hotkeys.onPasteToggle = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.listening { self.endDictation() }
                else { self.startDictation(paste: true) }
            }
        }
        picker.onPick = { [weak self] pick in self?.record(pick) }
        picker.onBind = { [weak self] in self?.bindFrontmostTerminal() }
        // **Bind a named session** — the restore half of a restart, never a
        // gesture. It skips everything `bindFrontmostTerminal` does *because*
        // somebody pressed something: no toggle (a caller putting a binding back
        // must not find it there and let it go), no bind flight and no flash (an
        // app that has just replaced itself is not announcing a gesture Victor
        // made), and no `wakePointer` — he is not necessarily at the machine.
        picker.onBindTTY = { [weak self] tty in
            guard let self = self, let bound = self.terminal.bind(tty: tty) else { return nil }
            Log.info("📍 re-bound to \(bound.address) by request")
            DispatchQueue.main.async { [weak self] in self?.showBound(bound) }
            return Self.describe(bound)
        }
        // The same call the loopback route makes, from the key Victor actually
        // presses. Already off the main thread — the tap dispatches globally —
        // which this needs: it spends several subprocesses working out what it
        // is looking at.
        hotkeys.onBindHotkey = { [weak self] in _ = self?.bindFrontmostTerminal() }
        hotkeys.onPasteLast = { [weak self] in
            DispatchQueue.main.async { self?.pasteLastDictation() }
        }
        hotkeys.onMouse5Double = { [weak self] in
            guard let self = self else { return }
            // The first click of the pair has already opened the microphone if
            // the local engine is up. Close it: a double click is by definition
            // faster than `MicRecorder.minimumDuration`, so the recording is
            // dropped by the guard there rather than transcribed and sent.
            if self.listening { self.endDictation() }
            _ = self.bindFrontmostTerminal()
        }
        hotkeys.onPromptEnter = { [weak self] in self?.overlay.sendHeldPrompt() }
        hotkeys.onPromptEscape = { [weak self] in self?.overlay.cancelHeldPrompt() }
        picker.onUnbind = { [weak self] in self?.unbindTerminal() }
        picker.describeTarget = { [weak self] in self?.terminal.target.map { Self.describe($0) } }
        // Enters exactly where a real dictation does, so what it exercises is
        // the real path and not a shortcut through it.
        picker.onTestDictationStart = { [weak self] in
            guard let self = self else { return }
            // **In Replace Wispr it opens a *caret* dictation**, which is the
            // only way the mode's new half — the shutter and the picker, live
            // here since 2026-09-08 — is reachable from a desk. Without this the
            // route falls at `captureContext`'s first gate whenever nothing is
            // bound, which is exactly the state this mode is designed to be used
            // in. It mirrors `startLocalRecording(paste:)`: the flag first,
            // because `hasDestination` is what the gates below ask, then the
            // bookkeeping that makes a shot attach rather than fly off on its
            // own, and no context frame and no ⌘C.
            let paste = self.replaceWispr
            if paste {
                self.pasteMode = true
                self.stateLock.lock()
                self.dictationInFlight = true
                self.dictationStartedAt = Date()
                self.pendingShotOffsets = []
                self.stateLock.unlock()
                self.armOrphanFlush()
            } else {
                self.captureContext()
            }
            // **Every AppKit call here is on the main queue, including the chip's
            // destination row.** This closure runs on `ElementPicker`'s listener
            // thread, and `setSpawnDestination` reaches `layoutContent`, which
            // sets a window frame — done off main it took the whole app down with
            // a `SIGTRAP` inside `NSWMWindowCoordinator` the first time this
            // branch ran. The `captureContext` path never had the problem
            // because it does its own hop; this one had to be given one.
            DispatchQueue.main.async {
                if paste {
                    self.overlay.setSpawnDestination("at caret", icon: RelayWindow.pinGlyph)
                }
                self.listening = true
                self.syncBorrowedGestures()
                self.overlay.setListening(true)
                self.publishShotCount()
                self.publishPicks()
            }
        }
        picker.onTestDictation = { [weak self] text in
            guard let self = self else { return }
            // **It goes to the caret when that is where a real one would go.**
            // The route's whole claim is that a fabricated transcript enters
            // exactly where a spoken one does, and after 2026-09-08 that stopped
            // being true for Replace Wispr: the caret path now builds an envelope
            // of its own (`caretLine`), and routing the test straight into `send`
            // meant the one branch that had just grown a shape nobody could look
            // at was also the one branch no test could reach.
            //
            // `replaceWispr` (the mode) rather than `pasteMode` (this sentence's
            // destination): nothing has opened a microphone here, so there is no
            // sentence in flight to have decided anything.
            guard !self.replaceWispr else {
                let line = self.caretLine(words: text)
                // Consumed here the way `stopLocalRecording` consumes it, so a
                // route that opened a caret dictation does not leave the flag —
                // and with it `hasDestination` — standing after the words land.
                self.pasteMode = false
                DispatchQueue.main.async {
                    self.listening = false
                    self.syncBorrowedGestures()
                    self.overlay.setListening(false)
                    self.overlay.setSpawnDestination(nil)
                    self.overlay.clearSelection()
                    self.pasteText(line)
                }
                return
            }
            // The last read of the sentence, exactly as `stopLocalRecording`
            // makes it — otherwise the one part of the watcher that only runs at
            // the close is the one part no route can reach.
            self.finalSelectionRead { self.send(kind: "dictation", text: text, app: "test") }
        }
        // The spawn's transcript, entering where a spoken one does — with the
        // destination armed first, exactly as the ⇧-wheel press arms it.
        picker.onTestSpawn = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spawnPending = true
                self.send(kind: "dictation", text: text, app: "test")
            }
        }
        // The folder menu on its own — the one stretch of the spawn gesture no
        // fabricated transcript passes through. `spawnPending` is armed with it,
        // since the pick is refused without it and refusing is exactly what is
        // being checked here.
        picker.onTestSpawnFolders = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spawnPending = true
                self.offerSpawnFolders()
            }
        }
        picker.onTestReplaceWispr = { [weak self] on in
            DispatchQueue.main.async { self?.setReplaceWispr(on, fromMenu: false) }
        }
        // In the middle of the screen the pointer happens to be on, rather than
        // at the pointer: nothing at a desk moves the mouse, and a panel drawn
        // under a cursor parked in a corner is one shoved back onto the screen
        // by its own edge clamp.
        picker.onTestResumeSession = { [weak self] session, directory in
            self?.resumeSession(session, in: directory)
        }
        picker.onTestRebindPanel = { [weak self] query in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
                self.status.showRebindPanel(at: NSPoint(x: area.midX, y: area.midY + 200),
                                            query: query)
            }
        }
        picker.onReloadExtension = { [weak self] in self?.music.reloadExtensions() ?? 0 }
        picker.describeEngine = { [weak self] in
            guard let self else { return [:] }
            var out: [String: Any] = ["source": self.source.name,
                                      "ready": self.source.isReady,
                                      "wrapWispr": self.wisprSource.wrapWispr]
            out["whisper"] = self.whisperSource.describe()
            return out
        }

        let trusted = AXIsProcessTrusted()
        let tapped = hotkeys.start()
        Log.info("accessibility trusted=\(trusted) eventTap=\(tapped)")
        if !trusted || !tapped {
            DispatchQueue.main.async { [weak self] in
                self?.overlay.flash("⚠️ grant Accessibility to Walkie Talkie", duration: 15)
            }
        }
        startListeningForSnapshots()

        // The chip's `Listening...` bar fills on speech, not on elapsed time —
        // see `RelayWindow.listenWarmth`. This is the whole of the wiring: the
        // overlay pulls the number when it wants it and never learns what a
        // recorder is.
        overlay.voicedSeconds = { [weak self] in self?.source.meter.voicedSeconds ?? 0 }

        picker.start()
        music.start()
        // The same seam the chip's warmth ramp is fed through one line up, and
        // the same reason: the ring lights on his voice, and which recorder is
        // holding the microphone is this delegate's business, not its own.
        caretHalo.level = { [weak self] in self?.source.meter.level ?? 0 }
        // And it asks a second question of the same recorder, because the drop
        // arrow is triggered by silence rather than by volume — see
        // `MicRecorder.quietSeconds` for why that is not read off `level`.
        caretHalo.quietSeconds = { [weak self] in self?.source.meter.quietSeconds ?? 0 }

        // **The ring covers Wispr Flow's dictations too, since 2026-09-11.**
        // Replace Wispr is off most days, and with it off Wispr Flow is what he
        // dictates into everywhere — *"în orice context în care dictez … că este
        // la cursor, peste tot"*. A beacon dark for the commonest dictation of
        // the day is worth nothing on the rare one, so there is no gate: not on
        // the tick, not on a binding.
        //
        // The relay opens its own microphone alongside Wispr's for the length of
        // it, because the ring breathes on `level` and a CoreAudio boolean only
        // knows *open* or *closed* — and since 2026-09-12 that session writes the
        // WAV the corpus is built from. See `WisprFlowSource`.
        wireDictationSource()

        // The ring's panel is built here rather than on the first dictation —
        // see `CaretHalo.prewarm`.
        caretHalo.prewarm()

        // Nothing is bound yet, and a marker left by a relay that was killed
        // rather than quit would claim otherwise until the first bind.
        Outbox.publishBound(tty: nil)
        Log.info("ready — label \(SessionLabel.value), outbox at \(Outbox.outboxURL.path)")
        Log.info("voice corpus at \(VoiceCorpus.root.path)")

        // **The model comes up here, at launch, not on the first gesture.**
        // Loading it lazily meant the first dictation of the day paid ten
        // seconds for the weights, and paid them in the worst place available:
        // between Victor deciding to talk and the microphone opening. The relay
        // is a login item that is up before he is, so the same ten seconds cost
        // nothing at all when they are spent here — by the time the first ⌘⌃B
        // happens the helper has been warm for minutes.
        //
        // What it buys back is the whole `Preparing…` state, which no longer
        // exists on the chip: a wait nobody is waiting on does not need to be
        // narrated. `startWhisper` stays idempotent and the two gestures still
        // call it, so a load that *failed* here — no `mlx_whisper`, most likely —
        // is retried at the next bind rather than leaving the relay deaf until
        // it is restarted.
        //
        // Not while shooting the state pages: `RELAY_SHOOT` draws every view and
        // quits, and 1.5 GB of weights is a long detour to take for a picture.
        // **The weights are no longer loaded at launch** (2026-09-12). They were,
        // so the first dictation of the day cost nothing — and there is no first
        // local dictation of the day any more: Wispr Flow is the source, and 1.5
        // GB resident for a fallback nobody reaches is 1.5 GB of a laptop that is
        // not this app's to spend. `startDictation` brings it up on demand when
        // the local source is selected.

        // **And the spawn menu's bottom half, if nobody has measured it today.**
        // Same shape as the load above and for the same reason: it is a login
        // item, so the two seconds are free here and would otherwise be charged
        // to the first spawn of the day. `refreshIfStale` is one `stat` when the
        // answer is fresh, which is what makes it safe to also ask at the
        // gesture — see `RecentProjects`.
        if ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil { RecentProjects.refreshIfStale() }

        if ProcessInfo.processInfo.environment["RELAY_DEMO"] == "1" { runDemo() }
        // Photograph every state and quit — see `OverlayStates`, and
        // `docs/shoot-overlay-states.sh`, which is what actually runs this.
        if let dir = ProcessInfo.processInfo.environment["RELAY_SHOOT"] {
            OverlayStates.shoot(overlay: overlay, into: dir)
        }
        // The `CaptureEffect` tryout — see `CaptureEffects.swift`. Fires once,
        // on the whole app's normal running state, so Victor can watch all
        // six live without anything else being disturbed. WALKIE_EFFECT_ONLY
        // / _REPS / _SPEED narrow that to "replay #1, 3 times, 1.5x slower".
        if ProcessInfo.processInfo.environment["WALKIE_EFFECT_DEMO"] == "1" {
            let env = ProcessInfo.processInfo.environment
            let only = env["WALKIE_EFFECT_ONLY"].flatMap { CaptureEffect(rawValue: $0) }
            let reps = env["WALKIE_EFFECT_REPS"].flatMap { Int($0) } ?? 3
            let speed = env["WALKIE_EFFECT_SPEED"].flatMap { Double($0) } ?? 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                CaptureEffectDemo.runOne(only, reps: reps, speed: speed)
            }
        }
    }

    // MARK: - The dictation source

    /// **Wire whichever recogniser is live into the one lifecycle below.**
    ///
    /// Five events and no branches: the source says *a gesture was seen*, *the
    /// microphone is open*, *it closed*, *here are the words*, *it is over*, and
    /// everything this app does about a dictation hangs off those. Which source
    /// produced them is not asked anywhere past this method — see
    /// `DictationSource` for why that is the whole point.
    private func wireDictationSource() {
        source.didMaybeBegin = { [weak self] why in self?.dictationMaybeBeginning(why) }
        source.didBegin = { [weak self] in self?.dictationBegan() }
        source.didStopListening = { [weak self] in self?.dictationStoppedListening() }
        source.didTranscribe = { [weak self] result in self?.deliver(result) }
        source.didEnd = { [weak self] end in self?.dictationEnded(end) }
        source.prepare()
        Log.info("dictation source: \(source.name)")
    }

    /// **The ring is up on the keystroke, before the microphone.**
    ///
    /// The CoreAudio edge is the truth about the microphone and it is not the
    /// first observable thing about the dictation: between Victor's finger and a
    /// recorder in another process sit Electron waking, an overlay window and a
    /// device open. Victor sees that gap (2026-09-12: *the ring still comes up
    /// late*), so the ring goes up on the gesture and the source takes it back
    /// if no microphone follows.
    private func dictationMaybeBeginning(_ why: String) {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard !listening, !speculative else { return }
        speculative = true
        endSettling(reason: "a new dictation started", quiet: true)
        syncBorrowedGestures()
        Log.info(String(format: "⚡ ring up %.1f ms after %@ (speculative — waiting for the microphone)",
                        (CFAbsoluteTimeGetCurrent() - t0) * 1000, why))
    }

    /// **The microphone is open — open the sentence.**
    ///
    /// Everything `startLocalRecording` used to do *after* `mic.start` returned
    /// lives here, because the two sources reach this moment differently: the
    /// local one arrives inside its own `start()`, Wispr Flow's arrives when
    /// CoreAudio says its input is running, which may be a second later and may
    /// be a dictation Victor started with his own keyboard chord and this app
    /// never asked for. A sentence the relay did not start is still a sentence
    /// it must dress, book and route — that is what *Wispr Flow everywhere*
    /// means.
    private func dictationBegan() {
        guard !listening else { return }
        speculative = false
        endSettling(reason: "a new dictation started", quiet: true)

        // **The chip says where these words are going.** A spawn names its
        // folder (armed at the gesture), a caret sentence says so and outranks
        // the bound terminal for its own length, and a sentence with nothing
        // bound names the gesture that would give it somewhere to go.
        if pasteMode { overlay.setSpawnDestination("at caret", icon: RelayWindow.pinGlyph) }
        else if !spawnPending, !isBound {
            overlay.setSpawnDestination("bind to send", icon: RelayWindow.pinGlyph)
        }
        else if !spawnPending { overlay.setSpawnDestination(nil) }

        localRecordingApp = NSWorkspace.shared.frontmostApplication?.localizedName

        // **A new sentence never inherits the last one's subject.** The
        // microphone just opened, so anything still pending belongs to something
        // that is over.
        abandonDictation("a new dictation started")

        // **A picture is taken for somebody who will read it.** A sentence bound
        // for an agent gets the screen and the ⌘C probe; one bound for the caret
        // gets neither — there is no agent, and the probe would post a keystroke
        // into the very field he is dictating into, which is the whole subject
        // of a caret dictation. The sentence is booked either way, or a shot
        // taken mid-dictation would be named by wall-clock and dropped for want
        // of a destination.
        //
        // **`pasteMode` first** (2026-09-12): the forward click now opens a caret
        // dictation with a terminal bound, and `isBound` alone would have taken
        // the picture and posted the ⌘C into the field he is about to dictate
        // into.
        if !pasteMode, isBound || spawnPending {
            if contextAtWheelRelease { bookDictation() } else { captureContext() }
        } else {
            bookDictation()
        }

        listening = true
        syncBorrowedGestures()
        overlay.setListening(true)
        publishShotCount()
        publishPicks()
    }

    /// Open the sentence without taking a picture of it: `dictationInFlight` is
    /// what makes a shutter press attach a frame rather than send it off on its
    /// own, and `dictationStartedAt` is the zero every shot is named from.
    private func bookDictation() {
        stateLock.lock()
        dictationInFlight = true
        if dictationStartedAt == nil { dictationStartedAt = Date() }
        pendingShotOffsets = []
        stateLock.unlock()
        armOrphanFlush()
    }

    /// **The microphone closed and the words are in flight.**
    ///
    /// This is where the destination is latched — *"the recipient is whoever the
    /// relay is pointed at when the microphone closes"* — and it matters far
    /// more here than it did when the relay owned the recogniser: with a round
    /// trip in another process the close and the transcript are seconds apart,
    /// and a bind made in those seconds is a bind he made *about this sentence*.
    private func dictationStoppedListening() {
        guard listening else { return }
        listening = false
        // **One last look at what is highlighted**, before `syncBorrowedGestures`
        // takes the watcher down — a highlight made in the last seconds of a
        // sentence never gets its three settling reads, and that is exactly when
        // he selects the thing he has just described.
        finalSelectionRead()
        latchedAtCaret = pasteMode || (!isBound && !spawnPending)
        // **The ring waits for the words** (2026-09-12), on every source: the
        // microphone closing is not the end of the dictation, the words landing
        // is. A **bound** sentence is settled too now that the relay inserts it
        // itself — the settle ends at `⚡ ring down: routed to …`, which is the
        // one line that says the wrap worked.
        beginSettling(atCaret: latchedAtCaret)
        syncBorrowedGestures()
        overlay.setListening(false)
    }

    /// Where this sentence is going, decided at the close and read when the words
    /// arrive seconds later.
    private var latchedAtCaret = false

    /// **The words — put them where the close said they were going.**
    ///
    /// The one router, for both sources. Nothing here asks which recogniser
    /// produced the text: a transcript is a transcript, and the only question
    /// left is the one the chip has been answering all along.
    private func deliver(_ result: DictationResult) {
        // **The corpus first, and before anything can fail.** Filing a recording
        // is not *acting* on a dictation, so nothing that stops a delivery stops
        // this — and with the local model retired this is the only path by which
        // `~/.walkie-talkie/voice-corpus/` goes on growing. The bytes are read on
        // this thread so the staged WAV can go immediately after.
        if let wav = result.audio {
            corpus.captureLocal(wav: wav, text: result.text, language: result.language,
                                duration: result.duration, app: localRecordingApp,
                                engine: result.engine)
            try? FileManager.default.removeItem(at: wav)
        }
        lastDictation = result.text
        pendingPromptWarning = result.warning

        // Somebody else already put the words on screen — Wispr Flow with the
        // wrap off, and nothing else today. Filed above, delivered by nobody.
        guard case .route = result.delivery else {
            endSettling(reason: "\(source.name) inserted it")
            clearSpawn()
            abandonDictation("the source delivered it itself")
            return
        }

        let app = localRecordingApp
        localRecordingApp = nil
        let atCaret = latchedAtCaret
        pasteMode = false

        // **The ring goes down when the words land**, and for a bound sentence
        // that is here: the relay has just taken Wispr's paste and is putting
        // the words through the prompt panel instead. `⚡ ring down: routed to
        // …` is the one line in the file that says the wrap worked.
        endSettling(reason: atCaret ? "pasting at the caret"
                                    : "routed to \(terminal.target?.label ?? "the bound session")")
        guard !atCaret else {
            // **The caret's envelope**: the words, plus whatever he attached
            // while speaking. No outbox line, no terminal, no prompt panel and no
            // countdown — the words are wanted in the field he is looking at, and
            // a panel between the sentence and the caret is exactly the ceremony
            // this path exists to remove.
            let line = caretLine(words: result.text)
            overlay.setSpawnDestination(nil)
            overlay.clearSelection()
            pasteText(line)
            return
        }
        send(kind: "dictation", text: result.text, app: app)
    }

    /// The session is over, whichever way it ended.
    private func dictationEnded(_ end: DictationEnd) {
        // **A guess that was never confirmed ends here too.** The source drops a
        // speculative ring 1.5 s after a chord no microphone followed, and the
        // flag it raised lives on this side of the protocol.
        speculative = false
        switch end {
        case .delivered:
            break
        case .silent(let why):
            endSettling(reason: why.isEmpty ? "nothing was recorded" : why)
            if !why.isEmpty { overlay.flash(why, duration: 8) }
            overlay.setTranscribing(false)
            clearSpawn()
            abandonDictation("the source returned nothing")
        case .cancelled(let audio, let duration):
            endSettling(reason: "cancelled", quiet: true)
            if let audio { keepCancelled(wav: audio, duration: duration) }
            else { Log.info("🗑️ dictation cancelled — nothing had been recorded yet") }
            clearCancelledDictationState()
        }
        if listening {
            listening = false
            overlay.setListening(false)
        }
        syncBorrowedGestures()
    }

    // MARK: - The settle

    /// **The ring goes down when the words land, not when the microphone shuts.**
    ///
    /// Between the two is the transcription — another app's round trip for Wispr
    /// Flow, the model's for the local one — and it is exactly the stretch in
    /// which Victor is waiting and the beacon used to be already dark.
    ///
    /// - Parameter atCaret: what the ring was saying about the destination when
    ///   the microphone closed, kept so the chevrons do not disarm underneath the
    ///   settle.
    private func beginSettling(atCaret: Bool) {
        settling = true
        settlingAtCaret = atCaret
        settlingFrom = CFAbsoluteTimeGetCurrent()
        syncBorrowedGestures()

        settleGiveUp?.cancel()
        let giveUp = DispatchWorkItem { [weak self] in
            self?.endSettling(reason: "timed out waiting for the text")
        }
        settleGiveUp = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTimeout, execute: giveUp)
    }

    /// The words landed, or gave up, or a new dictation overtook this one.
    /// Says which, and how long after the microphone closed — the one line that
    /// makes *"the ring went away too early"* answerable from the file.
    private func endSettling(reason: String, quiet: Bool = false) {
        guard settling else { return }
        settling = false
        settlingAtCaret = false
        settleGiveUp?.cancel()
        settleGiveUp = nil
        if !quiet {
            Log.info(String(format: "⚡ ring down: %@ — %.0f ms after the recording ended",
                            reason, (CFAbsoluteTimeGetCurrent() - settlingFrom) * 1000))
        }
        syncBorrowedGestures()
    }


    /// **A gesture is waiting on a recogniser that is not up yet.**
    ///
    /// Wispr Flow is either running or it is not and there is nothing to wait
    /// for; the local model takes ten seconds to load 1.5 GB of weights, and a
    /// gesture made against a cold one used to cost Victor the sentence *and*
    /// the gesture. It is banked here and honoured when the source reports ready.
    private var recordWhenSourceReady = false

    /// A note the next panel should carry under its transcript — set by the
    /// source's confidence gate, consumed by the `showSentPrompt` that follows it.
    private var pendingPromptWarning: String?

    // MARK: - The relay's own microphone

    /// Whether the wheel may open the microphone.
    ///
    /// **On whether or not anything is bound, since 2026-09-11.** It was
    /// `isBound`, and it was the one gate *Unbound is inert* deliberately
    /// refused to widen when the spawn and the caret were let through: those two
    /// bypass the flag in the tap, where the bare wheel cannot. The argument was
    /// that a recording with nowhere to go is a room taped for nobody, and
    /// `holdsForBind` is what took the premise away — the words now wait for the
    /// terminal instead of being dropped on the floor.
    ///
    /// **It has a price and the price is outside this app**: with *Use Logi
    /// Gestures* unticked, the wheel is the relay's for as long as the relay is
    /// running, so middle-click stops opening links in Chrome and closing tabs
    /// in VS Code — which is exactly the cost Victor named when he moved the
    /// gestures onto the side buttons (*"folosesc middle click sa inchid de ex
    /// taburi chrome/vsc"*). In the **default** mode it costs nothing at all:
    /// `HotkeyTap` hands every mouse button straight back there and the dictate
    /// gesture is a chord on the side buttons. If it grates, this line is the
    /// one to put back to `isBound`.
    private func syncLocalCapture() {
        hotkeys.localCapture = true
        // Deliberately its own flag: the unbind chord is the one gesture that
        // still applies to a relay that is not listening, because what it acts on
        // is the binding rather than the microphone.
        hotkeys.bound = isBound
    }

    /// Start a dictation, or finish the one that is open.
    ///
    /// A **toggle**, not a push-to-talk: the dictations that go to an agent run
    /// to a minute or more, and a mouse button held for a minute is a hand that
    /// cannot do anything else — including take the screenshots (mouse 4) that
    /// the same minute is for.
    private func toggleDictation() {
        if listening || source.isRecording { endDictation() } else { startDictation() }
    }

    /// **Ask the source for a microphone**, and dress the gesture while it opens.
    ///
    /// This is `startLocalRecording` with the recorder taken out of it: what is
    /// left is the destination the gesture is arming (a spawn, the caret) and the
    /// question of whether the source can serve it at all. Everything that used
    /// to follow `mic.start` — the context shot, the chip, the bookkeeping — has
    /// moved into `dictationBegan`, because with Wispr Flow the microphone opens
    /// a beat later and may open without ever being asked.
    ///
    /// `spawn` is ⬆️: this dictation carries its own destination, so it is
    /// allowed through the one gate a bare one is not — having a binding.
    ///
    /// `resumed` is the source-ready continuation, and it exists because a cold
    /// local model makes this run **twice** for one gesture. The second run must
    /// not redo the opening ceremony: measured 2026-09-04, it re-offered the
    /// folder menu ten seconds in — flickering it under the hovering hand,
    /// restarting its clock, and wiping a folder he had already chosen.
    ///
    /// `deferContext` is the bare wheel at rest, reachable only with *Use Logi
    /// Gestures* off: its context shot is taken at the **release**, not the
    /// press, so the picture is of the screen his finger left.
    private func startDictation(spawn: Bool = false, paste: Bool = false, resumed: Bool = false,
                                deferContext: Bool = false) {
        // **Never twice.** Every caller is a gesture that means "start", and two
        // of them arriving in one turn — a hold timer and a release racing for
        // the same press, the menu row clicked on a session already opening —
        // used to reach the recorder twice.
        guard !listening, !source.isRecording, !speculative else { return }
        // Set before the gate below and before anything reads `hasDestination`:
        // it *is* the answer for a spawn.
        spawnPending = spawn
        // A folder chosen for a previous sentence must never ride this one. A
        // resumed start keeps the choice — its menu was offered at the press and
        // may already have been clicked.
        if !resumed { spawnFolder = nil }
        pasteMode = paste
        contextAtWheelRelease = deferContext
        // **Always true since `holdsForBind`**, and kept rather than deleted: it
        // is the gate this path is written under.
        guard hasDestination else { return }
        if spawn {
            overlay.setSpawnDestination("✨ \(Self.spawnFolderName)", mark: "✨")
            // **As early as the press allows** — Victor's ask, 2026-09-04. Its
            // clock is his reading time, which starts now. Once per gesture,
            // though: a resumed start skips it.
            if !resumed { offerSpawnFolders() }
        }

        guard source.isReady else {
            // **The gesture is kept.** Telling him to say it again made him watch
            // for a banner and then remember to repeat a gesture he had already
            // made. The intention is unambiguous, so it is banked and honoured
            // when the source comes up.
            Log.info("dictate gesture with \(source.name) not ready — bringing it up")
            recordWhenSourceReady = true
            bringUpSource()
            return
        }

        if let why = source.start() {
            overlay.flash("⚠️ \(why)", duration: 6)
            Log.error("\(source.name) did not start: \(why)")
            return
        }
        // **And now nothing happens until the microphone is open.** For the local
        // model that is this same turn; for Wispr Flow it is Electron waking up.
        // `dictationBegan` is where the sentence is actually opened.
    }

    /// End the dictation that is open — the words follow when the source has
    /// them.
    private func endDictation() {
        guard listening || source.isRecording else { return }
        source.stop()
    }

    /// Bring a source that is not ready up, and honour a gesture that was banked
    /// against it. Only the local model has anything to do here; Wispr Flow is
    /// running or it is not, and the relay cannot launch it on his behalf.
    private func bringUpSource() {
        guard let local = source as? LocalWhisperSource else {
            recordWhenSourceReady = false
            overlay.flash("⚠️ Wispr Flow is not running", duration: 8)
            return
        }
        local.bringUpModel()
        // Polled rather than pushed: the model's readiness is the source's own
        // business and a callback for one banked gesture is a second contract
        // between two objects that already have one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.recordWhenSourceReady else { return }
            guard self.source.isReady else { return self.bringUpSource() }
            self.recordWhenSourceReady = false
            self.overlay.clearFlash()
            Log.info("\(self.source.name) up after a gesture that had to wait — opening the microphone")
            // **The gesture is kept whole, ⇧ included.** `resumed`, so the folder
            // menu is not re-offered and a folder already clicked is not wiped.
            self.startDictation(spawn: self.spawnPending, paste: self.pasteMode, resumed: true)
        }
    }

    /// **Ask which folder, without making it a question he has to answer.**
    ///
    /// The menu appears where the mouse was when he started talking, names the
    /// repos he pinned plus the five he has most recently been working in, and
    /// takes itself off screen three seconds later. Not answering it is the
    /// ordinary case and costs nothing: the spawn opens in `~/workspace`, which
    /// is what it has always done.
    ///
    /// **The pick is only taken while the spawn is still pending.** The menu
    /// outlives short sentences — three seconds is longer than some dictations —
    /// and `send` consumes the destination on its way onto the `Message`. A click
    /// after that belongs to nothing: the words are already in flight, and
    /// silently moving a folder under them would be worse than ignoring it.
    private func offerSpawnFolders() {
        SpawnFolderMenu.show(at: NSEvent.mouseLocation) { [weak self] choice in
            guard let self = self, self.spawnPending else { return }
            self.spawnFolder = choice.path
            // **The folder he picked gets a row of its own, behind Terminal's
            // icon** — the shape a binding has, which is what he asked for:
            // *"ca și cum aș fi fost deja bind-uit la un alt astfel de
            // terminal"*. The name loses its ✨ here because the ✨ has not gone
            // anywhere — it stays in front of `Listening...` one row up, saying
            // the one thing a binding's row cannot: this session does not exist
            // yet. See `RelayWindow.spawnCollapsed`.
            //
            // Terminal's icon and not the app the spawn happens to be launched
            // from: `SpawnTerminal` opens a Terminal.app window, always, so this
            // is a fact about the destination rather than a guess about it.
            self.overlay.setSpawnDestination(choice.name, mark: "✨",
                                             icon: Self.appIcon("com.apple.Terminal", height: 18))
            Log.info("✨ spawn folder chosen — \(choice.path)")
        }
    }

    /// End the open dictation and throw it away — no decode, nothing delivered.
    ///
    /// Deliberately not `stopLocalRecording` with a flag: that one's whole body
    /// after the microphone closes is about getting a transcript somewhere, and
    /// the difference here is that none of it should happen. What the two share
    /// is closing the microphone and putting the overlay back, which is the part
    /// written out again rather than shared, because a `cancel` that fell through
    /// into the send path by accident is the one bug this must not have.
    ///
    /// Everything the dictation had gathered goes with it. Shots and picks are
    /// stamped against `dictationStartedAt`, so leaving them behind would attach
    /// them to the *next* sentence, timed from a clock that no longer exists.
    /// **Throw away whatever is being dictated right now, whoever is hearing
    /// it** — the ✕ on the overlay, the menu bar's *Cancel Dictation*, the ⬅️
    /// flick and `POST /test/cancel` all come here.
    ///
    /// **One cancel, because there is one source.** It used to be two — the
    /// relay's own recorder, thrown away from the inside, and Wispr Flow's, which
    /// is not this app's to end from the inside and so is ended with a chord on
    /// the wire (`postWisprCancel`, Wispr's own ⌃Escape *discard this, paste
    /// nothing*). Both are `source.cancel()` now, and which of the two it is has
    /// stopped being a question anything outside the source asks.
    ///
    /// Everything the dictation had gathered goes with it: shots and picks are
    /// stamped against `dictationStartedAt`, so leaving them behind would attach
    /// them to the *next* sentence, timed from a clock that no longer exists.
    /// That clearing happens in `dictationEnded`, on the `.cancelled` the source
    /// sends back — a cancel Wispr ignores therefore leaves the beacon
    /// truthfully lit rather than lying about a dictation that is still running.
    ///
    /// - Returns: whether there was anything to cancel — the ✕ falls through to
    ///   ending the session when there was not.
    @discardableResult
    private func cancelDictationInFlight(reason: String) -> Bool {
        guard listening || source.isRecording || speculative || settling else { return false }
        Log.info("🗑️ dictation cancelled via \(reason)")
        source.cancel()
        overlay.flash("🗑️ Cancelled", duration: 1.5)
        return true
    }

    /// **A bind is a dictation coming**, so whatever the source needs time for
    /// is started now: the ten seconds a cold local model costs overlap him
    /// settling into the session. Wispr Flow needs nothing — it is running or it
    /// is not, and this app does not launch it on his behalf.
    ///
    /// **The load only.** Arming the microphone here was wrong: a bind is Victor
    /// pointing the relay at a terminal, not Victor starting to talk, and the two
    /// can be minutes apart.
    private func prepareSourceForBind() {
        (source as? LocalWhisperSource)?.bringUpModel()
    }

    /// Everything a cancelled sentence had gathered, put down.
    ///
    /// Shots and picks are stamped against `dictationStartedAt`, so leaving them
    /// behind would attach them to the *next* sentence, timed from a clock that
    /// no longer exists.
    private func clearCancelledDictationState() {
        pasteMode = false
        clearSpawn()
        localRecordingApp = nil

        stateLock.lock()
        pendingPicks = []
        pendingShots = []
        pendingShotOffsets = []
        pendingSelection = nil
        pendingExtraSelections = []
        shotSources = [:]
        dictationStartedAt = nil
        pendingScreen = nil
        dictationInFlight = false
        contextShotPending = false
        contextAtWheelRelease = false
        stateLock.unlock()

        publishShotCount()
        publishPicks()
        // **And the highlight comes off the chip with it.** `pendingSelection` is
        // cleared above, but the row showing it is the overlay's own copy and
        // nothing else here puts it down. Reported 2026-09-04: *"once I have a
        // selected text it sometimes remains into the tooltip even if there is no
        // current dictation"*.
        overlay.clearSelection()
    }

    /// Move the cancelled audio somewhere it will survive the next few minutes,
    /// and start the clock that removes it.
    private func keepCancelled(wav: URL, duration: TimeInterval) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Outbox.cancelledDir, withIntermediateDirectories: true)
        // Named by the clock rather than by an offset: there is no sentence for
        // it to be an offset *into* any more, which is the whole of what
        // cancelling did.
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "HH-mm-ss"
        let kept = Outbox.cancelledDir.appendingPathComponent("cancelled-\(stamp.string(from: Date())).wav")
        // **Only one is kept.** A second cancel inside the five minutes replaces
        // the first: the row says *the* cancelled dictation, and a menu that had
        // to ask which one is a menu answering a question nobody has.
        discardCancelled()
        do {
            try fm.moveItem(at: wav, to: kept)
        } catch {
            Log.error("could not keep the cancelled audio: \(error)")
            try? fm.removeItem(at: wav)
            return
        }
        cancelledAudio = (url: kept, at: Date(), duration: duration)
        Log.info(String(format: "🗑️ dictation cancelled — %.1fs of audio kept for %.0f min",
                        duration, Self.cancelledGrace / 60))
        let sweep = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Log.info("🗑️ the cancelled audio's five minutes are up")
            self.discardCancelled()
        }
        cancelledSweep = sweep
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cancelledGrace, execute: sweep)
    }

    /// Take the kept audio away — the clock ran out, it has been recovered, or a
    /// newer cancel has replaced it. Idempotent, and the only place the file is
    /// removed.
    private func discardCancelled() {
        cancelledSweep?.cancel()
        cancelledSweep = nil
        if let kept = cancelledAudio { try? FileManager.default.removeItem(at: kept.url) }
        cancelledAudio = nil
    }

    /// **The menu's undo for a cancel.** Transcribe the audio that was kept and
    /// send it exactly as the sentence would have gone had it not been thrown
    /// away — into the bound terminal, or at the caret when that is where this
    /// app is currently typing.
    ///
    /// It is deliberately **not** a gesture. Cancelling is the deliberate act
    /// and this is the second thought about it, which happens at the speed of
    /// deciding rather than at the speed of a hand: a chord for it would be one
    /// more thing the wheel could be misread as doing.
    private func recoverCancelledDictation() {
        guard let kept = cancelledAudio, FileManager.default.fileExists(atPath: kept.url.path) else {
            overlay.flash("⚠️ nothing to recover")
            return
        }
        guard !listening else {
            // A sentence is in the air; two transcripts arriving at one panel is
            // the ordering problem `send` already has to solve, and there is no
            // reason to create it from a menu.
            overlay.flash("⚠️ finish this dictation first")
            return
        }
        Log.info(String(format: "↩️ recovering %.1fs of cancelled audio", kept.duration))
        overlay.setTranscribing(true, audio: kept.duration)
        let decodeStartedAt = Date()
        whisperSource.transcribe(wav: kept.url.path) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async { self.overlay.setTranscribing(false) }
            guard let r = result, !r.text.isEmpty else {
                Log.error("the recovered audio produced no transcript")
                DispatchQueue.main.async { self.overlay.flash("No words detected", duration: 8) }
                return
            }
            DecodeRate.record(audio: kept.duration, decode: Date().timeIntervalSince(decodeStartedAt))
            Log.info("↩️ recovered \(r.text.count) chars")
            // It is a real sample of his voice with a transcript beside it, which
            // is the only thing the corpus is for — and it was never filed,
            // because the cancel path files nothing.
            self.corpus.captureLocal(wav: kept.url, text: r.text, language: r.language,
                                     duration: kept.duration, app: "recovered")
            DispatchQueue.main.async {
                self.discardCancelled()
                // **Where it goes is decided now, not then.** The destination the
                // cancelled sentence had is minutes stale — he may have bound
                // something else since, or switched the mode — so this asks the
                // same question a fresh dictation asks at the moment it ends.
                if self.isBound {
                    self.send(kind: "dictation", text: r.text, app: "recovered")
                } else {
                    self.pasteText(r.text)
                }
            }
        }
    }

    /// Register the app as a login item, once, quietly.
    ///
    /// **The relay has to be up before Victor starts talking**, and since ⌘⌃B
    /// moved into this app there is nothing else left to launch it: the key that
    /// starts a session is served by the very process that has to be running to
    /// hear it. A login item is the whole of what that requires — the app is an
    /// accessory with no window, so starting it costs a menu bar icon and 56 MB.
    /// **The model comes up with it** (see `applicationDidFinishLaunching`):
    /// paying for the weights at login is what makes the first dictation of the
    /// day cost nothing, and login is the one moment nobody is waiting.
    ///
    /// `SMAppService` rather than a LaunchAgent plist: it registers the bundle
    /// that is running, so a copy moved or renamed cannot leave a stale plist
    /// pointing at a path with nothing behind it — and Victor can turn it off in
    /// System Settings → General → Login Items, which is where he would look.
    /// Already-registered is not an error, and a failure is logged rather than
    /// shown: an app that cannot register is still an app that runs.
    private static func startAtLogin() {
        guard #available(macOS 13, *) else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            Log.info("already a login item")
            return
        }
        do {
            try service.register()
            Log.info("registered as a login item")
        } catch {
            Log.error("could not register as a login item: \(error.localizedDescription)")
        }
    }

    /// `kill -USR1 <pid>` writes what is on screen right now to
    /// `<home>/snapshot.png` — the documentation screenshot the window itself
    /// refuses to appear in, and the only way to review a layout change without
    /// standing behind Victor.
    ///
    /// A `DispatchSourceSignal` on the main queue rather than a C handler: drawing
    /// a view has to happen on the main thread, and almost nothing is legal inside
    /// a real signal handler. `SIG_IGN` first, or the default action kills us
    /// before the source ever sees it.
    private func startListeningForSnapshots() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            let path = Outbox.home.appendingPathComponent("snapshot.png").path
            self?.overlay.snapshot(to: path)
        }
        source.resume()
        snapshotSignal = source
    }

    /// Walk the overlay through its states with canned content, for documentation
    /// screenshots. Nothing here touches the outbox: `held` stays nil, so the
    /// displayed prompt resolves into nothing.
    private func runDemo() {
        Log.info("demo mode — driving the UI with canned content")
        let selection = "public Order placeOrder(Cart cart) {"
        let opened = Date()
        let picks = [
            ElementPick(at: opened.addingTimeInterval(12), path: "main.content > button.buy-button",
                        tag: "button", text: "Add to cart"),
            ElementPick(at: opened.addingTimeInterval(21), path: "div#cart > span.price",
                        tag: "span", text: "100 €"),
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.overlay.setSelection(selection)
            self?.overlay.setListening(true)
        }
        // Empty first, so the hint gets its moment — that is the state he is in
        // for the first seconds of every dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.overlay.setPicks(count: 1, newest: picks[0].short)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
            self?.overlay.setPicks(count: 2, newest: picks[1].short)
        }
        // The automatic context shot, then one taken with the back button — the two ways the
        // count moves in a real dictation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.overlay.setShotCount(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.overlay.setShotCount(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.overlay.setListening(false)
            self?.overlay.setPicks(count: 0, newest: nil)
            // Built by the real formatter, so a documentation shot cannot drift
            // from what the panel actually renders.
            let body = Self.promptPreview(text: "extract the tax calculation out of this method",
                                          selection: selection,
                                          picks: picks, since: opened) ?? ""
            self?.overlay.showSentPrompt(body, hold: 25)
        }
    }

    // MARK: - Dictation window

    /// Everything that must be true at the instant dictation starts: confirm it
    /// on screen, open the window for attaching shots, grab the selection, and
    /// photograph the screen being talked about.
    ///
    /// Runs on both the Mouse 5 press and the CoreAudio transition, which can
    /// fire within a few hundred ms of each other. That is deliberate and
    /// harmless — but the screen is only captured once per dictation, since a
    /// second capture would cost a megabyte for an identical frame.
    private func captureContext() {
        // A picture of the screen at the moment he starts talking is only worth
        // taking when there is somebody it is being taken *for*. A spawn counts
        // as somebody — the session it is about to open reads the same line.
        guard hasDestination else { return }

        // Where he was pointing when he started talking. Taken here and carried
        // down: by the time the capture actually runs, a clipboard probe and a
        // subprocess later, the pointer has moved on.
        let cursor = NSEvent.mouseLocation
        // And what he was looking at, for the same reason and at the same
        // instant. This is the frame he means by "uite ce e aici" — reading the
        // title after the subprocess would name whatever he switched to while
        // still talking about this.
        let source = WindowContext.describe()

        stateLock.lock()
        let alreadyOpen = dictationInFlight
        dictationInFlight = true
        // A new dictation is a new subject. Clear the old one before probing, so
        // a selection stranded by a dictation that never produced a transcript
        // cannot ride along with the next thing he says.
        if !alreadyOpen {
            pendingSelection = nil
            pendingExtraSelections = []
            contextShotPending = true
            // The zero of every offset in this dictation, set the moment the
            // context shot is booked.
            if dictationStartedAt == nil {
                dictationStartedAt = Date()
                pendingShotOffsets = []
            }
        }
        // How far into the sentence this frame is taken: 0 for every path that
        // captures at the press, the hold's length for a wheel that was still
        // being judged when it was let go.
        let offset = dictationStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        stateLock.unlock()

        // Say `📸 ×1` now, not when the subprocess returns.
        publishShotCount()

        // The receipt comes FIRST — before the AX probe, before screencapture.
        // Those take the best part of a second between them, and a flash that
        // lands after the work is a flash that no longer means "now": it was
        // firing long after the frame it confirms had already been taken.
        if !alreadyOpen { CaptureFlash.announce(cursor: cursor, cycleMarker: true) }

        armOrphanFlush()

        // Off the caller's thread on purpose. The clipboard probe sleeps up to
        // 400ms and screencapture is a subprocess we wait on; left on the event
        // tap or the main queue, that is the flash frozen mid-fade.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.stashSelection()

            guard !alreadyOpen else { return }
            // Named by its offset — 0:00 for a capture at the press, the hold's
            // length when the wheel path deferred it to the release.
            let path = ScreenCapture.grab(cursor: cursor, offset: offset)
            self.stateLock.lock()
            self.pendingScreen = path
            if let path = path, let source = source { self.shotSources[path] = source }
            self.contextShotPending = false
            self.stateLock.unlock()
            // Either way: the promised picture is now a file, or it never will be
            // and the count has to come back down to the truth.
            self.publishShotCount()
            guard let path = path else { return }
            Log.info("context screen captured: \((path as NSString).lastPathComponent)")
        }
    }

    /// Keep the overlay's `📸 ×N` honest. N is what this dictation would carry if it
    /// were sent right now: the automatic context screen counts as the first
    /// picture, because that is what it is — he took it by starting to talk.
    private func publishShotCount() {
        stateLock.lock()
        let context = (pendingScreen != nil || contextShotPending) ? 1 : 0
        let count = context + pendingShots.count
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.overlay.setShotCount(count) }
    }

    private func armOrphanFlush() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.orphanFlush?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flushOrphaned() }
            self.orphanFlush = work
            DispatchQueue.main.asyncAfter(deadline: .now() + self.orphanTimeout, execute: work)
        }
    }

    /// No transcript came. Release deliberate shots so they are never lost; the
    /// automatic context screen is dropped, since without a transcript there is
    /// nothing for it to be context *for*.
    private func flushOrphaned() {
        stateLock.lock()
        let shots = pendingShots
        pendingShots = []
        pendingShotOffsets = []
        dictationStartedAt = nil
        pendingScreen = nil
        pendingSelection = nil
        pendingExtraSelections = []
        shotSources = [:]
        dictationInFlight = false
        contextShotPending = false
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in self?.overlay.clearSelection() }
        guard !shots.isEmpty else { return }
        Log.info("no transcript within \(Int(orphanTimeout))s — releasing \(shots.count) shot(s) on their own")
        send(kind: "screenshot", paths: shots)
    }

    /// A dictation ended without ever becoming a message. Let go of everything it
    /// gathered, now, instead of waiting out the two-minute orphan timer.
    ///
    /// **This is what kept quoting him at himself.** The selection is read once
    /// per dictation and frozen — `stashSelection` returns early when the slot is
    /// already full, and `captureContext` only empties it when `dictationInFlight`
    /// says a *new* dictation is opening. So a dictation that gathered a selection
    /// and then never produced a transcript left both behind: the flag stayed up,
    /// the next press was therefore not a new dictation as far as the reset was
    /// concerned, no fresh read was taken, and the old highlight went out attached
    /// to the next sentence — and the one after that, since every press re-armed
    /// the orphan timer that would eventually have cleared it.
    ///
    /// Three routes end a dictation this way and all three now come here: audio
    /// under `MicRecorder.minimumDuration` (which is *every* wheel double-click,
    /// the bind gesture — the common case), a decode that returned nothing, and a
    /// message dropped for want of a destination.
    ///
    /// Routed through `flushOrphaned` so deliberate shots are still released
    /// rather than dropped; only the timer is different, and it is cancelled here.
    private func abandonDictation(_ reason: String) {
        stateLock.lock()
        let carrying = dictationInFlight || pendingSelection != nil
            || !pendingExtraSelections.isEmpty || !pendingShots.isEmpty
        stateLock.unlock()
        guard carrying else { return }
        Log.info("dictation abandoned (\(reason)) — dropping what it had gathered")
        DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        flushOrphaned()
    }

    // MARK: - Actions

    /// The two gestures the relay **borrows from other software**, handed over and
    /// handed back together.
    ///
    /// Mouse 4 is Victor's Return key (LinearMouse types one with it) and ⌘-click
    /// is how a link opens in a new tab; the relay takes both **only while there is
    /// a dictation for them to add to**. Outside that window — at rest, the whole
    /// time nothing is bound — they must
    /// go back to doing what every other app expects, so this is called from all
    /// three edges that can change the answer: a dictation starting or stopping,
    /// a binding appearing or going away (`showBound`).
    ///
    /// One switch for both, so the recording row can never be on screen advertising
    /// a gesture that is no longer live, or off while one still is. Main thread only.
    private func syncBorrowedGestures() {
        let live = hasDestination && listening
        // **Replace Wispr borrows them too, since 2026-09-08.** It did not until
        // then, and the argument was that both buttons are taken in order to
        // *add to a message* while that mode has no message — one string, going
        // where the caret is. Victor overruled the premise rather than the
        // conclusion: *"chiar dacă pornesc dictare la caret … să poți să agăți și
        // poze și elemente, exact ca la o dictare țintită către un terminal"*. A
        // paste **is** a message; it is simply one whose recipient is whatever
        // has the caret — routinely another agent, in a web chat or an editor's
        // assistant, where a frame and a selector are worth exactly what they are
        // worth in a terminal.
        //
        // **The price is the back button, and it is the price this app always
        // pays.** In this mode it gave Return (*"pe butonul de Back să dea
        // Enter"*) because nothing was borrowing it; now it is the shutter for
        // the length of a sentence, exactly as it is in every other dictation.
        // The window is the same narrow one — `listening`, not the mode — so
        // outside it LinearMouse and Victor Addons go on typing Return with it.
        hotkeys.dictating = live
        picker.dictating = live
        // The halves as well as the verdict, so a refused ⌘⇧ can name the one
        // that was missing rather than saying an undivided no — see
        // `ElementPicker.listening`.
        picker.listening = listening
        picker.bound = hasDestination
        // **The ring round the pointer rides the same switch**, and deliberately
        // on `listening` rather than on `live`: since 2026-09-11 it answers *is
        // it hearing me?*, and the microphone is either open or it is not —
        // where the words then go is the chip's question, not this one. That is
        // the switch the 84pt microphone on the bottom edge used to ride, and
        // this is now the whole of what became of it.
        //
        // **`atCaret` is the second half, and it is `pasteMode`** — this
        // sentence's destination rather than the menu tick, so a bind made
        // mid-sentence takes it away and the drop arrow goes with it, which is
        // right: there is a terminal now, and the chip is naming it. The ring
        // itself stays, because the microphone is still open.
        //
        // The ring used to be gated on `pasteMode` outright, and Victor gave
        // that reading up knowingly when he made it the beacon: *"asta va
        // implica și că va trebui să arăți … haloul de fulgi de zăpadă și când
        // dictezi cu țintă. Însă, da?"*. What the caret dictation lost is given
        // back by `DropArrow`, in a shape a ring never had.
        //
        // **Wispr Flow's microphone counts as `listening`** (2026-09-11) and its
        // destination counts as the caret, which is what Wispr pastes into. The
        // relay's own dictation outranks it on `atCaret` only: while a wheel
        // dictation is live the destination is the relay's to name, and the chip
        // is naming it.
        // **Four ways for the ring to be up, and they are four different
        // claims.** `listening` and `wisprDictating` are *a microphone is open*;
        // `wisprSpeculative` is *the key that opens one has just been pressed*
        // (dropped again after `wisprSpeculativeGrace` if no microphone follows);
        // `settling` is *it closed, and the words have not landed yet*.
        caretHalo.setActive(listening || speculative || settling,
                            atCaret: pasteMode
                                     || (speculative && !listening)
                                     || (listening && !isBound && !spawnPending)
                                     || (settling && settlingAtCaret))
        // The status line goes yellow → red on the same edge, and reads the same
        // `listening` the ring does rather than a flag of its own.
        publishBinding(terminal.target)
        // **The music pauses for every dictation, and so reads `listening`, not
        // `live`.** It hung off `live` until 2026-09-03, on the argument that an
        // unbound dictation is Victor talking into some other app and none of the
        // relay's business. That argument was about *where the words go*, and the
        // music is not about where the words go — it is about the microphone
        // being open. Unbound, forwarding unbound, Replace Wispr, a test
        // dictation: in all of them he is speaking into this app's microphone
        // with a track playing over it, which is the one thing the pause exists
        // to stop. Same switch as the ring, and for the same reason.
        music.setActive(listening)
        // **The watcher runs in Replace Wispr too, since 2026-09-09.** It was
        // `live && !pasteMode`, on the argument that `caretLine` carried no
        // highlight at all so a watcher there would gather text nothing would
        // ever send. Victor took the premise away rather than the conclusion —
        // *"even during the dictation at the caret … I still want to capture
        // selection of text during the dictation"* — and `caretLine` now carries
        // `[selected: …]` exactly as `terminalLine` does. The paste is a message
        // whose recipient is whatever holds the caret, which is routinely another
        // agent; a highlight is worth there what it is worth in a terminal.
        //
        // **The one thing to keep in mind is what the caret is sitting in.** The
        // watcher reads through Accessibility, and in this mode the field with
        // the caret is the field he is dictating *into* — so a selection he made
        // there to be replaced by the dictation is a selection this will file.
        // It has to settle over two seconds first, which is longer than that
        // gesture survives in practice, and the receipt says so on the chip
        // before a word is pasted.
        syncSelectionWatch(live)
    }

    // MARK: - The bound terminal

    /// ⌘⌃B, arriving over loopback from Victor Addons: point the relay at the
    /// terminal in front and type every later dictation straight into it.
    ///
    /// **Runs on the listener queue** — `TerminalBinding.bind` spends a couple
    /// of `osascript` and `ps` subprocesses working out what it is looking at,
    /// and the main thread is drawing an overlay that follows the cursor at
    /// 60 Hz. Only the one main-thread question — which app is in front — is
    /// asked there, and it is asked first, before any of that work has had the
    /// chance to move the focus it is about to read.
    /// Keep `HotkeyTap.frontIsBindable` current, so the menu can decide whether
    /// a tap is a bind or a plain middle click **without asking the main thread**
    /// — an event tap that blocks is a mouse that stops moving.
    ///
    /// Pushed on every activation rather than polled: app switches are rare and
    /// the notification is exact, where a poll would be a timer running all day
    /// to answer a question that changes a few dozen times.
    /// The browser the pick extension lives in. One id, deliberately: the
    /// extension is loaded in Victor's Chrome and nowhere else, and a list of
    /// Chromium bundle ids would be a row promising a gesture that no extension
    /// is there to serve.
    private static let chromeBundleID = "com.google.Chrome"

    private func startWatchingFrontApp() {
        let update: (NSRunningApplication?) -> Void = { [weak self] app in
            let bundle = app?.bundleIdentifier ?? ""
            self?.hotkeys.frontIsBindable = TerminalBinding.isBindable(bundleID: bundle)
            // …and whether the ⌘⇧-pick row has a page to be about. The same
            // notification answers both questions, and it is the only place
            // either is asked — see `RelayWindow.chromeFront`.
            self?.overlay.setChromeFront(bundle == Self.chromeBundleID)
        }
        update(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { note in
            update(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    /// `toggle` is what makes a second press on the target already bound *let go*
    /// of it. ⌘⌃B and `POST /bind` keep it; **the left-plus-wheel chord does
    /// not**, since 2026-09-01.
    ///
    /// The chord is made while pointing at the terminal, and the ordinary reason
    /// to make it twice is that Victor is not sure the first one landed — so the
    /// answer he wants there is the flight again, not a session let go. Letting go
    /// already has two routes of its own that say nothing else: the right-held
    /// chord and the menu's Disconnect. A toggle is worth having on a key that has
    /// no off switch; it is a trap on a gesture that has two.
    private func bindFrontmostTerminal(toggle: Bool = true) -> [String: Any]? {
        var front: NSRunningApplication?
        DispatchQueue.main.sync {
            front = NSWorkspace.shared.frontmostApplication
            // The next second or two is spent in `osascript`, and `isBound` is
            // false for all of it. See `bindInFlight`.
            bindInFlight = true
        }
        // Read before binding: `bind` replaces the target, and what decides
        // between "point somewhere new" and "stop" is what it *was*.
        let previous = terminal.target?.handle
        guard let front = front, let bound = terminal.bind(app: front) else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.bindInFlight = false
                // A gesture banked on this bind goes with it: there is no
                // terminal for it to have been waiting for, and opening the
                // microphone at nothing is exactly what *Unbound is inert* is.
                self.recordWhenBound = false
                self.overlay.flash("⚠️ nothing bindable in front", duration: 3)
            }
            return nil
        }

        // **The answer to this key is drawn where the pointer is, so the pointer
        // has to be there.** ⌘⌃B is pressed mid-typing, in the very terminal it
        // is about to bind — which means macOS has hidden the pointer and the
        // chip has faded out with it, and both of the things this key draws land
        // on empty screen: the flight shrinks onto a label that is not visible,
        // and the unbind burst goes off beside a cursor that is not either.
        // Waking here rather than in each branch is deliberate — it is one key
        // with one problem, and both of its outcomes have it. (See
        // `RelayWindow.wakePointer`.)
        DispatchQueue.main.async { [weak self] in self?.overlay.wakePointer() }

        // **⌘⌃B on the target it is already pointed at lets go of it.**
        //
        // The key had no off. Starting the relay is a keystroke and stopping it
        // was a trip to the menu bar — and the menu bar is a moving target when
        // the reason you are stopping is that you are already elsewhere. Making
        // the same key the off switch also makes it reachable without aiming:
        // whatever app is in front, two quick presses bind it and then stop,
        // because the second press finds the first one's target.
        //
        // Compared by **handle**, not by app: two tabs of Terminal are two ttys,
        // so pressing in a different tab re-points rather than stops. That is the
        // more useful reading of "again" — the thing bound is a session, not an
        // application.
        //
        // **It unbinds; it does not quit.** It used to quit, and the argument was
        // that ⌘⌃B is what *starts* the relay, so its off switch should not leave
        // a process running. That argument died with the two changes underneath
        // it: the app now **starts at login** and is up all day whether or not
        // anything is bound (*⌘⌃B is this app's own key*), and *unbound is inert*
        // made an idle relay cost nothing — it touches no dictation at all. So
        // quitting no longer undoes a launch, it undoes a **binding** plus a
        // login item, and the second half has to be put back by hand before the
        // key works again. The opposite of "point this at that terminal" is
        // "stop pointing at it", which is exactly `unbindTerminal` — the same
        // call `POST /unbind` and the menu's Disconnect make, so all three routes
        // out of a binding now end in the same state instead of two of them
        // leaving the app running and one killing it.
        if toggle, let previous = previous, previous == bound.handle {
            DispatchQueue.main.async { [weak self] in
                BindFlight.cancel()
                Log.info("⌘⌃B on the bound target — unbinding")
                // Letting go is the opposite of naming a destination: whatever
                // the grace and the banked press were about is over.
                self?.bindInFlight = false
                self?.unbindTerminal()
            }
            return ["unbound": true, "label": bound.label, "address": bound.address]
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // **`walkie: started in petclinic@main`** — the folder, and nothing
            // else. The flash used to name the `ttysNNN` address as well, on the
            // grounds that it settles "did it grab the right tab?"; it never was
            // the question Victor asks at this moment, and the device file is
            // noise on a projector. Addons' banner for the same press says the
            // same words, so the two panels read as one event rather than as two
            // announcements of it.
            //
            // It is still where the shell guard's absence is reported, now that
            // the chip no longer distinguishes ⌨️ from 🎯: binding is the moment
            // that fact can still change what Victor does about it, and a warning
            // is not a label — it survives the shortening.
            // **Only the warning survives.** The flash used to read
            // `walkie: started in <folder>`, and the chip beside the cursor
            // changes to that same folder at this exact instant — so it was the
            // one fact said twice, in two places, one of which then sat over his
            // work for three seconds. The missing shell guard has nowhere else
            // to be said, and it is the one thing here that can still change what
            // Victor does about it, so it flashes on its own.
            let unguarded = bound.isGuarded ? nil : "⚠️ no shell guard"

            // **The rectangle hands over to the chip.** It flies from the window
            // that was captured to the cursor, and the label appears there the
            // instant it arrives — so the two are one gesture rather than two
            // announcements, and the shape that lands *becomes* the thing now
            // sitting under his hand.
            //
            // The flash is sized to the flight for the same reason: a flash is a
            // panel, and a panel is not the chip, so an overlay still showing one
            // in the corner has nowhere to put a label beside the pointer. Ending
            // them together is what leaves the cursor free at the exact moment
            // the rectangle gets there.
            //
            // With no window to fly from — nothing resolved a frame — there is no
            // arrival to wait for and the chip is set at once.
            // Ordinarily a no-op — the model has been up since launch. It stays
            // as the retry for a launch load that failed, and a bind is the right
            // moment for one: a dictation is coming, and the ten seconds overlap
            // him settling into the session.
            // **The load only.** Arming the microphone here was wrong: a bind is
            // Victor pointing the relay at a terminal, not Victor starting to
            // talk, and the two can be minutes apart. The wheel remains the only
            // thing that opens it — and if he holds it while this load is still
            // running, `startLocalRecording` remembers the gesture and it fires
            // the moment the weights land.
            self.prepareSourceForBind()
            // **The chip is set first, and the rectangle flies into it.** It used
            // to be the other way round — the label appeared when the rectangle
            // landed — which meant the flight ended on empty screen and the
            // answer arrived a frame later. Showing it up front gives the
            // rectangle something to aim at, and it now slides underneath and
            // disappears there: the window that was captured is *this* label.
            self.bindInFlight = false
            // **The sentence he starts now belongs to this terminal** — see
            // `boundAt`. Stamped on the gesture route only: `picker.onBindTTY`,
            // the restore half of a restart, is not somebody pressing something.
            self.boundAt = Date()
            self.showBound(bound)
            // The press that arrived while this was resolving, honoured now that
            // there is somewhere for it to go — on the next hop, so the chip and
            // the menu are already naming the destination when the microphone
            // opens.
            if self.recordWhenBound {
                self.recordWhenBound = false
                Log.info("🎙️ bind landed — opening the microphone the press was waiting for")
                DispatchQueue.main.async { self.startDictation() }
            }
            guard let frame = bound.sourceFrame else {
                if let unguarded = unguarded { self.overlay.flash(unguarded, duration: 3) }
                return
            }
            // Still sized to the flight when there is one: a flash is a panel,
            // and a panel is not the chip, so an overlay still showing one has
            // nowhere to put a label beside the pointer.
            if let unguarded = unguarded {
                self.overlay.flash(unguarded, duration: BindFlight.duration)
            }
            BindFlight.fly(from: frame, to: { [weak self] in
                self?.overlay.chipFrame ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
            })
        }
        return Self.describe(bound)
    }

    private func unbindTerminal() {
        terminal.unbind()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // **Read before the chip goes**, or the burst is aimed at whatever
            // shape the overlay has already shrunk to.
            let chip = self.overlay.chipFrame
            self.showBound(nil)
            // No sentence any more. `unbound — nothing is relayed now` was a
            // panel appearing in order to announce a disappearance, a few pixels
            // from the thing that disappeared. The chip coming apart where it
            // stood says it in the place it happened, and leaves nothing behind,
            // which is the whole of the message.
            UnbindPop.burst(at: chip)
        }
    }

    /// The bound terminal has been renamed by whatever is running in it — **or
    /// closed under the relay.** Called off the overlay's 10s tick, and doing
    /// the work on a background queue, because reading the title is an
    /// `osascript` round trip and the caller is the main thread in the middle of
    /// a timer.
    ///
    /// **The window closing is the same question as the window being renamed**,
    /// which is why it rides the same tick: both ask whether the line on the
    /// chip is still true. Until this, only a *delivery* could find out — so a
    /// terminal Victor closed left a chip naming a dead session, the wheel and
    /// the shutter borrowed for it, and a microphone on the status line, until
    /// he spoke a whole sentence at it and was told afterwards.
    ///
    /// It lets go the **normal** way (`unbindTerminal`, the chip coming apart
    /// where it stood) rather than with `report(.targetGone)`'s six-second
    /// warning: nothing was lost here, and a panel announcing the tidy-up of a
    /// window he closed himself would be the app reporting his own action back
    /// to him.
    private func refreshBoundTitle() {
        guard terminal.target != nil else { return }
        // **Not while a sentence is in the air.** The delivery asks the same
        // question a beat later and answers it with the words still in hand —
        // a warning, and the transcript kept. Unbinding here would hand the
        // wheel and the microphone back from under a dictation in progress to
        // save it ten seconds. This is the tidy-up for a relay at rest.
        let busy = listening || held != nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if !busy, case .gone(let what) = self.terminal.checkAlive() {
                Log.info("📍 \(what) — letting the binding go")
                self.unbindTerminal()
                return
            }
            guard let updated = self.terminal.refreshBinding() else { return }
            // **Not deliberate**: this is the same binding with a fresher name
            // on it, so it must not take a spawn's destination away.
            DispatchQueue.main.async { self.showBound(updated, deliberate: false) }
        }
    }

    /// The one place the binding is put on screen, so the chip and the menu can
    /// never disagree about where the words are going.
    ///
    /// Both show the same line — `walkie-talkie@main` behind the destination app's
    /// own icon — because they answer the same question in two places: the chip is
    /// where he is looking while he talks, and the menu bar is what is left when
    /// the pointer (and with it the chip) is hidden because he started typing.
    /// Main thread only: it draws.
    ///
    /// `deliberate` is false for the 10s poll that only re-reads the name of the
    /// binding already in place — see the spawn branch below, which is the one
    /// thing in here that must not happen on a tick.
    private func showBound(_ target: TerminalBinding.Target?, deliberate: Bool = true) {
        // Binding is also the switch that decides whether the relay touches a
        // dictation at all, and this is the one place every route into it passes
        // through — ⌘⌃B, `/unbind`, and a target found gone at delivery. Doing it
        // here is what keeps a relay that lost its terminal mid-session from
        // going on holding the wheel and the microphone.
        defer { syncLocalCapture(); syncBorrowedGestures() }
        guard let target = target else {
            // Nothing to inherit and nothing to wait for any more.
            boundAt = nil
            recordWhenBound = false
            overlay.setBound(label: nil)
            status.setDestination(nil, icon: nil)
            publishBinding(nil)
            return
        }
        // A target with no readable directory (a blind-paste app) says its own
        // name instead. That is the one case where the icon is not enough on its
        // own — there is nothing else on the line to give it a subject.
        // **A bind mid-sentence changes the recipient.** Rebinding from one
        // terminal to another already did: the delivery asks `terminal.target`
        // when the panel resolves, not when the microphone opened, so the words
        // go where the relay is pointing when the sentence ends. A spawn did not
        // — `spawnPending` was set at the press and nothing took it back — so
        // the spawn chord followed by the left-plus-wheel chord opened a new
        // session anyway and left the terminal he had just pointed at empty.
        //
        // The chord is Victor answering the same question with a destination
        // that exists. Taking the spawn back here rather than at delivery keeps
        // the chip honest too: it stops saying `✨ workspace` the moment it
        // stops being true.
        //
        // **Only a deliberate bind, and that is the whole of this fix.** The
        // branch used to read `spawnPending && localRecording`, and `showBound`
        // is not only the bind route: `refreshBoundTitle` rides the overlay's 10s
        // tick and calls it with the binding that was *already* there, to pick up
        // a renamed window. So a spawn dictation started over an existing binding
        // lost it to the next tick — a couple of seconds in, no button pressed,
        // the chip quietly going from `✨ workspace` back to the terminal bound
        // before it, and the sentence with it. Reported 2026-09-02: *"după 2-3
        // sec de vorbit, fără să apăs niciun buton, tooltipul a arătat că s-a
        // reconectat la unul dintre terminale"*.
        //
        // A poll is not Victor answering anything. The rule is about the gesture,
        // so it is gated on the gesture.
        if spawnPending, listening, deliberate {
            Log.info("✨ spawn dropped — bound mid-sentence, the words go to \(target.label)")
            clearSpawn()
        }
        // **And a caret dictation becomes a terminal one on the same terms**
        // (Victor, 2026-09-09: *"sesiunea de dictare pornită pentru paste …
        // trebuie să se poată converti într-o sesiune legată de un terminal,
        // prin același gest … și într-adevăr să se trimită nu la caret, ci în
        // terminal"*).
        //
        // It is the same rule the spawn branch above is, arrived at from the
        // other side: Replace Wispr's destination is *wherever the caret is*,
        // which is the vaguest destination this app has, and the chord is him
        // naming a precise one while the sentence is still being spoken. The
        // spawn case had to be written because `spawnPending` was decided at the
        // press; this one had to be written for exactly the same reason —
        // `pasteMode` is read at the press and consumed in `stopLocalRecording`,
        // so without this the words went to the caret however deliberately he
        // had just pointed at a terminal.
        //
        // **Only the sentence, never the mode.** `replaceWispr` — the menu tick,
        // the forward button's meaning — is untouched: the *next* press of the
        // forward button opens another caret dictation, which is what the tick
        // says it does. What is taken back is this one dictation's destination.
        // Clearing the mode here would make a bind a hidden way to switch it off,
        // discoverable only by finding it already off.
        //
        // The chip is the other half. `setSpawnDestination(nil)` takes the map
        // pin and `at the caret` down, and the line the bind writes a moment
        // later — the destination app's icon and `petclinic@main` — is then the
        // top row again, which is the honest answer to where the words go.
        if pasteMode, listening, deliberate {
            Log.info("⌨️ caret dictation redirected — bound mid-sentence, the words go to \(target.label)")
            pasteMode = false
            overlay.setSpawnDestination(nil)
        }
        // **`bind to send — ⌘⌃B` is the row he has just answered.** It goes on
        // any bind rather than on a deliberate one: unlike the two above, this
        // row claims nothing about *which* terminal, so there is no destination
        // for a poll to steal — and it must not be left standing on a dictation
        // that now has somewhere to go. The row only ever exists while a
        // dictation is running, so a bind at rest passes through this untouched.
        if listening, !pasteMode, !spawnPending {
            overlay.setSpawnDestination(nil)
        }
        let line = target.folder ?? target.appName
        overlay.setBound(label: target.label, folder: line, title: target.title,
                         icon: Self.appIcon(target.bundleID, height: 18))
        status.setDestination(line, icon: Self.appIcon(target.bundleID, height: 20))
        // Published here for the reason everything else about a binding is
        // published here: this is the one method every route into and out of one
        // passes through, so the file cannot drift from the chip.
        publishBinding(target)
        // **And for exactly that reason, this is where a held sentence goes
        // out.** Every way a terminal can become the destination ends here, and
        // what the words have been waiting for is a terminal — not a particular
        // gesture. Dispatched rather than called inline: `showBound` runs on the
        // bind's own thread and a delivery is `osascript`.
        if awaitingBind != nil {
            DispatchQueue.main.async { [weak self] in self?.releaseAwaitingBind() }
        }
    }

    /// Write the marker the status line reads — see `Outbox.publishBound`.
    ///
    /// Called from the two switches that own the two facts in it: `showBound`,
    /// which every route into and out of a binding passes through, and
    /// `syncBorrowedGestures`, which every edge of a dictation does. Neither can
    /// answer the other's question, which is why the file is written from both
    /// rather than from whichever one happened to fire last.
    private func publishBinding(_ target: TerminalBinding.Target?) {
        Outbox.publishBound(tty: target?.handle.tty, listening: listening)
    }

    /// The destination app's icon, drawn down to the row height it has to sit in.
    ///
    /// Asked of the installed application rather than of the running one: a
    /// running app answers `nil` for its icon often enough (it is loaded lazily,
    /// and an app that is busy launching has none yet), and the bundle on disk is
    /// the same picture with no timing to it.
    private static func appIcon(_ bundleID: String, height: CGFloat) -> NSImage? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: height, height: height)
        let scaled = NSImage(size: size)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        scaled.unlockFocus()
        return scaled
    }

    private static func describe(_ target: TerminalBinding.Target) -> [String: Any] {
        var obj: [String: Any] = ["label": target.label, "address": target.address,
                                  "guarded": target.isGuarded]
        if let folder = target.folder { obj["folder"] = folder }
        if let title = target.title { obj["title"] = title }
        return obj
    }

    /// **Open the destination and hand it the words in one gesture.** ⇧ + the
    /// wheel ends here: a new Terminal window, an interactive Claude Code in the
    /// folder that was current when he started talking, and the dictation as its
    /// first prompt.
    ///
    /// **The prompt goes in `argv`, not through the keyboard.** Every other
    /// delivery in this app types into a session that already exists and has to
    /// prove first that a shell is not sitting at the prompt (`wouldRunAsShell`).
    /// Here there is nothing to prove and nothing to wait for — the words are an
    /// argument to the process being started, so they cannot be executed by a
    /// shell, cannot land in an editor window, and cannot arrive before the agent
    /// is ready to read them. That is also why this does not wait for the session
    /// to come up before reporting: there is no readiness to wait for.
    ///
    /// **The binding moves to the new window, since 2026-09-01.** It used to
    /// stay where it was — a spawn was a one-shot destination — and the case
    /// that killed that rule is the commonest one there is: the app starts
    /// unbound, a double click opens a session, the words land, and the relay
    /// is still pointing at nothing, so the next sentence has nowhere to go and
    /// the wheel is inert (*Unbound is inert*). Reported 2026-09-01: *"nu s-a
    /// autolegat de acel terminal … a rămas idle"*.
    ///
    /// Always, not only when unbound — Victor's call. A spawn is him saying the
    /// session he wants does not exist yet, which is the same sentence as "the
    /// one I am pointed at is not it" — the thing the right chord says by
    /// letting the binding go. Two spawns in a row still
    /// each get their own window; the relay ends up on the second, which is the
    /// one he is talking to.
    private func spawnClaude(_ m: Message) {
        let line = Self.terminalLine(m)
        guard !line.isEmpty else { return clearSpawn() }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = SpawnTerminal.launchClaude(prompt: line, directory: m.directory)
            DispatchQueue.main.async {
                self.clearSpawn()
                switch outcome {
                // **Silent**, like every other delivery that landed: the window
                // is in front with the session running in it, which is a whole
                // screen of evidence, and a flash would be a panel thrown over
                // his work to repeat what it already shows.
                case .opened(let tty):
                    self.adoptSpawnedWindow(tty: tty)
                case .failed(let why):
                    // Nothing to fly to and nothing to wait for — the dialog goes
                    // now, and the warning below takes the chip.
                    self.overlay.promptFarewell = nil
                    self.overlay.releaseSpawnPanel(fadeOver: 0.2)
                    // The outbox already has the line — `commit` wrote it before
                    // this ran — so what is lost is the delivery, and this is the
                    // only place he would learn that.
                    Log.error("✨ spawn failed: \(why)")
                    self.overlay.flash("⚠️ \(why)", duration: 8)
                }
            }
        }
    }

    /// **A session found in the transcripts whose window has been closed**, put
    /// back on screen — `RebindPanel`'s ⏎ on a row that has no tty to point at.
    ///
    /// The spawn is the one ⇧ + wheel makes, minus the prompt: same tiling, same
    /// flight, same bind at the end, since `adoptSpawnedWindow` does not care
    /// that the session inside the window is an old one. A resumed session is a
    /// destination that did not exist a second ago, which is the same sentence a
    /// spawn says.
    ///
    /// **The flash is not decoration.** `do script` plus a Claude Code starting
    /// up is a couple of seconds during which the panel has closed, the window is
    /// being tiled onto a screen he is not looking at, and the alternative is a
    /// gesture that appears to have done nothing.
    private func resumeSession(_ session: String, in directory: String) {
        let folder = (directory as NSString).lastPathComponent
        DispatchQueue.main.async { [weak self] in
            self?.overlay.flash("✨ reopening \(folder)…", duration: 4)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            switch SpawnTerminal.resumeClaude(session: session, directory: directory) {
            case .opened(let tty):
                DispatchQueue.main.async { self.adoptSpawnedWindow(tty: tty) }
            case .failed(let why):
                Log.error("✨ resume failed: \(why)")
                DispatchQueue.main.async { self.overlay.flash("⚠️ \(why)", duration: 8) }
            }
        }
    }

    /// **The spawned window becomes the binding, a beat after it appears** — and
    /// gets the bind flight that says so.
    ///
    /// A spawn is the one destination Victor never pointed at: the window opens
    /// on its own, somewhere he was not looking, while his hand is still on the
    /// mouse. Every other way a session becomes a destination answers itself with
    /// a picture of that window flying into the chip (*The bind flight*), and this
    /// one answered with nothing — the sentence went somewhere he had to go and
    /// find. The flight is what connects the gesture to the window it produced.
    ///
    /// **It binds, since 2026-09-01** — see `spawnClaude`. The flight was already
    /// the bind animation played without the claim behind it; now the claim is
    /// true, and the chip names the session that just opened.
    ///
    /// **The flight runs backwards, and starts when the window is on screen.**
    /// Both on Victor's ask, 2026-09-04: *"the animation should be backwards,
    /// from the mouse going to the terminal, and should start as soon as the
    /// terminal window is displayed. Faster a bit."*
    ///
    /// Away from the chip is the honest direction here. A bind is *that window is
    /// now this chip* — he pointed at something and the chip is the answer. A
    /// spawn is the reverse sentence: the words are already spoken, and what he
    /// does not know is **where they went**. Something leaving the words he just
    /// read and arriving on a window he has not looked at yet is a direction to
    /// look in; the same shape flying the other way is an answer to a question
    /// nobody asked.
    ///
    /// **And since 2026-09-09 it is the window itself that travels, not a frame
    /// around nothing** (`spawnSeed`): a little terminal is born under the
    /// dialog, the destination in miniature and carrying its pixels, and grows
    /// over a second until it lands on the real one pixel for pixel. The two
    /// outlined flights refuse a picture because they end on a window he is
    /// *reading*; this one ends on a window that did not exist a second ago.
    ///
    /// **It used to wait a flat 1.25s** — `do script` returns as soon as Terminal
    /// has a window, so the shell is still starting and a picture taken then is a
    /// picture of nothing. A fixed beat is the wrong instrument for that: it is
    /// too long when the window is up in 300ms and too short when the machine is
    /// busy. So the window is polled for instead and the flight goes the moment
    /// it exists, which is also the moment it has finished being tiled.
    ///
    /// **The bind is made after the flight is launched, not before.** It needs
    /// the process on that tty and there may not be one yet; waiting for it is
    /// what put the flight a second late. The chip is renamed when the answer
    /// comes, which lands under the flight rather than ahead of it — and in this
    /// direction the chip is where the rectangle *leaves* from, so nothing is
    /// waiting on the label.
    private func adoptSpawnedWindow(tty: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // Off the main thread: this is `osascript` and `ps` subprocesses all
            // the way down, like every other question this app asks Terminal.
            var frame: CGRect?
            let deadline = Date().addingTimeInterval(Self.spawnWindowWait)
            while Date() < deadline {
                if let found = TerminalBinding.terminalWindowFrame(tty: tty) { frame = found; break }
                Thread.sleep(forTimeInterval: 0.08)
            }
            if let frame = frame {
                DispatchQueue.main.async {
                    // Same reason ⌘⌃B wakes it: macOS hides the pointer while he
                    // types, and the chip the dialog collapses back into must be
                    // somewhere he can see it land.
                    self.overlay.wakePointer()
                    // **The outline leaves the dialog, not the chip** (Victor,
                    // 2026-09-07). The panel he read the prompt on is still on
                    // screen — it was held for exactly this moment — so the
                    // flight is the same sentence the send flight says, with the
                    // same call: *these words are now that window over there*.
                    // It used to leave the chip beside the pointer, `reversed`,
                    // because by then the dialog was long gone; holding the
                    // dialog is what makes the honest source available.
                    let farewell = self.overlay.promptFarewell
                    self.overlay.promptFarewell = nil
                    if let farewell = farewell, farewell.width > 1 {
                        BindFlight.fly(from: Self.spawnSeed(under: farewell, like: frame),
                                       to: { frame }, picturing: frame,
                                       seconds: Self.spawnGrowSeconds,
                                       tail: Self.spawnFlightRest)
                        // **The outline leaves first; the dialog goes after it.**
                        // These two ran on the same instant, and that is exactly
                        // what made the gesture unreadable: at t=0 the outline
                        // lies pixel for pixel on the panel, so a panel already
                        // dissolving underneath it never reads as *a thing
                        // leaving a dialog* — it reads as both of them fading at
                        // once. Victor, 2026-09-07: *"dialogul trebuie abia
                        // atunci să înceapă să facă fade-out … dar doar după ce
                        // conturul lui pleacă în călătorie către terminalul nou
                        // deschis"*.
                        //
                        // A quarter second is what it takes for the rectangle to
                        // clear the panel it came from — a third of the flight,
                        // by which point it is unmistakably somewhere else — and
                        // it lands the panel's half-second fade almost exactly on
                        // the outline's arrival, so the dialog is gone when the
                        // window has it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.spawnPanelFadeDelay) { [weak self] in
                            // `releaseSpawnPanel` no-ops unless the hold is still
                            // this one's, so a second dictation that took the chip
                            // in the meantime is not faded out from under itself.
                            self?.overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
                        }
                    } else {
                        // No panel to leave from, so nothing to hold back for.
                        self.overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
                        // A spawn that never showed a panel has only the chip to
                        // be born under — the same window growing out of the
                        // pointer instead of out of the dialog, which is where
                        // Victor first put it before he corrected himself.
                        let chip = self.overlay.chipFrame
                        let anchor = chip.isEmpty
                            ? CGRect(origin: NSEvent.mouseLocation, size: .zero) : chip
                        BindFlight.fly(from: Self.spawnSeed(under: anchor, like: frame),
                                       to: { frame }, picturing: frame,
                                       seconds: Self.spawnGrowSeconds,
                                       tail: Self.spawnFlightRest)
                    }
                }
            } else {
                Log.error("✨ spawned window on \((tty as NSString).lastPathComponent) never appeared — no flight")
                // The dialog was being held for a window that never came. It
                // still has to go: a panel left on screen is worse than a missing
                // receipt.
                DispatchQueue.main.async {
                    self.overlay.promptFarewell = nil
                    self.overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
                }
            }
        }
        // **The bind keeps the beat it always had, on a queue of its own.**
        // Asking for it the instant the window exists does not make the answer
        // come any sooner — it waits on `claude` appearing as the foreground
        // process either way — and measured, asking early made it *later*: 6s
        // against the 3s the old fixed wait produced, which is 3s more of the
        // chip naming the session the words did **not** go to. So the flight is
        // early and the label is not: the two were only ever sequential because
        // the flight used to need the chip to aim at, and flying the other way
        // it does not.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.25) { [weak self] in
            guard let self = self else { return }
            // A window this app opened that Terminal will not name is a bind that
            // cannot be made — but the sentence still landed there, so the flight
            // is still worth playing on its own.
            // ✨ — this window did not exist a second ago, and the *Rebind to*
            // menu marks the ones this app opened itself.
            let bound = self.terminal.bind(tty: tty, spawned: true)
            DispatchQueue.main.async { if let bound = bound { self.showBound(bound) } }
        }
    }

    /// **The half second the outline spends resting on the new window**, fading
    /// out (Victor, 2026-09-07). The fade starts inside the last sixth of the
    /// travel and finishes here, so the rectangle is already dissolving as it
    /// settles and is gone a beat later — see `BindFlight.tailFadeFraction`.
    ///
    /// A bind ends by sliding under the chip, which is a place for it to *go*;
    /// this direction ends on a window that stays exactly where it is, so
    /// without a fade the last frame is a white rectangle blinking off a
    /// terminal. Landing and dissolving is the same sentence with an ending.
    private static let spawnFlightRest: TimeInterval = 0.5

    /// **The half second the dialog spends dissolving** while the outline that
    /// left it travels to the new terminal (Victor, 2026-09-07). Deliberately the
    /// same number as `spawnFlightRest` at the other end of the same flight: the
    /// panel empties out over half a second here, the outline dissolves over half
    /// a second there, and the travel between them is the 0.7s of
    /// `spawnGrowSeconds` — so the whole gesture is a fade, a flight and a fade
    /// with nothing left hanging at either end.
    private static let spawnPanelFade: TimeInterval = 0.5

    /// **How long the dialog stays solid after the outline has set off.**
    ///
    /// The fade used to start on the same instant as the flight, which is the
    /// one arrangement that cannot show what the flight is for: at t=0 the
    /// outline is lying exactly on the panel's own rectangle, so a panel already
    /// dissolving under it reads as the two of them fading together rather than
    /// as something *leaving* a dialog that is still there.
    ///
    /// A quarter of a second is a third of the flight — far enough that the
    /// rectangle has visibly cleared the panel — and it puts the end of the
    /// half-second fade within a hair of the outline's arrival, so the dialog
    /// finishes emptying out just as the window receives it.
    private static let spawnPanelFadeDelay: TimeInterval = 0.25

    /// How long to keep asking Terminal for the new window before giving up on
    /// the flight. Generous, because it costs nothing when the window is up in
    /// 300ms — the loop exits on the first answer, not on the clock.
    private static let spawnWindowWait: TimeInterval = 4

    /// **A shorter second**, for the flight to a terminal that was already open.
    /// The bind's flight is the answer to a press and is watched; this one is a
    /// receipt for words that have already gone, glanced at on the way back to
    /// work, and at a full second it was still going when he got there.
    ///
    /// The **spawn** used to share it and no longer does — see
    /// `spawnGrowSeconds`: that one is not a receipt, it is the window being
    /// carried to where it now lives, and a thing being carried is watched.
    private static let sendFlightSeconds: CFTimeInterval = 0.7

    /// **The second the little terminal spends growing** (Victor, 2026-09-09:
    /// *"slowly move it out of the screen in about … one second"*). Longer than
    /// the send flight beside it, because this one is not glanced at: it is the
    /// only thing on screen that says *which* of the monitors around him the
    /// session he just dictated into has gone to, and it says it by travelling
    /// the whole way there.
    private static let spawnGrowSeconds: CFTimeInterval = 1.0

    /// How tall the little terminal is when it is born, and how far under the
    /// dialog it sits. Its **width comes from the window it will become**, so it
    /// is that window in miniature rather than a rectangle of this app's own
    /// proportions — the shape is half of what makes it read as a terminal at
    /// 96 points, the picture inside it being the other half.
    private static let spawnSeedHeight: CGFloat = 96
    private static let spawnSeedGap: CGFloat = 12

    /// **A little terminal window, born just under `anchor`.**
    ///
    /// Victor, 2026-09-09: *"from the dialogue … it creates a terminal right
    /// under it and then slowly move it out of the screen … rather than having
    /// that just the frame flying out"*. A spawn is the one destination he never
    /// pointed at — the window opens on a monitor beside him while he is looking
    /// at the dialog — and an outline arriving there says *somewhere over
    /// there*. A picture of the window itself, growing out from under the words
    /// he just read and landing pixel for pixel on the real thing, says *this,
    /// and it is now there*. It is the bind flight's own argument for carrying
    /// pixels, which the two outlined flights refuse for the opposite reason:
    /// those end on a window he is **reading**, where a copy pasted over it
    /// covers the destination it is pointing at, and this one ends on a window
    /// that did not exist a second ago and has nothing to cover.
    ///
    /// Clamped into the anchor's own screen, so a dialog low on a short display
    /// still gets a terminal that is on screen to be seen leaving.
    private static func spawnSeed(under anchor: CGRect, like window: CGRect) -> CGRect {
        let aspect = window.height > 1 ? window.width / window.height : 1.5
        let height = spawnSeedHeight
        let width = max(1, height * aspect)
        var rect = CGRect(x: anchor.midX - width / 2,
                          y: anchor.minY - spawnSeedGap - height,
                          width: width, height: height)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            rect.origin.y = max(rect.minY, visible.minY + spawnSeedGap)
            rect.origin.x = min(max(rect.minX, visible.minX + spawnSeedGap),
                                max(visible.minX, visible.maxX - width - spawnSeedGap))
        }
        return rect
    }

    /// The dictation that was going to open a terminal is over — delivered,
    /// cancelled, or never transcribed. Main thread only: it draws.
    private func clearSpawn() {
        spawnPending = false
        spawnFolder = nil
        // It is normally long gone — three seconds against a sentence — but a
        // dictation cancelled inside those three seconds must not leave a menu
        // on screen offering a folder to a session nobody is going to open.
        SpawnFolderMenu.hide()
        overlay.setSpawnDestination(nil)
    }

    /// **The default, and nothing is inferred.** Victor's call, and the
    /// three reasons line up behind it: it is where he starts every session by
    /// hand, so it is the one folder Claude Code already trusts — a spawn into a
    /// sub-repo stops on the "do you trust this folder" question instead of
    /// working — every repo he has is a folder inside it, so the agent can still
    /// be told which one, and a destination that is always the same is one he
    /// never has to check before he starts talking.
    ///
    /// The alternative was resolving it from the bound target or the terminal in
    /// front. It was written, and it is what surfaced the trust prompt: an answer
    /// that is right four times out of five is worse here than one that is fixed,
    /// because the fifth is only discovered after the sentence is spoken.
    ///
    /// **Since 2026-09-04 it can be overridden, but only by him saying so**, in
    /// the three seconds `SpawnFolderMenu` is on screen. That does not reopen the
    /// argument above: the alternative it beat was *guessing*, and a click is not
    /// a guess. Every folder on that menu is one Claude Code already trusts, so
    /// the failure this constant exists to prevent cannot happen there either.
    private static let spawnDirectory = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent("workspace").path

    /// What the chip calls that folder while he is talking at it.
    private static let spawnFolderName = (spawnDirectory as NSString).lastPathComponent

    /// Type a message into the bound terminal, if there is one.
    ///
    /// Off the main thread for the same reason binding is: this is subprocesses
    /// all the way down. It is fire-and-forget — the outbox line has already
    /// been written by the time this runs, so a failure here costs the delivery
    /// and nothing else, and the flash is how Victor learns which.
    private func deliverToTerminal(_ m: Message) {
        guard terminal.target != nil else { return }
        let line = Self.terminalLine(m)
        guard !line.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let outcome = self.terminal.deliver(line)
            DispatchQueue.main.async { self.report(outcome) }
        }
    }

    /// **Silent on success.** A dictation that landed announces itself in the
    /// terminal it landed in, which is a whole window of evidence; a flash
    /// saying the same thing would be a panel thrown across Victor's work to
    /// repeat what the target already shows. Every other outcome is a message
    /// that goes nowhere unless this says so.
    private func report(_ outcome: TerminalBinding.Outcome) {
        switch outcome {
        case .delivered:
            Log.info("⌨️ delivered to the bound terminal")
        case .noTarget:
            break
        case .targetGone(let what):
            Log.error("⌨️ \(what) — unbound")
            showBound(nil)
            overlay.flash("⚠️ \(what) — unbound", duration: 6)
        case .wouldRunAsShell(let shell):
            Log.error("⛔️ \(shell) is at the prompt — refused, nothing sent")
            // The one refusal in the whole app, and it is worth six seconds of
            // panel: what was stopped is a sentence about to be run as a
            // command. The binding is deliberately *kept* — he pressed Escape
            // or the agent exited, and starting it again is all this needs.
            overlay.flash("⛔️ \(shell) is at the prompt — not sent", duration: 6)
        case .failed(let why):
            Log.error("⌨️ delivery failed: \(why)")
            overlay.flash("⚠️ \(why)", duration: 5)
        }
    }

    /// One line, carrying everything the outbox JSON carries.
    ///
    /// **One line because the delivery ends with a Return**, so an embedded
    /// newline is not a paragraph break — it is an early submit that sends half
    /// the sentence and leaves the rest to arrive as a prompt of its own.
    ///
    /// The shots travel as **paths, not as a `📸 ×2` count**: the panel's
    /// preview is written for Victor, who took the pictures and needs only to
    /// be told they landed, while this is written for an agent, which can do
    /// nothing with a number and everything with something to `Read`. That is
    /// the same split the outbox already makes, said in one line instead of in
    /// keys — and it is what replaces the skill, which is no longer there to
    /// explain what a field called `screen` is for.
    /// **The agent is told the words were spoken, and in which two languages
    /// they might have been spoken.** This is the one clause here written to
    /// change how the text is *read* rather than to add something to read.
    ///
    /// A transcript arrives looking exactly like something Victor typed, so a
    /// mis-heard word reads as a word he chose. Measured on his own corpus, a
    /// local recogniser turned `Wispr Relay` — what this app was called then —
    /// into `risparerile ei`; an agent that knows the input came through a
    /// microphone sounds that out, one that does not has no reason to try.
    ///
    /// **`RO or EN`, fixed, rather than the language the recogniser detected.**
    /// It did carry the detected code for one commit, and the reason it no
    /// longer does is that the code is not reliable enough to assert: a sentence
    /// of Victor's plain Romanian came back labelled `en` in the very recording
    /// used to test it. A clause naming the wrong language is worse than one naming
    /// neither — it points the phonetics of a mis-heard word in a direction it
    /// was never said in. Both, always, is true on every dictation and is still
    /// the useful half: *which* two languages to sound a word out in. He asked
    /// for exactly this, twice, and the second time after being shown the
    /// mislabel: *"RO or EN"*.
    ///
    /// **Everything else went, also on his instruction** — *"skip the rest of
    /// details - are obvious"*. The clause used to spell out what to do about a
    /// word that makes no sense; a reader capable of acting on that advice does
    /// not need it spelled out, and this rides on every single dictation.
    ///
    /// Only `dictation` gets it. A screenshot or a typed message was not spoken,
    /// and a hint that invites phonetic guessing at text nobody dictated is an
    /// invitation to misread it.
    ///
    /// **Its other failure mode is not a mis-heard word, it is a fluent invention.**
    /// Measured over 442 dictations, 11 came back semantically broken — not
    /// garbled, but confident sentences that were never said ("Nu uitați să vă
    /// abonați" for a sentence about an invoice). The confidence gate catches 7
    /// of them before they are sent; the other 4, and everything the relay's own
    /// microphone path deliberately sends *below* the gate rather than
    /// swallowing, arrive looking exactly like a correct transcript. That is the
    /// one failure an agent cannot defend itself against by reading, so it is
    /// told instead — which is what Victor asked for.
    ///
    /// **It no longer names the recogniser** (2026-09-12). It said *a local
    /// Whisper* for as long as that was the only one; since Wispr Flow became
    /// the default source the same envelope carries its sentences too, and a
    /// clause naming the wrong engine is a clause the reader has to disbelieve
    /// — *"elimină bucata aceea din text pentru că acum poate să fie și Wispr
    /// Flow"*. What the reader needs is that the words were spoken and heard by
    /// a machine, and that is true of both.
    private static let dictatedHint =
        "[this text was dictated in RO or EN and transcribed automatically — "
        + "it can hallucinate a fluent sentence that was never said]"

    /// **What a Replace Wispr dictation actually pastes: the words, and only
    /// what he deliberately attached** (2026-09-08).
    ///
    /// The mode used to paste the transcript and nothing else, because it had
    /// nothing else — no shutter, no picker. Victor turned both on here (*"să
    /// poți să agăți și poze și elemente"*) and drew the line himself in the same
    /// breath: *"nu trebuie să facă poză originală și nu trebuie să vină cu tot
    /// sufixul standard … dar să pot să fac poză, în care caz poate să arate ca
    /// cel obișnuit"*.
    ///
    /// So this is `terminalLine` with everything **automatic** taken out and
    /// everything **deliberate** kept, in the shape it already has:
    ///
    /// | clause | terminal | caret |
    /// |---|---|---|
    /// | the words | ✓ | ✓ |
    /// | `[look at: …]`, `[pointed at: …]` | ✓ | ✓ — identical wording |
    /// | `[selected: …]` | ✓ | ✓ — identical wording, since 2026-09-09 |
    /// | the context frame, `[Focused window: …]` | ✓ | — none is taken |
    /// | `[this text was dictated in RO or EN…]` | ✓ | — |
    ///
    /// **Why the language hint goes and the paths stay.** Both are addressed to a
    /// reader, and the difference is who is certain to be one. A frame's path and
    /// a CSS selector are inert text to anything that is not an agent — noise in
    /// a commit message, but noise he asked for by pressing a shutter. The hint
    /// is the opposite: it is unconditional ceremony on every sentence, and this
    /// mode's whole claim is that what he says is what gets typed. A stray
    /// sentence about mis-hearing pasted into a Slack message is the mode failing
    /// at its one job.
    ///
    /// **The highlights joined them on 2026-09-09**, on Victor's ask — *"even
    /// during the dictation at the caret … I still want to capture selection of
    /// text during the dictation"*. They were the one deliberate attachment this
    /// envelope refused, and the refusal was really about the *probe*: nothing
    /// automatic runs in this mode, so nothing reaches into the field he is
    /// dictating into unasked. A highlight that got here was either read by a
    /// shutter press or watched settling for two seconds, and both are gestures
    /// he made.
    ///
    /// **Nothing is appended when he attached nothing**, which is the common case
    /// and is byte-for-byte what this mode did before.
    private func caretLine(words: String) -> String {
        stateLock.lock()
        let shots = pendingShots
        pendingShots = []
        pendingShotOffsets = []
        let sources = shotSources
        shotSources = [:]
        // **No context frame rides this envelope, and it is cleared rather than
        // ignored.** None is ever taken in this mode, so `pendingScreen` is nil
        // in every real path through here — but `shotsClause` is called with
        // `screen: nil` regardless, so one that *did* arrive (a `/test` route
        // that opened the dictation the terminal way) would survive to be
        // attached to the next sentence. Dropping it is one line and closes the
        // leak; leaving it would make this method depend on a fact about its
        // callers.
        pendingScreen = nil
        contextShotPending = false
        pruneStalePicks()
        let picks = pendingPicks
        pendingPicks = []
        // **Taken, not left behind.** They are cleared here for the reason every
        // other field on this envelope is: what is not consumed by the sentence
        // that gathered it rides the next one.
        let selection = pendingSelection
        let extraSelections = pendingExtraSelections
        pendingSelection = nil
        pendingExtraSelections = []
        // Read before it is cleared, and for the reason `Message.startedAt`
        // exists: it is the zero every pick's stamp is measured from, and one
        // line later there is nothing left to measure against.
        let since = dictationStartedAt
        dictationStartedAt = nil
        dictationInFlight = false
        stateLock.unlock()

        // The orphan timer was armed when the dictation opened, and these shots
        // have just been claimed — left running it would fire mid-next-sentence
        // and drop what that one had gathered.
        DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        publishShotCount()
        publishPicks()

        var parts: [String] = [words]
        // **In `terminalLine`'s order and `terminalLine`'s wording**, down to the
        // stamp on the extras: he pastes this into another agent as often as into
        // a commit message, and two envelopes that carry the same fact in two
        // shapes are two things to learn instead of one.
        if let selection = selection, !selection.isEmpty {
            parts.append("[selected: \(Self.clampForTerminal(selection))]")
        }
        for extra in extraSelections {
            parts.append("[selected \(Self.stamp(extra.at)): \(Self.clampForTerminal(extra.text))]")
        }
        parts.append(contentsOf: Self.shotsClause(paths: shots, screen: nil, sources: sources))
        if let clause = Self.picksClause(picks, since: since) { parts.append(clause) }
        guard parts.count > 1 else { return words }
        // The words, a blank line, then one clause per line — `terminalLine`'s
        // shape, for `terminalLine`'s reason: he reads this one too, and more
        // often than he reads that one, since it lands in a field in front of him.
        return words + "\n\n" + parts.dropFirst().joined(separator: "\n")
    }

    private static func terminalLine(_ m: Message) -> String {
        var parts: [String] = []
        if let text = m.text, !text.isEmpty { parts.append(text) }
        if m.kind == "dictation", let text = m.text, !text.isEmpty {
            parts.append(dictatedHint)
        }
        if let selection = m.selection, !selection.isEmpty {
            parts.append("[selected: \(clampForTerminal(selection))]")
        }
        // **Stamped, because that is the only thing that distinguishes them.**
        // A bare second `[selected: …]` beside the first is two highlights with
        // no way to tell which came from where in the sentence — and the reason
        // to record them at all is that he said something different while each
        // one was on screen. `0:31` is what lets "the one I mentioned after the
        // tax bit" resolve to a string.
        for extra in m.extraSelections {
            parts.append("[selected \(stamp(extra.at)): \(clampForTerminal(extra.text))]")
        }
        // **What was in front of him is not a caption for a picture.**
        // It used to ride inside the context frame's clause, as
        // `shot-00:00(…).jpg = Terminal — ✳ walkie-talkie`, which made a fact
        // about the dictation readable only by an agent that had decided to open
        // an image — and that clause says in the same breath that opening it is
        // usually unnecessary. The title is the cheapest context here and the one
        // most often enough on its own: it names the app he is talking about and
        // the file, page or session inside it, in a dozen characters, with no
        // megabyte attached. So it is its own block, delivered whether or not any
        // frame is ever opened. He asked for exactly this: *"it has nothing to do
        // with the images"*.
        //
        // The manual shots keep their `= title` — there it genuinely is a caption,
        // the thing that says which picture is which in an enumeration of five.
        if let screen = m.screen, let front = m.sources[screen],
           !front.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("[Focused window: \(front)]")
        }
        // `look at` and `context` stay separate, exactly as `paths` and `screen`
        // do: one is what he deliberately photographed and wants opened, the
        // other is the frame that happened to be on screen when he started
        // talking. Collapsing them would have every dictation drag a megabyte of
        // desktop into a context window nobody asked to spend.
        parts.append(contentsOf: shotsClause(paths: m.paths, screen: m.screen, sources: m.sources))
        if let clause = picksClause(m.elements, since: m.startedAt) { parts.append(clause) }
        // **The words, a blank line, then one clause per line** (Victor,
        // 2026-09-07: *"vreau să-i dai două linii goale … după mesajul dictat, și
        // textele ajutătoare să fie fiecare începând pe rând nou"*).
        //
        // **This is a deliberate reversal of *One line, always*, and it is safe
        // for exactly one reason**: the Return that submits is `\r`, written
        // separately, while these separators are `\n` — and in a TUI in raw mode
        // `\n` is *insert a newline*, which is the convention Claude Code uses
        // for a multi-line prompt. That distinction is not new; it is the same
        // one measured when both IDE extensions were fixed for appending `\n`
        // where a real Return was wanted. What the old rule was right about is
        // that a newline must never be *submitted*, and nothing here submits one.
        //
        // The words themselves are still flattened (`clampForTerminal` and the
        // per-line pass in `TerminalBinding`), so a transcript that arrives with
        // its own line breaks cannot fragment the sentence; the structure below
        // is the app's, not the recogniser's.
        //
        // Why it is worth it: this envelope is read by Victor as often as by an
        // agent — `⌘⌃P` pastes exactly this, and the Prompt Log shows it — and
        // five bracketed clauses run together on one line is the shape he has to
        // parse a sentence out of. The shell guard is unaffected: it looks at
        // what is *running* on the target, not at what is being sent.
        guard let first = parts.first else { return "" }
        let clauses = parts.dropFirst()
        guard !clauses.isEmpty else { return first }
        return first + "\n\n" + clauses.joined(separator: "\n")
    }

    /// How the pictures are handed over: the folder once, then the frames by
    /// name, oldest first.
    ///
    /// **The small copies travel, not the retina frames.** `ScreenCapture.handover`
    /// picks the downscaled sibling, which the evals in `evals/` measured as
    /// costing a fraction of the tokens for the same answers. The originals are named in
    /// the clause too, because "I can't read that" has to have an answer that is
    /// not "take the picture again".
    ///
    /// **The order is stated, because nothing else states it.** Every one of
    /// these messages is a sequence — he says "ăsta … și ăsta … și ăsta" and
    /// presses the shutter between clauses — and until now the only thing
    /// carrying that was the order of paths inside `[look at:]`, which is an
    /// ordering something has to *guess* is meaningful rather than incidental.
    /// The frames are named by their offset into the sentence (`shot-00:38…`),
    /// so once the list is known to be chronological the names locate each one
    /// inside what he was saying.
    ///
    /// **The context frame is offered, not withheld, and is not called a spare.**
    /// Dropping it scored worse in the evals for a reason worth remembering: he
    /// starts talking about what is already on his screen, so it is routinely
    /// picture *one* of the enumeration rather than a fallback nobody needs.
    /// What it gets is a hint that it can be skipped — a "Test, test, test"
    /// dictation had the agent open a megabyte of desktop for nothing.
    ///
    /// Factoring the directory out saves ~90 characters a frame. That is worth
    /// having and is **not** where the tokens are: measured, the addressing is a
    /// rounding error beside the pixels, which is why this method is short and
    /// `handoverWidth` has an essay over it.
    private static func shotsClause(paths: [String], screen: String?,
                                    sources: [String: String] = [:]) -> [String] {
        guard paths.first != nil || screen != nil else { return [] }
        let dir = ((paths.first ?? screen!) as NSString).deletingLastPathComponent

        /// `shot-00:18(…).jpg = IntelliJ IDEA — OwnerController.java`
        ///
        /// **The title goes here and not into the file name**, which is where
        /// the offset and the pointer already live. Those two are short,
        /// machine-generated readings that survive being made into a filename.
        /// A window title is arbitrary text — it carries `/`, quotes, colons and
        /// eighty characters of headline — so putting it in a name means
        /// sanitising away exactly the characters that identify the page, and
        /// leaves Victor, who reads these names himself, with something he
        /// cannot read. The evals settled the cost question: the addressing is a
        /// rounding error beside the pixels, so the line has room.
        ///
        /// **Only the deliberate shots are described this way.** The automatic
        /// context frame gets `handed` instead: what was in front of him then is
        /// now its own `[Focused window: …]` block in the envelope, because it is
        /// a fact about the dictation rather than a caption identifying one
        /// picture among several — and burying it here hid it behind a clause
        /// that tells you not to open the file.
        func handed(_ original: String) -> String {
            ((ScreenCapture.handover(for: original)) as NSString).lastPathComponent
        }
        func described(_ original: String) -> String {
            guard let source = sources[original] else { return handed(original) }
            return "\(handed(original)) = \(source)"
        }

        // **A clause each, rather than one sentence with the context tacked on.**
        // Written as one, it came out `… = Google Chrome — Netflix. shot-00:00(…)
        // is the screen when I started talking` — and a window title can itself
        // end in a full stop, so the separator between the last shot and the
        // context frame stopped being a separator. Titles are arbitrary text;
        // the brackets are the only delimiter here that they cannot forge.
        var note = "Each is at most \(ScreenCapture.handoverWidth)px wide; "
            + "drop the -small for the full-resolution original."
        // **The one thing a frame cannot say about itself.** A picture of a
        // region and a picture of a display are both a rectangle of pixels, and
        // nothing inside either says whether its edges are the edges of a
        // screen — so an agent handed a crop reads it as a whole desktop that
        // happens to be small, and a small desktop is a display it should be
        // looking around in. Said once, in the clause, and carried per frame by
        // the `area-` its name starts with.
        if paths.contains(where: ScreenCapture.isArea) || screen.map(ScreenCapture.isArea) == true {
            note += " Anything named `area-` is a region I dragged a box around, "
                + "not the whole screen — its edges are mine, not the display's."
        }

        // Nothing but the automatic frame — 168 of the 180 dictations in the
        // outbox look like this. One short clause and no ceremony.
        guard !paths.isEmpty else {
            guard let screen = screen else { return [] }
            return ["[the screen when I started talking, open only if the words need it: "
                    + "\(dir)/\(handed(screen)). \(note)]"]
        }

        var clauses = ["[the shots I took, in \(dir)/, oldest first, each named by what was in front of me: "
                       + paths.map(described).joined(separator: "; ") + ". \(note)]"]
        if let screen = screen {
            clauses.append("[and \(handed(screen)) is the screen when I started talking, "
                           + "open it only if the words need it]")
        }
        return clauses
    }

    /// The full text is in the outbox either way. What rides into the terminal
    /// is a prompt somebody has to be able to read back, and a selection can be
    /// an entire file.
    private static func clampForTerminal(_ s: String, _ limit: Int = 400) -> String {
        let flat = s.components(separatedBy: .newlines).joined(separator: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    /// What was selected when he started talking IS the subject, for the whole
    /// dictation — so the first non-empty read wins and nothing later overwrites
    /// it. He talks for a minute, another window jumps in front, he switches
    /// apps to look something up: none of that changes what he is talking about.
    /// Later probes exist only to fill a blank the first one left.
    private func stashSelection() {
        stateLock.lock()
        let alreadyHave = pendingSelection != nil
        // Which dictation this probe belongs to. `dictationStartedAt` is set the
        // instant one opens and nil'd the instant one ends, by every route there
        // is, so it doubles as the identity of the sentence in flight.
        let opened = dictationStartedAt
        stateLock.unlock()
        guard !alreadyHave else { return }

        let text = SelectionCapture.read()
        Log.info("selection front=\(SelectionCapture.frontmostAppName() ?? "?") → \(text.map { "\($0.count) chars" } ?? "nothing")")
        guard let text = text, !text.isEmpty else { return }

        stateLock.lock()
        // **The dictation can end while this probe is still running**, and often
        // does: the ⌘C fallback polls the pasteboard for up to 400ms, and the
        // wheel held down through those 400ms is a cancel. Everything the cancel
        // cleared would then be written straight back — a `pendingSelection` that
        // rides the *next* sentence, and a row on the chip with no dictation
        // behind it. Anchored on the moment it opened, so a sentence that ended
        // (nil) or a different one that has since begun both read as stale.
        let stale = opened == nil || dictationStartedAt != opened
        let lost = pendingSelection != nil      // the other probe got there first
        if !stale && !lost { pendingSelection = text }
        stateLock.unlock()
        guard !stale else {
            Log.info("selection dropped — the dictation it was read for is over")
            return
        }
        guard !lost else { return }
        DispatchQueue.main.async { [weak self] in self?.overlay.setSelection(text) }
    }

    /// The shutter's other half: whatever is highlighted **at this moment**,
    /// filed under where in the sentence he is.
    ///
    /// He points at things by highlighting them as much as by photographing
    /// them, and until now only the first of those survived — the selection was
    /// frozen at the start of the dictation and every later highlight was
    /// dropped. Now the same press that says "look at this" also records what
    /// "this" was selected as, which is the half a picture cannot carry: a
    /// screenshot shows a line of code, the selection *is* the line of code, in
    /// characters something can grep for.
    ///
    /// **Three things are skipped, and each of them would be noise:**
    /// nothing highlighted at all; the same text the frozen selection already
    /// holds (he never let go of it, which is the common case and says nothing
    /// new); and the same text as the previous extra, for shots taken in quick
    /// succession over one highlight.
    ///
    /// **Read the same way the opening selection is** — AX first, then the ⌘C
    /// probe. It was AX-only, to keep a synthetic keystroke out of an app he is
    /// pointing at several times a sentence, and the consequence was that the
    /// feature was missing precisely where he uses it: a highlight in a Chrome
    /// page is not a highlight AX can see, so every shot he took over one filed
    /// nothing at all, without saying so. See `SelectionCapture.read`.
    // MARK: - The selection watcher

    /// **A highlight is picked up on its own, without the shutter** (2026-09-09).
    ///
    /// Victor's ask, and his reason: *"de multe ori selectez text și apoi apas
    /// butonul de back ca să ți-l dau, doar că asta face și poza la ecran, ceea
    /// ce uneori nu-i nevoie. Ai putea să preiei automat textul selectat printr-un
    /// polling, să vezi dacă s-a selectat text nou în timpul dictării … dacă e
    /// nou; dacă l-ai mai văzut, îl ignori. Și în felul ăsta n-aș mai fi nevoit
    /// să fac poze ca să-ți dau textul selectat."*
    ///
    /// **The shutter is one gesture doing two jobs.** Mouse 4 takes a picture
    /// *and* reads the selection, so the only way to hand over a highlight was to
    /// pay for a retina JPEG he did not want — on disk (a megabyte or two a
    /// press, in a folder capped at 300 frames) and in the agent's context (~550
    /// tokens for an 800px frame, and it has to be *looked at* before anything
    /// can be read off it). A selection costs the characters it contains and is
    /// already the thing he meant. Selecting the text is a gesture he was making
    /// anyway; this makes it the whole gesture.
    ///
    /// - **Accessibility only** (`SelectionCapture.readQuiet`) — see there for
    ///   why the ⌘C fallback the shutter uses is exactly wrong in a loop. The
    ///   cost is that a highlight in a **Chrome page** is not seen: that is the
    ///   one case AX does not expose and the reason the shutter grew the ⌘C in
    ///   the first place. Mouse 4 is still the answer there, and so is ⌘⇧-click,
    ///   which addresses a page element properly rather than as loose text.
    /// - **It has to settle before it is filed: three identical reads in a row.**
    ///   A selection made by dragging grows under the cursor — `Hel`,
    ///   `Hello wor`, `Hello world` — and a poll that filed the first thing it
    ///   saw would put a fragment in the message and the whole line beside it.
    ///   Victor's rule, and his words for what three unchanged reads mean:
    ///   *"3 selecții identice = m-am oprit"*. At a 1s tick that is two seconds
    ///   of a hand that has stopped moving, which is a much stronger statement
    ///   than one second and costs nothing that matters — the sentence is still
    ///   being spoken.
    /// - **The stamp is when it was *first* seen, not when it was confirmed.**
    ///   *"reține și timestampul selecției"*. Waiting two seconds to be sure is
    ///   the watcher's business; the offset in the message is supposed to say
    ///   where in the sentence the highlight happened, and filing it two seconds
    ///   late would put every automatic selection behind the words it belongs
    ///   to.
    /// - **One last read when the microphone closes**, whatever it has or has
    ///   not settled into: *"la finele dictării preiei selecția activă încă o
    ///   dată, să nu fi selectat exact pe final"*. The settle rule is a filter
    ///   against fragments and it has a cost — a highlight made in the last two
    ///   seconds of a sentence would never be confirmed, and that is exactly the
    ///   moment he selects the thing he has just finished describing. There is
    ///   no fragment risk at the end: the drag is over, or he would not have
    ///   stopped talking.
    /// - **Once each, per dictation.** `polledSeen` is what *"dacă l-ai mai
    ///   văzut, îl ignori"* is: a highlight left on screen is read every tick
    ///   and filed on none of them after the first. It is a set rather than a
    ///   last-value check, so going back to something he selected earlier in the
    ///   same sentence is not a second entry either.
    /// - **Silent when it finds nothing new.** The chip's `“ selecting …` row is
    ///   the receipt for a *deliberate* press; here it appears only on the tick
    ///   that actually filed something.
    /// - **Not in Replace Wispr.** `caretLine` carries no `[selected: …]` at all
    ///   — the field under the caret is the one he is dictating *into* — so a
    ///   watcher there would gather text nothing would ever send.
    /// - **The first one still fills the frozen slot.** A dictation that opened
    ///   with nothing highlighted takes the first thing he selects as its
    ///   subject, which is `fileSelection`'s existing rule and is exactly right
    ///   here: he starts talking, then selects the thing he is talking about.
    /// **One second, not the 0.6 it shipped at.** Victor: *"pune 1s în loc de
    /// 0,6, să nu fie grabă"*. Nothing downstream of this is in a hurry — the
    /// sentence is still being spoken — and three ticks at a second apart is a
    /// far better statement about a hand having stopped than three at 0.6.
    private static let selectionPollSeconds: TimeInterval = 1.0

    /// How many identical reads in a row mean the hand has stopped.
    private static let selectionSettleReads = 3

    /// Reset per dictation, and touched **only** on `selectionQueue`, which is
    /// serial — so none of them needs a lock of its own.
    ///
    /// `polledSettling` keeps **when the text was first seen** along with the
    /// text, because that is the offset the message carries: the two seconds
    /// spent making sure are the watcher's problem, not the transcript's.
    private var polledSettling: (text: String, since: Date, reads: Int)?
    private var polledSeen: Set<String> = []
    private var selectionWatch: DispatchSourceTimer?
    private let selectionQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.selection")

    /// On for the length of a dictation, off otherwise — driven from
    /// `syncBorrowedGestures`, the one switch every edge of a dictation passes
    /// through, so the watcher cannot outlive the sentence it belongs to.
    private func syncSelectionWatch(_ on: Bool) {
        guard on != (selectionWatch != nil) else { return }
        guard on else {
            selectionWatch?.cancel()
            selectionWatch = nil
            Log.info("👁 selection watcher off")
            return
        }
        Log.info("👁 selection watcher on — reading the highlight every "
                 + String(format: "%.1fs", Self.selectionPollSeconds))
        selectionQueue.async { [weak self] in
            self?.polledSettling = nil
            self?.polledSeen = []
        }
        let timer = DispatchSource.makeTimerSource(queue: selectionQueue)
        timer.schedule(deadline: .now() + Self.selectionPollSeconds,
                       repeating: Self.selectionPollSeconds)
        timer.setEventHandler { [weak self] in self?.pollSelection() }
        timer.resume()
        selectionWatch = timer
    }

    /// One tick. On `selectionQueue`, which is serial, so a read that outran its
    /// interval delays the next one rather than overlapping with it.
    private func pollSelection() {
        stateLock.lock()
        let opened = dictationStartedAt
        stateLock.unlock()
        // The dictation ended between the tick being scheduled and it running.
        guard let opened = opened else { return }

        guard let text = SelectionCapture.readQuiet(), !text.isEmpty else {
            // Nothing highlighted: whatever was settling is abandoned rather than
            // carried across a gap, so `select, deselect, select the same again`
            // has to settle again on its own.
            polledSettling = nil
            return
        }
        guard !polledSeen.contains(text) else { return }
        guard var settling = polledSettling, settling.text == text else {
            polledSettling = (text: text, since: Date(), reads: 1)
            return
        }
        settling.reads += 1
        polledSettling = settling
        guard settling.reads >= Self.selectionSettleReads else { return }

        take(text, firstSeen: settling.since, opened: opened, how: "watched")
    }

    /// **The last read of a dictation, when the microphone closes.**
    ///
    /// The settle rule needs `selectionSettleReads` seconds of a hand that has
    /// stopped, and a highlight made in the last of those would never be
    /// confirmed — which is precisely the moment he selects the thing he has
    /// just finished describing. Victor: *"la finele dictării preiei selecția
    /// activă încă o dată, să nu fi selectat exact pe final"*.
    ///
    /// **No settling here**, deliberately: the drag is over, or he would not
    /// have stopped talking. `polledSeen` still applies, so the highlight that
    /// has been on screen all sentence is not filed a second time.
    ///
    /// **Off the main thread and not waited on.** It is posted to the same
    /// serial queue the ticks run on, so it lands after any read already in
    /// flight, and the transcript it has to beat is a round trip through the
    /// helper — a second at the very least against an AX call measured in
    /// milliseconds. Blocking the main thread for up to the AX timeout at the
    /// instant the microphone closes would be the worse trade: that is the frame
    /// the recording row is being replaced in.
    private func finalSelectionRead(then: (() -> Void)? = nil) {
        selectionQueue.async { [weak self] in
            // `then` is `/test/dictation`'s only way to model the tail of a real
            // dictation: there, the transcript follows the microphone closing by
            // a decode — a second at the very least — while the route hands one
            // over on the spot, so without somewhere to hang the send it would
            // race this read and lose every time.
            defer { if let then = then { DispatchQueue.main.async(execute: then) } }
            guard let self = self else { return }
            self.stateLock.lock()
            let opened = self.dictationStartedAt
            self.stateLock.unlock()
            guard let opened = opened else { return }
            guard let text = SelectionCapture.readQuiet(), !text.isEmpty else { return }
            guard !self.polledSeen.contains(text) else { return }
            self.take(text, firstSeen: Date(), opened: opened, how: "watched at the close")
        }
    }

    /// File one watched highlight. On `selectionQueue`.
    private func take(_ text: String, firstSeen: Date, opened: Date, how: String) {
        polledSeen.insert(text)
        polledSettling = nil
        // **Stamped from when it was first seen**, not from now: the settling is
        // the watcher making sure, and a stamp two seconds behind the highlight
        // would put it after the words it belongs to.
        let offset = firstSeen.timeIntervalSince(opened)
        Log.info("👁 selection \(how) at \(Self.stamp(offset)) — \(text.count) chars, taken without a shot")
        fileSelection(text, at: offset, opened: opened, announceOnRepeat: false)
    }

    private func stashExtraSelection(at offset: TimeInterval) {
        stateLock.lock()
        let opened = dictationStartedAt
        stateLock.unlock()
        guard let text = SelectionCapture.read(), !text.isEmpty else { return }
        fileSelection(text, at: offset, opened: opened, announceOnRepeat: true)
    }

    /// File one highlight against the dictation in flight, and say so on the
    /// chip. Shared by the shutter — which reads with a ⌘C fallback — and by the
    /// watcher, which reads through Accessibility alone.
    ///
    /// `announceOnRepeat` is the one thing the two callers disagree about. A
    /// **press** that found a highlight already carried still deserves the
    /// receipt: he aimed at something and a shutter that says nothing reads as
    /// one that missed. A **poll** that finds the same text has found nothing —
    /// saying so once a second would be a row flickering for the whole sentence
    /// about a highlight that has not changed.
    private func fileSelection(_ text: String, at offset: TimeInterval, opened: Date?,
                               announceOnRepeat: Bool) {
        stateLock.lock()
        // The probe outliving its dictation, exactly as in `stashSelection` and
        // for the same 400ms — a highlight filed against a sentence that is over
        // would be attached to the next one and shown on a chip at rest.
        guard opened != nil, dictationStartedAt == opened else {
            stateLock.unlock()
            Log.info("↪ selection at \(Self.stamp(offset)) — the dictation ended first, dropped")
            return
        }
        let isFrozen = pendingSelection == text
        let isRepeat = pendingExtraSelections.last?.text == text
        let novel = !isFrozen && !isRepeat
        // A dictation that opened with nothing highlighted has an empty frozen
        // slot, and the first thing he highlights mid-sentence belongs *there* —
        // it is the subject, arriving late. Only once that slot is taken does a
        // highlight become an extra.
        let fillsTheBlank = novel && pendingSelection == nil
        if fillsTheBlank {
            pendingSelection = text
        } else if novel {
            pendingExtraSelections.append((at: offset, text: text))
        }
        let total = (pendingSelection != nil ? 1 : 0) + pendingExtraSelections.count
        stateLock.unlock()

        // **The receipt is not behind `novel`, the filing is.** Three reads are
        // skipped as noise — nothing highlighted, the text the frozen slot
        // already holds, the same text as the last extra — and for two of those
        // the press still *caught* something: he had a highlight on screen and
        // pressed the shutter over it. A shutter that says nothing in that case
        // reads as one that missed, which is exactly the failure the row was
        // added to rule out. So the chip confirms every press that read a
        // selection, and the message still carries each highlight once.
        if novel {
            Log.info("↪ selection at \(Self.stamp(offset)) — \(text.count) chars (\(total) in this dictation)")
        } else if announceOnRepeat {
            Log.info("↪ selection at \(Self.stamp(offset)) — already carried, not filed again")
        }
        guard novel || announceOnRepeat else { return }
        // **Said back, in his own words, for a beat.** The row carries this
        // highlight for the rest of the dictation either way, which answers "is
        // it still there" but not the question he has at the instant he presses:
        // *did this catch the thing I meant?* A picture is taken silently and a
        // selection is read silently, so without the verb the only confirmation
        // that the shutter grabbed the right paragraph arrived in the terminal,
        // a sentence too late to reselect.
        DispatchQueue.main.async { [weak self] in
            self?.overlay.setSelection(text, count: total)
        }
    }

    /// `m:ss`, the one clock this app measures anything in.
    private static func stamp(_ offset: TimeInterval) -> String {
        let s = max(0, Int(offset.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Mouse 4 while dictating — one more shot for the dictation in
    /// progress, with the cursor recorded so the agent can see what he was
    /// pointing at when he pressed.
    private func plusOneShot(cursor: NSPoint) {
        guard hasDestination else { return }
        // Sampled at the gesture, like the cursor and for the same reason: by the
        // time `screencapture` returns, a subprocess later, the moment he pressed
        // at is a second in the past — and a second is a whole sentence.
        let takenAt = Date()
        // Sampled here with the moment and the cursor, not in the background
        // block below: this is the window he pressed the shutter *at*.
        let source = WindowContext.describe()
        // Flash first, capture second — same reason as in `captureContext`: the
        // confirmation should land on the keypress, not on the subprocess.
        CaptureFlash.announce(cursor: cursor, cycleMarker: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Where in the sentence this is, read **before** the capture: the
            // name is built from it, and a dictation that ends while
            // `screencapture` runs would otherwise turn a 1:52 into a timestamp.
            self.stateLock.lock()
            let openNow = self.dictationInFlight
            let startedAt = self.dictationStartedAt
            self.stateLock.unlock()
            let offset = openNow ? takenAt.timeIntervalSince(startedAt ?? takenAt) : nil

            // **Before `screencapture`, for the same reason the cursor is.** The
            // shutter is pressed at a moment, and by the time a subprocess has
            // run and returned, the caret and the highlight it sat in have both
            // moved on. A selection read after the picture would be a selection
            // from after the picture.
            //
            // **In Replace Wispr too, since 2026-09-09.** It was skipped there,
            // because `SelectionCapture.read` falls back to a synthetic ⌘C and
            // the field under the caret is the one he is dictating *into*. That
            // objection was really about the *automatic* probe, which fires on
            // every press of the wheel with no subject behind it; this one is a
            // deliberate press with a deliberate subject, and it is the only
            // route that sees a highlight in a **Chrome page** at all — which is
            // where the watcher's Accessibility read is blind. ⌘C reads and
            // changes nothing, and the clipboard is put back.
            if let offset = offset { self.stashExtraSelection(at: offset) }

            guard let path = ScreenCapture.grab(cursor: cursor, offset: offset) else {
                DispatchQueue.main.async { self.overlay.flash("⚠️ screenshot failed") }
                return
            }

            self.stateLock.lock()
            let attaching = self.dictationInFlight
            if let source = source { self.shotSources[path] = source }
            if attaching {
                self.pendingShots.append(path)
                self.pendingShotOffsets.append(
                    takenAt.timeIntervalSince(self.dictationStartedAt ?? takenAt))
            }
            let count = self.pendingShots.count
            self.stateLock.unlock()

            if attaching {
                self.armOrphanFlush()
                Log.info("📸 attached to in-flight dictation (\(count) so far)")
                // No flash and no title override any more: both are panel states,
                // and throwing the panel into the corner is exactly what taking a
                // picture mid-dictation must not do. The `📸 ×N` in the recording
                // row goes up under his cursor instead — the receipt is the number.
                self.publishShotCount()
                return
            }
            self.send(kind: "screenshot", paths: [path])
        }
    }

    // MARK: - The region he dragged out

    /// The words on the selection overlay. **English**, like every other string
    /// this app renders — the chip and everything near it go on a projector in
    /// front of an international room. Victor Addons draws the same overlay in
    /// Romanian, which is exactly why the strings are a parameter of
    /// `CropSelectionStyle` rather than a constant inside the shared module.
    ///
    /// The hint itself is never shown here: it belongs to the flavour that waits
    /// for a drag to start, and this one arrives with one already under way.
    private static let cropStyle = CropSelectionStyle(
        hint: "drag an area  ·  ⌘ move  ·  ⌥ from centre  ·  Esc cancels",
        // Named after the keys and always on the readout, lit only while held
        // — see `CropSelectionStyle.movingSuffix`.
        movingSuffix: "⌘ move",
        centeredSuffix: "⌥ centre")

    /// **The wheel, dragged while he is talking: a region of the screen instead
    /// of the whole display.**
    ///
    /// A dictation's frames are the expensive half of the message — 800px of
    /// handover and a picture the agent has to *look through* before it can read
    /// anything — and most of what is in them is the desk around the answer. The
    /// shutter cannot help with that: it photographs a display because a press
    /// is a moment, not a shape. A drag is a shape, and it is the same hand
    /// already on the same mouse.
    ///
    /// **The dictation keeps running behind it.** Nothing here touches the
    /// microphone, the countdown or the chip: he is still mid-sentence, which is
    /// the whole point — he says *"this bit here"* and drags a box round it
    /// while saying it.
    ///
    /// **There is no red vignette and no cursor mark**, which every other
    /// capture in this app fires. Those exist to say *a picture was taken, and
    /// here is where you were pointing* about something that happened in a
    /// millisecond with nothing on screen to show for it. This one he watched
    /// himself draw, at the pixels he drew it around; a flash lit over them
    /// afterwards would be the same news, later, on top of the thing he framed.
    /// It is the same call Victor made in Victor Addons, where the crop's yellow
    /// border went the same day.
    ///
    /// `takenAt` is the **press**, not the release: the shot is named by where
    /// in the sentence he reached for it, and framing a box carefully is a
    /// second or two he should not be charged for.
    private func areaShot(from anchor: NSPoint, at takenAt: Date) {
        guard hasDestination else { return }
        // Sampled with the gesture, like the shutter's: by the time the box is
        // drawn the front window may be one he switched to in order to frame it.
        let source = WindowContext.describe()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // **Main, and not the tap thread.** The overlay puts a panel up per
            // screen and sets window frames; the same mistake made in an
            // `ElementPicker` callback took the whole app down with a `SIGTRAP`
            // inside `NSWMWindowCoordinator`.
            CropSelectionOverlay.begin(button: .middle, from: anchor, style: Self.cropStyle) { selection in
                guard let selection = selection else {
                    // Esc, a right-click, or a drag that turned out to be a
                    // twitch. Nothing was filed and nothing is said: he called it
                    // off, and an app reporting his own cancellation back to him
                    // is the tidy-up-announcement `checkAlive` already refuses.
                    Log.info("✂️ area selection cancelled")
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    self.fileArea(selection, takenAt: takenAt, source: source)
                }
            }
        }
    }

    /// The tail of `plusOneShot`, for a rectangle instead of a display: name it
    /// by where in the sentence it was taken, attach it to the dictation in
    /// flight, and let the chip count it.
    private func fileArea(_ selection: CropSelectionOverlay.Selection,
                          takenAt: Date, source: String?) {
        stateLock.lock()
        let openNow = dictationInFlight
        let startedAt = dictationStartedAt
        stateLock.unlock()
        let offset = openNow ? takenAt.timeIntervalSince(startedAt ?? takenAt) : nil

        guard let path = ScreenCapture.grabArea(selection.rect, on: selection.screen, offset: offset) else {
            DispatchQueue.main.async { self.overlay.flash("⚠️ area capture failed") }
            return
        }

        stateLock.lock()
        let attaching = dictationInFlight
        if let source = source { shotSources[path] = source }
        if attaching {
            pendingShots.append(path)
            pendingShotOffsets.append(takenAt.timeIntervalSince(dictationStartedAt ?? takenAt))
        }
        let count = pendingShots.count
        stateLock.unlock()

        guard attaching else {
            // The sentence ended while he was framing. The picture is still
            // worth having on its own — same rule the shutter follows.
            send(kind: "screenshot", paths: [path])
            return
        }
        armOrphanFlush()
        Log.info("✂️ area attached to in-flight dictation (\(count) picture(s) so far)")
        publishShotCount()
    }

    // MARK: - Picked elements

    /// A ⌘-click landed in Chrome. Off the main thread — this arrives on the
    /// listener's queue.
    ///
    /// Only reachable while dictating: the endpoint refuses everything else
    /// (`ElementPicker.dictating`), so by the time one gets here it is a thing he
    ///
    /// There is no flash and no panel, deliberately: the outline in the page has
    /// already turned green under his cursor, at the pixel he clicked, before this
    /// code ran. A second receipt across the screen would be the same news, later
    /// and further away. What this adds is the running total, in the chip.
    private func record(_ pick: ElementPick) {
        stateLock.lock()
        // **A drag amends the press that started it, rather than arriving beside
        // it.** The extension picks on the *press* — the outline turns green
        // under his finger before this code has run, which is the receipt — and
        // it cannot know at that instant whether a drag is about to follow. So a
        // drag sends the same element again with its two corners on it, and the
        // one already waiting is replaced: one gesture, one entry, and the
        // receipt still lands at the press where his hand expects it.
        //
        // Matched on the path and only against the newest entry, so two
        // deliberate picks of two different things can never collapse into one.
        if pick.move != nil, pendingPicks.last?.path == pick.path {
            pendingPicks.removeLast()
        }
        pendingPicks.append(pick)
        pruneStalePicks()
        let count = pendingPicks.count
        let last = pendingPicks.last?.short ?? ""
        stateLock.unlock()
        Log.info("🎯 \(count) element(s) waiting on a sentence — newest \(last)")
        publishPicks()
    }

    /// Caller holds `stateLock`.
    private func pruneStalePicks() {
        let cutoff = Date().addingTimeInterval(-pickTTL)
        pendingPicks.removeAll { $0.at < cutoff }
    }

    /// **Everything he ⌘⇧-clicked in Chrome, in one clause: when, what, and on
    /// which page** (2026-09-09).
    ///
    /// ```
    /// [elements I picked in Chrome, on https://shop.example/cart, oldest first,
    ///  each stamped with when in the sentence I clicked it:
    ///  0:12 div#cart > span.price (1.299,00 lei) ·
    ///  0:21 button.buy-button (Cumpără acum), moved from 120,340 to 500,205 …]
    /// ```
    ///
    /// It read `[pointed at: <path> (<text>)]` until then, and Victor named all
    /// three things missing from it in one breath: *"dacă se aleg mai multe
    /// elemente pe parcursul dictării, ele trebuie toate să fie capturate
    /// împreună cu timpul la care au fost clickate … și nu «pointed at» ca text,
    /// trebuie să-i spui că picked element in Chrome … și să-i spui și URL-ul
    /// paginii în care ai făcut pick, nu doar path-ul, că nu e relevant"*.
    ///
    /// - **The stamps** are the same reading the held panel has always shown and
    ///   the message never did — and they are the half that orders a sentence
    ///   against its own pointing. `−0:08` is normal and not an edge case:
    ///   pointing usually comes *before* the words, since he finds the thing and
    ///   then says what to do with it.
    /// - **The page, because a selector without one is not an address.**
    ///   `div#cart > span.price` resolves in any number of documents, and the
    ///   agent's first move on receiving one is to find out which — a question
    ///   already answered in `pick.url` and simply never said out loud.
    /// - **Factored out when they all came from one page**, which is the usual
    ///   case and the difference between one URL and five copies of one. The same
    ///   bargain `shotsClause` strikes with the directory, and it says something
    ///   true besides: these all came from the same page. Mixed, each entry
    ///   carries its own.
    /// - **`picked … in Chrome` rather than `pointed at`.** The old wording named
    ///   the gesture; this one names what arrived, which is a DOM element from a
    ///   browser and not a direction.
    /// - **The move is spelled out in words** rather than as a pair of fields,
    ///   because the clause is read by an agent as a sentence and by Victor as a
    ///   receipt, and *moved from 120,340 to 500,205* is the same instruction in
    ///   both readings — his own wording: *"se mută de la XY la XY, coordonata
    ///   originală cu colțul stânga sus"*.
    ///
    /// Shared by `terminalLine` and `caretLine` — the two envelopes name picks
    /// identically on purpose, and the day they stopped doing so would be the
    /// day a caret dictation quietly lost half of what it was carrying.
    private static func picksClause(_ picks: [ElementPick], since: Date?) -> String? {
        guard !picks.isEmpty else { return nil }
        let urls = Set(picks.map { $0.url ?? "" })
        // One page and every pick actually carrying it: an empty URL among them
        // means one entry would silently inherit another's page.
        let shared = urls.count == 1 ? urls.first.flatMap { $0.isEmpty ? nil : $0 } : nil

        let named = picks.map { pick -> String in
            var line = ""
            if let stamp = stamp(pick.at, since: since) { line += stamp + " " }
            line += pick.path
            if let text = pick.text, !text.isEmpty { line += " (\(clampForTerminal(text, 60)))" }
            if shared == nil, let url = pick.url, !url.isEmpty { line += " on \(url)" }
            if let move = pick.move {
                line += ", moved from \(move.from.x),\(move.from.y)"
                      + " to \(move.to.x),\(move.to.y) (top-left, page coordinates)"
            }
            return line
        }

        var head = picks.count == 1 ? "element I picked in Chrome" : "elements I picked in Chrome"
        if let shared = shared { head += ", on \(shared)" }
        if picks.count > 1 { head += ", oldest first" }
        if since != nil {
            head += picks.count > 1 ? ", each stamped with when in the sentence I clicked it"
                                    : ", stamped with when in the sentence I clicked it"
        }
        return "[\(head): \(named.joined(separator: " · "))]"
    }

    /// Where in the sentence something happened, as `m:ss` — or `−m:ss` when it
    /// happened before the microphone opened, which for a pick is the ordinary
    /// order rather than an oddity. Nil with no dictation to measure against.
    private static func stamp(_ at: Date, since: Date?) -> String? {
        guard let since = since else { return nil }
        let seconds = Int(at.timeIntervalSince(since).rounded())
        let sign = seconds < 0 ? "−" : ""
        let abs = Swift.abs(seconds)
        return String(format: "%@%d:%02d", sign, abs / 60, abs % 60)
    }

    /// Keep the overlay's `🎯 ×N` honest, and name the newest one — the count says
    /// the click landed, the name says *what* landed, which is the half he can
    /// actually check against what he meant to point at.
    private func publishPicks() {
        stateLock.lock()
        pruneStalePicks()
        let count = pendingPicks.count
        let newest = pendingPicks.last?.short
        // **Any of them, not the newest.** The row settles into a bare count, and
        // *one of these was dragged somewhere* is exactly the thing a count
        // cannot say about the things it counted.
        let moved = pendingPicks.contains { $0.move != nil }
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.overlay.setPicks(count: count, newest: newest, moved: moved)
        }
    }

    /// The elements line(s): one per thing he pointed at, in the order he pointed
    /// at them, each with when it happened relative to the dictation.
    ///
    /// A selector is not a stamp on a list, it *is* the content — so unlike the
    /// pictures, these get a line each rather than a row of times. He has to be
    /// able to read "that is the buy button, not the price next to it" in the
    /// seconds Cancel is still available, and a comma-separated run of CSS paths
    /// is not readable at that speed.
    ///
    /// **The type, not the selector.** These lines used to carry `pick.short` —
    /// the last two steps of the path, `div#cart > span.price` — which is the
    /// right thing to *send* and the wrong thing to show here. Three of them turn
    /// the panel into a wall of punctuation to be read at the exact moment the
    /// Cancel clock is running, and the question he is answering is not "which
    /// selector" but "did my three clicks land". `button`, `div`, `a` answers that
    /// in a glance. The full selector still travels in the message; nothing is
    /// lost, it is just not shouted at him. Bulleted for the same reason: a list
    /// of three is read as a count when it looks like a list.
    ///
    /// **Negative stamps are the point, not an edge case.** Pointing usually comes
    /// *before* the sentence — he finds the thing, then says what to do with it —
    /// so `−0:08` reads exactly as it should: you pointed at this eight seconds
    /// before you started talking.
    private static func pickLines(_ picks: [ElementPick], since: Date?) -> [String] {
        let shown = picks.prefix(maxPickLines)
        // The same `stamp` the message uses, so the panel and the envelope can
        // never disagree about where in the sentence a pick happened.
        var lines = shown.map { pick -> String in
            guard let at = stamp(pick.at, since: since) else { return "• \(pick.tag)" }
            return "• \(at) \(pick.tag)"
        }
        if picks.count > shown.count { lines.append("• +\(picks.count - shown.count) more") }
        return lines
    }

    /// Enough to check the ones he is likely to still be holding in his head. Past
    /// that the panel is a list he has to read instead of a prompt he has to
    /// approve, and the countdown is running.
    private static let maxPickLines = 3

    /// Same bargain as `maxPickLines`, and the same countdown behind it: past
    /// two or three the panel is a document rather than a prompt to approve.
    private static let maxExtraSelectionLines = 3

    /// **When each picture was taken**, as m:ss from the moment he started
    /// talking — one stamp per frame, in the order the frames are handed over.
    ///
    /// The count alone answers "did my shots land"; it does not answer the
    /// question he actually has a few seconds later, which is *which* moments he
    /// caught. In a three-minute dictation `📸 ×4` is four indistinguishable
    /// files, while `0:38`, `1:52`, `2:41` written across the frames themselves
    /// is a table of contents — and this panel, with Cancel still running, is the
    /// last instant at which noticing a missing one is free.
    ///
    /// Relative to the dictation, never wall-clock: the shots exist only as parts
    /// of this message, and 15:22:07 says nothing about where in it he was.
    ///
    /// **The context shot gets no stamp**, and an empty string is what says so.
    /// Its `0:00` is the one stamp that carries no information — the automatic
    /// capture is always at zero, by definition — so it stays a bare frame.
    ///
    /// These used to be a line of text above the strip (`0:38 · 1:52 · 2:41`),
    /// which left the reader counting columns to pair a stamp with a frame — and
    /// counting them across a *gap*, since the unstamped context shot is in the
    /// strip and was not in the line. Written **on** the thumbnail there is
    /// nothing to pair: the caption is inside the picture it captions.
    static func shotStamps(_ offsets: [TimeInterval]) -> [String] {
        offsets.map { offset in
            guard offset > 0 else { return "" }
            let s = Int(offset.rounded())
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }

    /// What to render in the overlay as "this is what the agent got". Returns nil
    /// for messages with no words in them (a bare screenshot), which fall back
    /// to the one-line flash.
    private static func promptPreview(text: String?, selection: String?,
                                      extraSelections: [(at: TimeInterval, text: String)] = [],
                                      picks: [ElementPick], since: Date?) -> String? {
        var parts: [String] = []
        if let text = text, !text.isEmpty { parts.append(text) }
        // **The selection counts as something to show, but is not shown here.**
        // It goes to the panel separately and is drawn above the words, quoted —
        // so this string must not carry it, and must still refuse to return nil
        // for a message that has one. Getting only the first half of that right
        // would send a highlighted-with-no-words message straight out, past the
        // Cancel button that exists for it.
        let hasSelection = !(selection ?? "").isEmpty
        guard !parts.isEmpty || hasSelection else { return nil }
        // Stamped, and after the words rather than before them: the frozen
        // selection is what he was talking *about* and belongs at the top, while
        // these are things he reached for part-way through and read back in the
        // order he reached for them. Cancel is still running while he reads this,
        // which is the only moment noticing a wrong highlight is free.
        for extra in extraSelections.prefix(maxExtraSelectionLines) {
            parts.append("↪ \(stamp(extra.at)) " + extra.text)
        }
        if extraSelections.count > maxExtraSelectionLines {
            parts.append("↪ +\(extraSelections.count - maxExtraSelectionLines) more")
        }
        parts.append(contentsOf: pickLines(picks, since: since))
        return parts.joined(separator: "\n")
    }

    /// The ✕ and the menu bar's Quit both end the session. Announce it through the
    /// outbox before quitting so the watching agent learns the overlay is gone
    /// from the queue itself — it is blocked on that file, not on the process, and
    /// would otherwise sit waiting for messages that can no longer come.
    private func endSession(reason: String) {
        announceEnd(reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// Every deliberate way out goes through here — the ✕, ⌘Q, a Quit sent from
    /// Activity Monitor — and it fires at most once.
    ///
    /// The words travel in `text`, not just in `kind`: the agent is watching a
    /// queue, and "user closed the relay" reads as the instruction it is —
    /// stop watching — where a bare `session_end` has to be interpreted.
    private func announceEnd(_ reason: String) {
        guard !endAnnounced else { return }
        endAnnounced = true
        // Anything still counting down goes out ahead of the goodbye. Quitting is
        // not cancelling — Cancel is a button he presses on purpose — and the
        // outbox writes serially, so it lands in the right order.
        overlay?.flushHeldPrompt()
        // Let the ~2.5 GB go on the way out. It would go anyway — the helper sees
        // EOF on stdin when the relay's pipes close and exits on its own, measured
        // at nine seconds even after a SIGKILL — but nine seconds of a model
        // nobody is using is nine seconds of a laptop that is not his to spend.
        whisperSource.shutDown()
        Log.info("session ended via \(reason)")
        Outbox.send(kind: "session_end", text: "user closed the relay")
    }

    /// Catches the quit routes the ✕ does not: ⌘Q, and the Apple Event a newly
    /// launched instance sends to its predecessor.
    ///
    /// Which is exactly why it consults the replacement marker first. Restarting
    /// the relay kills the old one, and reporting *that* as "user closed the
    /// overlay" would tell the agent to stop watching at the very moment Victor
    /// asked for a fresh session — the one failure mode worth writing code to
    /// avoid, since it is silent and he would only notice by talking into a void.
    func applicationWillTerminate(_ notification: Notification) {
        // Before either branch: a relay that quits mid-sentence must not leave
        // Chrome silent. The extension also resumes on a dead socket, but that is
        // the safety net for a crash, not the way an orderly quit should look.
        music.stop()
        // A marker outliving the process would put a microphone on a status line
        // with nothing behind it — see `Outbox.publishBound`.
        Outbox.publishBound(tty: nil)
        guard !SingleInstance.beingReplaced() else {
            Log.info("terminating to make way for a new instance — no session_end")
            return
        }
        announceEnd("app terminate")
    }

    private func send(kind: String, text: String? = nil, paths: [String] = [], app: String? = nil) {
        // **The outbox is not written either.** It used to be, on the grounds
        // that an agent might be watching the queue without a binding — the
        // `/relay` skill's original mode. Victor settled it on 2026-08-27: with
        // the app running from login, that meant every sentence he spoke all day
        // was being filed for a watcher that mostly is not there. Unbound now
        // means inert, and `/relay` gets its destination by binding like
        // everything else. `session_end` is unaffected: it goes to `Outbox`
        // directly, not through here.
        // Taken here and cleared here, so the flag never outlives the dictation
        // that set it: from this point the destination travels on the `Message`.
        //
        // **Only a dictation may claim it.** `flushOrphaned` comes through here
        // with a bag of screenshots when no transcript arrived — and, since its
        // timer is armed at the start of the dictation rather than at the end of
        // it, also in the middle of a sentence that has run past two minutes. A
        // spawn consumed there would open a session holding nothing but pictures
        // and leave the words that were still being spoken with nowhere to go.
        let spawn = spawnPending && kind == "dictation"
        // Taken and cleared in the same breath as the flag it belongs to — from
        // here the folder travels on the `Message`. Nil is the default it has
        // always had, so a dictation that never saw the menu is unchanged.
        let directory = spawnFolder ?? Self.spawnDirectory
        if kind == "dictation" { spawnPending = false; spawnFolder = nil }
        // **A dictation is never dropped for want of a binding any more**
        // (`holdsForBind`): it is built, shown and read exactly as a bound one
        // is, and `commit` parks it for the terminal Victor is about to point
        // at. Everything else here still is — `session_start`, `session_end` and
        // a bare screenshot are addressed to a watcher of the outbox, and an
        // outbox with nothing bound is the one thing the 2026-08-27 rule was
        // actually protecting.
        guard isBound || spawn || kind == "dictation" else {
            Log.info("unbound — dropped \(kind)")
            return
        }
        stateLock.lock()
        let selection = pendingSelection
        pendingSelection = nil
        let extraSelections = pendingExtraSelections
        pendingExtraSelections = []
        let sources = shotSources
        shotSources = [:]
        var attached = paths
        var screen: String?
        // The context shot is the first picture and it was taken at 0:00 — he took
        // it by starting to talk. Counting from `pendingScreen` rather than from
        // `attached` is what keeps this total agreeing with the `📸 ×N` he watched
        // go up while he was speaking, which does include it.
        var offsets: [TimeInterval] = []
        var picks: [ElementPick] = []
        var since: Date?
        if kind == "dictation" {
            attached += pendingShots
            screen = pendingScreen
            offsets = (pendingScreen != nil ? [0] : []) + pendingShotOffsets
            // Everything he pointed at goes with the words, whether he pointed
            // before or during — the queue exists precisely because those two
            // orders are equally normal. `since` is what turns the absolute
            // stamps into "where in this sentence", negatives and all.
            pruneStalePicks()
            picks = pendingPicks
            since = dictationStartedAt
            pendingPicks = []
            pendingShots = []
            pendingShotOffsets = []
            dictationStartedAt = nil
            pendingScreen = nil
            dictationInFlight = false
            contextShotPending = false
        }
        stateLock.unlock()

        if kind == "dictation" { publishPicks() }

        if kind == "dictation" {
            DispatchQueue.main.async { [weak self] in self?.orphanFlush?.cancel() }
        }

        let message = Message(kind: kind, text: text, selection: selection,
                              extraSelections: extraSelections,
                              paths: attached, screen: screen, sources: sources,
                              app: app, elements: picks, startedAt: since, spawn: spawn,
                              directory: directory)

        // Show what is about to go out — selection included, since that is part
        // of the prompt the agent receives, not a separate thing.
        let shown = Self.promptPreview(text: text, selection: selection,
                                       extraSelections: extraSelections,
                                       picks: picks, since: since)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlay.clearSelection()

            // Nothing to read is nothing to cancel: a bare screenshot goes
            // straight out, and so does the goodbye.
            guard let shown = shown else {
                self.pendingPromptWarning = nil
                self.commit(message)
                if kind == "dictation" {
                    // `offsets`, not `attached`: same total the recording row was
                    // showing a second ago, context shot included.
                    self.overlay.flash(offsets.isEmpty ? "🎙️ sent" : "🎙️ sent + \(offsets.count) 📸")
                }
                return
            }

            let warning = self.pendingPromptWarning
            self.pendingPromptWarning = nil
            let words = shown.split(whereSeparator: { $0.isWhitespace }).count
            // **Autosend is a flash, not a shorter countdown.** The hold is
            // normally scaled to how much there is to read, because the panel is
            // there to be read *before* deciding; with the decision taken in
            // advance there is nothing to scale to, and what is left is a receipt
            // — long enough to see that something went, short enough not to be a
            // window opening over his work.
            let hold = self.autosend ? Self.autosendHold
                     : min(max(Self.minHold, Double(words) / 3.0), Self.maxHold)
            // Oldest first, context frame included — it is picture one of the
            // enumeration far more often than it is a spare, and a strip that
            // skipped it would disagree with the count in the row above.
            let frames = ([screen] + attached).compactMap { $0 }
            // Aligned with `frames` by construction: `offsets` is built from the
            // same `pendingScreen` + `pendingShots` in the same order, a few lines
            // up, which is what lets the panel write each stamp on its own frame.
            let stamps = Self.shotStamps(offsets)
            if self.overlay.showSentPrompt(shown, hold: hold, shots: frames,
                                           stamps: stamps,
                                           selection: selection,
                                           front: screen.flatMap { sources[$0] },
                                           // What he said, apart from what the
                                           // preview adds to it — the panel needs
                                           // the seam to know what is editable.
                                           words: text, warning: warning,
                                           buttons: !self.autosend,
                                           // Consumed above, so the panel is told
                                           // rather than left to re-derive it.
                                           spawning: spawn) {
                self.held = message
                self.hotkeys.promptHeld = true
            } else {
                self.commit(message)
            }
        }
    }

    /// The only route to the outbox — and therefore the only place the bound
    /// terminal has to be taught about. Everything else builds a `Message` and
    /// hands it here, eventually or never; Cancel is still the thing that means
    /// neither happens.
    ///
    /// **The outbox is written whether or not a terminal is bound**, and that is
    /// deliberate. It is the log of what Victor said — the record that outlives
    /// the session, the thing to read when a delivery went somewhere surprising
    /// — and a binding is a second destination, not a replacement for the first.
    /// It also means an agent watching the queue the old way keeps working while
    /// the same words are being typed at another one.
    ///
    /// `session_end` is the exception: it is addressed to a watcher, and there
    /// is nothing for a terminal to do with "the user closed the relay".
    /// What ⌘⌃P pastes: the last dictation that actually went out — **the whole
    /// line the terminal got**, not just the words.
    ///
    /// It was the words alone until 2026-09-04, on the argument that the
    /// envelope — `📸 ×2 0:38`, the quoted selection, the picked selectors, the
    /// paths of the frames — is addressed to an agent and is noise in a commit
    /// message. Victor reversed it: *"paste the whole text with all the image
    /// references and everything"*. The argument was about the wrong caret. The
    /// place this lands is overwhelmingly **another agent** — a second session, a
    /// web chat, an editor's assistant — and there the screenshots and the
    /// highlight are the half that cannot be retyped, while a stray `📸 ×2` in a
    /// commit message is a word to delete.
    ///
    /// **Replace Wispr still pastes the words**, and that is not an exception to
    /// the rule but the rule itself: that mode builds no envelope at all, so the
    /// words *are* the whole message. `pasteText` sets this for it.
    ///
    /// Set at `commit`, so a cancelled prompt does not overwrite the last thing
    /// that did go out, and after the edit has been folded in — the corrected
    /// words are the ones that were sent.
    private var lastDictation: String?

    private func commit(_ m: Message) {
        // The assembled line, and assembled from `m` — the same call
        // `deliverToTerminal` and `spawnClaude` make, so what he pastes (and
        // what the Message Log's Copy puts on the clipboard, via the outbox's
        // `line`) is byte for byte what the session received.
        let line = Self.terminalLine(m)
        if m.kind == "dictation", let text = m.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            lastDictation = line
        }
        // **Nothing is written before there is somewhere to write it to.** A
        // dictation spoken with nothing bound goes to `awaitingBind` and comes
        // back through this same method the moment a binding lands, at which
        // point the branch below is taken and the outbox line is the delivered
        // one. That ordering is the whole of what survives from the 2026-08-27
        // decision — see `holdsForBind`: the words wait, the log does not fill
        // up with them. ⌘⌃P still has them, because `lastDictation` is set
        // above: he said it, so he can paste it, bound or not.
        if m.kind == "dictation", !m.spawn, !isBound { return holdForBind(m) }
        Outbox.send(kind: m.kind, text: m.text, selection: m.selection,
                    selections: m.extraSelections.map {
                        ["at": Self.stamp($0.at), "text": $0.text]
                    },
                    paths: m.paths, screen: m.screen,
                    sources: m.sources.reduce(into: [String: String]()) { out, pair in
                        out[(pair.key as NSString).lastPathComponent] = pair.value
                    },
                    app: m.app, elements: m.elements.map { $0.json },
                    line: line)
        guard m.kind != "session_end" else { return }
        guard !m.spawn else { return spawnClaude(m) }
        deliverToTerminal(m)
    }

    // MARK: - Said now, bound later

    /// **A sentence spoken with nothing bound, and the clock it is kept under.**
    ///
    /// Victor's ask, 2026-09-11: *"tot ce pot să fac când sunt legat de un
    /// terminal să pot să fac și atunci când sunt nelegat, urmând a mă lega
    /// ulterior"* — the second half is the feature. He has a thought before he
    /// has a window for it, and until now the app's answer was to refuse the
    /// gesture outright (*Unbound is inert*), which meant the thought had to
    /// survive the trip to the terminal in his head instead.
    ///
    /// **One, not a queue.** A second dictation replaces the first, exactly as a
    /// second cancel replaces the cancelled recording that is being kept: the
    /// chip says *the* sentence being held, and a relay that had to ask which of
    /// three to deliver would be asking a question nobody has. The one it
    /// replaces is not lost to him — ⌘⌃P still pastes it.
    ///
    /// **Five minutes**, the same net `Recover Cancelled Dictation` is kept
    /// under and for the same reason: long enough to cross the room and open a
    /// terminal, short enough that a sentence from this morning cannot land in
    /// an agent he binds this afternoon for something else. A held message
    /// arriving in the wrong session is worse than one he has to say again.
    private var awaitingBind: Message?
    private var awaitingBindExpiry: DispatchWorkItem?
    private static let bindWait: TimeInterval = 5 * 60

    private func holdForBind(_ m: Message) {
        // The words have left the dictation, so the row that named where they
        // were going has nothing left to say — the flash below says the rest,
        // and after it the chip goes back to being a chip with nothing bound.
        overlay.setSpawnDestination(nil)
        awaitingBindExpiry?.cancel()
        awaitingBind = m
        let words = (m.text ?? "").split(whereSeparator: { $0.isWhitespace }).count
        Log.info("⏳ nothing bound — holding \(words) words for the next bind, \(Int(Self.bindWait / 60)) min")
        let expiry = DispatchWorkItem { [weak self] in
            guard let self = self, self.awaitingBind != nil else { return }
            self.awaitingBind = nil
            Log.info("⏳ held dictation expired — never bound")
            // Said out loud, because the alternative is a sentence he believes
            // is still going to arrive somewhere. ⌘⌃P is the way back to it.
            self.overlay.flash("⏳ held dictation expired — ⌘⌃P to paste it", duration: 4)
        }
        awaitingBindExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bindWait, execute: expiry)
        overlay.flash("⏳ held — bind a terminal to send it", duration: 3)
    }

    /// Called from `showBound`, which is the one place every route into a
    /// binding passes through — ⌘⌃B, the chords, `POST /bind`, the restart's
    /// restore and a spawned window adopting itself. All of them are a terminal
    /// appearing, which is the only thing the held sentence was waiting for.
    ///
    /// **Deliberate or not.** The 10s poll calls `showBound` with a binding
    /// already in place and passes `false`, which is what stops it stealing a
    /// spawn's destination — but it cannot produce a binding out of nothing, so
    /// it can never be the call that releases this. Any call that arrives with a
    /// target when there was none is a bind that happened.
    private func releaseAwaitingBind() {
        guard let m = awaitingBind, isBound else { return }
        awaitingBind = nil
        awaitingBindExpiry?.cancel()
        awaitingBindExpiry = nil
        Log.info("⏳ bound — sending the sentence that was waiting")
        // Through `commit` again rather than straight to `deliverToTerminal`:
        // the outbox line has still not been written, and writing it is the
        // first half of what a delivery is.
        commit(m)
        overlay.flash("🎙️ sent — the sentence you were holding", duration: 3)
    }

    /// **⌘⌃P — the last dictation, again, wherever the caret is.**
    ///
    /// Dictating is how Victor writes, and the agent is not the only place his
    /// words belong: the same sentence is often wanted in a commit message, a
    /// chat or a form a minute later. Saying it twice is worse than saying it
    /// once — the second take is never the same sentence, and it costs another
    /// model run.
    ///
    /// **Both halves are the feature.** The clipboard keeps it, so it can be
    /// pasted again anywhere; the ⌘V is so he does not have to think about the
    /// clipboard at all when the caret is already where he wants the words. The
    /// clipboard is deliberately **not** restored afterwards, unlike the blind
    /// paste in `TerminalBinding` — there the relay is borrowing it behind his
    /// back, here he asked for it.
    ///
    /// **Silent on success**, like every delivery that landed: the words appear
    /// at the caret, which is the whole of the evidence. Only the empty case has
    /// anything to say.
    ///
    /// `fromMenu` buys a beat: AppKit dismisses the menu and the app underneath
    /// gets the caret back a frame or two later, so a ⌘V posted on the click
    /// would land in whatever had focus while the menu was still up. Same
    /// hazard the menu-driven screenshot has.
    private func pasteLastDictation(fromMenu: Bool = false) {
        guard let text = lastDictation, !text.isEmpty else {
            overlay.flash("⚠️ nothing dictated yet", duration: 3)
            return
        }
        pasteText(text, after: fromMenu ? 0.25 : 0.0)
    }

    /// **Words onto the clipboard, then ⌘V at the caret.** The one delivery this
    /// app makes that is not addressed to a terminal, and the only one it has for
    /// Replace Wispr — which is why it lives here rather than inside
    /// `pasteLastDictation`, its first caller.
    ///
    /// The clipboard is deliberately **not** restored, unlike the blind paste in
    /// `TerminalBinding`: there the relay borrows it behind Victor's back, here
    /// he asked for the words, and keeping them is what makes a paste that landed
    /// somewhere unhelpful recoverable with one ⌘V of his own.
    ///
    /// **Silent on success**, like every delivery that lands: the words appear
    /// where he was looking, which is the whole of the evidence.
    private func pasteText(_ text: String, after delay: TimeInterval = 0) {
        // So ⌘⌃P can say it again — a Replace Wispr dictation is a dictation that
        // went out, and it is exactly the kind he wants twice: the same sentence
        // into a second field.
        lastDictation = text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Log.info("📋 \(text.count) chars on the clipboard — pasting at the caret")
        // The insertion the ring has been waiting for, said at the ⌘V rather than
        // at the transcript: the words are on screen when the key goes out, not
        // when the model handed them over.
        if delay == 0 {
            TerminalBinding.pressPaste()
            endSettling(reason: "pasted at the caret")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                TerminalBinding.pressPaste()
                self?.endSettling(reason: "pasted at the caret")
            }
        }
    }

    /// The countdown ran out (or he clicked the overlay away) → write it. He hit
    /// Cancel → drop it, and say so, because a message that silently disappears
    /// is indistinguishable from an overlay that has stopped working.
    ///
    /// Cancelling is cheap precisely because nothing was written: the agent polls
    /// the outbox every couple of seconds, so a line already in the file may
    /// already be a tool call in flight.
    /// `edited` is the transcript as it stands on the panel — the same words
    /// unless he clicked into them and fixed something, which is the whole reason
    /// it travels back here rather than the panel being trusted to have shown
    /// what was already in `held`.
    private func releaseHeld(send: Bool, edited: String? = nil) {
        hotkeys.promptHeld = false
        guard var m = held else { return }
        held = nil
        if let edited = edited, edited != m.text {
            Log.info("✎ transcript edited before sending — \(m.text?.count ?? 0) → \(edited.count) chars")
            m.text = edited
        }
        guard send else {
            Log.info("✕ cancelled — \(m.text?.count ?? 0) chars never left the overlay")
            // The picked elements go back in the queue. Cancel means the sentence
            // was wrong, not that he pointed at the wrong things — and re-taking a
            // pick means finding the element in the page again, which is the
            // expensive half of the gesture. (Shots are not restored: he can take
            // another one blind, and the screen has moved on anyway.)
            if !m.elements.isEmpty {
                stateLock.lock()
                pendingPicks = m.elements + pendingPicks
                pruneStalePicks()
                stateLock.unlock()
                publishPicks()
            }
            if m.spawn { clearSpawn() }
            overlay.flash("✕ cancelled", duration: 2.0)
            return
        }
        commit(m)
        // **The send flight** (Victor, 2026-09-04): the panel the prompt was
        // just read on flies to the terminal the words were sent to, growing
        // into that window's frame — *"once the timer expires or it sends to
        // the terminal I would love it to pan and increase the size until it
        // reaches that terminal"*. The receipt for *it went there*, said in
        // the bind flight's own language, and played whether the panel had
        // buttons (the countdown, ⏎, a click) or not (autosend). A spawn has
        // its own flight already; a cancelled prompt has nowhere to fly.
        if !m.spawn, let farewell = overlay.promptFarewell {
            overlay.promptFarewell = nil
            sendFlight(from: farewell)
        } else if !m.spawn {
            // Held with nothing to fly — a panel left on screen is worse than a
            // missing receipt.
            overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
        }
    }

    /// Fly the just-sent panel to the bound terminal's window, growing until it
    /// fills it. Silent no-op when there is no honest frame to aim at — IDE and
    /// keystroke targets have no window this app can name, and a flight toward
    /// a guessed rectangle is worse than none.
    ///
    /// **An outline, never a picture** — Victor, 2026-09-07: *"când dialogul se
    /// duce spre terminal, vreau să se ducă spre un border doar … nu mai știu
    /// mental ce era în acel terminal, doar să înțeleg că se duce într-un
    /// terminal, undeva"*. It carried the panel's own drawing, which is the
    /// bind flight's argument run in the wrong direction: a bind ends at the
    /// cursor, on a shape the size of the chip, so pixels are what identify the
    /// window it came from; this ends **on** a window, at full size, over
    /// whatever he is reading — and a picture there covers the destination it is
    /// pointing at. Same call the spawn flight makes, and for the same reason.
    private func sendFlight(from frame: CGRect) {
        // **Every exit releases the panel**, because `resolvePrompt` now holds it
        // for this method on every send — see `RelayWindow.resolvePrompt`. A
        // target with no window this app can honestly name has no flight, and a
        // dialog waiting for one that will never come is a dialog that never
        // closes.
        let giveUp = { [weak self] in
            guard let self = self else { return }
            self.overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
        }
        guard let target = terminal.target else { return giveUp() }
        let tty: String?
        switch target.handle {
        case .terminalApp(let t): tty = t
        case .tmux(_, let t): tty = t
        case .ide, .keystroke: tty = nil
        }
        guard let tty = tty else { return giveUp() }
        // AppleScript, so off the main thread — the same discipline
        // `deliverToTerminal` keeps.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let destination = TerminalBinding.terminalWindowFrame(tty: tty) else {
                DispatchQueue.main.async { giveUp() }
                return
            }
            DispatchQueue.main.async {
                BindFlight.fly(from: frame, to: { destination },
                               seconds: Self.sendFlightSeconds,
                               outlined: true, tail: Self.spawnFlightRest)
                // **The outline leaves, then the dialog fades** — the same beat
                // the spawn flight keeps, and for its reason: at t=0 the outline
                // lies exactly on the panel, so a panel already dissolving under
                // it reads as both fading at once rather than as one leaving the
                // other. See `spawnPanelFadeDelay`.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.spawnPanelFadeDelay) { [weak self] in
                    self?.overlay.releaseSpawnPanel(fadeOver: Self.spawnPanelFade)
                }
            }
        }
    }
}
