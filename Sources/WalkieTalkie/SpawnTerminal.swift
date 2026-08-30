import Foundation

/// **The destination that does not exist yet.** Shift + the wheel opens a fresh
/// Terminal.app window, starts an interactive Claude Code in it, and hands it
/// the dictation as its first prompt.
///
/// It exists because every other destination in this app has to be *pointed at*:
/// ⌘⌃D, the mouse-5 double click and the left-plus-wheel chord all say "that
/// terminal, the one already on screen". The one thing they cannot express is
/// the most common way a session actually begins — Victor has a thought, and
/// there is no window for it yet. Making him open a terminal, `cd` somewhere,
/// type `claude`, wait for it to come up and *then* start talking is four steps
/// in front of the sentence he already has in his head.
///
/// **The prompt travels as an argument, not as typing.** `claude "<prompt>"`
/// starts the interactive session with that prompt already submitted, which
/// removes the entire class of bug this app has been bitten by twice: there is
/// no window to wait for, no caret to land in, no shell prompt to be executed
/// at, and no race between "the process is up" and "the process is ready to
/// read". The words are in the process's `argv` before it has drawn anything.
///
/// **Two files on disk, and that is deliberate too.** The prompt is a
/// transcript of Victor speaking freely — quotes, apostrophes, semicolons,
/// backticks, `$` — and it would otherwise have to survive a trip through
/// AppleScript's string literals *and* a shell command line, which is two
/// escapings stacked and the exact place a dictation turns into a command. So
/// AppleScript is only ever handed a path this app generated, and the shell only
/// ever reads the words from a file.
enum SpawnTerminal {

    /// Scratch space for the two files above — beside the shots, and in Caches
    /// for the same reason they are: it is a staging area, not an archive, and
    /// what any of it is *for* is over within the turn that reads it. The
    /// outbox already keeps the durable copy of every word here.
    static let dir = Outbox.cacheRoot.deletingLastPathComponent()
        .appendingPathComponent("spawn")

    /// What opening one did — the same shape `TerminalBinding.Outcome` has, and
    /// for the same reason: the caller's only job with a failure is to say it out
    /// loud, since the outbox already has the words.
    enum Outcome {
        case opened(tty: String)
        case failed(String)
    }

    /// Open the window, and say which tty it landed on so the relay can point
    /// itself at the session it just created.
    ///
    /// Runs subprocesses — call it off the main thread.
    static func launchClaude(prompt: String, directory: String) -> Outcome {
        let stamp = "\(Int(Date().timeIntervalSince1970))-\(UInt32.random(in: 0..<0xFFFF))"
        let promptFile = dir.appendingPathComponent("prompt-\(stamp).txt")
        let launcher = dir.appendingPathComponent("start-\(stamp).sh")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try prompt.write(to: promptFile, atomically: true, encoding: .utf8)
            try script(prompt: promptFile.path, directory: directory)
                .write(to: launcher, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
        } catch {
            return .failed("could not stage the new session — \(error.localizedDescription)")
        }

        // `do script` with no `in` clause opens a **new window**, which is the
        // whole request: a second session beside the one he is in, not a line
        // typed into it. The tab it returns is how the relay finds the tty
        // without going back and guessing which window is in front — and by the
        // time an answer came back from that guess, Victor's hand may well have
        // moved on.
        let osa = """
        tell application "Terminal"
            activate
            set t to do script "\(escape(launcher.path))"
            return tty of t
        end tell
        """
        guard let tty = run("/usr/bin/osascript", ["-e", osa]), tty.hasPrefix("/dev/") else {
            return .failed("Terminal would not open a window for the new session")
        }
        Log.info("✨ new Claude Code spawned in \(directory) on \((tty as NSString).lastPathComponent)")
        return .opened(tty: tty)
    }

    /// **A login shell is what runs this, so `claude` is normally on the PATH
    /// already** — Terminal starts `zsh -l`, `.zshrc` is read, and this script
    /// is its child. The three directories are prepended anyway because the one
    /// failure mode here is silent and expensive: a window that opens, prints
    /// `command not found` and leaves the sentence nowhere. `~/.local/bin` is
    /// where the Claude Code installer puts it on this machine.
    ///
    /// **The prompt file is removed by the script that reads it**, not by this
    /// app: nothing else knows when it has been read, and a sweeper that ran on
    /// a timer would be racing the shell. The launcher itself stays — zsh reads
    /// a script incrementally, and deleting it out from under `exec` is a class
    /// of flake not worth the few hundred bytes it saves.
    private static func script(prompt: String, directory: String) -> String {
        """
        #!/bin/zsh
        # Written by Walkie Talkie — shift + wheel, a dictation with no destination yet.
        PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd \(quote(directory)) 2>/dev/null || cd "$HOME"
        prompt="$(cat \(quote(prompt)))"
        rm -f \(quote(prompt))
        if ! command -v claude >/dev/null; then
          echo "walkie: claude is not on the PATH — the dictation is in the outbox"
          echo "$prompt"
          exec /bin/zsh -l
        fi
        exec claude "$prompt"
        """
    }

    /// Single quotes, with the one character they cannot carry spelled out —
    /// everything else inside them is literal, which is exactly what a path
    /// containing a space, a `$` or a backtick needs.
    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            Log.error("\(path) would not run: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
