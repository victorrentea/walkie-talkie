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
/// - **Square, side `max(w, h)` of the screen**, CSS-scaled by the preset's
///   `scale` — the page's "cover": rendered any other shape the circles come
///   out as ovals.
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
    private var readyWatchdog: Timer?
    private var failed = false
    /// The page is unusable, and why — `CaretHalo` draws the film instead.
    var onFailure: ((String) -> Void)?

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
        let opts = "{fadeRadius: \(preset.fadeRadius.map { "\($0)" } ?? "null"), fadeAtEdge: \(preset.fadeAtEdge), fadeFloor: \(preset.fadeFloor), gain: \(preset.gain), rot: \(preset.rot)}"
        // `WT_HALO_PRESET_OPTS='{"gain": 4}'` overrides fields for one run — the knob for looking.
        let override = ProcessInfo.processInfo.environment["WT_HALO_PRESET_OPTS"] ?? "{}"
        let js = "halo.size(\(side), \(preset.scale), \(dpr), {w: \(screen.width), h: \(screen.height)}); "
               + "halo.preset(\(Self.jsString(preset.name)), \(preset.fade), Object.assign(\(opts), \(override)))"
        web.evaluateJavaScript(js) { [weak self] result, error in
            // The exception's own message, not WebKit's cover line for it.
            let status = (result as? String) ?? error.map { e in
                "error: \(((e as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String) ?? e.localizedDescription) at line \((e as NSError).userInfo["WKJavaScriptExceptionLineNumber"] ?? "?")" } ?? "?"
            if status != self?.lastStatus {
                self?.lastStatus = status
                Log.info("◯ MilkDrop \(self?.preset.number ?? 0): \(status)")
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
        configure()
        web.evaluateJavaScript("halo.start()", completionHandler: nil)
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
