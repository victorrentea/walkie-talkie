import AppKit

/// There is never more than one bubble on screen.
///
/// Two bubbles would be actively harmful, not just untidy: both would tap the
/// same shortcuts, both would poll Wispr and forward the *same* dictation, and
/// they would relay into different sessions' outboxes — so Victor could not tell
/// which Claude was listening. The newest launch always wins, because it is the
/// one whose session is actually watching.
///
/// Enforced in the app itself rather than only in `install.sh`, so starting it
/// by any route (skill, Spotlight, a second Claude session) still collapses to
/// one instance.
enum SingleInstance {

    /// Terminates every other running copy and waits for them to go, so the new
    /// instance never races the old one for the event tap.
    static func enforce() {
        let mypid = ProcessInfo.processInfo.processIdentifier
        let myExecutable = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let myBundleId = Bundle.main.bundleIdentifier

        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != mypid else { return false }
            if let myBundleId = myBundleId, app.bundleIdentifier == myBundleId { return true }
            // Also match by executable path: a copy started straight out of
            // .build/release has no bundle identifier to compare.
            if let mine = myExecutable,
               let theirs = app.executableURL?.resolvingSymlinksInPath(),
               mine == theirs { return true }
            return false
        }

        guard !others.isEmpty else { return }
        Log.info("single-instance: terminating \(others.count) older bubble(s)")

        markReplacement()
        for app in others { app.terminate() }

        // Give them a moment to exit cleanly, then insist.
        //
        // Spin the run loop rather than sleeping: `isTerminated` is KVO-updated
        // on the main run loop, so blocking it would leave the flag permanently
        // stale and send every shutdown down the force-kill path even when the
        // old instance had already quit politely.
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        for app in others where !app.isTerminated {
            Log.info("single-instance: force-killing pid \(app.processIdentifier)")
            app.forceTerminate()
        }
    }

    // MARK: - Replacement marker
    //
    // The dying instance cannot tell "the user quit me" from "a newer bubble
    // asked me to go" — both arrive as the same Quit event. So the newcomer says
    // so out loud, in a file, just before knocking: a `session_end` emitted
    // during a restart would tell the watching agent to stop listening exactly
    // when Victor wanted a fresh session.

    private static var markerURL: URL {
        Outbox.home.appendingPathComponent(".replacing")
    }

    private static func markReplacement() {
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        try? Data().write(to: markerURL)
    }

    /// True if a replacement was announced in the last few seconds. Time-boxed on
    /// purpose: a stale marker left behind by a crash must not silence a real
    /// close days later.
    static func beingReplaced() -> Bool {
        guard let modified = try? FileManager.default
                .attributesOfItem(atPath: markerURL.path)[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < 10
    }
}
