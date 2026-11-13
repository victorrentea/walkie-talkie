import AppKit
import ApplicationServices
import CoreAudio

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

    /// **No memory of on or off** (2026-11-13, the first live run): a belief
    /// kept here was wrong after one lost key — the app said *off* over a
    /// conversation that was listening. ⌃⇧V is the app's own toggle; every
    /// flick does the same three things and the window says which it was.
    private static var busy = false
    private static var last: [String: Any] = [:]

    static var describe: [String: Any] {
        var out = last
        out["callIsOn"] = callIsOn()
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
            let cold = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let target = screen.map { fill($0.visibleFrame, primaryHeight: primaryHeight) }
            Log.info("🗣️ ChatGPT voice toggle\(cold ? " (starting the app)" : "")")
            say(cold ? "🗣️ ChatGPT voice — starting the app" : "🗣️ ChatGPT voice")
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
                    var steady = 0
                    while CFAbsoluteTimeGetCurrent() - began < (cold ? 30 : 4) {
                        // In front for 0.4 s on end: pressed 0.2 s after the
                        // flick, the first live ⌃⇧V reached nobody
                        // (2026-11-13) — an activation is not yet a focused
                        // composer.
                        if inFront(pid), let w = mainWindow(pid) {
                            steady += 1
                            if steady >= 4 { window = w; break }
                        } else {
                            steady = 0
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
                    if let target { setFrame(window, target) }
                    let known = Set(voiceThreads())
                    // A fresh chat in the window, not whatever thread was
                    // open — unless a conversation is on (its controls hang
                    // on the character): then the flick only ends it.
                    let wasOn = callIsOn()
                    if !wasOn, let fresh = URL(string: "codex://threads/new") {
                        NSWorkspace.shared.open(fresh)
                        usleep(700_000)
                        // The link can take the front away for a beat (one
                        // live run in five lost the key there).
                        var tries = 0
                        while !inFront(pid), tries < 20 { usleep(100_000); tries += 1 }
                    }
                    pressToggle()
                    // **The microphone is the proof.** A start that left the
                    // app without it 4 s later reached nobody: once more.
                    if !wasOn {
                        var held = false
                        for _ in 0..<40 where !held { usleep(100_000); held = callIsOn() }
                        if !held, inFront(pid) {
                            Log.info("🗣️ ChatGPT voice — no microphone 4 s after ⌃⇧V, pressed once more")
                            pressToggle()
                        }
                    }
                    DispatchQueue.main.async { if wasOn { followGeneration += 1 } else { followNewThread(known: known) } }
                    let stillInFront = inFront(pid)
                    DispatchQueue.main.async {
                        var note: [String: Any] = ["ok": stillInFront, "cold": cold, "waited": (waited * 100).rounded() / 100, "characterIsOut": characterIsOut, "callWasOn": wasOn]
                        if let target { note["frame"] = [target.minX, target.minY, target.width, target.height] }
                        if !stillInFront { note["error"] = "lost the front before the key" }
                        last = note
                    }
                    Log.info(String(format: "🗣️ ChatGPT voice — ⌃⇧V pressed %.1f s after the flick, window filling the pointer's screen%@",
                                    CFAbsoluteTimeGetCurrent() - began, stillInFront ? "" : " — but the app was no longer in front"))
                }
            }
        }
    }

    /// After a cold start's first window: unmeasured, generous.
    static let coldSettle: UInt32 = 2_500_000

    /// Either witness will do: the system-wide `kAXFocusedApplication` never
    /// named ChatGPT in the second live run (4.1 s in front on the screen,
    /// *not in front* here), `NSWorkspace` did in the first.
    private static func inFront(_ pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid || focusedPid() == pid
    }

    /// The application holding the keyboard, as Accessibility sees it now.
    private static func focusedPid() -> pid_t {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return 0 }
        var pid: pid_t = 0
        AXUIElementGetPid(raw as! AXUIElement, &pid)
        return pid
    }

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

    /// A chord, the modifiers as keys of their own (an Electron accelerator
    /// reads the flags, a key listener the keys — both are satisfied), after
    /// the flick's own ⌃⌥⌘ has left the wire, and the wire left bare.
    private static func press(_ key: CGKeyCode, under modifiers: [(key: CGKeyCode, flag: CGEventFlags)]) {
        usleep(HotkeyTap.settleForOptionsPlus)
        let watched: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        var waited = 0
        while !CGEventSource.flagsState(.combinedSessionState).intersection(watched).isEmpty, waited < 100 {
            usleep(5_000)
            waited += 1
        }
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            if modifier { e.type = .flagsChanged }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        var held: CGEventFlags = []
        for m in modifiers { held.insert(m.flag); post(m.key, down: true, flags: held, modifier: true) }
        post(key, down: true, flags: held, modifier: false)
        post(key, down: false, flags: held, modifier: false)
        for m in modifiers.reversed() { held.remove(m.flag); post(m.key, down: false, flags: held, modifier: true) }
    }

    /// ⌃⇧V — `composer.startVoiceMode`, *Toggle voice chat*.
    private static func pressToggle() {
        press(9, under: [(59, .maskControl), (56, .maskShift)])
    }

    // MARK: - The little character, and the new chat

    private static var codexHome: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex") }

    /// **The little character is put away first** (2026-11-13, Victor: *"can
    /// you stop the little character? and instead show the window with the
    /// new chat? full screen"*). It is the app's *Mini* (`openAvatarOverlay`,
    /// *Toggle Mini*, global ⌥Space); while it is out, a conversation started
    /// with ⌃⇧V hangs its controls on the character and the window stays on
    /// *What should we build?*. The app says whether it is out in
    /// `.codex-global-state.json` (`electron-avatar-overlay-open`).
    static var characterIsOut: Bool {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent(".codex-global-state.json")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return state["electron-avatar-overlay-open"] as? Bool ?? false
    }

    /// **Not put away yet**: pressing ⌥Space from here left it standing in
    /// the live run (2026-11-13, twice) — rebound, or taken by another app
    /// before it reaches this one. Open.

    /// **A conversation is on = the app holds the microphone.** Core Audio's
    /// process objects (macOS 14.2+) say which process records; the app's
    /// audio runs in a helper, so the match is on the bundle id's prefix.
    /// The window list could not tell (the Mini's window is 1138×2137 with
    /// or without a call — measured 2026-11-13).
    static func callIsOn() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return false }
        for object in objects {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard withUnsafeMutablePointer(to: &bundle, {
                AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, $0)
            }) == noErr else { continue }
            if (bundle as String).hasPrefix(bundleID) { return true }
        }
        return false
    }

    /// The conversations the app has spoken in, oldest first — the keys of
    /// `realtime-voice-continuity.json`, which it writes as words arrive.
    static func voiceThreads(in file: URL? = nil) -> [String] {
        let file = file ?? codexHome.appendingPathComponent("realtime-voice-continuity.json")
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let threads = json["threads"] as? [String: Any] else { return [] }
        // In the file's own order: a dictionary loses it.
        return threads.keys.sorted { (text.range(of: "\"\($0)\"")?.lowerBound ?? text.endIndex) < (text.range(of: "\"\($1)\"")?.lowerBound ?? text.endIndex) }
    }

    private static var followGeneration = 0

    /// **The new chat is opened in the window** (*"aș vrea să auto-deschidă
    /// chatul nou"*): the app starts a voice conversation in a thread of its
    /// own and leaves the window where it was. The thread's id appears in the
    /// continuity file with the first words; `codex://threads/<id>` shows it
    /// (proven by hand the same evening). Watched for 2 min; the next flick
    /// calls the watch off.
    private static func followNewThread(known: Set<String>) {
        followGeneration += 1
        let mine = followGeneration
        DispatchQueue.global().async {
            let began = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - began < 120 {
                usleep(500_000)
                var current = 0
                DispatchQueue.main.sync { current = followGeneration }
                guard current == mine else { return }
                guard let id = voiceThreads().last(where: { !known.contains($0) }),
                      let url = URL(string: "codex://threads/\(id)") else { continue }
                Log.info(String(format: "🗣️ ChatGPT voice — the new chat %@ opened in the window, %.1f s after the key", id, CFAbsoluteTimeGetCurrent() - began))
                DispatchQueue.main.async { NSWorkspace.shared.open(url); last["thread"] = id }
                return
            }
        }
    }
}
