import AppKit

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
/// `WT_CORNER_TUNNEL=0` turns it off: the atom is back for the held prompt and the
/// settle shows nothing in the corner.
final class CornerTunnel {
    static let off = ProcessInfo.processInfo.environment["WT_CORNER_TUNNEL"] == "0"
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
    private var feedTimer: Timer?
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
        ["up": up, "settling": settling, "holding": holding, "claimed": claimed,
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

    private func sync() {
        let wanted = (settling || holding) && !take.isEmpty && !held && home != nil
        if wanted { show() } else { hide() }
    }

    private func show() {
        guard let home else { return }
        let target = Self.frame(onAtom: home)
        if up {
            if panel?.frame != target { panel?.setFrame(target, display: false) }
            return
        }
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
        if !running { host?.start(); running = true }
        if feedTimer == nil { startFeeding() }
        p.orderFrontRegardless()
        Log.info(String(format: "🌀 the corner tunnel is up at (%.0f, %.0f)%@", target.midX, target.midY,
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

    /// Reverse tunnel's own preset, as a square: no trail canvas, so the engine
    /// renders `side` points and nothing more.
    private func make() -> NSPanel? {
        guard var preset = HaloStyle.milkdrop7Reversed.preset else { return nil }
        preset.trail = 0
        preset.lag = 0
        let box = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let screen = (NSScreen.main?.frame.size) ?? box.size
        guard let engine = ProjectMHalo(preset: preset, side: Self.side, screen: screen) else {
            Log.error("🌀 no corner tunnel — the Reverse tunnel preset cannot be drawn")
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
        host = engine
        return p
    }
}
