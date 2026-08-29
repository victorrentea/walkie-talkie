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
/// ⌃⌥C, ⌃⌥V, ⌘⌃C, ⌘⌥C, ⌘⌃A, ⌘⌃V, ⌘⌃⌥C, ⌘⌃⌥D) or with Wispr's own ⌘⌥V.
///
/// Mouse 5 (Wispr push-to-talk) is still observed — never swallowed — but only
/// as a hint; the authoritative dictation signal is `DictationMonitor`.
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
    var onDictationStarted: (() -> Void)?

    /// Mouse 5, when it is the relay's and not Wispr's: start or stop the local
    /// recording. Fired on the press only — the release is swallowed with it and
    /// says nothing, because this is a toggle and not a push-to-talk.
    var onLocalToggle: (() -> Void)?

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

    /// Wispr is recording **and** the relay is forwarding — the only window in
    /// which mouse 4 is ours. Written from the main thread, read from the tap
    /// thread, hence the lock.
    var dictating: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return dictatingFlag }
        set { stateLock.lock(); dictatingFlag = newValue; stateLock.unlock() }
    }
    private var dictatingFlag = false

    /// Local Whisper is the engine **and** the relay is forwarding — the state in
    /// which mouse 5 belongs to the relay and must never reach Wispr, because in
    /// that mode Wispr is not in the loop at all: the relay holds the microphone
    /// itself. Set from the main thread by `AppDelegate.syncLocalCapture`.
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

    // MARK: The wheel's two presses

    /// How long the wheel must be held to start a dictation.
    private static let wheelHoldSeconds: TimeInterval = 0.4
    /// The hold fired (or a stop was sent) — the matching release is ours too,
    /// or the app underneath is left holding a button that was never let go.
    private var wheelArmed = false
    /// A press we swallowed and have not yet judged. If it ends short, it was a
    /// plain middle click and is replayed.
    private var wheelPending: (at: CFTimeInterval, position: CGPoint)?
    private var wheelHold: DispatchWorkItem?
    /// While `CACurrentMediaTime()` is under this, wheel events are passed
    /// through untouched — it is how a replayed click gets past the tap that
    /// produced it. A time window rather than a tag on the event, because a tag
    /// that failed to survive posting would be an infinite loop, and a window
    /// that fails is one click let through.
    private var wheelReplayUntil: CFTimeInterval = 0

    /// Swallow keystrokes **posted by Wispr Flow itself** — i.e. the transcript it
    /// types or pastes into whatever holds the caret.
    ///
    /// That paste is the thing Victor dictates *around*: he talks about a page he
    /// is reading, and Wispr drops the sentence into the document, the search
    /// field, the terminal — wherever the caret happened to be. The relay already
    /// takes the words from Wispr's database, so the injection is pure damage.
    ///
    /// Off while paused, and that is the whole meaning of pause: pausing is what
    /// he does to dictate *into* an app, and the app getting the text is then
    /// exactly what he wants.
    var blockInjection: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return blockInjectionFlag }
        set { stateLock.lock(); blockInjectionFlag = newValue; stateLock.unlock() }
    }
    private var blockInjectionFlag = false

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

        if type == .otherMouseDown || type == .otherMouseUp {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let bare = !event.flags.contains(.maskCommand) && !event.flags.contains(.maskControl)
                    && !event.flags.contains(.maskAlternate) && !event.flags.contains(.maskShift)

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
            // is otherwise passed straight through to Wispr.
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

            // **Hold the wheel to start, tap it to stop.**
            //
            // The two live in different states, which is what makes the wheel
            // affordable at all. Starting is the deliberate gesture, so it costs
            // a 400ms hold; stopping happens while a row on screen says a
            // dictation is running, so a tap is unambiguous there and instant.
            // And a tap while nothing is recording now means nothing to this app
            // — so it is **given back**, and middle-click goes on opening links
            // and closing tabs the way it always did. That is the half that
            // repairs the bargain: the wheel was swallowed outright for as long
            // as a terminal was bound, which is hours, for a gesture Victor uses
            // in Chrome all day.
            //
            // The press is swallowed first and judged on release, because the
            // decision cannot be made when the button goes down. A short one is
            // then **replayed** as a synthetic click. The alternative — pass the
            // press through and swallow only the release — leaves whatever is
            // underneath holding a button that never came up, which is the same
            // orphan-event bug this file already guards against twice, pointing
            // the other way.
            if button == MOUSE_BUTTON_MIDDLE && CACurrentMediaTime() < wheelReplayUntil {
                return Unmanaged.passUnretained(event)   // our own replay, going out
            }

            if button == MOUSE_BUTTON_MIDDLE && bare && localCapture {
                if type == .otherMouseDown {
                    if dictating {
                        // Recording: the tap ends it, now.
                        wheelArmed = true
                        Log.info("🎙️ wheel — ending the dictation")
                        DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                        return nil
                    }
                    let position = event.location
                    wheelPending = (CACurrentMediaTime(), position)
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self, self.wheelPending != nil else { return }
                        self.wheelPending = nil
                        self.wheelArmed = true
                        Log.info("🎙️ wheel held — starting a dictation")
                        DispatchQueue.global().async { [weak self] in self?.onLocalToggle?() }
                    }
                    wheelHold = work
                    // On main, so cancelling from the tap thread races nothing:
                    // the tap serialises its own callbacks and this is the only
                    // other toucher.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.wheelHoldSeconds, execute: work)
                    return nil
                }

                // .otherMouseUp
                if wheelArmed {
                    wheelArmed = false
                    return nil
                }
                if let pending = wheelPending {
                    wheelPending = nil
                    wheelHold?.cancel()
                    wheelHold = nil
                    replayMiddleClick(at: pending.position)
                    return nil
                }
                return nil
            }

            if type == .otherMouseDown && button == MOUSE_BUTTON_5 {
                // Untouched, always: mouse 5 is Wispr Flow's push-to-talk and the
                // relay only *observes* it — a hint that lands a beat before
                // CoreAudio confirms, for the Wispr engine's own path.
                DispatchQueue.global().async { [weak self] in self?.onDictationStarted?() }
            }
            return Unmanaged.passUnretained(event)
        }

        // Anything Wispr Flow types or pastes, dropped before it reaches the app
        // under the caret. Checked first, and for all three keyboard event types:
        // whatever mechanism Wispr uses, if it arrives as a posted event it is
        // stopped here, and if nothing is ever logged then it does not arrive as
        // one at all (it would be going through the Accessibility API instead,
        // which no event tap can see).
        if blockInjection {
            let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
            if pid != 0 && isWispr(pid) {
                noteSwallowed(type: type, event: event, pid: pid)
                return nil
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

        guard ctrl && opt && !cmd else { return Unmanaged.passUnretained(event) }

        if keyCode == VK_P {
            let cursor = NSEvent.mouseLocation
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?(cursor) }
            return nil   // swallow
        }
        return Unmanaged.passUnretained(event)
    }

    /// Post the middle click we swallowed while waiting to see whether it was a
    /// hold. Sent at the position it was pressed at, not at the pointer now: the
    /// judgement took 400ms at most, but a click belongs where the hand put it.
    private func replayMiddleClick(at position: CGPoint) {
        wheelReplayUntil = CACurrentMediaTime() + 0.3
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: position, mouseButton: .center) else { continue }
            e.post(tap: .cgSessionEventTap)
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
    private static let remapperProcessName = "LinearMouse"
    private var remapperPids: [pid_t: Bool] = [:]

    /// Is this pid Wispr Flow, or one of its helpers?
    ///
    /// Matched on the process name by prefix because Electron spreads itself over
    /// `Wispr Flow`, `Wispr Flow Helper (Renderer)` and friends, and which of them
    /// posts the keystrokes is an implementation detail of a third-party app —
    /// one that may well change under us. Cached per pid like `isRemapper`: this
    /// runs on the event tap, for every key of a transcript being typed out.
    private func isWispr(_ pid: pid_t) -> Bool {
        stateLock.lock()
        if let known = wisprPids[pid] { stateLock.unlock(); return known }
        stateLock.unlock()

        var buf = [CChar](repeating: 0, count: 256)
        let match = proc_name(pid, &buf, UInt32(buf.count)) > 0
                 && String(cString: buf).hasPrefix(Self.wisprProcessPrefix)

        stateLock.lock()
        wisprPids[pid] = match
        stateLock.unlock()
        return match
    }

    private static let wisprProcessPrefix = "Wispr Flow"
    private var wisprPids: [pid_t: Bool] = [:]

    /// One line per burst, not per key.
    ///
    /// A transcript typed character by character is hundreds of events, and a log
    /// line each would bury everything else the relay says. What is worth knowing
    /// is *that* an injection was stopped and what it looked like — the first
    /// event carries the mechanism (a ⌘V, or a key with a unicode payload) — plus
    /// how many followed it. A gap of a second ends the burst.
    private func noteSwallowed(type: CGEventType, event: CGEvent, pid: pid_t) {
        stateLock.lock()
        let now = Date().timeIntervalSinceReferenceDate
        let fresh = now - lastSwallowAt > 1.0
        if fresh {
            if burstCount > 0 { Log.info("🛑 …and \(burstCount) more events from Wispr") }
            burstCount = 0
        } else {
            burstCount += 1
        }
        lastSwallowAt = now
        stateLock.unlock()

        guard fresh else { return }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        let typed = length > 0 ? String(utf16CodeUnits: chars, count: length) : ""
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        Log.info("🛑 swallowed Wispr injection — \(Self.name(type)) key=\(key) flags=\(event.flags.rawValue)"
                 + (typed.isEmpty ? "" : " text=\(typed.debugDescription)") + " pid=\(pid)")
    }

    private var lastSwallowAt: TimeInterval = 0
    private var burstCount = 0

    private static func name(_ type: CGEventType) -> String {
        switch type {
        case .keyDown:      return "keyDown"
        case .keyUp:        return "keyUp"
        case .flagsChanged: return "flagsChanged"
        default:            return "type\(type.rawValue)"
        }
    }
}
