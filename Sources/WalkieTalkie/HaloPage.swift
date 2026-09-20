import AppKit
import WebKit

/// **The `voice-halo` page itself, hosted in a transparent web view**
/// (2026-09-20). Victor's standard for every halo but the film: *identical to
/// the page*. `HaloEffects.swift` re-drew nine of them in CoreGraphics and came
/// out small, coarse and — for the water — missing most of the scene; the
/// MilkDrop presets, run by the real engine in a `WKWebView`, came out right.
/// So the page is run whole, in the same kind of view, and the app is a remote
/// control over it: `pick`, `center`, `audio`, `start`, `stop`.
///
/// Measured, not guessed (see the report of 2026-09-20): a full-screen
/// CoreGraphics trail pass costs 48–86 ms a frame on this Mac and the page's
/// ring with its shadow blur 58 ms; the page does the same work on the GPU.
///
/// - **Vendored, never fetched.** `assets/voice-halo/` is `index.html` +
///   `water.js` from `victorrentea/voice-halo` at the tag pinned in
///   `tools/vendor-voice-halo.sh`; `build-app.sh` copies it into
///   `Resources/voice-halo`. The MilkDrop engine and its preset packs stay in
///   `Resources/milkdrop` and the page is told where they are (`?md=`).
/// - **`?embed=1`** is the page's own mode for this host: no chrome, no drawn
///   cursor, transparent body, the opaque canvases (MilkDrop, water) keyed to
///   alpha in a WebGL pass, and the drawing origin on the pointer through the
///   page's walk offset — so a change on the page flows in by re-vendoring.
/// - **Transparent and click-through**: `drawsBackground` off, clear
///   `underPageBackgroundColor`, in the halo's `ignoresMouseEvents` panel.
/// - **Audio is pushed in**, thirty times a second, the last 1024 samples at
///   16 kHz; the page emulates its `AnalyserNode` from them. No
///   `getUserMedia`, no second microphone, no `AudioContext` running.
/// - **Failure has a floor**: the page missing, failing to load, not ready
///   two seconds after the ring is asked for, reporting no WebGL for a keyed
///   effect, or a preset that will not pin — each calls `onFailure`, and
///   `CaretHalo` draws the film instead. The everyday ring never waits on this.
final class HaloPage: NSView, HaloWebHost {
    let web: WKWebView
    private(set) var ready = false
    private var pendingStart = false
    private var pendingPick: HaloStyle?
    private var pendingCenter: CGPoint?
    private var readyWatchdog: Timer?
    private var failed = false
    /// The page is unusable, and why. Called at most once per instance.
    var onFailure: ((String) -> Void)?

    /// Where the page is — `Resources/voice-halo` installed, `assets/voice-halo`
    /// walking up from a `.build` binary, `WT_HALO_PAGE_DIR` overriding both.
    static func folder() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WT_HALO_PAGE_DIR"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let res = Bundle.main.resourcePath {
            candidates.append(URL(fileURLWithPath: res).appendingPathComponent("voice-halo"))
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("assets/voice-halo"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path) }
    }

    /// Is the page here at all?
    static var available: Bool { folder() != nil }

    /// Where the MilkDrop engine and its preset packs are — `Resources/milkdrop`
    /// installed, `assets/milkdrop` from a `.build` binary, `WT_MILKDROP_DIR`
    /// overriding both. A folder of its own, because `WT_HALO_PAGE_DIR` can
    /// point the page at the sibling checkout, where no engine lives.
    static func engineFolder() -> URL? {
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
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("butterchurnPresets.min.js").path) }
    }

    /// Is the MilkDrop engine here? The preset packs are in the repo;
    /// `butterchurn.min.js` is dropped in by hand, and without it a preset
    /// row would show nothing.
    static var engineAvailable: Bool {
        guard let dir = engineFolder() else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent("butterchurn.min.js").path)
    }

    /// The deepest folder holding both `a` and `b`: what the web view is
    /// allowed to read, so the page can load the engine from beside it.
    private static func commonAncestor(_ a: URL, _ b: URL) -> URL {
        let pa = a.standardizedFileURL.pathComponents, pb = b.standardizedFileURL.pathComponents
        var common: [String] = []
        for (x, y) in zip(pa, pb) where x == y { common.append(x) }
        return URL(fileURLWithPath: NSString.path(withComponents: common))
    }

    /// `size` is the screen's, in points: the page lays every effect out
    /// from `innerWidth × innerHeight`, exactly as it does in a browser.
    init?(size: CGSize) {
        guard let dir = Self.folder() else { return nil }
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let bridge = Bridge()
        config.userContentController.add(bridge, name: "halo")
        web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        super.init(frame: NSRect(origin: .zero, size: size))
        bridge.owner = self
        wantsLayer = true
        web.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) { web.underPageBackgroundColor = .clear }
        web.autoresizingMask = [.width, .height]
        addSubview(web)
        web.navigationDelegate = self
        // The engine folder is handed to the page as an absolute file URL, and
        // the read access covers both it and the page.
        let engine = Self.engineFolder()
        var parts = URLComponents(url: dir.appendingPathComponent("index.html"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "embed", value: "1")]
        if ProcessInfo.processInfo.environment["WT_HALO_PAGE_DBG"] != nil { parts.queryItems?.append(URLQueryItem(name: "dbg", value: "1")) }
        if let engine = engine {
            parts.queryItems?.append(URLQueryItem(name: "md", value: engine.absoluteString + "/"))
        }
        let readable = engine.map { Self.commonAncestor(dir, $0) } ?? dir
        web.loadFileURL(parts.url!, allowingReadAccessTo: readable)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { web.configuration.userContentController.removeScriptMessageHandler(forName: "halo") }

    /// `NSView` is not flipped; the page's coordinates are handed in already
    /// converted (`center`).
    override var isFlipped: Bool { false }

    // MARK: The remote control

    /// Which effect: the page's `pick(i)`, by the style's position in its
    /// `FORMULAS` list. Queued until the page is ready.
    func pick(_ style: HaloStyle) {
        guard let i = style.pageIndex else { return }
        guard ready else { pendingPick = style; return }
        web.evaluateJavaScript("halo.pick(\(i))") { result, error in
            if let error = error { Log.error("◯ halo page: pick(\(i)) failed: \(error.localizedDescription)") }
            else { Log.info("◯ halo page: \(style.rawValue) → page \(i + 1) — \((result as? String) ?? "?")") }
        }
    }

    /// The pointer, in the page's coordinates: CSS px from the panel's
    /// top-left, y down. Written on every pointer move; queued until ready.
    func center(_ p: CGPoint) {
        guard ready else { pendingCenter = p; return }
        web.evaluateJavaScript(String(format: "halo.center(%.1f, %.1f)", p.x, p.y), completionHandler: nil)
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

    /// The page's frame loop runs only while the ring is up. If the page is
    /// not ready two seconds after the ring is asked for, it is not coming.
    func start() {
        guard ready else {
            pendingStart = true
            if readyWatchdog == nil {
                let t = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
                    guard let self = self, !self.ready else { return }
                    self.fail("the page was not ready 2 s after the ring was asked for")
                }
                readyWatchdog = t
                RunLoop.main.add(t, forMode: .common)
            }
            return
        }
        web.evaluateJavaScript("halo.fps(\(haloFrameCap)); halo.start()", completionHandler: nil)
        // `WT_HALO_PAGE_PROBE=1`: five seconds in, ask the page what it sees —
        // which effect, the canvases' sizes and brightness, the audio's range.
        if ProcessInfo.processInfo.environment["WT_HALO_PAGE_PROBE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.web.evaluateJavaScript("halo.probe()") { result, error in
                    Log.info("◯ halo page probe: \((result as? String) ?? error?.localizedDescription ?? "?")")
                }
            }
        }
    }

    func stop() {
        pendingStart = false
        guard ready else { return }
        web.evaluateJavaScript("halo.stop()", completionHandler: nil)
    }

    private func fail(_ why: String) {
        guard !failed else { return }
        failed = true
        readyWatchdog?.invalidate(); readyWatchdog = nil
        Log.error("◯ halo page: \(why) — falling back to the film")
        onFailure?(why)
    }

    /// What the page says, through `webkit.messageHandlers.halo`.
    fileprivate func received(_ body: Any) {
        guard let msg = body as? [String: Any], let event = msg["event"] as? String else { return }
        switch event {
        case "ready":
            let webgl = msg["webgl"] as? Bool ?? false
            let names = (msg["names"] as? [String]) ?? []
            Log.info("◯ halo page ready: \(names.count) effects, webgl \(webgl), dpr \(msg["dpr"] ?? "?"), \(msg["w"] ?? "?")×\(msg["h"] ?? "?") CSS px")
            if !webgl, let style = pendingPick, style.needsWebGL {
                fail("no WebGL, and \(style.rawValue) needs the keying pass")
                return
            }
            ready = true
            readyWatchdog?.invalidate(); readyWatchdog = nil
            if let p = pendingCenter { pendingCenter = nil; center(p) }
            if let s = pendingPick { pendingPick = nil; pick(s) }
            if pendingStart { pendingStart = false; start() }
        case "picked":
            if (msg["ok"] as? Bool) == false {
                fail("the page could not show \(msg["name"] ?? "?")")
            }
        case "error":
            fail((msg["what"] as? String) ?? "the page reported an error")
        default:
            break
        }
    }

    /// `WKUserContentController` retains its handler, so the handler may not
    /// retain the view: a weak hop in between.
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var owner: HaloPage?
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.received(message.body)
        }
    }
}

extension HaloPage: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("the page failed to load: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("the page failed to load: \(error.localizedDescription)")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("the web content process died")
    }
}
