import AppKit
import ApplicationServices
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
        didSet {
            guard wrapWispr != oldValue else { return }
            Log.info("wispr wrap \(wrapWispr ? "on" : "off") — \(wrapMode.rawValue): \(wrapReason)")
        }
    }

    /// **How the relay takes Wispr's words**, and the three answers are three
    /// different relationships with another app (Victor's decisions, 2026-09-13).
    ///
    /// | mode | Wispr is told | the words come from | what it costs |
    /// |---|---|---|---|
    /// | `scratchpad` | *Open Scratchpad*, **held** for the sentence | its own `Notes` row | nothing — no insertion, no focus moved |
    /// | `sink` | the hands-free chord | the relay's own key window | the keyboard, for a moment, during every dictation |
    /// | `off` | the hands-free chord | nobody — Wispr inserts where the focus is | the wrap |
    ///
    /// The order matters and so does why the other two were rejected. **The sink
    /// works** — measured 3/3 on 2026-09-13: Wispr picks its insertion target at
    /// the *end*, so a window taking the keyboard 1–5 ms after the stop chord
    /// receives the text. Victor rejected it as the primary path anyway, because
    /// it takes the focus off a man who may be clicking or typing at that
    /// instant, and a dictation helper whose ordinary behaviour is to interrupt
    /// him is not one he can leave running. **Revoking Wispr's Accessibility
    /// grant** also works and was rejected for its own reason: Wispr has to go on
    /// being usable on its own, and an app this one has quietly disarmed is not.
    ///
    /// The Scratchpad costs nothing because it is Wispr's own answer to *dictate
    /// somewhere that is not the caret*. Measured: F18 held 20 s, the text in
    /// `Notes`, the victim document untouched, **focus never moved**, no ⌘V
    /// posted, e2e 432 ms.
    enum WrapMode: String {
        case scratchpad
        case sink
        case off
    }

    /// `WT_WRAP_MODE=sink` for one run, and `POST /test/wrap-mode` for the loop.
    /// Nil means *decide from the tick and from Wispr's own configuration*.
    private var modeOverride: WrapMode? =
        ProcessInfo.processInfo.environment["WT_WRAP_MODE"].flatMap { WrapMode(rawValue: $0.lowercased()) }

    /// The mode in force this instant, and a sentence saying how it got there —
    /// both in `/engine` and `GET /test/state`, because a wrap that silently
    /// fell back to the emergency path is exactly the thing nobody notices.
    var wrapMode: WrapMode {
        guard wrapWispr else { return .off }
        if let modeOverride { return modeOverride }
        guard !scratchpadBroken else { return .sink }
        return HotkeyTap.scratchpadIsConfigured ? .scratchpad : .sink
    }

    var wrapReason: String {
        guard wrapWispr else { return "the wrap is off (WT_WRAP_WISPR / POST /test/wrap-mode — there is no menu row since 2026-09-14) — Wispr inserts where the focus is and the relay only draws the ring" }
        if let modeOverride {
            return "forced to \(modeOverride.rawValue) by WT_WRAP_MODE / POST /test/wrap-mode"
        }
        if scratchpadBroken {
            return "the Scratchpad window would not close, and a held chord writes no note while it is open — the sink until it does"
        }
        return HotkeyTap.scratchpadIsConfigured
            ? "Wispr has an open_scratchpad shortcut — the relay holds it and reads the note"
            : "Wispr has no open_scratchpad shortcut — falling back to the sink, which takes the keyboard for a moment at every stop"
    }

    /// `POST /test/wrap-mode {"mode": "scratchpad"|"sink"|"off"|"auto"}`.
    func setWrapMode(_ raw: String) -> [String: Any] {
        if raw.lowercased() == "auto" {
            modeOverride = nil
            scratchpadBroken = false
            wrapWispr = true
        } else if let mode = WrapMode(rawValue: raw.lowercased()) {
            if mode == .off { wrapWispr = false }
            else { wrapWispr = true; modeOverride = mode }
            if mode != .off { modeOverride = mode }
        } else {
            return ["ok": false, "error": "unknown mode \(raw)", "modes": ["scratchpad", "sink", "off", "auto"]]
        }
        Log.info("wispr wrap mode → \(wrapMode.rawValue): \(wrapReason)")
        return ["wrapMode": wrapMode.rawValue, "why": wrapReason]
    }

    /// **Whether this dictation is the relay's to take.**
    ///
    /// Victor's line, 2026-09-13: a dictation *he* starts — his own keyboard
    /// chord, or 🔽→ which posts Wispr's chord raw — is Wispr's. The relay draws
    /// the ring for it because the ring is *a microphone is open* and that is
    /// true, and it does nothing else: no swallow, no Scratchpad, no routing.
    /// Taking over a tool he reached for directly is a different thing from
    /// wrapping a dictation this app asked for itself.
    private(set) var relayStarted = false

    /// **The mode this dictation opened in**, latched at the gesture. `wrapMode`
    /// can change under a sentence — the tick is a menu row and the loop posts
    /// `/test/wrap-mode` — and a dictation started by holding a key must be
    /// ended by releasing *that* key, whatever the menu says by then.
    private(set) var startedMode: WrapMode = .off

    /// **The app he was looking at when he asked**, remembered at the chord — the
    /// last moment it is unambiguous, because the window that will take the
    /// keyboard never becomes frontmost. It travels out on
    /// `DictationResult.focusPid` so the caret paste can be *addressed* instead
    /// of aimed at whatever holds the focus, which is what lets the delivery fire
    /// at `formatted` rather than waiting for Wispr's window to close.
    ///
    /// **Remembered in every mode, not only the caret's** (2026-09-14). It was
    /// filled inside `guardTheKeyboard`, behind a guard that returned early when
    /// the frontmost application was the relay itself — and a spawn dictation
    /// puts the relay's own folder menu in front at exactly that moment, so
    /// `wrap-spawn` and `wrap-bound` armed no redirect at all and lost every
    /// probe keystroke. The destination of the sentence has nothing to do with
    /// whose keyboard it is.
    private(set) var focusPid: pid_t?

    /// **The last application that was frontmost and was not this one.**
    ///
    /// The fallback for the moment the relay's own menu or panel is in front
    /// when the chord goes out. Kept by subscription rather than asked for,
    /// because by the time it is wanted the answer has already been spoiled.
    private var lastFrontPid: pid_t = 0

    /// **The app that was in front before the one that is in front now.**
    ///
    /// Whose front Wispr took is a different question from whose front it was at
    /// the chord: he may have clicked into another window while he was talking,
    /// and putting him back into the one he left would be a second theft dressed
    /// as a fix. This is the first answer `putTheFrontBack` tries; `focusPid` is
    /// the fallback.
    private var frontBeforeLast: pid_t = 0

    /// When the front was last given back, newest last — a rate limit and
    /// nothing more. Wispr and the relay each activating in answer to the other
    /// is a fight the man watching loses either way, so after
    /// `frontHandbackLimit` inside `frontHandbackWindow` it stops.
    private var frontHandbacks: [Date] = []
    private static let frontHandbackLimit = 5
    private static let frontHandbackWindow: TimeInterval = 60

    /// For `GET /test/state` — the flag above, which is not `startedMode`.
    var isIntercepting: Bool { intercepting }

    /// **The wrap's apparatus is armed for this sentence** — latched at the
    /// gesture, exactly like `startedMode`, and deliberately a *different*
    /// question from it.
    ///
    /// `startedMode` says **how the chord was posted**, so it says what `stop()`
    /// has to undo: a dictation opened by holding a key is ended by releasing
    /// that key. This says **whether the relay delivers the words**. They come
    /// apart on `POST /test/wispr-handsfree`, which posts the hands-free chord —
    /// so its `startedMode` is `off`, no key is held and no sink is taken — while
    /// the wrap is on and the ⌘V is still the relay's to swallow. Folding the two
    /// into one flag broke that route the first time it was tried.
    private var intercepting = false

    /// **This dictation was opened by holding right ⌘⌥**, so the moment that pair
    /// comes back up is the moment it ends — see `pushToTalkReleased`.
    ///
    /// The gate, and the reason the release is not simply *a stop*: a ⌘⌥ Victor
    /// presses for something else in the middle of a hands-free sentence, or of
    /// one the relay opened, must not end it. Only a sentence this pair started
    /// is a sentence this pair can finish.
    private var startedByHeldPair = false

    // MARK: - Events

    var didMaybeBegin: ((String) -> Void)?
    var didBegin: (() -> Void)?
    var didStopListening: (() -> Void)?
    var didTranscribe: ((DictationResult) -> Void)?
    var didEnd: ((DictationEnd) -> Void)?

    /// **Wispr's microphone is open — and this is the one event that is reported
    /// whether or not this source is the engine.**
    ///
    /// The five events above are `DictationSource`'s, and they only reach the app
    /// when this object *is* `source`: with the Engine on the local model nobody
    /// wires them, and a dictation Victor starts himself with ⌘⌥ then happens
    /// with the relay silent about it — which is what he found on 2026-09-18,
    /// music playing over a push-to-talk sentence that the log had already named
    /// (`⚡ right ⌘⌥ — Wispr push-to-talk`).
    ///
    /// It is deliberately narrower than `didBegin`: a dictation the relay did not
    /// ask for is still Wispr's — no screenshot, no ⌘C probe, no route — and this
    /// says only *he is talking to a microphone right now*, which is the whole of
    /// what the music has ever needed (`MusicBridge`). Set once at launch, not in
    /// `wireDictationSource`, because it does not belong to whichever source is
    /// wired up.
    ///
    /// **`WisprState.listening` and not `WisprWatch`**, for the reason the machine
    /// exists: the CoreAudio edge is 0–6 s late and produced no edge at all in
    /// five of five runs on 2026-09-13, and with the Engine on the local model
    /// this source's own `watch` is never even started (`prepare()` is not
    /// called), so the poll sees nothing either. The phase joins those two with
    /// Wispr's `History` row, which is written at the gesture and is the signal
    /// that actually fires — measured 182 ms on 2026-09-18.
    var hearingChanged: ((Bool) -> Void)?

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

    /// **Yes** — Wispr's microphone is pinned to the Loopback device
    /// `🎓 TO Wispr`, whose output side any app can speak into, and measured
    /// 2026-09-14 the marker arrives in `asrText` and survives the formatting
    /// pass into `formattedText`. See `ShotMarker`.
    var acceptsAudioMarkers: Bool { true }

    /// **Two mechanisms, and which one is in force is whether this app owns the
    /// path into Wispr.**
    ///
    /// With the bridge up the marker is written into the stream Wispr is being
    /// fed (`MicRecorder.insert`), so it arrives **between** two of his words —
    /// deterministic, nothing to mask it, no gap to wait for. Without it, the
    /// marker can only be *played into* the Loopback device and is therefore
    /// summed with his voice, which measured 2026-09-14 means it vanishes over
    /// continuous speech — and it is not a level that can be raised, since it is
    /// already the louder of the two. So that path waits for a gap and accepts
    /// the ceiling. → `AudioBridge`, `ShotMarker.maskCeiling`
    func mark(_ kind: ShotMarker.Kind, index: Int) {
        if bridge.isRunning, let pcm = ShotMarker.pcm(kind, index: index, in: MicRecorder.fileFormat) {
            meter.insert(pcm)
            // One sequence, two destinations (`MicRecorder.onBuffer`): the same
            // buffer reaches Wispr's ear *and* the WAV this app is filing. So
            // this pair is now one whose audio contains the marker, and the
            // corpus must keep the words that name it rather than the cleaned
            // ones. Without this the bridged path files exactly the poisoned
            // pair `markersInAudio` was invented to prevent.
            markersInAudio = true
            return
        }
        ShotMarker.play(kind, index: index,
                        whenQuiet: { [weak self] in
                            (self?.meter.quietSeconds ?? 0) >= ShotMarker.gapNeeded
                        })
    }

    /// **How long Wispr still has to listen for audio this app has not handed
    /// over yet**, capped. The stop chord waits this out, or Wispr ends the
    /// sentence on a tail still sitting in the player's queue. Zero with the
    /// bridge down, which is every run that has not opted in.
    var bridgeDrainSeconds: TimeInterval { min(bridge.queuedSeconds, 3) }

    let meter = MicRecorder()

    /// **His voice, carried to Wispr by this app** — off unless `WT_BRIDGE=1`,
    /// and see `AudioBridge` for the one-time Loopback change it needs. While it
    /// is up, a shot marker is *spliced* into the stream instead of played over
    /// it, which is the whole point of owning the path.
    private let bridge = AudioBridge()

    /// Whether this sentence's WAV has a marker spliced into it — true only on
    /// the bridged path, where `mark` splices rather than plays. Reset with the
    /// meter, because it describes one recording.
    private var markersInAudio = false

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
    /// **The one place this app reads the pasteboard's text**, and it is
    /// guarded because the delivery path runs exactly when Wispr — and, in a
    /// test, the harness — are rewriting it.
    ///
    /// Three cheap defences, none of which can catch a fault but all of which
    /// shrink the window it needs:
    ///
    /// - **Ask `types` first.** It is the question that says whether there is a
    ///   string at all, and `stringForType:` on a pasteboard without one still
    ///   walks the type cache — which is where the crash was.
    /// - **Sandwich it in `changeCount`.** A pasteboard that moved while it was
    ///   being read may hand back a mixture of two owners' contents; the caller
    ///   is better off with nothing than with half a sentence.
    /// - **Read once.** Every caller on the delivery path comes here, so a
    ///   delivery costs one read rather than one per branch that wondered.
    static func pasteboardString() -> String? {
        let board = NSPasteboard.general
        guard board.types?.contains(.string) == true else { return nil }
        let before = board.changeCount
        let text = board.string(forType: .string)
        guard board.changeCount == before else { return nil }
        return text
    }

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

    /// **The sentence is cancelled but Wispr has not finished with it.**
    ///
    /// Set by a cancel that lands during the settle. Everything stays armed —
    /// the swallow, the row poll, the deadline — and every route that would
    /// have delivered drops the words instead. It is cleared by `endCapture`,
    /// which runs when Wispr's row goes terminal, when its ⌘V is seen, or at
    /// `captureTimeout`; the Scratchpad window goes with it.
    private var discardOnArrival = false

    /// **When the ⌃Escape dismiss went out for a cancel during the settle.**
    /// The clock the early close is measured from — see `armDiscardClose`.
    private var dismissedAt: CFAbsoluteTime = 0
    private var discardCloseTimer: Timer?

    /// **The row of a cancelled sentence whose capture a new gesture superseded**
    /// (2026-09-14).
    ///
    /// A cancel during the settle keeps everything armed until Wispr is finished,
    /// and that is right — but it may not hold the *next* dictation hostage for
    /// the 30 s of `captureTimeout`, which is exactly what it did: `capturing`
    /// stayed true, `retireCaptureIfSettled` refused to let a non-terminal row
    /// go, and the relay measured **never listening (8.1 s)** on the gesture
    /// after it. So the capture is retired at once and only this much of it
    /// survives: the swallow, **keyed by the rowid it was armed for**, so Wispr's
    /// late ⌘V for the sentence Victor threw away still lands nowhere.
    private var retiredDiscardRow: Int64?
    private var retiredDiscardUntil: CFAbsoluteTime = 0
    private var retiredDiscardTerminalAt: CFAbsoluteTime = 0
    private var retiredDiscardTimer: Timer?
    /// Five seconds, against Wispr's own p99 of 7.1 s counted from the *chord* —
    /// this is counted from a row that is already being transcribed, and the
    /// claim is let go earlier than this on every ordinary run (the row goes
    /// terminal and `pasteGrace` passes). It exists so a row Wispr abandons
    /// cannot keep the swallow armed over Victor's next sentence for ever.
    private static let retiredDiscardCeiling: TimeInterval = 5

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
    /// The Scratchpad note that was newest when this dictation opened, so the
    /// one Wispr writes at the end can be told from it — by id for a new note,
    /// by its stamp for one Wispr appended to.
    private var priorNoteId: String?
    private var priorNoteStamp: TimeInterval = 0
    /// **The note's whole text before this dictation**, because Wispr does not
    /// reliably start a new note: measured 2026-09-13, it appended to the note
    /// from a run four minutes earlier with `source = typed`, and a delivery of
    /// `NoteVersions.content` would then have handed over the accumulated
    /// notepad — 70 characters for a four-word sentence, growing every time.
    private var priorNoteText: String?
    /// Whether the note path has already dealt with the Scratchpad window, so
    /// `endCapture` does not tap the chord a second time behind it.
    private var scratchpadWindowHandled = false
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
        // **And every edge of `listening` is published** — see `hearingChanged`.
        state.onTransition = { [weak self] previous, next, _ in
            guard let self else { return }
            self.syncInputPoll()
            if previous.isListening != next.isListening {
                self.hearingChanged?(next.isListening)
            }
        }
        watch.onChange = { [weak self] on in self?.edge(on, measured: true) }
        hotkeys.onWisprMaybeStarting = { [weak self] start in
            // His keyboard, not the relay's — `relay: false`.
            DispatchQueue.main.async {
                self?.gestureSeen(start.why, confident: start.isConfident, relay: false,
                                  heldPair: start == .pushToTalk)
            }
        }
        hotkeys.onWisprPushToTalkReleased = { [weak self] in
            DispatchQueue.main.async { self?.pushToTalkReleased() }
        }
        hotkeys.onWisprMaybeCancelling = { [weak self] in
            DispatchQueue.main.async { self?.dismissSeen() }
        }
        hotkeys.onInjectedPaste = { [weak self] from in
            DispatchQueue.main.async { self?.injected(from: from) }
        }
    }

    /// **Watch Wispr's microphone whichever engine is wired up** (Victor,
    /// 2026-09-21: *"ori de câte ori Wispr Flow interceptează vocea, trebuie să
    /// fie o animație pe ecran … că pornesc cu apăsat taste, că pornesc din
    /// gesturi de mouse"*).
    ///
    /// Everything else this source does for a foreign dictation is already
    /// unconditional — the tap's two chords and `onWisprRawChord` are wired in
    /// `init` and in `AppDelegate` whatever `dictationSource` says. The
    /// CoreAudio watch was the one witness that was not: it is started by
    /// `prepare()`, which `AppDelegate.wireDictationSource` calls on the
    /// **selected** source only, so with the engine on ElevenLabs or the local
    /// Whisper it never ran. The consequence was a hole exactly the shape of
    /// *every way of starting Wispr that is neither of those two chords* — the
    /// F18 Scratchpad hold, a rebound shortcut, Wispr's own window — for which
    /// nothing at all appeared on screen.
    ///
    /// `WisprWatch.start()` is idempotent, so `prepare()` may still call it and
    /// the source that is wired up loses nothing. This is deliberately **only**
    /// the watch: the Scratchpad sweep and the front-restore in `prepare()` are
    /// wrap machinery, and the relay wraps nothing it did not start.
    func watchMicrophone() {
        watch.start()
    }

    func prepare() {
        watch.start()
        // **The orphan sweep runs for the life of the app** (2026-09-14). It was
        // armed for twelve seconds after each capture and that is exactly when
        // it cannot work: the orphan it is looking for is made by a toggle that
        // lands late, so the window does not exist yet while the sweep is
        // looking, and by +3 s and +15 s — where the runner found it standing —
        // nothing was watching at all. One AX existence read every half second,
        // and only while this source says nothing is going on.
        WisprScratchpad.startIdleSweep { [weak self] in
            guard let self else { return true }
            return self.state.phase == .idle && !self.capturing
                && !self.isRecording && !self.speculative
        }
        // **And whose front it is, given back after every close.** The close is
        // a chord posted at Wispr and Wispr answers it by activating itself —
        // see `putTheFrontBack`. A beat is left for the activation to land,
        // because the chord is posted on its own queue and the front changes
        // after it, not with it.
        //
        // **Twice, because the activation is not on the chord's clock.** The
        // close is a toggle whose effect lands when Wispr gets to it; the
        // second look costs one `frontmostApplication` read on a run where the
        // first one already put him back, and catches the run where Wispr came
        // forward a second after its own window went.
        WisprScratchpad.onCloseFinished = { [weak self] reason, _ in
            for delay in [0.45, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self?.putTheFrontBack(after: reason)
                }
            }
        }
        // Whose keyboard it is, kept current — see `lastFrontPid`.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier != Bundle.main.bundleIdentifier,
                      app.processIdentifier > 0 else { return }
                self?.frontBeforeLast = self?.lastFrontPid ?? 0
                self?.lastFrontPid = app.processIdentifier
                // The tap needs this too, and must not ask AppKit on its own
                // thread — see `HotkeyTap.noteFrontmost`.
                self?.hotkeys.noteFrontmost(app.processIdentifier)
            }
    }

    // MARK: - DictationSource

    @discardableResult
    func start() -> String? {
        guard !isRecording else { return nil }
        guard isReady else { return "Wispr Flow is not running" }
        // **A stand-down is not a verdict.** If the window that would not close
        // is closed now — Victor clicked the menu row, Wispr was restarted — the
        // precondition holds again and there is no reason to go on using the
        // emergency path.
        if scratchpadBroken, HotkeyTap.scratchpadIsConfigured, !WisprScratchpad.windowIsOpen() {
            scratchpadBroken = false
            Log.info("🗒️ the Scratchpad window is closed again — scratchpad mode is back")
        }
        let mode = wrapMode
        // **The ring first, always.** Whatever the mode has to do to get Wispr
        // ready, Victor pressed a button and the beacon answers the button.
        gestureSeen("the relay asked for a dictation (\(mode.rawValue))", confident: true, relay: true)
        switch mode {
        case .scratchpad:
            holdScratchpad()
        case .sink:
            HotkeyTap.postWisprHandsFree()
            // The sink comes up now and takes the keyboard only at the stop —
            // Wispr picks its target at insertion time (measured 3/3), so there
            // is nothing to gain by holding his keyboard for the whole sentence
            // and everything to lose.
            WisprSink.shared.open()
            WisprSink.shared.clear()
        case .off:
            HotkeyTap.postWisprHandsFree()
        }
        return nil
    }

    /// **Close the Scratchpad window if it is up, then hold the chord.**
    ///
    /// The order is the measurement (2026-09-13, four runs): with the window
    /// **closed** a held chord writes a note, 3/3; with it **open** Wispr
    /// transcribes normally and writes **no note at all**, and closing it
    /// afterwards does not commit one. The sentence is simply lost, silently, and
    /// the thing that leaves the window open is the *previous* dictation — Wispr
    /// opens it in the background at the end of every one. So the precondition is
    /// checked at the start as well as restored at the end: two chances to
    /// notice, because the failure shows up one sentence later than its cause.
    ///
    /// The common path costs nothing — the window is already closed, `windowIsOpen`
    /// is one window-server call, and the chord goes down in the same turn.
    private func holdScratchpad() {
        // **The window appears at the start of the hold, not at the end**
        // (2026-09-13, corrected by Victor and by the loop's first
        // `scratchpad-hold`). It is a floating panel and it sits on top of his
        // work for the whole sentence, which is the thing he objected to — so it
        // is watched from the chord, parked the moment it is seen, and closed
        // later. His keys are guarded for the same stretch and by the same flag.
        WisprScratchpad.beginDictation()
        guardTheKeyboard()
        guard WisprScratchpad.windowIsOpen() else {
            HotkeyTap.postWisprScratchpad(down: true)
            return
        }
        Log.info("🗒️ the Scratchpad window is open — a held chord writes no note while it is; closing it first")
        WisprScratchpad.closeWindow { [weak self] gone in
            guard let self, self.startedMode == .scratchpad,
                  self.isRecording || self.speculative else { return }
            if gone {
                Log.info("🗒️ the Scratchpad window is closed — holding the chord")
                HotkeyTap.postWisprScratchpad(down: true)
                return
            }
            // **Salvage the sentence rather than lose it.** Holding the chord
            // now would record into a window that writes no note; the hands-free
            // chord with the sink behind it is the emergency path and it works.
            Log.error("🗒️ the Scratchpad window would not close — this sentence goes through the sink instead, and so will the next one")
            WisprScratchpad.endWatch()
            self.scratchpadBroken = true
            self.startedMode = .sink
            HotkeyTap.postWisprHandsFree()
            WisprSink.shared.open()
            WisprSink.shared.clear()
        }
    }

    /// **Shut the window on sight, and hold the keyboard for him meanwhile.**
    ///
    /// Two halves of one answer to the loop's 2026-09-13 finding: a `z` typed
    /// 1.5 s after the stop gesture landed in Wispr's note and was delivered
    /// **inside the sentence**, with `NSWorkspace.frontmostApplication` reading
    /// TextEdit the whole time. The Scratchpad becomes key without its app
    /// becoming frontmost.
    ///
    /// So the window is closed the instant it is seen (50 ms poll, the press
    /// posted immediately), which cuts its life to the few hundred milliseconds
    /// the close itself takes; and for exactly that stretch every real keystroke
    /// is taken by the tap and re-posted to the app he was looking at when he
    /// stopped talking.
    /// **The owner of the frontmost window that is neither this app's nor
    /// Wispr's** — the fallback when `NSWorkspace` says the relay itself is in
    /// front, which a **spawn** guarantees: `startDictation(spawn:)` offers the
    /// folder menu on the gesture, and a menu makes its own app frontmost.
    ///
    /// The cached *last* frontmost app was the fallback before this and it is
    /// empty after a restart and stale after a relaunch of the victim — measured
    /// 2026-09-14, `wrap-spawn` aimed every keystroke at pid 56416, which had
    /// been dead for two builds. The window server's own front-to-back order
    /// cannot be stale: it is asked here and now, and the first window in it that
    /// belongs to somebody else *is* the app he is looking at.
    private static func frontWindowOwner() -> pid_t? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        for w in windows {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != mine,
                  pid != WisprScratchpad.wisprPid,
                  // Layer 0 is an ordinary window; the menu bar, the Dock and
                  // Wispr's own floating pill all sit above it.
                  (w[kCGWindowLayer as String] as? Int) == 0
            else { continue }
            return pid
        }
        return nil
    }

    /// The window he was typing in, read once at the chord — `AXFocusedWindow`
    /// of the application that was frontmost then.
    private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let w = value, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    private func guardTheKeyboard() {
        // `focusPid` was decided at the gesture, in every mode — see its note.
        guard let pid = focusPid, pid != 0 else {
            Log.error("⌨️ no application to give his keys back to — the keyboard is not guarded for this dictation")
            return
        }
        let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
        // **Take the keyboard back rather than work around it.** The Scratchpad
        // becomes key without becoming frontmost, and an app that is frontmost
        // but not key has **no first responder** — so keys re-posted to it with
        // `postToPid` are simply dropped (measured 2026-09-14: five re-posted to
        // TextEdit, five lost). Re-activating the application he was using is
        // the only thing that actually puts the caret back where he left it. It
        // is one call, once per dictation, aimed at the app he is already in,
        // and the Scratchpad it takes the focus from is parked off the edge of
        // the screen by the time this runs.
        // **Give the victim its key WINDOW back, not just its application.**
        //
        // Re-activating the app was not enough and could not be: `activate` says
        // *be frontmost*, and the app was already frontmost — what it did not
        // have was a **key window**, because Wispr's non-activating panel had
        // taken that without taking the front. An application that is frontmost
        // with no key window has no first responder, so a plain character posted
        // to it is dropped, which is why five re-posted letters vanished.
        //
        // So the window itself is remembered at the chord and told, through
        // Accessibility, to be main and focused again. Cheap, and aimed at the
        // window he was actually typing in rather than at whatever the app would
        // pick for itself.
        let victimWindow = Self.focusedWindow(of: pid)
        if victimWindow == nil {
            Log.error("⌨️ could not read \(name)'s focused window — the keyboard cannot be handed back if Wispr takes it")
        }
        WisprScratchpad.onKeyStolen = {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            app.activate(options: [])
            if let w = victimWindow {
                AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            }
            let back = !WisprScratchpad.focusOwnerIsWispr()
            Log.info("⌨️ Wispr's Scratchpad took the keyboard — handed it back to \(name); the focus owner "
                     + (back ? "flipped back" : "is still Wispr"))
        }
        WisprScratchpad.onWindowGone = { [weak self] openMs in
            WisprScratchpad.onKeyStolen = nil
            self?.hotkeys.disarmKeyRedirect()
            if let openMs {
                Log.info(String(format: "🗒️ the Scratchpad existed for %.0f ms; his keys were watched throughout and went to %@",
                                openMs, name))
            }
        }
        hotkeys.armKeyRedirect(to: pid)
    }

    // MARK: - The front of the screen, and who took it

    /// **Wispr's application comes to the front when the wrap closes its note
    /// window, and the front is his.** Victor, 2026-09-14: *"in timpul dictarii
    /// la caret … am pierdut de 3 ori focusul pe aplicatia pe care eram. fix
    /// cand wisprflow pus sa transcrie"*.
    ///
    /// The log names the thief rather than guessing at it: on both of the caret
    /// dictations he lost — 05:56:01 and 05:58:38, out of Terminal — the line
    /// `the front app changed since the chord — his keys go to pid 92966, not
    /// 46446` lands in the same second as `scratchpad chord DOWN/UP`, and 92966
    /// is `com.electron.wispr-flow`. It is the close toggle doing it, not the
    /// transcription, and nothing was putting the front back: he clicked his way
    /// back by hand, three times.
    ///
    /// **This is a different loss from the one `dictation-source.md` calls the
    /// theft, and unlike that one it can be undone.** The theft takes the *key
    /// window* while the victim stays frontmost — `activate` has nothing to say
    /// to it, which is what "the theft cannot be undone" means. This takes the
    /// *front*, so the victim really is behind and activating it is exactly the
    /// right sentence.
    ///
    /// **Only after the close, never during the sentence.** Handing the front
    /// back while Wispr is still writing its note would be aiming Wispr's own
    /// insertion at his document — the failure `WisprHistory` exists because of.
    /// So it hangs off `WisprScratchpad.onCloseFinished`, which fires when the
    /// wrap is finished with the window, and it costs him nothing that the
    /// accepted "a second or two of the keyboard" did not already cost.
    private func putTheFrontBack(after reason: String) {
        guard let thief = NSWorkspace.shared.frontmostApplication,
              thief.bundleIdentifier?.hasPrefix("com.electron.wispr-flow") == true
        else { return }   // he is wherever he is; the close cost him nothing.
        let now = Date()
        frontHandbacks.removeAll { now.timeIntervalSince($0) > Self.frontHandbackWindow }
        guard frontHandbacks.count < Self.frontHandbackLimit else {
            Log.error("🪟 Wispr Flow is in front again after \(reason) — leaving it, \(Self.frontHandbackLimit) handbacks in a minute is a fight, not a fix")
            return
        }
        let mine = ProcessInfo.processInfo.processIdentifier
        let candidates = [frontBeforeLast, focusPid ?? 0, lastFrontPid]
        guard let victim = candidates.first(where: { pid in
            pid != 0 && pid != mine && pid != thief.processIdentifier
                && kill(pid, 0) == 0
                && NSRunningApplication(processIdentifier: pid)?
                    .bundleIdentifier?.hasPrefix("com.electron.wispr-flow") != true
        }), let app = NSRunningApplication(processIdentifier: victim) else {
            Log.error("🪟 Wispr Flow took the front at \(reason) and there is nobody to give it back to")
            return
        }
        frontHandbacks.append(now)
        let name = app.localizedName ?? "pid \(victim)"
        // **`activate` is not enough and measured not to be** (2026-09-14,
        // 06:13): with Wispr holding the front, `activate(options: [])` plus
        // `AXRaise`/`AXMain`/`AXFocused` on his window left Wispr exactly where
        // it was, twice — `it would not go back to Terminal — Wispr Flow is in
        // front`. A background application asking for somebody *else* to be
        // frontmost is the request macOS declines; **`AXFrontmost` on the
        // application element is the one that is granted**, because it is asked
        // with the Accessibility trust this app already has and that is the
        // grant the restriction defers to.
        let activated = app.activate(options: [])
        let axFront = AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(victim), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // **The window, not only the application** — the same pair `onKeyStolen`
        // sets, plus the raise, because an application that comes forward with
        // no main window leaves him looking at a front with no caret in it.
        if let w = Self.focusedWindow(of: victim) {
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(w, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == victim {
                Log.info("🪟 the close took the front to Wispr Flow (\(reason)) — \(name) has it back")
            } else {
                Log.error("🪟 the close took the front to Wispr Flow (\(reason)) and it would not go back to \(name) — \(front?.localizedName ?? "?") is in front (activate=\(activated), AXFrontmost=\(axFront.rawValue))")
            }
        }
    }

    /// **Close it again when the sentence is over, and check that it went.**
    ///
    /// Mandatory rather than tidy: the window Wispr opens at the end of this
    /// dictation is the thing that would silently swallow the next one. Called
    /// from `endCapture`, so it runs on every way out — delivered, dismissed,
    /// empty, timed out.
    private func closeScratchpadAfterwards() {
        WisprScratchpad.closeWhenItAppears { [weak self] appeared, gone in
            guard let self else { return }
            WisprScratchpad.endWatch()
            if gone {
                Log.info(appeared
                    ? "🗒️ the Scratchpad window opened and has been closed — the next dictation can write a note"
                    : "🗒️ no Scratchpad window appeared — nothing to close")
                return
            }
            Log.error("🗒️ THE SCRATCHPAD WINDOW WOULD NOT CLOSE — the next dictation would be transcribed and written nowhere. Falling back to the sink until it does.")
            self.scratchpadBroken = true
        }
    }

    /// **The Scratchpad mode has failed its own precondition and stands down.**
    ///
    /// Not a permanent decision and not a silent one: `POST /test/wrap-mode
    /// {"mode": "auto"}` clears it, and so does a close that works. What it must
    /// not do is go on holding a chord that writes nothing.
    private var scratchpadBroken = false {
        didSet {
            guard scratchpadBroken, !oldValue else { return }
            Log.error("🗒️ scratchpad mode stood down — the wrap is the sink until the window closes again or /test/wrap-mode says otherwise")
        }
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
        // **The last second of his sentence may still be in this app** (2026-09-14).
        // With the bridge up, what Wispr has heard lags what he said by whatever
        // is queued in the player — and a stop chord posted now ends the
        // dictation on a tail Wispr never received. So the chord waits for the
        // queue, bounded: a stuck player must not leave the microphone open.
        // Zero, and therefore a straight-through call, on every run with the
        // bridge down. → `AudioBridge.queuedSeconds`
        //
        // **The feed is cut first, and that is not an optimisation.** The meter
        // goes on capturing until `stopMeter`, which runs *after* this — so a
        // drain measured with the sink still attached is a queue being refilled
        // as fast as it empties, and the chord would never go out while he was
        // still making a sound. Detaching here also draws the line in the right
        // place: Wispr hears everything up to the stop gesture and nothing after
        // it. Idempotent, so the re-entry below costs nothing.
        meter.onBuffer = nil
        let drain = bridgeDrainSeconds
        guard drain <= 0.02 else {
            Log.info(String(format: "🔀 holding the stop for %.0f ms of his voice still in the bridge",
                            drain * 1000))
            DispatchQueue.main.asyncAfter(deadline: .now() + drain) { [weak self] in self?.stop() }
            return
        }
        switch startedMode {
        case .scratchpad:
            HotkeyTap.postWisprScratchpad(down: false)
        case .sink:
            HotkeyTap.postWisprHandsFree()
            // **The keyboard, for the moment that matters and no longer.**
            // Wispr picks the app it will insert into at the *end*; taking key
            // 1–5 ms after the stop chord was enough, 3/3.
            WisprSink.shared.onArrival = { [weak self] text, route in
                DispatchQueue.main.async { self?.sinkArrived(text: text, route: route) }
            }
            WisprSink.shared.becomeKey()
        case .off:
            HotkeyTap.postWisprHandsFree()
        }
        closeListening("the relay's own stop gesture")
    }

    func cancel() {
        // **The ✕ during the wait counts too.** Between the microphone closing
        // and the words arriving there are seconds in which the sentence is
        // still this app's to throw away — and it is exactly the stretch in
        // which Victor realises he does not want it.
        if !isRecording, !speculative, capturing {
            // **A cancel during the settle must not disarm the swallow.**
            //
            // It used to `endCapture` here, and the adversarial run found what
            // that costs: a `forward-left` 200 ms after the stop tore the
            // capture down while Wispr's ⌘V was still 300 ms from arriving, and
            // the trace shows exactly what happened next —
            // `↓ key 9 pid 81316 flags 0x20100000 — passed`. Wispr's text went
            // into TextEdit, which is the one promise this whole wrap exists to
            // keep. **Never disarm while Wispr may still paste.**
            //
            // So the capture stays armed and the sentence is *discarded on
            // arrival*: Victor is told it is cancelled now, Wispr is told to
            // dismiss, and whatever still comes — a ⌘V, a row going terminal, a
            // note — is swallowed and dropped rather than let through. The
            // Scratchpad closes with the capture, which is to say after Wispr is
            // finished with it and not before.
            discardOnArrival = true
            dismissedAt = CFAbsoluteTimeGetCurrent()
            Log.info("🗑️ cancelled while the words were in flight — the swallow stays armed until Wispr is done, and the words are dropped")
            HotkeyTap.postWisprCancel()
            // **And nothing is being waited for any more** (2026-09-14). The
            // capture stays armed because Wispr may still paste; the *phase*
            // stayed `transcribing` with it, and that is a different claim and a
            // false one — `isWaitingForWords` is what `onPasteToggle` and the
            // settle read to decide whether a sentence is still on its way, and
            // for up to thirty seconds after the cancel it told them one was.
            // The next 🔼 click was answered with *nothing to start, nothing to
            // stop* and the relay measured **never listening (8.1 s)**. The
            // swallow is armed; the sentence is gone. The two are said
            // separately now, and `pollHistory` no longer feeds the machine from
            // a row it is only listening to in order to drop it.
            state.reset("cancelled while the words were in flight — the swallow stays armed, nothing is awaited")
            armDiscardClose()
            didEnd?(.cancelled(audio: nil, duration: 0))
            return
        }
        guard isRecording || speculative else { return }
        cancelling = true
        // **Release first, then dismiss.** In Scratchpad mode the chord is held,
        // and a ⌃Escape posted with it still down is a dismiss Wispr reads while
        // it is still being told to record.
        if startedMode == .scratchpad { HotkeyTap.postWisprScratchpad(down: false) }
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
    ///
    /// - Parameter byHand: post it **as though Victor had pressed it** — `relay:
    ///   false`, so the dictation is Wispr's from the chord: ring only, nothing
    ///   swallowed, nothing delivered, `intercepting` and `relayStarted` both
    ///   false. Without it the route keeps its old behaviour, which is the
    ///   transcribe primitive the harness is written against.
    ///
    ///   The adversarial round found the two being conflated (Finding 3): the
    ///   route promised a hand-started dictation and `gestureSeen(relay: true)`
    ///   made the relay swallow Wispr's ⌘V and re-deliver the sentence itself —
    ///   `lastDelivery={via:wispr-cmdv,kind:route,to:caret}` on a run whose whole
    ///   point was that the relay would only watch. They are two different
    ///   questions and they get two different calls.
    func postStartChord(byHand: Bool = false) {
        HotkeyTap.postWisprHandsFree()
        if isRecording || speculative {
            closeListening("POST /test/wispr-handsfree — the toggle's second press")
        } else if byHand {
            gestureSeen("POST /test/wispr-handsfree {hand}", confident: true, relay: false, mode: .off)
        } else {
            // **`mode: .off`, and the wrap still on.** This route posts Wispr's
            // *hands-free* chord, so there is no held key for `stop()` to release
            // and no sink to take — but the ⌘V it will produce is the relay's to
            // swallow exactly as it was yesterday, which is the behaviour the
            // loop is written against.
            gestureSeen("POST /test/wispr-handsfree", confident: true, relay: true, mode: .off)
        }
    }

    /// **A chord this app posted for a gesture — 🔽 →, or the back click that
    /// stops it** (2026-09-18).
    ///
    /// The tap's keyboard branch cannot report these: it filters this app's own
    /// posts out by design (`backButtonStamp`), so a 🔽 → sentence reached
    /// `WisprState` through **no** witness at all — no chord, therefore no row
    /// poll, therefore never `listening`, therefore no `hearingChanged` and no
    /// ⚡ ring. With the Engine on the local model or ElevenLabs there is no
    /// second witness either: this source's `watch` is only started by
    /// `prepare()`, which is never called for a source that is not wired.
    ///
    /// **`relay: false`, always.** The sentence is Wispr's own — the relay rings
    /// for it and routes nothing, which is the 09-12 contract for this flick and
    /// is what `relayStarted` carries. `confident: true`, because this app
    /// posted the chord itself: there is no gesture to have misread. The
    /// toggle's two halves are told apart by `gestureSeen` from its own state,
    /// exactly as they are for his keyboard, so `closing` is a *description* of
    /// what the tap believed rather than an instruction.
    func noteRawChord(closing: Bool) {
        gestureSeen(closing ? "🔽 → (the stop) — Wispr's chord, posted raw"
                            : "🔽 → — Wispr's chord, posted raw",
                    confident: true, relay: false, mode: .off)
    }

    /// `POST /test/wispr {"hotkey": true}` — the speculative ring, one step
    /// earlier than the microphone.
    func simulateHotkey() {
        gestureSeen("POST /test/wispr {hotkey}", confident: true, relay: true, mode: .off)
    }

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
    /// - Parameter relay: whether **this app** asked for the dictation. A
    ///   dictation Victor starts himself is Wispr's: ring only, never
    ///   intercepted, never routed.
    /// - Parameter mode: **how the chord was posted**, which is what `stop()`
    ///   will have to undo. Nil means *the mode in force* — every gesture except
    ///   the loopback's hands-free routes, which post Wispr's own chord and so
    ///   have no key held and no sink to take.
    /// - Parameter heldPair: whether this is the **held** right ⌘⌥ pair, whose
    ///   release ends the sentence (`pushToTalkReleased`). Only the tap's
    ///   `.pushToTalk` branch passes it; every other route here is a toggle or
    ///   the relay's own, and is closed by something else.
    private func gestureSeen(_ why: String, confident: Bool, relay: Bool, mode: WrapMode? = nil,
                             heldPair: Bool = false) {
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
        // **A chord still waiting for a bare wire belongs to the sentence that
        // asked for it, and that sentence is over.** The epoch moves here and at
        // every `closeListening`; `HotkeyTap.emitScratchpad` drops a hold whose
        // epoch has moved on rather than pressing a key for a dictation nobody
        // is having.
        HotkeyTap.retireDictationEpoch()
        // The guard's counters belong to this dictation and start at zero, armed
        // or not — see `HotkeyTap.resetKeyRedirect`.
        hotkeys.resetKeyRedirect()
        // **Whose keyboard, decided here and in every mode.** The relay's own
        // menu can be in front at this instant (a spawn offers its folder list
        // on the gesture), so the frontmost application is taken only when it is
        // somebody else's, and the last one that was is the fallback.
        let front = NSWorkspace.shared.frontmostApplication
        let frontPid = front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? 0 : (front?.processIdentifier ?? 0)
        focusPid = frontPid != 0 ? frontPid
            : (Self.frontWindowOwner() ?? (lastFrontPid != 0 ? lastFrontPid : nil))
        relayStarted = relay
        startedByHeldPair = heldPair
        startedMode = relay ? (mode ?? wrapMode) : .off
        intercepting = relay && wrapWispr
        gestureAt = CFAbsoluteTimeGetCurrent()
        openedAt = Date().timeIntervalSince1970
        state.startChord(why)
        if !relay {
            Log.info("⚡ \(why) — Victor's own dictation; the ring is all the relay does with it")
        }
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
            // **Nothing else is going to release it.** This is the one path out
            // of a dictation that does not go through `closeListening`, and in
            // Scratchpad mode the chord is still down — twelve seconds of a
            // held key, then a hundred and twenty until the dead-man's switch.
            if HotkeyTap.scratchpadIsHeld { HotkeyTap.postWisprScratchpad(down: false) }
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
        startedByHeldPair = false
        // **Belt on the hold.** Every ordinary path releases the chord before it
        // gets here; this is for the ones that do not exist yet and for the one
        // that already does — Victor's own hands-free chord, read as a stop for
        // a dictation the relay opened by holding a different key.
        if HotkeyTap.scratchpadIsHeld { HotkeyTap.postWisprScratchpad(down: false) }
        // …and after the release, because the release is the one chord that must
        // still go out: any hold still queued for this sentence is now for a
        // sentence that is over, and pressing it would open Wispr's window
        // behind everything — the 57 s orphan of the adversarial round.
        HotkeyTap.retireDictationEpoch()
        // **When the relay itself stopped the last dictation**, which is what a
        // late CoreAudio *open* edge has to be told from a new one.
        lastStopAt = CFAbsoluteTimeGetCurrent()
        isRecording = false
        speculativeDrop?.cancel()
        speculativeDrop = nil
        speculative = false
        stopMeter(keep: !cancelling)
        captureFrom = CFAbsoluteTimeGetCurrent()
        Log.info(String(format: "🎙️ the microphone is closed — %@ (%.0f ms of speech)",
                        why, (captureFrom - gestureAt) * 1000))
        // The sentence is over, so the window may go — and the ten seconds the
        // keyboard guard is allowed to outlive it start counting here.
        if startedMode == .scratchpad {
            WisprScratchpad.armCloseOnSight()
            // **And nothing else may ask again.** The close is a *toggle*: a
            // second tap behind the first one closes the window and opens it
            // straight back up. `wrap-cancel` left `['Status', 'Scratchpad']`
            // behind for exactly that reason (2026-09-14) — the cancel path ran
            // `closeListening`'s close and then `endCapture`'s, three seconds
            // apart, and the second undid the first. One owner per close.
            scratchpadWindowHandled = true
            hotkeys.startKeyRedirectCountdown()
        }
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
            // The same credential the notification needs, for the same reason:
            // a poll that never saw this dictation's microphone open is
            // reporting the end of somebody else's.
            guard state.pollMs != nil else { return }
            // Victor ended the dictation from Wispr's own window, or Wispr ended
            // it itself. At most one tick late, against a notification measured
            // at up to six seconds.
            closeListening("the 100 ms poll saw the microphone close")
        }
    }

    /// **He let go of right ⌘⌥ — the push-to-talk sentence is over.**
    ///
    /// The whole of what was missing on 2026-09-18: *"nu se prinde când Wispr se
    /// oprește când apas cmd-opt și dau release la taste"*. The start of that
    /// dictation has been read off the keyboard since 2026-09-12; its end never
    /// was, and every other witness the relay has is late or conditional. The
    /// CoreAudio notification is 0–6 s behind and was absent in five of five
    /// runs; the 100 ms poll needs a `WisprWatch` that `prepare()` never started
    /// when the Engine is the local model; and Wispr's `History` row only leaves
    /// `listening` once it turns **terminal**, which is after the formatting
    /// pass — measured that morning, the row sat at `raw_transcript` and the
    /// phase stayed `listening` indefinitely, with the music off the whole time.
    /// The key going up is the same fact, free and exact.
    ///
    /// **Only for a sentence this pair started** (`startedByHeldPair`). Wispr
    /// keeps push-to-talk on its own `ptt` action (`54+61`) and its hands-free
    /// toggle on another chord entirely, so a release here is never a toggle in
    /// disguise — but a ⌘⌥ pressed for something unrelated in the middle of a
    /// hands-free sentence, or of one the relay opened, is ordinary and must not
    /// end it.
    ///
    /// **And only once the guess is confirmed.** A tap too short for Wispr to
    /// have made a row leaves this `speculative`, and *that was not a dictation*
    /// is a different claim from *the sentence is over* — `speculativeGrace`
    /// owns it and says so in its own words.
    private func pushToTalkReleased() {
        guard startedByHeldPair, isRecording else { return }
        closeListening("right ⌘⌥ released — his push-to-talk is over")
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
        // **Asked before the machine is told**, because `WisprState.notify(true)`
        // takes an `idle` machine into `listening`, and a late open edge would
        // therefore put the phase back into a sentence that is over.
        if on, !speculative, !isRecording, let why = lateOpenEdge() {
            Log.info("⚡ \(why) — a late confirmation of the sentence that is over, not a new dictation")
            return
        }
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
            // **A witness that never saw the microphone open cannot report it
            // closing** (2026-09-13, 23:56). The notification is 0–6 s late, and
            // a close belonging to the *previous* sentence arrived six seconds
            // afterwards, 600 ms into the next one, and ended it — the dictation
            // was over before a word of it was spoken. `notifyMs` is nil unless
            // this notification saw *this* dictation start, which is exactly the
            // credential the report needs.
            if isRecording, state.notifyMs == nil {
                Log.info("⚡ a mic edge closed with no matching open — it belongs to the previous dictation, ignored")
                return
            }
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

    /// **Is this open edge the last sentence's, arriving late?**
    ///
    /// Two credentials, and it needs both — the second is what keeps a dictation
    /// Victor really did start by hand from being ignored:
    ///
    /// 1. **The relay stopped the last dictation itself and nothing has been
    ///    asked for since** (`lastStopAt >= gestureAt`). A microphone that opens
    ///    after the relay closed the sentence it opened for is describing that
    ///    sentence.
    /// 2. **Wispr has created no newer row.** Wispr writes the `History` row at
    ///    the gesture, 357 ms measured, so a dictation that has really started
    ///    has a row of its own; a late notification about the old one does not.
    ///
    /// Bounded by `lateOpenGrace` — the notification has measured 0–6 s late and
    /// nothing has ever been later, so beyond twice that an open edge is a new
    /// dictation whatever the rows say. The cost of being wrong in that
    /// direction is a missing ring over a dictation the relay would not have
    /// touched anyway (*a dictation Victor starts himself is Wispr's*); the cost
    /// of being wrong the other way is the phantom cycle this exists to remove.
    private func lateOpenEdge() -> String? {
        let now = CFAbsoluteTimeGetCurrent()
        guard lastStopAt > 0, lastStopAt >= gestureAt, now - lastStopAt < Self.lateOpenGrace
        else { return nil }
        let since = (now - lastStopAt) * 1000
        // **The plainest case, and the one both attacks actually took**: the
        // capture for the sentence the relay has just stopped is still open, so
        // the words are still in flight and this edge is about them. It arrived
        // *before* the delivery in Attack 7, which is why a test written only on
        // the finished row would have missed it.
        if capturing {
            return String(format: "the mic edge opened %.0f ms after the relay's own stop, with that sentence's capture still open", since)
        }
        guard let last = historyRow ?? lastRow else { return nil }
        guard let newest = WisprHistory.newest() else {
            return String(format: "the mic edge opened %.0f ms after the relay had already stopped, and Wispr has no row at all", since)
        }
        guard newest.rowid <= last else { return nil }
        return String(format: "the mic edge opened %.0f ms after the relay had already stopped, and row %d is still Wispr's newest",
                      since, newest.rowid)
    }

    /// When the relay's own stop closed the last dictation's listening.
    private var lastStopAt: CFAbsoluteTime = 0
    /// The `History` row the last capture belonged to, kept past `endCapture` —
    /// which clears `historyRow` — because *has Wispr started anything since* is
    /// a question asked after the capture is over.
    private var lastRow: Int64?
    private static let lateOpenGrace: TimeInterval = 12

    // MARK: - The meter, which is also the corpus's recording

    private func startMeter() {
        let wav = Outbox.shotsDir.appendingPathComponent("wispr-\(Int(Date().timeIntervalSince1970)).wav")
        meterQueue.async { [weak self] in
            guard let self else { return }
            guard !self.meter.isRecording else { return }
            // **Before the recorder opens**, so no buffer is produced that the
            // bridge has not been told about: the first syllable is the one most
            // often worth carrying.
            self.markersInAudio = false
            if AudioBridge.isEnabled, self.bridge.start(format: MicRecorder.fileFormat) {
                self.meter.onBuffer = { [weak self] buffer in self?.bridge.schedule(buffer) }
            }
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
            self.meter.onBuffer = nil
            let taken = self.meter.stop()
            // **After the recorder, and after whatever it had left.** Tearing the
            // bridge down with audio still queued throws away the end of his
            // sentence — the part Wispr has not heard yet. `bridgeDrainSeconds`
            // is what the stop chord waits on for the same reason; this is the
            // same wait on the way out, bounded so a stuck player cannot hold
            // the meter's queue.
            if self.bridge.isRunning {
                let until = Date().addingTimeInterval(3)
                while self.bridge.queuedSeconds > 0.02, Date() < until {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                self.bridge.stop()
            }
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
        // **A dictation Victor started is watched and never taken.** The row
        // poll still runs — the chip and the ring want to know when Wispr is
        // done — but nothing is swallowed, nothing is read off the pasteboard
        // and nothing is delivered.
        let takes = intercepting
        sawWisprGone = 0
        wisprPidAtChord = Self.wisprMainPid
        armedAt = CFAbsoluteTimeGetCurrent()
        captureFrom = armedAt
        askedForCopy = false
        // **The change count, and deliberately not the string** (2026-09-14).
        //
        // This line used to read the pasteboard's *text* as well, to keep a
        // baseline to compare a later read against. It crashed the app on the
        // main thread, at the start of a dictation:
        //
        //     EXC_BAD_ACCESS — objc_msgSend → -[NSPasteboard _updateTypeCacheIfNeeded]
        //       → stringForType: → beginCapture → gestureSeen → start()
        //
        // Reading a pasteboard that another process is rewriting is not safe,
        // and this one runs on **every** dictation. The baseline was only ever
        // the belt behind the 2026-09-13 clipboard-restore bug — arming at the
        // start chord is what actually fixed that — so it goes, and the change
        // count, which is an integer and cannot fault, stays.
        clipboardAt = NSPasteboard.general.changeCount
        clipboardMoved = nil
        // **Armed whether or not the relay is going to take it.** The probe half
        // — which process posted what key, how long after the microphone shut —
        // is the only record of how Wispr delivers, and it is worth the same two
        // log lines in either mode. Only `swallow` differs.
        // **The ⌘V is taken in every mode, and Scratchpad mode is not the
        // exception it looked like** (2026-09-13, settled at 23:54).
        //
        // It was let through for one build, on the reasoning that Wispr's paste
        // belongs to Wispr's own note and swallowing it is this app reaching
        // into another app's conversation with itself. True while the note was
        // the delivery; false the moment the row took over and the window
        // started being closed on sight. Measured: with the window shut at the
        // release, Wispr's paste arrives ~450 ms later with nowhere of its own
        // to go, and it lands in **Victor's document** — every sentence appeared
        // twice, once lowercased from Wispr and once properly from the relay.
        //
        // With the row as the delivery there is nothing the paste is needed for,
        // so the invariant the whole wrap exists to keep — *Wispr never inserts
        // anywhere* — is simply restored. The note becomes a thinner cross-check
        // and says so when it is empty.
        if takes { hotkeys.armInjectionCapture(swallow: true) }

        // The pasteboard is the other half of the answer, and the only half in
        // the cases where the ⌘V never arrives: an Accessibility insertion, a
        // focus Wispr refuses to paste into, a keystroke that went somewhere
        // else. Polled at 20 Hz and **only while capturing** — a permanent
        // pasteboard poll is a different and much worse thing than a six-second
        // one.
        clipboardWatch?.invalidate()
        // **No pasteboard watch in Scratchpad mode.** Wispr writes the clipboard
        // and puts it straight back there too, and with nothing pasted anywhere
        // the only thing a watcher could report is the restore — which is the
        // bug that filed a Word contract as a dictation three times.
        let watchesBoard = takes && startedMode != .scratchpad
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard watchesBoard else { return }
            guard let self, self.capturing else { return }
            guard NSPasteboard.general.changeCount != self.clipboardAt else { return }
            self.clipboardWatch?.invalidate()
            self.clipboardWatch = nil
            // **Read the string now, not in 250 ms.** Wispr writes the
            // transcript, presses ⌘V and puts the previous clipboard back, and
            // the restore lands inside exactly that gap — three sentences on
            // 2026-09-13 were delivered as the clipboard Wispr had just restored.
            self.clipboardMoved = Self.pasteboardString()
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
        // **The note as it stood before he started talking**, so a Scratchpad
        // that is appended to rather than added to is still recognisable.
        scratchpadWindowHandled = false
        if startedMode == .scratchpad, let note = WisprNotes.newest() {
            priorNoteId = note.id
            priorNoteStamp = max(note.createdAt, note.modifiedAt)
            priorNoteText = note.content
        } else {
            priorNoteId = nil
            priorNoteStamp = 0
            priorNoteText = nil
        }
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
        // **A cancelled capture is not a sentence in flight, and a new gesture
        // supersedes it at once** (2026-09-14, the regression the
        // `discardOnArrival` fix left behind). The words of the old sentence
        // were thrown away by Victor; what is still owed is only that Wispr's
        // late ⌘V lands nowhere, and that survives the retirement on its own.
        if discardOnArrival { return retireDiscardedCapture() }
        if let row = historyRow, !WisprState.isTerminal(status(of: row)) {
            Log.info("wispr: a capture is still standing for row \(row) (\(status(of: row).isEmpty ? "no status yet" : status(of: row))) — the new gesture does not disarm it")
            return
        }
        endCapture(quiet: true)
    }

    /// **Retire a cancelled capture and keep only its swallow, keyed by its row.**
    ///
    /// Everything the capture *holds* goes back with it — the Scratchpad window,
    /// the keyboard guard, the sink's key window, the row poll, the deadline —
    /// because `endCapture` is the one place that lets all of them go, and the
    /// new dictation then arms its own inside the same call. What outlives it is
    /// the one promise the cancel made: Wispr may still press ⌘V for the
    /// sentence Victor threw away, and that key belongs to nobody.
    private func retireDiscardedCapture() {
        retiredDiscardRow = historyRow
        retiredDiscardUntil = CFAbsoluteTimeGetCurrent() + Self.retiredDiscardCeiling
        retiredDiscardTerminalAt = 0
        Log.info("🗑️ a new gesture supersedes the cancelled sentence — its capture is retired now"
                 + (retiredDiscardRow.map { ", and the swallow stays armed for row \($0)'s ⌘V" }
                    ?? "; Wispr never created a row for it, so there is no ⌘V to wait for"))
        endCapture(quiet: true)
        // **Armed again, because `endCapture` disarmed it and the dictation that
        // follows may not want one.** A capture the relay is not intercepting —
        // Victor's own chord, a moment after his cancel — arms no swallow at
        // all, and the old row's ⌘V would then land in his document, which is
        // the whole failure the cancel path exists to prevent.
        if retiredDiscardRow != nil { hotkeys.armInjectionCapture(swallow: true) }
        armRetiredDiscardWatch()
    }

    /// The claim is let go on the row's own evidence: terminal, plus the
    /// `pasteGrace` in which the ⌘V that follows `formatted` would have arrived.
    private func armRetiredDiscardWatch() {
        retiredDiscardTimer?.invalidate()
        retiredDiscardTimer = nil
        guard retiredDiscardRow != nil else { return }
        let t = Timer(timeInterval: Self.historyTick, repeats: true) { [weak self] _ in
            self?.pollRetiredDiscard()
        }
        retiredDiscardTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func pollRetiredDiscard() {
        guard let row = retiredDiscardRow else { return letRetiredDiscardGo("there was no row to wait for") }
        let now = CFAbsoluteTimeGetCurrent()
        guard now < retiredDiscardUntil else {
            return letRetiredDiscardGo("row \(row) produced no ⌘V within \(Int(Self.retiredDiscardCeiling)) s")
        }
        // **Asked about the row itself**, not about the newest one: by now the
        // next dictation has a row of its own on top of it.
        guard let e = WisprHistory.entry(rowid: row), WisprState.isTerminal(e.status) else { return }
        if retiredDiscardTerminalAt == 0 {
            retiredDiscardTerminalAt = now
            return
        }
        guard now - retiredDiscardTerminalAt >= Self.pasteGrace else { return }
        letRetiredDiscardGo("row \(row) is \(e.status) and no ⌘V followed it")
    }

    private func letRetiredDiscardGo(_ why: String) {
        retiredDiscardTimer?.invalidate()
        retiredDiscardTimer = nil
        retiredDiscardTerminalAt = 0
        guard retiredDiscardRow != nil else { return }
        retiredDiscardRow = nil
        Log.info("🗑️ the cancelled sentence's claim on the swallow is let go — \(why)")
        // The swallow belongs to the running capture again — or to nobody.
        if !(capturing && intercepting) { hotkeys.disarmInjectionCapture() }
    }

    /// **Close the Scratchpad as soon as the cancel has had its answer, not when
    /// the capture ends** (2026-09-14).
    ///
    /// `closeListening` already asked for the close at the stop and the window
    /// went; Wispr then **reopens** it when it writes its note, ~2 s later, and
    /// nothing was watching for that second window until `endCapture` — which a
    /// cancelled sentence does not reach until Wispr has finished transcribing
    /// the words nobody wants. Measured **3.2 s** with the window standing over
    /// his work and taking his keystrokes throughout. So the moment the cancel
    /// has its answer — the row is terminal, or the dismiss is old enough that
    /// no ⌘V can still follow it — the close is armed again.
    ///
    /// **Exactly once while one is in flight**: the close is a toggle, and the
    /// second ask re-opens what the first shut.
    private func armDiscardClose() {
        guard startedMode == .scratchpad else { return }
        discardCloseTimer?.invalidate()
        let t = Timer(timeInterval: Self.historyTick, repeats: true) { [weak self] _ in
            self?.pollDiscardClose()
        }
        discardCloseTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func pollDiscardClose() {
        guard capturing, discardOnArrival else { return endDiscardClose() }
        guard !WisprScratchpad.closeIsInFlight else { return }
        let waited = CFAbsoluteTimeGetCurrent() - dismissedAt
        var why: String?
        if let row = historyRow, let e = WisprHistory.entry(rowid: row), WisprState.isTerminal(e.status) {
            why = "Wispr's row \(row) is \(e.status)"
        } else if waited >= Self.pasteGrace {
            why = "the dismiss went out and no ⌘V can follow it"
        }
        guard let why else { return }
        endDiscardClose()
        scratchpadWindowHandled = true
        Log.info(String(format: "🗒️ %@ — closing the Scratchpad now rather than at the end of the capture (%.0f ms after the cancel)",
                        why, waited * 1000))
        WisprScratchpad.armCloseOnSight()
    }

    private func endDiscardClose() {
        discardCloseTimer?.invalidate()
        discardCloseTimer = nil
    }

    private func status(of row: Int64) -> String {
        WisprHistory.entry(rowid: row)?.status ?? ""
    }

    /// **What Wispr says about this dictation.** `status` stays empty while it
    /// works; the first non-empty value is the end of the round trip, whatever
    /// the tap saw. `formatted` waits `pasteGrace` for the ⌘V that usually
    /// follows — the ordinary paths deliver and close the capture underneath
    /// this timer — and only then takes the words from the row: Wispr put them
    /// where the focus was, by a route no tap sees, and `insertedElsewhere`
    /// lets the router decide whether that was the destination.
    private func pollHistory() {
        guard capturing else { return }
        // **The recogniser has quit and nothing is coming** (2026-09-14,
        // adversarial round 2, Finding 5). Wispr killed mid-settle left the
        // relay holding `Transcribing...` for the full 30 s of `captureTimeout`
        // before it said `No words came back` — thirty seconds of a chip
        // promising words from a process that no longer exists. Two consecutive
        // ticks, because `runningApplications` is KVO-updated and a single blank
        // reading during Wispr's own relaunch is not a death.
        let pid = Self.wisprMainPid
        if pid == 0 {
            sawWisprGone += 1
            if sawWisprGone >= 2 { return abandonForDeadWispr("it is not running") }
        } else if wisprPidAtChord != 0, pid != wisprPidAtChord {
            return abandonForDeadWispr("it is pid \(pid) now, and this sentence was given to pid \(wisprPidAtChord)")
        } else {
            sawWisprGone = 0
        }
        let wasDiscarding = discardOnArrival
        // **The note is never the delivered text in Scratchpad mode, and that is
        // now a rule rather than a default** (2026-09-14). Two runs delivered
        // `added 'qz'` — a pair of probe *keystrokes* that had landed in the note
        // — as though they were the sentence. A note that has had his typing in
        // it is not a transcript, and the row is the only thing that ever was.
        // `WT_SCRATCHPAD_DELIVER=note` is kept for the non-Scratchpad modes and
        // for looking at the other record by hand; it no longer decides anything
        // in the mode that ships.
        //
        // It was read unconditionally for one build, and that build delivered a
        // stray `z` (2026-09-13, 23:52): the window is open for the whole
        // sentence, a keystroke that lands in the note changes it, and the note
        // poll fired **13 ms after the microphone closed** — before the row was
        // even `formatted` — and shipped the one character it found. The note
        // has to be a cross-check or it is a second delivery racing the first.
        if startedMode == .scratchpad, Self.deliverFromNote, Self.noteMayDeliver,
           intercepting, !isRecording, pollNote() { return }
        guard let e = WisprHistory.newest() else { return }

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
        // …and **not for a sentence that has been cancelled**: the poll goes on
        // running so the ⌘V can be swallowed, but a row fed into the machine
        // would put the phase back into `transcribing` a tick after the cancel
        // reset it, and the next gesture would be refused all over again.
        if armedAt >= state.chordAt, !discardOnArrival { state.sawRow(e.rowid, status: e.status) }

        let took = (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000
        switch e.status {
        // **Intermediate, and they are progress rather than silence.** `""` is
        // the row as created at the gesture; `raw_transcript` and `processing`
        // were first seen on 2026-09-13 and were unknown to this switch that day,
        // so a settle sat out its whole timeout on a sentence that was arriving.
        // Bounded by `captureTimeout` and by nothing else.
        case let s where WisprState.intermediateStatuses.contains(s):
            // **…and one of them is not progress at all.** Two seconds of
            // digital silence left row 12814 in `raw_transcript` with `asrText`,
            // `formattedText` and `pastedText` all empty, **for ever** — Wispr
            // never made it terminal — and the relay sat out its whole 30 s
            // capture before saying `No words came back` (adversarial round 2,
            // Attack 12). A row with nothing in it after `silenceCeiling` is
            // Wispr having heard nothing, which is a different sentence to show
            // him and a much earlier one.
            guard !isRecording, s == "raw_transcript",
                  e.asrText.isEmpty, e.formattedText.isEmpty, e.pastedText.isEmpty,
                  took >= Self.silenceCeiling * 1000 else { return }
            Log.info(String(format: "wispr history: %@ with nothing in it %.0f s after the microphone closed — Wispr heard no speech",
                            s, took / 1000))
            endCapture(quiet: true)
            if !wasDiscarding { didEnd?(.silent("No speech was heard")) }
            return

        case "formatted", "extension_paste", "extension_other":
            // **A dictation the relay did not start is over here and nothing
            // else happens.** It was Wispr's from the chord; the row is how the
            // ring and the chip find out it is finished, and `.silent("")` is
            // *nothing worth a banner* rather than a failure.
            guard intercepting else {
                Log.info(String(format: "wispr history: %@ — Victor's own dictation, delivered by Wispr (%.0f ms)",
                                e.status, took))
                endCapture(quiet: true)
                didEnd?(.silent(""))
                return
            }
            // **In Scratchpad mode the row is the delivery and the note is the
            // cross-check** (2026-09-13, after the first working run).
            //
            // Measured on that run: the row said `formatted` **531 ms** after
            // the microphone closed, and the note was not readable until
            // **2627 ms** — Wispr writes the note when it opens its window, two
            // seconds later, and closing that window cost another 663 ms on top.
            // Waiting for the note therefore made the mode 2.8 s slower than the
            // ⌘V it replaced, for a copy of the same sentence.
            //
            // The note is where Wispr *pastes*; the row is where Wispr *writes
            // what it heard*. So the words come from the row the instant it is
            // terminal, the window is dealt with afterwards on its own time, and
            // the note is read at the end only to say whether the two agree.
            // `WT_SCRATCHPAD_DELIVER=note` goes back to waiting for the note.
            if startedMode == .scratchpad, !Self.deliverFromNote {
                deliverFromRow(e, took: took)
                return
            }
            if startedMode == .scratchpad {
                if historyFormattedAt == 0 {
                    historyFormattedAt = CFAbsoluteTimeGetCurrent()
                    Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — waiting for the Scratchpad note",
                                    e.status, took, e.e2eLatency))
                }
                return
            }
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
            // A sentence already cancelled has had its ending; a second one
            // would clear the *next* dictation's state from under it.
            if !wasDiscarding { didEnd?(.cancelled(audio: nil, duration: 0)) }
            return
        case "empty", "no_audio":
            Log.info(String(format: "wispr history: %@ — %.0f ms after the microphone closed", e.status, took))
            endCapture(quiet: true)
            if !wasDiscarding { didEnd?(.silent("No words detected")) }
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

    /// **How long a row with nothing in it may be called progress**, counted
    /// from the microphone's close. Eight seconds is Wispr's own p99 and the
    /// same number the settle gives up on, so nothing that was going to arrive
    /// is cut off by it.
    private static let silenceCeiling: TimeInterval = 8

    /// **Wispr Flow's own process, matched on the anchored executable path.**
    ///
    /// Not the bundle identifier and not the name: LaunchServices resolves both
    /// to the nested Accessibility helper at
    /// `…/Contents/Resources/swift-helper-app-dist/Wispr Flow.app` as well, so a
    /// check written on either reports Wispr running when only the helper is —
    /// the same trap `open -a "Wispr Flow"` is in *Never reintroduce* for.
    private static var wisprMainPid: pid_t {
        NSWorkspace.shared.runningApplications.first {
            $0.executableURL?.path == mainExecutable
        }?.processIdentifier ?? 0
    }
    private static var wisprMainIsRunning: Bool { wisprMainPid != 0 }
    private static let mainExecutable = "/Applications/Wispr Flow.app/Contents/MacOS/Wispr Flow"
    private var sawWisprGone = 0
    /// **Which Wispr this sentence was given to**, read at the chord.
    ///
    /// Absence is not the only way a recogniser dies, and on this rig it is not
    /// even the likely one: the harness relaunches Wispr **200 ms** after killing
    /// it, so a rule built on two consecutive absences 300 ms apart never sees
    /// the death at all — which is why `wispr-dies-mid-settle` still waited out
    /// its 30 s on the build that was supposed to have fixed it. A **different
    /// pid** is the same fact and it cannot be missed: the process this sentence
    /// was dictated into is gone, whatever is running now has never heard of it.
    private var wisprPidAtChord: pid_t = 0

    /// **Wispr is gone and the sentence went with it.** Everything this capture
    /// holds is handed back on the way out: `closeListening` releases the chord
    /// and asks the Scratchpad close, `endCapture` disarms the keyboard guard
    /// and takes the window down for good.
    private func abandonForDeadWispr(_ why: String) {
        sawWisprGone = 0
        wisprPidAtChord = 0
        Log.error("⚠️ Wispr Flow quit — the sentence is lost (\(why))")
        // **And the window the dead instance left behind.** It belongs to a
        // process that no longer exists, so nothing else is going to ask.
        WisprScratchpad.ensureClosed(reason: "Wispr Flow quit mid-sentence")
        if isRecording || speculative { closeListening("Wispr Flow quit") }
        // After the close, or `stopChord` would transition out of the `done`
        // this puts the machine in and the phase would say the sentence ended
        // normally.
        state.timedOut("Wispr Flow quit")
        let wasDiscarding = discardOnArrival
        endCapture(quiet: true)
        if !wasDiscarding { didEnd?(.silent("Wispr Flow quit — the sentence is lost")) }
    }

    /// **`WT_SCRATCHPAD_DELIVER=note`** — wait for the note rather than taking
    /// the row, which is 2.8 s slower and the behaviour of the first working
    /// build. Kept because the row and the note are two different records and
    /// the day they disagree this is how to look at the other one.
    /// Long enough for Wispr to have written the note and for the window to have
    /// been shut again — measured at 2.1 s and 0.1–0.4 s respectively.
    private static let crossCheckDelay: TimeInterval = 3.5

    /// **The note may never be delivered as text in Scratchpad mode.** A
    /// second flag rather than a deleted branch, because the note path is still
    /// the way to read Wispr's other record by hand — and because a rule that is
    /// one `guard` is a rule somebody removes by accident.
    /// `WT_SCRATCHPAD_NOTE_MAY_DELIVER=1` for a deliberate experiment.
    private static let noteMayDeliver =
        ProcessInfo.processInfo.environment["WT_SCRATCHPAD_NOTE_MAY_DELIVER"] == "1"

    private static let deliverFromNote =
        ProcessInfo.processInfo.environment["WT_SCRATCHPAD_DELIVER"]?.lowercased() == "note"

    /// **The row, delivered at `formatted`, with the window dealt with after.**
    ///
    /// The one thing that must not race is the caret paste against the
    /// Scratchpad window's keyboard grab: that window takes the key when it
    /// opens, and a paste made while it has it goes **into the note** — measured
    /// on 2026-09-13, 70 characters of the relay's own delivery appended to
    /// Wispr's notepad while the document Victor was looking at stayed empty. At
    /// `formatted` the window is normally not open yet (it opens ~2 s later with
    /// the note), so the ordinary path pastes straight away; if it *is* open —
    /// left over, or Wispr being quick — it is closed first and the words follow.
    private func deliverFromRow(_ e: WisprHistory.Entry, took: Double) {
        // **`formattedText` first in this mode**, where every other path prefers
        // `pastedText`. What Wispr *pasted* here is what it appended to its own
        // note, and an append arrives lowercased and run on — `commit and push
        // the fix.` where the recogniser's own reading is `Commit and push the
        // fix.`. The row's formatted text is the sentence; the pasted text is a
        // record of what happened to a text view.
        let words = e.formattedText.isEmpty ? e.text : e.formattedText
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.error(String(format: "wispr history: %@ with no text — waiting for the Scratchpad note instead", e.status))
            return
        }
        historyPoll?.invalidate()
        historyPoll = nil
        scratchpadWindowHandled = true
        // Everything the cross-check needs, before `endCapture` clears it.
        let priorId = priorNoteId
        let priorText = priorNoteText
        let since = openedAt

        Log.info(String(format: "wispr history: %@ %.0f ms after the microphone closed (Wispr's own e2e %.0f ms) — the row is the delivery",
                        e.status, took, e.e2eLatency))
        // **Who holds the keyboard is a log line now, not a gate** (2026-09-14).
        //
        // It used to be both: the delivery waited for Wispr's window to close,
        // because a ⌘V posted at the session while the Scratchpad has the key
        // focus lands in its note. That cost 488 ms on a good close and 3337 ms
        // on one that needed a retry, for a round trip the row had finished at
        // 400 ms. The paste is **addressed** now — `postToPid` to the app he was
        // looking at when he asked — so who holds the focus stops being this
        // delivery's business and becomes something worth saying and nothing
        // more.
        if WisprScratchpad.windowIsOpen() {
            Log.info("🗒️ the Scratchpad window is open at the delivery"
                     + (WisprScratchpad.focusOwnerIsWispr() ? " and holds the key focus" : "")
                     + " — the paste is addressed to pid \(focusPid.map(String.init) ?? "the caret"), so it goes to him either way")
        }
        deliver(reason: "Wispr's History row (scratchpad)", via: "wispr-history",
                delivery: .route, text: words)
        // The window is already being shut on sight — armed at the release. All
        // that is left here is the second opinion, once the note has had time to
        // be written.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.crossCheckDelay) {
            Self.crossCheckNote(delivered: words, priorId: priorId, priorText: priorText, since: since)
        }
    }

    /// **Did Wispr's note say the same thing as Wispr's row?**
    ///
    /// They are two records of one sentence and they are not the same record:
    /// the row is what the recogniser produced, the note is what its paste put
    /// on screen — and the paste has been seen to arrive lowercased and without
    /// the final stop (` commit and push the fix ` against
    /// `Commit and push the fix.`). Punctuation and case are therefore normalised
    /// away before comparing, and only a **material** difference is worth a line:
    /// a disagreement about the words is the wrap delivering something other
    /// than what Wispr heard, which is the failure this whole mode exists to
    /// avoid.
    private static func crossCheckNote(delivered: String, priorId: String?, priorText: String?,
                                       since: TimeInterval) {
        guard let note = WisprNotes.newest(since: since - 2) else {
            Log.info("🗒️ cross-check: Wispr wrote no note for this dictation")
            return
        }
        var added = note.content
        if note.id == priorId, let prior = priorText, !prior.isEmpty {
            var cut = added.startIndex
            var p = prior.startIndex
            while cut < added.endIndex, p < prior.endIndex, added[cut] == prior[p] {
                cut = added.index(after: cut)
                p = prior.index(after: p)
            }
            added = String(added[cut...])
        }
        func plain(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let a = plain(added)
        let b = plain(delivered)
        if a == b {
            Log.info("🗒️ cross-check: the note and the row agree (\(added.trimmingCharacters(in: .whitespacesAndNewlines).count) chars in the note)")
        } else if a.isEmpty {
            // The ordinary case since the ⌘V is swallowed: Wispr's paste never
            // reached its own note, so there is nothing to compare against.
            Log.info("🗒️ cross-check: the note added nothing — the paste that would have filled it was taken, and the row is the record")
        } else {
            Log.error("🗒️ cross-check: the note and the row DISAGREE — note \(added.debugDescription) vs row \(delivered.debugDescription)")
        }
    }

    /// **Wispr's Scratchpad note, which under `WT_SCRATCHPAD_DELIVER=note` is
    /// the whole delivery.**
    ///
    /// - Returns: whether the sentence was delivered, so the caller can stop.
    private func pollNote() -> Bool {
        guard let note = WisprNotes.newest(since: openedAt - 2) else { return false }
        let stamp = max(note.createdAt, note.modifiedAt)
        // A **new** note, or the one that was there written to again — the
        // Scratchpad is a notepad and nothing promises Wispr will keep adding
        // files rather than lines.
        let isThisOne = note.id != priorNoteId || stamp > priorNoteStamp
        let text = newPortion(of: note)
        guard isThisOne, !text.isEmpty else { return false }
        Log.info(String(format: "🗒️ wispr scratchpad: note %@ (%@) — %d chars, %.0f ms after the microphone closed",
                        String(note.id.prefix(8)),
                        note.versionSource.isEmpty ? "no version" : note.versionSource,
                        text.count, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
        // **Close the window before delivering, not after** (2026-09-13, 23:29).
        // Wispr's Scratchpad window takes the keyboard when it opens, and it
        // opens when the note is written — so a `pasteText` fired the moment the
        // note appears goes **into the note**, which is exactly what happened:
        // the relay's own 70 characters were appended to the Scratchpad and the
        // TextEdit document Victor was looking at stayed empty. The words are
        // already read; the window goes first and the caret gets them after.
        historyPoll?.invalidate()
        historyPoll = nil
        scratchpadWindowHandled = true
        WisprScratchpad.closeWhenItAppears { [weak self] appeared, closed in
            guard let self, self.capturing else { return WisprScratchpad.endWatch() }
            WisprScratchpad.endWatch()
            if closed {
                Log.info(appeared
                    ? "🗒️ the Scratchpad window is closed — delivering the words to the caret"
                    : "🗒️ no Scratchpad window to close — delivering the words to the caret")
            } else {
                Log.error("🗒️ THE SCRATCHPAD WINDOW WOULD NOT CLOSE — it has the keyboard, so these words would land in the note. Falling back to the sink for the next dictation.")
                self.scratchpadBroken = true
            }
            self.deliver(reason: "Wispr's Scratchpad note", via: "wispr-notes",
                         delivery: .route, text: text)
        }
        return true
    }

    /// **Only what this dictation added.**
    ///
    /// A new note is the whole sentence; a note Wispr appended to is the
    /// notepad, and the sentence is what is on the end of it. Compared against
    /// the text captured at the gesture rather than against the version row,
    /// because a `typed` version carries the accumulated note and not the
    /// increment.
    private func newPortion(of note: WisprNotes.Note) -> String {
        let full = note.content
        if note.id == priorNoteId, let prior = priorNoteText, !prior.isEmpty {
            // The common prefix rather than `hasPrefix`, so a note Wispr
            // reformatted at the front still yields its tail instead of the lot.
            var cut = full.startIndex
            var p = prior.startIndex
            while cut < full.endIndex, p < prior.endIndex, full[cut] == prior[p] {
                cut = full.index(after: cut)
                p = prior.index(after: p)
            }
            let tail = String(full[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { return tail }
        }
        let version = note.versionContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? full.trimmingCharacters(in: .whitespacesAndNewlines) : version
    }

    /// **The sink caught it** — the emergency path, and the only one in which
    /// this app holds Victor's keyboard for a moment.
    private func sinkArrived(text: String, route: String) {
        guard capturing, startedMode == .sink else { return }
        WisprSink.shared.restoreFocus()
        WisprSink.shared.onArrival = nil
        Log.info(String(format: "🧪 wispr sink caught the delivery via %@ — %d chars, %.0f ms after the microphone closed",
                        route, text.count, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
        deliver(reason: "the sink (\(route))", via: "wispr-sink", delivery: .route, text: text)
    }

    /// Wispr pressed ⌘V. Under the wrap the tap has already eaten it, so the
    /// words are nowhere yet and this is the whole delivery.
    private func injected(from process: String) {
        // **The cancelled sentence's ⌘V, arriving after its capture was
        // retired** (2026-09-14). It is keyed by the row it was armed for, and
        // it is checked before `capturing` on purpose: the capture running now
        // belongs to the *next* dictation, and this key is not its delivery.
        if let row = retiredDiscardRow {
            Log.info(String(format: "🗑️ ⌘V from %@ belongs to cancelled row %d — swallowed and dropped", process, row))
            letRetiredDiscardGo("its ⌘V arrived and went nowhere")
            return
        }
        guard capturing else { return }
        if discardOnArrival {
            Log.info("🗑️ ⌘V from \(process) after the cancel — swallowed and dropped; the capture closes now")
            endCapture(quiet: true)
            return
        }
        guard intercepting else { return }
        // **Taken and dropped.** In Scratchpad mode the words are already the
        // row's; this key exists only so that it cannot land anywhere, and the
        // line is the probe's record of Wispr still delivering the way it did.
        guard startedMode != .scratchpad else {
            Log.info(String(format: "⌘V from %@ — %.0f ms after the microphone closed (taken and dropped; the row is the delivery)",
                            process, (CFAbsoluteTimeGetCurrent() - captureFrom) * 1000))
            return
        }
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
        // Nothing was ever going to come back for a dictation this app did not
        // start, and a banner about it would be the relay complaining that
        // another app's tool worked.
        guard intercepting else {
            Log.info("wispr: Victor's own dictation is over and the relay took nothing from it")
            endCapture(quiet: true)
            didEnd?(.silent(""))
            return
        }
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
        if discardOnArrival {
            Log.info("🗑️ nothing came back for the cancelled sentence within \(Int(Self.captureTimeout)) s — closing the capture")
            endCapture(quiet: true)
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
        // **Cancelled, and the words arrived anyway.** They were swallowed on
        // the way in, so they are nowhere; this is the moment to say so and let
        // the capture — and the Scratchpad with it — go.
        if discardOnArrival {
            let count = (given ?? clipboardMoved ?? "").count
            Log.info("🗑️ \(reason) arrived after the cancel — \(count) chars dropped, and the capture can close now")
            endCapture(quiet: true)
            return
        }
        // The one gate that says *these words are the relay's to route*. Every
        // caller is already behind it; it is here because the cost of one of
        // them ever not being is a sentence Victor spoke into another app
        // arriving in an agent's terminal.
        guard intercepting else { return }
        // The string as it stood when the pasteboard first moved, when that is
        // what this delivery is about — see `clipboardMoved`.
        let fromBoard = clipboardMoved ?? Self.pasteboardString()
        let text = (given ?? fromBoard ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                    via: via,
                    // Only where the recogniser may have moved the focus under
                    // the sentence; every other path means *the caret*.
                    focusPid: self.startedMode == .scratchpad ? self.focusPid : nil,
                    markersInAudio: self.markersInAudio,
                    engineLabel: "Wispr Flow"))
                self.didEnd?(.delivered)
            }
        }
    }

    private func endCapture(quiet: Bool) {
        guard capturing else { return }
        capturing = false
        // **Unless a cancelled row still has a claim on it** — the swallow is
        // the one thing that outlives a retired capture, and disarming it here
        // for even the turn it takes to arm the next one is a window in which
        // Wispr's ⌘V for the sentence Victor cancelled reaches his document.
        if retiredDiscardRow == nil { hotkeys.disarmInjectionCapture() }
        clipboardWatch?.invalidate()
        clipboardWatch = nil
        clipboardMoved = nil
        historyPoll?.invalidate()
        historyPoll = nil
        // **Kept past the capture**, because *has Wispr started anything since*
        // is asked after it — see `lateOpenEdge`.
        if let row = historyRow { lastRow = row }
        historyRow = nil
        priorRow = nil
        priorRowWasOpen = false
        priorNoteId = nil
        priorNoteStamp = 0
        priorNoteText = nil
        discardOnArrival = false
        endDiscardClose()
        // **Never leave the sink holding his keyboard.** Every ordinary sink
        // delivery restores focus on arrival; this is the path where nothing
        // arrived and the capture timed out.
        if startedMode == .sink {
            WisprSink.shared.onArrival = nil
            if WisprSink.shared.isKey { WisprSink.shared.restoreFocus() }
            WisprSink.shared.close()
        }
        // **And the window Wispr just opened**, which is the next dictation's
        // precondition and not this one's housekeeping.
        //
        // **Whatever happened**, and that word is the fix (2026-09-14). This
        // read `!scratchpadWindowHandled`, and the flag is claimed at the
        // *release* — so a dictation that came back with nothing had already
        // marked the window as somebody else's problem, and nobody else picked
        // it up: the runner watched it stand open for three seconds after
        // `No words came back`, with his keystrokes going into the note the
        // whole time. A sentence Wispr never finished is exactly when the window
        // and the keyboard are most owed back, not least.
        if startedMode == .scratchpad {
            // Idempotent, and the guard must never outlive the capture.
            hotkeys.disarmKeyRedirect()
            // **A capture retired by a gesture leaves the window to that
            // gesture** (2026-09-14). `holdScratchpad` owns the precondition —
            // it checks the window and closes it before it holds the chord — and
            // a close started here would be the second half of a toggle behind
            // that one, which re-opens what the first shut.
            if isRecording || speculative {
                scratchpadWindowHandled = true
                Log.info("🗒️ the next dictation is already opening — its own precondition closes the window, not this capture")
            }
            // **Unless one is already being asked for**, which the cancel path
            // now does as soon as Wispr is finished rather than here — and a
            // second ask behind the first is the toggle re-opening the window.
            else if WisprScratchpad.closeIsInFlight {
                scratchpadWindowHandled = true
                Log.info("🗒️ a close is already in flight — not asking a second time (it is a toggle)")
            } else if !scratchpadWindowHandled || WisprScratchpad.windowIsUp {
                scratchpadWindowHandled = true
                closeScratchpadAfterwards()
            }
        }
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
