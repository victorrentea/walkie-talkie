import Foundation

/// **When the event tap stops having opinions** — the pure half of
/// `HotkeyTap.failingOpen`, apart so `swift test` can hold it to its rules.
///
/// Opens the moment the main thread's last beat is older than `threshold`.
/// Closes only once the beat is fresh again **and no mouse button is down**:
/// a press handed through while open must have its release handed through
/// too, or the OS is left holding a button (the seven-hour stuck middle
/// button in `.claude/rules/area-crop.md`).
///
/// Three seconds: the heartbeat ticks every half second, so a healthy main
/// thread is never more than ~0.5 s stale, and nothing this app does on the
/// main thread is allowed to take seconds. The cost of opening on a stall
/// that then clears is a Wispr sentence pasted by Wispr *and* delivered by
/// the relay once it thaws — the cost of not opening is the sentence lost.
struct MainStallGate {
    static let threshold: CFTimeInterval = 3

    enum Change: Equatable { case unchanged, opened, closed(after: CFTimeInterval) }

    private(set) var isOpen = false
    private var openedAt: CFAbsoluteTime = 0

    /// `buttonsDown` is asked only while open — it is a window-server read,
    /// and the tap runs this for every scroll event on the Mac.
    mutating func evaluate(now: CFAbsoluteTime, lastBeat: CFAbsoluteTime, buttonsDown: @autoclosure () -> Bool) -> Change {
        let stalled = now - lastBeat > Self.threshold
        if !isOpen, stalled {
            isOpen = true
            openedAt = lastBeat
            return .opened
        }
        if isOpen, !stalled, !buttonsDown() {
            isOpen = false
            return .closed(after: now - openedAt)
        }
        return .unchanged
    }
}
