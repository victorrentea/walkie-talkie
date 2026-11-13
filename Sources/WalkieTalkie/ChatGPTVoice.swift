import AppKit
import ApplicationServices

/// **🔽 ← at rest: talk to ChatGPT** (2026-11-13). Victor: *"să-mi deschidă
/// fereastra aceea de ChatGPT undeva pe un sfert de ecran și să intrăm în modul
/// de vorbă, ca să pot să și văd ce vorbește"*, then *"vreau back + swipe left.
/// Că seamănă cu modul question actual, doar că ar fi alternativa ChatGPT. Le
/// voi folosi alternativ"* — 🔼 ← asks Claude a ⚡ question, 🔽 ← opens a voice
/// conversation with ChatGPT. The flick again ends it.
///
/// **How, and why this way.** `/Applications/ChatGPT.app` is the unified
/// ChatGPT/Codex Electron app (`com.openai.codex`, 26.1106). Read from its
/// `app.asar` on 2026-11-13: no URL route, App Intent or AppleScript starts
/// voice; the commands are
///
/// - `composer.startVoiceMode` — *Toggle voice chat*, **⌃⇧V**, scope `app`
///   (the app must be in front): the one command that is a toggle **and**
///   lands in the main window, where the conversation is readable;
/// - `realtimeVoice` — a global hotkey with no default (he would have to set
///   it), and `notchVoice` ⌥V, which talks in the small Mini window.
///
/// So: bring the app forward (`NSWorkspace.openApplication` — it starts it
/// when it is not running, and never by its executable path), fill the pointer's
/// screen with its window (*"să o faci fullscreen"*, the same evening — the
/// quarter he first asked for lasted an hour), press ⌃⇧V.
enum ChatGPTVoice {

    static let bundleID = "com.openai.codex"

    /// What this app believes: its own ⌃⇧V started a conversation and has not
    /// ended it. A call he ends by hand leaves it stale for one flick — that
    /// flick then only skips the window move, the toggle is the app's own.
    private(set) static var talking = false
    private static var busy = false
    private static var last: [String: Any] = [:]

    static var describe: [String: Any] {
        var out = last
        out["talking"] = talking
        out["running"] = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        return out
    }

    /// The whole visible frame of a screen (AppKit coordinates) as an
    /// Accessibility rect — origin top-left of the primary screen, whose
    /// height is `primaryHeight`. *"fullscreen"* is this, not a Space of its
    /// own: no animation to wait out, and the flick can be undone by hand.
    static func fill(_ visible: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
    }

    /// The flick. `say` flashes on the chip (main thread).
    static func toggle(say: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            guard !busy else { Log.info("🗣️ ChatGPT voice — a flick while the last one is still opening, dropped"); return }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                Log.error("🗣️ ChatGPT voice — no app with bundle id \(bundleID)")
                last = ["ok": false, "error": "not installed"]
                say("ChatGPT is not installed")
                return
            }
            busy = true
            let starting = !talking
            let cold = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let target = screen.map { fill($0.visibleFrame, primaryHeight: primaryHeight) }
            Log.info("🗣️ 🔽 ← at rest — ChatGPT voice \(starting ? "on" : "off")\(cold ? " (starting the app)" : "")")
            say(starting ? (cold ? "🗣️ ChatGPT voice — starting the app" : "🗣️ ChatGPT voice") : "🗣️ ChatGPT voice — off")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                DispatchQueue.global().async {
                    defer { DispatchQueue.main.async { busy = false } }
                    guard let app, error == nil else {
                        Log.error("🗣️ ChatGPT voice — the app did not open: \(String(describing: error))")
                        DispatchQueue.main.async { last = ["ok": false, "error": "open"]; say("ChatGPT did not open") }
                        return
                    }
                    // In front, with a window — a cold start takes seconds.
                    let pid = app.processIdentifier
                    let began = CFAbsoluteTimeGetCurrent()
                    var window: AXUIElement?
                    while CFAbsoluteTimeGetCurrent() - began < (cold ? 30 : 4) {
                        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let w = mainWindow(pid) {
                            window = w
                            break
                        }
                        usleep(100_000)
                    }
                    let waited = CFAbsoluteTimeGetCurrent() - began
                    guard let window else {
                        Log.error(String(format: "🗣️ ChatGPT voice — not in front with a window after %.1f s, nothing pressed", waited))
                        DispatchQueue.main.async { last = ["ok": false, "error": "not in front", "waited": waited]; say("ChatGPT did not come forward") }
                        return
                    }
                    // A window just created is not yet a composer that takes keys.
                    if cold { usleep(coldSettle) }
                    if starting, let target { setFrame(window, target) }
                    pressToggle()
                    DispatchQueue.main.async {
                        talking = starting
                        var note: [String: Any] = ["ok": true, "started": starting, "cold": cold, "waited": (waited * 100).rounded() / 100]
                        if starting, let target { note["frame"] = [target.minX, target.minY, target.width, target.height] }
                        last = note
                    }
                    Log.info(String(format: "🗣️ ChatGPT voice — ⌃⇧V pressed %.1f s after the flick%@", CFAbsoluteTimeGetCurrent() - began,
                                    starting && target != nil ? ", window filling the pointer's screen" : ""))
                }
            }
        }
    }

    /// After a cold start's first window: unmeasured, generous.
    static let coldSettle: UInt32 = 2_500_000

    private static func mainWindow(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute as CFString, &raw) == .success, let raw,
               CFGetTypeID(raw) == AXUIElementGetTypeID() {
                return (raw as! AXUIElement)
            }
        }
        return nil
    }

    /// Size, position, size again, with `AXEnhancedUserInterface` off for the
    /// duration — Victor Addons' `AXWindows.setFrame`, where both halves were
    /// paid for (2026-10-05: a resize is clamped to the room below the current
    /// origin; 2026-10-16: a Chromium app with the flag on answers each write
    /// against the frame before the batch). Copied, not imported: this app
    /// does not depend on Victor Addons.
    private static func setFrame(_ window: AXUIElement, _ rect: CGRect) {
        var size = rect.size, origin = rect.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        var enhanced: CFTypeRef?
        let wasEnhanced = pid != 0
            && AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &enhanced) == .success
            && (enhanced as? Bool) == true
        if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// ⌃⇧V, the modifiers as keys of their own (an Electron accelerator reads
    /// the flags, a key listener the keys — both are satisfied), after the
    /// flick's own ⌃⌥⌘ has left the wire, and the wire left bare.
    private static func pressToggle() {
        usleep(HotkeyTap.settleForOptionsPlus)
        let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        var waited = 0
        while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty, waited < 100 {
            usleep(5_000)
            waited += 1
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let control: CGKeyCode = 59, shift: CGKeyCode = 56, v: CGKeyCode = 9
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            if modifier { e.type = .flagsChanged }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        post(control, down: true, flags: [.maskControl], modifier: true)
        post(shift, down: true, flags: [.maskControl, .maskShift], modifier: true)
        post(v, down: true, flags: [.maskControl, .maskShift], modifier: false)
        post(v, down: false, flags: [.maskControl, .maskShift], modifier: false)
        post(shift, down: false, flags: [.maskControl], modifier: true)
        post(control, down: false, flags: [], modifier: true)
    }
}
