import AppKit
import AVFoundation
import ServiceManagement
import WebKit

/// **Which macOS permissions the app holds, read without asking for any**
/// (2026-11-22, Victor: *"un semn de exclamare dacă n-ai toate permisiunile date …
/// să-ți arate frumos, într-o pagină, de ce permisiuni mai ai nevoie de dat și de
/// ce ai nevoie de ele"*).
///
/// Three readers: the menu's last row before Quit (`StatusItem`, at every menu
/// open), `PermissionsPage` (while it is open) and one log line at launch.
/// **Nothing here may raise a system dialog** — every check is the preflight
/// form (`AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`,
/// `AVCaptureDevice.authorizationStatus`, `AEDeterminePermissionToAutomateTarget`
/// with `askUserIfNeeded: false`, `TCCAccessPreflight`). The asking stays where
/// it was: `AppDelegate.requestGrantsAtLaunch` and the first use.
///
/// `catalogue` is the single table: the README's, the page's and the tests'.
enum Permissions {

    enum Kind: String, CaseIterable {
        case accessibility
        case microphone
        case screenRecording = "screen-recording"
        case automationTerminal = "automation-terminal"
        case systemAudio = "system-audio"
        case camera
        case loginItem = "login-item"
    }

    enum State: String {
        case granted
        /// Refused, or switched off in System Settings.
        case missing
        /// macOS has not asked yet — it will at the first use.
        case notAsked = "not-asked"
        /// Cannot be told right now (Terminal is not running, an API is absent).
        case unknown

        /// What the ❗ counts: everything that is known not to be granted.
        var lacking: Bool { self == .missing || self == .notAsked }
    }

    struct Entry {
        let kind: Kind
        /// The pane's name as System Settings writes it.
        let title: String
        let required: Bool
        /// One plain sentence: what the app does with it.
        let why: String
        /// What is off without it.
        let without: String
        /// `x-apple.systempreferences:` deep link to the pane.
        let settings: String
        /// Where the switch is, in words.
        let path: String
        /// Shown instead of `path` while macOS has not asked yet.
        let notAskedHint: String?
    }

    private static let privacy = "x-apple.systempreferences:com.apple.preference.security?"

    static let catalogue: [Entry] = [
        Entry(kind: .accessibility, title: "Accessibility", required: true,
              why: "Hears the mouse-button gestures and keyboard shortcuts in every app, types the finished sentence at the caret, and reads the text you selected.",
              without: "No gesture or shortcut reaches the app, so no dictation can start.",
              settings: privacy + "Privacy_Accessibility",
              path: "Privacy & Security ▸ Accessibility ▸ switch Walkie Talkie on",
              notAskedHint: nil),
        Entry(kind: .microphone, title: "Microphone", required: true,
              why: "Records your voice while you dictate, so it can be transcribed.",
              without: "Nothing is recorded — every dictation comes out empty.",
              settings: privacy + "Privacy_Microphone",
              path: "Privacy & Security ▸ Microphone ▸ switch Walkie Talkie on, then Quit & Reopen when macOS offers it",
              notAskedHint: "macOS asks at the first dictation — click Allow."),
        Entry(kind: .screenRecording, title: "Screen & System Audio Recording", required: true,
              why: "Takes the screenshots, area crops and short screen recordings you attach to a prompt.",
              without: "Pictures come out black or show only the wallpaper. Dictation still works.",
              settings: privacy + "Privacy_ScreenCapture",
              path: "Privacy & Security ▸ Screen & System Audio Recording ▸ switch Walkie Talkie on (macOS offers Quit & Reopen — Later works too)",
              notAskedHint: nil),
        Entry(kind: .automationTerminal, title: "Automation ▸ Terminal", required: true,
              why: "Sends your prompt into the Terminal tab you bound, opens new agent sessions, and reads the tabs' names.",
              without: "Binding a Terminal tab fails. Prompts can still be typed at the caret.",
              settings: privacy + "Privacy_Automation",
              path: "Privacy & Security ▸ Automation ▸ Walkie Talkie ▸ switch Terminal on",
              notAskedHint: "macOS asks the first time you bind a Terminal tab (⌘⌃B) — click Allow."),
        Entry(kind: .systemAudio, title: "System Audio Recording Only", required: false,
              why: "Silences the Codex app's own chime for a second when a voice chat starts or ends. Nothing is recorded or kept.",
              without: "You hear the chime.",
              settings: privacy + "Privacy_ScreenCapture",
              path: "Privacy & Security ▸ Screen & System Audio Recording ▸ System Audio Recording Only ▸ switch Walkie Talkie on",
              notAskedHint: "macOS asks the first time a voice chat is started from Walkie Talkie."),
        Entry(kind: .camera, title: "Camera", required: false,
              why: "With 🙂 Read my face on, reads two frames a second while a prompt records, to tag a smile, tiredness or that you looked away. No picture is kept.",
              without: "Prompts go without the face tag.",
              settings: privacy + "Privacy_Camera",
              path: "Privacy & Security ▸ Camera ▸ switch Walkie Talkie on",
              notAskedHint: "macOS asks at the first prompt recorded with 🙂 Read my face on."),
        Entry(kind: .loginItem, title: "Open at Login", required: false,
              why: "Starts Walkie Talkie when you log in.",
              without: "You start it by hand after every login.",
              settings: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
              path: "General ▸ Login Items & Extensions ▸ Open at Login",
              notAskedHint: nil),
    ]

    static func entry(_ kind: Kind) -> Entry { catalogue.first { $0.kind == kind }! }

    struct Reading: Equatable {
        let kind: Kind
        let state: State
        /// Set by `POST /test/permissions`, not read from macOS.
        var faked = false
    }

    // MARK: - Pure

    /// How many required permissions are known not to be granted.
    static func missingRequired(_ readings: [Reading]) -> Int {
        readings.filter { entry($0.kind).required && $0.state.lacking }.count
    }

    /// The row above Quit: today's `Built …` with everything granted.
    static func rowTitle(missing: Int, build: String) -> String {
        switch missing {
        case ..<1: return "Built \(build)"
        case 1: return "❗ 1 permission missing"
        default: return "❗ \(missing) permissions missing"
        }
    }

    /// `AEDeterminePermissionToAutomateTarget`'s status, read.
    static func automationState(status: Int) -> State {
        switch status {
        case 0: return .granted
        case -1743: return .missing      // errAEEventNotPermitted
        case -1744: return .notAsked     // errAEEventWouldRequireUserConsent
        default: return .unknown         // -600 procNotFound: the target is not running
        }
    }

    /// `TCCAccessPreflight`'s answer, read.
    static func tccState(preflight: Int32) -> State {
        switch preflight {
        case 0: return .granted
        case 1: return .missing
        case 2: return .notAsked
        default: return .unknown
        }
    }

    /// `{"accessibility": "missing", …}` → the fakes; unknown names and states are returned as errors.
    static func parseFakes(_ raw: [String: Any]) -> (fakes: [Kind: State], errors: [String]) {
        var fakes: [Kind: State] = [:]
        var errors: [String] = []
        for (name, value) in raw {
            guard let kind = Kind(rawValue: name) else { errors.append("unknown permission '\(name)'"); continue }
            guard let s = value as? String, let state = State(rawValue: s) else {
                errors.append("'\(name)': expected granted｜missing｜not-asked｜unknown"); continue
            }
            fakes[kind] = state
        }
        return (fakes, errors.sorted())
    }

    /// The real readings with the fakes laid over them.
    static func overlay(_ real: [Reading], fakes: [Kind: State]) -> [Reading] {
        real.map { r in fakes[r.kind].map { Reading(kind: r.kind, state: $0, faked: true) } ?? r }
    }

    // MARK: - Reading macOS

    private static let lock = NSLock()
    private static var fakes: [Kind: State] = [:]
    /// The last definite answer about Terminal: the check needs Terminal running
    /// and may wait on the AppleEvent manager, so it runs off main (`refreshAutomation`).
    private static var automation: State = .unknown

    static var faked: [Kind: State] {
        get { lock.lock(); defer { lock.unlock() }; return fakes }
        set { lock.lock(); fakes = newValue; lock.unlock() }
    }

    /// Every permission's state, fakes included. Cheap and prompt-free: no
    /// subprocess, no AppleEvent — Automation is the cached answer.
    /// `requiredOnly` skips the optional ones (the menu row needs only the count).
    static func readings(requiredOnly: Bool = false) -> [Reading] {
        let real = catalogue.filter { !requiredOnly || $0.required }
            .map { Reading(kind: $0.kind, state: read($0.kind)) }
        return overlay(real, fakes: faked)
    }

    private static func read(_ kind: Kind) -> State {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .missing
        case .microphone:
            return capture(.audio)
        case .camera:
            return capture(.video)
        case .screenRecording:
            // `CGPreflightScreenCaptureAccess` (and TCC's own preflight) keep the
            // answer they gave first until the app restarts — measured in the lab
            // guest. A child process is asked afresh: `probeScreenRecording`.
            if CGPreflightScreenCaptureAccess() { return .granted }
            lock.lock(); defer { lock.unlock() }
            return screenProbe?.granted == true ? .granted : .missing
        case .automationTerminal:
            lock.lock(); defer { lock.unlock() }
            return automation
        case .systemAudio:
            guard let preflight = tccPreflight else { return .unknown }
            return tccState(preflight: preflight("kTCCServiceAudioCapture" as CFString, nil))
        case .loginItem:
            guard #available(macOS 13, *), Bundle.main.bundleURL.pathExtension == "app" else { return .unknown }
            return SMAppService.mainApp.status == .enabled ? .granted : .missing
        }
    }

    private static func capture(_ media: AVMediaType) -> State {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .missing
        }
    }

    /// System Audio Recording has no public preflight; TCC's own is read-only
    /// and absent-safe (`unknown` when the symbol is not there).
    private static let tccPreflight: (@convention(c) (CFString, CFDictionary?) -> Int32)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (CFString, CFDictionary?) -> Int32).self)
    }()

    // MARK: Screen Recording, granted while running

    static let screenProbeFlag = "--preflight-screen-recording"
    private static var screenProbe: (granted: Bool, at: Date)?

    /// **Ask a child whether the screen may be recorded** — this same binary with
    /// `screenProbeFlag` (`main.swift`). A child is this app to TCC (as `osascript`
    /// and `screencapture` are) but starts with no cached answer, so it sees a
    /// grant given while the app runs. Only when the in-process answer is *no*;
    /// the answer is kept `maxAge` seconds. Blocks ≤ 2 s — never on main in a loop.
    @discardableResult
    static func probeScreenRecording(maxAge: TimeInterval = 5) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        lock.lock()
        let cached = screenProbe
        lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < maxAge { return cached.granted }
        var granted = false
        if let path = Bundle.main.executablePath {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = [screenProbeFlag]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let done = DispatchSemaphore(value: 0)
                p.terminationHandler = { _ in done.signal() }
                if done.wait(timeout: .now() + 2) == .timedOut { p.terminate() }
                let said = String(decoding: out.fileHandleForReading.availableData, as: UTF8.self)
                granted = said.hasPrefix("granted")
            }
        }
        lock.lock()
        let changed = screenProbe?.granted != granted
        screenProbe = (granted, Date())
        lock.unlock()
        if changed { Log.info("🔐 screen recording, asked of a child: \(granted ? "granted" : "missing")") }
        return granted
    }

    private static let queue = DispatchQueue(label: "walkie.permissions", qos: .utility)
    private static var refreshing = false

    /// Ask the AppleEvent manager whether Terminal may be scripted — never
    /// prompting — and call `changed` on main when the answer differs from the
    /// cached one. With Terminal not running the last answer stands.
    static func refreshAutomation(changed: (() -> Void)? = nil) {
        lock.lock()
        if refreshing { lock.unlock(); return }
        refreshing = true
        lock.unlock()
        queue.async {
            let now = automationNow()
            let screenBefore = read(.screenRecording)
            probeScreenRecording()
            lock.lock()
            refreshing = false
            var differs = now != .unknown && now != automation
            if differs { automation = now }
            lock.unlock()
            if read(.screenRecording) != screenBefore { differs = true }
            if differs, let changed { DispatchQueue.main.async(execute: changed) }
        }
    }

    /// `POST /test/permissions` waits for a fresh answer.
    static func refreshAutomationNow() {
        let now = automationNow()
        probeScreenRecording(maxAge: 0)
        lock.lock()
        if now != .unknown { automation = now }
        lock.unlock()
    }

    private static func automationNow() -> State {
        let target = "com.apple.Terminal"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: target).first != nil else { return .unknown }
        var address = AEAddressDesc()
        let made = target.utf8CString.withUnsafeBufferPointer {
            AECreateDesc(typeApplicationBundleID, $0.baseAddress, $0.count - 1, &address)
        }
        guard made == noErr else { return .unknown }
        defer { AEDisposeDesc(&address) }
        let status = AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, false)
        return automationState(status: Int(status))
    }

    // MARK: - Guards: a feature that finds its permission missing

    /// The state macOS reports — **never a fake**: a guard must not switch a
    /// feature off because a test route said so.
    static func real(_ kind: Kind) -> State { read(kind) }

    /// Refused or switched off (not merely *not asked yet* — then macOS is about to ask).
    static func denied(_ kind: Kind) -> Bool { read(kind) == .missing }

    /// What the chip says when a feature finds its permission missing.
    static func hintText(_ kind: Kind) -> String {
        "❗ \(entry(kind).title) permission missing — the menu's ❗ row says why"
    }

    /// The one line at launch for everything refused.
    static func launchHint(_ titles: [String]) -> String {
        "❗ Missing permission\(titles.count == 1 ? "" : "s"): \(titles.joined(separator: ", ")) — the menu's ❗ row says why"
    }

    /// Wired by `AppDelegate`: flash the hint. Called on main.
    static var onHint: ((Kind) -> Void)?
    private static var hintedAt: [Kind: Date] = [:]

    /// Whether a hint for `kind` is due: at most one per `every` seconds (pure but for the clock).
    static func hintDue(last: Date?, now: Date, every: TimeInterval) -> Bool {
        last.map { now.timeIntervalSince($0) >= every } ?? true
    }

    /// A feature found `kind` missing: say so, at most once per `every` seconds
    /// (a gesture the hand repeats: 3 s; something polled: 5 min). Any thread.
    static func hint(_ kind: Kind, every: TimeInterval = 300) {
        lock.lock()
        let due = hintDue(last: hintedAt[kind], now: Date(), every: every)
        if due { hintedAt[kind] = Date() }
        lock.unlock()
        guard due else { return }
        Log.error("🔐 \(kind.rawValue) is not granted — the feature that needed it is off")
        DispatchQueue.main.async { onHint?(kind) }
    }

    /// `osascript` answered -1743: Terminal's Automation switch is off.
    static func automationRefused() {
        lock.lock(); automation = .missing; lock.unlock()
        hint(.automationTerminal)
    }

    /// One line at launch; also warms the Automation answer for the first menu open.
    static func logAtLaunch() {
        refreshAutomation()
        let line = readings().map { "\($0.kind.rawValue)=\($0.state.rawValue)" }.joined(separator: " ")
        Log.info("permissions: \(line) (automation is read in the background)")
    }

    /// For the loopback route.
    static func describe() -> [String: Any] {
        let all = readings()
        let fakes = faked
        let real = Dictionary(uniqueKeysWithValues: catalogue.map { ($0.kind, read($0.kind)) })
        let missing = missingRequired(all)
        return ["permissions": all.map { r -> [String: Any] in
                    let e = entry(r.kind)
                    return ["id": r.kind.rawValue, "title": e.title, "required": e.required,
                            "state": r.state.rawValue, "real": real[r.kind]!.rawValue,
                            "faked": fakes[r.kind] != nil, "settings": e.settings]
                },
                "missingRequired": missing,
                "row": rowTitle(missing: missing, build: StatusItem.buildStamp),
                "page": PermissionsPage.describe()]
    }
}

/// **The Permissions page** — what is granted, what is not, and why each is
/// asked for. The house window (`GestureGuide`): a native, non-activating panel
/// holding a `WKWebView`, nothing fetched. Re-read every 2 s **only while it is
/// visible**, and repainted only when a state changed.
enum PermissionsPage {

    private static var panel: NSPanel?
    private static var web: WKWebView?
    private static let loader = Loader()
    private static var loaded = false
    private static var timer: Timer?
    private static var shown: [Permissions.Reading] = []

    /// Up, or brought forward, without activating the app.
    static func show() {
        Permissions.refreshAutomation { refresh() }
        if let p = panel {
            refresh(force: true)
            p.orderFrontRegardless()
            startTimer()
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(760, screen.width - 80), height: min(820, screen.height - 60))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .closable, .resizable, .miniaturizable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Walkie Talkie — Permissions"
        p.isFloatingPanel = false
        p.level = .normal
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.minSize = NSSize(width: 480, height: 360)

        let w = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: WKWebViewConfiguration())
        w.autoresizingMask = [.width, .height]
        w.navigationDelegate = loader
        w.setValue(false, forKey: "drawsBackground")
        p.contentView = w
        panel = p
        web = w
        refresh(force: true)
        p.center()
        p.orderFrontRegardless()
        startTimer()
        Log.info("→ permissions page \(Int(p.frame.width))×\(Int(p.frame.height))")
    }

    static func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    /// The timer lives only while the panel is visible — a closed page costs nothing.
    private static func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { _ in
            guard panel?.isVisible == true else {
                timer?.invalidate()
                timer = nil
                return
            }
            Permissions.refreshAutomation { refresh() }
            refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Repaint when a state changed (or `force`); the fakes count as a change.
    static func refresh(force: Bool = false) {
        guard let w = web, force || panel?.isVisible == true else { return }
        let now = Permissions.readings()
        guard force || now != shown else { return }
        shown = now
        loaded = false
        w.loadHTMLString(html(now, build: StatusItem.buildStamp), baseURL: nil)
    }

    static func describe() -> [String: Any] {
        guard let p = panel else { return ["shown": false] }
        return ["shown": p.isVisible, "loaded": loaded, "polling": timer != nil,
                "frame": ["x": p.frame.minX, "y": p.frame.minY, "w": p.frame.width, "h": p.frame.height]]
    }

    /// `Open Settings` leaves for System Settings; the page itself never navigates.
    private final class Loader: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            PermissionsPage.loaded = true
        }
    }

    // MARK: - The page (pure)

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// An optional one that is not granted is a fact, not an alarm: grey, no red.
    private static func badge(_ state: Permissions.State, required: Bool) -> String {
        if !required, state.lacking {
            return "<span class=\"badge dim\">– \(state == .notAsked ? "Not asked yet" : "Not granted")</span>"
        }
        switch state {
        case .granted: return "<span class=\"badge ok\">✓ Granted</span>"
        case .missing: return "<span class=\"badge no\">✗ Missing</span>"
        case .notAsked: return "<span class=\"badge ask\">✗ Not asked yet</span>"
        case .unknown: return "<span class=\"badge dim\">– Cannot tell now</span>"
        }
    }

    private static func row(_ r: Permissions.Reading) -> String {
        let e = Permissions.entry(r.kind)
        var more = ""
        if r.state.lacking {
            let hint = r.state == .notAsked ? (e.notAskedHint ?? e.path) : e.path
            more = """
            <p class="without"><b>Without it:</b> \(esc(e.without))</p>
            <div class="fix"><a class="button" href="\(esc(e.settings))">Open Settings</a><span class="path">\(esc(hint))</span></div>
            """
        } else if r.state == .unknown, r.kind == .automationTerminal {
            more = "<p class=\"without\">Terminal is not running, so macOS cannot say. Open Terminal and this row updates.</p>"
        }
        return """
        <div class="row \(e.required ? r.state.rawValue : "optional")" id="\(r.kind.rawValue)">
          <div class="head"><h3>\(esc(e.title))</h3>\(badge(r.state, required: e.required))</div>
          <p class="why">\(esc(e.why))</p>\(more)
        </div>
        """
    }

    static func html(_ readings: [Permissions.Reading], build: String) -> String {
        let missing = Permissions.missingRequired(readings)
        let summary: String
        switch missing {
        case 0: summary = "<p class=\"summary good\">✓ Every required permission is granted.</p>"
        case 1: summary = "<p class=\"summary bad\">❗ 1 required permission is missing — what depends on it is off until you grant it.</p>"
        default: summary = "<p class=\"summary bad\">❗ \(missing) required permissions are missing — what depends on them is off until you grant them.</p>"
        }
        func group(_ title: String, _ required: Bool) -> String {
            let rows = readings.filter { Permissions.entry($0.kind).required == required }.map(row).joined()
            return rows.isEmpty ? "" : "<h2>\(title)</h2>\(rows)"
        }
        let simulated = readings.contains { $0.faked } ? " · <b>simulated states</b> (test route)" : ""
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>Permissions</title><style>\(css)</style></head><body>
        <h1>Permissions</h1>
        <p class="lede">What Walkie Talkie asks macOS for, and what it does with each. macOS grants them in System Settings; this page only reads them.</p>
        \(summary)
        \(group("Required", true))
        \(group("Optional", false))
        <footer>Refreshes by itself while open\(simulated) · built \(esc(build))</footer>
        </body></html>
        """
    }

    private static let css = #"""
    :root { --bg:#f6f5f2; --card:#ffffff; --ink:#1d1d1f; --mute:#6e6e73; --line:#e3e1dc; --red:#d92d20;
            --green:#1a8f3c; --amber:#b25e00; --accent:#0a6cdb; color-scheme: light dark; }
    @media (prefers-color-scheme: dark) {
      :root { --bg:#1c1c1e; --card:#2a2a2d; --ink:#f2f2f4; --mute:#a1a1a6; --line:#3a3a3d; --red:#ff6b5e;
              --green:#4cd471; --amber:#ffb340; --accent:#5aa9ff; }
    }
    * { box-sizing:border-box; }
    html, body { margin:0; background:var(--bg); color:var(--ink);
                 font:14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
    body { padding:26px 30px 30px; }
    h1 { font-size:26px; margin:0 0 6px; letter-spacing:-0.02em; }
    h2 { font-size:12px; margin:22px 0 8px; color:var(--mute); text-transform:uppercase; letter-spacing:0.06em; }
    h3 { font-size:15px; margin:0; }
    p { margin:0; }
    .lede { color:var(--mute); margin-bottom:14px; }
    .summary { border-radius:10px; padding:10px 14px; font-weight:600; border:1px solid var(--line); background:var(--card); }
    .summary.bad { border-color:var(--red); color:var(--red); }
    .summary.good { color:var(--green); }
    .row { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px 16px; margin-bottom:10px; }
    .row.missing, .row.not-asked { border-color:var(--red); }
    .head { display:flex; align-items:baseline; justify-content:space-between; gap:12px; margin-bottom:3px; }
    .badge { font-weight:600; font-size:13px; white-space:nowrap; }
    .ok { color:var(--green); } .no { color:var(--red); } .ask { color:var(--amber); } .dim { color:var(--mute); }
    .why { color:var(--mute); }
    .without { margin-top:6px; }
    .fix { display:flex; align-items:center; gap:12px; margin-top:10px; }
    .button { flex:none; background:var(--accent); color:#fff; text-decoration:none; font-weight:600; font-size:13px;
              padding:5px 12px; border-radius:7px; }
    .path { color:var(--mute); font-size:12.5px; }
    footer { margin-top:20px; padding-top:12px; border-top:1px solid var(--line); color:var(--mute); font-size:12.5px; }
    """#

    // MARK: - A picture, with no window on any screen

    private static var shoots: [Shoot] = []

    private final class Shoot: NSObject, WKNavigationDelegate {
        let web: WKWebView
        let window: NSWindow
        let path: String
        let done: (Bool) -> Void
        init(html: String, width: CGFloat, dark: Bool, path: String, done: @escaping (Bool) -> Void) {
            let frame = NSRect(x: -Offstage.shift, y: 0, width: width, height: 900)
            web = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: WKWebViewConfiguration())
            // Never ordered in: the snapshot is the page drawing itself.
            window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = web
            self.path = path
            self.done = done
            super.init()
            web.navigationDelegate = self
            web.loadHTMLString(html, baseURL: nil)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [self] value, _ in
                let height = CGFloat((value as? NSNumber)?.doubleValue ?? 900)
                let size = NSSize(width: web.frame.width, height: max(200, height))
                window.setContentSize(size)
                web.frame = NSRect(origin: .zero, size: size)
                // One turn of layout at the new height before the picture.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    let config = WKSnapshotConfiguration()
                    config.rect = NSRect(origin: .zero, size: size)
                    web.takeSnapshot(with: config) { [self] image, _ in
                        var wrote = false
                        if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            wrote = (try? png.write(to: URL(fileURLWithPath: path))) != nil
                        }
                        finish(wrote)
                    }
                }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
        private func finish(_ ok: Bool) {
            PermissionsPage.shoots.removeAll { $0 === self }
            done(ok)
        }
    }

    /// The page for these readings as a PNG — drawn in a window that is never
    /// ordered in, so nothing reaches a screen. Main thread; `done` on main.
    static func png(_ readings: [Permissions.Reading], to path: String, width: CGFloat = 760,
                    dark: Bool = false, done: @escaping (Bool) -> Void) {
        shoots.append(Shoot(html: html(readings, build: StatusItem.buildStamp), width: width, dark: dark,
                            path: path, done: done))
    }

    /// `WT_SHOOT_PERMISSIONS=<png>` (+ `WT_PERMISSIONS_FAKE=accessibility:missing,…`,
    /// `WT_PERMISSIONS_DARK=1`): draw the page and quit — `main.swift`.
    static func shoot(to path: String) {
        let env = ProcessInfo.processInfo.environment
        var raw: [String: Any] = [:]
        for pair in (env["WT_PERMISSIONS_FAKE"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            raw[parts[0]] = parts.count > 1 ? parts[1] : "missing"
        }
        let parsed = Permissions.parseFakes(raw)
        for e in parsed.errors { FileHandle.standardError.write(Data("\(e)\n".utf8)) }
        Permissions.faked = parsed.fakes
        Permissions.refreshAutomationNow()
        var result: Bool?
        png(Permissions.readings(), to: path, dark: env["WT_PERMISSIONS_DARK"] == "1") { result = $0 }
        let deadline = Date().addingTimeInterval(15)
        while result == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if result != true { FileHandle.standardError.write(Data("no picture written\n".utf8)) }
        exit(result == true ? 0 : 1)
    }
}
