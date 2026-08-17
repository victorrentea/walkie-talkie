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
    static func read() -> String? {
        if let ax = readViaAccessibility(), !ax.isEmpty { return ax }
        return readViaClipboardProbe()
    }

    /// Accessibility only — **no ⌘C is injected**, and nothing is waited on.
    ///
    /// This is what the shutter uses. `read()` fires once per dictation, at the
    /// moment Victor starts talking, and paying a synthetic ⌘C plus up to 400ms
    /// of polling for it is a bargain there. A shot is different: he takes
    /// several across one sentence, at moments he chooses, into whatever app is
    /// under his hand — and a keystroke posted into that app on every press is
    /// a side effect the gesture never promised. The failure mode is also the
    /// right one: no AX selection reads as "he did not highlight anything new",
    /// which is true far more often than not.
    static func readQuiet() -> String? {
        guard let ax = readViaAccessibility(), !ax.isEmpty else { return nil }
        return ax
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
