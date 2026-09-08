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
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.keyUp.rawValue)
                 | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

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

        // **Every mouse button now goes straight past.** Until 2026-09-09 this
        // tap owned the wheel, both side buttons, and read the left and right
        // ones as modifiers for chords built on top of them. All of it is gone,
        // and the reason is hardware: the two side buttons are diverted inside
        // the mouse — measured at every level, they reach neither this tap nor
        // the raw HID report, with Logi Options+ running *or killed* — so the
        // branches that waited for them could never fire again. The wheel could
        // still be taken, and is deliberately not: Victor's ask was to hand it
        // back (*"eliberezi orice gest ce implică rotița"*), which returns
        // middle-click-to-close-a-tab to Chrome and VS Code for the first time
        // since the relay was bound to a terminal — the price *The wheel is the
        // relay's* used to state as unavoidable.
        //
        // What replaced them: Logi Options+ custom gestures, which emit a
        // **keystroke** of our choosing for each side-button gesture. Those
        // arrive as ⌃⌥⌘F3…F12 below, are indistinguishable from a key press,
        // and cost this tap nothing but a keycode comparison.
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

        // **The back button's Return no longer arrives as a Return.** Until
        // 2026-09-09 that button was remapped upstream of this tap — LinearMouse,
        // then Victor Addons' `BackButtonEnter` — and the branch that stood here
        // existed to *withhold* the Return mid-dictation and take a picture
        // instead, telling a disguised button from a typed key by an event-source
        // stamp. Options+ owns the button now and emits ⌃⌥⌘F6, so there is no
        // disguised Return left to catch: the picture and the Return are both
        // decided in that branch, and this app posts the Return itself.
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
        if ctrl && opt && cmd {
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

            // ⬇️ — point the relay at the terminal in front. **No toggle**, like
            // the left-plus-wheel chord it replaces: the gesture is made while
            // pointing at the terminal he means, and the ordinary reason to make
            // it twice is not being sure the first one landed.
            case VK_F9:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in _ = self?.onGestureBind?() }
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

            // The forward button **clicked**, with no movement — the microphone
            // for a dictation that goes to the caret. Gated on the mode alone,
            // exactly as it was when this lived on mouse 5: a dictation aimed at
            // the caret carries its own destination, so *Unbound is inert* has
            // nothing to say about it. Outside the mode the chord is handed on
            // rather than eaten, so Options+ can be pointed at something else
            // without this app quietly eating it.
            case VK_F7:
                guard replaceWispr else { return Unmanaged.passUnretained(event) }
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                DispatchQueue.global().async { [weak self] in self?.onPasteToggle?() }
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
    static func postReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = backButtonStamp
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }


    /// The mark this app puts on the Return it posts for the back button's
    /// click, so its own tap can tell that Return from one Victor typed.
    ///
    /// It began life in Victor Addons' `BackButtonEnter.swift`, which used to
    /// make the Return; the value is kept rather than reinvented so that a
    /// version of that app still running against the old wiring is recognised
    /// rather than fought.
    private static let backButtonStamp: Int64 = 0x7774_4241_434B_0000
}
