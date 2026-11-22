import Foundation

/// **A quit that arrives mid-sentence waits for the sentence** (2026-09-23).
///
/// Victor: *"Whenever you restart it, make sure it's not currently dictating or
/// transcribing … Implement whatever it takes for this not to lose ongoing
/// dictation or transcription."* Several agents rebuild and restart this app
/// during the day; `relay-restart.sh` is the gate they go through, and this is the
/// same rule enforced from inside, for every quit the script does not own — ⌘Q, a
/// `pkill` (SIGTERM is routed through `NSApp.terminate`), a newer instance's
/// `SingleInstance.enforce()`, a logout.
///
/// **`.terminateCancel` and a retry, never `.terminateLater`.** `terminateLater`
/// runs the main run loop in the modal-panel mode until the reply, and every
/// default-mode `Timer` in this app — the settle's, the row poll's — would stop
/// firing: the very sentence being waited for could never finish. So the quit is
/// refused, the app goes on exactly as before, and `AppDelegate` asks again every
/// half second until `restartBlockers` is empty.
///
/// While it waits it keeps a marker fresh on disk, so a newcomer's
/// `SingleInstance.enforce()` extends its two-second patience instead of
/// force-killing the sentence it was about to cut off.
enum QuitGate {

    /// Longest a quit may be put off. A sentence is at most a couple of minutes
    /// (81 s is the longest measured) and a sentence held for a bind five; a flag
    /// left standing with nothing behind it must not make the app unquittable.
    /// Force Quit (SIGKILL) always works regardless.
    static let ceiling: TimeInterval = 600

    /// **Asked twice, it goes** (2026-11-22). At 13:56 that day a Quit was put
    /// off behind two sentences whose microphone had never opened — nothing
    /// could land, the ceiling was ten minutes away, a second Quit and a SIGTERM
    /// changed nothing and the app had to be SIGKILLed. A second ask this long
    /// after the first is him insisting, and no sentence outranks that.
    static let insistAfter: TimeInterval = 1

    /// **Once a quit is let through, the process is gone within this** — whatever
    /// `applicationWillTerminate` or an atexit handler is waiting on (a device
    /// teardown is IPC to `coreaudiod` and can hang). See `armHardExit`.
    static let hardExit: TimeInterval = 2

    enum Verdict: Equatable {
        /// Leave now; the string is the log's reason (empty = nothing was in the way).
        case go(String)
        case wait
    }

    /// The one decision behind ⌘Q, the menu's Quit, SIGTERM and the half-second
    /// retry. `waited` is nil for a quit not yet deferred; `askedAgain` is true
    /// when this call is a new ask (not the retry's poll).
    static func verdict(blockers: [String], waited: TimeInterval?, askedAgain: Bool) -> Verdict {
        if blockers.isEmpty { return .go("") }
        guard let waited else { return .wait }
        if waited >= ceiling { return .go("deferred \(Int(waited)) s and still \(blockers.joined(separator: ", "))") }
        if askedAgain, waited >= insistAfter {
            return .go("asked again \(Int(waited)) s into the wait — \(blockers.joined(separator: ", ")) is given up")
        }
        return .wait
    }

    private static var hardExitArmed = false
    /// Arms the deadline, once: a thread that is not the main one ends the
    /// process `hardExit` seconds from now if it is still here. `_exit`, not
    /// `exit` — no atexit handler may be what it waits on.
    static func armHardExit() {
        guard !hardExitArmed, ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        hardExitArmed = true
        let t = Thread {
            Thread.sleep(forTimeInterval: hardExit)
            Log.error("quit: still here \(Int(hardExit)) s after the quit was let through — leaving without the rest of the teardown")
            _exit(0)
        }
        t.qualityOfService = .userInitiated
        t.start()
    }

    /// The shoot run fabricates states — `listening` included — and then quits;
    /// deferring that quit would hang `docs/shoot-overlay-states.sh`.
    /// `WT_QUIT_NOW=1` is the same switch for any other run that must go at once.
    static var disabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["RELAY_SHOOT"] != nil || env["WT_QUIT_NOW"] == "1"
    }

    private static var markerURL: URL { Outbox.home.appendingPathComponent(".quit-deferred") }

    /// Touched every poll while a quit is being put off.
    static func touchMarker() {
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        try? Data().write(to: markerURL)
    }

    static func clearMarker() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// True while an instance is putting a quit off — the marker is refreshed
    /// every half second, so one older than five is a process that has gone.
    static func someoneIsDeferring() -> Bool {
        guard let modified = try? FileManager.default
                .attributesOfItem(atPath: markerURL.path)[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < 5
    }
}
