import AppKit
import CProjectM

/// **Which prompt this is, said by an edge of the screen** (2026-11-16). Victor:
/// *"all 3 prompt styles have this same look and feel but to distinguish the 3 from
/// each other, during the dictation into a new terminal, there should be an effect
/// similar to dust, but spread over the entire top edge of the screen. The idea is
/// that, in that direction, I swipe my mouse. The same dust effect, spread over the
/// entire right edge, should happen for the prompting bound to the terminal behind.
/// The effect should be delicate on the edge, barely visible."*
///
/// The three prompts wear the same dust round the pointer (`HaloStyle.promptsWearDust`);
/// the gesture that opened the sentence is repeated on the screen: 🔼 ↑ (a new
/// session) the top edge, 🔼 → (the bound terminal) the right one, the bare 🔼 (the
/// caret) none.
///
/// - **His Smoke on a strip of its own** — a `ProjectMHalo` on a canvas the edge's
///   length by `thickness`, as `CornerTunnel`'s dust is one on a square. The stamp
///   runs the edge back and forth (`stamp(at:)`, a pass every `sweep` on average,
///   the pace and the depth wandering) and the trail it leaves is the dust; the
///   microphone is fed in while it is open, so his voice puffs out of the edge too.
///   A gradient takes it to nothing away from the edge.
/// - **Faint**: the panel at `restAlpha`.
/// - **Up from the first word until the message is in.** *"That edge is glowing and
///   having this effect until the message is confirmed to be dispatched to the
///   target terminal."* Through the transcription and the held prompt (`waiting`,
///   as long as `stillPending` says something of the sentence is on its way), then
///   `sent()` from the terminal's `.delivered` or the new window's `.opened`:
///   *"it … becomes a bit more visible. Let's say it doubles its size and opacity
///   and then fades out, suggesting the message was sent"* — twice as deep, twice
///   the alpha, the stamp twice as fast, over `swell`; held `swellHold`; out in
///   `sentFade`. A cancel, a flip to the caret, a sentence that went nowhere: out
///   in `quietFade`, no swell.
/// - Click-through, `sharingType = .none` (`capturable` for a desk shot), above the
///   menu bar — the top edge is the screen's, not the visible frame's.
///
/// Knobs, in the defaults (`edgeDust.alpha|thickness|sweep|puff|gain|fade|force`):
/// read when the strip is built, so a `defaults write` and the next sentence (or
/// `POST /test/edge-dust`) show it with no restart.
final class EdgeDust {
    enum Edge: String { case top, right }

    static var capturable = false
    static weak var current: EdgeDust?
    init() { Self.current = self }

    private static func knob(_ key: String, _ standard: Double) -> Double {
        UserDefaults.standard.object(forKey: "edgeDust.\(key)") as? Double ?? standard
    }
    /// How deep the strip is, in points; the swell doubles it.
    static var thickness: CGFloat { CGFloat(knob("thickness", 110)) }
    static var restAlpha: CGFloat { CGFloat(knob("alpha", 0.3)) }
    /// One pass of the stamp along the edge, on average.
    static var sweep: TimeInterval { knob("sweep", 1.3) }
    /// A puff's size, in points — the splat's radius is derived from it per canvas.
    static var puff: CGFloat { CGFloat(knob("puff", 22)) }
    static let swell: TimeInterval = 0.35
    static let swellHold: TimeInterval = 0.45
    static let sentFade: TimeInterval = 0.8
    static let quietFade: TimeInterval = 0.4
    /// With nothing of the sentence on its way for this long, the edge goes quietly.
    static let patience: TimeInterval = 1.2
    static let ceiling: TimeInterval = 90

    /// The microphone's recent samples, as `CaretHalo.samples`.
    var samples: (() -> [Float]?)?
    /// Something of the sentence is still on its way: transcribing, held, being typed.
    var stillPending: (() -> Bool)?

    private enum Phase: String { case down, listening, waiting, leaving }
    private var phase: Phase = .down
    private var edge: Edge?
    private var panel: NSPanel?
    private var host: ProjectMHalo?
    private var strip: NSView?
    private var built: (edge: Edge, screen: NSRect, thickness: CGFloat)?
    private var pathTimer: Timer?
    private var feedTimer: Timer?
    private var pollTimer: Timer?
    private var pathClock: Double = 0
    private var pathAt: CFAbsoluteTime = 0
    private var pace: Double = 1
    private var micOpen = false
    private var waitingFrom: CFAbsoluteTime = 0
    private var lastPending: CFAbsoluteTime = 0
    private var turn = 0

    var report: [String: Any] {
        ["phase": phase.rawValue, "edge": edge?.rawValue ?? NSNull(),
         "frame": panel.map { NSStringFromRect($0.frame) } ?? NSNull(),
         "alpha": Double(panel?.alphaValue ?? 0)]
    }

    // MARK: - Pure

    /// The panel: twice the strip's depth, so the swell has room, along `edge` of `screen`.
    static func frame(_ edge: Edge, on screen: NSRect, thickness: CGFloat) -> NSRect {
        switch edge {
        case .top:   return NSRect(x: screen.minX, y: screen.maxY - 2 * thickness, width: screen.width, height: 2 * thickness)
        case .right: return NSRect(x: screen.maxX - 2 * thickness, y: screen.minY, width: 2 * thickness, height: screen.height)
        }
    }

    /// Where the stamp is `t` seconds of its own clock in: `along` 0…1 of the
    /// edge's length, `depth` 0…1 of the strip's thickness away from the edge.
    /// Back and forth, a pass every `sweep` on average, never at an even pace,
    /// and never at the same depth twice running.
    static func stamp(at t: Double, sweep: Double = sweep) -> (along: Double, depth: Double) {
        let u = max(t, 0) / max(sweep, 0.1)
        let phase = u + 0.18 * sin(u * 2.3) + 0.07 * sin(u * 5.1 + 1)
        let tri = abs((phase.truncatingRemainder(dividingBy: 2)) - 1)       // 1 → 0 → 1
        let along = 0.02 + 0.96 * (1 - tri)
        let depth = 0.16 + 0.07 * sin(u * 3.7 + 2) + 0.04 * sin(u * 9.1)
        return (along, depth)
    }

    /// The splat's radius for a puff `points` across on a canvas `height` points
    /// tall: the engine's Gaussian is `exp(-d² / radius)` with `d` in canvas heights.
    static func radius(puff points: CGFloat, canvasHeight height: CGFloat) -> Float {
        let d = Double(points / max(height, 1))
        return Float(2 * d * d)
    }

    // MARK: - The sentence

    /// From `AppDelegate.syncBorrowedGestures`, on every sync. `edge`: the one this
    /// sentence wears while it is being said, nil for any other state of the app.
    func listen(_ wanted: Edge?, micOpen: Bool) {
        self.micOpen = micOpen
        if let wanted {
            if phase == .listening, edge == wanted { return }
            show(wanted)
            return
        }
        guard phase == .listening else { return }
        if micOpen {
            // Still talking, to somewhere else now (🔼 → flipped it to the caret).
            leave(sent: false, why: "the sentence goes elsewhere")
            return
        }
        phase = .waiting
        waitingFrom = CFAbsoluteTimeGetCurrent()
        lastPending = waitingFrom
        startPolling()
        Log.info("🌫️ the \(edge?.rawValue ?? "?") edge stays — until the message is in")
    }

    /// The message is in the terminal (or the new window is open with it).
    func sent() {
        guard phase == .listening || phase == .waiting else { return }
        leave(sent: true, why: "the message is in")
    }

    /// Battery, a cancel that must not wait for the poll.
    func drop(_ why: String) {
        guard phase == .listening || phase == .waiting else { return }
        leave(sent: false, why: why)
    }

    /// `POST /test/edge-dust {"edge": "top"|"right", "seconds": 4, "sent": true, "capturable": true}`:
    /// the edge with no sentence behind it, then the swell (or the quiet end).
    func demo(_ edge: Edge, seconds: Double, sent: Bool, capturable: Bool) {
        Self.capturable = capturable
        teardown()
        show(edge)
        let mine = turn
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.turn == mine else { return }
            self.leave(sent: sent, why: "the demo ends")
        }
    }

    // MARK: - Up and down

    private func show(_ wanted: Edge) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let thickness = Self.thickness
        if let b = built, b.edge != wanted || b.screen != screen.frame || b.thickness != thickness { teardown() }
        guard let p = panel ?? make(wanted, on: screen.frame, thickness: thickness) else { return }
        turn += 1
        edge = wanted
        phase = .listening
        pollTimer?.invalidate(); pollTimer = nil
        pace = 1
        setSwell(1, animated: false)
        p.sharingType = Self.capturable ? .readOnly : .none
        if !p.isVisible { p.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            p.animator().alphaValue = Self.restAlpha
        }
        host?.start()
        if pathTimer == nil { startPath() }
        if feedTimer == nil { startFeeding() }
        p.orderFrontRegardless()
        Log.info("🌫️ the \(wanted.rawValue) edge is up — \(wanted == .top ? "a prompt to a new session" : "a prompt to the bound terminal")")
    }

    private func leave(sent: Bool, why: String) {
        guard let p = panel else { phase = .down; return }
        phase = .leaving
        turn += 1
        let mine = turn
        pollTimer?.invalidate(); pollTimer = nil
        Log.info("🌫️ the \(edge?.rawValue ?? "?") edge goes — \(why)\(sent ? ", swelling first" : "")")
        let out = { [weak self] (span: TimeInterval) in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = span
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: {
                guard let self, self.turn == mine else { return }
                self.settleDown()
            })
        }
        guard sent else { out(Self.quietFade); return }
        pace = 2
        setSwell(2, animated: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.swell
            p.animator().alphaValue = min(1, Self.restAlpha * 2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.swell + Self.swellHold) { [weak self] in
            guard let self, self.turn == mine else { return }
            out(Self.sentFade)
        }
    }

    private func settleDown() {
        phase = .down
        edge = nil
        panel?.orderOut(nil)
        pathTimer?.invalidate(); pathTimer = nil
        feedTimer?.invalidate(); feedTimer = nil
        host?.stop()
        setSwell(1, animated: false)
    }

    private func teardown() {
        turn += 1
        phase = .down
        edge = nil
        pollTimer?.invalidate(); pollTimer = nil
        pathTimer?.invalidate(); pathTimer = nil
        feedTimer?.invalidate(); feedTimer = nil
        panel?.orderOut(nil)
        host?.stop()
        panel = nil; host = nil; strip = nil; built = nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.phase == .waiting else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if self.stillPending?() == true { self.lastPending = now }
            if now - self.lastPending > Self.patience { self.leave(sent: false, why: "nothing of the sentence is on its way") }
            else if now - self.waitingFrom > Self.ceiling { self.leave(sent: false, why: "no confirmation in \(Int(Self.ceiling)) s") }
        }
        pollTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - The picture

    /// The strip twice as deep (or back), about the screen's edge — the content
    /// view's `sublayerTransform`, as `CaretHalo`'s dock scales its content.
    private func setSwell(_ k: CGFloat, animated: Bool) {
        guard let layer = panel?.contentView?.layer, let b = built else { return }
        let t = b.thickness
        // The edge is `t` from the content's middle, on the axis that swells.
        var m = CATransform3DIdentity
        switch b.edge {
        case .top:
            m = CATransform3DTranslate(m, 0, t, 0); m = CATransform3DScale(m, 1, k, 1); m = CATransform3DTranslate(m, 0, -t, 0)
        case .right:
            m = CATransform3DTranslate(m, t, 0, 0); m = CATransform3DScale(m, k, 1, 1); m = CATransform3DTranslate(m, -t, 0, 0)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let a = CABasicAnimation(keyPath: "sublayerTransform")
            a.fromValue = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
            a.toValue = m
            a.duration = Self.swell
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(a, forKey: "swell")
        } else {
            layer.removeAnimation(forKey: "swell")
        }
        layer.sublayerTransform = m
        CATransaction.commit()
    }

    /// The stamp at 60 a second, on a clock that the swell runs twice as fast.
    private func startPath() {
        pathAt = CFAbsoluteTimeGetCurrent()
        place()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CFAbsoluteTimeGetCurrent()
            self.pathClock += (now - self.pathAt) * self.pace
            self.pathAt = now
            self.place()
        }
        pathTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// The stamp in the strip's points, y down from its top.
    private func place() {
        guard let host, let b = built else { return }
        let s = Self.stamp(at: pathClock)
        let t = Double(b.thickness)
        switch b.edge {
        case .top:   host.center(CGPoint(x: s.along * Double(b.screen.width), y: s.depth * t))
        case .right: host.center(CGPoint(x: t - s.depth * t, y: s.along * Double(b.screen.height)))
        }
    }

    private func startFeeding() {
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let host = self.host else { return }
            let live = self.micOpen ? (self.samples?() ?? nil) : nil
            host.feed(CaretHalo.lift(CaretHalo.undoInputGain(live ?? [Float](repeating: 0, count: 1024))))
        }
        feedTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func make(_ edge: Edge, on screen: NSRect, thickness: CGFloat) -> NSPanel? {
        guard let preset = HaloStyle.smoke.preset, ProjectMHalo.available(for: preset) else {
            Log.error("🌫️ no edge — the dust cannot be drawn")
            return nil
        }
        let frame = Self.frame(edge, on: screen, thickness: thickness)
        // The strip: the half of the panel on the screen's edge.
        let box: NSRect
        let canvas: CGSize
        switch edge {
        case .top:
            box = NSRect(x: 0, y: thickness, width: frame.width, height: thickness)
            canvas = CGSize(width: frame.width, height: thickness)
        case .right:
            box = NSRect(x: thickness, y: 0, width: thickness, height: frame.height)
            canvas = CGSize(width: thickness, height: frame.height)
        }
        guard let engine = ProjectMHalo(preset: preset, side: (thickness * preset.scale).rounded(), screen: canvas) else { return nil }
        engine.tunes = false
        // The engine's force is per canvas width; the stamp travels the long side.
        let long = max(canvas.width, canvas.height) * ProjectMHalo.renderScale
        engine.fluidOverrides = [
            Int32(PMH_FLUID_RADIUS): Self.radius(puff: Self.puff, canvasHeight: canvas.height),
            Int32(PMH_FLUID_GAIN): Float(Self.knob("gain", 0.35)),
            Int32(PMH_FLUID_FADE): Float(Self.knob("fade", 1.4)),
            Int32(PMH_FLUID_FORCE): Float(Self.knob("force", 1)) * 5 * Float(long),
            Int32(PMH_FLUID_OPACITY): 1,
        ]
        engine.onFailure = { why in Log.error("🌫️ the edge's dust failed: \(why)") }
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.autoresizesSubviews = false
        let strip = NSView(frame: box)
        strip.wantsLayer = true
        engine.frame = NSRect(origin: .zero, size: box.size)
        strip.addSubview(engine)
        // To nothing away from the edge, and at the strip's two ends.
        let away = CAGradientLayer()
        away.frame = strip.bounds
        away.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        away.locations = [0, 0.3, 1]
        switch edge {
        case .top:   away.startPoint = CGPoint(x: 0.5, y: 1); away.endPoint = CGPoint(x: 0.5, y: 0)
        case .right: away.startPoint = CGPoint(x: 1, y: 0.5); away.endPoint = CGPoint(x: 0, y: 0.5)
        }
        strip.layer?.mask = away
        content.addSubview(strip)
        p.contentView = content
        p.setFrame(frame, display: false)
        panel = p
        host = engine
        self.strip = strip
        built = (edge, screen, thickness)
        pathClock = Double.random(in: 0..<20)
        return p
    }
}
