import AppKit
import CoreGraphics

private let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(ptr).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}

/// Global shortcuts for the bubble.
///
/// Chosen to not collide with anything Victor Addons already claims (it owns
/// ⌃P, ⌃⇧P, ⌃W, ⌃⌥C, ⌃⌥V, ⌘⌃C, ⌘⌥C, ⌘⌃A, ⌘⌃V, ⌘⌃⌥C, ⌘⌃⌥D) or with Wispr's
/// own ⌘⌥V "paste last transcript":
///
///   ⌃⌥P  screenshot the display under the cursor → send to Claude
///   ⌃⌥S  stash the current screen selection as the prefix for the next message
///   Mouse 5  (Wispr push-to-talk) — observed, never swallowed: snapshots the
///            selection at the instant dictation starts
final class HotkeyTap {

    var onScreenshot: (() -> Void)?
    var onStashSelection: (() -> Void)?
    var onDictationStarted: (() -> Void)?

    private let VK_P: CGKeyCode = 0x23
    private let VK_S: CGKeyCode = 0x01
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

        guard ctrl && opt && !cmd else { return Unmanaged.passUnretained(event) }

        if keyCode == VK_P {
            DispatchQueue.global().async { [weak self] in self?.onScreenshot?() }
            return nil   // swallow
        }
        if keyCode == VK_S {
            DispatchQueue.global().async { [weak self] in self?.onStashSelection?() }
            return nil   // swallow
        }
        return Unmanaged.passUnretained(event)
    }
}
