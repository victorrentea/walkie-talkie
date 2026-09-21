import AppKit
import CProjectM
import ImageIO

/// **The MilkDrop presets, run natively by projectM 4** (the `projectm` branch,
/// 2026-09-21) — the "route B" of the halo rule file, built out. Same contract
/// as `MilkDropHalo` (`HaloWebHost`: start/stop, the microphone's samples
/// pushed in, the square following the pointer as a window), same keying and
/// the same radial mask, no web view: the engine renders into an FBO of our own
/// in a CGL context (`pmhalo.cpp`), a keying pass turns its black into alpha
/// and writes an IOSurface, and a `CALayer` shows that surface. No WebContent
/// process, no WebKit GPU process, no JavaScript bridge, no base64 audio.
///
/// - **Presets are `.milk` files** in `assets/projectm/presets/`, one per
///   `HaloStyle.Preset`, named by the preset's butterchurn name; the textures
///   they reference in `assets/projectm/textures/`. All six are the originals
///   butterchurn's JSON was converted from (three had to be found upstream —
///   `assets/projectm/README.md` says where, and the one line edited).
/// - **`gain`, `rot`, `pinCenter`, the fade** are honoured the way the page
///   honours them: the mask and the gain in the keying shader; `rot` and the
///   pinned centre as `per_frame_` lines appended to our copy of the preset's
///   text before it is handed to the engine.
/// - **Selected by `HaloEngine.current`** (`WT_HALO_ENGINE=native`, or the
///   `haloEngine` default); the web route (`MilkDropHalo`) stays the default
///   until this one is judged.
/// - **Resolution**: `WT_PM_SCALE` pixels per point of the square (default 1 —
///   the web route renders at the backing scale, 2; measured, see
///   `docs/projectm/REPORT.md`).
final class ProjectMHalo: NSView, HaloWebHost {
    private let preset: HaloStyle.Preset
    private let screen: CGSize
    private var renderer: OpaquePointer?
    private let picture = CALayer()
    /// **The engine renders off the main thread** — its own serial queue, where
    /// the CGL context is made current for each frame; the main thread only
    /// receives the finished surface. The tap and the chip never wait on a frame.
    private let renderQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.projectm", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var configured = false
    private var failed = false
    private var frames = 0, totalFrames = 0
    private var engineMs = 0.0, keyMs = 0.0, statAt = CFAbsoluteTimeGetCurrent()
    var onFailure: ((String) -> Void)?
    var onVisible: (() -> Void)?

    /// The microphone's rate, as `MicRecorder` and `DemoVoice` fill `samples`.
    static let sampleRate = 16000
    static let resample = ProcessInfo.processInfo.environment["WT_PM_RESAMPLE"] == "1"
    /// `WT_PM_AUDIO_GAIN=<k>`: the samples multiplied before the engine — the knob for
    /// matching the beat response of the web route.
    static let audioGain: Float = ProcessInfo.processInfo.environment["WT_PM_AUDIO_GAIN"].flatMap { Float($0) } ?? 1
    /// Pixels per point of the square. The engine's cost is per pixel.
    static let renderScale: CGFloat = ProcessInfo.processInfo.environment["WT_PM_SCALE"].flatMap { Double($0) }.map { CGFloat($0) } ?? 1
    /// **The native engine's own gain per preset**, multiplied into the style's
    /// `gain` before keying — measured 2026-09-21 as the ratio of the web
    /// twin's mean luminance to the native one over the same three seconds
    /// of the demo voice (`docs/projectm/lum.py`), then iterated until the
    /// means agree (`REPORT.md`, *Brightness*). `WT_PM_GAIN_SCALE='{"7": 0.7}'`
    /// overrides a value for a run.
    ///
    /// **Bipolar (1) is deliberately absent — it has never been measured.**
    /// Added 2026-09-21 with **the screen locked**, and a locked screen is a
    /// capture stop for both routes: the engine runs and counts frames but the
    /// surface reads back pure black, and the web twin never starts at all
    /// (*"the engine's page was not ready 2 s after the ring was asked for"*).
    /// The control proves it is the screen and not the preset — **Cauldron,
    /// measured at 0.95 the night before, came back just as black.** So no
    /// web/native ratio exists for Bipolar. A missing entry reads as 1 — the
    /// honest value until someone runs
    /// `ROUTES="web native1" docs/projectm/shoot.sh /tmp/shoot milkdrop1`
    /// **at an unlocked screen** and puts the measured number here.
    static let gainScale: [Int: CGFloat] = {
        var table: [Int: CGFloat] = [7: 0.12, 8: 0.3, 20: 0.9, 85: 1.05, 87: 1.2, 103: 1.1]
        if let raw = ProcessInfo.processInfo.environment["WT_PM_GAIN_SCALE"], let data = raw.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
            for (k, v) in o { if let n = Int(k) { table[n] = CGFloat(v) } }
        }
        return table
    }()

    /// Same warm-up as the web route: a feedback preset's first frames are the
    /// bare waveform on an empty buffer.
    static let warmup: TimeInterval = MilkDropHalo.warmup

    // MARK: Where the presets are

    /// `Resources/projectm` installed, `assets/projectm` walking up from a
    /// `.build` binary, `WT_PROJECTM_DIR` overriding both.
    static func folder() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["WT_PROJECTM_DIR"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let res = Bundle.main.resourcePath {
            candidates.append(URL(fileURLWithPath: res).appendingPathComponent("projectm"))
        }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("assets/projectm"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("presets").path) }
    }

    /// The preset's `.milk`: by its butterchurn name, else by its number
    /// (`md<n>.milk`, for a stand-in).
    static func milkFile(for preset: HaloStyle.Preset) -> URL? {
        guard let dir = folder()?.appendingPathComponent("presets") else { return nil }
        let byName = dir.appendingPathComponent("\(preset.name).milk")
        if FileManager.default.fileExists(atPath: byName.path) { return byName }
        let byNumber = dir.appendingPathComponent("md\(preset.number).milk")
        if FileManager.default.fileExists(atPath: byNumber.path) { return byNumber }
        return nil
    }

    static func available(for preset: HaloStyle.Preset) -> Bool { milkFile(for: preset) != nil }

    // MARK: Life

    init?(preset: HaloStyle.Preset, side: CGFloat, screen: CGSize) {
        guard Self.milkFile(for: preset) != nil else { return nil }
        self.preset = preset
        self.screen = screen
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        // **Layer-hosting, not layer-backed**: `layer` set before `wantsLayer`,
        // so the tree is ours from this line — `wantsLayer` alone leaves `layer`
        // nil until AppKit's next display pass, and a sublayer added to nil is
        // a halo that never shows (measured: an empty capture, a rendered surface).
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: side, height: side)
        root.isOpaque = false
        layer = root
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        picture.frame = root.bounds
        picture.contentsGravity = .resize
        picture.isOpaque = false
        picture.magnificationFilter = .linear
        picture.minificationFilter = .linear
        root.addSublayer(picture)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        stopTimer()
        if let r = renderer { renderQueue.sync { pmh_destroy(r) } }
    }

    override var isFlipped: Bool { false }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        picture.frame = bounds
        CATransaction.commit()
    }

    /// **The preset's text, with our two amendments** appended as the last
    /// `per_frame_` lines — the page appends the same to the compiled frame
    /// equations (`halo.html`): `rot=rot*k` multiplies the whole per-frame turn,
    /// sine terms included; `cx=cy=0.5` pins a centre the preset wanders.
    static func amend(_ milk: String, rot: CGFloat, pinCenter: Bool) -> String {
        guard rot != 1 || pinCenter else { return milk }
        var maxN = 0
        for line in milk.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.hasPrefix("per_frame_"), let eq = line.firstIndex(of: "=") else { continue }
            let n = Int(line[line.index(line.startIndex, offsetBy: 10)..<eq].trimmingCharacters(in: .whitespaces)) ?? 0
            maxN = max(maxN, n)
        }
        var out = milk
        if !out.hasSuffix("\n") { out += "\n" }
        if rot != 1 { maxN += 1; out += "per_frame_\(maxN)=rot=rot*\(rot);\n" }
        if pinCenter { maxN += 1; out += "per_frame_\(maxN)=cx=0.5;cy=0.5;\n" }
        return out
    }

    /// Per-run options, as `MilkDropHalo.optionsOverride` / `WT_HALO_PRESET_OPTS` carry them
    /// (`{"gain": 4, "rot": 2, "fadeFloor": 0, "fadeStart": 0.5, "pinCenter": true}`).
    private func options() -> (gain: CGFloat, rot: CGFloat, floor: CGFloat, start: CGFloat, pin: Bool, fadeAtEdge: Bool, fadeRadius: CGFloat?) {
        var gain = preset.gain, rot = preset.rot, floor = preset.fadeFloor, start = preset.fadeStart
        var pin = preset.pinCenter, atEdge = preset.fadeAtEdge, radius = preset.fadeRadius
        let raw = MilkDropHalo.optionsOverride ?? ProcessInfo.processInfo.environment["WT_HALO_PRESET_OPTS"] ?? "{}"
        if let data = raw.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = o["gain"] as? Double { gain = CGFloat(v) }
            if let v = o["rot"] as? Double { rot = CGFloat(v) }
            if let v = o["fadeFloor"] as? Double { floor = CGFloat(v) }
            if let v = o["fadeStart"] as? Double { start = CGFloat(v) }
            if let v = o["pinCenter"] as? Bool { pin = v }
            if let v = o["fadeAtEdge"] as? Bool { atEdge = v }
            if let v = o["fadeRadius"] as? Double { radius = CGFloat(v) }
        }
        return (gain, rot, floor, start, pin, atEdge, radius)
    }

    private func configure() -> Bool {
        guard let dir = Self.folder(), let file = Self.milkFile(for: preset),
              let milk = try? String(contentsOf: file, encoding: .isoLatin1) else {
            fail("the preset file for \(preset.number) could not be read"); return false
        }
        let side = bounds.width
        let px = max(64, Int((side * Self.renderScale).rounded()))
        var err = [CChar](repeating: 0, count: 512)
        let texDirs = [dir.appendingPathComponent("textures").path, dir.appendingPathComponent("presets").path]
        var cstrs: [UnsafeMutablePointer<CChar>?] = texDirs.map { strdup($0) } + [nil]
        defer { cstrs.forEach { free($0) } }
        let r = cstrs.withUnsafeMutableBufferPointer { buf -> OpaquePointer? in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { p in
                pmh_create(Int32(px), Int32(haloFrameCap > 0 ? haloFrameCap : 60), p, &err, 512)
            }
        }
        guard let renderer = r else { fail("projectM could not start: \(String(cString: err))"); return false }
        self.renderer = renderer
        let o = options()
        let text = Self.amend(milk, rot: o.rot, pinCenter: o.pin)
        if pmh_load_preset(renderer, text, &err, 512) != 0 {
            fail("projectM refused preset \(preset.number) (\(file.lastPathComponent)): \(String(cString: err))"); return false
        }
        // The mask's radii as fractions of the square's side — `halo.html`'s
        // three cases: to the canvas edge, a fraction of the screen's width, or
        // the screen's own ellipse.
        var rx: CGFloat = 0.5, ry: CGFloat = 0.5
        if o.fadeAtEdge { rx = 0.5; ry = 0.5 }
        else if let f = o.fadeRadius { rx = screen.width * f / side; ry = rx }
        else { rx = screen.width / 2 / side; ry = screen.height / 2 / side }
        let gain = o.gain * (Self.gainScale[preset.number] ?? 1)
        pmh_set_mask(renderer, preset.fade, Float(rx), Float(ry), Float(o.floor), Float(gain), Float(o.start))
        Log.info("◯ projectM \(preset.number): \(file.lastPathComponent) at \(px)px (\(Self.renderScale)× of \(Int(side))pt), gain \(o.gain) × \(Self.gainScale[preset.number] ?? 1) = \(gain), rot ×\(o.rot)\(o.pin ? ", centre pinned" : "") \(CaretHalo.sinceStyleChange)")
        return true
    }

    func start() {
        guard !failed else { return }
        let fresh = !configured
        if fresh {
            configured = true
            guard configure() else { return }
        }
        startTimer()
        if !fresh { onVisible?(); return }
        picture.opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmup) { [weak self] in
            guard let self = self else { return }
            CATransaction.begin()
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.25
            self.picture.add(fade, forKey: "fadeIn"); self.picture.opacity = 1
            CATransaction.commit()
            Log.info("◯ projectM \(self.preset.number): fading in after the warm-up \(CaretHalo.sinceStyleChange)")
            self.onVisible?()
        }
    }

    func stop() { stopTimer() }

    /// The square follows the pointer as a window; nothing to tell the engine.
    func center(_ p: CGPoint) {}

    /// The microphone's last 2048 samples at 16 kHz, thirty times a second: the
    /// newest 1/30 s of them go to the engine (resampled to 44.1 kHz in the glue).
    func feed(_ samples: [Float]) {
        guard let r = renderer else { return }
        // Pushed on the render queue, behind whatever frame is in flight: the
        // engine's PCM ring is not written from two threads.
        let fresh = min(samples.count, Self.sampleRate / max(1, haloFrameCap > 0 ? haloFrameCap : 30) + 16)
        var tail = Array(samples.suffix(fresh))
        if Self.audioGain != 1 { for i in tail.indices { tail[i] *= Self.audioGain } }
        // **Handed over as they are, not resampled** (`WT_PM_RESAMPLE=1` to resample
        // to 44.1 kHz): both engines are MilkDrop's beat detector, which reads
        // its bands off spectrum bins and assumes 44.1 kHz, and the web route
        // gives butterchurn these very samples raw — so the presets Victor tuned
        // by eye see the same spectrum here.
        renderQueue.async {
            tail.withUnsafeBufferPointer { pmh_add_pcm(r, $0.baseAddress, UInt32(tail.count), Self.resample ? Int32(Self.sampleRate) : 44100) }
        }
    }

    // MARK: The frame loop

    private func startTimer() {
        stopTimer()
        let interval = 1.0 / Double(haloFrameCap > 0 ? haloFrameCap : 60)
        let t = DispatchSource.makeTimerSource(queue: renderQueue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.frame() }
        t.resume()
        timer = t
    }
    private func stopTimer() { timer?.cancel(); timer = nil }

    /// One frame, on the render queue: the engine and the key pass, the
    /// surface's seed bumped, the layer told on the main thread.
    private func frame() {
        guard let r = renderer, !failed else { return }
        // A CF object out of a C function comes back `Unmanaged`; handed to
        // `contents` as it is, the layer shows nothing and says nothing.
        guard let surface = pmh_render(r)?.takeUnretainedValue() else {
            DispatchQueue.main.async { [weak self] in self?.fail("a GL error in the keying pass") }
            return
        }
        // **CA does not see a GPU write.** It reads an IOSurface's *seed*, which
        // only a CPU lock bumps, and the object alternates between two surfaces
        // it has already seen — so without one of these it keeps showing the
        // first frame each surface ever held (measured: a dark disc at alpha
        // ≤ 20 on screen while the readback was bright). `WT_PM_SYNC=nil`
        // clears the contents first; the default bumps the seed with an empty lock.
        if Self.syncMode != "nil" { IOSurfaceLock(surface, [], nil); IOSurfaceUnlock(surface, [], nil) }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            if Self.syncMode == "nil" { self.picture.contents = nil }
            self.picture.contents = surface
            CATransaction.commit()
        }
        frames += 1
        totalFrames += 1
        if ProcessInfo.processInfo.environment["WT_PM_DEBUG_ALPHA"] != nil, totalFrames == 60 || totalFrames == 100 { pmh_debug_alpha(r) }
        engineMs += pmh_last_engine_ms(r); keyMs += pmh_last_key_ms(r)
        // `WT_PM_SHOOT=<dir/name>` writes the frame at every whole second from 3
        // to 8 s (by frame count at the cap) read back from the surface — the
        // engine's output with nothing of the screen in it — as `<dir/name>-3s.png`…
        let fps = haloFrameCap > 0 ? haloFrameCap : 60
        if totalFrames % fps == 0, (3...8).contains(totalFrames / fps), let base = ProcessInfo.processInfo.environment["WT_PM_SHOOT"], let img = snapshot() {
            let path = "\(base)-\(totalFrames / fps)s.png"
            if let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, nil)
                Log.info("◯ projectM \(preset.number): frame \(totalFrames) written to \(path): \(CGImageDestinationFinalize(dest))")
            }
        }
        if Self.stats, CFAbsoluteTimeGetCurrent() - statAt > 5, frames > 0 {
            Log.info(String(format: "◯ projectM %d: %d frames, engine %.2f ms + key %.2f ms a frame (CPU submit%@), %u GL errors left by the engine",
                            preset.number, frames, engineMs / Double(frames), keyMs / Double(frames),
                            ProcessInfo.processInfo.environment["WT_PM_FINISH"] != nil ? " + GPU finish" : "", pmh_engine_gl_errors(r)))
            frames = 0; engineMs = 0; keyMs = 0; statAt = CFAbsoluteTimeGetCurrent()
        }
    }
    static let stats = ProcessInfo.processInfo.environment["WT_PM_STATS"] != nil
    static let syncMode = ProcessInfo.processInfo.environment["WT_PM_SYNC"] ?? "seed"

    /// **The last frame as an image**, read back from the surface — for the
    /// captures in `docs/projectm/` and for tests. Nil before the first frame.
    func snapshot() -> CGImage? {
        guard let r = renderer else { return nil }
        // From the render queue (the shoot) or from main with the queue drained.
        let px = Int((bounds.width * Self.renderScale).rounded())
        var buf = [UInt8](repeating: 0, count: px * px * 4)
        guard pmh_read_pixels(r, &buf) == 0 else { return nil }
        let data = Data(buf)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func fail(_ why: String) {
        guard !failed else { return }
        failed = true
        stopTimer()
        Log.error("◯ projectM: \(why) — falling back to the film")
        onFailure?(why)
    }
}

/// **Which engine draws a preset**: the web route (`MilkDropHalo`, butterchurn
/// in a `WKWebView`) or the native one (`ProjectMHalo`). `WT_HALO_ENGINE=native`
/// for a run, the `haloEngine` default otherwise; web until the native one is
/// judged (`docs/projectm/REPORT.md`).
enum HaloEngine: String {
    case web, native
    static let defaultsKey = "haloEngine"
    static var current: HaloEngine {
        if let name = ProcessInfo.processInfo.environment["WT_HALO_ENGINE"], let e = HaloEngine(rawValue: name) { return e }
        if let name = UserDefaults.standard.string(forKey: defaultsKey), let e = HaloEngine(rawValue: name) { return e }
        return .web
    }
}
