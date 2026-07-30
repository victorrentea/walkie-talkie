import AppKit
import CoreGraphics

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(ptr).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

/// The bubble's global shortcut for "plus one shot": screenshot the display
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
final class HotkeyTap {

    var onScreenshot: (() -> Void)?
    var onDictationStarted: (() -> Void)?

    private let VK_P: CGKeyCode = 0x23
    private let VK_F3: CGKeyCode = 0x63
    private let MOUSE_BUTTON_5: Int64 = 4   // 0-indexed "forward" side button

    private var tapPort: CFMachPort?
    var isActive: Bool { tapPort != nil }

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.error("could not create event tap — grant Accessibility permission to Claude Bubble")
            return false
        }
        tapPort = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "ClaudeBubbleEventTap"
        thread.start()
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable after a system timeout disable, else the tap dies silently.
        if type.rawValue == 0xFFFFFFFE || type.rawValue == 0xFFFFFFFF {
            if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            if event.getIntegerValueField(.mouseEventButtonNumber) == MOUSE_BUTTON_5 {
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

        // F3 on its own. Swallowed like any other binding, so whatever the key is
        // nominally wired to cannot fire behind the screenshot.
        if keyCode == VK_F3 && !ctrl && !opt && !cmd && !flags.contains(.maskShift) {
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?() }
            return nil
        }

        guard ctrl && opt && !cmd else { return Unmanaged.passUnretained(event) }

        if keyCode == VK_P {
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?() }
            return nil   // swallow
        }
        return Unmanaged.passUnretained(event)
    }
}
