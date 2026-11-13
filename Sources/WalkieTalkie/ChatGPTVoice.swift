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
                    // **The same conversation goes on** (*"dacă apăs din nou …
                    // continuă în aceeași conversație"*): a start within
                    // `sameConversation` of the last one's end reopens its
                    // thread; later than that, or the first time, a new chat.
                    var resumed: String?
                    DispatchQueue.main.sync {
                        if let t = lastThread, CFAbsoluteTimeGetCurrent() - t.at < sameConversation { resumed = t.id }
                    }
                    if !wasOn, let fresh = URL(string: "codex://threads/\(resumed ?? "new")") {
                        NSWorkspace.shared.open(fresh)
                        usleep(700_000)
                        // The link can take the front away for a beat (one
                        // live run in five lost the key there).
                        var tries = 0
                        while !inFront(pid), tries < 20 { usleep(100_000); tries += 1 }
                        // Only the conversation: both side bars shut.
                        if let target { closeBars(window: target) }
                    }
                    DispatchQueue.main.async { chime(on: !wasOn) }
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
                    DispatchQueue.main.async {
                        if wasOn { followGeneration += 1; lastThread?.at = CFAbsoluteTimeGetCurrent() }
                        else if let resumed { followGeneration += 1; lastThread = (resumed, CFAbsoluteTimeGetCurrent()) }
                        else { followNewThread(known: known) }
                    }
                    let stillInFront = inFront(pid)
                    DispatchQueue.main.async {
                        var note: [String: Any] = ["ok": stillInFront, "cold": cold, "waited": (waited * 100).rounded() / 100, "characterIsOut": characterIsOut, "callWasOn": wasOn, "resumed": resumed ?? "", "bars": lastBars]
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

    // MARK: - Its own radio sound

    /// **A second radio, so the ear knows which one opened** (2026-11-13,
    /// Victor: *"tot ceva ca walkie să sune, dar un alt sunet … tot ca stație
    /// de emisie-recepție. Eventual poți modifica sunetul walkie un pic"*).
    /// Both are `assets/start-squelch.wav` reworked with ffmpeg, the same
    /// −20 dBFS peak and 150 ms of leading silence: **on** = the squelch
    /// 22 % higher, then a rising roger beep (1250 → 1700 Hz); **off** = the
    /// beep falling, then the squelch 15 % lower. Played whatever the
    /// `Radio Squelch` tick says — that one is the dictation's.
    private static let sounds: [Bool: NSSound] = {
        var out: [Bool: NSSound] = [:]
        for (on, name) in [(true, "chat-voice-on.wav"), (false, "chat-voice-off.wav")] {
            var candidates: [URL] = []
            if let res = Bundle.main.resourcePath { candidates.append(URL(fileURLWithPath: res).appendingPathComponent(name)) }
            var dir = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                .standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<4 { candidates.append(dir.appendingPathComponent("assets/\(name)")); dir = dir.deletingLastPathComponent() }
            if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
               let sound = NSSound(contentsOf: url, byReference: false) { out[on] = sound }
        }
        return out
    }()

    static func chime(on: Bool) {
        guard let sound = sounds[on] else { Log.error("🗣️ ChatGPT voice — no chat-voice-\(on ? "on" : "off").wav, silent"); return }
        if sound.isPlaying { sound.stop() }
        sound.play()
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
    /// The conversation the last start talked in, and when it was last on.
    private static var lastThread: (id: String, at: CFAbsoluteTime)?
    /// How long after a conversation the next start still continues it.
    static let sameConversation: CFAbsoluteTime = 30 * 60

    // MARK: - The side bars

    private static var lastBars = ""

    /// **Nothing but the conversation** (*"fără lista de conversații din
    /// stânga, fără niciun panel pe dreapta, doar textul mare"*). The app
    /// keeps neither bar's state anywhere readable and refuses an
    /// Accessibility tree (`AXManualAccessibility` → −25205), so the window
    /// is *looked at*: a strip a quarter of the way down, and three columns
    /// of it. Each bar has a shade of its own (measured dark, 2026-11-13: the
    /// list 30, the conversation's ground 24, the icon rail 41), so 130 pt
    /// in from either edge a shade that is not the middle's is a bar: ⌘⇧S
    /// (`toggleSidebar`) on the left, ⌘⌥B (`toggleSidePanel`) on the right —
    /// the right one never seen open, so that half is a guess.
    private static func closeBars(window: CGRect) {
        usleep(500_000)
        guard let shades = shades(of: window) else { lastBars = "no picture"; return }
        var note = String(format: "rail %.0f left %.0f middle %.0f right %.0f", shades.rail, shades.left, shades.middle, shades.right)
        if abs(shades.left - shades.middle) >= 3 {
            press(1, under: [(55, .maskCommand), (56, .maskShift)])
            note += " — left bar shut"
            usleep(350_000)
        }
        if abs(shades.right - shades.middle) >= 3 {
            press(11, under: [(55, .maskCommand), (58, .maskAlternate)])
            note += " — right panel shut"
            usleep(350_000)
        }
        lastBars = note
        Log.info("🗣️ ChatGPT voice — bars: \(note)")
    }

    /// The median brightness (0…255) of four columns of the window: the icon
    /// rail, where the left bar would be, the middle, where a right panel
    /// would be. `window` in global top-left coordinates.
    private static func shades(of window: CGRect) -> (rail: Double, left: Double, middle: Double, right: Double)? {
        let band = CGRect(x: window.minX, y: window.minY + (window.height * 0.25).rounded(), width: window.width, height: 60)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-voice-bars-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-R", "\(Int(band.minX)),\(Int(band.minY)),\(Int(band.width)),\(Int(band.height))", file.path]
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard let data = try? Data(contentsOf: file), let bitmap = NSBitmapImageRep(data: data) else { return nil }
        let scale = Double(bitmap.pixelsWide) / Double(band.width)
        func column(_ pt: Double) -> Double {
            let x = min(max(Int(pt * scale), 0), bitmap.pixelsWide - 1)
            var values: [Double] = []
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let c = bitmap.colorAt(x: x, y: y) else { continue }
                values.append(Double(c.redComponent + c.greenComponent + c.blueComponent) / 3 * 255)
            }
            values.sort()
            return values.isEmpty ? 0 : values[values.count / 2]
        }
        let middle = column(Double(band.width) * 0.5)
        return (column(20), column(130), middle, column(Double(band.width) - 130))
    }

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
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                    last["thread"] = id
                    lastThread = (id, CFAbsoluteTimeGetCurrent())
                }
                return
            }
        }
    }

    /// **The page zoom, by hand from the desk** (`POST /test/chat-voice-zoom
    /// {"steps": n}`, 2026-11-13: *"mai dai un pic zoom să vină chatboxul de
    /// text cât toată lățimea"*): the app in front, then ⌘= (or ⌘− for a
    /// negative n) that many times. The app keeps its zoom; the flick does
    /// not touch it.
    static func zoom(steps: Int) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            guard let app else { return }
            DispatchQueue.global().async {
                var tries = 0
                while !inFront(app.processIdentifier), tries < 40 { usleep(100_000); tries += 1 }
                usleep(500_000)
                for _ in 0..<abs(steps) {
                    press(steps > 0 ? 24 : 27, under: [(55, .maskCommand)])
                    usleep(250_000)
                }
                Log.info("🗣️ ChatGPT — zoom \(steps > 0 ? "in" : "out") ×\(abs(steps))")
            }
        }
    }

    /// Desk: `POST /test/chat-voice-mini` — ⌥V, the app's global *Voice in
    /// Mini* (`notchVoice`: *Start voice in Mini or show the ongoing call*),
    /// pressed wherever the keyboard is. Nothing else.
    static func pressVoiceInMini() {
        DispatchQueue.global().async { press(9, under: [(58, .maskAlternate)]) }
    }

    // MARK: - Reading the window

    /// Every labelled element of the app's front window — role, label, whether
    /// it can be pressed — for the desk (`POST /test/chat-voice-ax`) and for
    /// `panels`. An Electron app builds its tree only once asked
    /// (`AXManualAccessibility`).
    static var lastTreeNote = ""
    static func windowLabels(limit: Int = 4000) -> [[String: String]] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let manual = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let enhanced = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        defer { lastTreeNote = "manual \(manual.rawValue) enhanced \(enhanced.rawValue)" }
        guard let window = mainWindow(pid) else { return [] }
        var out: [[String: String]] = []
        var queue: [AXUIElement] = [window]
        var seen = 0
        while !queue.isEmpty, seen < limit {
            let e = queue.removeFirst()
            seen += 1
            func text(_ attribute: String) -> String? {
                var raw: CFTypeRef?
                guard AXUIElementCopyAttributeValue(e, attribute as CFString, &raw) == .success else { return nil }
                return (raw as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            let label = text(kAXTitleAttribute) ?? text(kAXDescriptionAttribute) ?? text(kAXValueAttribute)
            if let role = text(kAXRoleAttribute) {
                out.append(["role": role, "label": String((label ?? "").prefix(80))])
            }
            var raw: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &raw) == .success, let children = raw as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return out
    }
}
