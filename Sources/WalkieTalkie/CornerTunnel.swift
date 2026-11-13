import AppKit
import CProjectM

/// **While the words are transcribed, the atom's corner plays Reverse tunnel on
/// the take, backwards** (2026-11-10, Victor: *"în locul acelui atom din colțul
/// ecranului … unde [e] panoul de prompt preview, pune-i efectul de reverse
/// tunnel, redând audio înregistrat pentru [propoziția] care acum se transcrie"*).
///
/// The 2026-11-09 quiet settle stands: the wave wipes every effect off the screen
/// and nothing rides the pointer or flies to a window until the words land. This is
/// the one picture of the transcription, and it stays in the corner the prompt
/// lives in — `PromptAtom.home`, the box Victor drew — not over his page.
///
/// - **The rewind's sound, not the rewind's geometry.** The take snapshotted at the
///   close, read backwards at `take / DecodeRate.predict` × (1…8×) and looped, as
///   `CaretHalo.setRewind` feeds it; nothing is played aloud.
/// - **A square of its own engine** (`ProjectMHalo`, the Reverse tunnel preset with
///   no trail canvas): the halo's panel is the screen and belongs to the pointer,
///   and the wave has just wiped it. Here the picture is a `side`-point square on
///   the atom's centre, its ring about the atom's size.
/// - **In the atom's place, as long as the atom would have been there.** Up from the
///   close (`settle`), and kept through the held prompt (`hold`, from
///   `RelayWindow.syncPromptAtom`), which then shows no atom. The atom comes back
///   only where there is no take to play: a typed prompt, a test route, a take
///   under half a second, battery.
/// - Click-through, `sharingType = .none` (`capturable` for a desk shot), one level
///   above the chip's panel — as the atom.
///
/// **Three dresses for that corner since 2026-11-13** (Victor: *"I wanted to go back
/// to the Atom. Or also maybe try the dust effect that moves like a loading icon,
/// not perfectly regular … moving on a circle … within the area of the current
/// reverse tunnel effect"*) — `Dress`, picked under `𝓯𝔁 ▸ Transcribing`:
/// - **Dust** (the default, the one to try): his caret Smoke on a canvas of its own,
///   `side` points square, its stamp driven round `dustPoint` — a loading icon whose
///   pace and radius wander. Fed the same take, backwards.
/// - **Reverse tunnel**: the 2026-11-10 picture, unchanged.
/// - **Atom**: nothing of this class is drawn; the atom is back for the held prompt
///   and the settle shows nothing in the corner (what `WT_CORNER_TUNNEL=0` did and
///   still does).
final class CornerTunnel {
    enum Dress: String, CaseIterable {
        case dust, tunnel, atom
        var title: String {
            switch self {
            case .dust:   return "Dust"
            case .tunnel: return "Reverse tunnel"
            case .atom:   return "Atom"
            }
        }
    }
    static let dressKey = "cornerFx"
    /// `WT_CORNER_TUNNEL=0` (atom) and `WT_CORNER_FX=dust|tunnel|atom` win for a run.
    static var dress: Dress {
        let env = ProcessInfo.processInfo.environment
        if env["WT_CORNER_TUNNEL"] == "0" { return .atom }
        if let forced = env["WT_CORNER_FX"].flatMap(Dress.init(rawValue:)) { return forced }
        return UserDefaults.standard.string(forKey: dressKey).flatMap(Dress.init(rawValue:)) ?? .dust
    }
    /// The menu's pick: written, and whatever stands in the corner rebuilt in it.
    static func setDress(_ new: Dress) {
        guard new != dress else { return }
        UserDefaults.standard.set(new.rawValue, forKey: dressKey)
        Log.info("🌀 the corner's dress: \(new.rawValue)")
        current?.redress()
    }
    static var off: Bool { dress == .atom }
    /// The picture's square. The tunnel's ring is ~0.66 of it — the atom's rings are
    /// 0.88 of 170 pt, so 230 pt puts the two the same size.
    static let side: CGFloat = 230
    /// A desk's switch, as on `PromptAtom`.
    static var capturable = false

    private static let minSamples = 8000          // half a second at 16 kHz, as the rewind
    private static let maxSpeed: Double = 8
    private static let fadeOut: TimeInterval = 0.3

    private var panel: NSPanel?
    private var host: ProjectMHalo?
    /// What `panel` was built to draw; another pick builds another.
    private var built: Dress?
    private var feedTimer: Timer?
    /// The dust's stamp, moved round `dustPoint` at the display's pace.
    private var pathTimer: Timer?
    private var pathFrom: CFAbsoluteTime = 0
    /// The engine's loop is on (`start`), until a fade-out completes.
    private var running = false

    private var take: [Float] = []
    private var takeFrom: CFAbsoluteTime = 0
    private var speed: Double = 1

    private var settling = false
    private var settleEndedAt: CFAbsoluteTime = 0
    private var holding = false
    /// The held prompt has taken this take: it plays until the prompt goes.
    private var claimed = false
    private(set) var up = false
    private var home: NSRect?
    /// Bumped by every show and hide, so a late fade orders nothing out.
    private var turn = 0

    /// For `GET /test/state`.
    var report: [String: Any] {
        ["up": up, "dress": Self.dress.rawValue, "settling": settling, "holding": holding, "claimed": claimed,
         "takeSeconds": Double(take.count) / 16000, "speed": speed,
         "frame": panel.map { NSStringFromRect($0.frame) } ?? NSNull()]
    }

    // MARK: - Pure

    /// The square on the atom's centre.
    static func frame(onAtom atom: NSRect) -> NSRect {
        NSRect(x: (atom.midX - side / 2).rounded(), y: (atom.midY - side / 2).rounded(), width: side, height: side)
    }

    /// The take's backwards speed, fitted to this engine's typical round trip.
    static func speed(takeSeconds: Double, predicted: Double) -> Double {
        min(max(takeSeconds / max(predicted, 0.5), 1), maxSpeed)
    }

    /// `count` samples of `take` read backwards from `elapsed` seconds in, `speed`
    /// samples of the take apart, wrapping so it loops. `CaretHalo.rewindWindow`'s rule.
    static func window(of take: [Float], elapsed: Double, speed: Double, count: Int = 1024) -> [Float] {
        let n = take.count
        guard n > 0 else { return [Float](repeating: 0, count: count) }
        let now = elapsed * 16000
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let k = now - Double(count - 1 - i)
            let back = Int((max(k, 0) * speed).rounded(.down)) % n
            out[i] = take[n - 1 - back]
        }
        return out
    }

    /// **The dust's own size and brightness.** His Smoke sliders are set for a
    /// screen (`Size` 0.0012 of it): on a 230-point canvas that was a wisp a few
    /// points across, seen on the first desk shot. `cornerDust.radius|gain|fade|opacity`
    /// in the defaults try others; the demo route rebuilds, so no restart is needed.
    /// **The canvas is `dustGrain` times the square, shown at the square's size.**
    /// Smoke's solver grid is a quarter of its canvas: at 230 px that is 57 cells,
    /// drawn as 4-point blocks (the second desk shot). `cornerDust.grain` tries another.
    static var dustGrain: CGFloat {
        (UserDefaults.standard.object(forKey: "cornerDust.grain") as? Double).map { CGFloat(max(1, min($0, 6))) } ?? 3
    }
    static var dustKnobs: [Int32: Float] {
        let d = UserDefaults.standard
        func knob(_ key: String, _ standard: Float) -> Float {
            (d.object(forKey: "cornerDust.\(key)") as? Double).map(Float.init) ?? standard
        }
        return [Int32(PMH_FLUID_RADIUS): knob("radius", 0.003), Int32(PMH_FLUID_GAIN): knob("gain", 0.35),
                Int32(PMH_FLUID_FADE): knob("fade", 0.9), Int32(PMH_FLUID_OPACITY): knob("opacity", 1)]
    }
    /// One lap of the dust's ring, on average.
    static let dustLap: TimeInterval = 1.6
    /// **Where the dust's stamp is `t` seconds in** — points in the square, y down.
    /// Clockwise, a lap every `dustLap` on average, but *"not perfectly regular"*:
    /// the pace wanders between half and one and a half times that (never back),
    /// and the ring breathes between 0.15 and 0.25 of the side, so no two laps
    /// draw the same circle. The periods share no small multiple.
    static func dustPoint(at t: Double, side: CGFloat = side) -> CGPoint {
        let lap = 2 * Double.pi * max(t, 0) / dustLap
        let angle = lap + 0.45 * sin(lap * 0.37) + 0.25 * sin(lap * 1.31 + 1)
        let r = Double(side) * 0.2 * (1 + 0.16 * sin(lap * 0.53 + 2) + 0.09 * sin(lap * 1.9))
        return CGPoint(x: Double(side) / 2 + r * cos(angle), y: Double(side) / 2 + r * sin(angle))
    }

    // MARK: - The two reasons to be up

    /// From `AppDelegate.syncBorrowedGestures`: the words are being transcribed.
    /// `take` is read only on the rising edge.
    func settle(_ on: Bool, take: @autoclosure () -> [Int16]) {
        guard on != settling else { return }
        settling = on
        if on {
            let samples = take()
            claimed = false
            guard !Self.off, samples.count >= Self.minSamples else {
                self.take = []
                if !Self.off { Log.info("🌀 no corner tunnel — only \(samples.count) samples in the take") }
                sync()
                return
            }
            self.take = samples.map { Float($0) / 32768 }
            let seconds = Double(samples.count) / 16000
            speed = Self.speed(takeSeconds: seconds, predicted: DecodeRate.predict(audio: seconds))
            takeFrom = CFAbsoluteTimeGetCurrent()
            // Where the prompt will stand: the pointer's screen, as `showSentPrompt` picks it.
            if let screen = RelayWindow.screenUnderMouse() ?? NSScreen.main {
                home = PromptAtom.home(in: screen.visibleFrame)
            }
            Log.info(String(format: "🌀 the corner tunnel: %.1f s of his voice, backwards at %.1f×", seconds, speed))
        } else {
            settleEndedAt = CFAbsoluteTimeGetCurrent()
        }
        sync()
    }

    /// From `RelayWindow.syncPromptAtom`: the prompt rests in the corner. Answers
    /// whether the tunnel stands there in the atom's place.
    @discardableResult
    func hold(_ on: Bool, atom: NSRect) -> Bool {
        if on {
            // Only this sentence's take: still settling, just landed, or already ours.
            let fresh = settling || claimed || CFAbsoluteTimeGetCurrent() - settleEndedAt < 3
            guard !Self.off, !take.isEmpty, fresh else {
                if holding { holding = false; sync() }
                return false
            }
            claimed = true
            home = atom
        }
        if holding != on { holding = on; sync() }
        return on
    }

    /// From `RelayWindow.syncPromptAtom` once no prompt rests: the take is spent.
    func release() {
        guard claimed || holding else { return }
        claimed = false
        holding = false
        if !settling { take = [] }
        sync()
    }

    /// Battery, a ⚡ question: down now, whatever the reasons.
    var held = false { didSet { if held != oldValue { sync() } } }

    // MARK: - The desk

    /// The live instance, for `POST /test/corner-tunnel`.
    static weak var current: CornerTunnel?
    init() { Self.current = self }

    /// `POST /test/corner-tunnel {"on": true, "capturable": true, "seconds": 6}`: a
    /// settle with a synthetic take (syllables of a 140 Hz voice, 4 a second) and
    /// no sentence behind it — the only way to see it without dictating.
    func demo(_ on: Bool, seconds: Double = 6, capturable: Bool = false) {
        Self.capturable = capturable
        panel?.sharingType = capturable ? .readOnly : .none
        guard on else { settle(false, take: []); return }
        teardown()      // a desk's run reads the knobs afresh
        let n = Int(seconds * 16000)
        let take: [Int16] = (0..<n).map { i in
            let t = Double(i) / 16000
            let syllable = max(0, sin(2 * .pi * 4 * t))
            let voice = sin(2 * .pi * 140 * t) + 0.5 * sin(2 * .pi * 280 * t) + 0.25 * sin(2 * .pi * 560 * t)
            return Int16(max(-32767, min(32767, 9000 * syllable * voice)))
        }
        settle(false, take: [])
        settle(true, take: take)
    }

    // MARK: - Up and down

    /// Another dress was picked: what is up goes at once, and comes back in it.
    private func redress() {
        teardown()
        if Self.off { settling = false; holding = false; claimed = false; take = [] }
        sync()
    }

    private func teardown() {
        up = false
        turn += 1
        panel?.orderOut(nil)
        feedTimer?.invalidate(); feedTimer = nil
        pathTimer?.invalidate(); pathTimer = nil
        host?.stop()
        running = false
        panel = nil; host = nil; built = nil
    }

    private func sync() {
        let wanted = (settling || holding) && !take.isEmpty && !held && home != nil && !Self.off
        if wanted { show() } else { hide() }
    }

    private func show() {
        guard let home else { return }
        let target = Self.frame(onAtom: home)
        if up {
            if panel?.frame != target { panel?.setFrame(target, display: false) }
            return
        }
        if panel != nil, built != Self.dress { teardown() }
        guard let p = panel ?? make() else { return }
        up = true
        turn += 1
        p.sharingType = Self.capturable ? .readOnly : .none
        p.setFrame(target, display: false)
        // Animated, so it cancels a fade-out still in flight (a hover on the dialog
        // and off again): a plain `alphaValue = 1` loses to the running animator.
        if !p.isVisible { p.alphaValue = 0 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        if built == .dust, pathTimer == nil { startCircling() }
        if !running { host?.start(); running = true }
        if feedTimer == nil { startFeeding() }
        p.orderFrontRegardless()
        Log.info(String(format: "🌀 the corner \(built == .dust ? "dust" : "tunnel") is up at (%.0f, %.0f)%@", target.midX, target.midY,
                        holding ? " — in the atom's place" : " — the words are being transcribed"))
    }

    private func hide() {
        guard up, let p = panel else { return }
        up = false
        turn += 1
        let hiding = turn
        Log.info("🌀 the corner tunnel goes")
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.turn == hiding else { return }
            p.orderOut(nil)
            self.feedTimer?.invalidate(); self.feedTimer = nil
            self.pathTimer?.invalidate(); self.pathTimer = nil
            self.host?.stop()
            self.running = false
        })
    }

    private func startFeeding() {
        feedTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let host = self.host else { return }
            let window = Self.window(of: self.take, elapsed: CFAbsoluteTimeGetCurrent() - self.takeFrom, speed: self.speed)
            host.feed(CaretHalo.lift(CaretHalo.undoInputGain(window)))
        }
        feedTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// The stamp goes round at 60 a second — the engine's own pace, so the fluid is
    /// stirred every frame — from where the ring starts, each time it comes up.
    private func startCircling() {
        pathFrom = CFAbsoluteTimeGetCurrent()
        host?.center(Self.dustPoint(at: 0, side: Self.side * Self.dustGrain))
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, let host = self.host else { return }
            host.center(Self.dustPoint(at: CFAbsoluteTimeGetCurrent() - self.pathFrom, side: Self.side * Self.dustGrain))
        }
        pathTimer = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// The engine for the picked dress. **Reverse tunnel**: its own preset as a
    /// square, no trail canvas, so the engine renders `side` points and nothing
    /// more. **Dust**: Smoke, whose canvas — the screen, at the pointer — is this
    /// square, so the same solver draws a ring that fits the corner; his saved
    /// Smoke sliders apply, the tuner panel is not taken from the pointer's halo.
    private func engine(for dress: Dress, box: NSRect) -> ProjectMHalo? {
        switch dress {
        case .atom: return nil
        case .tunnel:
            guard var preset = HaloStyle.milkdrop7Reversed.preset else { return nil }
            preset.trail = 0
            preset.lag = 0
            let screen = (NSScreen.main?.frame.size) ?? box.size
            return ProjectMHalo(preset: preset, side: Self.side, screen: screen)
        case .dust:
            guard let preset = HaloStyle.smoke.preset else { return nil }
            let canvas = CGSize(width: box.width * Self.dustGrain, height: box.height * Self.dustGrain)
            let engine = ProjectMHalo(preset: preset, side: (Self.side * preset.scale).rounded(), screen: canvas)
            engine?.tunes = false
            engine?.fluidOverrides = Self.dustKnobs
            return engine
        }
    }

    private func make() -> NSPanel? {
        let dress = Self.dress
        let box = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        guard let engine = engine(for: dress, box: box) else {
            Log.error("🌀 nothing in the corner — \(dress.rawValue) cannot be drawn")
            return nil
        }
        engine.onFailure = { why in Log.error("🌀 the corner tunnel failed: \(why)") }
        let p = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: box)
        view.wantsLayer = true
        engine.frame = box
        view.addSubview(engine)
        // **Round, never a square's edge**: the preset's own fade reaches the square's
        // sides with ink still on them (seen on the first desk shot, a straight cut on
        // the right). A radial mask takes it to nothing inside the inscribed circle.
        let round = CAGradientLayer()
        round.type = .radial
        round.frame = box
        round.startPoint = CGPoint(x: 0.5, y: 0.5)
        round.endPoint = CGPoint(x: 1, y: 1)
        round.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        round.locations = [0, 0.62, 1]
        view.layer?.mask = round
        p.contentView = view
        panel = p
        built = dress
        host = engine
        return p
    }
}
