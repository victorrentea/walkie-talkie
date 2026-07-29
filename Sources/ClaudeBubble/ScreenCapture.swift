import AppKit

/// Screenshots the display under the cursor into `~/.claude-bubble/shots`.
///
/// The bubble hides itself for the duration of the grab: `screencapture` is a
/// separate process taking a fresh frame of the display, so the only reliable
/// way to keep the overlay out of the picture is to not be on screen when the
/// shutter fires (`sharingType = .none` is also set on the panel as a second
/// line of defence).
enum ScreenCapture {

    static var willCapture: (() -> Void)?
    static var didCapture: (() -> Void)?

    static func grab() -> String? {
        DispatchQueue.main.sync { willCapture?() }
        // Let the compositor land the hide before the shutter.
        Thread.sleep(forTimeInterval: 0.12)
        defer {
            DispatchQueue.main.async { didCapture?() }
        }

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
        // Confirm it visually — the shutter is silent (`-x`) and the shot may be
        // held back for a dictation, so without this there is no sign anything
        // happened.
        DispatchQueue.main.async {
            if let screen = CaptureFlash.screenUnderCursor() {
                CaptureFlash.flash(on: screen)
            }
        }
        return file.path
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
