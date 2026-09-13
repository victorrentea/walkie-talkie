import AppKit
import Foundation

/// **Wispr Flow, driven and read as if it were this app's own microphone.**
///
/// Victor's decision, 2026-09-12: *Wispr Flow is the dictation source for
/// everything* — the caret, a spawned session, and the bound terminal that used
/// to be the local model's alone. Wispr is better at his accent, it is already
/// running, and it is what his hand reaches for; the relay's job is to stop
/// being a second recogniser and start being the thing that decides **where the
/// words go**.
///
/// Three problems stand between that decision and a `DictationSource`, and this
/// file is the three answers.
///
/// ## 1 · Starting it — a chord, not an API
///
/// Wispr has no API. It has shortcuts, and it writes them into its own
/// `~/Library/Application Support/Wispr Flow/config.json` under
/// `prefs.user.shortcuts`, keyed by keycodes joined with `+`. The relay posts
/// the hands-free one (`49+59+63` = fn ⌃ Space) through
/// `HotkeyTap.postWisprHandsFree` and the dismiss one (`53+59` = ⌃Escape)
/// through `postWisprCancel`. Both were already here and both are correct in
/// ways that took a day each to find — the Options+ settle, the wait for
/// Victor's own modifiers to come off the wire, the `hidSystemState` source,
/// the stamp that keeps this app's own tap from reading them as gestures.
///
/// **The chord is a toggle and its state is never tracked from here.** Wispr
/// misses one, or Victor ends a dictation from Wispr's own window, and a
/// counter in this process is wrong for the rest of the day. `WisprWatch`'s
/// CoreAudio edge is the only truth about whether the microphone is open.
///
/// ## 2 · Hearing it — a second microphone for the ring
///
/// `WisprWatch` answers one boolean. A beacon that breathes on his voice needs
/// a level, so the relay opens the input *alongside* Wispr and meters it. Two
/// clients on one input device is ordinary on macOS; Wispr's audio is not
/// touched.
///
/// **And since 2026-09-12 that session writes a WAV**, because it is the only
/// recording of a Wispr dictation that will ever exist on this disk. Retiring
/// the local model would otherwise have killed `~/.walkie-talkie/voice-corpus/`
/// — *"the one thing here that cannot be regenerated"* — on the day the last
/// local dictation was spoken. The label beside it is Wispr's own transcript.
///
/// ## 3 · Reading it — the delivery, intercepted
///
/// Wispr's entire output interface is *it types the sentence into whatever has
/// focus*. There is no clipboard-only mode (the whole 45 KB config was read on
/// 2026-09-12: `polishAutoPaste`, `instructPasteOnEmptyContext`,
/// `focusModeBlockedApps` and three notification strings, and nothing that
/// turns the paste off), and **its database is not an option** — the 2026-08-29
/// rule stands and Victor restated it when he asked for this.
///
/// What is left is the delivery itself. Wispr writes the transcript to the
/// pasteboard and presses ⌘V, and this app's event tap is head-inserted on the
/// session tap, so it sees that ⌘V *before the front app does*. Under
/// `wrapWispr` (default on) the relay **swallows it** and inserts the words
/// itself — into the bound agent through the held prompt, or at the caret
/// through `pasteText`, which is the same paste Wispr was about to make. With
/// the flag off nothing is taken: Wispr pastes as it always did and the relay
/// only watches, which is what every build before today did.
///
/// The swallow is narrow on purpose: the key has to be **V with ⌘**, from a
/// **process whose name says Wispr**, inside the window between the microphone
/// closing and the deadline. Victor's own ⌘V carries pid 0 and can never match.
final class WisprFlowSource: DictationSource {

    let name = "Wispr Flow"

    /// **The whole of the wrap, in one flag.** On: the relay takes Wispr's
    /// paste and delivers the words itself, so Wispr looks exactly like the
    /// local recogniser to everything downstream. Off: Wispr inserts its own
    /// text wherever the focus is and the relay only draws the ring — the
    /// behaviour of every build before 2026-09-12, kept because it is the one
    /// thing to fall back to if a Wispr update changes how it delivers.
    var wrapWispr = true {
        didSet { Log.info("wispr wrap \(wrapWispr ? "on — the relay takes the paste" : "off — Wispr pastes where the focus is")") }
    }

    // MARK: - Events

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    // MARK: - State

    private(set) var isRecording = false

    /// **The measured state machine** — see `WisprState`. Everything below feeds
    /// it and nothing below asks it a question it cannot answer from its own
    /// three inputs; `phase` is the one thing the rest of the app reads, through
    /// `DictationSource`.
    let state = WisprState()
    var phase: DictationPhase { state.phase }

    /// **The 100 ms pull that replaced a push nobody could trust.**
    ///
    /// `WisprWatch`'s notification is kept (it can be earlier than a tick, and
    /// the lag between the two is the number `WisprState.lags` exists to take),
    /// but it is no longer the only witness: measured 2026-09-13 it is 0–6 s late
    /// and, with Wispr pinned to the Loopback device `🎓 TO Wispr`, it produced
    /// **no edge at all** in five successful runs. Running only between the chord
    /// and the words (`WisprState.wantsPoll`), because a permanent CoreAudio poll
    /// is the thing this app spent 2026-09-11 arguing itself out of.
    private var inputPoll: Timer?
    private var lastPollSaw = false
    private static let pollTick: TimeInterval = 0.1

    /// Wispr Flow is running at all. Asked of the process list rather than
    /// remembered: it is quit and relaunched like any other app.
    var isReady: Bool { NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier?.hasPrefix(Self.bundlePrefix) == true } }

    let meter = MicRecorder()

    private let watch = WisprWatch()
    private let hotkeys: HotkeyTap
    /// Where the meter is opened and closed, off the main thread — see
    /// `AppDelegate.wisprMeterQueue`, whose whole argument moved here with it:
    /// `MicRecorder.start(to:)` is a synchronous device open and it was being
    /// run on the edge, in front of the ring.
    private let meterQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr-meter")
    /// Touched only on `meterQueue`, so the stop queued at the closing edge can
    /// never be overtaken by the read that wants its result.
    private var recording: (url: URL, duration: TimeInterval)?

    /// A gesture was seen and no microphone has confirmed it yet.
    private var speculative = false
    private var speculativeDrop: DispatchWorkItem?
    /// When the gesture was seen, so the confirming edge can say how long the
    /// guess had to wait — the number that settled `speculativeGrace`.
    private var gestureAt: CFAbsoluteTime = 0
    /// **How long a guess is allowed to stand unconfirmed — 12 s, and the number
    /// is measured (2026-09-12).**
    ///
    /// It was 1.5 s, fitted to the five `mic edge confirms the ring N ms after
    /// the hotkey` lines in `relay.log`: 324, 478, 528, 634, 674 ms. Every one of
    /// those is a *warm* Wispr. Victor's dictations on the evening of 09-12
    /// measured **5.0 s and 6.0 s** from the chord to `wispr flow opened the
    /// microphone`, and the whole of what he saw was the bug: the ring came up
    /// on his keystroke, **shrank away** two seconds later when the grace ran
    /// out, and came back four seconds after that with the screenshot bubble and
    /// the chip. *"the lightning starts fast, but only later the yellow bubble
    /// appears, and there is a pause in which the ring disappears"*.
    ///
    /// So: the worst measured open × 2, never under three seconds. A retraction
    /// is for a chord Wispr **ignored** — it was not running, the shortcut had
    /// been changed — and that is rare enough to be worth twelve seconds of
    /// patience. A beacon that flickers is worse than one that is briefly wrong,
    /// which is the opposite of the trade the 1.5 s was making.
    private static let speculativeGrace: TimeInterval = 12

    /// The microphone closed and the words have not arrived.
    ///
    /// `private(set)` since 2026-09-13 so `GET /test/state` can say whether the
    /// swallow window is armed — the 2.5 s Word dictation failed precisely
    /// because it never was, and nothing outside this file could see that.
    private(set) var capturing = false
    /// When the swallow window was armed — the **start** chord since 2026-09-13,
    /// not the microphone's close.
    private var armedAt: CFAbsoluteTime = 0
    private var captureFrom: CFAbsoluteTime = 0
    private var captureDeadline: DispatchWorkItem?
    private var clipboardWatch: Timer?
    private var clipboardAt = 0
    /// **What was on the pasteboard before the dictation, and it is the fix for
    /// three sentences that were never spoken** (2026-09-13).
    ///
    /// Wispr writes the transcript to the pasteboard, presses ⌘V, and **puts the
    /// previous contents back**. While the capture was armed at the microphone's
    /// close — 0–6 s late — the baseline `changeCount` was taken *after* Wispr's
    /// own write, so the only move the relay ever saw was the restore, and it
    /// delivered the restored clipboard as the transcript. Measured in the
    /// corpus: three runs on the evening of 09-13 filed 166 characters of a Word
    /// rental contract (`Semnături, PROPRIETAR CHIRIAȘ …`) as Victor's dictation,
    /// against audio of him saying *"Commit and push the fix"*.
    ///
    /// Arming at the start chord fixes the ordering; this is the belt beside it,
    /// and it is worth keeping for the day Wispr changes the order again: a
    /// pasteboard whose contents are **what they were before he started talking**
    /// cannot be this sentence, whatever the change count says.
    private var clipboardBaseline: String?
    /// The string as it stood the instant the change was first seen — read then
    /// rather than 250 ms later, because the restore lands inside that gap.
    private var clipboardMoved: String?
    /// Whether the fallback chord has been posted for this sentence, so a
    /// pasteboard that never moves cannot make the relay type ⌘⌃C twice.
    private var askedForCopy = false
    /// **The longest the relay waits for words that may never come — 30 s, and
    /// it was 6 and that cost a sentence (2026-09-12).**
    ///
    /// Wispr's round trip was measured at avg 2.6 s over 71 dictations, min
    /// 0.27, max **22.8** — the tail is a cold network and a long clip. Six
    /// seconds was fitted to the average and it let go of an 81-second dictation
    /// on the evening it shipped: the ⌘V arrived after the window had closed, so
    /// the relay never saw it and Wispr pasted into whatever was in front.
    /// Measured the same evening: **5.9 s** on one sentence, a second one past
    /// six.
    ///
    /// This is the wrap's own window and it is deliberately far longer than the
    /// ring's: the ring is a thing Victor looks at and 30 s of it would be a lie,
    /// where a capture window is a thing nobody sees and costs one armed flag.
    private static let captureTimeout: TimeInterval = 30
    /// How long the fallback chord is given, once it has been posted.
    private static let copyGrace: TimeInterval = 3

    /// **The `copy_last_text` fallback is off by default, and it is off for a
    /// reason that showed up the hour it was written (2026-09-12).**
    ///
    /// ⌘⌃C asks Wispr for *the last text it produced* — not *the text from the
    /// sentence that just ended*. If this sentence produced nothing, the chord
    /// hands back the **previous** one, and the relay would deliver a paragraph
    /// Victor spoke five minutes ago into an agent as though he had just said it.
    /// A dictation that goes missing is a sentence he repeats; a dictation that
    /// silently becomes an older one is a sentence he cannot trust.
    ///
    /// Measured on the first run: the chord went out and `NSPasteboard
    /// .changeCount` never moved, so it does not even buy the case it was
    /// written for. `WT_WISPR_COPY_FALLBACK=1` turns it back on for whoever
    /// wants to work on it; the probe (2026-09-12) showed the ⌘V path is the
    /// real one and this was only ever the insurance.
    private static let copyFallbackEnabled =
        ProcessInfo.processInfo.environment["WT_WISPR_COPY_FALLBACK"] == "1"

    private var cancelling = false

    /// **Wispr's own row for this dictation** (`WisprHistory`, 2026-09-12) —
    /// the completion signal for a delivery the tap cannot see. Taken at the
    /// microphone's close as the newest row whose `startedAt` is this
    /// dictation's; polled every `historyTick` while capturing.
    /// `private(set)` for `GET /test/state`: *is Wispr's own row being polled,
    /// and which one* is the difference between a settle that will end on its
    /// own and one that will sit out `settleTimeout`.
    private(set) var historyRow: Int64?
    /// The newest rowid at the moment the capture was armed, so a row that was
    /// already there when he started talking can never be read as this
    /// dictation's answer — the failure that would otherwise end every settle on
    /// the first tick now that the poll starts at the **gesture** rather than at
    /// the microphone's close.
    private var priorRow: Int64?
    /// …unless that row was still open, in which case it *is* this dictation's:
    /// Wispr creates the row at the gesture and the relay can be reading a
    /// millisecond after it.
    private var priorRowWasOpen = false
    private var historyPoll: Timer?
    /// When the row said `formatted`, so the ⌘V that normally follows gets
    /// `pasteGrace` to arrive before the text is taken from the row instead.
    private var historyFormattedAt: CFAbsoluteTime = 0
    private static let historyTick: TimeInterval = 0.15
    private static let pasteGrace: TimeInterval = 1.0

    /// **The row is the delivery, not the fallback** — off by default, and the
    /// shape the wrap is heading for (Victor, 2026-09-13, evening).
    ///
    /// The wrap as built is *swallow Wispr's ⌘V and insert the words ourselves*,
    /// and it failed twice on 09-13 for the same reason both times: it depends on
    /// a keystroke another process may or may not post, inside a window the relay
    /// may or may not have armed. The candidate that replaces it does not depend
    /// on a keystroke at all — **take Wispr's Accessibility grant away**, so it
    /// can neither write through AX nor post a synthetic ⌘V, and read the words
    /// out of its `History` row. The sink was the other candidate and Victor
    /// ruled it out the same evening: holding the key window through every
    /// dictation is not something to do to a man who may be typing.
    ///
    /// With this on: `formatted` delivers **immediately** (there is no ⌘V to wait
    /// `pasteGrace` for), the text comes from `pastedText` or `formattedText`
    /// (`Entry.text` — a Wispr that inserted nothing fills the second), and the
    /// delivery is always `.route`, because nobody but the relay is going to put
    /// the sentence anywhere. The ⌘V swallow stays armed as the safety net for
    /// the day the grant comes back.
    ///
    /// `WT_WISPR_HISTORY_ROUTE=1`, or `POST /test/wispr {"historyRoute": true}`.
    var historyIsTheRoute = ProcessInfo.processInfo.environment["WT_WISPR_HISTORY_ROUTE"] == "1" {
        didSet {
            Log.info("wispr history route \(historyIsTheRoute ? "on — the row is the delivery, no ⌘V is waited for" : "off — the ⌘V is the delivery and the row is the backstop")")
        }
    }
    /// Wall clock of whichever came first, the gesture or the microphone — the
    /// row's `startedAt` has to be at or after this to be this dictation's.
    private var openedAt: TimeInterval = 0

    private static let bundlePrefix = "com.electron.wispr-flow"

    // MARK: - Life

    init(hotkeys: HotkeyTap) {
        self.hotkeys = hotkeys
        // The machine decides when the poll is worth running; nothing else may.
        state.onTransition = { [weak self] _, _, _ in self?.syncInputPoll() }
        watch.onChange = { [weak self] on in self?.edge(on, measured: true) }
        hotkeys.onWisprMaybeStarting = { [weak self] why, confident in
            DispatchQueue.main.async { self?.gestureSeen(why, confident: confident) }
        }
        hotkeys.onWisprMaybeCancelling = { [weak self] in
            DispatchQueue.main.async { self?.dismissSeen() }
        }
        hotkeys.onInjectedPaste = { [weak self] from in
            DispatchQueue.main.async { self?.injected(from: from) }
        }
    }

    func prepare() {
        watch.start()
    }

    // MARK: - DictationSource

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard isReady else { return "Wispr Flow is not running" }
        HotkeyTap.postWisprHandsFree()
        // **The relay asked for this one**, so there is nothing to guess about:
        // the dictation opens now and the microphone edge confirms it. The tap
        // will *also* see the chord this posts and call `gestureSeen`, which is
        // a no-op once `speculative` is set.
        gestureSeen("the relay asked for a dictation", confident: true)
        return nil
    }

    /// **The same chord again** — Wispr's hands-free shortcut is a toggle, and
    /// the relay has nothing else with which to say *stop*. The closing edge is
    /// still `WisprWatch`'s, never this call: a chord Wispr ignores must not
    /// end a dictation that is still running.
    /// **The same chord again, and since 2026-09-13 the relay's own stop is what
    /// closes the listening phase** — the 🔼 click, ⌘⌃D, the second 🔼→, the end
    /// of a `/test` run.
    ///
    /// It used to wait for `WisprWatch`'s closing edge, on the argument that a
    /// chord Wispr ignores must not end a dictation that is still running. The
    /// argument was right and the premise was false: that edge is 0–6 s late and
    /// on the Loopback device it never comes at all, so what the rule actually
    /// bought was a ring standing over a sentence that had already been pasted
    /// into Word, a swallow window armed too late to swallow anything, and a
    /// `speculativeGrace` announcing *Wispr ignored the chord* about a dictation
    /// that had been delivered twelve seconds earlier.
    ///
    /// The relay knows what it asked for. The edge now confirms and logs.
    func stop() {
        guard isRecording || speculative else { return }
        HotkeyTap.postWisprHandsFree()
        closeListening("the relay's own stop gesture")
    }

    func cancel() {
        // **The ✕ during the wait counts too.** Between the microphone closing
        // and the words arriving there are seconds in which the sentence is
        // still this app's to throw away — and it is exactly the stretch in
        // which Victor realises he does not want it.
        if !isRecording, !speculative, capturing {
            Log.info("🗑️ Wispr Flow's transcript abandoned before it arrived")
            endCapture(quiet: true)
            didEnd?(.cancelled(audio: nil, duration: 0))
            return
        }
        guard isRecording || speculative else { return }
        cancelling = true
        Log.info("🗑️ Wispr Flow dictation cancelled — posting ⌃Escape")
        HotkeyTap.postWisprCancel()
        // **The cancel closes it here too.** Same change as `stop()`, same
        // reason: waiting for a CoreAudio edge that may never come left the ring
        // up over a dictation Victor had already thrown away.
        closeListening("the relay's own cancel")
        state.reset("cancelled")
    }

    // MARK: - The test routes

    /// `POST /test/wispr` — the CoreAudio edge with no CoreAudio behind it.
    /// `measured: false` keeps the latency line honest: this enters below the
    /// watcher and would otherwise print the age of the last real dictation.
    func simulateEdge(_ on: Bool) {
        guard isRecording != on || (on && speculative) else { return }
        Log.info("wispr flow \(on ? "opened" : "closed") the microphone (simulated)")
        edge(on, measured: false)
    }

    /// `POST /test/wispr-handsfree` — the **real** chord on the wire, which is
    /// the one input the end-to-end harness is allowed to cause. Deliberately
    /// not `start()`: the harness has to be able to post the chord a second time
    /// to stop the dictation, and `start()` refuses while one is running.
    /// **And it drives the machine**, because since 2026-09-13 this app's own
    /// posts are stamped out of its tap (`backButtonStamp` on the hands-free
    /// branch of `HotkeyTap`) — otherwise every chord this route posts would come
    /// back through the tap as though Victor had pressed it. The toggle's two
    /// presses are the dictation's two ends, so the second call stops.
    func postStartChord() {
        HotkeyTap.postWisprHandsFree()
        if isRecording || speculative {
            closeListening("POST /test/wispr-handsfree — the toggle's second press")
        } else {
            gestureSeen("POST /test/wispr-handsfree", confident: true)
        }
    }

    /// `POST /test/wispr {"hotkey": true}` — the speculative ring, one step
    /// earlier than the microphone.
    func simulateHotkey() { gestureSeen("POST /test/wispr {hotkey}", confident: true) }

    // MARK: - Edges

    /// **Wispr's own start gesture, seen on the wire — the dictation starts
    /// here, not when CoreAudio catches up.**
    ///
    /// Measured on Victor's desk 2026-09-12: 5–6 seconds between the chord and
    /// `wispr flow opened the microphone` on a cold Wispr, against 324–674 ms
    /// warm. For those seconds the relay used to have a ring and nothing else —
    /// no chip, no context shot, no music pause — and then everything arrived at
    /// once, behind a ring that had already shrunk away and come back. What he
    /// sees now is one opening: *"the lightning starts fast, but only later the
    /// yellow bubble appears"* is the whole bug report and this is the whole fix.
    ///
    /// - Parameter confident: whether the gesture is unambiguous.
    ///   **fn ⌃ Space is** — it is a chord nothing else on this Mac claims, and
    ///   `postWisprHandsFree` is this app posting exactly it. **Push-to-talk is
    ///   not**: it is two modifiers held (right ⌘ + right ⌥) and nothing else, so
    ///   it fires on a chord Victor may have pressed for something entirely
    ///   different. A false `didBegin` costs a screenshot and a ⌘C probe posted
    ///   into whatever he is working in, which is far too much to spend on a
    ///   guess — so an unconfident gesture raises the beacon and nothing else,
    ///   and its microphone edge does the opening a moment later.
    private func gestureSeen(_ why: String, confident: Bool) {
        // **The chord is a toggle and the second press is the stop** (2026-09-13).
        // Only for a confident gesture: `fn ⌃ Space` is unambiguous and this
        // app's own posts no longer come back through the tap, so a hands-free
        // chord seen here while a dictation is open is Victor ending it from his
        // keyboard — which the relay used to learn only from a CoreAudio edge
        // that may be six seconds late or absent.
        if confident, isRecording || speculative {
            closeListening("Victor's own \(why)")
            return
        }
        guard !isRecording, !speculative else { return }
        speculative = true
        gestureAt = CFAbsoluteTimeGetCurrent()
        openedAt = Date().timeIntervalSince1970
        state.startChord(why)
        // **A capture still standing whose row is not terminal is a sentence
        // still in flight**, and this new one does not get to disarm it — that
        // is precisely what happened on 2026-09-13 when a phantom second
        // dictation called `endCapture(quiet:)` and Wispr's ⌘V for the *first*
        // sentence went into whatever Terminal was in front.
        retireCaptureIfSettled()
        if confident {
            isRecording = true
            Log.info("⚡ \(why) — opening the dictation on the gesture")
            didBegin?()
        } else {
            didMaybeBegin?(why)
        }
        // **A guess that is never taken back is a lie.** A chord Wispr ignored
        // — it was not running, the shortcut had been changed, the key went to
        // something else — must not leave a beacon claiming a microphone.
        // **It may only fire when Wispr never created a row** (2026-09-13).
        //
        // The retraction is for a chord Wispr *ignored* — it was not running, the
        // shortcut had been changed — and until today the only evidence it had
        // was *no microphone was seen*, which is exactly the thing this app has
        // stopped being able to see. Twice that day it announced *Wispr ignored
        // the chord* about sentences Wispr had transcribed and pasted. Wispr
        // creates the `History` row at the gesture, so the row's absence is the
        // honest test, and the two outcomes get two different sentences because
        // they call for two different fixes.
        let drop = DispatchWorkItem { [weak self] in
            guard let self, self.speculative else { return }
            if self.historyRow != nil {
                self.confirmSpeculative(by: "Wispr's own row (the relay saw no microphone)")
                return
            }
            self.speculative = false
            self.isRecording = false
            self.stopMeter(keep: false)
            self.state.timedOut("no row and no microphone within \(Int(Self.speculativeGrace)) s")
            let why = "Wispr never created a row within \(Int(Self.speculativeGrace)) s of the chord — it ignored it"
            RingDown.note(why)
            Log.info("⚡ ring down: \(why)")
            self.endCapture(quiet: true)
            self.didEnd?(.silent(""))
        }
        speculativeDrop?.cancel()
        speculativeDrop = drop
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.speculativeGrace, execute: drop)
        // **The swallow window and the row poll are armed here, at the start
        // chord** (2026-09-13). They used to be armed at the microphone's close,
        // which is the single decision both failures of that day came out of: a
        // 2.5 s dictation produced no close edge at all, so nothing was ever
        // armed and Wispr pasted straight into Word. Armed at the gesture, a
        // missing edge costs nothing — the window is simply open for the whole
        // sentence, which is one flag.
        beginCapture()
        // The meter comes up with the guess, so the ring breathes from the first
        // syllable rather than from whenever CoreAudio gets round to the edge.
        // `start(to:)` is a no-op on a session already open, so the confirming
        // edge costs nothing when it arrives.
        startMeter()
        syncInputPoll()
    }

    /// **A guess confirmed by something other than the ring's own patience.**
    ///
    /// Three things can confirm it and they are three different facts: the 100 ms
    /// poll and the CoreAudio notification both say *a microphone is open*, and
    /// Wispr's own row says *Wispr took the chord*, which is the one that still
    /// works when nothing can hear the microphone at all.
    private func confirmSpeculative(by what: String) {
        guard speculative else { return }
        speculativeDrop?.cancel()
        speculativeDrop = nil
        speculative = false
        Log.info(String(format: "⚡ %@ confirms the ring %.0f ms after the gesture",
                        what, (CFAbsoluteTimeGetCurrent() - gestureAt) * 1000))
        isRecording = true
        startMeter()
    }

    /// **The microphone is shut as far as this app is concerned** — by the
    /// relay's own stop gesture, by the poll, by the notification, or by Victor's
    /// own chord. Whoever said so, this is the one place the sentence stops being
    /// heard and starts being waited for.
    private func closeListening(_ why: String) {
        guard isRecording || speculative else { return }
        // **The machine closes here too, and only here.** It used to be told
        // separately at each call site, and the one site that forgot was the
        // CoreAudio edge — so a dictation the relay had settled sat in `warming`
        // for ever as far as the phase was concerned, which is precisely the
        // kind of disagreement between two records of the same fact this file
        // exists to remove.
        state.stopChord(why)
        isRecording = false
        speculativeDrop?.cancel()
        speculativeDrop = nil
        speculative = false
        stopMeter(keep: !cancelling)
        captureFrom = CFAbsoluteTimeGetCurrent()
        Log.info(String(format: "🎙️ the microphone is closed — %@ (%.0f ms of speech)",
                        why, (captureFrom - gestureAt) * 1000))
        didStopListening?()
        if cancelling {
            cancelling = false
            endCapture(quiet: true)
            didEnd?(.cancelled(audio: nil, duration: 0))
            return
        }
        // The capture was armed at the gesture; what starts here is only its
        // deadline, because *how long may the words take* is counted from the
        // last word and not from the first.
        armCaptureDeadline()
        syncInputPoll()
    }

    // MARK: - The 100 ms poll

    /// On between the chord and the words, off the rest of the day.
    private func syncInputPoll() {
        let wanted = state.wantsPoll
        if wanted, inputPoll == nil {
            lastPollSaw = isRecording
            let t = Timer(timeInterval: Self.pollTick, repeats: true) { [weak self] _ in self?.pollInput() }
            inputPoll = t
            RunLoop.main.add(t, forMode: .common)
        } else if !wanted, inputPoll != nil {
            inputPoll?.invalidate()
            inputPoll = nil
        }
    }

    private func pollInput() {
        let on = watch.sampleIsRunningInput()
        guard on != lastPollSaw else { return }
        lastPollSaw = on
        state.poll(on)
        if on {
            confirmSpeculative(by: "the 100 ms poll")
        } else if isRecording {
            // Victor ended the dictation from Wispr's own window, or Wispr ended
            // it itself. At most one tick late, against a notification measured
            // at up to six seconds.
            closeListening("the 100 ms poll saw the microphone close")
        }
    }

    /// **Victor pressed Wispr's own dismiss (⌃Escape).** The sentence is over
    /// on Wispr's side and nothing will be pasted, so nothing here may go on
    /// waiting for it: a capture standing is closed and the ring goes down now,
    /// not at `settleTimeout`. While the microphone is still open the closing
    /// edge is still `WisprWatch`'s — `cancelling` makes it report a cancel
    /// rather than arm a capture, exactly as `cancel()` does after posting the
    /// same key.
    private func dismissSeen() {
        // A guess the microphone never confirmed has no closing edge to wait
        // for: it is over here and now. Should Wispr open the microphone after
        // all, that edge opens a fresh dictation, which is what it would be.
        if isRecording || speculative {
            Log.info("🗑️ ⌃Escape — Wispr Flow's dismiss, pressed by hand")
            cancelling = true
            closeListening("Victor's own ⌃Escape")
            state.reset("dismissed by hand")
            return
        }
        guard capturing else { return }
        Log.info("🗑️ ⌃Escape — Wispr Flow's dismiss, pressed by hand while the words were in flight")
        endCapture(quiet: true)
        didEnd?(.cancelled(audio: nil, duration: 0))
    }

    /// **The CoreAudio notification — a second witness now, not the witness.**
    ///
    /// It still opens a dictation nothing else knew about (Victor's own chord, on
    /// a build whose tap missed it), because a microphone that is open is a
    /// dictation whatever asked for it. What it no longer does is *end* one on
    /// its own authority while the relay's own stop, the 100 ms poll and Wispr's
    /// row all have something to say first.
    private func edge(_ on: Bool, measured: Bool) {
        state.notify(on)
        if on {
            // **The edge confirms; it never re-opens.** A guess that is standing
            // is *this* dictation — the ring, the chip and the context shot are
            // already up — and firing `didBegin` again would take them all down
            // and put them back, which is precisely the flicker Victor reported
            // on 2026-09-12.
            if speculative {
                confirmSpeculative(by: "the mic edge")
                return
            }
            guard !isRecording else { return }
            isRecording = true
            openedAt = Date().timeIntervalSince1970
            // No chord was seen for this one — Victor's own, on a build whose
            // tap missed it — so the edge is the only clock there is.
            if gestureAt == 0 || state.chordAt == 0 { gestureAt = CFAbsoluteTimeGetCurrent() }
            beginCapture()
            startMeter()
            didBegin?()
            syncInputPoll()
            if measured, watch.edgeAt > 0 {
                Log.info(String(format: "⚡ ring up %.0f ms after Wispr Flow opened the microphone",
                                (CFAbsoluteTimeGetCurrent() - watch.edgeAt) * 1000))
            }
        } else {
            guard isRecording else {
                // The ordinary case since the relay closes on its own gesture:
                // the edge arrives seconds later with nothing left to say. Said
                // anyway, because *how much later* is the number that made all
                // of this necessary.
                if captureFrom > 0 {
                    Log.info(String(format: "⚡ the mic edge closed %.0f ms after the relay had already stopped",
                                    (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
                }
                return
            }
            closeListening("the CoreAudio edge")
        }
    }

    // MARK: - The meter, which is also the corpus's recording

    private func startMeter() {
        let wav = Outbox.shotsDir.appendingPathComponent("wispr-\(Int(Date().timeIntervalSince1970)).wav")
        meterQueue.async { [weak self] in
            guard let self else { return }
            guard !self.meter.isRecording else { return }
            if let why = self.meter.start(to: wav) {
                // The ring is already up — at rest, not breathing. Said out loud
                // because a ring that does not move looks exactly like a broken
                // swell and is not one.
                Log.error("wispr halo: no level — \(why)")
                return
            }
            self.recording = nil
        }
    }

    /// - Parameter keep: whether the WAV is wanted. A cancelled sentence's audio
    ///   is Victor's voice with nothing to label it, and the corpus files pairs.
    private func stopMeter(keep: Bool) {
        meterQueue.async { [weak self] in
            guard let self else { return }
            let taken = self.meter.stop()
            if keep { self.recording = taken }
            else if let taken { try? FileManager.default.removeItem(at: taken.url) }
        }
    }

    // MARK: - Catching the transcript

    /// **Armed at the start chord since 2026-09-13**, not at the microphone's
    /// close — see `gestureSeen`. What is armed here is the whole of the wrap's
    /// listening apparatus: the ⌘V swallow, the pasteboard watch and Wispr's own
    /// row. What is *not* armed here is the deadline, because how long the words
    /// may take is counted from the last word (`armCaptureDeadline`).
    private func beginCapture() {
        guard !capturing else { return }
        capturing = true
        armedAt = CFAbsoluteTimeGetCurrent()
        captureFrom = armedAt
        askedForCopy = false
        clipboardAt = NSPasteboard.general.changeCount
        clipboardBaseline = NSPasteboard.general.string(forType: .string)
        clipboardMoved = nil
        // **Armed whether or not the relay is going to take it.** The probe half
        // — which process posted what key, how long after the microphone shut —
        // is the only record of how Wispr delivers, and it is worth the same two
        // log lines in either mode. Only `swallow` differs.
        hotkeys.armInjectionCapture(swallow: wrapWispr)

        // The pasteboard is the other half of the answer, and the only half in
        // the cases where the ⌘V never arrives: an Accessibility insertion, a
        // focus Wispr refuses to paste into, a keystroke that went somewhere
        // else. Polled at 20 Hz and **only while capturing** — a permanent
        // pasteboard poll is a different and much worse thing than a six-second
        // one.
        clipboardWatch?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.capturing else { return }
            guard NSPasteboard.general.changeCount != self.clipboardAt else { return }
            self.clipboardWatch?.invalidate()
            self.clipboardWatch = nil
            // **Read the string now, not in 250 ms.** Wispr writes the
            // transcript, presses ⌘V and puts the previous clipboard back, and
            // the restore lands inside exactly that gap — three sentences on
            // 2026-09-13 were delivered as the clipboard Wispr had just restored.
            self.clipboardMoved = NSPasteboard.general.string(forType: .string)
            // Give the ⌘V a beat to arrive behind the write: Wispr sets the
            // pasteboard *then* presses the key, so a poll that fires in between
            // must not conclude the key is never coming.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.capturing else { return }
                self.deliver(reason: "the pasteboard moved but no ⌘V was seen",
                             via: "pasteboard", delivery: .alreadyInserted)
            }
        }
        clipboardWatch = t
        RunLoop.main.add(t, forMode: .common)

        // **And Wispr's own row**, the third witness and the only one that works
        // when nothing can hear the microphone.
        //
        // It used to be read **once**, at the microphone's close, and kept only
        // if its `startedAt` was this dictation's. Polled from the gesture
        // instead, because the row is *created* at the gesture: its appearance is
        // itself the confirmation that Wispr took the chord, which is the fact
        // `speculativeGrace` needs and the CoreAudio edge stopped being able to
        // give. What has to be guarded against is the opposite mistake — reading
        // the *previous* dictation's finished row as this one's answer and ending
        // every settle on the first tick — so the row that was on top when this
        // was armed is remembered and refused, unless it was still open.
        let prior = WisprHistory.newest()
        priorRow = prior?.rowid
        priorRowWasOpen = prior.map { !WisprState.isTerminal($0.status) } ?? false
        historyRow = nil
        historyFormattedAt = 0
        historyPoll?.invalidate()
        let h = Timer(timeInterval: Self.historyTick, repeats: true) { [weak self] _ in self?.pollHistory() }
        historyPoll = h
        RunLoop.main.add(h, forMode: .common)
    }

    /// **How long the words may take, counted from the last one.** The capture
    /// window opened at the gesture; this is the 30 s it is allowed to stand
    /// after the microphone shuts.
    private func armCaptureDeadline() {
        captureDeadline?.cancel()
        let giveUp = DispatchWorkItem { [weak self] in self?.captureExpired() }
        captureDeadline = giveUp
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.captureTimeout, execute: giveUp)
    }

    /// **A capture whose row is not terminal belongs to a sentence still in
    /// flight**, and a new gesture does not get to disarm it.
    ///
    /// This is the second failure of 2026-09-13 in one method. A 🔼 click landed
    /// inside a settle, `onPasteToggle` asked only about `listening` and started
    /// a phantom dictation, and `gestureSeen`'s unconditional `endCapture` threw
    /// away the *first* sentence's swallow window — so Wispr's ⌘V, a second
    /// later, went into whatever Terminal happened to be in front. The click is
    /// now a stop (`AppDelegate.onPasteToggle`); this is the guard behind it, for
    /// the dictation Victor starts from his own keyboard while the last one is
    /// still being transcribed.
    private func retireCaptureIfSettled() {
        guard capturing else { return }
        if let row = historyRow, !WisprState.isTerminal(status(of: row)) {
            Log.info("wispr: a capture is still standing for row \(row) (\(status(of: row).isEmpty ? "no status yet" : status(of: row))) — the new gesture does not disarm it")
            return
        }
        endCapture(quiet: true)
    }

    private func status(of row: Int64) -> String {
        guard let e = WisprHistory.newest(), e.rowid == row else { return "" }
        return e.status
    }

    /// **What Wispr says about this dictation.** `status` stays empty while it
    /// works; the first non-empty value is the end of the round trip, whatever
    /// the tap saw. `formatted` waits `pasteGrace` for the ⌘V that usually
    /// follows — the ordinary paths deliver and close the capture underneath
    /// this timer — and only then takes the words from the row: Wispr put them
    /// where the focus was, by a route no tap sees, and `insertedElsewhere`
    /// lets the router decide whether that was the destination.
    private func pollHistory() {
        guard capturing, let e = WisprHistory.newest() else { return }

        // **Adopting the row.** Anything that is not the row that was on top when
        // this was armed, and was created at or after the gesture, is this
        // dictation's — unless that top row was still open, in which case it is
        // this dictation's and was simply created before the first tick.
        if historyRow == nil {
            let isNew = e.rowid != priorRow || priorRowWasOpen
            guard isNew, e.startedAt >= openedAt - 2 else { return }
            historyRow = e.rowid
            Log.info(String(format: "wispr history: row %d is this dictation's — %.0f ms after the chord (%@)",
                            e.rowid, (CFAbsoluteTimeGetCurrent() - armedAt) * 1000,
                            e.micDevice.isEmpty ? "no device named yet" : e.micDevice))
            // The row exists, so Wispr took the chord — whatever the microphone
            // signals did or did not see.
            confirmSpeculative(by: "Wispr's own row")
        }
        guard e.rowid == historyRow else { return }
        // **Only while this capture is the current chord's.** A capture left
        // standing for the previous sentence (`retireCaptureIfSettled`) goes on
        // polling its own row, and feeding that row's terminal status into a
        // machine that is describing the *new* dictation would put it straight
        // into `done` before Wispr had heard a word of it.
        if armedAt >= state.chordAt { state.sawRow(e.rowid, status: e.status) }

        let took = (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000
        switch e.status {
        // **Intermediate, and they are progress rather than silence.** `""` is
        // the row as created at the gesture; `raw_transcript` and `processing`
        // were first seen on 2026-09-13 and were unknown to this switch that day,
        // so a settle sat out its whole timeout on a sentence that was arriving.
        // Bounded by `captureTimeout` and by nothing else.
        case let s where WisprState.intermediateStatuses.contains(s):
            return

        case "formatted", "extension_paste", "extension_other":
            // **The row as the delivery, with no ⌘V ever arriving.** Nothing to
            // wait for when Wispr cannot insert: the words are in the row, and
            // the relay is the only one who is going to put them anywhere.
            if historyIsTheRoute {
                Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — the row is the delivery",
                                e.status, took, e.e2eLatency))
                deliver(reason: "Wispr's History row", via: "wispr-history",
                        delivery: .route, text: e.text)
                return
            }
            if historyFormattedAt == 0 {
                historyFormattedAt = CFAbsoluteTimeGetCurrent()
                Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — giving the ⌘V %.1f s",
                                e.status, took, e.e2eLatency, Self.pasteGrace))
                return
            }
            guard CFAbsoluteTimeGetCurrent() - historyFormattedAt >= Self.pasteGrace else { return }
            Log.info("wispr history: no ⌘V and no pasteboard after \(e.status) — Wispr inserted it into \(e.app) by a route the tap cannot see")
            deliver(reason: "Wispr's History row", via: "wispr-history",
                    delivery: .insertedElsewhere, text: e.text)
        case "dismissed":
            Log.info(String(format: "wispr history: dismissed — %.0f ms after the microphone closed", took))
            endCapture(quiet: true)
            didEnd?(.cancelled(audio: nil, duration: 0))
        case "empty", "no_audio":
            Log.info(String(format: "wispr history: %@ — %.0f ms after the microphone closed", e.status, took))
            endCapture(quiet: true)
            didEnd?(.silent("No words detected"))
        default:
            // A status nobody has seen ends the dictation rather than hanging it
            // — today's behaviour, kept — but it says so, because the alternative
            // reading (unknown = progress) turns one new Wispr status into every
            // sentence waiting out thirty seconds.
            Log.error(String(format: "wispr history: %@ — %.0f ms after the microphone closed", e.status, took))
            endCapture(quiet: true)
            didEnd?(.silent("Wispr Flow reported \(e.status)"))
        }
    }

    /// Wispr pressed ⌘V. Under the wrap the tap has already eaten it, so the
    /// words are nowhere yet and this is the whole delivery.
    private func injected(from process: String) {
        guard capturing else { return }
        Log.info(String(format: "⌘V from %@ — %.0f ms after the microphone closed%@",
                        process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000,
                        wrapWispr ? " (taken)" : " (let through)"))
        deliver(reason: "Wispr's ⌘V", via: "wispr-cmdv",
                delivery: wrapWispr ? .route : .alreadyInserted)
    }

    private func captureExpired() {
        guard capturing else { return }
        // **The fallback, and it is Wispr's own shortcut.** `55+59+8` =
        // `copy_last_text` (⌘⌃C) puts the last transcript on the pasteboard
        // without a microphone. Posted once, and only when nothing has been seen
        // at all: a pasteboard that never moved and a ⌘V that never came means
        // the delivery went somewhere this tap cannot see.
        if !askedForCopy, Self.copyFallbackEnabled {
            askedForCopy = true
            Log.info("no delivery seen — asking Wispr for it with ⌘⌃C (copy_last_text)")
            clipboardAt = NSPasteboard.general.changeCount
            HotkeyTap.postWisprCopyLast()
            let again = DispatchWorkItem { [weak self] in self?.captureExpired() }
            captureDeadline = again
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.copyGrace, execute: again)
            return
        }
        if NSPasteboard.general.changeCount != clipboardAt {
            deliver(reason: "copy_last_text", via: "pasteboard",
                    delivery: wrapWispr ? .route : .alreadyInserted)
            return
        }
        let waiting = historyRow.map { "Wispr's row \($0) is still \(status(of: $0).isEmpty ? "empty" : status(of: $0))" }
            ?? "Wispr never created a row"
        state.timedOut("nothing came back within \(Int(Self.captureTimeout)) s")
        Log.error("wispr: nothing came back within \(Int(Self.captureTimeout)) s — \(waiting)")
        endCapture(quiet: true)
        didEnd?(.silent("No words came back"))
    }

    /// - Parameter via: the route, in the one word `outbox.jsonl` and
    ///   `GET /test/state` record it under. `reason` above is prose for the log;
    ///   this is the same fact in a form a test can assert on — see
    ///   `DictationResult.via`.
    /// - Parameter text: the words, when they did not come through the
    ///   pasteboard — Wispr's own row. The pasteboard otherwise.
    private func deliver(reason: String, via: String, delivery: DictationDelivery,
                         text given: String? = nil) {
        guard capturing else { return }
        // The string as it stood when the pasteboard first moved, when that is
        // what this delivery is about — see `clipboardMoved`.
        let fromBoard = clipboardMoved ?? NSPasteboard.general.string(forType: .string)
        let text = (given ?? fromBoard ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // **A pasteboard holding what it held before he started talking is not a
        // transcript** — it is Wispr putting the clipboard back after its own
        // ⌘V. The capture is *kept*, because the row can still answer and
        // usually does a beat later; only this route is refused.
        if given == nil, !text.isEmpty,
           text == clipboardBaseline?.trimmingCharacters(in: .whitespacesAndNewlines) {
            Log.error("wispr: \(reason) — the pasteboard holds exactly what it held before the dictation (\(text.count) chars). Wispr restored it; this is not the sentence. Waiting for the row.")
            return
        }
        let took = CFAbsoluteTimeGetCurrent() - captureFrom
        // Before `endCapture` resets it, or the machine goes `transcribing` →
        // `idle` and the transition log never says this one finished.
        if armedAt >= state.chordAt { state.delivered(via: via) }
        endCapture(quiet: true)
        guard !text.isEmpty else {
            Log.error("wispr: \(reason) carried nothing")
            didEnd?(.silent("No words detected"))
            return
        }
        Log.info(String(format: "🗣️ wispr transcript via %@ — %d chars, %.0f ms after the microphone closed",
                        reason, text.count, took * 1000))
        meterQueue.async { [weak self] in
            guard let self else { return }
            let taken = self.recording
            self.recording = nil
            DispatchQueue.main.async {
                self.didTranscribe?(DictationResult(
                    text: text,
                    language: nil,
                    audio: taken?.url,
                    duration: taken?.duration ?? 0,
                    // Stamped so a sample labelled by Wispr's own recogniser is
                    // never mistaken for one the local model read. The text has
                    // been through Wispr's formatting pass — punctuation, its
                    // custom dictionary — which is a fact a later evaluation has
                    // to know, and the engine name is where it is said.
                    engine: "wispr-flow",
                    warning: nil,
                    delivery: delivery,
                    via: via))
                self.didEnd?(.delivered)
            }
        }
    }

    private func endCapture(quiet: Bool) {
        guard capturing else { return }
        capturing = false
        hotkeys.disarmInjectionCapture()
        clipboardWatch?.invalidate()
        clipboardWatch = nil
        clipboardBaseline = nil
        clipboardMoved = nil
        historyPoll?.invalidate()
        historyPoll = nil
        historyRow = nil
        priorRow = nil
        priorRowWasOpen = false
        captureDeadline?.cancel()
        captureDeadline = nil
        // The machine goes back to rest with the capture, which is also what
        // takes the 100 ms poll off CoreAudio.
        if !isRecording, !speculative { state.reset("the capture is over") }
        // **A sentence that is still being spoken gets its own window now.**
        // The capture that just ended belonged to the *previous* one — kept by
        // `retireCaptureIfSettled` because its row was not terminal — and
        // leaving this one with no swallow, no pasteboard watch and no row poll
        // is the 2026-09-13 Word failure with extra steps.
        if isRecording || speculative {
            Log.info("wispr: the standing capture is retired — arming this dictation's own")
            beginCapture()
        }
        syncInputPoll()
    }
}
