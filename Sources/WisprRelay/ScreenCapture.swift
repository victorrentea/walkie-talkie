import AppKit

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
    static func grab(cursor: NSPoint? = nil) -> String? {
        let mouse = cursor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        let display = activeDisplayNumber(of: screen)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let name = "shot-\(stamp.string(from: Date()))\(cursorTag(mouse: mouse, screen: screen)).jpg"
        let file = Outbox.shotsDir.appendingPathComponent(name)

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
        prune()
        return file.path
    }

    /// Where the cursor was, written into the file name as
    /// `-cursor-34.2x71.8pct` — 34.2% across, 71.8% down, **top-left origin**,
    /// like the image itself.
    ///
    /// It rides in the name and not in the outbox JSON because the name is what
    /// the agent already has in front of it: the path is in `paths`, so the
    /// pointer arrives with the picture, and nothing downstream has to learn a
    /// new field to benefit from it. He points at things while he talks ("this
    /// button", "that line") and the sentence alone cannot say which.
    ///
    /// **Percentages, not pixels.** The agent reads the shot through a tool that
    /// downsamples it, so a pixel coordinate stops pointing at the right thing
    /// the moment the picture is resized. A percentage survives any scaling.
    private static func cursorTag(mouse: NSPoint, screen: NSScreen?) -> String {
        guard let frame = screen?.frame, frame.width > 0, frame.height > 0 else { return "" }
        let clamp = { (v: CGFloat) in min(max(v, 0), 100) }
        let x = clamp((mouse.x - frame.minX) / frame.width * 100)
        // AppKit counts y up from the bottom, images count it down from the top.
        let y = clamp((frame.maxY - mouse.y) / frame.height * 100)
        return String(format: "-cursor-%.1fx%.1fpct", x, y)
    }

    /// One screenshot per dictation adds up fast — Victor dictates all day, and
    /// each retina JPG is a megabyte or two. Keep the most recent `keepNewest`
    /// and drop the rest, so the folder can't quietly eat the disk.
    private static let keepNewest = 300

    private static func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Outbox.shotsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let jpgs = files.filter { $0.pathExtension.lowercased() == "jpg" }
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
