import AppKit
import CoreGraphics

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
final class HotkeyTap {

    /// The cursor at the instant of the gesture — what he was pointing at.
    var onScreenshot: ((NSPoint) -> Void)?

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
    /// ⌘⌃P — the last dictation, again: onto the clipboard and pasted at the
    /// caret. It sits beside ⌘⌃B because it is the same kind of key — a global
    /// one this app owns outright — and on P because the neighbouring ⌃⌥P is
    /// already the shutter, so the two things Victor reaches for after a
    /// sentence share a letter and differ by which modifier the hand is holding.
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
    private var leftDownAt: CFTimeInterval = 0
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
                return Unmanaged.passUnretained(event)
            case .leftMouseUp:
                leftDownAt = 0
                return Unmanaged.passUnretained(event)
            case .rightMouseDown, .rightMouseUp,
                 .otherMouseDown, .otherMouseUp:
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
                return Unmanaged.passUnretained(event)
            }
            if type == .leftMouseUp {
                leftDownAt = 0
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

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let ctrl = flags.contains(.maskControl)
        let opt = flags.contains(.maskAlternate)
        let cmd = flags.contains(.maskCommand)

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
            return nil   // swallow: the panel took it, so nothing behind it should
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
        // again. The event is eaten either way — it shadows nothing standard.
        if keyCode == VK_P && cmd && ctrl && !opt {
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
        if useLogiGestures && ctrl && opt && cmd {
            switch keyCode {
            // ➡️ — the mouse moved right with the forward button held: start the
            // dictation, or end the one already open. The same call ⌘⌃D makes,
            // so a dictation started with the key ends with the gesture and the
            // other way round. Where it goes is not this gesture's business: a
            // bound terminal takes it, and Replace Wispr sends it to the caret.
            case VK_F10:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                return nil

            // ⬅️ — throw the running dictation away. Deliberately the mirror
            // direction of the one that starts it: the two gestures that open
            // and abandon a sentence are the same hand movement, reversed.
            case VK_F11:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
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
            // With the left button up it is the microphone for a dictation that
            // goes to the caret, gated on the mode alone exactly as it was when
            // this lived on mouse 5: a dictation aimed at the caret carries its
            // own destination, so *Unbound is inert* has nothing to say about
            // it. The bind is **not** gated on the mode — it is the one gesture
            // that says where words go, and it has to work whichever way the
            // next sentence is headed. Outside the mode and with nothing held
            // the same click means the same sentence in the other engine's
            // hands: it types Wispr Flow's hands-free chord — see
            // `postWisprHandsFree`. So the chord is eaten in every branch now,
            // where it used to be handed on when nothing here wanted it.
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
                guard replaceWispr else {
                    Log.info("🎙️ forward button — Wispr Flow's hands-free toggle")
                    Self.postWisprHandsFree()
                    return nil
                }
                DispatchQueue.global().async { [weak self] in self?.onPasteToggle?() }
                return nil

            // 🔽 → — Wispr Flow's hands-free toggle **while Replace Wispr is
            // ticked**, which is the one mode where the forward button cannot
            // offer it: there the click is this app's own microphone at the
            // caret, and Victor still wants Wispr reachable without going to the
            // menu to untick anything. Same chord, same `postWisprHandsFree`.
            //
            // Gated, and it stays a free row outside the mode on purpose: with
            // Replace Wispr unticked the forward click already *is* this verb,
            // and two gestures for one verb is the thing the Options+ screen has
            // room for and the hand does not.
            case VK_F5:
                guard replaceWispr else { return Unmanaged.passUnretained(event) }
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                Log.info("🎙️ 🔽 → — Wispr Flow's hands-free toggle")
                Self.postWisprHandsFree()
                return nil

            // The back button **clicked** — a picture while a dictation is
            // running, and Return at every other moment.
            //
            // **The Return is posted here now, and that is new.** The button used
            // to type it itself: LinearMouse, then Victor Addons' `BackButtonEnter`,
            // remapped it upstream of this tap, and the tap's only job was to
            // *withhold* that Return mid-dictation and take the shot instead.
            // Options+ owns the button now, so nothing upstream types anything —
            // if this branch does not post the Return, the key Victor submits with
            // all day simply stops existing.
            case VK_F6:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                if dictating {
                    let cursor = NSEvent.mouseLocation
                    DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                } else {
                    Self.postReturn()
                }
                return nil

            default:
                break
            }
        }

        guard ctrl && opt && !cmd else { return Unmanaged.passUnretained(event) }

        if keyCode == VK_P {
            let cursor = NSEvent.mouseLocation
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
            return nil   // swallow
        }
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
    private static let backButtonStamp: Int64 = 0x7774_4241_434B_0000

    /// How long `postReturn` lets the ⌃⌥⌘ that Options+ stamped on the chord
    /// wear off before it types. Measured 12–22 ms on this Mac; 45 ms is that
    /// with room over it, and far below what a finger notices between the click
    /// and the prompt going.
    private static let settleForOptionsPlus: UInt32 = 45_000

    /// The three keys of Wispr Flow's hands-free chord, written in the same
    /// numbers Wispr's own config stores them in: `"49+59+63"`.
    private static let VK_SPACE:   CGKeyCode = 49
    private static let VK_CONTROL: CGKeyCode = 59
    private static let VK_FN:      CGKeyCode = 63
}
