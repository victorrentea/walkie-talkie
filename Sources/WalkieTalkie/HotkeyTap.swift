import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Security
import VictorMacKit

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(ptr).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

/// **This tap watches the keyboard and nothing else.**
///
/// It used to own most of the mouse: the wheel carried the dictation, a hold on
/// it cancelled, chords with the left and right buttons bound and unbound, and
/// the two side buttons took a screenshot and drove Replace Wispr. On
/// 2026-09-09 all of it moved onto the keyboard, and the reason was measurement
/// rather than taste — see *The side buttons speak in function keys* in
/// CLAUDE.md.
///
/// The short of it: the M650's side buttons are **diverted inside the mouse**.
/// Held, clicked, with Logi Options+ running or killed outright, they reach
/// neither this tap nor the raw HID report — on Bluetooth LE the diverted press
/// leaves over Logitech's own GATT service, which is not the HID path. Every
/// branch here that waited for `otherMouseDown` on buttons 4 and 5 was
/// unreachable code describing a mouse that does not exist.
///
/// What does arrive is what Options+ *chooses* to send. Its custom gestures emit
/// a keystroke per direction, so each side button now speaks five sentences —
/// click, and held-while-moving in four directions — as ⌃⌥⌘ + a function key.
/// Those are ordinary key events, indistinguishable from typed ones bar the
/// chord, and this tap reads them as such.
///
/// **The wheel is handed back.** It could still be taken and deliberately is
/// not: it is the middle click that closes a tab in Chrome and VS Code, and
/// borrowing it for the hours a terminal stays bound was the standing price of
/// the old design. That price is now zero.
///
/// **One exception, and it costs nothing that price was about**: a wheel
/// *drag* made while a dictation is running selects a region of the screen
/// (`areaDrag`). A click is still a click — the press goes straight past this
/// tap in both modes and Chrome closes its tab — and only once the hand has
/// travelled past `areaDragThreshold` is anything taken.
///
final class HotkeyTap {

    /// The cursor at the instant of the gesture — what he was pointing at.
    var onScreenshot: ((NSPoint) -> Void)?

    /// **The wheel, dragged while dictating: a region instead of the display.**
    /// The corner the drag started from, and the moment the wheel went down —
    /// which is the moment the picture belongs to, exactly as the shutter's
    /// `takenAt` is the press and not the subprocess.
    var onAreaShot: ((NSPoint, Date) -> Void)?

    /// **The wheel came up and this tap ate the event.** The selection is
    /// finished by the button, and the overlay watches the button through
    /// session state — which a swallowed release never reaches, so it would
    /// otherwise sit there dimming the screen with the finger long since up.
    /// Measured, on the first run of this gesture.
    var onAreaEnd: (() -> Void)?

    /// The wheel, clicked on its own — **or ⌘⌃D**: start the recording, or end
    /// the one that is open. A toggle and not a push-to-talk — a dictation at an agent runs to a
    /// minute or more, and a button held for a minute is a hand that cannot do
    /// anything else, including take the screenshots the same minute is for.
    var onLocalToggle: (() -> Void)?





    /// **The forward side button, in Replace Wispr mode** — open the microphone,
    /// or close the one that is open and paste what was said at the caret. See
    /// `AppDelegate.replaceWispr`: it is the mode in which the relay stops being
    /// a way to talk to an agent and becomes a way to type.
    ///
    /// It consults **only** the mode flag — not `localCapture`, not `bound`. A
    /// dictation that is going to the caret carries its own destination, exactly
    /// as the spawn chord does, so *Unbound is inert* has nothing to say about it.
    var onPasteToggle: (() -> Void)?

    /// The wheel held down **while a dictation is running** — throw it away.
    /// Same verdict as the menu's Cancel Dictation, and the same verdict as
    /// pressing Cancel on the panel a moment later, without waiting for the model
    /// to transcribe something already known to be unwanted.
    var onLocalCancel: (() -> Void)?

    /// **Wispr Flow is probably about to start listening** — its own start
    /// gesture, seen on the wire, ahead of any microphone opening.
    ///
    /// `WisprWatch`'s CoreAudio edge is the *truth* and stays the thing the ring
    /// is confirmed on, but it is not the *first* thing: between Victor's finger
    /// and `kAudioProcessPropertyIsRunningInput` sits Electron waking up, an
    /// overlay window and a device open, and he can see the gap. The keystroke
    /// that asks for it is the earliest observable moment there is, and this app
    /// already has every key event in its hands.
    ///
    /// Both of Wispr Flow's start gestures, read out of its own
    /// `~/Library/Application Support/Wispr Flow/config.json`
    /// (`prefs.user.shortcuts`, key = keycodes joined by `+`):
    ///
    /// | shortcut | code | what |
    /// |---|---|---|
    /// | `49+59+63` | `popo` | fn ⌃ Space — the hands-free toggle (`postWisprHandsFree` posts exactly this) |
    /// | `54+61` | `ptt` | right ⌘ + right ⌥ held — push-to-talk |
    ///
    /// **Watched, never taken**: both go straight back out. This is a guess and
    /// is labelled one — `AppDelegate` drops the ring again if no microphone
    /// opens within `wisprSpeculativeGrace`.
    ///
    /// **Which gesture it was travels with it** (`WisprStart`, 2026-09-18) rather
    /// than a `why` string and a `confident` flag. The two are not two spellings
    /// of one thing — one is a toggle and the other a hold — and the source has
    /// to be able to tell them apart later, when the pair comes back up.
    var onWisprMaybeStarting: ((WisprStart) -> Void)?

    /// **This app has just posted Wispr's hands-free chord itself** (2026-09-18)
    /// — 🔽 →, or the back click that stops what it started.
    ///
    /// `onWisprMaybeStarting` cannot carry these: it is raised by the keyboard
    /// branch, which **deliberately ignores this app's own posts**
    /// (`backButtonStamp`, 2026-09-13 — otherwise `postWisprHandsFree` hands the
    /// source its own start back as a stop a millisecond later). The consequence
    /// nobody had noticed until Victor asked for the ring: a 🔽 → dictation is
    /// invisible to `WisprState`. There is no chord, so the row poll never runs,
    /// so the machine never reaches `listening`, so `hearingChanged` never fires
    /// — and with the Engine on anything but Wispr, the only other witness (this
    /// source's `watch`) is never started either. The flick opened a microphone
    /// and nothing on screen said so.
    ///
    /// So the post announces itself, straight to the source, which is what the
    /// stamp was protecting against when it came back round *through the tap*.
    /// `closing` says which half of the toggle it is; the source decides
    /// anyway, from its own state, exactly as it does for his keyboard.
    var onWisprRawChord: ((Bool) -> Void)?

    /// **Which of Wispr Flow's two start gestures was seen**, and the whole of
    /// what the difference between them costs.
    ///
    /// They are not two spellings of one thing: `popo` is a **toggle** and `ptt`
    /// is a **hold**, which is why only the second has an end the keyboard can
    /// report (`onWisprPushToTalkReleased`). Carried as a value rather than as a
    /// string and a bool, because the release has to be paired with *its own*
    /// press — a ⌘⌥ pressed for something else in the middle of a hands-free
    /// sentence must not end it.
    enum WisprStart {
        /// `49+59+63` — fn ⌃ Space, Wispr's hands-free toggle. `postWisprHandsFree`
        /// posts exactly this.
        case handsFree
        /// `54+61` — right ⌘ + right ⌥, held. Victor's commonest dictation.
        case pushToTalk

        var why: String {
            switch self {
            case .handsFree: return "fn ⌃ Space — Wispr hands-free"
            case .pushToTalk: return "right ⌘⌥ — Wispr push-to-talk"
            }
        }

        /// Whether the gesture is unambiguous. `fn ⌃ Space` is — nothing else on
        /// this Mac claims it, and this app posts exactly it. The push-to-talk
        /// pair is not: it is two modifiers and nothing else, so it also fires on
        /// a ⌘⌥ Victor pressed for something entirely different. The source
        /// spends a whole dictation's opening on the first and only a beacon on
        /// the second.
        var isConfident: Bool { self == .handsFree }
    }

    /// **The push-to-talk pair went back up — that sentence is over.**
    ///
    /// The one end of a Wispr dictation that is *free* to observe, and the one
    /// the relay was missing: Victor holds right ⌘⌥, talks, lets go, and until
    /// 2026-09-18 nothing told the relay so. Everything else it has is late or
    /// conditional — the CoreAudio notification is 0–6 s behind and sometimes
    /// absent, the 100 ms poll needs a started `WisprWatch`, and Wispr's own
    /// `History` row only says *listening is over* once it turns terminal, which
    /// is after the formatting pass. The keyboard says it at the instant it
    /// happens, for nothing.
    ///
    /// Fired on the falling edge whatever is or is not running: *whose* sentence
    /// this ends — if any — is the source's question, not the tap's.
    /// `54+61` is Wispr's dedicated `ptt` action and its hands-free toggle lives
    /// on a different chord entirely (`49+59+63`), so a release here is never a
    /// toggle in disguise.
    var onWisprPushToTalkReleased: (() -> Void)?

    /// **Wispr Flow's dismiss chord, typed by Victor** — `53+59`, ⌃Escape —
    /// seen on the wire (2026-09-12). A dictation he throws away from Wispr's
    /// side pastes nothing, and until this the relay only found that out by
    /// waiting `settleTimeout` for a ⌘V that was never coming, with the ring's
    /// lightning on screen the whole time — *"tooltipul dispare relativ repede
    /// (corect), dar fulgerele rămân pe ecran încă multe secunde în plus
    /// (greșit)"*. Watched, never taken: the key goes on to Wispr. This app's
    /// own `postWisprCancel` carries `backButtonStamp` and is not reported —
    /// the source already knows about that one.
    var onWisprMaybeCancelling: (() -> Void)?

    /// Whether Wispr's push-to-talk pair is currently held, so the ring is asked
    /// for on the edge rather than on every `flagsChanged` while it is down.
    private var wisprPTTDown = false

    // ── Another app's delivery, watched and (when wrapped) taken ─────────────

    /// **Wispr Flow pressed ⌘V** — its whole output interface, seen here before
    /// the front app sees it. The string is the posting process's name, for the
    /// log. Fired on the tap's own thread; the source hops to main.
    ///
    /// This is the deleted `blockInjection` coming back with a different job.
    /// The old one swallowed a paste so the relay could substitute a transcript
    /// it had read out of Wispr's **database**; that rule (2026-08-29) stands and
    /// nothing here reads a file of Wispr's. What is read is the **pasteboard**,
    /// which is where Wispr itself puts the sentence a millisecond before it
    /// presses this key — public, and the same place `pasteText` puts its own.
    var onInjectedPaste: ((String) -> Void)?

    /// Arm the window in which another app's paste is expected.
    ///
    /// - Parameter swallow: take the ⌘V (the wrap) or merely report it. Armed in
    ///   both modes, because the *probe* half — which process posted what key,
    ///   how long after the microphone shut — is the only record of how Wispr
    ///   delivers, and it is worth the same two log lines either way.
    func armInjectionCapture(swallow: Bool) {
        stateLock.lock()
        injectionArmed = true
        injectionSwallows = swallow
        injectionProbeLeft = Self.injectionProbeLines
        stateLock.unlock()
    }

    // ── Victor's own keys, while another app's window has stolen the focus ───

    /// **Send real keystrokes to the app he is looking at**, for as long as
    /// Wispr's Scratchpad window is up.
    ///
    /// Measured by the loop on 2026-09-13: **the Scratchpad window becomes key
    /// without its app becoming frontmost.** `NSWorkspace.frontmostApplication`
    /// said TextEdit for the whole run; a `z` typed 1.5 s after the stop gesture
    /// went into Wispr's note, was picked up as part of the newly added portion,
    /// and was delivered to the bound agent **inside the sentence** — while the
    /// document Victor was looking at stayed empty. That is his exact worry, and
    /// it is not a theoretical one.
    ///
    /// So for the few hundred milliseconds the window is up, a key that came
    /// from **real hardware** (pid 0) is taken here and re-posted with
    /// `postToPid` to the application that was frontmost when he stopped
    /// talking. Wispr's own synthetic keys carry its pid and are never touched;
    /// this app's carry `backButtonStamp` and are never touched either.
    ///
    /// **Two hard limits, because swallowing real keys is the most dangerous
    /// thing in this file.** It is armed only while the window is actually
    /// observed to be open — a few hundred milliseconds, measured — and it
    /// expires on its own after `redirectCeiling` whatever anyone forgets.
    /// `WT_SCRATCHPAD_REDIRECT_KEYS=0` turns it off.
    /// **Zeroed at the chord, whether or not the guard then arms.** The loop read
    /// `keys = 5` on runs where nothing had been redirected at all — the counts
    /// and the target were the *previous* dictation's, because only a successful
    /// arm reset them, and a run that never armed inherited them wholesale.
    func resetKeyRedirect() {
        stateLock.lock()
        redirectPid = 0
        redirectTarget = 0
        redirectUntil = 0
        redirectCount = 0
        redirectPassed = 0
        redirectSeen = 0
        redirectAX = 0
        stateLock.unlock()
    }

    func armKeyRedirect(to pid: pid_t) {
        guard Self.redirectEnabled, pid > 0 else {
            Log.error("⌨️ the keyboard guard did NOT arm — "
                      + (Self.redirectEnabled ? "no application to give his keys to" : "WT_SCRATCHPAD_REDIRECT_KEYS=0"))
            return
        }
        stateLock.lock()
        redirectPid = pid
        redirectTarget = pid
        // **No countdown while he is still talking.** A dictation runs to a
        // minute or more; the ten seconds is measured from the release, where
        // it means *the window should have gone by now*.
        redirectUntil = CFAbsoluteTimeGetCurrent() + Self.redirectDictationCeiling
        redirectCount = 0
        redirectPassed = 0
        redirectSeen = 0
        redirectAX = 0
        stateLock.unlock()
        Log.info("⌨️ his keys are watched, and go to pid \(pid) whenever Wispr's Scratchpad holds the focus")
    }

    /// The sentence is over: from here the arming has ten seconds to be taken
    /// down by the window actually closing.
    func startKeyRedirectCountdown() {
        stateLock.lock()
        if redirectPid != 0 { redirectUntil = CFAbsoluteTimeGetCurrent() + Self.redirectCeiling }
        stateLock.unlock()
    }

    func disarmKeyRedirect() {
        stateLock.lock()
        let n = redirectCount
        let passed = redirectPassed
        let was = redirectPid
        redirectPid = 0
        redirectUntil = 0
        stateLock.unlock()
        guard was != 0 else { return }
        Log.info("⌨️ keys are unwatched again — \(n) redirected to pid \(was), \(passed) passed through")
    }

    /// For `GET /test/state`, and it answers five separate questions because one
    /// field answering all of them was unreadable after the fact. **The pid it
    /// was aimed at survives the disarm, and the counts are this dictation's.**
    ///
    /// `seen` is every real key the guard looked at; the three below it are what
    /// became of them and must add up to it.
    var keyRedirect: (armed: Bool, pid: pid_t, seen: Int, ax: Int, key: Int, passed: Int) {
        stateLock.lock(); defer { stateLock.unlock() }
        return (redirectPid != 0 && CFAbsoluteTimeGetCurrent() < redirectUntil,
                redirectTarget, redirectSeen, redirectAX, redirectCount, redirectPassed)
    }

    private var redirectPid: pid_t = 0
    /// The pid the guard was aimed at, kept after the disarm so a test can read
    /// *who was protected* rather than *is it still running*.
    private var redirectTarget: pid_t = 0
    private var redirectUntil: CFAbsoluteTime = 0
    private var redirectCount = 0
    private var redirectPassed = 0
    private var redirectSeen = 0
    private var redirectAX = 0
    /// Ten seconds **from the release**. By then the window has either gone or
    /// something is wrong, and this is the number that makes a forgotten disarm
    /// a nuisance rather than a Mac whose keyboard has stopped working.
    private static let redirectCeiling: TimeInterval = 10
    /// While he is still talking there is no countdown worth running — a
    /// dictation aimed at an agent goes to a minute or more. Five minutes is the
    /// backstop for a `stop()` that never arrived at all.
    private static let redirectDictationCeiling: TimeInterval = 300
    /// **On by default since 2026-09-14, and the default is the measurement.**
    ///
    /// The suite, run alone under its own lock: **all three `wrap-*` scenarios
    /// 7/7 letters into the victim at every offset** — including the two typed
    /// while the clip was playing — none in Wispr's note, none inside the
    /// delivered sentence, `redirectedAX=5`, deliveries at 12–18 ms.
    ///
    /// Every earlier reading that said otherwise was taken while two harness
    /// instances were typing into the same document at once, which is also what
    /// produced the doubled letters and the two-pid traces.
    /// `WT_SCRATCHPAD_REDIRECT_KEYS=0` turns it off.
    /// A `var`, and settable at runtime (`POST /test/ax-insert {"redirect": …}`),
    /// for the same reason `axInsert` is: an installed app does not inherit a
    /// shell's environment, and a default that is supposed to be decided by
    /// measurement has to be measurable without a rebuild.
    static var redirectEnabled =
        ProcessInfo.processInfo.environment["WT_SCRATCHPAD_REDIRECT_KEYS"] != "0" {
        didSet {
            guard redirectEnabled != oldValue else { return }
            Log.info("⌨️ the keyboard guard is \(redirectEnabled ? "armed — his keys are taken while Wispr's window is up" : "off — his keys pass through untouched")")
        }
    }

    /// **Insert printable characters through Accessibility — off by default, and
    /// the default is the measurement** (2026-09-14).
    ///
    /// The reasoning for it is sound and is written out at `insertViaAX`: a key
    /// cannot reach an application with no key window, and `AXSelectedText`
    /// needs none. What the run said is that the *place* is wrong. An
    /// `AXUIElementCopyAttributeValue` is a synchronous round trip into another
    /// application, and this code runs **inside the event tap's callback** —
    /// where a slow answer stalls every keystroke on the Mac and macOS may
    /// disable the tap outright. Measured once: the run that switched it on
    /// produced a single trace line and then silence, and the dictation never
    /// finished at all.
    ///
    /// Moving it off the tap thread made it *work sometimes*, and sometimes is
    /// the finding. Measured 2026-09-14 02:20, both scenarios, guard on:
    ///
    /// | | `wrap-spawn` | `wrap-bound` |
    /// |---|---|---|
    /// | letters in the victim | **7/7** | **0/7** |
    /// | `redirectedAX` | 5 | 8 |
    /// | AX reported | success, 1–5 ms | **success, 1–5 ms** |
    ///
    /// **`AXUIElementSetAttributeValue` returned `.success` eight times and
    /// inserted nothing.** Two of those probes were sampled with the victim
    /// showing `NO FOCUSED ELEMENT` — so the element the insert went to was one
    /// the application had already let go of, and AX said yes to writing into it.
    /// A delivery route that cannot tell a success from a silent loss is not one
    /// to leave armed over Victor's typing, whatever it manages in the easy case.
    /// `WT_SCRATCHPAD_AX_INSERT=1`, or `POST /test/ax-insert`.
    ///
    /// The crash that made this look impossible for three runs was **not** the
    /// insertion at all — it was `TISGetInputSourceProperty` inside `translate`,
    /// which asserts the main thread and traps. See `refreshKeyboardLayout`.
    /// `WT_SCRATCHPAD_AX_INSERT=1` at launch, or `POST /test/ax-insert` at any
    /// moment — the second because an installed app does not inherit a shell's
    /// environment, and deciding a default by measurement needs the measurement
    /// to be takeable without a rebuild.
    static var axInsert = ProcessInfo.processInfo.environment["WT_SCRATCHPAD_AX_INSERT"] != "0" {
        didSet {
            guard axInsert != oldValue else { return }
            Log.info("⌨️ printable keys go in through \(axInsert ? "Accessibility, on its own queue" : "postToPid, best effort")")
        }
    }

    // ── `WT_KEY_TRACE=1` — every keyboard event, and what became of it ───────

    /// **Every keyboard event this tap sees, and the decision it made**, for the
    /// one question that three nights of inference could not settle: *who is
    /// eating his keystrokes.*
    ///
    /// Off by default and deliberately not clever. It logs a **keycode**, the
    /// posting process and the verdict — never a character, because a log that
    /// records what he typed is a log that must not exist. One line per event
    /// for the length of a dictation is a few dozen lines; the alternative is
    /// another night of reading outcomes backwards.
    ///
    /// A line with no matching verdict is an event that reached the end of
    /// `handle` untouched — `passed` says so explicitly.
    /// `WT_KEY_TRACE=1` at launch, or `POST /test/key-trace {"on": true}` at any
    /// moment — the second because an installed app started by LaunchServices
    /// does not inherit a shell's environment, and a debugging aid nobody can
    /// switch on is not one.
    static var keyTrace = ProcessInfo.processInfo.environment["WT_KEY_TRACE"] == "1" {
        didSet {
            guard keyTrace != oldValue else { return }
            Log.info("⌨️trace \(keyTrace ? "on — every keyboard event and what became of it" : "off")")
        }
    }

    /// **The modifiers the session believes are held**, by name — `GET
    /// /test/state.sessionFlags`.
    ///
    /// `CGEventSource.flagsState(.combinedSessionState)` reports whatever the
    /// last event's flags said, which is why a poster that stamps a modifier on
    /// a key-up and posts nothing after leaves the whole session believing that
    /// modifier is down. It self-heals on the next real key, which is why it has
    /// never been reported and has had to be found four times.
    static func sessionModifierNames() -> [String] {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var out: [String] = []
        if flags.contains(.maskCommand) { out.append("command") }
        if flags.contains(.maskAlternate) { out.append("option") }
        if flags.contains(.maskControl) { out.append("control") }
        if flags.contains(.maskShift) { out.append("shift") }
        if flags.contains(.maskSecondaryFn) { out.append("fn") }
        return out
    }

    /// **The modifiers, and the two keys that can each be holding one down.**
    /// `CGEventFlags` has no names for *which* ⌘ — the device bits do — so both
    /// are asked, and a modifier is stale only when neither is down.
    private static let modifierKeys: [(mask: CGEventFlags, name: String, keys: [CGKeyCode])] = [
        (.maskCommand,     "⌘", [55, 54]),
        (.maskAlternate,   "⌥", [58, 61]),
        (.maskControl,     "⌃", [59, 62]),
        (.maskShift,       "⇧", [56, 60]),
        (.maskSecondaryFn, "fn", [63]),
    ]

    /// **A modifier the session believes is held that no key is holding down —
    /// put back at launch** (2026-09-14, the seventh occurrence of the stale-⌘
    /// bug and the first this app did not cause).
    ///
    /// `wispr-alone` is the scenario: the relay is stopped, Wispr pastes for
    /// itself, the relay is started again — and the session is left with
    /// `sessionFlags == ["command"]`. Wispr's ⌘V is `keycode 9, flags
    /// 0x20100000`, ⌘ stamped on the key **and on its release**, with no
    /// `flagsChanged` behind it; with a tap running, `clearCommandAfterWisprPaste`
    /// puts it back, and with no tap running there is nobody to. It self-heals on
    /// Victor's next real keystroke, which is exactly why it survives a relaunch
    /// unnoticed — and until it does, every gesture gated on `bare` refuses and
    /// every *wait for a bare wire* loop spins its full allowance.
    ///
    /// So the first thing the relay does is read what the window server believes
    /// and compare it against what is physically down. The comparison is the
    /// whole safety of it: a man who launched the app with ⌥ held is holding ⌥,
    /// and `keyState` says so.
    ///
    /// Called from `applicationDidFinishLaunching` after `SingleInstance.enforce`,
    /// so the relaunch path — where the outgoing instance's last posted event is
    /// the likeliest source of a stale flag — is covered by the same call.
    static func clearStaleModifiersAtLaunch() {
        var live = CGEventSource.flagsState(.combinedSessionState)
        let stale = modifierKeys.filter { m in
            live.contains(m.mask)
                && !m.keys.contains { CGEventSource.keyState(.combinedSessionState, key: $0) }
        }
        guard !stale.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = Self.backButtonStamp
        for m in stale {
            // **What the keyboard is left in**, not nothing: a modifier he is
            // really holding must survive the clearing of one he is not.
            live.remove(m.mask)
            // On the modifier's **own** keycode — a `flagsChanged` is a modifier
            // transition, and one announced on any other key is not applied.
            let key = m.keys[0]
            guard let clear = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
            else { continue }
            clear.type = .flagsChanged
            clear.flags = live
            clear.post(tap: .cghidEventTap)
            Log.info("⌨️ a stale \(m.name) from before the relay started was put back down")
        }
    }

    private func trace(_ verdict: String, _ type: CGEventType, _ event: CGEvent) {
        guard Self.keyTrace else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let stamped = event.getIntegerValueField(.eventSourceUserData) == Self.backButtonStamp
        let kind = type == .keyDown ? "↓" : type == .keyUp ? "↑" : "⇧"
        Log.info(String(format: "⌨️trace %@ key %d pid %d%@ flags 0x%llx — %@",
                        kind, code, pid, stamped ? " (ours)" : "",
                        event.flags.rawValue, verdict))
    }

    /// Swallow, and say which branch did it.
    private func swallow(_ why: String, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        trace("SWALLOWED by \(why)", type, event)
        return nil
    }

    /// **Whoever is frontmost now**, pushed in by `WisprFlowSource`'s workspace
    /// observer so the tap never has to ask AppKit on its own thread. It is the
    /// fallback for a remembered pid that has since died — the loop force-quits
    /// its victim between scenarios, and the guard spent a whole run posting into
    /// a corpse (`re-posted to pid 62948`, dead; the live TextEdit was 87941).
    func noteFrontmost(_ pid: pid_t) {
        stateLock.lock(); currentFrontPid = pid; stateLock.unlock()
    }
    private var currentFrontPid: pid_t = 0

    /// **The pid to redirect to, resolved at the keystroke and not at the
    /// chord.** Cheap enough for the tap thread: a lock, two comparisons and a
    /// `kill(pid, 0)` — a signal-zero liveness probe that touches neither the
    /// window server nor Accessibility.
    private func redirectTargetNow() -> pid_t {
        stateLock.lock(); defer { stateLock.unlock() }
        guard redirectPid != 0, CFAbsoluteTimeGetCurrent() < redirectUntil else { return 0 }
        // **Whoever is in front at this keystroke wins**, when that is somebody
        // else and alive. He may have clicked into another app since the chord,
        // and an insertion into the app he has left is worse than a dropped key.
        if currentFrontPid != 0, currentFrontPid != redirectPid, kill(currentFrontPid, 0) == 0 {
            Log.info("⌨️ the front app changed since the chord — his keys go to pid \(currentFrontPid), not \(redirectPid)")
            redirectPid = currentFrontPid
            redirectTarget = currentFrontPid
            return currentFrontPid
        }
        if kill(redirectPid, 0) == 0 { return redirectPid }
        let replacement = currentFrontPid
        guard replacement != 0, replacement != redirectPid, kill(replacement, 0) == 0 else { return 0 }
        Log.error("⌨️ pid \(redirectPid) is gone — his keys go to pid \(replacement) instead")
        redirectPid = replacement
        redirectTarget = replacement
        return replacement
    }

    /// **Why a swallowed key still appears to land**, answered rather than
    /// guessed (2026-09-14).
    ///
    /// The question was whether the tap is leaking — returning the event instead
    /// of nil on the guard's branch — or whether the key that arrives is a
    /// *second* event. The trace already answers it and this makes the answer
    /// impossible to miss: each probe letter arrives **twice, from two different
    /// posting processes**, each with its own `SWALLOWED` line. Nothing is being
    /// let through; the harness posts every letter twice, and a guard that
    /// faithfully forwards both delivers two.
    private func noteDuplicate(_ code: CGKeyCode, pid: pid_t) {
        let now = CFAbsoluteTimeGetCurrent()
        stateLock.lock()
        let previous = lastKey
        lastKey = (code, pid, now)
        stateLock.unlock()
        guard let previous, previous.code == code, previous.pid != pid,
              now - previous.at < 0.5 else { return }
        Log.info(String(format: "⌨️ key %d arrived again from pid %d (was pid %d, %.0f ms earlier) — "
                        + "it is posted twice at the source; the swallow is not leaking",
                        Int(code), Int(pid), Int(previous.pid), (now - previous.at) * 1000))
    }
    private var lastKey: (code: CGKeyCode, pid: pid_t, at: CFAbsoluteTime)?

    /// **Put ⌘ back down after Wispr's paste.** Announced on the ⌘ key's own
    /// keycode, because a `flagsChanged` is a modifier transition and one
    /// carrying the letter is not one — the lesson of the fifth occurrence.
    /// Stamped, so this app's own tap does not read it as Victor's, and posted
    /// off the tap thread because nothing that can wait belongs there.
    private func clearCommandAfterWisprPaste() {
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = Self.backButtonStamp
            guard let clear = CGEvent(keyboardEventSource: source,
                                      virtualKey: Self.VK_COMMAND, keyDown: true) else { return }
            clear.type = .flagsChanged
            clear.flags = []
            clear.post(tap: .cghidEventTap)
            Log.info("⌨️ Wispr's ⌘V released with ⌘ still stamped on it — the flag has been put back down")
        }
    }

    private func countSeen() {
        stateLock.lock(); redirectSeen += 1; stateLock.unlock()
    }

    private func countAX() -> Int {
        stateLock.lock(); defer { stateLock.unlock() }
        redirectAX += 1
        return redirectAX
    }

    /// **Insert text where the caret is, without needing a key window.**
    ///
    /// This is the whole point of the change. An application that is frontmost
    /// with no key window has **no first responder**, so a character delivered to
    /// it by any key route is dropped — measured twice, once with a dead target
    /// and once with a live one, and the letters vanished both times.
    /// `AXSelectedText` needs no key window at all: it replaces the focused
    /// element's selection, which at a caret is empty, so setting it *is* typing.
    ///
    /// The focused element is read **fresh at the keystroke** rather than
    /// remembered from the chord: he may have clicked into another field since,
    /// and an insertion into the field he has left is worse than a dropped key.
    /// **The queue the Accessibility work happens on, and it is the whole fix.**
    ///
    /// `AXUIElementCopyAttributeValue` is a synchronous round trip into another
    /// application. Doing it inside the event tap's callback stalls every
    /// keystroke on the Mac while it waits, and macOS may disable the tap
    /// outright — measured 2026-09-14: the run that tried it produced one trace
    /// line and then silence, the dictation never finished, and the relay was
    /// dead afterwards.
    ///
    /// So the tap does only what a tap can do quickly — decide, translate the
    /// keycode through the layout (pure, no AX), swallow — and the insertion
    /// happens here. Serial, so his characters arrive in the order he typed
    /// them; `.userInteractive`, because this *is* his typing.
    private static let axQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr-keys",
                                               qos: .userInteractive)

    /// **Two hundred milliseconds per character, and then it is lost.**
    ///
    /// `AXUIElementSetMessagingTimeout` bounds the round trip at its source,
    /// which is the only place it can be bounded — an AX call cannot be
    /// cancelled once it is waiting. A character that misses the deadline is
    /// **said to be lost** rather than queued behind the next one: a keyboard
    /// that delivers his sentence half a second late, in order, is worse than
    /// one that drops a letter and says so.
    private static let axDeadline: Float = 0.2

    /// Hand one character to the queue. Returns immediately; the tap is never
    /// held up by an application that is thinking.
    private func insert(_ text: String, code: CGKeyCode) {
        Self.axQueue.async { [weak self] in
            guard let self, let pid = self.liveTarget() else {
                Log.error("⌨️ key \(code) lost — no live application to insert it into")
                return
            }
            let started = CFAbsoluteTimeGetCurrent()
            if self.insertViaAX(text, into: pid) {
                Log.info(String(format: "⌨️ key %d → pid %d through Accessibility (#%d, %.0f ms)",
                                Int(code), Int(pid), self.countAX(),
                                (CFAbsoluteTimeGetCurrent() - started) * 1000))
            } else {
                Log.error(String(format: "⌨️ key %d LOST — Accessibility would not insert into pid %d (%.0f ms)",
                                 Int(code), Int(pid), (CFAbsoluteTimeGetCurrent() - started) * 1000))
            }
        }
    }

    /// Re-post one non-printable on the same queue, so it keeps its place in the
    /// order his characters arrive in.
    private func repost(_ event: CGEvent, code: CGKeyCode) {
        guard let copy = event.copy() else { return }
        Self.axQueue.async { [weak self] in
            guard let self, let pid = self.liveTarget() else { return }
            copy.postToPid(pid)
            Log.info("⌨️ key \(code) → pid \(pid) as a key, best effort (#\(self.countRedirect())) — not a printable character")
        }
    }

    private func liveTarget() -> pid_t? {
        let pid = redirectTargetNow()
        return pid != 0 ? pid : nil
    }

    private func insertViaAX(_ text: String, into pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axDeadline)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        let target = element as! AXUIElement
        AXUIElementSetMessagingTimeout(target, Self.axDeadline)
        return AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString,
                                            text as CFString) == .success
    }

    /// **What this key would type, and whether that is a character at all.**
    ///
    /// The event is asked first — and on a **synthetic** one it answers nothing.
    /// `keyboardGetUnicodeString` returns the string the window server put there
    /// during translation, and an event built with `CGEvent(keyboardEventSource:
    /// virtualKey:keyDown:)` has never been translated: measured 2026-09-14, the
    /// loop's seven probe letters every one of them came back empty and took the
    /// *non-printable* path, so the Accessibility insertion this was written for
    /// was never once exercised by the test that exists to exercise it.
    ///
    /// So the keycode is translated against the **current keyboard layout**,
    /// which is what a real keystroke would have been translated against anyway.
    /// `UCKeyTranslate` is the only API that answers it, and it needs the layout
    /// data from the current input source; the dead-key state is deliberately
    /// discarded — a dead key produces no character on its own and belongs on the
    /// key path with the arrows.
    private static func printable(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length,
                                       unicodeString: &chars)
        if length > 0 {
            return usable(String(utf16CodeUnits: chars, count: length))
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        return usable(translate(code, flags: event.flags))
    }

    private static func usable(_ text: String?) -> String? {
        guard let text, !text.isEmpty,
              text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F })
        else { return nil }
        return text
    }

    /// **The keyboard layout, cached, because reading it crashes the tap.**
    ///
    /// `TISGetInputSourceProperty` asserts that it is on the **main thread** —
    /// HIToolbox calls `dispatch_assert_queue` and traps. Called from the event
    /// tap's own thread it is not a slow path or a race, it is an immediate
    /// `SIGTRAP`: three runs died this way on 2026-09-14 (`_dispatch_assert_queue_fail`
    /// → `TSMGetInputSourceProperty` → `HotkeyTap.translate`) and each looked
    /// like something else, because what the log showed was a dictation that
    /// simply stopped.
    ///
    /// So the layout is read once on the main thread and re-read when the input
    /// source changes. What the tap touches is a `Data` and nothing else.
    private static let layoutLock = NSLock()
    private static var layoutData: Data?

    /// Called from `start()`, on the main thread, and again whenever he switches
    /// keyboard.
    static func refreshKeyboardLayout() {
        var data: Data?
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }
        layoutLock.lock(); layoutData = data; layoutLock.unlock()
    }

    /// The keycode through the current layout — `UCKeyTranslate`.
    private static func translate(_ code: CGKeyCode, flags: CGEventFlags) -> String? {
        layoutLock.lock()
        let cached = layoutData
        layoutLock.unlock()
        guard let data = cached else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey >> 8) }
        if flags.contains(.maskAlphaShift) { modifiers |= UInt32(alphaLock >> 8) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey >> 8) }
        var dead: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                  &dead, 8, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    private func countRedirect() -> Int {
        stateLock.lock(); defer { stateLock.unlock() }
        redirectCount += 1
        return redirectCount
    }

    private func countPassed() {
        stateLock.lock(); redirectPassed += 1; stateLock.unlock()
    }

    func disarmInjectionCapture() {
        stateLock.lock()
        injectionArmed = false
        injectionSwallows = false
        stateLock.unlock()
    }

    private var injectionArmed = false
    private var injectionSwallows = false
    /// **How many synthetic key events one window may narrate.** Enough to tell a
    /// ⌘V from a key-by-key type (which would be one line per character) without
    /// a recogniser that types turning `relay.log` into a transcript of itself.
    private static let injectionProbeLines = 6
    private var injectionProbeLeft = 0

    /// The wheel clicked **with the left button already held** — point the relay
    /// The wheel clicked **with the left button already held** — point the relay
    /// at the window in front. Same call ⌘⌃B makes, including its toggle: made on
    /// the terminal already bound, it lets go.
    ///
    /// Still returns whether anything was bound, and the return is now only
    /// logged: the click is never handed back to the app underneath, because with
    /// the left button down a replayed middle click would land in the middle of
    /// whatever drag or selection that button is in.
    var onGestureBind: (() -> Bool)?

    /// **⬅️ held + forward button flicked right — bind, and start dictating at
    /// what was just bound** (2026-09-14). Victor: *"click butonul principal de
    /// mouse stânga și apoi forward și drag în dreapta, să facă bind și să și
    /// înceapă transcrierea"*.
    ///
    /// The left-held sub-case of 🔼→, exactly as the plain bind is the left-held
    /// sub-case of 🔼click. It is one gesture for the two things he always does
    /// together — point the relay at the terminal under the cursor, then talk to
    /// it — and the order matters, so `AppDelegate` does the bind first and only
    /// dictates if it took.
    var onGestureBindAndDictate: (() -> Void)?

    /// **⬆️ — the forward button held, mouse moved up.** Dictate at a session
    /// that does not exist yet: the folder menu opens and the words go to the
    /// terminal it spawns.
    ///
    /// A gesture of its own again. From 2026-09-05 to 2026-09-09 the spawn was a
    /// *conversion* — the wheel clicked twice, the second click turning the
    /// dictation the first had started into a spawn — because the wheel had only
    /// one press to spend and the hold on it had already failed. A direction has
    /// no such shortage: there are four of them on this button, so the spawn gets
    /// one and needs no first click to reinterpret.
    var onGestureSpawn: (() -> Void)?

    // ── Only reachable with *Use Logi Gestures* off ─────────────────────────
    //
    // The wheel's own vocabulary, kept whole. Every one of these is dead code
    // while the flag is on, and that is the point: the old gesture set is a
    // switch away rather than a `git revert` away.

    /// **The wheel pressed at rest, bound: start a dictation — and defer its
    /// context shot to the release** (Victor, 2026-09-04). Distinct from
    /// `onLocalToggle` because the bare wheel's press is only half a verdict:
    /// a second click on its heels turns the dictation into a spawn, and the
    /// picture is of the screen his finger left, not of the one it landed on.
    /// The shot fires at the release instead, through `onWheelRelease`.
    var onWheelDictate: (() -> Void)?
    /// **The wheel clicked twice** — turn the dictation the first click started
    /// into a spawn: same words being recorded, but the destination becomes a
    /// session that does not exist yet, and the folder menu opens on the second
    /// click. Victor's design, 2026-09-05, replacing the 2s wheel hold of the
    /// day before, which never fired (see `spawnDoubleSeconds`).
    var onWheelDoubleSpawn: (() -> Void)?
    /// The same double click made **with nothing bound**, where there is no
    /// dictation yet to convert: it opens one, already aimed at a new session.
    var onWheelIdleDoubleSpawn: (() -> Void)?
    /// The wheel came up after a press that started a dictation — the deferred
    /// context shot's cue (`onWheelDictate`). Fires on no other release.
    var onWheelRelease: (() -> Void)?
    /// **Mouse 5, twice quickly — bind, exactly as ⌘⌃B does.** The keyboard
    /// shortcut asks for both hands at the moment his pointing hand is already
    /// on the terminal he means; the button is where the hand already is.
    ///
    /// Recognised *retroactively*, on the second press, and never by delaying the
    /// first. Waiting out the double-click interval before acting would put
    /// macOS's own 0.5s in front of every single press — i.e. in front of the
    /// start of every dictation — to serve the rarer gesture. So the first press
    /// does what it has always done and the second undoes it: on Local Whisper
    /// that means a microphone opened for a couple of hundred milliseconds, which
    /// is under `MicRecorder.minimumDuration` and is thrown away by the guard
    /// that already exists for a slipped click.
    var onMouse5Double: (() -> Void)?


    /// The wheel clicked **with the right button already held** — let the
    /// binding go. The same call the menu's `Disconnect` row makes, so the
    /// gesture and the row cannot drift apart.
    ///
    /// **The mirror of the rebind chord, and deliberately shaped like it**: one
    /// button held as a modifier, the wheel clicked on top, judged at the press.
    /// Left points the relay somewhere; right takes it back. Nothing else in
    /// this app has to be learned twice to know both.
    ///
    /// Why it needed a gesture at all: disconnecting was only ever in the menu,
    /// which means going to the menu bar — the one place the hand on the mouse
    /// is not. Every other thing the wheel does (bind, dictate, cancel, spawn)
    /// is reachable without leaving the pointer, and the one that *ends* the
    /// session was the exception.
    var onGestureUnbind: (() -> Void)?

    /// **🔽 ↑ — start or stop a screen recording** (2026-09-18). One gesture for
    /// both, like every other toggle on this mouse: the hand that started it is
    /// already in the right place, and a separate stop gesture is one more thing
    /// to remember while he is mid-sentence and watching something happen.
    var onGestureFilm: (() -> Void)?
    /// 🔼 ↓ — mark the sentence in flight as a small job (2026-09-23).
    var onGestureKamikaze: (() -> Void)?

    /// Whether the frontmost app is one `bind` would take. Pushed from
    /// `AppDelegate` on every app switch rather than asked here: the answer needs
    /// `NSWorkspace`, which is a main-thread question, and an event tap that
    /// blocks on the main thread is a frozen mouse.
    ///
    /// The wheel no longer consults it — rebinding is the left-plus-wheel chord
    /// and it acts wherever it is made, letting `bindFrontmostTerminal` refuse.
    /// It survives because the menu's **Connect Terminal** row greys itself out
    /// with it, and this is where the answer is already kept up to date.
    var frontIsBindable: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return frontIsBindableFlag }
        set { stateLock.lock(); frontIsBindableFlag = newValue; stateLock.unlock() }
    }
    private var frontIsBindableFlag = false

    /// **Which mouse this app thinks it is holding** — the menu's
    /// *Use Logi Gestures*, remembered across restarts by `StatusItem`.
    ///
    /// On (the default): the side buttons arrive as ⌃⌥⌘F3…F12 from Logi Options+
    /// and **every mouse button is passed straight through**, wheel included.
    /// Off: the pre-2026-09-09 wiring is back — the wheel carries the dictation,
    /// the left and right buttons are chord modifiers, and the side buttons are
    /// read as buttons 4 and 5.
    ///
    /// **Both paths are live code, not one path and a comment.** Victor asked for
    /// the old one kept rather than deleted, and a gesture set that only exists
    /// in a diff cannot be switched back to at a workshop when the Options+
    /// profile is missing on a machine — which is the case this flag is for.
    ///
    /// Read on the tap thread, written from the main one, hence the lock.
    var useLogiGestures: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return useLogiGesturesFlag }
        set { stateLock.lock(); useLogiGesturesFlag = newValue; stateLock.unlock() }
    }
    private var useLogiGesturesFlag = true

    /// ⌘⌃B — point the relay at the terminal in front, or end the session when it
    /// is already pointed there. On **B for bind** since 2026-09-01, having been
    /// ⌘⌃D before that: D is now the key that dictates.
    ///
    /// Owned here since 2026-08-26; it used to live in
    /// Victor Addons, which had to launch this app before it could ask it to
    /// bind. Now that the relay starts at login there is nothing to launch, and
    /// the key belongs to the app it acts on.
    var onBindHotkey: (() -> Void)?
    /// ⌘⇧P — the last dictation, again: onto the clipboard and pasted at the
    /// caret. It is the same kind of key as ⌘⌃B and ⌘⌃D — a global one this app
    /// owns outright — and it stays on P because the neighbouring ⌃⌥P is already
    /// the shutter, so the two things Victor reaches for after a sentence share
    /// a letter and differ by which modifier the hand is holding.
    ///
    /// **It was ⌘⌃P until 2026-09-19**, when Victor moved it to ⌘⇧P. The
    /// difference from its two neighbours is now more than a spelling: ⌘⌃ is a
    /// pair nothing on a Mac ships, while ⌘⇧P is the Command Palette in VS Code
    /// and Cursor, the command menu in Chrome's DevTools, and a run action on
    /// some IntelliJ keymaps. This tap swallows it unconditionally, so while the
    /// relay is up the chord is the relay's in those applications too.
    var onPasteLast: (() -> Void)?

    /// ⏎ while the overlay is holding a prompt: send it now instead of waiting
    /// out the countdown. The Send button has read `⏎ Send 3s` since it was
    /// written; this is the key finally meaning what the label promised.
    var onPromptEnter: (() -> Void)?
    /// ⎋ while the prompt is held: stop it going out.
    var onPromptEscape: (() -> Void)?

    /// A prompt is on screen with its clock running — the only window in which
    /// Return is the overlay's. It is a **short** window (3–5s, and only after a
    /// dictation), which is what makes taking a key as ordinary as Return
    /// affordable at all: outside it the key is untouched, and inside it Victor
    /// is reading a panel, not typing into a terminal.
    var promptHeld: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return promptHeldFlag }
        set { stateLock.lock(); promptHeldFlag = newValue; stateLock.unlock() }
    }
    private var promptHeldFlag = false

    /// A dictation is running **and** the relay is forwarding — the only window
    /// in which mouse 4 is ours. Written from the main thread, read from the tap
    /// thread, hence the lock.
    var dictating: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return dictatingFlag }
        set { stateLock.lock(); dictatingFlag = newValue; stateLock.unlock() }
    }
    private var dictatingFlag = false

    /// **Has the relay's own engine got a sentence open right now?** (2026-09-18)
    ///
    /// Broader than `dictating`, which is `hasDestination && listening` and
    /// therefore answers *is mouse 4 ours*. This one answers *would a second
    /// recogniser now be listening alongside the first* — so it covers the
    /// speculative ring and the settle as well, and it does not care whether
    /// there is anywhere to send the words.
    ///
    /// It exists because 🔽 → posts Wispr's chord **raw, in every engine**. With
    /// the Engine on the local model or on ElevenLabs, that flick starts Wispr's
    /// microphone while the relay's own is already open — two recognisers on one
    /// voice, two transcripts, and a sentence split between them. Victor,
    /// 2026-09-18: *"E absurd să pornesc două motoare de transcriere simultan.
    /// Trebuie exclusiv, ba unu, ba altu."*
    ///
    /// Written from the main thread, read from the tap thread, hence the lock —
    /// `dictating`'s arrangement, for `dictating`'s reason.
    var ownDictation: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return ownDictationFlag }
        set {
            stateLock.lock()
            // **Both edges are stamped**, because the age of an open sentence is
            // what `gestureStopDwellSeconds` is measured against — see
            // `openSentenceAge`. Written from the main thread on every
            // `syncBorrowedGestures`, most of which change nothing, so the clock
            // only moves on a real transition.
            if newValue != ownDictationFlag {
                ownDictationSince = newValue ? CACurrentMediaTime() : 0
            }
            ownDictationFlag = newValue
            stateLock.unlock()
        }
    }
    private var ownDictationFlag = false
    private var ownDictationSince: CFTimeInterval = 0

    /// **How long the relay's own sentence has been open**, or nil when none is
    /// — read from the tap thread, hence the lock.
    ///
    /// `ownDictation` rather than `dictating` on purpose: this answers *is there
    /// a sentence to undo*, which is true through the speculative ring and the
    /// settle as well, and is true whether the words are going to a terminal or
    /// to the caret. A guard that only counted a destination would let the flick
    /// close a caret dictation it had just opened.
    private var openSentenceAge: CFTimeInterval? {
        stateLock.lock(); defer { stateLock.unlock() }
        guard ownDictationFlag, ownDictationSince > 0 else { return nil }
        return CACurrentMediaTime() - ownDictationSince
    }

    /// **A gesture was refused because the other engine is already listening.**
    /// The banner is the overlay's and the tap may not reach for it; this is the
    /// whole of the wiring. Raised on the tap thread, so the other end hops.
    var onEngineBusy: ((String) -> Void)?

    /// **A Wispr Flow sentence was thrown away by ⬅️ on the back button.** The
    /// banner is the overlay's and the tap may not reach for it, exactly as
    /// `onEngineBusy`. Only for a sentence the relay does **not** own — one it
    /// owns goes down `onLocalCancel`, which has a banner of its own.
    var onWisprCancel: (() -> Void)?

    /// **Is Wispr Flow's microphone open right now?** — supplied by
    /// `AppDelegate` and read from the tap thread, so it must be cheap and it
    /// must be safe there: `WisprWatch.sampleIsRunningInput` is three CoreAudio
    /// reads over a cached list of object ids, under its own lock.
    ///
    /// The back button's stop is decided on this and not on the relay's own
    /// `listening`, because the relay is **blind to a 🔽 → dictation whenever
    /// the Engine is the local model** — that gesture posts Wispr's chord raw,
    /// and with `LocalWhisperSource` wired up nothing in this app is watching
    /// Wispr at all. The button has to work in exactly that configuration,
    /// which is the one he dictates into other applications from.
    var wisprMicIsOpen: (() -> Bool)?

    /// **Told when 🔽 → arms the back button's stop, and when it goes down
    /// again**, so `AppDelegate` can watch Wispr's microphone for exactly the
    /// length of that one dictation and nothing else. Raised on whichever thread
    /// moved the arm — the tap's, for both of them — so the other end hops.
    var onWisprRawGesture: ((Bool) -> Void)?

    /// **When 🔽 → last opened a Wispr dictation** (2026-09-17), and zero when
    /// the back button is nobody's but Return's.
    ///
    /// Victor: *"butonul de Back trebuie să se transforme în a opri Wispr Flow
    /// din dictare. Să nu mai fie necesar să fac, încă o dată, gestul de Back cu
    /// dreapta."* The gesture that starts that dictation is made with the back
    /// button held, so ending it meant making the whole flick a second time. For
    /// the length of that one sentence the back button's **click** is its stop —
    /// the same chord the second flick would have posted, on the button already
    /// under the thumb.
    ///
    /// Armed by 🔽 → and by nothing else, because that is the only gesture that
    /// hands the sentence to Wispr raw. Every relay-started dictation keeps the
    /// shutter on this button: those sentences are a message being assembled and
    /// a picture has something to attach to, where a 🔽 → sentence is Wispr's
    /// own — the relay rings for it and routes nothing.
    private var wisprGestureAt: CFTimeInterval = 0

    /// How long the arm survives **before** Wispr's microphone has opened.
    /// Measured 2026-09-12: 324–674 ms from the chord to the microphone warm and
    /// **5–6 s cold**, which is `WisprFlowSource.speculativeGrace`'s 12 s and the
    /// same reasoning — the button has to work in that gap, and a chord Wispr
    /// ignored altogether must not leave it a stop for the rest of the day.
    private static let wisprGestureGrace: CFTimeInterval = 12

    /// **Is the back button this dictation's stop?** Armed by 🔽 →, and true for
    /// as long as Wispr's microphone is open — plus the cold-start grace above,
    /// which covers the seconds before it opens. Once the microphone closes the
    /// button is Return again with no edge to be told about and nothing to go
    /// stale: *"după ce Wispr Flow nu mai dictează, revine butonul de back la
    /// tasta obișnuită de Enter."*
    var backStopsWispr: Bool {
        stateLock.lock()
        let armedAt = wisprGestureAt
        stateLock.unlock()
        guard armedAt > 0 else { return false }
        if wisprMicIsOpen?() == true { return true }
        return CACurrentMediaTime() - armedAt < Self.wisprGestureGrace
    }

    /// **The arm goes down when the sentence it belongs to is over** — called
    /// from `AppDelegate`'s watch on Wispr's microphone.
    ///
    /// Without it the arm is only ever *read*, and a reading is not an ending: a
    /// 🔽 → dictation that stopped on its own — Wispr's own silence timeout, a
    /// ⌃Escape, the window closed — would leave `wisprGestureAt` standing, and
    /// the next time Wispr's microphone opened for some **other** reason the
    /// back button would read that as its own sentence still running and stop
    /// it. The grace alone cannot catch that: it has long expired, and the
    /// microphone being open makes the check say yes regardless.
    func retireWisprStop(_ why: String) {
        stateLock.lock()
        let armed = wisprGestureAt > 0
        stateLock.unlock()
        guard armed else { return }
        Log.info("⌨️ the back button is Return again — \(why)")
        setWisprArm(0)
    }

    /// **Put the arm back after a restart**, carrying the age it already had.
    ///
    /// A relaunch in the middle of a 🔽 → sentence — a Dock click, `build-app.sh`,
    /// `relay-restart.sh` — used to take the stop away from under his thumb
    /// silently: the button went back to Return mid-dictation and the only way
    /// out was making the whole flick again. `AppDelegate` restores it at launch
    /// when `Relaunch` left a marker **and** Wispr's microphone is open now, and
    /// the age travels with it so the cold-start grace is not handed out a
    /// second time — past it, the arm stands on the microphone alone, which is
    /// the honest test for *that sentence is still running*.
    func restoreWisprStop(armedSecondsAgo: TimeInterval) {
        let at = max(1, CACurrentMediaTime() - max(0, armedSecondsAgo))
        Log.info("⌨️ the back button is the stop again — a restart landed inside a 🔽 → dictation (\(Int(armedSecondsAgo * 1000)) ms in)")
        setWisprArm(at)
    }

    /// The one place the arm moves, so *it went up* and *it went down* are
    /// always announced and never announced twice.
    private func setWisprArm(_ at: CFTimeInterval) {
        stateLock.lock()
        let changed = (wisprGestureAt > 0) != (at > 0)
        wisprGestureAt = at
        stateLock.unlock()
        if changed { onWisprRawGesture?(at > 0) }
    }

    /// There is a destination **and** the relay is forwarding — the state in
    /// which the wheel can open the microphone at all. Set from the main thread
    /// by `AppDelegate.syncLocalCapture`.
    var localCapture: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return localCaptureFlag }
        set { stateLock.lock(); localCaptureFlag = newValue; stateLock.unlock() }
    }
    private var localCaptureFlag = false

    /// There is a destination, **whether or not the relay is forwarding to it** —
    /// the only state in which the unbind chord means anything. Deliberately not
    /// `localCapture`: the two say the same thing today, and the flag meaning
    /// *there is a binding to let go of* must not be the one meaning *the wheel
    /// may open the microphone*.
    /// Written from the main thread by `AppDelegate.syncLocalCapture`.
    var bound: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return boundFlag }
        set { stateLock.lock(); boundFlag = newValue; stateLock.unlock() }
    }
    private var boundFlag = false

    /// **Replace Wispr is on** — the forward button is the microphone and the
    /// back button is left alone. Written from the main thread by
    /// `AppDelegate`, read from the tap thread, hence the lock.
    var replaceWispr: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return replaceWisprFlag }
        set { stateLock.lock(); replaceWisprFlag = newValue; stateLock.unlock() }
    }
    private var replaceWisprFlag = false

    /// When mouse 5 last went down, for the double-click test. Touched only from
    /// the tap callback, which is one thread, so it needs no lock — unlike the
    /// flags above, which the main thread writes.
    private var lastMouse5DownAt: CFTimeInterval = 0
    /// The release of a press we swallowed. It has to go with it: LinearMouse is
    /// downstream of this tap and would otherwise act on an orphan release.
    private var swallowMouse5Up = false

    // MARK: The wheel's presses

    /// How long a dictation must be cancelled for. Ending one is a tap; throwing
    /// one away costs two seconds, because it discards a sentence already spoken
    /// and there is nothing to undo it with — the long press is the confirmation
    /// dialog this gesture does not have.
    private static let cancelHoldSeconds: TimeInterval = 2.0

    /// How long the left button must **already** have been down for a wheel click
    /// on top of it to read as the rebind chord rather than as two buttons that
    /// happened to overlap. Short on purpose: nobody holds the left button a
    /// third of a second by accident while reaching for the wheel.
    private static let chordHoldSeconds: CFTimeInterval = 0.3

    /// How long the **wheel** then has to stay down for the same chord to also
    /// open the microphone. One second, and it is a wait rather than a
    /// confirmation — nothing it leads to is destructive, so it only has to be
    /// long enough that a bind meant as a bind is not read as a dictation, and
    /// short enough that the hand has not let go by then.
    private static let chordDictateSeconds: TimeInterval = 1.0

    /// When the left button went down, or 0 while it is up. Written and read only
    /// from the tap callback, which is one thread.
    /// **Where the left button went down**, so a release can tell a click from a
    /// drag — see `onSelectionDragEnded`. Same thread as `leftDownAt`, no lock.
    private var leftDownPoint: CGPoint = .zero
    /// Further than this between press and release and it was a drag, not a
    /// click. Four points: a hand resting on a mouse moves one or two.
    private static let selectionDragSlop: CGFloat = 4

    /// **When he last did something that selects text**, on the tap's own clock.
    ///
    /// The point of it is what it is *not*: a poll. Every gesture that selects
    /// text is a mouse or keyboard event, and this tap already sees every one of
    /// them — a drag's release is already measured a few lines down for
    /// `onSelectionDragEnded`, and every `keyDown` already passes through
    /// `handle`. So the recency of a highlight costs one `CACurrentMediaTime()`
    /// in code that runs anyway: no timer, no thread, no Accessibility call, and
    /// nothing at all while he is not dictating.
    ///
    /// **Why not `AXObserver` / `kAXSelectedTextChangedNotification`**, which is
    /// the textbook push answer: it needs an observer created per pid and
    /// re-registered on every app switch, it fires on plain **caret moves** in
    /// most text views (a callback per keystroke, all day), and its blind spot
    /// is *exactly* `readQuiet`'s — IntelliJ's editor, WhatsApp and Chrome page
    /// content do not answer `AXSelectedText`, so they do not post the
    /// notification either. It costs more than this and sees less.
    ///
    /// Written from the tap thread, read from main at the dictation gesture, so
    /// unlike `leftDownAt` and `leftDownPoint` beside it this one takes the lock.
    private var lastSelectionGestureAt: CFTimeInterval = 0

    /// Three gestures stamp it, and the two silent ones are the *better*
    /// witnesses: a drag can be a window being moved, but a double-click and a
    /// ⇧-arrow are selections and nothing else.
    func noteSelectionGesture() {
        stateLock.lock(); lastSelectionGestureAt = CACurrentMediaTime(); stateLock.unlock()
    }

    /// How long ago that was — `.infinity` when it has never happened, so a
    /// caller can compare against its window without a special case.
    var secondsSinceSelectionGesture: TimeInterval {
        stateLock.lock(); let at = lastSelectionGestureAt; stateLock.unlock()
        guard at > 0 else { return .infinity }
        return CACurrentMediaTime() - at
    }

    /// The keys that extend a selection, all of which need ⇧ to do it. ⌘A is
    /// handled beside them and is the one that does not.
    private static let selectionExtendKeys: Set<CGKeyCode> = [
        123, 124, 125, 126,   // ← → ↓ ↑
        115, 119, 116, 121,   // Home, End, Page Up, Page Down
    ]
    private static let VK_A: CGKeyCode = 0

    /// **The left button was released after a drag, during a dictation** — which
    /// is what selecting text with a mouse looks like from here (2026-09-14).
    ///
    /// Victor: *"Am selectat text în IntelliJ, nu merge. Am selectat text în
    /// WhatsApp, nimic."* The watcher polls Accessibility once a second and
    /// `AXSelectedText` is simply not answered by IntelliJ's editor or by
    /// WhatsApp — the ⌘C fallback that does reach them belongs to the shutter,
    /// because a synthetic ⌘C every second for the length of a sentence would
    /// take that key away from him for the whole dictation.
    ///
    /// The release of a drag is the one moment that is neither: the selection is
    /// **complete** by definition, and it happens once per selection rather than
    /// once per second. It also answers the other half of what he reported — the
    /// watcher's three settling reads are why a highlight *"intră greu, cu
    /// întârziere"*.
    var onSelectionDragEnded: (() -> Void)?

    private var leftDownAt: CFTimeInterval = 0
    /// Both left-up sites go through here, because they are the same fact and a
    /// second copy is a second thing to forget. **Nothing is swallowed and
    /// nothing blocks**: the callback is handed to a global queue, because this
    /// runs inside the event tap and a probe that reaches for the pasteboard on
    /// the tap's own thread would stall every click on the Mac.
    private func noteLeftRelease(at point: CGPoint, clicks: Int64 = 1) {
        let wasDown = leftDownAt > 0
        let from = leftDownPoint
        leftDownAt = 0
        leftDownPoint = .zero
        guard wasDown else { return }
        let moved = hypot(point.x - from.x, point.y - from.y)
        let dragged = moved > Self.selectionDragSlop
        // **Stamped above the `dictating` gate**, because the question this
        // answers is asked when no dictation has started yet: *did he select
        // something in the last few seconds*. A double- or triple-click selects
        // a word or a line without moving, so it fails the slop test and is a
        // better witness than the drag that passes it.
        if dragged || clicks >= 2 { noteSelectionGesture() }
        guard dictating, dragged else { return }
        DispatchQueue.global().async { [weak self] in self?.onSelectionDragEnded?() }
    }

    private var leftIsHeld: Bool { leftDownAt > 0 && CACurrentMediaTime() - leftDownAt >= Self.chordHoldSeconds }

    /// When the right button went down, or 0 while it is up — the mirror of
    /// `leftDownAt`. Same thread, so no lock.
    private var rightDownAt: CFTimeInterval = 0

    /// **The right chord has no hold to wait out, since 2026-09-04.**
    ///
    /// It was judged against `chordHoldSeconds` like the left one, and that
    /// threshold was the bug: right-press then wheel — the two halves of one
    /// quick motion — land inside 0.3s often enough that the press fell straight
    /// through to the branch at the bottom of this file and opened a dictation
    /// *at the terminal already bound*, which is the one destination this
    /// gesture exists to get away from. Doing it again more slowly "worked",
    /// which is exactly how a timing threshold feels from the outside.
    /// Reported 2026-09-04: *"the tool thinks I want to dictate to the existing
    /// bound terminal … if I repeat it a bunch of times, I make it work"*.
    ///
    /// The threshold was borrowed reasoning. It earns its keep on the **left**
    /// chord, where a click-drag with the wheel pressed on top of it is a real
    /// thing to rule out. Nothing is like that on the right: there is no
    /// right-drag anyone finishes with a middle click, so the button being down
    /// at all is already the entire signal.
    ///
    /// **And the window server is asked as well as our own bookkeeping.** A
    /// press this tap never saw — re-enabled after a timeout mid-gesture, or a
    /// menu tracking loop in the way, which is what Victor guessed was happening
    /// — leaves `rightDownAt` at zero while the finger is very much down, and
    /// that is the same failure wearing a different hat.
    private var rightIsHeld: Bool {
        rightDownAt > 0 || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    /// **Our own bookkeeping can go stale; the window server cannot.** A release
    /// this tap never saw would otherwise leave a button held for good — every
    /// bare wheel click read as a chord, which is the reported bug pointing the
    /// other way. Run before any chord is judged, so the two always agree.
    private func reconcileButtons() {
        if leftDownAt > 0 && !CGEventSource.buttonState(.combinedSessionState, button: .left) {
            leftDownAt = 0
        }
        if rightDownAt > 0 && !CGEventSource.buttonState(.combinedSessionState, button: .right) {
            rightDownAt = 0
        }
    }

    /// The hold fired (or the chord was taken) — the matching release is ours
    /// too, or the app underneath is left holding a button that was never let go.
    private var wheelArmed = false
    /// A press we swallowed and have not yet judged.
    private var wheelDown = false
    /// The same, for the left chord. There the release has nothing to do — the
    /// bind fired at the press — but it still has to be told apart from a bare
    /// wheel, whose release is the whole gesture.
    private var wheelLeftChord = false
    private var wheelHold: DispatchWorkItem?

    /// **When ⌃⌥⌘F10 (🔼 →) last fired for real** (2026-09-16). Victor: *"fac
    /// gestul de forward-dreapta și cumva cred că-l fac de două ori, pentru că
    /// se și pornește și se și închide dictarea instant"* — one flick toggling
    /// the microphone open and immediately shut. The autorepeat guard above
    /// only catches the OS's own key-repeat flag, and a synthetic Options+ tap
    /// never carries one; a gesture engine re-triggering on the tail of the
    /// same continued motion looks exactly like a second, deliberate flick.
    /// So a second F10 arriving inside `gestureRetriggerSeconds` of the first
    /// is dropped rather than toggling the microphone straight back — no
    /// physical second gesture lands that fast, and one that legitimately does
    /// only costs a fraction of a second's delay.
    ///
    /// **It came back on 2026-09-18**, with the flick made slowly: *"if I hold
    /// down the forward button and move the mouse to the right, if I keep moving
    /// it to the right, that gesture both starts and then immediately ends the
    /// transcription"*. Two things were wrong with the third of a second above.
    /// It was measured against the last F10 **this tap acted on**, so a train of
    /// re-fires at, say, 300 ms let every second one through — dropped, acted
    /// on, dropped, acted on. And it was too short for a hand that goes on
    /// moving: Options+ re-fires for as long as the motion lasts, not once per
    /// flick. So the window **slides** — a dropped tap stamps `lastF10At` too,
    /// which makes the guard last as long as the motion rather than as long as
    /// one interval — and it is `0.6` s, which is longer than any gap inside one
    /// continued movement and shorter than letting go of the button, moving back
    /// and pressing again.
    private var lastF10At: CFTimeInterval = 0
    /// The last 🔽 → (F5, Return), for the same re-trigger guard.
    private var lastF5At: CFTimeInterval = 0
    /// The last back click that posted Wispr's toggle — see the F6 case.
    private var lastBackToggleAt: CFTimeInterval = 0
    private static let backToggleSettleSeconds: CFTimeInterval = 0.8
    private static let gestureRetriggerSeconds: CFTimeInterval = 0.6

    /// **A sentence younger than this cannot be ended by 🔼 →** (2026-09-18) —
    /// Victor's own fallback for the same report: *"or at least just put a two
    /// seconds minimum threshold between stopping after starting"*.
    ///
    /// It is the belt to `gestureRetriggerSeconds`' braces, and it is worth
    /// having both: the sliding window is a guess about how a gesture engine
    /// re-fires, while this one is a statement about the gesture's meaning —
    /// within two seconds of opening the microphone, ➡️ can only be the flick
    /// that opened it arriving twice. **Only the stop is guarded**; a flick that
    /// would *start* a dictation, bind, or redirect a caret sentence at the
    /// bound terminal is never delayed by it, and ⌘⌃D and the ⬅️ cancel are not
    /// touched at all — a key pressed twice in a second is a hand meaning it,
    /// and throwing a sentence away must never be the gesture that waits.
    ///
    /// The price is real and accepted: a deliberate one-word dictation cannot be
    /// closed with the same flick for two seconds. ⌘⌃D closes it immediately.
    private static let gestureStopDwellSeconds: CFTimeInterval = 2.0

    // MARK: - The wheel drag that selects a region

    /// Where the wheel went down, while it is still an open question whether
    /// this is a click or a drag. Cleared at the release, and never set by a
    /// press that already meant something else (a chord, a prompt on screen).
    private var areaAnchor: NSPoint?
    /// The same corner as `CGEvent.location` reads it — global, y **down** from
    /// the primary display's top. The threshold is measured against this and not
    /// against the Cocoa anchor, because an event carries the position it was
    /// *made* at while `NSEvent.mouseLocation` answers where the pointer is by
    /// the time the tap asks. They differ by one event, which is nothing to a
    /// hand and everything to a burst of posted events — the arm was silently
    /// skipped for a drag delivered faster than the pointer could be read.
    private var areaAnchorCG: CGPoint = .zero
    private var areaPressedAt = Date()
    /// The drag crossed the threshold: the overlay is up, and this press is the
    /// crop's from here to the release.
    private var areaCropping = false
    /// **Did the press go out?** The release has to match it, and which it was
    /// depends on the gesture mode: in Logi mode this branch hands the press
    /// straight back, while with the flag off the wheel's own branch below
    /// swallows it. Passing a release whose press was swallowed hands the app
    /// underneath an orphan; swallowing a release whose press went out leaves
    /// the window server believing the button is still down — which it does,
    /// for hours, dragging whatever the press landed on around behind the
    /// cursor. Measured on 2026-09-10, seven hours after the crop that caused
    /// it, with an editor tab stuck to the pointer.
    private var areaPressPassed = false

    /// **How far the hand has to travel before a middle click stops being one.**
    ///
    /// Victor's rule for this gesture, and it is the whole of it: *"ar trebui să
    /// ignori click/dublu-click de wheel — doar drag ne interesează."* A click
    /// is never perfectly still, and a double click is two of them in quick
    /// succession over whatever he happens to be reading, so the number has to
    /// be comfortably past a hand's tremor rather than at the edge of it. It was
    /// 6 for a day — the same distance `CropSelectionOverlay` refuses to call a
    /// selection — which is the right floor for *"is this box worth
    /// capturing?"* and too fine for *"did he mean to drag at all?"*.
    ///
    /// Nothing is lost by waiting: the corner was recorded at the press, so the
    /// only thing these points buy is the moment the dimming appears.
    private static let areaDragThreshold: CGFloat = 12

    /// **How close the wheel's second click has to land** for the dictation the
    /// first one started to become a spawn (Victor, 2026-09-05).
    ///
    /// This replaced a 2s *hold*, which lasted one day and never once fired.
    /// `relay.log` says why: the hold's timer guarded on `dictating`, a flag the
    /// tap only learns from `syncBorrowedGestures` after the recording is up, so
    /// on a cold model it was still false at the 2s mark — and when it was true,
    /// the press had long since been read by the branch below as *hold to
    /// cancel*, whose 1s timer wins every race against a 2s one. Two holds on
    /// one button, told apart by a flag that arrives late, is not a gesture.
    ///
    /// A double click has no such race: both presses are events, and the second
    /// one is judged the instant it arrives.
    private static let spawnDoubleSeconds: TimeInterval = 0.6

    /// When the wheel last opened a dictation on its own. The second click is
    /// measured from **the press that started it**, not from the release, so a
    /// slow finger on the first click does not eat the window.
    private var wheelDictateAt: TimeInterval = 0

    /// When the wheel was last clicked **while this app wanted nothing to do
    /// with it** — unbound, not dictating, the press passed straight through to
    /// whatever was underneath. It is the only trace such a click leaves, and it
    /// is what the second one of a double click is measured against.
    private var idleWheelClickAt: TimeInterval = 0

    /// A rest-press that started a dictation and whose wheel is still down —
    /// the press whose release takes the deferred context shot. Set false by
    /// every other kind of press.
    private var wheelHeldFromPress = false

    /// **Take the undecided press, if it is still going.** Every gesture with a
    /// hold has two claimants racing for one press: the timer, which runs on the
    /// main queue, and the release, which arrives on the tap thread. They both
    /// used to read `wheelDown` and then act on it, so a button let go in the
    /// same millisecond the timer fired ran **both** halves — a disconnect *and*
    /// a spawn, or a dictation opened twice, which is `mic.start` called twice.
    ///
    /// Whoever gets here first acts; the loser finds it already taken.
    ///
    /// `wheelArmed` is set **before** `wheelDown` is cleared, and both inside the
    /// lock: the release's own swallow test reads `wheelArmed || wheelDown`, and
    /// a window in which neither is true is a middle-up handed to an app that
    /// never saw the middle-down — the orphan-event bug this file guards against
    /// everywhere else.
    /// **The wheel dragged while a dictation is open: select a region.**
    ///
    /// Answers whether the event must be swallowed. Called from **both** gesture
    /// modes, before either of them decides anything else about the wheel, and
    /// it is written to be inert in every state but the one it is for.
    ///
    /// The shape of it is Victor's answer to the one thing this gesture costs:
    /// the press is **passed through**, so a middle click that never becomes a
    /// drag still closes a Chrome tab, and only the release of a press that
    /// *did* become one is swallowed. The app underneath is then holding a
    /// middle-down it will never see the up for — the orphan this file guards
    /// against twice — and that is the deliberate trade, taken with the
    /// alternatives on the table: eating every middle click for the length of
    /// every dictation, or reviving the replay that was deleted on 2026-09-06.
    /// Nothing measured acts on a middle-up that never arrives; a middle-down
    /// that never arrives loses the click he made.
    ///
    /// **It is judged on the tap thread and nowhere else**, which is what makes
    /// the swallow decision raceless: the drag that arms the crop and the
    /// release that ends it are the same serial stream of events.
    private func areaDrag(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.mouseEventButtonNumber) == MOUSE_BUTTON_MIDDLE else { return false }

        switch type {
        case .otherMouseDown:
            areaAnchor = nil
            areaCropping = false
            haloDialed = false
            // **Bare, and with no chord underneath it.** ⌘ and ⌥ mean something
            // *inside* the selection — move the box, draw it from its middle —
            // but at the press they are the spawn's modifier and would be two
            // gestures on one press. A press the chords or a held prompt have
            // already spoken for is not available either.
            let bare = !event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl)
                    && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift)
            guard dictating, bare, !promptHeld, !leftIsHeld, !rightIsHeld else { return false }
            areaAnchor = NSEvent.mouseLocation
            areaAnchorCG = event.location
            areaPressedAt = Date()
            areaPressPassed = useLogiGestures
            return false

        case .otherMouseDragged:
            if areaCropping {
                // **The box follows the events, not a timer.** Every one of
                // these is about to be swallowed, so the overlay would otherwise
                // be left polling `NSEvent.mouseLocation` from a main-thread
                // timer for a position this thread already has in its hand — and
                // a box that stops following the hand while the wheel is held is
                // exactly what that timer looks like when it is starved.
                let where_ = event.location
                DispatchQueue.main.async { CropSelectionOverlay.dragMoved(toCG: where_) }
                return true
            }
            // **A press that has been turned is a dial, not a drag** — see
            // `haloDial`. The hand wobbles while it works the wheel, and a box
            // opening under a halo he is choosing is the collision this guards.
            guard let anchor = areaAnchor, dictating, !haloDialed else { return false }
            let now = event.location
            guard hypot(now.x - areaAnchorCG.x, now.y - areaAnchorCG.y) >= Self.areaDragThreshold else { return false }
            areaCropping = true
            // **With *Use Logi Gestures* off the press was swallowed and still
            // means something** — a dictation to end, and a 2s timer that would
            // cancel it. Claiming it is what takes both away: the release then
            // finds `tapped` false and fires nothing, and the timer's own
            // `claimWheelPress` comes back empty. In Logi mode the press was
            // passed through, so this claims nothing and costs nothing.
            _ = claimWheelPress()
            wheelHold?.cancel()
            wheelHold = nil
            Log.info("✂️ wheel dragged while dictating — selecting an area")
            let at = areaPressedAt
            DispatchQueue.global().async { [weak self] in self?.onAreaShot?(anchor, at) }
            return true

        case .otherMouseUp:
            let cropping = areaCropping
            areaAnchor = nil
            areaCropping = false
            haloDialed = false
            // **The press's own bookkeeping is finished here, because this
            // release never reaches the branch that normally finishes it.** With
            // *Use Logi Gestures* off the press was swallowed and `wheelArmed`
            // was set by the claim above; left standing it would swallow the
            // release of the *next* middle press — one this file passed through
            // — and hand the app underneath an up it never saw a down for. That
            // is the orphan-event bug, and it is the third place this file has
            // had to be told about it. In Logi mode none of these were ever set
            // and clearing them costs nothing.
            if cropping {
                wheelArmed = false
                wheelDown = false
                wheelLeftChord = false
                wheelHold?.cancel()
                wheelHold = nil
            }
            // **Say so, because the overlay is no longer allowed to look.** A
            // drag handed in is one the tap owns from both ends, so the panel
            // stops polling session button state and waits to be told — see
            // `CropSelectionOverlay.driven`, and the two ways that poll is wrong
            // once a tap has an opinion about the button.
            if cropping { onAreaEnd?() }
            // **The release matches the press, always.** Ours only if the press
            // was ours; out if the press went out, whatever happened in between.
            return cropping && !areaPressPassed

        default:
            return false
        }
    }

    // MARK: - The halo dial: wheel held, wheel turned (2026-09-20)

    /// **Is the ring up** — the gate for the halo dial, pushed in from
    /// `syncBorrowedGestures` beside `caretHalo.setActive`, so the two cannot
    /// disagree about what *dictating* means for a gesture that is about the
    /// halo. Written from the main thread, read from the tap thread.
    var haloUp: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return haloUpFlag }
        set { stateLock.lock(); haloUpFlag = newValue; stateLock.unlock() }
    }
    private var haloUpFlag = false

    /// One notch: `+1` for up (the next halo), `−1` for down (the previous).
    /// Delivered on the main queue.
    var onHaloDial: ((Int) -> Void)?
    /// **Bare F7 / F9 step the halo** (Victor, 2026-09-20 late: *"F7 și F9 să
    /// schimbe efectul curent"*): F9 forward, F7 back, outside a dictation
    /// too. No modifier — the ⌃⌥⌘F7/F9 chords are Options+'s gestures and
    /// stay theirs. On a Mac keyboard these need *Use F1, F2… as standard
    /// function keys*, or the keys arrive as media keys and never reach this.
    var onHaloStep: ((Int) -> Void)?

    /// This press has been turned, so it is a dial and not a drag: the crop
    /// refuses to arm for the rest of it, whatever the hand does. Reset by
    /// `areaDrag` at every middle press and release.
    private var haloDialed = false
    private var lastHaloDialAt: CFTimeInterval = 0
    /// One step per notch — a wheel spun fast reports several lines per
    /// event and several events a frame, and a dial that skipped three halos
    /// on one flick is one he cannot aim.
    private static let haloDialDebounce: CFTimeInterval = 0.12

    /// **Middle button held, wheel turned, ring up: the next (or previous)
    /// halo.** Victor, 2026-09-20: a way to change the effect without opening
    /// a menu, *only while dictating*. Outside that state — or with the middle
    /// button up — every scroll passes through untouched, because this is a
    /// global tap on his everyday machine and a swallowed middle-scroll in
    /// another app is a regression nobody would forgive.
    ///
    /// **Same button as the crop drag, told apart by what the hand does.** The
    /// crop arms once the pointer has travelled `areaDragThreshold` with the
    /// wheel down; this fires on the wheel *turning* with the wheel down. The
    /// first of the two to happen owns the press: a press that has dialed
    /// cannot become a crop (`haloDialed`), and a press that is cropping does
    /// not dial (`areaCropping`) — its scrolls pass through, since a hand
    /// dragging a box is not aiming a dial. In Wheel mode the press has
    /// meanings of its own, and the dial claims it exactly as the drag does
    /// (`claimWheelPress`, the hold cancelled), so the release ends nothing.
    ///
    /// The button is asked of the window server rather than of this tap's
    /// bookkeeping: in Logi mode the press goes straight past and leaves no
    /// mark here, and `rightIsHeld` already reaches for the same instrument.
    private func haloDial(_ event: CGEvent) -> Bool {
        guard haloUp, !areaCropping else { return false }
        guard CGEventSource.buttonState(.combinedSessionState, button: .center)
           || CGEventSource.buttonState(.hidSystemState, button: .center) else { return false }
        // Ours from here: the wheel is down and the ring is up, so nothing
        // underneath should scroll — including a trackpad's momentum tail.
        if !haloDialed {
            haloDialed = true
            _ = claimWheelPress()
            wheelHold?.cancel()
            wheelHold = nil
        }
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return true }
        let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        guard delta != 0 else { return true }
        let now = CACurrentMediaTime()
        guard now - lastHaloDialAt >= Self.haloDialDebounce else { return true }
        lastHaloDialAt = now
        let step = delta > 0 ? 1 : -1
        Log.info("✨ wheel held and turned \(step > 0 ? "up" : "down") over the ring — \(step > 0 ? "next" : "previous") halo")
        DispatchQueue.main.async { [weak self] in self?.onHaloDial?(step) }
        return true
    }

    private func claimWheelPress() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard wheelDown else { return false }
        wheelArmed = true
        wheelDown = false
        return true
    }

    /// **Is the forward button physically down, according to the window server?**
    ///
    /// The event stream cannot answer this. Something between the mouse and this
    /// tap — the receiver, Logi's own agent, or LinearMouse, which already
    /// rewrites the *back* button into a Return — hands the forward button over
    /// as an 18ms down-and-up pair however long it is actually held (measured
    /// 2026-09-04). A gesture defined by duration cannot be built on a stream
    /// that has thrown the duration away.
    ///
    /// `CGEventSourceButtonState` is the way round it, and it is the same
    /// instrument `rightIsHeld` already reaches for when a press this tap never
    /// saw leaves its own bookkeeping stale. **Both state IDs are asked**:
    /// `.hidSystemState` is the hardware, `.combinedSessionState` includes
    /// whatever has been synthesized on top of it, and a button that is down in
    /// either is down.
    ///
    /// `CGMouseButton(rawValue: 4)` is not nil — the type is imported from a C
    /// enum and takes any raw value, which is what makes the two side buttons
    /// askable at all.
    private static let forwardButton = CGMouseButton(rawValue: 4) ?? .center

    static func mouse5IsPhysicallyDown() -> Bool {
        CGEventSource.buttonState(.hidSystemState, button: forwardButton)
            || CGEventSource.buttonState(.combinedSessionState, button: forwardButton)
    }

    /// When the current press went down, for the log line at its release.
    private var mouse5PressedAt: CFTimeInterval = 0

    private let stateLock = NSLock()

    private let VK_B: CGKeyCode = 0x0B
    private let VK_D: CGKeyCode = 0x02
private let VK_P: CGKeyCode = 0x23
    private let VK_RETURN: CGKeyCode = 0x24        // Return
    private let VK_KEYPAD_ENTER: CGKeyCode = 0x4C  // Enter (keypad / Fn-Return)
private let VK_ESCAPE: CGKeyCode = 0x35        // esc

    // **The side buttons, arriving as keys.** Logi Options+ holds a custom
    // gesture per direction on each of the two side buttons and emits one of
    // these with ⌃⌥⌘ held. The numbers are Victor's, chosen in the Options+ UI
    // on 2026-09-09, and the two halves must not drift: change one here and the
    // gesture goes to whatever app claims that chord instead. They are written
    // down in CLAUDE.md under *The side buttons speak in function keys*.
    private let VK_F3:  CGKeyCode = 0x63
    private let VK_F4:  CGKeyCode = 0x76
    private let VK_F5:  CGKeyCode = 0x60
    private let VK_F6:  CGKeyCode = 0x61
    private let VK_F7:  CGKeyCode = 0x62
    private let VK_F8:  CGKeyCode = 0x64
    private let VK_F9:  CGKeyCode = 0x65
    private let VK_F10: CGKeyCode = 0x6D
    private let VK_F11: CGKeyCode = 0x67
    private let VK_F12: CGKeyCode = 0x6F
    private let MOUSE_BUTTON_4: Int64 = 3   // 0-indexed "back" side button — LinearMouse types Return with it
    private let MOUSE_BUTTON_5: Int64 = 4   // 0-indexed "forward" side button
    private let MOUSE_BUTTON_MIDDLE: Int64 = 2   // the wheel, pressed

    private var tapPort: CFMachPort?
    var isActive: Bool { tapPort != nil }

    @discardableResult
    func start() -> Bool {
        // On the main thread, where HIToolbox insists it be read — see
        // `refreshKeyboardLayout`.
        Self.refreshKeyboardLayout()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { _ in Self.refreshKeyboardLayout() }
        // `keyUp` and `flagsChanged` are here only for the injection block: a
        // synthetic ⌘V is a modifier press, a key down and a key up, and letting
        // two thirds of that through would leave the target app holding a ⌘ that
        // was never released.
        // **The mouse is subscribed to in both modes.** The mask is fixed when
        // the tap is created and *Use Logi Gestures* can be flipped at any
        // moment from the menu, so the events have to be arriving already; in
        // Logi mode every one of them is handed straight back, one comparison
        // later. Rebuilding the tap on a toggle would be the alternative, and it
        // would mean tearing down the thing that carries ⌘⌃B while a dictation
        // may be running.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.keyUp.rawValue)
                 | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                 | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                 | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
                 // **Drags, for the one gesture that is a drag.** A middle press
                 // cannot be told from a middle click at the press — the
                 // difference is whether the hand then moves — so the only place
                 // the question can be answered is in the events between them.
                 // Everything that is not a middle drag goes straight back out.
                 | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
                 // **The wheel's turn, for the one gesture that reads it** — the
                 // halo dial (2026-09-20). Every scroll on the machine comes past
                 // here and goes straight back out unless the middle button is
                 // down while the ring is up; see `haloDial`.
                 | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
                 | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                 | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
                 | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
                 | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.error("could not create event tap — grant Accessibility permission to Walkie Talkie")
            return false
        }
        tapPort = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "WalkieTalkieEventTap"
        thread.start()
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable after a system timeout disable, else the tap dies silently.
        if type.rawValue == 0xFFFFFFFE || type.rawValue == 0xFFFFFFFF {
            if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // The canary — see `proveAlive`. Ours, harmless, and never let through.
        if event.getIntegerValueField(.eventSourceUserData) == Self.canaryStamp {
            stateLock.lock(); canarySeenAt = CFAbsoluteTimeGetCurrent(); stateLock.unlock()
            return nil
        }

        // **The wheel turned: the halo dial, in both modes, or nothing.** Judged
        // before either mode's wiring because neither reads a scroll — this is
        // the only branch that does, and everything it does not take goes out
        // untouched.
        if type == .scrollWheel {
            return haloDial(event) ? nil : Unmanaged.passUnretained(event)
        }

        // **In Logi mode every mouse button goes straight past.** The two side
        // buttons could not be read even if this app wanted them — they are
        // diverted inside the mouse and reach neither this tap nor the raw HID
        // report — and the wheel is deliberately handed back, which is what
        // returns middle-click-to-close-a-tab to Chrome and VS Code. See *The
        // side buttons speak in function keys* in CLAUDE.md.
        //
        // With the flag off, everything below is the pre-2026-09-09 wiring,
        // unchanged.
        //
        // **The left button is the one exception, and it is watched rather than
        // taken.** Since the bind moved onto ⬅️ held + the forward button
        // clicked, this mode needs the same one fact the wheel's chord needed:
        // *when did the left button go down*. The event is handed straight back
        // either way — nothing in this file may ever swallow one.
        if useLogiGestures {
            switch type {
            case .leftMouseDown:
                leftDownAt = CACurrentMediaTime()
                leftDownPoint = event.location
                return Unmanaged.passUnretained(event)
            case .leftMouseUp:
                noteLeftRelease(at: event.location,
                                clicks: event.getIntegerValueField(.mouseEventClickState))
                return Unmanaged.passUnretained(event)
            case .rightMouseDown, .rightMouseUp:
                return Unmanaged.passUnretained(event)
            case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                // A stale `leftDownAt` would read as a chord and refuse the
                // drag; `areaDrag` asks about both buttons, so it gets the same
                // reconciliation the wheel's own chords get below.
                reconcileButtons()
                // **The one thing this mode takes, and only once it is a drag.**
                // Everything else about the wheel — the click that closes a tab
                // — goes past untouched, which is the whole reason this mode
                // exists.
                if areaDrag(type, event) { return nil }
                return Unmanaged.passUnretained(event)
            default:
                break
            }
        } else {
            // **Watched, never taken.** Every left click in the session comes past
            // here and every one goes straight back out; all this records is when the
            // button went down, which is what the wheel's rebind chord is judged
            // against. Nothing else in this file may ever swallow one — that button
            // is how the Mac is used.
            if type == .leftMouseDown {
                leftDownAt = CACurrentMediaTime()
                leftDownPoint = event.location
                return Unmanaged.passUnretained(event)
            }
            if type == .leftMouseUp {
                noteLeftRelease(at: event.location,
                                clicks: event.getIntegerValueField(.mouseEventClickState))
                return Unmanaged.passUnretained(event)
            }

            // **The right button, watched on exactly the same terms.** It is the
            // other half of the unbind chord and nothing else here; every press and
            // release goes straight back out, because a swallowed right click is a
            // context menu that never opened.
            if type == .rightMouseDown {
                rightDownAt = CACurrentMediaTime()
                return Unmanaged.passUnretained(event)
            }
            if type == .rightMouseUp {
                rightDownAt = 0
                return Unmanaged.passUnretained(event)
            }

            // **The region drag, before the wheel's own five meanings.** It is
            // the only branch that reads `.otherMouseDragged`, and the only one
            // that can take a press back from the meaning it already had — see
            // `areaDrag`, where the claim is made.
            if type == .otherMouseDown || type == .otherMouseUp || type == .otherMouseDragged {
                reconcileButtons()
                if areaDrag(type, event) { return nil }
                if type == .otherMouseDragged { return Unmanaged.passUnretained(event) }
            }

            if type == .otherMouseDown || type == .otherMouseUp {
                // Before anything below reads `leftIsHeld` or `rightIsHeld`.
                reconcileButtons()
                let button = event.getIntegerValueField(.mouseEventButtonNumber)
                let bare = !event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl)
                        && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift)
                // Mouse 4 mid-dictation → a picture, and the Return it would have
                // become never happens. Both halves of the click are swallowed:
                // LinearMouse is downstream of this tap and would otherwise still
                // see an orphan release to act on.
                //
                // At rest the button is nobody's again — LinearMouse's Return. The
                // 0.6s hold-to-spawn it carried for an afternoon is gone (Victor,
                // 2026-09-04): the same doubt that killed it on the forward button
                // never got answered here either, and the wheel grew the hold
                // instead — see the bare-wheel branch below.
                if button == MOUSE_BUTTON_4 && bare && dictating {
                    if type == .otherMouseDown {
                        Log.info("📸 mouse 4 — reached the tap as a mouse button")
                        let cursor = NSEvent.mouseLocation
                        DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                    }
                    return nil
                }

                // **Replace Wispr: the forward button opens the microphone.**
                //
                // The mode exists because dictating into an agent and dictating into
                // *the machine* are two different jobs, and Victor already had a tool
                // for the second one. This is that job, on this app's recogniser: press
                // to start, press to stop, and the words appear at the caret.
                //
                // **The forward button and not the wheel**, deliberately. The wheel is
                // the relay's whole vocabulary — dictate, cancel, bind, disconnect,
                // spawn — and every one of those meanings is about a *terminal*. A
                // mode that types into whatever is in front has no business colliding
                // with them, and the hand can hold this one without learning a chord.
                //
                // **It outranks the double click below.** That gesture binds a window,
                // which is the one thing this mode is not about; and the two cannot be
                // told apart at the press anyway — a first click that had to wait out
                // the double-click interval before opening the microphone is exactly
                // the wait Victor had removed from the wheel. `lastMouse5DownAt` is
                // zeroed so a second press is a second dictation rather than half a
                // bind.
                //
                // The release is swallowed by the branch below, on `swallowMouse5Up`:
                // LinearMouse sits downstream and must never be handed an orphan.
                if button == MOUSE_BUTTON_5 && bare && replaceWispr && type == .otherMouseDown {
                    swallowMouse5Up = true
                    lastMouse5DownAt = 0
                    Log.info("🎙️ forward button — Replace Wispr")
                    DispatchQueue.global().async { [weak self] in self?.onPasteToggle?() }
                    return nil
                }

                // **Every forward-button edge this tap sees, written down.**
                //
                // Reported 2026-09-04: holding it did not open a session. The log had
                // nothing at all about mouse 5 in the two hours around it — no press,
                // no double click, no hold — while a synthetic press through the same
                // code path worked first time. That is the one diagnosis this app
                // could not make: *did the event arrive?* is the question every other
                // explanation is downstream of, and nothing was recording the answer.
                // It is one line per press on a button pressed a few times an hour.
                if button == MOUSE_BUTTON_5 {
                    let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
                    if type == .otherMouseDown {
                        mouse5PressedAt = CACurrentMediaTime()
                        Log.info("🖱️ mouse 5 down — bare=\(bare) pid \(pid) remapper=\(isRemapper(pid)) physical=\(Self.mouse5IsPhysicallyDown())")
                    } else {
                        // **The duration was the whole diagnosis, and it answered.**
                        // Measured 2026-09-04, on a press Victor was deliberately
                        // holding: **18ms**. The button does not reach this tap as a
                        // press and a release — it reaches it as an instantaneous
                        // pair, so a threshold of any length can never be met. See
                        // `mouse5IsPhysicallyDown` for what is done about it; the pid
                        // and the physical state here are what say *which* of the
                        // two shapes the pair has.
                        let ms = Int((CACurrentMediaTime() - mouse5PressedAt) * 1000)
                        Log.info("🖱️ mouse 5 up — held \(ms)ms, pid \(pid) remapper=\(isRemapper(pid)) physical=\(Self.mouse5IsPhysicallyDown())")
                    }
                }

                // **The forward button is a pass-through again, apart from the
                // double click.** The 0.6s hold it carried for a day moved to the
                // back button: this one arrives as an ~20ms down-and-up pair however
                // long it is held — and `CGEventSourceButtonState` agrees — so a
                // hold of it can never be judged. Measured 2026-09-04 on Victor's
                // deliberate holds; Wispr Flow's push-to-talk, which lives on this
                // button, is the suspect. The swallow-and-judge machinery went with
                // the gesture, so a plain click no longer pays the replay's latency.
                //
                // The double-click test comes first, and applies whether or not
                // anything is bound: binding by pointing is most useful precisely
                // when nothing is bound yet.
                if button == MOUSE_BUTTON_5 && bare {
                    if type == .otherMouseUp {
                        // **Any release whose press we took is ours**: a double
                        // click's second half, or a Replace Wispr press. Nothing
                        // downstream may be handed an up it never saw a down for.
                        if swallowMouse5Up {
                            swallowMouse5Up = false
                            return nil
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    if type == .otherMouseDown {
                        let now = CACurrentMediaTime()
                        if now - lastMouse5DownAt <= NSEvent.doubleClickInterval {
                            // Zeroed rather than restamped, so a third click starts a
                            // fresh pair instead of binding again on every press.
                            lastMouse5DownAt = 0
                            swallowMouse5Up = true
                            Log.info("🎯 mouse 5 ×2 — binding")
                            // **Global, not main** — the same queue ⌘⌃B uses, and for
                            // the reason it uses it: `bindFrontmostTerminal` asks the
                            // main thread for the frontmost app with `main.sync`, so
                            // arriving there already on main is a wait for a queue
                            // that is waiting for you. libdispatch does not deadlock
                            // on that, it traps — this crashed the app on the first
                            // real double-click.
                            DispatchQueue.global().async { [weak self] in self?.onMouse5Double?() }
                            return nil
                        }
                        lastMouse5DownAt = now
                        // A plain click is handed straight through — mouse 5 is
                        // nobody's (and Wispr Flow's).
                    }
                }

                // **The wheel means one thing on its own, and another with the left
                // button already held.**
                //
                //   wheel, alone         → start the dictation, or end the open one
                //   wheel, dictating,
                //     held two seconds   → cancel it: throw the audio away
                //   left held, then
                //     wheel              → bind: point the relay at the window in front
                //   left held, then
                //     wheel held 1s      → …and start the dictation at it
                //   right held, then
                //     wheel              → disconnect: let the binding go
                //
                // **Starting used to cost a one-second hold and now costs a tap.**
                // The hold was buying one thing: a bare middle click could still be
                // handed back to whatever was underneath, so Chrome went on opening
                // links in new tabs while a terminal was bound. Victor gave that up
                // deliberately — the gesture he makes dozens of times a day should
                // not be the one with a wait in it. So while something is bound the
                // wheel is the relay's, and middle-click in a browser is not
                // available until the session ends.
                //
                // **Rebinding moved onto the left button because it had to move off
                // the wheel.** With a tap meaning "dictate" there is nothing left for
                // a tap to also mean, and the old rules — a tap over a bindable
                // window binds, a hold with nothing bound binds — were exactly the
                // ones a tap now collides with. A chord is not a compromise here: it
                // is unmistakable, it needs no timer to disambiguate, and the hand
                // that rebinds is already on the mouse pointing at the terminal it
                // means.
                //
                // The press is still swallowed and acted on at the release for the
                // dictation cases, because a hold has to be told from a tap. The
                // alternative — pass the press through and swallow only the release —
                // leaves whatever is underneath holding a button that never came up,
                // which is the orphan-event bug this file already guards against
                // twice, pointing the other way.

                // **The other chord: right held + wheel → let the binding go.**
                // Judged at the press like the bind above, and placed **before**
                // both it and the dictation branch, because it is the one gesture
                // here that has to work in every state — including mid-dictation,
                // where the wheel already means "cancel" if held and "end it" if
                // tapped. Disconnect outranks both: it is the answer to *stop, this
                // is going to the wrong place*, and it would be a poor one if it
                // first needed the sentence to be over.
                //
                // Nothing bound is nothing to disconnect, and the branch is skipped
                // so the click stays available to whatever is underneath.
                //
                // **Held, it used to open a session instead of closing one**, and
                // that second reading is gone (Victor, 2026-09-06). The spawn keeps
                // the two routes that do not need this chord — the bare wheel
                // clicked twice, and the menu's **Start dictation to new claude** — so what
                // the hold bought was a third way in, at the price of the chord
                // having to be *told apart from itself*: the disconnect could not
                // fire until the finger came up, and a tap that Victor made in a
                // hurry was one timer away from opening a session he did not ask
                // for.
                //
                // **So it is judged at the press again**, like the left chord: one
                // reading, nothing to wait out, and the unbind burst goes off under
                // the finger that ordered it.
                //
                // The press is swallowed either way — `wheelArmed` claims the
                // release with it — so a right-held wheel click never falls through
                // to the dictation branches below and never reaches the app
                // underneath half a gesture. Nothing bound is nothing to
                // disconnect: then the chord is simply inert.
                if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseDown && bare && rightIsHeld {
                    // A hold timer from a press we are now overriding must not fire
                    // on the dictation this click is ending.
                    wheelHold?.cancel()
                    wheelHold = nil
                    wheelDown = false
                    wheelArmed = true
                    wheelLeftChord = false
                    if bound {
                        Log.info("🔌 right held + wheel — disconnecting")
                        DispatchQueue.global().async { [weak self] in self?.onGestureUnbind?() }
                    }
                    return nil
                }

                // **A prompt on screen outranks everything else the wheel means.**
                // It is the same verdict a click on the panel already gives and the
                // same one ⏎ gives; what it adds is that the hand which just clicked
                // the words to edit them does not have to travel to the keyboard to
                // approve them. Acted on the press, with no hold to wait out: there
                // is no second meaning here to tell it apart from.
                if button == MOUSE_BUTTON_MIDDLE && bare && promptHeld {
                    if type == .otherMouseDown {
                        DispatchQueue.main.async { [weak self] in self?.onPromptEnter?() }
                    } else {
                        // **This release consumes whatever the press armed**, since
                        // it is swallowed here instead of at the branch below that
                        // normally clears the flags. Left set, `wheelArmed` would
                        // swallow the release of the *next* press — one this file
                        // passed through — which is precisely the orphan-event bug
                        // the branch below exists to prevent.
                        wheelArmed = false
                        wheelDown = false
                        wheelLeftChord = false
                        wheelHold?.cancel()
                        wheelHold = nil
                    }
                    return nil
                }

                // **Any release whose press we swallowed is ours**, whatever the
                // state has become in between — the left button may have come up,
                // the binding may have been dropped, the dictation may have ended
                // another way. The app underneath must never be handed a middle-up
                // it never saw a middle-down for; that is the orphan-event bug this
                // file guards against twice already, and re-deciding the state at the
                // release is how you write it a third time.
                //
                // This is also where a plain click becomes a dictation: `wheelArmed`
                // means something already fired on the press or during the hold, so
                // what is left — a press we took and nothing acted on — is the tap.
                if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseUp && (wheelArmed || wheelDown) {
                    let left = wheelLeftChord
                    // **The one place a tap is decided**, and it is a claim rather
                    // than a test: the hold timer is racing this release for the same
                    // press, and both acting is one gesture doing two things. See
                    // `claimWheelPress`.
                    let tapped = claimWheelPress()
                    wheelArmed = false
                    wheelLeftChord = false
                    wheelHold?.cancel()
                    wheelHold = nil
                    // A press that started a dictation takes its context shot
                    // **now**, at the release, per Victor 2026-09-04 (see
                    // `onWheelDictate`).
                    let contextAtRelease = wheelHeldFromPress
                    wheelHeldFromPress = false
                    guard tapped else {
                        if contextAtRelease {
                            DispatchQueue.global().async { [weak self] in self?.onWheelRelease?() }
                        }
                        return nil
                    }
                    if left {
                        // Nothing: the bind fired at the press, and the hold that
                        // would also have started a dictation did not last.
                    } else if localCapture || dictating {
                        Log.info(dictating ? "🎙️ wheel tapped — ending the dictation"
                                           : "🎙️ wheel tapped — starting a dictation")
                        DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                    }
                    return nil
                }

                // **The chord, judged at the press.** `chordHoldSeconds` is what
                // separates "he is holding the left button and reached for the wheel"
                // from "the wheel went down during a click" — a drag, a
                // click-through, a slip. It is deliberately short: the left button is
                // not a modifier anyone holds by accident for a third of a second
                // while pressing something else.
                //
                // Acted on the press and not the release, unlike the dictation below:
                // there is nothing to tell it apart from, so waiting would only make
                // it feel slow.
                if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseDown && bare && leftIsHeld {
                    wheelArmed = true    // the release is ours too
                    Log.info("🎯 left held + wheel — binding")
                    // **Global, not main** — the same queue ⌘⌃B uses, and for the
                    // reason it uses it: `bindFrontmostTerminal` asks the main thread
                    // for the frontmost app with `main.sync`, so arriving there
                    // already on main is a wait for a queue that is waiting for you.
                    // libdispatch does not deadlock on that, it traps.
                    DispatchQueue.global().async { [weak self] in _ = self?.onGestureBind?() }

                    // **…and keeping the wheel down starts the dictation.** The two
                    // halves of *point at that terminal and start talking to it* were
                    // two separate gestures made a second apart at the same window —
                    // the chord, then the wheel again — and the second one is the tax
                    // on the first. Now the chord is the whole thing: press and let go
                    // to bind, keep pressing to bind and start.
                    //
                    // **The bind still fires at the press**, above, so the flight
                    // plays the instant the signal arrives rather than a second later
                    // when the verdict on the hold is in. Nothing about it is
                    // conditional on how long he goes on holding, which is what makes
                    // the two readings of the same press one gesture instead of two.
                    //
                    // A second, not `cancelHoldSeconds`: this is not a confirmation
                    // — nothing here is destructive — it is a deliberate wait, and it
                    // has to be short enough that the hand does not let go first.
                    wheelDown = true
                    wheelLeftChord = true
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.claimWheelPress() else { return }
                        // A dictation that started some other way while he was still
                        // holding must not be ended by this timer.
                        guard !self.dictating else { return }
                        Log.info("🎙️ left held + wheel held — bound, now dictating")
                        DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                    }
                    wheelHold = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.chordDictateSeconds, execute: work)
                    return nil
                }

                // **The wheel on its own, while there is somewhere for words to go.**
                // Swallowed on the press and judged at the release above, because a
                // tap and a hold are the same event until the finger lifts.
                //
                // **`localCapture` is true whether or not anything is bound, since
                // 2026-09-11** (`AppDelegate.syncLocalCapture`), so in this gesture
                // mode the wheel is the relay's for as long as the relay is running.
                // The unbound double-click branch further down is unreachable
                // through it — the first click now opens a dictation and sets
                // `wheelDictateAt`, so the second converts it to a spawn up here,
                // which is the same gesture arriving at the same place. It is left
                // standing because it is what has to work again if `holdsForBind`
                // is ever flipped back.
                //
                // **⌘ + the wheel used to ride this same branch** and mean "and open
                // somewhere to put it" — the spawn, without the keyboard-free chord.
                // Removed at Victor's ask 2026-09-03: the modifier belonged to this
                // app for as long as it was running, bound or not, which cost every
                // ⌘-middle-click everywhere else on the machine. The spawn itself
                // came back a day later as the bare wheel *clicked twice* (below),
                // which is now its only gesture — ➡️ + 🛞 held a second went the same
                // way on 2026-09-06.
                if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseDown
                    && bare && (localCapture || dictating) {
                    wheelDown = true
                    wheelLeftChord = false

                    // **The second click of a double click, judged before anything
                    // else** (Victor, 2026-09-05): the dictation the first click
                    // opened becomes a spawn — same recording, new destination, a
                    // session that does not exist yet, with the folder menu opening
                    // right here.
                    //
                    // It is tested **ahead of `dictating`** on purpose. That flag
                    // reaches the tap only once the recording is actually up, and on
                    // a cold model that is ten seconds after the first click; asking
                    // it first is precisely what killed the hold this replaces. The
                    // stamp is set by the branch below, so it alone says "the click
                    // before this one was mine, and it was a dictation".
                    if wheelDictateAt > 0
                        && CFAbsoluteTimeGetCurrent() - wheelDictateAt <= Self.spawnDoubleSeconds {
                        wheelDictateAt = 0
                        // Ours, swallowed, and nothing left for the release to
                        // claim: `wheelArmed` keeps the middle-up from reaching the
                        // app underneath, and `wheelDown` cleared makes `tapped`
                        // false there — otherwise this second click would end the
                        // dictation it just re-aimed.
                        wheelArmed = true
                        wheelDown = false
                        wheelHeldFromPress = false
                        Log.info("🎙️✨ wheel double-clicked — this dictation opens a new Claude Code")
                        DispatchQueue.global().async { [weak self] in self?.onWheelDoubleSpawn?() }
                        return nil
                    }

                    // **Idle it fires on the press, not on the release.** Waiting for
                    // the lift cost the one thing this gesture has to give: Victor
                    // could not tell whether the microphone had opened until he let
                    // go, so he kept holding the button "for a second" to be sure —
                    // the wait the tap was supposed to have removed, put back by hand
                    // because nothing on screen said otherwise. Reported 2026-08-31:
                    // *"nu mai știam dacă trebuie să țin apăsat butonul o secundă ca
                    // să înceapă să mă asculte"*. The double click above solves the
                    // spawn the other way round: the dictation starts at the first
                    // press, so the chip appears under his finger, and the second
                    // press only *changes where it is going*.
                    //
                    // `wheelArmed` is what keeps the release honest: it still belongs
                    // to us and is still swallowed — the app underneath must never see
                    // a middle-up it never saw a middle-down for — but `tapped` is
                    // then false, so the release fires nothing and cannot immediately
                    // end the dictation the press just started.
                    guard dictating else {
                        wheelArmed = true
                        // **Decided here, so the release has nothing left to claim.**
                        // `wheelDown` means *swallowed and not yet judged*; leaving it
                        // set would let the release fire this same toggle a second
                        // time, which is `startLocalRecording` twice and a microphone
                        // opened on top of itself.
                        wheelDown = false
                        wheelHeldFromPress = true
                        // The stamp the branch above measures the second click
                        // against. Only a *bare wheel opening a dictation* sets it,
                        // so no chord and no cancel can be doubled into a spawn.
                        wheelDictateAt = CFAbsoluteTimeGetCurrent()
                        Log.info("🎙️ wheel pressed — starting a dictation")
                        DispatchQueue.global().async { [weak self] in self?.onWheelDictate?() }
                        return nil
                    }
                    wheelHeldFromPress = false
                    let work = DispatchWorkItem { [weak self] in
                        // The state at the press picked this timer and the state at
                        // the fire has to still agree — a dictation that ended under
                        // his finger must not have its cancel land on the next one.
                        guard let self = self, self.dictating, self.claimWheelPress() else { return }
                        Log.info("🗑️ wheel held while dictating — cancelling it")
                        DispatchQueue.global().async { [weak self] in self?.onLocalCancel?() }
                    }
                    wheelHold = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.cancelHoldSeconds, execute: work)
                    return nil
                }

                // **The same double click, with nothing bound at all.**
                //
                // The branch above is gated on `localCapture || dictating`, i.e. on
                // there being a binding — *"with no destination there is nowhere for
                // a transcript to go, so a recording would be a room taped for
                // nobody"* (`syncLocalCapture`). A double click is the one wheel
                // gesture that gate cannot apply to: it **brings its own
                // destination**, a Claude Code session that does not exist yet, so
                // the premise the gate rests on is false for it. Reported by Victor
                // 2026-09-06 — at rest, the gesture did nothing at all, and the log
                // stayed empty because the tap was not even claiming the button.
                //
                // **The first click is passed through, not swallowed**, and that is
                // the whole design. While unbound this app has no claim on the middle
                // button — the same argument that took ⌘ + wheel away on 2026-09-03 —
                // and swallowing every middle click on the machine on the chance that
                // a second one follows would cost every middle-click-to-open-a-tab in
                // Chrome. So a lone click leaves nothing behind but a timestamp, and
                // only the **second** one within `spawnDoubleSeconds` is taken. The
                // price is exact and small: a deliberate double middle click on a
                // link opens one background tab. A single one behaves as it always
                // did.
                if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseDown
                    && bare && !leftIsHeld && !rightIsHeld && !promptHeld {
                    let now = CFAbsoluteTimeGetCurrent()
                    if idleWheelClickAt > 0 && now - idleWheelClickAt <= Self.spawnDoubleSeconds {
                        idleWheelClickAt = 0
                        // Ours from here: the release is swallowed (`wheelArmed`) so
                        // the app underneath is never handed a middle-up whose
                        // middle-down it never saw, and `wheelDown` stays clear so
                        // that release fires nothing — this press starts a dictation,
                        // it must not also end it.
                        wheelArmed = true
                        wheelDown = false
                        // This press *did* start a dictation, so its release is where
                        // the context shot belongs — the same deal the bound first
                        // click gets, except here the shot rides the second click,
                        // the first having gone to the app underneath.
                        wheelHeldFromPress = true
                        Log.info("🎙️✨ wheel double-clicked at rest — dictating at a new Claude Code")
                        DispatchQueue.global().async { [weak self] in self?.onWheelIdleDoubleSpawn?() }
                        return nil
                    }
                    idleWheelClickAt = now
                    return Unmanaged.passUnretained(event)
                }

                // Anything else on these buttons belongs to whatever the system has
                // mapped it to.
                return Unmanaged.passUnretained(event)
            }
        }

        // ── Wispr Flow's own start gestures, watched and never taken ─────────
        //
        // Above the `keyDown` gate because half of it is a `flagsChanged`: Wispr's
        // push-to-talk is two modifiers and nothing else, so it never produces a
        // key down at all. See `onWisprMaybeStarting`.
        if type == .flagsChanged {
            let raw = event.flags.rawValue
            // Device-dependent bits, because the pair is specifically the **right**
            // ⌘ and the **right** ⌥: `.maskCommand` alone would fire on every ⌘ in
            // the session. `NX_DEVICERCMDKEYMASK` / `NX_DEVICERALTKEYMASK`.
            let ptt = (raw & Self.deviceRightCommand) != 0 && (raw & Self.deviceRightOption) != 0
            if ptt != wisprPTTDown {
                wisprPTTDown = ptt
                DispatchQueue.main.async { [weak self] in
                    if ptt { self?.onWisprMaybeStarting?(.pushToTalk) }
                    // **And the release, which is the end of the sentence.** See
                    // `onWisprPushToTalkReleased`.
                    else { self?.onWisprPushToTalkReleased?() }
                }
            }
        }
        // **This app's own posts are stamped out of it** (2026-09-13), exactly as
        // the ⌃Escape branch below has always been. It was harmless while the
        // report was guarded by `!isRecording` on the far side; it stopped being
        // harmless the day the chord became a **toggle** there — a hands-free
        // chord seen while a dictation is open is now read as Victor ending it,
        // and `postWisprHandsFree` would otherwise hand the source its own start
        // back as a stop, a millisecond after it.
        if type == .keyDown,
           CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == Self.VK_SPACE,
           event.flags.contains(.maskSecondaryFn), event.flags.contains(.maskControl),
           event.getIntegerValueField(.eventSourceUserData) != Self.backButtonStamp,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onWisprMaybeStarting?(.handsFree)
            }
        }
        if type == .keyDown,
           CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == Self.VK_ESC,
           event.flags.contains(.maskControl),
           event.getIntegerValueField(.eventSourceUserData) != Self.backButtonStamp,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { [weak self] in self?.onWisprMaybeCancelling?() }
        }

        // ── Another app's delivery, inside the window it is expected in ─────
        //
        // Above the `keyDown` gate because a paste is three events and the
        // release has to go with the press: passing a `keyUp` whose `keyDown`
        // was swallowed hands the app underneath an orphan. The ⌘ itself is left
        // alone — it goes out and comes back balanced, and a bare ⌘ press does
        // nothing anywhere.
        // ── His own keys, while Wispr's Scratchpad has the focus ────────────
        //
        // Below the app's own chords on purpose: ⌘⌃B, ⌘⌃D and the gesture keys
        // are handled above and have already returned by the time this runs, so
        // borrowing the keyboard for a few hundred milliseconds cannot take away
        // the keys the relay itself is listening for.
        if type == .keyDown || type == .keyUp {
            let target = redirectTargetNow()
            // **Anyone's key but ours and Wispr's.** It was `pid == 0` — real
            // hardware only — and that is the right *description* of Victor's
            // keystrokes and the wrong *rule*: it also makes the behaviour
            // untestable, because every probe the loop can post carries a pid.
            if target != 0,
               pid_t(event.getIntegerValueField(.eventSourceUnixProcessID)) != WisprScratchpad.wisprPid,
               event.getIntegerValueField(.eventSourceUserData) != Self.backButtonStamp {
                let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                if type == .keyDown {
                    countSeen()
                    noteDuplicate(code, pid: pid_t(event.getIntegerValueField(.eventSourceUnixProcessID)))
                }

                // **Never a chord.** ⌘Tab, ⌘Space and ⌃-anything are the
                // system's and the window manager's, and a key redirected into
                // an app that was not asking for it is worse than a shortcut
                // reaching the wrong window.
                if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
                    if type == .keyDown {
                        countPassed()
                        Log.info("⌨️ key \(code) passed (modifier) — chords are never redirected")
                    }
                // **The gate is the window's existence, because no focus reading
                // is true** (2026-09-14, measured twice).
                //
                // Asking the Scratchpad window whether it is focused answers
                // **no** while it is taking the keystrokes; asking the victim's
                // application answers **its own `AXTextArea`** while it is
                // receiving none of them. A gate built on either passed five
                // probe letters straight into Wispr's note. What does correlate
                // exactly is the window's life: the two probes typed after it
                // closed reached the victim and the five before it did not.
                //
                // So: while that window is up, a real keystroke is his and goes
                // to the app he is in — and the moment it is gone the guard stops
                // touching anything. `windowIsUp` is the 25 ms watcher's own
                // reading, cached, so this costs a lock and no AX call.
                } else if !WisprScratchpad.windowIsUp {
                    if type == .keyDown { countPassed() }
                } else if Self.axInsert, let text = Self.printable(event) {
                    // **Printable characters go in through Accessibility, on a
                    // queue.** A key event cannot be delivered to an application
                    // with no key window — it has no first responder, measured
                    // three times, `postToPid` to a verified-live victim
                    // included. `AXSelectedText` needs none. The tap translates
                    // the keycode (pure, layout only) and hands it on; nothing
                    // that can block runs here.
                    if type == .keyDown { insert(text, code: code) }
                    return swallow("the keyboard guard (queued for Accessibility)", type, event)
                } else {
                    // Return, Tab, the arrows, Delete: nothing to insert, so the
                    // key goes by the only other route there is — on the same
                    // queue, to keep its place in the order he typed.
                    if type == .keyDown { repost(event, code: code) }
                    return swallow("the keyboard guard (queued, non-printable)", type, event)
                }
            }
        }

        if type == .keyDown || type == .keyUp {
            let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            // **pid 0 is a key Victor pressed.** Real hardware carries no
            // process, so his own ⌘V can never match this branch — which is the
            // whole reason a swallow here is safe at all. The stamp is this
            // app's own keystrokes, which must never be eaten either.
            if pid != 0, event.getIntegerValueField(.eventSourceUserData) != Self.backButtonStamp {
                stateLock.lock()
                let armed = injectionArmed
                let swallows = injectionSwallows
                let firewall = wisprFirewall
                stateLock.unlock()
                if armed, type == .keyDown { probeInjected(pid: pid, code: code, flags: event.flags) }
                if code == Self.VK_V, event.flags.contains(.maskCommand), isWispr(pid) {
                    if type == .keyDown {
                        let who = processName(pid)
                        DispatchQueue.global().async { [weak self] in self?.onInjectedPaste?(who) }
                    }
                    // **The firewall: Wispr's ⌘V never reaches an application
                    // while this app runs** (2026-09-22; Victor: *"vreau
                    // wisprflow să NU mai fie lăsat să insereze text el"*).
                    // Stateless on purpose — the armed gate below is the
                    // ordering bet that leaked 5/5 on 2026-09-13, a paste
                    // arriving before the relay knew the microphone had shut.
                    // The words are never lost with it: every Wispr sentence
                    // is a `History` row, `WisprFlowSource` reads that row and
                    // the relay delivers it — the bound agent, or the caret,
                    // through the same door as every other engine's words.
                    if firewall { return self.swallow("the Wispr firewall", type, event) }
                    if armed, swallows { return self.swallow("the Wispr ⌘V capture", type, event) }
                }
            }
        }

        // ── Wispr's ⌘V leaves ⌘ down, and only this app can put it back ──────
        //
        // **The fifth stale ⌘ was ours; the sixth is Wispr's.** Its paste is
        // `keycode 9, flags 0x20100000` — ⌘ stamped on the key **and on its
        // release** — and it posts no `flagsChanged` after it. Since
        // `CGEventSource.flagsState` reports whatever the last event's flags
        // said, the whole session believes ⌘ is held from that moment until
        // Victor's next real keystroke: every gesture gated on `bare` refuses,
        // and every *wait for a bare wire* loop in this file spins its full
        // allowance.
        //
        // It shows up **only with the wrap off**, which is the tell that
        // identified it: wrapped, the swallow eats both halves and the session
        // never sees the release at all. So the clearing event is posted exactly
        // where the swallow is not — for a key-up we are letting through.
        if type == .keyUp,
           CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == Self.VK_V,
           event.flags.contains(.maskCommand),
           event.getIntegerValueField(.eventSourceUserData) != Self.backButtonStamp {
            let owner = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
            if owner != 0, isWispr(owner) { clearCommandAfterWisprPaste() }
        }

        guard type == .keyDown else {
            if Self.keyTrace, type == .keyUp || type == .flagsChanged {
                trace("passed (not a keyDown)", type, event)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let ctrl = flags.contains(.maskControl)
        let opt = flags.contains(.maskAlternate)
        let cmd = flags.contains(.maskCommand)

        // **The keyboard half of the selection stamp** (2026-09-18), first
        // because it decides nothing: the event goes on to every branch below
        // exactly as it did. ⇧ with an arrow, Home, End or a page key extends a
        // selection and does nothing else; ⌘A selects all. Neither can be a
        // window being dragged, which is the drag stamp's one false positive, so
        // these two are the witnesses worth having. Nothing of this app's own
        // chords is in here — ⌘⌃B, ⌘⌃D and ⌘⇧P are letters.
        if (flags.contains(.maskShift) && Self.selectionExtendKeys.contains(keyCode))
            || (cmd && !ctrl && !opt && keyCode == Self.VK_A) {
            noteSelectionGesture()
        }

        // ⏎ sends the prompt that is on screen. Bare only: ⌘⏎ and ⇧⏎ are other
        // people's shortcuts, and this window is short enough that a modified
        // Return during it is far more likely to be meant for the app behind.
        //
        // Above the mouse-5 branch below because the two cannot overlap — the
        // prompt appears when the dictation has ended — and because being first
        // makes that independence readable rather than merely true.
        if (keyCode == VK_RETURN || keyCode == VK_KEYPAD_ENTER) && promptHeld
            && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
            DispatchQueue.main.async { [weak self] in self?.onPromptEnter?() }
            return swallow("the prompt panel's ⏎", type, event)   // the panel took it
        }

        // ⎋ cancels the prompt that is on screen, the mirror of the ⏎ above and
        // swallowed the same way — while a countdown is running, Escape is this
        // panel's, not the editor's behind it. Bare only, for the same reason.
        if keyCode == VK_ESCAPE && promptHeld
            && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
            DispatchQueue.main.async { [weak self] in self?.onPromptEscape?() }
            return nil
        }

        // **Where the back button's Return comes from depends on the mode.** In
        // Logi mode the button emits ⌃⌥⌘F6 and this app posts the Return itself
        // (`postReturn`, from that branch below). With the flag off the button is
        // remapped upstream as it always was, and the branch here exists to
        // *withhold* that Return mid-dictation and take the picture instead.
        if !useLogiGestures {
            // The same button, arriving as a keystroke.
            //
            // The remapper taps the event stream **upstream of this one**, so the
            // remap happens before a session tap can ever see a mouse button: what
            // reaches us is already a Return. The branch above therefore never fires
            // on Victor's Mac, and is kept only because it is the correct handling if
            // the order is ever the other way round.
            //
            // Telling this Return from the one he types is the whole trick, and the
            // discriminator has two forms, because the remapper changed identity on
            // 2026-09-07:
            //
            // - **The stamp**, which is the live one. Victor Addons took the button
            //   over when LinearMouse was uninstalled, and it is not a remapper — it
            //   is a general-purpose app that also posts Returns for its own reasons
            //   (`KeySimulator`), and those mean Enter and must be left alone. So the
            //   one Return that is a disguised button carries `backButtonStamp` in
            //   `eventSourceUserData` and nothing else does. **The constant is
            //   duplicated in `BackButtonEnter.swift` in the victor-macos-addons
            //   repo; the two must not drift.**
            // - **The source pid**, kept for LinearMouse, which owned this until
            //   2026-09-07 and is matched by process name. A key pressed on real
            //   hardware carries pid 0, an event posted by a process carries that
            //   process's pid, so the physical Return key is never touched either way.
            //
            // Why this was worth a fix rather than a note: for a day the answer was
            // "neither", and the failure is silent — no shot, and the Enter it would
            // have been lands in whatever is in front. See *Tap order is what makes
            // this work* in CLAUDE.md: the order flipped because Victor Addons is
            // rebuilt and restarted after every change to it, i.e. routinely later
            // than the relay.
            if (keyCode == VK_RETURN || keyCode == VK_KEYPAD_ENTER) && dictating
                && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
                let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
                let stamped = event.getIntegerValueField(.eventSourceUserData) == Self.backButtonStamp
                let synthetic = stamped || (pid != 0 && isRemapper(pid))
                Log.info("↩︎ Return while dictating — source pid \(pid), stamped=\(stamped), remapper=\(synthetic)")
                if synthetic {
                    let cursor = NSEvent.mouseLocation
                    DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                    return nil   // swallow: the Enter it would have been is not wanted mid-dictation
                }
            }
        }

        // ⌘⌃B — **bind**, on B for bind since 2026-09-01. It was ⌘⌃D until then,
        // and D moved one branch down to the thing it spells: dictate.
        //
        // **Autorepeat is swallowed, not acted on.** A second press on the target
        // already bound *ends the session*, so a key held a moment too long would
        // otherwise bind and immediately stop the session it just started — the
        // one input mistake this gesture cannot afford. The event is eaten either
        // way, so nothing downstream sees the repeat.
        if (keyCode == VK_F7 || keyCode == VK_F9) && !cmd && !ctrl && !opt && !flags.contains(.maskShift) {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            let step = keyCode == VK_F9 ? 1 : -1
            DispatchQueue.main.async { [weak self] in self?.onHaloStep?(step) }
            return nil
        }

        if keyCode == VK_B && cmd && ctrl && !opt {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            DispatchQueue.global().async { [weak self] in self?.onBindHotkey?() }
            return nil
        }

        // ⌘⌃D — **dictate**: the wheel's click, from the keyboard. Same call, so
        // it is the same toggle, and a dictation started with the key can be
        // ended with the wheel and the other way round.
        //
        // Not ⌘⌃⌥D — that one is Victor Addons' dark-mode toggle, and the two are
        // told apart by ⌥ alone. It shadows the system-wide ⌘⌃D "look up in
        // dictionary", which it inherited from the bind it replaced.
        //
        // Ungated on purpose, unlike the bare wheel: `startLocalRecording` keeps
        // the `hasDestination` guard, so a press with nothing bound costs
        // nothing, and the key is swallowed either way rather than sometimes
        // falling through to the dictionary.
        //
        // Autorepeat swallowed for the same reason as above — a held key would
        // open the microphone and close it again on the next repeat.
        if keyCode == VK_D && cmd && ctrl && !opt {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
            return nil
        }

        // Autorepeat swallowed for the same reason ⌘⌃B swallows it: a key held a
        // moment too long would paste the sentence four times into whatever he
        // is typing in, and unlike a bind that is not undone by pressing it
        // again.
        //
        // **⌘⇧P since 2026-09-19**, at Victor's word and unlike its two
        // neighbours: ⌘⌃B and ⌘⌃D are on ⌘⌃ because nothing on a Mac ships that
        // pair, and this one is now on a chord that **several applications do
        // ship** — VS Code's and Cursor's Command Palette, Chrome's DevTools
        // command menu, IntelliJ on some keymaps. It is swallowed
        // unconditionally like the other two, so while this app is running that
        // is what the chord does, everywhere. That is the trade he asked for;
        // the `ctrl` half of the guard is now `shift` and nothing else moved.
        if keyCode == VK_P && cmd && flags.contains(.maskShift) && !ctrl && !opt {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            DispatchQueue.global().async { [weak self] in self?.onPasteLast?() }
            return nil
        }

        // ── The side buttons, as ⌃⌥⌘ + a function key ────────────────────────
        //
        // Every one of these is a **gesture made on the mouse**, not a chord
        // anyone types: Logi Options+ owns both side buttons and emits the
        // keystroke when the button is clicked, or held while the mouse moves in
        // one of four directions. Nothing on a Mac ships ⌃⌥⌘ + a function key,
        // which is why that shape was picked — the tap can swallow them all
        // outright without shadowing anything.
        //
        // **Autorepeat is swallowed on every one.** Options+ sends a single tap
        // per gesture, so a repeat can only be the key stuck down; acting on it
        // would bind twice, or open and close the microphone in a loop.
        //
        // **F10 turned out to be the exception** (2026-09-16): a re-triggered
        // tap with no autorepeat flag at all, on a fast flick — see
        // `lastF10At`.
        if useLogiGestures && ctrl && opt && cmd {
            switch keyCode {
            // ➡️ — the mouse moved right with the forward button held: start the
            // dictation, or end the one already open. The same call ⌘⌃D makes,
            // so a dictation started with the key ends with the gesture and the
            // other way round. Where it goes is not this gesture's business: a
            // bound terminal takes it, and Replace Wispr sends it to the caret.
            case VK_F10:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                let f10Now = CACurrentMediaTime()
                // **The window slides** (2026-09-18): a dropped re-fire counts
                // as the last one too, so a whole train of them lasts as long as
                // the motion does rather than letting every second tap through.
                // See `lastF10At`.
                let sinceLastF10 = f10Now - lastF10At
                guard sinceLastF10 >= Self.gestureRetriggerSeconds else {
                    lastF10At = f10Now
                    Log.info("🎯 ➡️ F10 re-triggered \(String(format: "%.0f", sinceLastF10 * 1000))ms after the last one — still the same motion, dropped")
                    return nil
                }
                lastF10At = f10Now
                // Our own bookkeeping can go stale — `VK_F7`'s reason, and the
                // same cost if it does: every plain flick right would read as a
                // bind. Asked of the window server rather than remembered.
                reconcileButtons()
                if leftIsHeld {
                    Log.info("🎯 ⬅️ held + forward button flicked right — bind, then dictate at it")
                    DispatchQueue.global().async { [weak self] in self?.onGestureBindAndDictate?() }
                    return nil
                }
                // **A sentence this young cannot be ended by the gesture that
                // opened it** — `gestureStopDwellSeconds`. The second half of
                // the same fix: a re-fire slow enough to clear the window above
                // is still the flick that started the dictation, and the only
                // thing it could do here is undo it.
                if let age = openSentenceAge, age < Self.gestureStopDwellSeconds {
                    Log.info("🎯 ➡️ F10 \(String(format: "%.0f", sinceLastF10 * 1000))ms on, but the sentence is only \(String(format: "%.0f", age * 1000))ms old — not stopping it")
                    return nil
                }
                DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                return nil

            // ⬅️ — throw the running dictation away. Deliberately the mirror
            // direction of the one that starts it: the two gestures that open
            // and abandon a sentence are the same hand movement, reversed.
            case VK_F11:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onLocalCancel?() }
                return nil

            // ⬅️ on the **back** button — throw a Wispr Flow sentence away.
            //
            // The row was free until 2026-09-21 (*"dacă sunt în dictare Wispr Flow
            // … apăs butonul de back și mut la stânga … trebuie să anuleze dictarea
            // Wispr Flow"*), and it is where that gesture belongs rather than on
            // the forward button: **the thumb is already on the back button**
            // during a Wispr sentence, because that is the button that stops it.
            // Stop and abandon are then the same button, one flick apart, which
            // is the shape ⬆️/⬅️ already have on the forward one.
            //
            // The body is the back *click*'s stop with one word changed —
            // `postWisprCancel` (⌃Escape, Wispr's own `dismiss`) where that
            // posts the hands-free chord — and it is gated the same way, on
            // `ownDictation`, for the same reason: a relay sentence has Wispr's
            // microphone open because the relay opened it, and it has its own
            // cancel with its own banner and its own clearing-up.
            //
            // `onWisprRawChord(true)` closes the listening phase here rather
            // than waiting for the CoreAudio edge, which is 0–6 s late where it
            // fires at all — a ring still turning after he has abandoned the
            // sentence is the thing this gesture exists to stop.
            case VK_F3:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                if wisprMicIsOpen?() == true, !ownDictation {
                    Log.info("🗑️ ⬅️ back button flicked left — dismissing Wispr Flow's dictation")
                    Self.postWisprCancel()
                    onWisprRawChord?(true)
                    DispatchQueue.global().async { [weak self] in self?.onWisprCancel?() }
                    return nil
                }
                // Nothing of Wispr's to throw away: the relay's own cancel, so
                // the flick is never a gesture that silently does nothing.
                DispatchQueue.global().async { [weak self] in self?.onLocalCancel?() }
                return nil

            // ⬆️ — dictate at a session that does not exist yet: the spawn, which
            // used to be the wheel clicked twice. A gesture of its own again,
            // rather than a conversion of a dictation already in flight, because
            // there is no longer a first click to convert.
            case VK_F8:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onGestureSpawn?() }
                return nil

            // ⬆️ on the **back** button — start or stop a screen recording
            // (2026-09-18).
            //
            // **A free side-button row rather than the wheel**, and that is the
            // whole design decision. Victor asked for a three-second hold on the
            // wheel with a countdown; the wheel cannot carry it, twice over. In
            // Logi mode the middle press is *passed through* to the app
            // underneath, so a hold only recognisable after three seconds lands
            // in Chrome as a middle click and closes the tab under the pointer —
            // and it cannot be swallowed retroactively, while swallowing it
            // speculatively and replaying the click is the mechanism this file
            // removed after the orphan-event bug (*Nothing is replayed*). In
            // Wheel mode a two-second hold already **cancels the dictation**
            // (`cancelHoldSeconds`), so the three-second verdict is unreachable.
            //
            // A side button costs nothing from any application, collides with
            // nothing, and is deliberate by construction — which is what the
            // hold and its countdown were for. The countdown went with them.
            //
            // **Ungated here.** Whether a recording may start is a question about
            // the dictation, and the tap's `dictating` is `hasDestination &&
            // listening` — too narrow, because Victor's rule is that a film can
            // be made *whenever a dictation is open*, bound, unbound or headed
            // for a folder that does not exist yet. `AppDelegate` holds that
            // state whole and answers it.
            case VK_F4:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onGestureFilm?() }
                return nil

            // 🔼 ↓ — **kamikaze** (2026-09-23). Victor: *"în timp cât dictez,
            // trag gest cu butonul de forward și trag de mouse în jos. Asta să
            // adauge automat la promptul respectiv cuvântul «kamikaze», ceea ce
            // înseamnă că e ceva mic."* The word is the agent's cue to close its
            // own terminal when done. What it means is `AppDelegate`'s call.
            case VK_F9:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onGestureKamikaze?() }
                return nil

            // ⬇️ on the **back** button — let the binding go. The same call the
            // menu's Disconnect row makes, so the gesture and the row cannot
            // drift apart.
            case VK_F12:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onGestureUnbind?() }
                return nil

            // The forward button **clicked** — two readings, told apart by the
            // left button.
            //
            // **⬅️ held, then the forward button: bind** (2026-09-09). It was
            // 🔼 ↓ — the forward button held while the mouse moved down — and
            // Victor replaced it with the chord for what the hand is already
            // doing: *"it's more natural, click to focus the thing and then grab
            // it"*. Pointing at a terminal starts with a click into it, so the
            // button that says *this window* is already down when the gesture is
            // made; a drag downwards says nothing about which window it means.
            // It is the left-plus-wheel chord returning with the forward button
            // where the wheel was, which is also why it is judged the same way —
            // `leftIsHeld`, i.e. the button genuinely down and down for
            // `chordHoldSeconds`, so a click that merely overlaps the gesture is
            // not one. **No toggle**, like the chord it descends from: the
            // ordinary reason to make it twice is not being sure the first one
            // landed.
            //
            // With the left button up it is **a dictation at the caret — in
            // both engines, whatever is bound** (2026-09-12). It used to be
            // gated on Replace Wispr: ticked, this app's microphone at the
            // caret; unticked, the raw Wispr chord — which opened a dictation
            // the relay then routed *by state*, i.e. to the bound terminal.
            // Victor, testing the wrap: *"apăsând butonul forward, click
            // normal, el tot dictează legat de fereastră … butonul forward
            // pornește dictare la caret (indiferent dacă e legat ceva)"*. So the
            // click goes through `startDictation(paste:)` like every other
            // gesture, and the source — Wispr posting its own chord, or the
            // local microphone — is the source's business. The bind is **not**
            // gated on anything either — it is the one gesture that says where
            // words go. The chord is eaten in every branch.
            case VK_F7:
                // Our own bookkeeping can go stale — a release this tap never
                // saw would leave the button held for good and read every plain
                // click as a bind.
                reconcileButtons()
                if leftIsHeld {
                    if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                    Log.info("🎯 ⬅️ held + forward button — binding")
                    DispatchQueue.global().async { [weak self] in _ = self?.onGestureBind?() }
                    return nil
                }
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                Log.info("🎙️ forward button — a dictation at the caret")
                DispatchQueue.global().async { [weak self] in self?.onPasteToggle?() }
                return nil

            // **The back button's two gestures swapped roles** (Victor,
            // 2026-09-23: *"când apăs butonul de back, asta doar să oprească și
            // să pornească dictarea curată, cum ar fi Wispr normal, iar enterul
            // să-l trimit cu gestul de back și swipe la dreapta. Așa nu avem
            // niciun fel de race pe cine ce face"*). Until today one click meant
            // three things — a Wispr stop, a picture, a Return — decided by a
            // state he could not see at the moment of pressing, and a click meant
            // as a stop that came a beat after the sentence had ended typed a
            // Return instead. Now the click is **only** Wispr's hands-free toggle
            // (the shutter excepted, below) and 🔽 → is **only** Return.

            // 🔽 → — **Return**, posted by this app (see `postReturn`: in Logi mode
            // nothing upstream types it). Guarded against Options+ re-firing on
            // the tail of one flick the way F10 is (`lastF10At`), since here a
            // re-fire would be a second send.
            case VK_F5:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                let f5Now = CACurrentMediaTime()
                let sinceLastF5 = f5Now - lastF5At
                lastF5At = f5Now
                guard sinceLastF5 >= Self.gestureRetriggerSeconds else {
                    Log.info("🎯 🔽 → F5 re-triggered \(String(format: "%.0f", sinceLastF5 * 1000))ms after the last one — still the same motion, dropped")
                    return nil
                }
                Log.info("⌨️ 🔽 → — Return")
                Self.postReturn()
                return nil

            // The back button **clicked** — Wispr Flow's **raw** hands-free
            // toggle, in both modes: it starts a sentence Wispr owns (the relay
            // rings for it and routes it by state) and stops any Wispr sentence,
            // whoever started it. Same chord, same `postWisprHandsFree` as
            // before, when 🔽 → was the start and this click its stop.
            //
            // **The one exception is the shutter**: while the relay's own
            // sentence is recording (`dictating`) the click takes a picture, as it
            // always has — opening Wispr then is refused anyway (below), so the
            // button would otherwise do nothing at all.
            case VK_F6:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                if dictating {
                    let cursor = NSEvent.mouseLocation
                    DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                    return nil
                }
                // **A second click inside `backToggleSettleSeconds` is dropped.**
                // Which half of the toggle a click is comes from Wispr's
                // microphone, and that witness lags both ways: it still reads
                // open for 100–600 ms after a stop, and reads closed for 0.3–6 s
                // after a start. A quick second click would read the stale state
                // and post the toggle again — re-opening what was just stopped.
                let f6Now = CACurrentMediaTime()
                guard f6Now - lastBackToggleAt >= Self.backToggleSettleSeconds else {
                    Log.info("🎯 ⬅️ back click \(String(format: "%.0f", (f6Now - lastBackToggleAt) * 1000))ms after the last toggle — dropped")
                    return nil
                }
                // The arm says *a start was posted and has not ended* even
                // before Wispr's microphone warms up, so it wins over the
                // microphone reading closed in that gap.
                let closing = backStopsWispr || wisprMicIsOpen?() == true
                // **Never a second microphone over the first** (2026-09-18):
                // with the Engine on the local model or ElevenLabs the relay's
                // own may be recording. Only the opening half is refused — a stop
                // must never be. Victor: *"E absurd să pornesc două motoare de
                // transcriere simultan. Trebuie exclusiv, ba unu, ba altu."*
                if !closing, ownDictation {
                    Log.error("🎙️ ⬅️ back click refused — the relay's own engine is mid-sentence")
                    onEngineBusy?("Back click ignored — finish the sentence you are dictating first")
                    return nil
                }
                lastBackToggleAt = f6Now
                Log.info("🎙️ ⬅️ back click — Wispr Flow's hands-free toggle\(closing ? " (the stop)" : " (the start)")")
                Self.postWisprHandsFree()
                // …and the chord says so to the state machine, which cannot see
                // it any other way — see `onWisprRawChord`.
                onWisprRawChord?(closing)
                setWisprArm(closing ? 0 : CACurrentMediaTime())
                return nil

            default:
                break
            }
        }

        guard ctrl && opt && !cmd else {
            trace("passed", type, event)
            return Unmanaged.passUnretained(event)
        }

        if keyCode == VK_P {
            let cursor = NSEvent.mouseLocation
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
            return swallow("⌃⌥P screenshot", type, event)
        }
        trace("passed", type, event)
        return Unmanaged.passUnretained(event)
    }

    /// **Return, posted by this app.** The back button's click used to arrive
    /// already remapped to Return by something upstream; since Options+ took the
    /// button over, nothing types it but this.
    ///
    /// Posted at `.cghidEventTap` so it enters the stream at the same depth a
    /// key press does and reaches whatever has focus, and stamped with
    /// `backButtonStamp` so this tap's own branches can tell it from a Return
    /// Victor typed — the stamp is why the event does not come back round and
    /// get read as a gesture.
    ///
    /// **It waits for ⌃⌥⌘ to come up first, and without that it is not a Return
    /// at all.** This is called from the tap callback for the chord's own F6 —
    /// i.e. at the one instant Options+ is *holding* all three modifiers — and a
    /// key posted then reaches the front app as ⌃⌥⌘Return, which Terminal gives
    /// Claude Code as ⌥⏎: a newline in the prompt instead of the send. That is
    /// the symptom Victor reported ("nu-ți trimite promptul, ci dă spații
    /// goale").
    ///
    /// **Clearing the event's own flags does not do it**, which is the part
    /// worth writing down. `down.flags = []` was tried first and measured clean
    /// against a *synthesised* chord — and then measured dirty against the real
    /// button, `mods=CTRL+OPT+CMD` on the wire (2026-09-09, listen-only tap).
    /// While the modifier keys are genuinely down, the window server merges the
    /// live state back into a posted key whatever the event says; the same trap
    /// `KeySimulator.waitForModifiersReleased` exists for in victor-macos-addons.
    /// So the only fix is to let go of the moment: off the tap thread, poll
    /// until the keyboard comes clean, then type. Measured on this Mac, Options+
    /// releases 11 ms after the F6 — far below anything a finger notices.
    ///
    /// **The wait is a fixed sleep, and asking the system instead does not
    /// work** — the second wrong fix, so it is written down. `CGEventSource
    /// .flagsState` answers *clean* through this whole window: Options+ never
    /// presses ⌃⌥⌘ as keys, it stamps them into the F6 event's own flags and
    /// sends one flags-cleared event afterwards. So a poll on the modifier state
    /// falls straight through and the Return goes out 2 ms after the F6, still
    /// inside the window where the merge happens. What *is* measurable is the
    /// gap to that trailing event: 12, 15 and 22 ms across the presses caught on
    /// the tap. `settleForOptionsPlus` is that gap with room over it.
    ///
    /// The poll is kept *after* the sleep for the other case — real modifiers
    /// Victor is physically holding — and is capped, posting anyway when the cap
    /// runs out: if he is really leaning on ⌘ the button still has to do
    /// something, and a late Return beats none.
    static func postReturn() {
        DispatchQueue.global().async {
            usleep(settleForOptionsPlus)
            let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            var waited = 0
            while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty,
                  waited < 40 {
                usleep(5_000)
                waited += 1
            }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = backButtonStamp
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else { return }
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// **Wispr Flow's hands-free toggle, typed by this app.** The forward button
    /// clicked outside Replace Wispr starts Wispr's dictation, and clicked again
    /// ends it. The chord is `fn ⌃ Space` — what Wispr calls `popo` and stores
    /// as `"49+59+63"` under `prefs.user.shortcuts` in `~/Library/Application
    /// Support/Wispr Flow/config.json`. **That file is the source, not the
    /// settings screen**, which draws the same three keys and says nothing about
    /// what it matches on.
    ///
    /// **Wispr cannot be given the button directly, and that is the whole reason
    /// this exists.** The button is diverted inside the mouse (*The side buttons
    /// speak in function keys*), so Wispr's hotkey recorder never sees a mouse
    /// button at all; and the ⌃⌥⌘F-key Options+ synthesises instead is refused
    /// too — *"Shortcut must include a modifier key or a valid mouse button"*,
    /// on 🔽 → (⌃⌥⌘F5), a chord nothing here claims and therefore one that does
    /// reach it. So Wispr keeps a keyboard shortcut recorded by hand, and the
    /// button arrives at it through this app.
    ///
    /// **The two modifiers go down as keys, not merely as flags on the Space.**
    /// Wispr stores the chord as three *keycodes* — 49 Space, 59 Control, 63 fn
    /// — which reads like a listener watching keys go down, the way `uiohook`
    /// reports them, and a bare Space wearing the flags might never look pressed
    /// to it. Four extra events buy correctness under either reading.
    ///
    /// It waits the Options+ chord out first for the reason `postReturn`
    /// documents at length: this runs in the tap callback for F7, the one
    /// instant ⌃⌥⌘ are on the wire, and the window server merges them into
    /// anything posted then — ⌃⌥⌘ fn Space is not the chord Wispr listens for.
    /// **Escape, to make Wispr Flow throw the sentence away.**
    ///
    /// The other half of `postWisprHandsFree`, and deliberately built out of it
    /// rather than beside it: the ✕ on the overlay now means *cancel this
    /// dictation*, and when the microphone belongs to Wispr Flow the only honest
    /// way to say that is the key Wispr itself listens for. Escape while it is
    /// recording discards the audio and pastes nothing — the one gesture that
    /// ends a Wispr dictation without leaving words behind.
    ///
    /// Everything that makes `postWisprHandsFree` correct is needed here for the
    /// same reasons and so is shared: the Options+ settle, the wait for Victor's
    /// own modifiers to come off the wire (a ⌘ or ⌥ still held would make this
    /// ⌘Escape, which is something else entirely in half the apps he dictates
    /// into), the `hidSystemState` source and the `backButtonStamp` so this
    /// app's own tap knows the keystroke is its own and lets it through.
    ///
    /// **⌃Escape, and the Control is not optional.** Wispr Flow's own config
    /// (`prefs.user.shortcuts`) files `53+59` as `dismiss` — Escape (53) plus
    /// Control (59) — the same place `49+59+63` files the hands-free chord this
    /// app already posts. A bare Escape is *not* that shortcut; it is whatever
    /// the app under the caret does with Escape. The Control goes out as a real
    /// `flagsChanged` around the key, exactly as `postWisprHandsFree` sends fn
    /// and Control, and nothing else is left on the wire.
    static func postWisprCancel() {
        DispatchQueue.global().async {
            usleep(settleForOptionsPlus)
            let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            var waited = 0
            while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty,
                  waited < 40 {
                usleep(5_000)
                waited += 1
            }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = backButtonStamp
            let held: CGEventFlags = [.maskControl]

            func modifier(_ key: CGKeyCode, leaving state: CGEventFlags) {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                else { return }
                e.type = .flagsChanged
                e.flags = state
                e.post(tap: .cghidEventTap)
            }

            modifier(Self.VK_CONTROL, leaving: held)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: Self.VK_ESC, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: Self.VK_ESC, keyDown: false) {
                down.flags = held
                up.flags = held
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            modifier(Self.VK_CONTROL, leaving: [])
        }
    }

    // MARK: - Wispr's Scratchpad, and the one chord this app has to *hold*

    /// **`open_scratchpad`, held** — the candidate wrap that does not touch
    /// Victor's focus and does not touch Wispr's permissions (2026-09-13).
    ///
    /// Two candidates were tried and both were rejected by Victor the same
    /// evening. The **sink** works (measured 3/3: Wispr picks its insertion
    /// target at the *end*, and a window that takes the keyboard 1–5 ms after the
    /// stop chord gets the text) but it steals the focus during every dictation,
    /// and he may be clicking or typing at that instant. **Revoking Wispr's
    /// Accessibility grant** works on paper but breaks Wispr as a standalone
    /// tool, which it has to go on being.
    ///
    /// The Scratchpad is the third door and it is Wispr's own. Per Wispr's docs
    /// the *Open Scratchpad* shortcut carries three gestures: **tap** opens and
    /// closes the window, **hold** is push-to-talk *into the Scratchpad*, and
    /// **double-tap** is hands-free into it while it is visible. The hypothesis
    /// this poster exists to test is the middle one: a held chord dictates into
    /// Wispr's own note — filed in `flow.sqlite`'s `Notes` / `NoteVersions`, with
    /// a `History` row whose `app` is `com.electron.wispr-flow` — **without
    /// inserting anything into the front app and without moving the focus**. If
    /// that holds, the wrap is *hold the chord for the length of the sentence and
    /// read the row*, and nothing in Victor's day changes.
    ///
    /// ## Why it reads the chord rather than carrying it
    ///
    /// `prefs.user.shortcuts` in Wispr's own `config.json` maps keycodes joined
    /// with `+` to an action name, and the *action* is the stable thing: Victor's
    /// is `"35+54+61": "open_scratchpad"` (P + right ⌘ + right ⌥) and the day he
    /// rebinds it, a hard-coded chord posts a keystroke into whatever now owns
    /// it. Read at call time, with his current value as the fallback — the same
    /// argument `postWisprHandsFree` makes for `49+59+63`, one file further on.
    ///
    /// ## Holding is not tapping twice
    ///
    /// Every other poster here is a press and a release in one breath. This one
    /// leaves the keyboard **down** between two calls, which is a state no event
    /// tap can clean up after: a crash, a missed `{"up": true}` or a script that
    /// dies with the chord held leaves a modifier stuck for the session, and a
    /// stuck right ⌘ is a Mac that has stopped working. So the hold carries its
    /// own dead-man's switch — 120 s, far past any sentence — and every path
    /// through `release` is idempotent.
    static func postWisprScratchpad(down: Bool) {
        scratchpadLock.lock()
        let alreadyHeld = scratchpadHeld
        scratchpadLock.unlock()
        if down {
            guard !alreadyHeld else { return Log.info("🗒️ scratchpad chord is already held — nothing posted") }
            postScratchpad(down: true, forDictation: true)
        } else {
            guard alreadyHeld else { return }
            postScratchpad(down: false, forDictation: true)
        }
    }

    /// **Which dictation a queued chord belongs to** (2026-09-14).
    ///
    /// The chord does not go out where it is asked for: `postScratchpad` moves
    /// the bookkeeping now and hands the keys to `scratchpadQueue`, which waits
    /// `settleForOptionsPlus` and then for a bare wire. The adversarial round
    /// found what that costs when a dictation is 18 ms long: the hold posted by
    /// `holdScratchpad` landed **after** the cancel had ended everything, Wispr
    /// read the down/up pair as a *tap*, opened its Scratchpad window, and the
    /// window then stood open for 57 s with the keyboard guard already disarmed
    /// — an orphan nobody owned. A queued hold is therefore stamped with the
    /// dictation it belongs to and dropped at post time if that dictation is
    /// over.
    ///
    /// A **release** is never dropped for this reason — a key stuck down is the
    /// worse failure by a wide margin — but it is dropped when the hold it
    /// releases never went out, because then nothing is down to release.
    private static var dictationEpochValue: UInt64 = 0

    static var dictationEpoch: UInt64 {
        scratchpadLock.lock(); defer { scratchpadLock.unlock() }
        return dictationEpochValue
    }

    /// The dictation a queued chord belonged to is over: anything still waiting
    /// for a bare wire on its behalf is no longer wanted.
    static func retireDictationEpoch() {
        scratchpadLock.lock()
        dictationEpochValue &+= 1
        scratchpadLock.unlock()
    }

    /// Press and release in one breath — the *tap*, which per Wispr's docs opens
    /// and closes the Scratchpad window rather than dictating into it.
    ///
    /// **250 ms, measured** (2026-09-13, 23:01): a 60 ms press/release did not
    /// toggle the window at all and a 250 ms one did, twice. Wispr is telling a
    /// tap from a hold by duration and 60 ms is below whatever floor it uses. It
    /// is still far under any hold a dictation would be.
    ///
    /// - Parameter stillWanted: **asked on the posting queue, immediately before
    ///   the keys go out** (2026-09-14, adversarial round 2). The toggle waits
    ///   `settleForOptionsPlus` and then for a bare wire, and Wispr closes its
    ///   own Scratchpad after a dismissed dictation — so a close asked while the
    ///   window was up can be *emitted* after it has gone, and a toggle posted
    ///   into that gap **opens** one. Every cancel row left an orphan window that
    ///   way. The check is a cheap AX existence read and it belongs here, riding
    ///   with the keys, because a check made at the call is a check made too
    ///   early. A skipped press takes its own release with it
    ///   (`scratchpadDownEmitted`), so nothing half-posted is left on the wire.
    static func tapWisprScratchpad(if stillWanted: @escaping () -> Bool = { true }) {
        // The 250 ms is measured from the press that actually went out, not from
        // this call — the press waits for a bare wire first, and the gap between
        // the two is exactly what Wispr is reading.
        postScratchpad(down: true, stillWanted: stillWanted)
        scratchpadQueue.async { usleep(UInt32(Self.scratchpadTapHold * 1_000_000)) }
        postScratchpad(down: false)
    }
    private static let scratchpadTapHold: TimeInterval = 0.25

    /// **Whether Wispr actually has a Scratchpad shortcut**, which is the
    /// question `WrapMode` asks before it decides to hold one.
    ///
    /// Deliberately *not* `scratchpadChord()` — that one always answers, because
    /// a poster with nothing to post is useless. This one distinguishes *Victor
    /// has bound it* from *we are guessing F18*, and the wrap falls back to the
    /// sink rather than holding a key nobody asked for.
    static var scratchpadIsConfigured: Bool {
        if let raw = ProcessInfo.processInfo.environment["WISPR_SCRATCHPAD_KEYS"], !raw.isEmpty {
            return true
        }
        return wisprShortcut(named: "open_scratchpad") != nil
    }

    /// The chord as Wispr has it today, newest read wins.
    /// `WISPR_SCRATCHPAD_KEYS=79` (or `35+54+61`) overrides both, and is the same
    /// variable `helpers/wispr_loopback.py` reads — the rig posts this chord too
    /// and the two must not disagree about what they are holding.
    static func scratchpadChord() -> [CGKeyCode] {
        if let raw = ProcessInfo.processInfo.environment["WISPR_SCRATCHPAD_KEYS"] {
            let codes = raw.split(whereSeparator: { "+, ".contains($0) })
                .compactMap { UInt16($0) }.map { CGKeyCode($0) }
            if !codes.isEmpty { return codes }
        }
        return wisprShortcut(named: "open_scratchpad") ?? Self.scratchpadFallback
    }

    /// **A single `F18`, and the single key is the point.** It shipped as
    /// `35+54+61` (P + right ⌘ + right ⌥) and moves to keycode **79** for a
    /// reason that is not tidiness: this chord is *held for the length of a
    /// sentence*, and a held ⌘⌥ hijacks every key Victor presses for that whole
    /// minute. F18 is a key nothing on this desk sends by itself, so holding it
    /// costs him nothing.
    private static let scratchpadFallback: [CGKeyCode] = [79]
    private static var scratchpadHeld = false
    /// Its own lock, because the hold is a **static** — every other flag in this
    /// file belongs to the one tap instance and shares its `stateLock`.
    private static let scratchpadLock = NSLock()
    private static var scratchpadDeadMan: DispatchWorkItem?
    /// The chord that is actually down, so the release cannot post a *different*
    /// one after Victor has rebound it mid-sentence.
    private static var scratchpadDownCodes: [CGKeyCode] = []
    /// Far past any sentence, and the only thing standing between a missed
    /// release and a Mac with right ⌘ stuck down.
    private static let scratchpadHoldCeiling: TimeInterval = 120

    /// **Posted on a serial queue of its own, and only onto a bare wire.**
    ///
    /// Both halves of that sentence were paid for on 2026-09-13, 23:20, by the
    /// first real dictation through the Scratchpad wrap. The chord went down for
    /// 5.2 s, Wispr recorded, transcribed — and pasted a ⌘V like an ordinary
    /// dictation, writing no note and never opening its Scratchpad window.
    ///
    /// The gesture that had started the dictation was `POST /test/gesture
    /// forward-click`, which posts **⌃⌥⌘F7**, and the F18 went out a
    /// millisecond later with those three modifiers still on the wire. Wispr was
    /// offered `⌃⌥⌘F18`, which is not the chord it has bound. This is the trap
    /// `mouse-gestures.md` names in as many words — *any key this app posts near
    /// a gesture has the same trap waiting* — and which `postWisprHandsFree`,
    /// `postWisprCancel`, `postWisprCopyLast` and `postReturn` have all been
    /// written under since 2026-09-09. This poster was the one that was not.
    ///
    /// So it waits `settleForOptionsPlus` and then for the modifiers to come off
    /// the wire, exactly as its four siblings do — which means it cannot run on
    /// the main thread, which means the **bookkeeping** (`scratchpadHeld`, the
    /// dead-man's switch) is done at the call and only the posting is deferred.
    /// A serial queue rather than `.global()`, because a press and a release
    /// that can overtake each other are a key stuck down.
    private static let scratchpadQueue =
        DispatchQueue(label: "ro.victorrentea.wispr-relay.wispr-scratchpad")

    /// - Parameter forDictation: whether this press belongs to a **dictation's
    ///   hold**, which a dictation that has since ended may cancel. The close's
    ///   own `tapWisprScratchpad` does not: it belongs to the window, not to a
    ///   sentence, and dropping it would leave the thing it was closing open.
    private static func postScratchpad(down: Bool, forDictation: Bool = false,
                                       stillWanted: (() -> Bool)? = nil) {
        let codes = down ? scratchpadChord() : (scratchpadDownCodes.isEmpty ? scratchpadChord() : scratchpadDownCodes)
        // **The flag moves now, the keys move on the queue.** `stop()` reads
        // `scratchpadIsHeld` a few milliseconds after `start()` returns, and a
        // release that saw `held == false` because the press was still waiting
        // for a bare wire is a key held until the dead-man's switch.
        scratchpadLock.lock()
        scratchpadHeld = down
        scratchpadDownCodes = down ? codes : []
        scratchpadLock.unlock()
        if down {
            let deadMan = DispatchWorkItem {
                Log.error("🗒️ scratchpad chord was held for \(Int(scratchpadHoldCeiling)) s — releasing it before it becomes a stuck modifier")
                postScratchpad(down: false)
            }
            scratchpadDeadMan?.cancel()
            scratchpadDeadMan = deadMan
            DispatchQueue.global().asyncAfter(deadline: .now() + scratchpadHoldCeiling, execute: deadMan)
        } else {
            scratchpadDeadMan?.cancel()
            scratchpadDeadMan = nil
        }
        let epoch = (down && forDictation) ? dictationEpoch : nil
        scratchpadQueue.async { emitScratchpad(codes, down: down, epoch: epoch, stillWanted: stillWanted) }
    }

    /// **Was the last hold actually put on the wire.** Touched only on
    /// `scratchpadQueue`, which is serial, so it needs no lock: it is the answer
    /// to *is there anything down for this release to let go of*.
    private static var scratchpadDownEmitted = false

    /// The keys themselves, on the serial queue, after the wire is clear.
    private static func emitScratchpad(_ codes: [CGKeyCode], down: Bool, epoch: UInt64? = nil,
                                       stillWanted: (() -> Bool)? = nil) {
        // **Checked here, at post time, and not at the call** — the whole point
        // is that this runs later than the code that asked for it.
        if down, let epoch, epoch != dictationEpoch {
            scratchpadDownEmitted = false
            Log.info("🗒️ scratchpad chord DOWN dropped — the dictation it belonged to ended while it waited for a bare wire")
            return
        }
        // …and the same question for a *toggle*: is the thing it was going to
        // close still there. A toggle posted at a window that has already gone
        // opens one.
        if down, let stillWanted, !stillWanted() {
            scratchpadDownEmitted = false
            Log.info("🗒️ the Scratchpad went on its own — the close toggle is not posted, which would have re-opened it")
            return
        }
        if !down, !scratchpadDownEmitted {
            Log.info("🗒️ scratchpad chord UP dropped — the hold it releases never went out, so nothing is down")
            return
        }
        usleep(settleForOptionsPlus)
        let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        var waited = 0
        while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty,
              waited < 40 {
            usleep(5_000)
            waited += 1
        }

        // Modifiers first on the way down, last on the way up — the order a hand
        // makes the chord in, and the order Wispr's own reader expects.
        let modifiers = codes.filter { modifierFlag(for: $0) != nil }
        let keys = codes.filter { modifierFlag(for: $0) == nil }

        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = backButtonStamp

        func flags(of held: [CGKeyCode]) -> CGEventFlags {
            var raw: UInt64 = 0
            for c in held { raw |= modifierFlag(for: c)?.rawValue ?? 0 }
            return CGEventFlags(rawValue: raw)
        }

        func modifier(_ key: CGKeyCode, leaving state: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) else { return }
            e.type = .flagsChanged
            e.flags = state
            e.post(tap: .cghidEventTap)
        }

        let chord = codes.map(String.init).joined(separator: "+")
        if down {
            var held: [CGKeyCode] = []
            for m in modifiers {
                held.append(m)
                modifier(m, leaving: flags(of: held))
            }
            let state = flags(of: held)
            for k in keys {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: k, keyDown: true) else { continue }
                e.flags = state
                e.post(tap: .cghidEventTap)
            }
            scratchpadDownEmitted = true
            Log.info("🗒️ scratchpad chord DOWN — \(chord) held (wire clear after \(waited * 5) ms)")
        } else {
            var held = modifiers
            let state = flags(of: held)
            for k in keys.reversed() {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: k, keyDown: false) else { continue }
                e.flags = state
                e.post(tap: .cghidEventTap)
            }
            for m in modifiers.reversed() {
                held.removeAll { $0 == m }
                modifier(m, leaving: flags(of: held))
            }
            scratchpadDownEmitted = false
            Log.info("🗒️ scratchpad chord UP — \(chord) released (wire clear after \(waited * 5) ms)")
        }
    }

    /// Whether the scratchpad chord is down right now — `GET /test/state`.
    static var scratchpadIsHeld: Bool {
        scratchpadLock.lock(); defer { scratchpadLock.unlock() }
        return scratchpadHeld
    }

    /// **The flag a modifier keycode leaves on the wire**, device-dependent bit
    /// included — the right ⌘ and the right ⌥ are specifically the *right* ones
    /// in Wispr's own push-to-talk reader (`deviceRightCommand` /
    /// `deviceRightOption` above), so a chord posted with only `.maskCommand`
    /// would be a different chord as far as it is concerned. Nil for a key that
    /// is not a modifier.
    private static func modifierFlag(for code: CGKeyCode) -> CGEventFlags? {
        switch code {
        case 55: return CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)   // ⌘ left
        case 54: return CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | deviceRightCommand)
        case 56: return CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x000002)     // ⇧ left
        case 60: return CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x000004)     // ⇧ right
        case 58: return CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x000020) // ⌥ left
        case 61: return CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | deviceRightOption)
        case 59: return CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x000001)   // ⌃ left
        case 62: return CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x002000)   // ⌃ right
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    /// **Read Wispr's own shortcut table** — `prefs.user.shortcuts`, keycodes
    /// joined with `+` mapped to an action name. Read-only and at call time, for
    /// `postWisprScratchpad`'s reason: the action is stable, the chord is not.
    private static func wisprShortcut(named action: String) -> [CGKeyCode]? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow/config.json")
        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let prefs = root["prefs"] as? [String: Any],
              let user = prefs["user"] as? [String: Any],
              let shortcuts = user["shortcuts"] as? [String: Any] else { return nil }
        for (chord, value) in shortcuts where (value as? String) == action {
            let codes = chord.split(separator: "+").compactMap { UInt16($0) }.map { CGKeyCode($0) }
            if !codes.isEmpty { return codes }
        }
        return nil
    }

    /// **⌘⌃C — Wispr Flow's `copy_last_text`**, the fallback for a delivery this
    /// tap never saw.
    ///
    /// `prefs.user.shortcuts` files `55+59+8` as `copy_last_text`: ⌘ (55), ⌃
    /// (59), C (8). It puts the last transcript on the pasteboard without a
    /// microphone, which is the one way left to read a sentence Wispr inserted
    /// through something other than a ⌘V — an Accessibility write, a paste into
    /// an app on its `focusModeBlockedApps` list, a keystroke that went to a
    /// window that had since moved.
    ///
    /// **It does not un-paste anything.** Wispr will already have put the words
    /// wherever the focus was; this only lets the relay know what they were.
    /// Everything that makes `postWisprHandsFree` correct is needed here for the
    /// same reasons and is shared.
    static func postWisprCopyLast() {
        DispatchQueue.global().async {
            usleep(settleForOptionsPlus)
            let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            var waited = 0
            while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty,
                  waited < 40 {
                usleep(5_000)
                waited += 1
            }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = backButtonStamp
            let held: CGEventFlags = [.maskCommand, .maskControl]

            func modifier(_ key: CGKeyCode, leaving state: CGEventFlags) {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                else { return }
                e.type = .flagsChanged
                e.flags = state
                e.post(tap: .cghidEventTap)
            }

            modifier(Self.VK_COMMAND, leaving: .maskCommand)
            modifier(Self.VK_CONTROL, leaving: held)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: Self.VK_C, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: Self.VK_C, keyDown: false) {
                down.flags = held
                up.flags = held
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            modifier(Self.VK_CONTROL, leaving: .maskCommand)
            modifier(Self.VK_COMMAND, leaving: [])
        }
    }

    static func postWisprHandsFree() {
        DispatchQueue.global().async {
            usleep(settleForOptionsPlus)
            let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            var waited = 0
            while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty,
                  waited < 40 {
                usleep(5_000)
                waited += 1
            }
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = backButtonStamp
            let held: CGEventFlags = [.maskSecondaryFn, .maskControl]

            // A modifier going down or coming up is a `flagsChanged` carrying
            // the state the keyboard is *left in*, not the key's own bit.
            func modifier(_ key: CGKeyCode, leaving state: CGEventFlags) {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                else { return }
                e.type = .flagsChanged
                e.flags = state
                e.post(tap: .cghidEventTap)
            }

            modifier(VK_FN, leaving: .maskSecondaryFn)
            modifier(VK_CONTROL, leaving: held)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: VK_SPACE, keyDown: true),
               let up   = CGEvent(keyboardEventSource: source, virtualKey: VK_SPACE, keyDown: false) {
                down.flags = held
                up.flags = held
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            modifier(VK_CONTROL, leaving: .maskSecondaryFn)
            modifier(VK_FN, leaving: [])
        }
    }

    // MARK: - The mouse gestures, posted from a script

    /// **One name per side-button gesture, and the chord Options+ makes for it.**
    ///
    /// The vocabulary is Victor's own (`🔼` forward, `🔽` back, plus a direction)
    /// written out in words a shell can type. The keycodes are the *instance*
    /// `VK_F*` above — not a second copy — which is the whole reason
    /// `postGesture` is an instance method where `postWisprHandsFree` is static:
    /// a static poster could not see them, and a duplicate table is exactly the
    /// drift *The numbers are duplicated in two places and must not drift*
    /// warns about.
    ///
    /// The three free rows are listed too. Options+ sends them and nothing here
    /// claims them, so posting one must visibly do nothing — which is a fact
    /// worth being able to assert rather than assume.
    var gestureNames: [String] {
        gestureVocabulary.map { $0.name }
    }

    private var gestureVocabulary: [(name: String, key: CGKeyCode, label: String, what: String)] {
        [("forward-click", VK_F7,  "⌃⌥⌘F7",  "dictate at the caret — or bind, with the left button held"),
         ("forward-right", VK_F10, "⌃⌥⌘F10",
          "start the dictation, or end the one open — with the left button held, bind and dictate"),
         ("forward-left",  VK_F11, "⌃⌥⌘F11", "cancel the dictation in flight"),
         ("forward-up",    VK_F8,  "⌃⌥⌘F8",  "dictate at a session that does not exist yet"),
         ("forward-down",  VK_F9,  "⌃⌥⌘F9",  "kamikaze — appends the word to the sentence in flight"),
         ("back-click",    VK_F6,  "⌃⌥⌘F6",  "start or stop Wispr Flow's dictation — a picture while the relay's own one is dictating"),
         ("back-down",     VK_F12, "⌃⌥⌘F12", "unbind — the menu's Disconnect"),
         ("back-right",    VK_F5,  "⌃⌥⌘F5",  "Return"),
         ("back-left",     VK_F3,  "⌃⌥⌘F3",  "cancel Wispr Flow's dictation — the relay's own when there is none"),
         ("back-up",       VK_F4,  "⌃⌥⌘F4",  "start or stop a screen recording, while a dictation is open")]
    }

    /// **Make a mouse gesture without a mouse** — `POST /test/gesture`.
    ///
    /// Every side-button gesture reaches this app as a keystroke and nothing
    /// else: Options+ diverts the button inside the mouse and emits ⌃⌥⌘ + a
    /// function key (*The side buttons speak in function keys*). So the honest
    /// way to fake one is to post that chord, which is what this does — it
    /// enters `handle`'s `useLogiGestures && ctrl && opt && cmd` branch by the
    /// same door a real gesture does, and every guard on the way (the autorepeat
    /// swallow, `reconcileButtons`, `leftIsHeld`) runs as it would for his hand.
    ///
    /// **The app's own tap sees it**, which is the property the whole route rests
    /// on: the tap is created at `.cgSessionEventTap` and this posts at
    /// `.cghidEventTap`, i.e. one level *below* it, so the event climbs through
    /// the session tap on its way to the front app. `postWisprHandsFree` has
    /// relied on exactly this since 2026-09-12 — the `fn ⌃ Space` it posts is
    /// read back by this tap's own Wispr watcher a moment later.
    ///
    /// **Stamped with `backButtonStamp`, and that does not hide it.** The gesture
    /// branch never looks at the stamp, so the chord is handled; the two branches
    /// that *do* look at it are the injection swallow and the probe, which is
    /// precisely where this app's own keystrokes must not be counted as another
    /// app's delivery. Stamping is therefore strictly quieter and changes
    /// nothing about what fires.
    ///
    /// **One sub-case is not fakeable and says so**: ⌃⌥⌘F7 with the left button
    /// genuinely held is the *bind* chord, and `leftIsHeld` asks the window
    /// server whether a physical button is down (`reconcileButtons`). Nothing
    /// posted can make that true, so `forward-click` from here is always the
    /// caret dictation.
    ///
    /// - Returns: the chord that went out, or nil for a name nobody knows.
    @discardableResult
    func postGesture(_ name: String) -> (label: String, what: String)? {
        guard let g = gestureVocabulary.first(where: { $0.name == name }) else { return nil }
        DispatchQueue.global().async {
            // The same settle `postReturn` documents at length. Nothing here is
            // posted from inside a tap callback, so the window server has no
            // live ⌃⌥⌘ of its own to merge — but a caller that fires two
            // gestures back to back is exactly the shape that trips it, and 45 ms
            // is nothing to a test.
            usleep(Self.settleForOptionsPlus)
            let source = CGEventSource(stateID: .hidSystemState)
            source?.userData = Self.backButtonStamp
            let held: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: g.key, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: source, virtualKey: g.key, keyDown: false)
            else { return }
            down.flags = held
            // Bare, for the reason `KeySimulator.simulateKeyPress` gives at
            // length: the last event's flags are what the session keeps.
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            // **And put the flags back down**, which Options+ does for itself
            // and this route did not (2026-09-13, 23:24).
            //
            // `CGEventSource` reports whatever the last event's flags said, so a
            // chord whose key-up carries ⌃⌥⌘ leaves the whole session believing
            // three modifiers are held until the next real keystroke heals it.
            // The gap between a real gesture and its trailing flags-cleared
            // event was measured at 12–22 ms on 2026-09-09; this route posted no
            // such event at all, so `settleForOptionsPlus` and every
            // wait-for-a-bare-wire loop behind it simply ran out — the Scratchpad
            // chord went out as `⌃⌥⌘F18`, which Wispr does not have bound, and
            // an ordinary paste came back instead of a note. It is the stale-⌘
            // bug of `area-crop.md` for a third time: **release the modifier
            // with a `flagsChanged` carrying the state the keyboard is left in.**
            // **On the modifiers' own keys.** Announced on `g.key` — an
            // F-key — this is not a modifier transition and the window server
            // need not apply it; see the fifth occurrence.
            for key: CGKeyCode in [Self.VK_COMMAND, Self.VK_CONTROL, 58] {
                guard let clear = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                else { continue }
                clear.type = .flagsChanged
                clear.flags = []
                clear.post(tap: .cghidEventTap)
            }
        }
        Log.info("🖱️ POST /test/gesture \(name) — posting \(g.label)")
        return (g.label, g.what)
    }


    private func injectionArmedNow() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return injectionArmed
    }

    /// **The probe, and it is the only record of how Wispr Flow delivers.**
    ///
    /// Nobody knew on 2026-09-12: the old `blockInjection` predated two Wispr
    /// versions, and the three candidate answers — a synthetic ⌘V, a key-by-key
    /// type, an Accessibility insertion — need three different mechanisms to
    /// catch. So every synthetic key inside the capture window says who posted
    /// it and what it was, capped so a recogniser that *types* cannot fill the
    /// log with the sentence it is typing. An insertion through Accessibility
    /// shows up here as **nothing at all**, which is itself the answer.
    private func probeInjected(pid: pid_t, code: CGKeyCode, flags: CGEventFlags) {
        stateLock.lock()
        guard injectionProbeLeft > 0 else { stateLock.unlock(); return }
        injectionProbeLeft -= 1
        stateLock.unlock()
        Log.info("probe: synthetic key \(code) flags 0x\(String(flags.rawValue, radix: 16)) "
                 + "from pid \(pid) (\(processName(pid)))")
    }

    // ── The Wispr firewall ───────────────────────────────────────────────────

    /// **Wispr Flow's ⌘V is dropped at the session tap, always, while this app
    /// runs** — `WT_WISPR_FIREWALL=0` for one run, `POST /test/firewall` at
    /// runtime. Read under `stateLock` on the tap thread beside the capture.
    private var wisprFirewall = ProcessInfo.processInfo.environment["WT_WISPR_FIREWALL"] != "0"
    var wisprFirewallOn: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return wisprFirewall
    }
    func setWisprFirewall(_ on: Bool) {
        stateLock.lock(); wisprFirewall = on; stateLock.unlock()
        Log.info("🛡️ Wispr firewall \(on ? "on — Wispr's ⌘V is dropped and the relay delivers" : "off — Wispr pastes where the focus is")")
    }
    /// **Is this pid Wispr Flow?** — answered on the tap thread, and it has to
    /// be right, because under an always-on drop a wrong *yes* eats an innocent
    /// application's ⌘V.
    ///
    /// Two layers. The name is the cheap one and it decides **now** — fail
    /// closed: a process called Wispr is dropped from its first paste. The
    /// signature is the sure one and runs once per process off the tap thread:
    /// a name match whose code is not signed by Wispr's Team ID is demoted, a
    /// signed Wispr under a name that does not say so is promoted. The cache is
    /// keyed on the pid **and its start time**, so a pid the kernel hands to
    /// another program after Wispr quits is a new question, not a stale yes.
    private struct ProcessKey: Hashable { let pid: pid_t; let started: Int64 }
    private var wisprIdentity: [ProcessKey: Bool] = [:]
    static let wisprTeamId = "C9VQZ78H85"

    private func isWispr(_ pid: pid_t) -> Bool {
        let key = ProcessKey(pid: pid, started: Self.startTime(of: pid))
        stateLock.lock()
        if let known = wisprIdentity[key] { stateLock.unlock(); return known }
        // A dead pid's entry is never read again; drop them when the map grows.
        if wisprIdentity.count > 64 {
            wisprIdentity = wisprIdentity.filter { kill($0.key.pid, 0) == 0 && Self.startTime(of: $0.key.pid) == $0.key.started }
        }
        stateLock.unlock()
        let match = processName(pid).lowercased().contains("wispr")
        stateLock.lock()
        wisprIdentity[key] = match
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let team = Self.teamIdentifier(of: pid)
            let signed = team == Self.wisprTeamId
            if signed != match {
                self.stateLock.lock()
                self.wisprIdentity[key] = signed
                self.stateLock.unlock()
                Log.error("🛡️ pid \(pid) (\(self.processName(pid))) — name said \(match ? "Wispr" : "not Wispr"), signature says team \(team ?? "none"): \(signed ? "treating it as Wispr" : "not Wispr after all")")
            }
        }
        return match
    }

    /// `kp_proc.p_starttime`, in microseconds; 0 for a pid that is gone.
    private static func startTime(of pid: pid_t) -> Int64 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        let t = info.kp_proc.p_un.__p_starttime
        return Int64(t.tv_sec) * 1_000_000 + Int64(t.tv_usec)
    }

    /// The Team ID the running code at `pid` is signed with, or nil.
    static func teamIdentifier(of pid: pid_t) -> String? {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // ── The canary: is the tap actually alive? ───────────────────────────────

    /// **A tap can say `enabled` and be inert** — `build-app.sh` re-signs this
    /// app on every change, and a green badge over a dead tap is a leaked
    /// sentence under an always-on drop. So the tap is asked to *prove* it:
    /// a harmless key (a bare V key-up, which no application acts on) is posted
    /// at the HID level carrying `canaryStamp`; this callback swallows it and
    /// says so. Not seen within the grace → the tap is dead, whatever
    /// `CGEventTapIsEnabled` reports, and `completion(false)` is the alarm.
    static let canaryStamp: Int64 = 0x7774_4341_4E41_5259   // "wtCANARY"
    private var canarySeenAt: CFAbsoluteTime = 0
    private(set) var lastCanary: (alive: Bool, ms: Double, at: Date)?

    func proveAlive(_ why: String, completion: @escaping (Bool) -> Void) {
        stateLock.lock(); canarySeenAt = 0; stateLock.unlock()
        let posted = CFAbsoluteTimeGetCurrent()
        let source = CGEventSource(stateID: .privateState)
        source?.userData = Self.canaryStamp
        guard let up = CGEvent(keyboardEventSource: source, virtualKey: Self.VK_V, keyDown: false) else {
            Log.error("🛡️ canary: could not even build the event"); completion(false); return
        }
        up.flags = []
        up.post(tap: .cghidEventTap)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); let seen = self.canarySeenAt; self.stateLock.unlock()
            let alive = seen > 0
            let ms = alive ? (seen - posted) * 1000 : 500
            self.stateLock.lock(); self.lastCanary = (alive, ms, Date()); self.stateLock.unlock()
            let enabled = self.tapPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
            if alive {
                Log.info(String(format: "🛡️ canary (%@): the tap is alive — seen after %.1f ms", why, ms))
            } else {
                Log.error("🛡️ canary (\(why)): the tap did NOT see its own event — enabled=\(enabled). The firewall is down: Wispr's ⌘V would reach the front app")
                if let port = self.tapPort { CGEvent.tapEnable(tap: port, enable: true) }
            }
            completion(alive)
        }
    }

    private func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buf)
    }

    /// Is this pid the mouse remapper — i.e. is that Return a button press in
    /// disguise?
    ///
    /// Matched by process name and nothing else. Swallowing a Return is only
    /// acceptable because it is provably not a keystroke: any *other* process
    /// posting one (a script, an automation, Victor Addons' own key simulator)
    /// meant it as an Enter and must be left alone.
    ///
    /// Answers are cached per pid: this runs on the event tap, once per Return
    /// pressed during a dictation, and a pid does not change identity.
    private func isRemapper(_ pid: pid_t) -> Bool {
        stateLock.lock()
        if let known = remapperPids[pid] { stateLock.unlock(); return known }
        stateLock.unlock()

        var buf = [CChar](repeating: 0, count: 256)
        let match = proc_name(pid, &buf, UInt32(buf.count)) > 0
                 && String(cString: buf) == Self.remapperProcessName

        stateLock.lock()
        remapperPids[pid] = match
        stateLock.unlock()
        return match
    }

    /// `~/.config/linearmouse/linearmouse.json` is where the button → Return
    /// mapping lives; this is the process that acts on it.
    ///
    /// **Uninstalled on 2026-09-07** — Victor Addons does this natively now, and
    /// is recognised by `backButtonStamp` instead, since a name cannot separate
    /// its disguised button from the Returns it posts for other reasons. Kept so
    /// that a reinstall keeps working, and because it costs one string.
    private static let remapperProcessName = "LinearMouse"
    private var remapperPids: [pid_t: Bool] = [:]

    /// The mark this app puts on the Return it posts for the back button's
    /// click, so its own tap can tell that Return from one Victor typed.
    ///
    /// It began life in Victor Addons' `BackButtonEnter.swift`, which used to
    /// make the Return; the value is kept rather than reinvented so that a
    /// version of that app still running against the old wiring is recognised
    /// rather than fought.
    /// Internal rather than private since 2026-09-14: `KeySimulator`'s ⌘C probe
    /// posts into the same event stream this tap reads, and an unstamped probe
    /// arrives looking exactly like a key Victor pressed.
    static let backButtonStamp: Int64 = 0x7774_4241_434B_0000

    /// How long `postReturn` lets the ⌃⌥⌘ that Options+ stamped on the chord
    /// wear off before it types. Measured 12–22 ms on this Mac; 45 ms is that
    /// with room over it, and far below what a finger notices between the click
    /// and the prompt going.
    private static let settleForOptionsPlus: UInt32 = 45_000

    /// The three keys of Wispr Flow's hands-free chord, written in the same
    /// numbers Wispr's own config stores them in: `"49+59+63"`.
    /// Escape, for `postWisprCancel` — Wispr Flow's *discard this*. Static
    /// beside the chord's keys rather than reusing the instance `VK_ESCAPE` the
    /// tap reads, because a static method cannot see that one.
    /// `NX_DEVICERCMDKEYMASK` / `NX_DEVICERALTKEYMASK` — the bits that say
    /// *which* ⌘ and *which* ⌥, which `CGEventFlags` has no names for. Wispr's
    /// push-to-talk is the right-hand pair specifically (`54+61`), and matching
    /// on `.maskCommand` instead would put the ring up on every ⌘⌥ in the day.
    private static let deviceRightCommand: UInt64 = 0x000010
    private static let deviceRightOption: UInt64 = 0x000040

    /// **V**, for the paste another app posts — see `onInjectedPaste`.
    private static let VK_V:       CGKeyCode = 9
    /// **C**, for Wispr's `copy_last_text` (`55+59+8` = ⌘⌃C). 8 is C.
    private static let VK_C:       CGKeyCode = 8
    private static let VK_COMMAND: CGKeyCode = 55
    private static let VK_ESC:     CGKeyCode = 53
    private static let VK_SPACE:   CGKeyCode = 49
    private static let VK_CONTROL: CGKeyCode = 59
    private static let VK_FN:      CGKeyCode = 63
}
