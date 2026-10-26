import AppKit

/// **A crash opens its own investigator** (2026-10-26, Victor: *"ridică automat
/// un debug agent după orice crash walkie de acum"*).
///
/// macOS writes `~/Library/Logs/DiagnosticReports/Walkie Talkie-<date>.ips`
/// for every abort of this app, and nobody reads it until Victor says *a dat
/// crash*. So the instance that comes up next looks: a report newer than the
/// last one seen is handed to a fresh Claude Code session in this repo, opened
/// the way a spawn opens (`SpawnTerminal.launchClaude` — tiled, not bound: the
/// binding stays where it was). The brief names the report and the log, and
/// asks for the cause, the fix, a gated restart and a commit.
///
/// The marker is the report's file name (`<home>/crash-seen`), written
/// **before** the session opens, so one report gets one agent whatever the
/// launcher does. Reports older than the marker are ignored; the first run
/// after this feature shipped was seeded with the report it was written for.
/// Skipped under the photo run — a second, unsigned process that must not
/// open terminals — and when the repo is not where it is expected.
enum CrashAgent {

    static var reportsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
    }

    static var marker: URL { Outbox.home.appendingPathComponent("crash-seen") }

    /// The checkout the agent works in — this file's repo on Victor's Mac.
    static var repo: String {
        ProcessInfo.processInfo.environment["WT_REPO"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("workspace/walkie-talkie").path
    }

    static func checkAtLaunch() {
        guard !RelayWindow.shooting else { return }
        DispatchQueue.global(qos: .utility).async { check() }
    }

    static func check() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: reportsDir.path) else { return }
        let seen = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // The date is in the name, so the names sort by time.
        let reports = names.filter { $0.hasPrefix("Walkie Talkie-") && $0.hasSuffix(".ips") }.sorted()
        guard let newest = reports.last, newest > seen else { return }
        try? newest.write(to: marker, atomically: true, encoding: .utf8)
        guard fm.fileExists(atPath: repo + "/relay-restart.sh") else {
            Log.error("💥 crash report \(newest) found, but no checkout at \(repo) to debug it in")
            return
        }
        let path = reportsDir.appendingPathComponent(newest).path
        let fresh = reports.filter { $0 > seen }
        Log.info("💥 \(fresh.count) crash report(s) since the last launch — opening a debug session on \(newest)")
        let prompt = """
        Walkie Talkie crashed. The crash report is at \(path)\(fresh.count > 1 ? " (and \(fresh.count - 1) more since the last launch, same folder)" : ""). \
        Investigate: parse the .ips (the first line is a JSON header, the rest a JSON body — \
        `faultingThread`, its `frames` with `symbol`/`sourceFile`/`sourceLine`, `exception`, `asi`, `lastExceptionBacktrace`), \
        then read ~/.walkie-talkie/relay.log around the report's timestamp (and ~/.walkie-talkie/hangs/ if there is a sample from then). \
        Find the cause, fix it in this repo if it is clear, build and restart through ./relay-restart.sh --build (never by hand), \
        and commit and push. If the cause is not clear, say what you ruled out and what the log shows. \
        Write the findings in Romanian; the app is running again, so do not hurry a restart that the gate refuses.
        """
        switch SpawnTerminal.launchClaude(prompt: prompt, directory: repo) {
        case .opened(let tty): Log.info("💥 debug session open on \(tty)")
        case .failed(let why): Log.error("💥 could not open the debug session — \(why)")
        }
    }
}
