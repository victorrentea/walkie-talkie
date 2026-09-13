import AppKit
import ApplicationServices

/// Reads whatever text is selected on screen right now, in the frontmost app.
///
/// Two strategies, in order:
///  1. **Accessibility** (`kAXSelectedTextAttribute` on the focused element) —
///     side-effect free, never touches the clipboard. Works in native apps and
///     most Electron/Chrome text fields.
///  2. **Simulated Cmd+C** — the fallback for apps that don't expose selected
///     text over AX (a lot of web content). The clipboard is snapshotted and
///     restored afterwards, so Victor's real clipboard survives the probe.
enum SelectionCapture {

    /// Runs on a background thread: strategy 2 blocks briefly polling the pasteboard.
    ///
    /// **The shutter uses this too, since 2026-08-31.** It used to call a
    /// `readQuiet()` that stopped after strategy 1, on the reasoning that a
    /// synthetic ⌘C posted into whatever app is under his hand, several times
    /// per sentence, is a side effect the gesture never promised. The reasoning
    /// was sound and the result was that the gesture did not work where he
    /// actually uses it: a highlight in a Chrome *page* is exactly the case AX
    /// does not see, so every shot taken over one recorded nothing, silently.
    /// A shutter press is a deliberate act with a deliberate subject; the ⌘C is
    /// a price Victor asked to pay, and with nothing selected the probe is a
    /// no-op the app never notices.
    static func read() -> String? {
        if let ax = readViaAccessibility(), !ax.isEmpty { return ax }
        return readViaClipboardProbe()
    }

    /// **Strategy 1 alone — no keystroke, no clipboard, nothing the app can
    /// notice.** For the watcher that reads the selection *every second* while a
    /// dictation is running (`AppDelegate.pollSelection`).
    ///
    /// This is `readQuiet` back from the dead, and the argument that removed it
    /// on 2026-08-31 is the argument for it here. It was taken out because the
    /// **shutter** used it: a deliberate press with a deliberate subject, where
    /// stopping at AX meant a highlight in a Chrome page recorded nothing at
    /// all, silently, and the ⌘C was a price Victor asked to pay for it. Nothing
    /// about that transfers to a poll. A synthetic ⌘C posted into whatever app
    /// is under his hand *once per second, all sentence*, is not a price
    /// anybody would pay: it would fight his own copying, spend 400ms of a
    /// pasteboard wait per tick, and stamp on the clipboard restore if two
    /// probes ever overlapped. So the watcher sees what AX exposes and no more,
    /// and the shutter stays exactly what it was for everything AX cannot see.
    ///
    /// **The messaging timeout is the other half.** `AXUIElementCopyAttributeValue`
    /// blocks until the target app answers, and the default allowance is
    /// seconds — an app mid-beachball would otherwise stall this queue through
    /// tick after tick. Half a second is far longer than a healthy answer takes
    /// and short enough that a sick app costs one skipped read.
    static func readQuiet() -> String? {
        readViaAccessibility(timeout: 0.5)
    }

    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - 1. Accessibility

    private static func readViaAccessibility(timeout: Float? = nil) -> String? {
        let system = AXUIElementCreateSystemWide()
        if let timeout = timeout { AXUIElementSetMessagingTimeout(system, timeout) }

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        // CFTypeRef → AXUIElement: the API guarantees this type for the attribute.
        let focusedElement = element as! AXUIElement
        // Set on both: the timeout belongs to the element it is asked of, and
        // the focused element is a different one from the system-wide handle.
        if let timeout = timeout { AXUIElementSetMessagingTimeout(focusedElement, timeout) }

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 2. Clipboard probe (Cmd+C, then restore)

    private static func readViaClipboardProbe() -> String? {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        let saved = snapshotClipboard(pb)

        KeySimulator.cmdC()

        // changeCount bumps on every pasteboard write, even of identical
        // content, so it reliably distinguishes "copied" from "nothing was
        // selected" (apps no-op Cmd+C with an empty selection).
        var waited: TimeInterval = 0
        let step: TimeInterval = 0.02
        while pb.changeCount == before && waited < 0.4 {
            Thread.sleep(forTimeInterval: step)
            waited += step
        }
        guard pb.changeCount != before else { return nil }

        let copied = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        restoreClipboard(pb, saved)
        return (copied?.isEmpty == false) ? copied : nil
    }

    /// Snapshot every representation of the current clipboard item so restoring
    /// doesn't silently downgrade a rich copy (an image, RTF, a file URL) to
    /// plain text.
    private static func snapshotClipboard(_ pb: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var saved: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pb.types ?? [] {
            if let data = pb.data(forType: type) { saved[type] = data }
        }
        return saved
    }

    private static func restoreClipboard(_ pb: NSPasteboard, _ saved: [NSPasteboard.PasteboardType: Data]) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.declareTypes(Array(saved.keys), owner: nil)
        for (type, data) in saved { pb.setData(data, forType: type) }
    }
}

enum KeySimulator {

    /// **A key with a modifier stamped on it, and the modifier put back down
    /// afterwards** — the second half of which was missing until 2026-09-14 and
    /// is the whole of this comment.
    ///
    /// The ⌘ is **flag-only**: there is no ⌘ `keyDown`/`keyUp` and no
    /// `flagsChanged` asserting it, so the session never believes a modifier is
    /// physically held while this runs. That half was always right.
    ///
    /// What was wrong is what it left behind. `CGEventSource.flagsState` reports
    /// **whatever the last event's flags said**, and the `keyUp` here carried
    /// `.maskCommand` — so after every probe the session believed ⌘ was held,
    /// indefinitely, until Victor's next real keystroke healed it. That is the
    /// stale-⌘ bug `area-crop.md` documents for `TerminalBinding.tap(key:command:)`
    /// and which was fixed there on 2026-09-10; this poster never got the fix,
    /// and the rule is the same one: **release the modifier with a `flagsChanged`
    /// carrying the state the keyboard is left in.**
    ///
    /// It matters more here than it did there, because of the other half of that
    /// same rule: **the window server merges live modifier state back into a
    /// posted key.** A letter arriving while the session believes ⌘ is down is
    /// delivered as **⌘ + that letter** — and the probe letters the loop types
    /// are `q z j k w y v`, which against TextEdit are *quit*, *close the
    /// document*, *undo* and four edits. A sentence's worth of keystrokes
    /// vanishing, and an empty victim document, are exactly what that would look
    /// like.
    ///
    /// **Stamped**, too: `keyboardEventSource: nil` gave the event pid 0 and no
    /// `userData`, so this app's own probe reached its own tap looking exactly
    /// like a key Victor had pressed. Every other poster in this repo carries
    /// `backButtonStamp` for that reason, and `WT_KEY_TRACE` now reads it.
    static func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = HotkeyTap.backButtonStamp
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // **And put the flags back down.** Deliberately only the trailing half:
        // a leading `flagsChanged` would assert ⌘-down in the session for the
        // microseconds between the two, which is the window this is closing.
        guard !flags.isEmpty else { return }
        if let clear = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            clear.type = .flagsChanged
            clear.flags = []
            clear.post(tap: .cghidEventTap)
        }
    }

    static func cmdC() { simulateKeyPress(keyCode: 0x08, flags: .maskCommand) }
}
