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

    static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    // MARK: - 1. Accessibility

    private static func readViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }
        // CFTypeRef → AXUIElement: the API guarantees this type for the attribute.
        let focusedElement = element as! AXUIElement

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
    static func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func cmdC() { simulateKeyPress(keyCode: 0x08, flags: .maskCommand) }
}
