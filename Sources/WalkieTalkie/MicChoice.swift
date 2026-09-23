import Foundation

/// **Which microphone Victor picked, in the one place both apps read it.**
///
/// The relay is not the only thing on this Mac that opens a microphone: Victor
/// Addons transcribes the room continuously through the same four devices, and
/// until 2026-09-22 each app kept its own answer — this one in `UserDefaults`
/// under `micDevice`, the other in a `.preferred-me-source` file holding a
/// CoreAudio name fragment. Two menus, the same six rows, and no way to tell
/// from either of them what the other was listening through. Victor's ask is
/// the obvious one: *"când o schimb într-una, să se schimbe automat și în
/// cealaltă"*.
///
/// So the preference is a **file**, and the file is the contract:
///
/// ```
/// ~/.walkie-talkie/mic/choice     # one line: auto | xlr | rx | stage | bose | mac   (tx went 2026-09-23; an old one reads as auto)
/// ```
///
/// ## Why a file and not a port
///
/// Both apps are already running an HTTP server the other one calls, so a route
/// was the obvious alternative and is the wrong shape for this. A route only
/// works while both apps are up: the microphone is picked between sessions as
/// often as during one, and a pick made while the other app is restarting would
/// be silently lost. A file is the state; whoever comes up next reads it. It
/// also keeps the dependency one-directional in the only way that matters —
/// this app writes and reads its own home folder and does not care whether
/// anything else on the Mac has ever heard of it, which is the standing rule
/// that Walkie Talkie must stay usable without `victor-macos-addons` (that repo
/// is private; this one is not).
///
/// ## Why its own subfolder
///
/// `~/.walkie-talkie/` is a busy directory — `relay.log` and `outbox.jsonl` are
/// appended to constantly — and half of noticing a change here is a
/// `DispatchSource` on the **directory** holding the file, because an atomic
/// write replaces the inode and a watch on the old descriptor goes deaf.
/// Watching the busy directory would wake this app on every log line. One quiet
/// subfolder costs nothing and makes the watch exact. (The other half is a watch
/// on the file itself — see `watch`.)
enum MicChoice {

    /// The id meaning *let the ladder decide*, and the answer to anything
    /// unreadable. Never a device id.
    static let automatic = "auto"

    static var folder: URL { Outbox.home.appendingPathComponent("mic") }
    static var url: URL { folder.appendingPathComponent("choice") }

    /// **What is on disk, or `auto`.** Unknown ids read as `auto` rather than
    /// being kept: the two apps' rosters are meant to be the same list, and the
    /// day one of them learns a device the other has not, the older one should
    /// fall back to its ladder rather than tick nothing and record through
    /// whatever CoreAudio last pointed at.
    static func read(known: [String]) -> String {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return automatic }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return known.contains(id) ? id : automatic
    }

    /// Publish a pick. Atomic, so a reader woken by the write never sees a
    /// half-written id.
    static func write(_ id: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try (id + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.error("mic: could not publish the choice '\(id)' — \(error)")
        }
    }

    // MARK: - Watching

    private static var folderSource: DispatchSourceFileSystemObject?
    private static var fileSource: DispatchSourceFileSystemObject?
    private static var handler: (() -> Void)?

    /// **Call `onChange` whenever the other app rewrites the file.**
    ///
    /// **Two watches, because one misses half the ways a file changes.** Both
    /// apps publish with `write(to:atomically:true)`, which writes a temp file
    /// and renames it over the target — that replaces the inode, so a watch on
    /// the *file* descriptor stops firing after the first change and a watch on
    /// the *folder* is what sees it. But a plain in-place write (a shell
    /// `printf > choice`, a test harness, an editor that truncates) touches the
    /// file and never the directory, and the folder watch sleeps through it.
    /// Both cases are real — the second one is how this was found — so the
    /// folder is watched for the replace and the file is watched for the write,
    /// and the file watch is re-armed every time it is replaced out from under
    /// itself.
    ///
    /// The folder is a dedicated one because `~/.walkie-talkie/` itself has
    /// `relay.log` and `outbox.jsonl` being appended to constantly, and watching
    /// it would wake this app on every log line.
    ///
    /// Fires on this app's own writes too. That is deliberate rather than
    /// filtered: the handler's job is *make the menu agree with the file*, and
    /// doing that twice is free.
    static func watch(_ onChange: @escaping () -> Void) {
        stopWatching()
        handler = onChange
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.error("mic: cannot watch \(folder.path) — the other app's picks will not arrive")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler {
            // A replace lands here, and the file watch below is now pointed at
            // a dead inode — re-aim it before answering.
            armFileWatch()
            handler?()
        }
        src.setCancelHandler { close(fd) }
        folderSource = src
        src.resume()

        armFileWatch()
    }

    /// Watch the `choice` file itself, for writes that do not go through a
    /// rename. Re-arms itself when the file is replaced or removed.
    private static func armFileWatch() {
        fileSource?.cancel()
        fileSource = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }   // no file yet; the folder watch will catch its creation
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler {
            let gone = src.data.contains(.delete) || src.data.contains(.rename)
            handler?()
            if gone { armFileWatch() }
        }
        src.setCancelHandler { close(fd) }
        fileSource = src
        src.resume()
    }

    static func stopWatching() {
        folderSource?.cancel(); folderSource = nil
        fileSource?.cancel(); fileSource = nil
        handler = nil
    }
}
