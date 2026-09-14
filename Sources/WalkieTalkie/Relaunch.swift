import AppKit

/// **Clicking the Dock tile restarts the relay instead of bringing it forward.**
///
/// Victor, 2026-09-14: *"When I open the walkie-talkie again from the sidebar in
/// macOS, it should restart it rather than refocus on it. Instead of quitting and
/// restarting, I should just click on the icon on the left that would restart the
/// application."*
///
/// Which is a gesture the tile did not have before and an activation it never
/// needed: there is nothing to come forward *to*. The overlay is a
/// `.nonactivatingPanel` that is already on screen whatever is frontmost, so the
/// default reopen — make the app active, show its windows — does nothing a person
/// can see, and the only two things the tile was ever used for are ⌥-click →
/// Force Quit and a restart after a build. This makes the second one a click.
///
/// It is the same restart `relay-restart.sh` performs, from inside: a dictation in
/// flight is a **stop** (`AppDelegate` waits for it), and a binding is a thing to
/// **put back** — which is what this file is for. The tty cannot travel in
/// `bound-tty`, because that file is cleared both at quit and at launch; it is
/// parked here instead, and read once by the instance that comes up.
enum Relaunch {

    /// Where the binding waits between the two processes. Beside `.replacing`,
    /// under `--home` with everything else, so a test instance restarts into its
    /// own world rather than stealing the real one's terminal.
    private static var handoffURL: URL { Outbox.home.appendingPathComponent(".rebind") }

    /// Park the tty the dying instance was pointed at. A `.keystroke` target has
    /// no tty and cannot be restored — same as the script, which says so and
    /// restarts anyway.
    static func stashBinding(tty: String?) {
        guard let tty = tty, !tty.isEmpty else {
            try? FileManager.default.removeItem(at: handoffURL)
            return
        }
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        try? Data(tty.utf8).write(to: handoffURL)
    }

    /// The tty to bind back to, taken exactly once.
    ///
    /// Time-boxed like `SingleInstance.beingReplaced`, and for its reason: a
    /// handoff left behind by a relaunch that never happened must not reach
    /// across a day and point tomorrow's relay at a terminal window Victor closed
    /// last night. Removed on read whether it is used or not.
    static func takePendingBinding() -> String? {
        let path = handoffURL.path
        defer { try? FileManager.default.removeItem(at: handoffURL) }
        guard let modified = try? FileManager.default
                .attributesOfItem(atPath: path)[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 60,
              let tty = (try? String(contentsOf: handoffURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !tty.isEmpty
        else { return nil }
        return tty
    }

    /// Start the replacement and let it do the killing.
    ///
    /// **`open -n`, not a `pkill` and a launch** — the same call `main.swift`
    /// makes for a binary started by path, and for the same two reasons. macOS
    /// keys the privacy grants to the bundle identifier only for a process
    /// **LaunchServices** started, and `SingleInstance.enforce()` in the newcomer
    /// already stands this instance down *and* writes the `.replacing` marker, so
    /// the agent watching the outbox is never told the session ended. Killing
    /// ourselves first would only add a window in which no relay is running.
    ///
    /// The arguments travel with it, so a `--home` or `--label` instance restarts
    /// as itself rather than as the real one.
    @discardableResult
    static func start() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else {
            Log.error("↻ restart asked of a binary that is not an installed bundle — ignored")
            return false
        }
        // `-psn_…` was LaunchServices' own argument in an older macOS and is
        // nothing this app parses; handing it back would be handing on noise.
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn") }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // **`-g`, because the relay he gets back must not be in front of him.**
        // A Dock click activates the app on its way to this code — that is the
        // Dock's doing, not the app's — and `open` would hand the front to the
        // replacement as well, leaving a restart ending with Walkie Talkie
        // frontmost over the terminal he was typing in. The overlay is a
        // `.nonactivatingPanel`; it is on screen either way.
        open.arguments = ["-g", "-n", "-a", bundle.path] + (args.isEmpty ? [] : ["--args"] + args)
        do {
            try open.run()
            return true
        } catch {
            Log.error("↻ could not relaunch (\(error)) — the relay is still the one you had")
            return false
        }
    }
}
