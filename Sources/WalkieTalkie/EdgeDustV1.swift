import AppKit
import CProjectM

/// **Variant 1: the pointer's own Smoke, risen from the whole edge at once** — the
/// real solver (`pmhalo.cpp`, mode 6) on a canvas the size of the strip, as the
/// first `EdgeDust` had it (`a3421cfd`), without the stamp that swept the edge
/// (*"nothing should travel along the edge"*).
///
/// - **One puff = the pointer lifted, put down beside the place, and jumped onto
///   it** (`liftPointer` → `center(from)` → `center(at)`, in that order on the render
///   queue, so the engine's next frame sees exactly one move and splats once, at
///   `at`). Nothing is drawn between two puffs: a lifted pointer has no stroke.
/// - **Where**: the edge is cut into cells of ~`pitch` points and each round visits
///   every cell once in a shuffled order, a random spot inside it — the whole length
///   is covered evenly and no order can be read as travel. A third of the puffs are
///   a second splat a few points from the last, so a puff is not always a round blob.
/// - **The jump's length is not what is seen; it is two numbers the engine reads.**
///   Its length in canvas *widths* per second sets how much the move counts
///   (`motionKnee`: s³/(s³+0.5³)) — the top strip is 16 widths of the right one, so
///   the same 20 pt would be worth 2 % there and 100 % here. Every jump is therefore
///   `speed` widths a second long (1.2 → 93 %) on both, the excess laid *along* the
///   edge. And its component *away from the edge* is the push: the engine's force is
///   per canvas side, so across the strip a point moved is worth `force / thickness`
///   on both orientations, and along it next to nothing — the smoke is blown out of
///   the edge and curls back, it is not carried along it.
/// - **Rate ∝ length** (one puff a second per `perSecond` points of edge), so both
///   edges are as dense; `setIntensity(2)` doubles it. Never more than one a frame.
/// - **The voice** goes to the engine as it is: its puffs come out of wherever the
///   last puff landed, so they wander the edge too.
///
/// Knobs (`defaults write … edgeDust.smoke.<key>`), read when the strip is built:
/// `gain` 0.55, `fade` 1.1 (per second), `size` 11 (the splat's σ, points),
/// `kick` 110 (points a second, the push out of the edge), `perSecond` 115, `pitch` 60.
final class EdgeDustV1: EdgeDustPicture {
    static let title = "Real smoke"

    private static func knob(_ key: String, _ standard: Double) -> Double {
        UserDefaults.standard.object(forKey: "edgeDust.smoke.\(key)") as? Double ?? standard
    }

    private let engine: ProjectMHalo
    private let edge: EdgeDust.Edge
    /// The strip, in points: along the edge and away from it.
    private let length: CGFloat
    private let thickness: CGFloat
    /// The canvas's height in points — the engine's splat radius is in these.
    private let canvasHeight: CGFloat
    /// How long a jump must be, in points, to count as `speed` widths a second.
    private let jump: CGFloat
    private let size: CGFloat
    private let rate: Double
    private let frame: TimeInterval
    private let cells: Int

    private var timer: Timer?
    private var intensity: Double = 1
    private var owed: Double = 0
    private var tickAt: CFAbsoluteTime = 0
    private var lastPuffAt: CFAbsoluteTime = 0
    private var order: [Int] = []
    private var last: (along: CGFloat, depth: CGFloat)?

    /// A jump of `speed` canvas widths a second counts for this much (the engine's
    /// `motionKnee` 0.5, cubed); the push is that × `motionBoost` 1.5.
    private static let speed: Double = 1.2
    private static var weight: Double { let s3 = speed * speed * speed; return s3 / (s3 + 0.125) }
    /// The push `kick` is tuned at: this many points of the jump are across the strip.
    private static let reach: ClosedRange<CGFloat> = 10...26

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard var preset = HaloStyle.smoke.preset, ProjectMHalo.available(for: preset) else { return nil }
        // A fluid opens on a clear canvas: there is no first picture to hide for 1.5 s.
        preset.warmup = 0.3
        let box = strip.bounds
        self.edge = edge
        switch edge {
        case .top:   length = box.width;  thickness = box.height
        case .right: length = box.height; thickness = box.width
        }
        guard length > 40, thickness > 20,
              let engine = ProjectMHalo(preset: preset, side: (thickness * preset.scale).rounded(), screen: box.size) else { return nil }
        self.engine = engine
        canvasHeight = box.height
        let fps = Double(haloFrameCap > 0 ? haloFrameCap : 60)
        frame = 1 / fps
        jump = CGFloat(Self.speed / fps) * box.width
        size = CGFloat(Self.knob("size", 11))
        rate = Double(length) / max(20, Self.knob("perSecond", 115))
        cells = max(4, Int((Double(length) / max(20, Self.knob("pitch", 60))).rounded()))

        engine.tunes = false
        // Velocity is in solver cells a second (a cell = 4 canvas pixels), and a
        // point moved across the strip is worth force / thickness of them.
        let scale = Double(ProjectMHalo.renderScale)
        let mid = Double((Self.reach.lowerBound + Self.reach.upperBound) / 2)
        let force = Self.knob("kick", 110) * scale / 4 * Double(thickness) / (mid * Self.weight * 1.5)
        engine.fluidOverrides = [
            Int32(PMH_FLUID_RADIUS): radius(size),
            Int32(PMH_FLUID_GAIN): Float(Self.knob("gain", 0.55)),
            Int32(PMH_FLUID_FADE): Float(Self.knob("fade", 1.1)),
            Int32(PMH_FLUID_FORCE): Float(force),
            Int32(PMH_FLUID_OPACITY): 1,
        ]
        engine.onFailure = { why in Log.error("🌫️ the edge's smoke failed: \(why)") }
        engine.frame = box
        strip.addSubview(engine)
    }

    func start() {
        engine.start()
        timer?.invalidate()
        owed = 1
        last = nil
        tickAt = CFAbsoluteTimeGetCurrent()
        lastPuffAt = 0
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        engine.stop()
    }

    func feed(_ samples: [Float]) { engine.feed(samples) }

    func setIntensity(_ k: CGFloat) { intensity = Double(max(0, k)) }

    // MARK: - The puffs

    /// The engine's Gaussian is `exp(-d² / radius)`, `d` in canvas heights.
    private func radius(_ sigma: CGFloat) -> Float {
        let d = Double(sigma / max(canvasHeight, 1))
        return Float(2 * d * d)
    }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        owed = min(3, owed + min(now - tickAt, 0.1) * rate * intensity)
        tickAt = now
        // Two puffs inside one engine frame are one: the second lifts the first away.
        guard owed >= 1, now - lastPuffAt >= frame * 0.95 else { return }
        owed -= 1
        lastPuffAt = now
        puff()
    }

    private func puff() {
        var along: CGFloat, depth: CGFloat
        if let l = last, Int.random(in: 0..<3) == 0 {
            // A second splat beside the last one, a little further out.
            let a = CGFloat.random(in: -1...1) * 0.9
            let r = CGFloat.random(in: 9...16)
            along = l.along + sin(a) * r * (Bool.random() ? 1 : -1)
            depth = l.depth + cos(a) * r
            last = nil
        } else {
            if order.isEmpty { order = Array(0..<cells).shuffled() }
            let cell = CGFloat(order.removeLast())
            along = (cell + CGFloat.random(in: 0...1)) / CGFloat(cells) * length
            depth = CGFloat.random(in: 6...30)
            last = (along, depth)
        }
        along = min(max(along, 0), length)
        depth = min(max(depth, 4), thickness * 0.55)
        // The jump: `across` out of the edge (now and then a weak one back into
        // it, which spreads along the glass), the rest of its length along it.
        var across = CGFloat.random(in: Self.reach)
        if Int.random(in: 0..<7) == 0 { across *= -0.4 }
        let rest = max(0, jump * jump - across * across).squareRoot() * (Bool.random() ? 1 : -1)
        let at = point(along: along, depth: depth)
        let from = point(along: along - rest, depth: depth - across)
        engine.setFluid(Int32(PMH_FLUID_RADIUS), radius(size * CGFloat.random(in: 0.75...1.35)))
        engine.liftPointer()
        engine.center(from)
        engine.center(at)
    }

    /// The canvas's points, y down from its top; the screen's edge is the top
    /// strip's top side and the right strip's right side.
    private func point(along: CGFloat, depth: CGFloat) -> CGPoint {
        switch edge {
        case .top:   return CGPoint(x: along, y: depth)
        case .right: return CGPoint(x: thickness - depth, y: along)
        }
    }
}
