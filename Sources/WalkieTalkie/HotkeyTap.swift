import AppKit
import CoreGraphics

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(ptr).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

/// The overlay's global shortcut for "plus one shot": screenshot the display
/// under the cursor and add it to the dictation in progress (or send it on its
/// own if none is).
///
/// **F3** is the one to use. A chord needs a hand on three keys, and the moment
/// it is needed is the moment both hands are busy and a sentence is already
/// half-spoken; a bare function key can be hit blind, mid-dictation, without
/// looking. F3 does nothing else on Victor's machine.
///
/// ⌃⌥P still works, since it is what the muscle memory and the older notes say.
/// It was chosen to not collide with anything Victor Addons claims (⌃P, ⌃⇧P, ⌃W,
/// ⌃⌥C, ⌃⌥V, ⌘⌃C, ⌘⌥C, ⌘⌃A, ⌘⌃V, ⌘⌃⌥C, ⌘⌃⌥D).
///
/// Mouse 5 is passed through untouched apart from a **double** click, which
/// binds the window under the pointer. So does the left button, always — it is
/// watched only so the wheel can tell a rebind chord from a plain click.
///
/// **Mouse 4 (the back side button) is the same shot, without the keyboard.**
/// LinearMouse turns that button into a Return (`~/.config/linearmouse/`), which
/// is what Victor submits with all day — so it is borrowed only for the few
/// seconds a dictation is actually running, where an Enter into whatever happens
/// to have focus was never what he meant anyway. Outside that window the button
/// is untouched and still types Return. Held with ⌘ it is untouched too:
/// LinearMouse maps that separately to ⌘Return, and one gesture must not quietly
/// become two different things.
final class HotkeyTap {

    /// The cursor at the instant of the gesture — what he was pointing at.
    var onScreenshot: ((NSPoint) -> Void)?

    /// The wheel, clicked on its own: start the recording, or end the one that is
    /// open. A toggle and not a push-to-talk — a dictation at an agent runs to a
    /// minute or more, and a button held for a minute is a hand that cannot do
    /// anything else, including take the screenshots the same minute is for.
    var onLocalToggle: (() -> Void)?

    /// The wheel held down **while a dictation is running** — throw it away.
    /// Same verdict as the menu's Cancel Dictation, and the same verdict as
    /// pressing Cancel on the panel a moment later, without waiting for the model
    /// to transcribe something already known to be unwanted.
    var onLocalCancel: (() -> Void)?

    /// **⌘ + the wheel — talk at a session that does not exist yet.** Start a
    /// dictation whose destination is a Terminal window this app has not opened
    /// yet: at the end of it, a new one appears with an interactive Claude Code
    /// in it and the words as its first prompt.
    ///
    /// **It ignores every gate the bare wheel obeys.** A binding is the bare
    /// wheel's on switch (*Unbound is inert*) precisely because a dictation with
    /// nowhere to go is a room taped for nobody — and that argument does not
    /// reach this gesture, which *carries* its destination. So it acts whenever
    /// the app is running, bound or not, which is exactly what Victor asked for:
    /// the moment this is most useful is the moment there is no session yet.
    ///
    /// **Mid-dictation it is just the wheel.** The destination is decided at the
    /// press that opened the microphone and cannot be changed halfway through a
    /// sentence, so a ⌘ click while one is running ends it like any other,
    /// and it goes wherever it was already going.
    ///
    /// **⌘ rather than ⇧, since 2026-08-30**, and it costs less: ⌘-middle-click
    /// in a browser is redundant with a bare middle click (both open a link in a
    /// background tab), where ⇧-middle-click is a gesture of its own — new tab
    /// *and* switch to it. ⇧ was also already spoken for on this very wheel:
    /// LinearMouse maps ⇧ + vertical scroll to horizontal scroll, so holding it
    /// to press the button put a sideways scroll one twitch away.
    ///
    /// The price stands either way: the modifier belongs to this app for as long
    /// as it is running, not merely while something is bound. That is the
    /// deliberate reading of *"cât timp e pornit walkie"*.
    var onSpawnToggle: (() -> Void)?

    /// The wheel clicked **with the left button already held** — point the relay
    /// The wheel clicked **with the left button already held** — point the relay
    /// at the window in front. Same call ⌘⌃D makes, including its toggle: made on
    /// the terminal already bound, it lets go.
    ///
    /// Still returns whether anything was bound, and the return is now only
    /// logged: the click is never handed back to the app underneath, because with
    /// the left button down a replayed middle click would land in the middle of
    /// whatever drag or selection that button is in.
    var onWheelBind: (() -> Bool)?

    /// Whether the frontmost app is one `bind` would take. Pushed from
    /// `AppDelegate` on every app switch rather than asked here: the answer needs
    /// `NSWorkspace`, which is a main-thread question, and an event tap that
    /// blocks on the main thread is a frozen mouse.
    ///
    /// The wheel no longer consults it — rebinding is the left-plus-wheel chord
    /// and it acts wherever it is made, letting `bindFrontmostTerminal` refuse.
    /// It survives because the menu's **Bind This Window** row greys itself out
    /// with it, and this is where the answer is already kept up to date.
    var frontIsBindable: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return frontIsBindableFlag }
        set { stateLock.lock(); frontIsBindableFlag = newValue; stateLock.unlock() }
    }
    private var frontIsBindableFlag = false

    /// **Mouse 5, twice quickly — bind, exactly as ⌘⌃D does.** The keyboard
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
    /// ⌘⌃D — point the relay at the terminal in front, or end the session when it
    /// is already pointed there. Owned here since 2026-08-26; it used to live in
    /// Victor Addons, which had to launch this app before it could ask it to
    /// bind. Now that the relay starts at login there is nothing to launch, and
    /// the key belongs to the app it acts on.
    var onBindHotkey: (() -> Void)?
    /// ⌘⌃P — the last dictation, again: onto the clipboard and pasted at the
    /// caret. It sits beside ⌘⌃D because it is the same kind of key — a global
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

    /// When the left button went down, or 0 while it is up. Written and read only
    /// from the tap callback, which is one thread.
    private var leftDownAt: CFTimeInterval = 0
    private var leftIsHeld: Bool { leftDownAt > 0 && CACurrentMediaTime() - leftDownAt >= Self.chordHoldSeconds }

    /// The hold fired (or the chord was taken) — the matching release is ours
    /// too, or the app underneath is left holding a button that was never let go.
    private var wheelArmed = false
    /// A press we swallowed and have not yet judged.
    private var wheelDown = false
    /// …and whether ⌘ was down when we took it. Read at the release, because
    /// that is where a tap is told from a hold — and remembered rather than
    /// re-read, since the modifier may well be let go before the button is.
    private var wheelSpawn = false
    private var wheelHold: DispatchWorkItem?

    private let stateLock = NSLock()

    private let VK_D: CGKeyCode = 0x02
private let VK_P: CGKeyCode = 0x23
    private let VK_F3: CGKeyCode = 0x63
    private let VK_RETURN: CGKeyCode = 0x24        // Return
    private let VK_KEYPAD_ENTER: CGKeyCode = 0x4C  // Enter (keypad / Fn-Return)
private let VK_ESCAPE: CGKeyCode = 0x35        // esc
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
                 | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                 | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
                 // The left button is watched, never taken: rebinding is the
                 // wheel pressed *while it is already down*, so the tap has to
                 // know whether it is and since when. Both are passed straight
                 // through — see the branch at the top of `handle`.
                 | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                 | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)

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

        if type == .otherMouseDown || type == .otherMouseUp {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let bare = !event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl)
                    && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift)
            // **⌘ and nothing else.** Deliberately not folded into `bare`: every
            // branch below that asks for `bare` means "the gesture with no
            // destination of its own", and this one carries one.
            let commanded = event.flags.contains(.maskCommand)
                    && !event.flags.contains(.maskShift) && !event.flags.contains(.maskControl)
                    && !event.flags.contains(.maskAlternate)

            // Mouse 4 mid-dictation → a picture, and the Return it would have
            // become never happens. Both halves of the click are swallowed:
            // LinearMouse is downstream of this tap and would otherwise still
            // see an orphan release to act on.
            if button == MOUSE_BUTTON_4 && bare && dictating {
                if type == .otherMouseDown {
                    Log.info("📸 mouse 4 — reached the tap as a mouse button")
                    let cursor = NSEvent.mouseLocation
                    DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                }
                return nil
            }

            // The double-click test comes first, and applies whether or not
            // anything is bound: binding by pointing is most useful precisely
            // when nothing is bound yet, and that is the state in which mouse 5
            // is otherwise passed straight through.
            if button == MOUSE_BUTTON_5 && bare {
                if type == .otherMouseUp && swallowMouse5Up {
                    swallowMouse5Up = false
                    return nil
                }
                if type == .otherMouseDown {
                    let now = CACurrentMediaTime()
                    if now - lastMouse5DownAt <= NSEvent.doubleClickInterval {
                        // Zeroed rather than restamped, so a third click starts a
                        // fresh pair instead of binding again on every press.
                        lastMouse5DownAt = 0
                        swallowMouse5Up = true
                        Log.info("🎯 mouse 5 ×2 — binding")
                        // **Global, not main** — the same queue ⌘⌃D uses, and for
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
                }
            }

            // **The wheel means one thing on its own, and another with the left
            // button already held.**
            //
            //   wheel, alone         → start the dictation, or end the open one
            //   wheel, dictating,
            //     held two seconds   → cancel it: throw the audio away
            //   left held, then
            //     wheel              → rebind: point the relay at the window in front
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

            // **A prompt on screen outranks everything else the wheel means.**
            // It is the same verdict a click on the panel already gives and the
            // same one ⏎ gives; what it adds is that the hand which just clicked
            // the words to edit them does not have to travel to the keyboard to
            // approve them. Acted on the press, with no hold to wait out: there
            // is no second meaning here to tell it apart from.
            if button == MOUSE_BUTTON_MIDDLE && bare && promptHeld {
                if type == .otherMouseDown {
                    DispatchQueue.main.async { [weak self] in self?.onPromptEnter?() }
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
                let tapped = wheelDown && !wheelArmed
                // Read off the **press**, not off the flags now: ⌘ is very often
                // let go before the button is, and a gesture that changed its
                // mind between the two halves of one click would be the least
                // predictable thing in this file.
                let spawn = wheelSpawn
                wheelArmed = false
                wheelDown = false
                wheelSpawn = false
                wheelHold?.cancel()
                wheelHold = nil
                if tapped && spawn {
                    // Ending one is ending one, whichever gesture it started
                    // with — the destination was decided at the press that
                    // opened the microphone.
                    Log.info(dictating ? "🎙️ ⌘wheel tapped — ending the dictation"
                                       : "✨ ⌘wheel tapped — dictating at a new Claude Code")
                    DispatchQueue.global().async { [weak self] in self?.onSpawnToggle?() }
                } else if tapped && (localCapture || dictating) {
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
                // **Global, not main** — the same queue ⌘⌃D uses, and for the
                // reason it uses it: `bindFrontmostTerminal` asks the main thread
                // for the frontmost app with `main.sync`, so arriving there
                // already on main is a wait for a queue that is waiting for you.
                // libdispatch does not deadlock on that, it traps.
                DispatchQueue.global().async { [weak self] in _ = self?.onWheelBind?() }
                return nil
            }

            // **The wheel on its own, while there is somewhere for words to go.**
            // Swallowed on the press and judged at the release above, because a
            // tap and a two-second hold are the same event until the finger
            // lifts.
            // **⌘ makes the same press mean "and open somewhere to put it".**
            // It joins this branch rather than getting one of its own because
            // everything from here down is identical — the press is swallowed,
            // a hold still cancels a running dictation, and the tap is judged at
            // the release. The only difference is which callback the release
            // makes, and that is what `wheelSpawn` carries.
            //
            // Note what it does *not* consult: `localCapture`. The bare wheel is
            // inert with nothing bound because its words would have nowhere to
            // go; these words bring their own destination, so the gesture is
            // live for as long as the app is.
            if button == MOUSE_BUTTON_MIDDLE && type == .otherMouseDown
                && ((bare && (localCapture || dictating)) || commanded) {
                wheelDown = true
                wheelSpawn = commanded
                // Only a running dictation has a second meaning for a long press.
                // Idle, the press is a tap however long it lasts — there is
                // nothing left for a hold to mean.
                guard dictating else { return nil }
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self, self.wheelDown else { return }
                    // The state at the press picked this timer and the state at
                    // the fire has to still agree — a dictation that ended under
                    // his finger must not have its cancel land on the next one.
                    guard self.dictating else { return }
                    self.wheelDown = false
                    self.wheelArmed = true
                    Log.info("🗑️ wheel held while dictating — cancelling it")
                    DispatchQueue.global().async { [weak self] in self?.onLocalCancel?() }
                }
                wheelHold = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.cancelHoldSeconds, execute: work)
                return nil
            }

            // Mouse 5 otherwise belongs to whatever the system has mapped it
            // to — the relay only ever claims the double click above.
            return Unmanaged.passUnretained(event)
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

        // The same button, arriving as a keystroke.
        //
        // LinearMouse taps the event stream **upstream of this one**, so the
        // remap happens before a session tap can ever see a mouse button: what
        // reaches us is already a Return. The branch above therefore never fires
        // on Victor's Mac, and is kept only because it is the correct handling if
        // the order is ever the other way round.
        //
        // Telling this Return from the one he types is the whole trick, and the
        // discriminator is the source pid: a key pressed on real hardware carries
        // 0, an event posted by a process carries that process's pid. So the
        // physical Return key is never touched — only one that LinearMouse itself
        // manufactured, and only while a dictation is running.
        if (keyCode == VK_RETURN || keyCode == VK_KEYPAD_ENTER) && dictating
            && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
            let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
            let synthetic = pid != 0 && isRemapper(pid)
            Log.info("↩︎ Return while dictating — source pid \(pid), remapper=\(synthetic)")
            if synthetic {
                let cursor = NSEvent.mouseLocation
                DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
                return nil   // swallow: the Enter it would have been is not wanted mid-dictation
            }
        }

        // F3 on its own. Swallowed like any other binding, so whatever the key is
        // nominally wired to cannot fire behind the screenshot.
        if keyCode == VK_F3 && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
            let cursor = NSEvent.mouseLocation
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
            return nil
        }

        // ⌘⌃D, and not ⌘⌃⌥D — that one is Victor Addons' dark-mode toggle, and
        // the two are told apart by ⌥ alone.
        //
        // **Autorepeat is swallowed, not acted on.** A second press on the target
        // already bound *ends the session*, so a key held a moment too long would
        // otherwise bind and immediately stop the session it just started — the
        // one input mistake this gesture cannot afford. The event is eaten either
        // way, so nothing downstream sees the repeat (it shadows the system-wide
        // ⌘⌃D "look up in dictionary", which is deliberate and long-standing).
        if keyCode == VK_D && cmd && ctrl && !opt {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            DispatchQueue.global().async { [weak self] in self?.onBindHotkey?() }
            return nil
        }

        // Autorepeat swallowed for the same reason ⌘⌃D swallows it: a key held a
        // moment too long would paste the sentence four times into whatever he
        // is typing in, and unlike a bind that is not undone by pressing it
        // again. The event is eaten either way — it shadows nothing standard.
        if keyCode == VK_P && cmd && ctrl && !opt {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            DispatchQueue.global().async { [weak self] in self?.onPasteLast?() }
            return nil
        }

        guard ctrl && opt && !cmd else { return Unmanaged.passUnretained(event) }

        if keyCode == VK_P {
            let cursor = NSEvent.mouseLocation
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
            return nil   // swallow
        }
        return Unmanaged.passUnretained(event)
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
    private static let remapperProcessName = "LinearMouse"
    private var remapperPids: [pid_t: Bool] = [:]
}
