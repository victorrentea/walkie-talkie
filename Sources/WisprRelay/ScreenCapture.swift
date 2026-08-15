import AppKit
import ImageIO

/// Screenshots the display under the cursor into `~/.wispr-relay/shots`.
///
/// The overlay does **not** need hiding: `sharingType = .none` on the panel
/// already excludes it from every capture — verified with a shot taken by a
/// separate process while the overlay was on screen and unhidden. That matters
/// for the automatic capture at dictation start, which fires on every single
/// dictation and must not blink the overlay each time.
///
/// The red vignette is **not** fired here. A frame of the screen leaves the
/// machine on every dictation and every ⌃⌥P, so both deserve the same visible
/// receipt — but the receipt belongs at the *start* of the gesture, not after
/// this subprocess has been waited on. Callers announce first, then grab.
enum ScreenCapture {

    /// `cursor` is where the pointer was **at the moment of the gesture**, in
    /// AppKit screen coordinates. It is passed in rather than read here because
    /// this runs after a clipboard probe that sleeps up to 400ms — by then the
    /// hand has moved on, and the whole point of recording it is to say what he
    /// was pointing at when he pressed.
    ///
    /// `offset` is **where in the dictation** this shot was taken, in seconds
    /// from the moment Victor started talking — `0` for the automatic context
    /// capture, which he took by starting to talk. nil for a shot with no
    /// dictation around it (bare F3), where there is no clock for it to be an
    /// offset into and the name falls back to a timestamp.
    static func grab(cursor: NSPoint? = nil, offset: TimeInterval? = nil) -> String? {
        let mouse = cursor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        let display = activeDisplayNumber(of: screen)
        let spot = cursorFraction(mouse: mouse, screen: screen)
        // Provisional: the pixel reading in the final name is measured against the
        // frame `screencapture` actually produces, which does not exist yet.
        let file = Outbox.shotsDir.appendingPathComponent("shot-\(stem(offset)).jpg")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "jpg", "-D", String(display), file.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("screencapture failed: \(error)")
            return nil
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            Log.error("screencapture produced no file (Screen Recording permission?)")
            return nil
        }
        if let spot = spot { CursorMarker.draw(at: spot, onJPEGAt: file) }
        let final = tagCursor(spot, on: file, offset: offset)
        prune()
        return final.path
    }

    /// **`00:00`, `01:23` — where in the sentence.** A dictation's shots are read
    /// as a set, and what makes one findable among them is not what o'clock it
    /// was but *how far into what he was saying* it was taken: `📸 ×4` is four
    /// indistinguishable files, `0:00 · 0:38 · 1:52` is a table of contents. The
    /// prompt panel already lists them this way (`AppDelegate.shotLine`), and
    /// this is the same reading put where the agent meets it — in the path.
    ///
    /// A shot with no dictation around it keeps a timestamp, because "elapsed
    /// since the start" of nothing is not a fact.
    ///
    /// NB the colon is legal in a POSIX filename on APFS and everything that
    /// handles these paths is POSIX — but **the Finder renders it as `/`**
    /// (`shot-00/00(…)`), the old HFS separator swap, so a folder Victor opens
    /// by hand will read slightly differently from what the agent sees.
    private static func stem(_ offset: TimeInterval?) -> String {
        guard let offset = offset else {
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            return stamp.string(from: Date())
        }
        let seconds = max(0, Int(offset.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Rename the shot to its final form:
    /// `shot-01:23(mouse-at-1034x1466px).jpg` — taken 1m23s into the dictation,
    /// with the pointer at x=1034, y=1466 **in the pixels of this image**,
    /// top-left origin like the image itself.
    ///
    /// It rides in the name and not in the outbox JSON because the name is what
    /// the agent already has in front of it: the path is in `paths`, so both the
    /// moment and the pointer arrive with the picture, and nothing downstream
    /// has to learn a new field to benefit from them. He points at things while
    /// he talks ("this button", "that line") and the sentence alone cannot say
    /// which.
    ///
    /// **Pixels.** The reading was a percentage pair (`-cursor-34.2x71.8pct`)
    /// because the agent reads these through a tool that downsamples them, so a
    /// pixel stops pointing at the right thing once the picture is resized. It
    /// then briefly carried its own denominator (`-of-3024x1890`) to answer
    /// that. Victor dropped the denominator: the name is read by him as often as
    /// by an agent, and a pair of raw pixels is the form he can check against a
    /// screen. The consequence is real and accepted — a downsampled frame needs
    /// its own dimensions read back before these numbers mean anything, which
    /// anything looking at the image already has.
    ///
    /// Measured against the frame `screencapture` really produced rather than
    /// computed from the screen's backing scale: mirrored displays, HiDPI modes
    /// and a sleeping external monitor all make that multiplication a guess.
    /// Renaming rather than naming up front is what buys that — the file has to
    /// exist before it can be measured. On failure the provisional name stands:
    /// a shot with no pointer in its name is still a shot.
    private static func tagCursor(_ spot: CGPoint?, on file: URL, offset: TimeInterval?) -> URL {
        guard let spot = spot, let size = pixelSize(of: file) else { return file }
        let x = Int((spot.x * size.width).rounded())
        let y = Int((spot.y * size.height).rounded())
        let tagged = unique(file.deletingLastPathComponent()
            .appendingPathComponent("shot-\(stem(offset))(mouse-at-\(x)x\(y)px).jpg"))
        do {
            try FileManager.default.moveItem(at: file, to: tagged)
            return tagged
        } catch {
            Log.error("could not name \(tagged.lastPathComponent): \(error)")
            return file
        }
    }

    /// A `-2`, `-3`… before the extension if that name is taken.
    ///
    /// The per-session folder keeps one run's shots away from another's, and the
    /// pointer position makes two shots at the same offset differ in almost every
    /// real case — but "almost" is doing work there: dictate twice without moving
    /// the mouse and both context shots are `shot-00:00(mouse-at-800x900px)`.
    /// Overwriting would destroy a picture an outbox line still points at, which
    /// is the same trap `ScreenshotManager.uniqueURL` exists for in Victor Addons.
    private static func unique(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        for n in 2...99 {
            let candidate = dir.appendingPathComponent("\(stem)-\(n).jpg")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    /// A session folder with nothing left in it says a session happened and
    /// tells you nothing about it. The current one is never touched: it is empty
    /// for the whole time before the first dictation.
    private static func dropEmptySessions() {
        let fm = FileManager.default
        let sessions = (try? fm.contentsOfDirectory(at: Outbox.cacheRoot,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])) ?? []
        for session in sessions where session.lastPathComponent != Outbox.sessionStamp {
            let contents = (try? fm.contentsOfDirectory(at: session,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])) ?? []
            if contents.isEmpty { try? fm.removeItem(at: session) }
        }
    }

    /// The frame's real size in pixels, read from the JPEG header — no decode,
    /// so this costs nothing next to the capture it follows.
    private static func pixelSize(of file: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Where the pointer sat, as a fraction of the frame in **image** coordinates:
    /// 0…1 across, 0…1 down from the top. The same reading feeds the file name and
    /// the marker painted into the picture, so the two can never disagree about
    /// what he was pointing at.
    private static func cursorFraction(mouse: NSPoint, screen: NSScreen?) -> CGPoint? {
        guard let frame = screen?.frame, frame.width > 0, frame.height > 0 else { return nil }
        let clamp = { (v: CGFloat) in min(max(v, 0), 1) }
        // AppKit counts y up from the bottom, images count it down from the top.
        return CGPoint(x: clamp((mouse.x - frame.minX) / frame.width),
                       y: clamp((frame.maxY - mouse.y) / frame.height))
    }

    /// One screenshot per dictation adds up fast — Victor dictates all day, and
    /// each retina JPG is a megabyte or two. Keep the most recent `keepNewest`
    /// and drop the rest, so the folder can't quietly eat the disk.
    ///
    /// Being in Caches means the system may reclaim these anyway; that is a
    /// backstop for a full disk, not a policy, and it fires far too late to be
    /// the only thing bounding a folder that grows all day.
    private static let keepNewest = 300

    /// Counted **across every session folder**, not within the current one.
    /// A relay session can be five minutes long, so a per-folder cap would keep
    /// 300 shots per restart and bound nothing at all. Session folders left empty
    /// by the sweep are removed with their contents — an empty stamp is litter,
    /// and the folders are how yesterday's shots are found until they go.
    private static func prune() {
        let fm = FileManager.default
        let sessions = (try? fm.contentsOfDirectory(at: Outbox.cacheRoot,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])) ?? []
        var jpgs: [URL] = []
        for session in sessions {
            let files = (try? fm.contentsOfDirectory(
                at: session,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            jpgs += files.filter { $0.pathExtension.lowercased() == "jpg" }
        }
        defer { dropEmptySessions() }
        guard jpgs.count > keepNewest else { return }
        let sorted = jpgs.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for stale in sorted.dropFirst(keepNewest) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// 1-indexed display number as `screencapture -D` expects, for the screen
    /// holding the cursor.
    ///
    /// Must be derived from the **active** display list, not the online one:
    /// online includes displays that are asleep or mirrored, so with a sleeping
    /// external monitor the online index overshoots and `screencapture` rejects
    /// it outright ("Invalid display specified. Only 1 display…") — no file, no
    /// screenshot. The count is clamped for the same reason.
    private static func activeDisplayNumber(of screen: NSScreen?) -> Int {
        guard let screen = screen,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return 1 }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }
        guard let index = displays.firstIndex(of: displayID), index < Int(count) else { return 1 }
        return index + 1
    }
}
