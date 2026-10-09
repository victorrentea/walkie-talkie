import AppKit

/// **Every touch of the general pasteboard, one at a time** (2026-10-09).
///
/// The app crashed at 14:24:51 on the main thread, inside AppKit:
///
///     EXC_BAD_ACCESS — objc_retain → -[NSConcreteMapTable keyEnumerator]
///       → -[_NSPasteboardOwnersCollection handleOwnershipChange]
///       → -[NSPasteboard changeCount] → PasteboardTimeline.tick()
///
/// `changeCount` is not the read-only integer it looks like: when another app
/// has taken the board over, it walks and prunes the set of this process's
/// past owners. The 20 Hz `tick` was doing that on main while a drag-release
/// selection probe (`SelectionCapture.readViaClipboardProbe`, on
/// `selectionQueue`) was doing the same through its own ⌘C wait loop — the ⌘C
/// is exactly the ownership change both of them noticed — and one thread freed
/// an entry the other was enumerating. The log's last line was a drag probe
/// 8 s earlier; the next one died before it could log.
///
/// NSPasteboard is not thread-safe, and this app reaches it from main, from
/// `selectionQueue`, from delivery threads and from a global queue. Confining
/// all of that to main would park the main thread on another app's promised
/// data; a lock costs nothing when uncontended and makes the overlap
/// impossible. Recursive, because `PasteboardTimeline.noteOwnWrite` reads the
/// count from inside a write that already holds it.
///
/// **Never hold it across a sleep or a keystroke** — take it per call.
enum Clipboard {
    private static let lock = NSRecursiveLock()

    static func with<T>(_ body: (NSPasteboard) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(NSPasteboard.general)
    }

    static var changeCount: Int { with { $0.changeCount } }

    /// Replace the board with one string — every write this app makes.
    static func write(_ text: String) {
        with { $0.clearContents(); $0.setString(text, forType: .string) }
    }
}
