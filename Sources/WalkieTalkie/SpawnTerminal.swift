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
        // `board()` and `slot(for:on:avoiding:)`: tiled across the displays
        // around the Retina one, and otherwise opened behind.
        let screens = board()
        let previous = screens.isEmpty ? NSWorkspace.shared.frontmostApplication : nil

        // `do script` with no `in` clause opens a **new window**, which is the
        // whole request: a second session beside the one he is in, not a line
        // typed into it. The tab it returns is how the relay finds the tty
        // without going back and guessing which window is in front — and by the
        // time an answer came back from that guess, Victor's hand may well have
        // moved on.
        //
        // **It also reports every window Terminal has**, in one round trip, since
        // the slot is chosen by *what is already there* and a second `osascript`
        // to ask would be a second launch of the interpreter for a list the first
        // one was already holding. `front window` is Terminal's own front, not
        // the screen's, so it names the window just created whether or not this
        // app was activated.
        let osa = """
        tell application "Terminal"
            \(screens.isEmpty ? "" : "activate")
            set t to do script "\(escape(launcher.path))"
            set out to (tty of t) & linefeed & (id of front window as string)
            repeat with x in windows
                try
                    if visible of x then
                        set b to bounds of x
                        set out to out & linefeed & (id of x as string) & " " & (item 1 of b as string) & " " & (item 2 of b as string) & " " & (item 3 of b as string) & " " & (item 4 of b as string)
                    end if
                end try
            end repeat
            return out
        end tell
        """
        guard let reply = run("/usr/bin/osascript", ["-e", osa]) else {
            return .failed("Terminal would not open a window for the new session")
        }
        let lines = reply.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let tty = lines.first, tty.hasPrefix("/dev/"), lines.count >= 2,
              let mine = Int(lines[1]) else {
            return .failed("Terminal would not open a window for the new session")
        }

        var windows: [(id: Int, box: Box)] = []
        for line in lines.dropFirst(2) {
            let n = line.split(separator: " ").compactMap { Int($0) }
            guard n.count == 5 else { continue }
            windows.append((id: n[0], box: Box(x: n[1], y: n[2], w: n[3] - n[1], h: n[4] - n[2])))
        }

        var placed = "behind, no display but the Retina one"
        if !screens.isEmpty, let window = windows.first(where: { $0.id == mine }) {
            let taken = windows.filter { $0.id != mine }.map { $0.box }
            let target = slot(for: window.box, on: screens, avoiding: taken)
            _ = run("/usr/bin/osascript", ["-e", """
            tell application "Terminal" to set bounds of (first window whose id is \(mine)) \
                to {\(target.x), \(target.y), \(target.x + target.w), \(target.y + target.h)}
            """])
            placed = "tiled at \(target.x),\(target.y) \(target.w)×\(target.h)"
        }

        // **Put the front back, if Terminal took it.** Nothing above activates it
        // in this branch, but a Terminal that was not running is launched by
        // `do script` and comes forward on its own. The quarter second is that
        // launch settling: restoring into the middle of it is a swap the window
        // server undoes a moment later.
        if let previous = previous {
            Thread.sleep(forTimeInterval: 0.25)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != previous.processIdentifier {
                previous.activate(options: [])
            }
        }
        Log.info("✨ new Claude Code spawned in \(directory) on \((tty as NSString).lastPathComponent) — \(placed)")
        return .opened(tty: tty)
    }

    /// A rectangle in **AppleScript's** coordinates: origin at the top-left of
    /// the primary screen, y growing downwards. Everything below speaks these,
    /// because the only thing any of it is for is `set bounds of window`.
    private struct Box {
        var x: Int, y: Int, w: Int, h: Int
        var right: Int { x + w }
        var bottom: Int { y + h }
    }

    /// **The displays a spawned window is allowed to land on, left to right.**
    /// Added 2026-09-04 on Victor's ask: *"the terminal should be placed outside
    /// of the Retina screen if there is any other screen connected"*, and then
    /// *"tile them somehow so that they don't overlap with others… use all the
    /// monitors you have around"*.
    ///
    /// A spawn is by definition the one window he never pointed at: it appears on
    /// its own while his eyes are elsewhere. It used to `activate` and land
    /// wherever Terminal felt like, which in practice is on top of what he is
    /// reading on the built-in display.
    ///
    /// "Retina" is `backingScaleFactor >= 2` — the same test the
    /// `come-back-when-done` skill uses, and deliberately neither a size nor a
    /// name, so it holds whatever is plugged in. An empty result means there is
    /// nowhere to move a window to, and the caller opens it **behind** instead:
    /// the window still exists and `adoptSpawnedWindow` still binds it, since
    /// delivery is `do script … in <tab>` and never needs a window in front.
    ///
    /// `visibleFrame`, not `frame`, so a menu bar or a Dock on a display is not
    /// tiled over.
    private static func board() -> [Box] {
        var found: [Box] = []
        let read = {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }
            // The pivot for the y flip is the primary screen — the one at Cocoa
            // origin — wherever it sits in the list.
            let primary = screens.first { $0.frame.origin == .zero } ?? screens[0]
            let pivot = primary.frame.maxY
            found = screens
                .filter { $0.backingScaleFactor < 2 }
                .map { screen -> Box in
                    let f = screen.visibleFrame
                    return Box(x: Int(f.minX.rounded()),
                               y: Int((pivot - f.maxY).rounded()),
                               w: Int(f.width.rounded()),
                               h: Int(f.height.rounded()))
                }
                .sorted { $0.x < $1.x }
        }
        // `launchClaude` runs off the main thread by contract, and `NSScreen` is
        // main-thread state. The hop is a hop, not a deadlock, precisely because
        // of that contract.
        if Thread.isMainThread { read() } else { DispatchQueue.main.sync(execute: read) }
        return found
    }

    /// **Where this window goes so that it covers as little as possible of what
    /// is already open.**
    ///
    /// Each display is cut into a grid of cells the size of the window itself —
    /// two columns of a 905pt terminal on a 1920pt monitor — and the grid is
    /// centred in whatever the cells did not use, so a single-column screen does
    /// not park the window against its left edge. Every cell on every display is
    /// then scored by how many square points of *other* Terminal windows it would
    /// sit on, and the first cell with the lowest score wins.
    ///
    /// **Scored rather than filtered**, so it degrades instead of failing: with
    /// every slot taken — six terminals across three monitors — the answer is the
    /// least-covered one rather than no answer at all, and the windows stack in
    /// the same order they were opened rather than piling on the first cell.
    /// Reading left to right across the displays is what makes a second spawn
    /// land beside the first instead of on it.
    ///
    /// Only Terminal's own windows are avoided. They are what this is laying out,
    /// they are what the question was about, and they are the only rectangles the
    /// same `osascript` was already holding — asking the window server about every
    /// app's windows would price a browser off these monitors on displays that are
    /// there to hold browsers.
    private static func slot(for window: Box, on screens: [Box], avoiding taken: [Box]) -> Box {
        var best: (cover: Int, box: Box)?
        for screen in screens {
            let w = min(window.w, screen.w), h = min(window.h, screen.h)
            guard w > 0, h > 0 else { continue }
            let cols = max(1, screen.w / w), rows = max(1, screen.h / h)
            let padX = (screen.w - cols * w) / 2, padY = (screen.h - rows * h) / 2
            for row in 0..<rows {
                for col in 0..<cols {
                    let cell = Box(x: screen.x + padX + col * w, y: screen.y + padY + row * h, w: w, h: h)
                    let cover = taken.reduce(0) { $0 + overlap(cell, $1) }
                    // Strictly less, so ties go to the earlier cell and the order
                    // of the grid is the order windows fill it in.
                    if best == nil || cover < best!.cover { best = (cover, cell) }
                    // Nothing beats an empty cell; stop looking for a better one.
                    if cover == 0 { return cell }
                }
            }
        }
        return best?.box ?? window
    }

    /// Square points two rectangles share, or zero.
    private static func overlap(_ a: Box, _ b: Box) -> Int {
        let w = min(a.right, b.right) - max(a.x, b.x)
        let h = min(a.bottom, b.bottom) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h : 0
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
