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
    static func grab(cursor: NSPoint? = nil) -> String? {
        let mouse = cursor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        let display = activeDisplayNumber(of: screen)
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let spot = cursorFraction(mouse: mouse, screen: screen)
        // Provisional: the pixel reading in the final name is measured against the
        // frame `screencapture` actually produces, which does not exist yet.
        let name = "shot-\(stamp.string(from: Date())).jpg"
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
        if let spot = spot { CursorMarker.draw(at: spot, onJPEGAt: file) }
        let final = tagCursor(spot, on: file)
        prune()
        return final.path
    }

    /// Rename the shot to carry the pointer position **in pixels**:
    /// `shot-<stamp>-cursor-at-1034x1466-of-3024x1890.jpg` — the cursor sat at
    /// x=1034, y=1466 of a 3024×1890 frame, **top-left origin** like the image.
    ///
    /// It rides in the name and not in the outbox JSON because the name is what
    /// the agent already has in front of it: the path is in `paths`, so the
    /// pointer arrives with the picture, and nothing downstream has to learn a
    /// new field to benefit from it. He points at things while he talks ("this
    /// button", "that line") and the sentence alone cannot say which.
    ///
    /// **Pixels, and the frame they are pixels of.** The reading used to be a
    /// percentage pair (`-cursor-34.2x71.8pct`) on the argument that the agent
    /// reads these through a tool that downsamples them, so a bare pixel stops
    /// pointing at the right thing the moment the picture is resized. That
    /// argument is about the *bare* pixel, and naming the frame answers it: the
    /// pair and its denominator scale together, so `1034x1466-of-3024x1890`
    /// survives any resize a percentage would have survived — and it is the form
    /// Victor can actually check against a screen he is looking at, which
    /// `34.2%` never was.
    ///
    /// Measured against the frame `screencapture` really produced rather than
    /// computed from the screen's backing scale: mirrored displays, HiDPI modes
    /// and a sleeping external monitor all make that multiplication a guess, and
    /// a guessed denominator is worse than no denominator at all.
    ///
    /// Renaming rather than naming up front is what buys that: the file has to
    /// exist before it can be measured. On failure the provisional name stands —
    /// a shot with no pointer in its name is still a shot.
    private static func tagCursor(_ spot: CGPoint?, on file: URL) -> URL {
        guard let spot = spot, let size = pixelSize(of: file) else { return file }
        let x = Int((spot.x * size.width).rounded())
        let y = Int((spot.y * size.height).rounded())
        let base = file.deletingPathExtension().lastPathComponent
        let tagged = file.deletingLastPathComponent().appendingPathComponent(
            "\(base)-cursor-at-\(x)x\(y)-of-\(Int(size.width))x\(Int(size.height)).jpg")
        do {
            try FileManager.default.moveItem(at: file, to: tagged)
            return tagged
        } catch {
            Log.error("could not tag the cursor into \(base): \(error)")
            return file
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
