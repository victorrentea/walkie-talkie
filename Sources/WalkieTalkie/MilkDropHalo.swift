import AppKit
import WebKit

/// **The MilkDrop presets, run by the real engine in a transparent web view**
/// (2026-09-20, `swift-port-02`). Victor: *"migrate the MilkDrop ones to Swift
/// as well"* — and since reimplementing a shader-and-equation preset is not
/// possible, the standard he set is *identical to the original*: butterchurn
/// itself, hosted here, the way `voice-halo` hosts it.
///
/// - **Bundled, never fetched.** `assets/milkdrop/` carries the page, the
///   engine and the two preset packs the page loads; `build-app.sh` copies the
///   folder into `Resources/milkdrop`. The halo has to work on a plane.
///   `engineAvailable` says whether `butterchurn.min.js` is actually there —
///   the preset packs were vendored from a local tarball, the engine has to be
///   dropped in by hand (the menu greys the rows until it is).
/// - **Transparent and click-through.** The web view draws no background
///   (`drawsBackground` false, `underPageBackgroundColor` clear, a transparent
///   body) and lives in the halo's own `ignoresMouseEvents`, non-activating
///   panel. The engine's opaque black is keyed to alpha in the page.
/// - **Audio is pushed in**, thirty times a second, as the last 1024 samples —
///   the page hands them to the engine as its analyser's byte arrays. No
///   `getUserMedia`, no second microphone, no permission prompt, no output
///   device.
/// - **Square, side `max(w, h)` of the screen × the preset's `scale`** — the
///   page's "cover": rendered any other shape the circles come out as ovals.
///   The **page** applies `scale` a second time, to the canvas inside this
///   view, so what is on screen is `max(w, h) × scale²` and this view carries a
///   dead margin round it. Since 2026-09-21 the canvas is laid out at exactly
///   that size in whole device pixels with no transform on it — one canvas
///   pixel per device pixel, which is what *"punctele apar un pic blurate"*
///   was. The log line carries the geometry: `ok · 1500pt canvas, 3000px`.
/// - **Why still this page and not the whole `voice-halo` page** (2026-09-20,
///   evening): the hand-written effects run in `HaloPage`, and the same
///   engine, fed the same bytes with the same preset, renders **dark** inside
///   that page in a `WKWebView` (measured: engine buffer mean 2/255 against
///   67 here, every JS-side variable identical — see the report of that day);
///   the cause was not found in the time there was, this page is proven, so
///   the presets stay here.
final class MilkDropHalo: NSView, HaloWebHost {
    let web: WKWebView
    private let preset: HaloStyle.Preset
    private let screen: CGSize
    private var ready = false
    private var pendingStart = false
    private var lastStatus = ""
    /// Per-run preset options from `POST /test/halo {"opts": …}` — a JSON
    /// object merged over the style's own; nil = none. Cleared by a style pick.
    static var optionsOverride: String?
    private var readyWatchdog: Timer?
    private var levelsTimer: Timer?
    /// The preset is loaded once per host, not on every `start`: the engine's
    /// feedback buffer is its picture, and reloading threw it away each dictation.
    private var configured = false
    /// **The warm-up is hidden** (Victor, 2026-09-20 late: *"initially it looks
    /// like a set of white circles … get rid of the beginning part"*). A
    /// feedback preset's first frames are the bare waveform on an empty
    /// buffer; the engine runs with the view at alpha 0 for `warmup` seconds
    /// after a load, then fades in over 0.25 s. Every preset, not only Tunnel.
    static let warmup: TimeInterval = 1.5
    private var failed = false
    /// The page is unusable, and why — `CaretHalo` draws the film instead.
    var onFailure: ((String) -> Void)?
    var onVisible: (() -> Void)?

    /// Where the page and its scripts are — `Resources/milkdrop` installed,
    /// `assets/milkdrop` walking up from a `.build` binary, `WT_MILKDROP_DIR`
    /// overriding both.
    static func folder() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WT_MILKDROP_DIR"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let res = Bundle.main.resourcePath {
            candidates.append(URL(fileURLWithPath: res).appendingPathComponent("milkdrop"))
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("assets/milkdrop"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("halo.html").path) }
    }

    /// Is the engine itself bundled? The page and the presets are in the repo;
    /// `butterchurn.min.js` (butterchurn 2.6.7, ~600 KB) is not, and without
    /// it a preset row would put a test pattern on his screen.
    static var engineAvailable: Bool {
        guard let dir = folder() else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("butterchurn.min.js").path)
    }

    init?(preset: HaloStyle.Preset, side: CGFloat, screen: CGSize) {
        guard let dir = Self.folder() else { return nil }
        self.preset = preset
        self.screen = screen
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: side, height: side), configuration: config)
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        wantsLayer = true
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        web.navigationDelegate = self
        web.loadFileURL(dir.appendingPathComponent("halo.html"), allowingReadAccessTo: dir)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `NSView` is not flipped; nothing here needs a coordinate.
    override var isFlipped: Bool { false }

    private func configure() {
        let side = bounds.width
        let dpr = window?.backingScaleFactor ?? 2
        let opts = "{fadeRadius: \(preset.fadeRadius.map { "\($0)" } ?? "null"), fadeAtEdge: \(preset.fadeAtEdge), fadeFloor: \(preset.fadeFloor), fadeStart: \(preset.fadeStart), gain: \(preset.gain), rot: \(preset.rot), pinCenter: \(preset.pinCenter), speed: \(preset.speed), hole: \(preset.hole), peak: \(preset.peak)}"
        // `WT_HALO_PRESET_OPTS='{"gain": 4}'` overrides fields for one run — the knob for looking.
        let override = Self.optionsOverride ?? ProcessInfo.processInfo.environment["WT_HALO_PRESET_OPTS"] ?? "{}"
        // The geometry the page settled on rides back with the preset's status,
        // because *what size is it actually drawing at* was a question only a
        // patched page could answer until 2026-09-21.
        // **Canvas pixels per point**: the preset's own, else the display's
        // backing scale. `WT_MD_SCALE` is the knob for looking, `ProjectMHalo`'s
        // `WT_PM_SCALE` twin.
        let pxPerPt = ProcessInfo.processInfo.environment["WT_MD_SCALE"].flatMap { Double($0) }.map { CGFloat($0) }
            ?? preset.renderScale ?? dpr
        let js = "var geom = halo.size(\(side), \(pxPerPt), \(dpr), {w: \(screen.width), h: \(screen.height)}); "
               + "halo.preset(\(Self.jsString(preset.name)), \(preset.fade), Object.assign(\(opts), \(override))) + ' · ' + geom"
        web.evaluateJavaScript(js) { [weak self] result, error in
            // The exception's own message, not WebKit's cover line for it.
            let status = (result as? String) ?? error.map { e in
                "error: \(((e as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? e.localizedDescription) at line \((e as NSError).userInfo["WKJavaScriptExceptionLineNumber"] ?? "?")" } ?? "?"
            if status != self?.lastStatus {
                self?.lastStatus = status
                Log.info("◯ MilkDrop \(self?.preset.number ?? 0): \(status) \(CaretHalo.sinceStyleChange)")
            }
        }
    }

    func start() {
        guard ready else {
            pendingStart = true
            if readyWatchdog == nil {
                let t = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
                    guard let self = self, !self.ready else { return }
                    self.fail("the engine's page was not ready 2 s after the ring was asked for")
                }
                readyWatchdog = t
                RunLoop.main.add(t, forMode: .common)
            }
            return
        }
        let fresh = !configured
        if fresh { configure(); configured = true }
        web.evaluateJavaScript("halo.fps(\(haloFrameCap)); halo.start()", completionHandler: nil)
        if !fresh { onVisible?() }
        // `WT_MD_SHOOT=<dir/name>`: at every whole second from 3 to 8 s, the engine's own frame, keyed,
        // with nothing of the screen in it — `ProjectMHalo`'s `WT_PM_SHOOT` twin.
        if fresh, let base = ProcessInfo.processInfo.environment["WT_MD_SHOOT"] {
            for t in 3...8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(t)) { [weak self] in
                    self?.web.evaluateJavaScript("halo.snapshot()") { result, error in
                        guard let url = result as? String, let comma = url.firstIndex(of: ","),
                              let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else {
                            Log.error("◯ MilkDrop: no snapshot — \(error?.localizedDescription ?? "?")"); return
                        }
                        let path = "\(base)-\(t)s.png"
                        try? data.write(to: URL(fileURLWithPath: path))
                        Log.info("◯ MilkDrop \(self?.preset.number ?? 0): frame at \(t) s written to \(path) (\(data.count) bytes)")
                    }
                }
            }
        }
        // `WT_MD_LEVELS=1`: the engine's bass/mid/treb ten times a second, to the log.
        if fresh, ProcessInfo.processInfo.environment["WT_MD_LEVELS"] != nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.web.evaluateJavaScript("halo.levels()") { result, _ in
                    if let s = result as? String { Log.info("[mdaudio] \(s)") }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            levelsTimer = t
        }
        if fresh {
            web.alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmup) { [weak self] in
                guard let web = self?.web else { return }
                NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.25; web.animator().alphaValue = 1 }
                Log.info("◯ MilkDrop \(self?.preset.number ?? 0): fading in after the warm-up \(CaretHalo.sinceStyleChange)")
                self?.onVisible?()
            }
        }
    }

    /// The engine's square follows the pointer as a window; nothing to tell the page.
    func center(_ p: CGPoint) {}

    private func fail(_ why: String) {
        guard !failed else { return }
        failed = true
        readyWatchdog?.invalidate(); readyWatchdog = nil
        Log.error("◯ MilkDrop: \(why) — falling back to the film")
        onFailure?(why)
    }

    func stop() {
        pendingStart = false
        web.evaluateJavaScript("halo.stop()", completionHandler: nil)
    }

    /// The last 1024 samples, base64 Float32 — ~5.5 KB a call, thirty a
    /// second. `evaluateJavaScript` rather than a message handler because the
    /// data flows one way, app → page.
    func feed(_ samples: [Float]) {
        guard ready else { return }
        let tail = Array(samples.suffix(1024))
        let data = tail.withUnsafeBufferPointer { Data(buffer: $0) }
        web.evaluateJavaScript("halo.audio('\(data.base64EncodedString())')", completionHandler: nil)
    }

    private static func jsString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}

extension MilkDropHalo: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        readyWatchdog?.invalidate(); readyWatchdog = nil
        if pendingStart { pendingStart = false; start() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("the engine's page failed to load: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("the engine's page failed to load: \(error.localizedDescription)")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("the web content process died")
    }
}
