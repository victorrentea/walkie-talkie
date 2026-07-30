import AppKit

/// Screenshots the display under the cursor into `~/.claude-bubble/shots`.
///
/// The bubble does **not** need hiding: `sharingType = .none` on the panel
/// already excludes it from every capture — verified with a shot taken by a
/// separate process while the bubble was on screen and unhidden. That matters
/// for the automatic capture at dictation start, which fires on every single
/// dictation and must not blink the overlay each time.
///
/// The red vignette is **not** fired here. A frame of the screen leaves the
/// machine on every dictation and every ⌃⌥P, so both deserve the same visible
/// receipt — but the receipt belongs at the *start* of the gesture, not after
/// this subprocess has been waited on. Callers announce first, then grab.
enum ScreenCapture {

    static func grab() -> String? {
        let display = activeDisplayNumber()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let file = Outbox.shotsDir.appendingPathComponent("shot-\(stamp.string(from: Date())).jpg")

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
    private static func activeDisplayNumber() -> Int {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
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
