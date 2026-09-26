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
/// Three seconds: the heartbeat ticks every tenth of a second (half a second
/// until 2026-09-26), so a healthy main thread is never more than ~0.1 s stale, and nothing this app does on the
/// main thread is allowed to take seconds. The cost of opening on a stall
/// that then clears is a Wispr sentence pasted by Wispr *and* delivered by
/// the relay once it thaws — the cost of not opening is the sentence lost.
///
/// **Every time handed in is uptime** (`HotkeyTap.uptime`, `CLOCK_UPTIME_RAW`
/// = `mach_absolute_time`, which does not advance while the Mac sleeps —
/// 2026-09-26). It was `CFAbsoluteTimeGetCurrent`, the wall clock, and a lid
/// closed for three minutes read as a three-minute stall: the `🧊 195 s` of
/// 2026-09-25, and a fail-open on every wake.
struct MainStallGate {
    static let threshold: CFTimeInterval = 3

    enum Change: Equatable { case unchanged, opened, closed(after: CFTimeInterval) }

    private(set) var isOpen = false
    /// The last beat before the stall.
    private var openedAt: CFTimeInterval = 0
    /// The first beat after it — the stall's real end, which the close may
    /// trail by a long way (a button held, or no evaluation for a while).
    private var thawedAt: CFTimeInterval?

    /// `buttonsDown` is asked only while open — it is a window-server read,
    /// and the tap runs this for every scroll event on the Mac.
    ///
    /// `closed(after:)` is **the stall**, first beat after minus last beat
    /// before, not the time the gate stood open: a 6 s stall used to be
    /// reported as `back after 16.4 s` because the close waited for the next
    /// event and measured to it (TR4, 2026-09-26).
    mutating func evaluate(now: CFTimeInterval, lastBeat: CFTimeInterval, buttonsDown: @autoclosure () -> Bool) -> Change {
        let stalled = now - lastBeat > Self.threshold
        if !isOpen, stalled {
            isOpen = true
            openedAt = lastBeat
            thawedAt = nil
            return .opened
        }
        guard isOpen else { return .unchanged }
        if thawedAt == nil, lastBeat > openedAt { thawedAt = lastBeat }
        if !stalled, !buttonsDown() {
            isOpen = false
            return .closed(after: (thawedAt ?? lastBeat) - openedAt)
        }
        return .unchanged
    }
}
