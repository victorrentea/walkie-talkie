import Foundation

/// What the overlay calls itself: `ai@master` — the same `folder@branch` Victor
/// reads in Claude Code's status line.
///
/// It used to say "Agent", which is fine until a second overlay exists. With two
/// sessions on screen, "Agent: Listening" on both is worse than no label at all:
/// he cannot tell which repo is about to receive what he says. The status line
/// already answers that question, so the overlay borrows its answer.
///
/// The directory is the overlay's own working directory, inherited from whatever
/// launched it — `/overlay` runs `start.sh` inside the session, so it is the
/// session's directory. `--label` overrides for anything that starts it from
/// somewhere else.
enum SessionLabel {

    /// Written on main, read from the HTTP listener, the outbox and the corpus
    /// writers — hence the lock.
    static var value: String {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
    private static let lock = NSLock()
    private static var stored: String = derive()

    private static var overridden = false

    static func override(_ label: String) {
        value = label
        overridden = true
    }

    /// Re-read the branch periodically: Victor switches branches mid-session, and
    /// an overlay still claiming `@master` while he works on a feature branch is a
    /// label that lies. `changed` runs on main when it did, so the caller can
    /// relayout (the title drives the overlay's width).
    ///
    /// **`git` runs off main** (2026-11-25, found by the Fable review): a 10 s
    /// timer forking `git` on main was a hitch every tick, and a `git` that
    /// stalled froze the app. One read at a time; main only publishes it.
    static func refresh(_ changed: @escaping () -> Void = {}) {
        guard !overridden, !reading else { return }
        reading = true
        DispatchQueue.global(qos: .utility).async {
            let fresh = derive()
            DispatchQueue.main.async {
                reading = false
                guard !overridden, fresh != value else { return }
                value = fresh
                changed()
            }
        }
    }
    /// A read in flight — main thread only.
    private static var reading = false

    private static func derive() -> String {
        let cwd = FileManager.default.currentDirectoryPath
        let folder = (cwd as NSString).lastPathComponent
        guard let branch = gitBranch(cwd) else { return folder }
        return "\(folder)@\(branch)"
    }

    private static func gitBranch(_ cwd: String) -> String? {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        git.standardOutput = pipe
        git.standardError = FileHandle.nullDevice
        do { try git.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return nil }   // not a repo
        let branch = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let branch = branch, !branch.isEmpty, branch != "HEAD" else { return nil }
        return branch                                          // detached HEAD: a sha is noise
    }
}
