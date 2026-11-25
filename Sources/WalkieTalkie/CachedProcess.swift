import AppKit
import Foundation

/// **Which pid a LaunchServices question answered last, kept** (2026-11-25, the
/// Fable review of slice 04, finding 1).
///
/// `NSWorkspace.runningApplications`, `runningApplications(withBundleIdentifier:)`
/// and even `-[NSRunningApplication processIdentifier]` go to `launchservicesd`
/// synchronously, and when it is slow the caller waits: 243 of 432 hang captures
/// had the Scratchpad's 0.5 s orphan sweep on the main thread inside
/// `_LSCopyApplicationInformation` (2367 of 2367 ms in one), three more had
/// `wisprMainPid` for the whole sample. The answer changes only when a process
/// starts or ends, so it is asked once and then re-checked against the kernel
/// (`ProcessClock`, a `sysctl`, no LaunchServices):
///
/// - **a pid** stands while that pid is alive with the start time it had when it
///   was found — a Wispr killed and relaunched in 200 ms by the harness is a dead
///   pid or a different start time, and is asked again at once;
/// - **no pid** stands until an application launches or `negativeTTL` passes;
/// - **any application launching or terminating** (`NSWorkspace` notifications)
///   makes the next read ask again.
final class CachedProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let scan: () -> pid_t
    private var state: CachedProcessState
    /// Start time when the pid is alive, nil when it is gone or a zombie.
    private let liveStart: (pid_t) -> Date?

    init(negativeTTL: TimeInterval = 2,
         liveStart: @escaping (pid_t) -> Date? = CachedProcess.kernelLiveStart,
         scan: @escaping () -> pid_t) {
        self.scan = scan
        self.liveStart = liveStart
        state = CachedProcessState(negativeTTL: negativeTTL)
        CachedProcess.observeLaunches()
    }

    var pid: pid_t {
        let now = ProcessInfo.processInfo.systemUptime
        let generation = CachedProcess.generation
        lock.lock()
        let held = state.answer(now: now, generation: generation, liveStart: liveStart)
        lock.unlock()
        if let held { return held }
        // Asked outside the lock: a slow LaunchServices must not hold up a
        // reader that a fresh answer could already serve.
        let found = scan()
        let start = found > 0 ? liveStart(found) : nil
        lock.lock()
        state.record(pid: start == nil ? 0 : found, start: start, now: now, generation: generation)
        lock.unlock()
        return start == nil ? 0 : found
    }

    static func kernelLiveStart(_ pid: pid_t) -> Date? {
        ProcessClock.isAlive(pid) ? ProcessClock.startTime(pid) : nil
    }

    // MARK: - Launch / terminate, for every cache

    private static let genLock = NSLock()
    private static var _generation = 0
    private static var observing = false
    static var generation: Int {
        genLock.lock(); defer { genLock.unlock() }
        return _generation
    }
    static func invalidateAll() {
        genLock.lock(); _generation &+= 1; genLock.unlock()
    }

    private static func observeLaunches() {
        genLock.lock()
        let first = !observing
        observing = true
        genLock.unlock()
        guard first else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            // No queue: the bump is a counter under a lock, any thread will do.
            center.addObserver(forName: name, object: nil, queue: nil) { _ in invalidateAll() }
        }
    }
}

/// The pure half of `CachedProcess` — when a kept answer still stands.
struct CachedProcessState {
    let negativeTTL: TimeInterval
    private(set) var pid: pid_t = 0
    private(set) var start: Date?
    private(set) var askedAt: TimeInterval?
    private(set) var generation = 0

    init(negativeTTL: TimeInterval) { self.negativeTTL = negativeTTL }

    /// The kept pid (0 = not running), or nil when LaunchServices must be asked.
    func answer(now: TimeInterval, generation: Int, liveStart: (pid_t) -> Date?) -> pid_t? {
        guard let askedAt, generation == self.generation else { return nil }
        if pid > 0 {
            guard let start, let live = liveStart(pid), live == start else { return nil }
            return pid
        }
        return now - askedAt < negativeTTL ? 0 : nil
    }

    mutating func record(pid: pid_t, start: Date?, now: TimeInterval, generation: Int) {
        self.pid = pid
        self.start = start
        askedAt = now
        self.generation = generation
    }
}
