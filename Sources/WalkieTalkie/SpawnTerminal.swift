import AppKit
import Foundation

/// **The destination that does not exist yet.** Shift + the wheel opens a fresh
/// Terminal.app window, starts an interactive Claude Code in it, and hands it
/// the dictation as its first prompt.
///
/// It exists because every other destination in this app has to be *pointed at*:
/// ⌘⌃B, the mouse-5 double click and the left-plus-wheel chord all say "that
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

        // **Where it opens is not where Terminal would have put it.** See
        // `elsewhere()`: an external display if there is one, and otherwise
        // behind whatever Victor is looking at.
        let area = elsewhere()
        // Only worth remembering in the second case. In the first, Terminal is
        // being brought forward on purpose, onto a screen he is not working on.
        let previous = area == nil ? NSWorkspace.shared.frontmostApplication : nil

        // Moved rather than sized: the window keeps whatever Terminal gave it and
        // is centred on the target screen, shrunk only if it would not fit — a
        // spawn is not the place to overrule his window settings.
        let place = area.map { a in """
            set w to front window
            set b to bounds of w
            set wd to (item 3 of b) - (item 1 of b)
            set ht to (item 4 of b) - (item 2 of b)
            if wd > \(a.w) then set wd to \(a.w)
            if ht > \(a.h) then set ht to \(a.h)
            set bounds of w to {\(a.x) + ((\(a.w) - wd) div 2), \(a.y) + ((\(a.h) - ht) div 2), \(a.x) + ((\(a.w) - wd) div 2) + wd, \(a.y) + ((\(a.h) - ht) div 2) + ht}
        """ } ?? ""

        // `do script` with no `in` clause opens a **new window**, which is the
        // whole request: a second session beside the one he is in, not a line
        // typed into it. The tab it returns is how the relay finds the tty
        // without going back and guessing which window is in front — and by the
        // time an answer came back from that guess, Victor's hand may well have
        // moved on.
        //
        // **`front window` is Terminal's own front, not the screen's**, so the
        // window just created is it whether or not this app was activated.
        let osa = """
        tell application "Terminal"
            \(area == nil ? "" : "activate")
            set t to do script "\(escape(launcher.path))"
        \(place)
            return tty of t
        end tell
        """
        guard let tty = run("/usr/bin/osascript", ["-e", osa]), tty.hasPrefix("/dev/") else {
            return .failed("Terminal would not open a window for the new session")
        }
        // **Put the front back, if Terminal took it.** Nothing here activates it,
        // but a Terminal that was not running is launched by `do script` and comes
        // forward on its own. The quarter second is that launch settling: restoring
        // into the middle of it is a swap the window server undoes a moment later.
        if let previous = previous {
            Thread.sleep(forTimeInterval: 0.25)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != previous.processIdentifier {
                previous.activate(options: [])
            }
        }
        Log.info("✨ new Claude Code spawned in \(directory) on \((tty as NSString).lastPathComponent)"
                 + (area == nil ? " — behind, no display but the Retina one" : " — on the external display"))
        return .opened(tty: tty)
    }

    /// **The Retina screen is Victor's, and a window nobody asked to look at may
    /// not take it.** Added 2026-09-04 on his ask: *"the terminal should be placed
    /// outside of the Retina screen if there is any other screen connected. If
    /// there's not, place it in the background, not in the foreground."*
    ///
    /// Every spawn used to `activate` and land wherever Terminal felt like, which
    /// in practice is on top of what he is reading — and a spawn is by definition
    /// the one window he did not point at, so it arrives while his eyes are
    /// somewhere else.
    ///
    ///  * With an external display attached, this returns its visible area and
    ///    the window is moved there and raised: it costs him nothing there.
    ///  * With nothing but the built-in display, there is nowhere to move it to,
    ///    so this returns `nil` and the caller opens it **behind** instead. The
    ///    window still exists and the relay still binds it a beat later; what it
    ///    does not do is take the front.
    ///
    /// "Retina" is `backingScaleFactor >= 2` — the same test the
    /// `come-back-when-done` skill uses, and deliberately not a size or a name,
    /// so it holds whatever is plugged in. The roomiest qualifying screen wins,
    /// because with three identical monitors any of them will do and the biggest
    /// is the least surprising default.
    ///
    /// The rectangle comes back in **AppleScript's** coordinates — origin at the
    /// top-left of the primary screen, y growing downwards — since that is the
    /// only place it is used. `NSScreen` speaks Cocoa's, so the y is flipped
    /// against the primary screen's height here rather than at the call site.
    private static func elsewhere() -> (x: Int, y: Int, w: Int, h: Int)? {
        var found: (x: Int, y: Int, w: Int, h: Int)?
        let read = {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }
            // The pivot for the flip is the primary screen — the one at Cocoa
            // origin — wherever it sits in the list.
            let primary = screens.first { $0.frame.origin == .zero } ?? screens[0]
            let pivot = primary.frame.maxY
            guard let target = screens
                .filter({ $0.backingScaleFactor < 2 })
                .max(by: { $0.visibleFrame.width * $0.visibleFrame.height
                         < $1.visibleFrame.width * $1.visibleFrame.height })
            else { return }
            let f = target.visibleFrame
            found = (x: Int(f.minX.rounded()),
                     y: Int((pivot - f.maxY).rounded()),
                     w: Int(f.width.rounded()),
                     h: Int(f.height.rounded()))
        }
        // `launchClaude` runs off the main thread by contract, and `NSScreen` is
        // main-thread state. The hop is a hop, not a deadlock, precisely because
        // of that contract.
        if Thread.isMainThread { read() } else { DispatchQueue.main.sync(execute: read) }
        return found
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
