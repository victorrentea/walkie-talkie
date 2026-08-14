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

    /// Wispr is recording **and** the relay is forwarding — the only window in
    /// which mouse 4 is ours. Written from the main thread, read from the tap
    /// thread, hence the lock.
    var dictating: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return dictatingFlag }
        set { stateLock.lock(); dictatingFlag = newValue; stateLock.unlock() }
    }
    private var dictatingFlag = false
    private let stateLock = NSLock()

    private let VK_P: CGKeyCode = 0x23
    private let VK_F3: CGKeyCode = 0x63
    private let VK_RETURN: CGKeyCode = 0x24        // Return
    private let VK_KEYPAD_ENTER: CGKeyCode = 0x4C  // Enter (keypad / Fn-Return)
    private let MOUSE_BUTTON_4: Int64 = 3   // 0-indexed "back" side button — LinearMouse types Return with it
    private let MOUSE_BUTTON_5: Int64 = 4   // 0-indexed "forward" side button

    private var tapPort: CFMachPort?
    var isActive: Bool { tapPort != nil }

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
            Log.error("could not create event tap — grant Accessibility permission to Wispr Relay")
            return false
        }
        tapPort = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "WisprRelayEventTap"
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

            if type == .otherMouseDown && button == MOUSE_BUTTON_5 {
                // Pass through — Wispr Flow must still see its push-to-talk.
                DispatchQueue.global().async { [weak self] in self?.onDictationStarted?() }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let ctrl = flags.contains(.maskControl)
        let opt = flags.contains(.maskAlternate)
        let cmd = flags.contains(.maskCommand)

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
