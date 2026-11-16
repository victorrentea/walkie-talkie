import AppKit

/// **Variant 2 of the prompt's edge: emitter smoke** (2026-11-16). The pointer's
/// Smoke (`kSmoke` in `pmhalo.cpp`: puffs of one colour each, additive where they
/// overlap, gone in a second or two) laid along an edge with no fluid behind it —
/// one `CAEmitterLayer`, nothing per frame in this app.
///
/// - **Puffs, not grains**: four 128 px sprites made once (value noise, warped,
///   under a warped radial falloff — lobes and holes, no disc), white, tinted by
///   the cell. Born `near`…`far` points from the edge all along it, ~32 pt wide
///   and faint, growing to ~105 pt while they fade to nothing *before* they die
///   (`alphaSpeed` ends every one of them ahead of its lifetime: no pop at the
///   end; the pop at birth is a small faint blob under the fog of the others).
/// - **Nothing travels**: a few points a second away from the edge, any direction
///   within ±100°, a slow spin and a sideways pull that differs per cell — two
///   colours side by side shear past each other, which is all the turbulence there is.
/// - **Many colours, never white**: six cells, six hues, each ±0.18 per channel.
/// - **The voice**: the RMS of `feed`, eased (fast up, slow down), raises the
///   layer's `birthRate` and `velocity`. Silence is the calm base, never empty.
final class EdgeDustV2: EdgeDustPicture {
    static let title = "Emitter smoke"

    /// Puffs born a second per 100 pt of edge, at rest and in silence.
    private static let per100: Double = 4.2
    /// The band the puffs are born in, in points from the edge.
    private static let near: CGFloat = 10, far: CGFloat = 40
    /// The layer's `birthRate` in silence / with a full voice (× the intensity).
    private static let calm: Float = 0.75, loud: Float = 1.9
    /// The layer's `velocity` in silence / with a full voice.
    private static let still: Float = 1, lively: Float = 3.2

    private let smoke = CAEmitterLayer()
    private var running = false
    private var intensity: Float = 1
    private var level: Float = 0
    private var sentRate: Float = -1
    private var sentVelocity: Float = -1

    // MARK: - The sprites

    private struct Rng {
        var s: UInt64
        mutating func next() -> Float {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Float((s >> 40) & 0xFFFFFF) / Float(0x1000000)
        }
    }

    private static let puffs: [CGImage] = (1...4).compactMap { puff(seed: UInt64($0)) }

    /// One wispy puff: white, premultiplied, to nothing well inside its square.
    private static func puff(seed: UInt64, px: Int = 128) -> CGImage? {
        var rng = Rng(s: seed &* 0x9E3779B97F4A7C15 &+ 77)
        let g = 9
        var lattice = [Float](repeating: 0, count: g * g * 2)
        for i in lattice.indices { lattice[i] = rng.next() }
        func noise(_ x: Float, _ y: Float, _ plane: Int) -> Float {
            let fx = x.rounded(.down), fy = y.rounded(.down)
            let xf = x - fx, yf = y - fy
            let x0 = ((Int(fx) % g) + g) % g, y0 = ((Int(fy) % g) + g) % g
            let x1 = (x0 + 1) % g, y1 = (y0 + 1) % g
            let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
            let o = plane * g * g
            let a = lattice[o + y0 * g + x0], b = lattice[o + y0 * g + x1]
            let c = lattice[o + y1 * g + x0], d = lattice[o + y1 * g + x1]
            let top = a + (b - a) * u, bottom = c + (d - c) * u
            return top + (bottom - top) * v
        }
        func fbm(_ x: Float, _ y: Float, _ plane: Int) -> Float {
            var sum: Float = 0, amp: Float = 0.5, f: Float = 1
            for _ in 0..<4 { sum += amp * noise(x * f, y * f, plane); amp *= 0.5; f *= 2.03 }
            return sum / 0.9375
        }
        var bytes = [UInt8](repeating: 0, count: px * px * 4)
        let ox = rng.next() * 7, oy = rng.next() * 7
        for j in 0..<px {
            for i in 0..<px {
                let nx = (Float(i) + 0.5) / Float(px) * 2 - 1, ny = (Float(j) + 0.5) / Float(px) * 2 - 1
                // Warp the lookup so the lobes curl, and the radius so the outline is not a disc.
                let wx = fbm(nx * 1.3 + ox + 3.1, ny * 1.3 + oy, 1) - 0.5
                let wy = fbm(nx * 1.3 + ox, ny * 1.3 + oy + 5.7, 1) - 0.5
                let r = (nx * nx + ny * ny).squareRoot() * (1 + 0.9 * wx)
                let fall = max(0, 1 - r * 1.08)
                let edge = fall * fall * (3 - 2 * fall)
                let n = fbm(nx * 1.6 + ox + wx * 2.2, ny * 1.6 + oy + wy * 2.2, 0)
                let wisp = min(max((n - 0.30) / 0.45, 0), 1)
                let a = edge * edge * (0.25 + 0.75 * wisp * wisp * (3 - 2 * wisp))
                let v = UInt8(min(max(a, 0), 1) * 255)
                let o = (j * px + i) * 4
                bytes[o] = v; bytes[o + 1] = v; bytes[o + 2] = v; bytes[o + 3] = v
            }
        }
        return bytes.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    // MARK: - The picture

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard let host = strip.layer, Self.puffs.count == 4 else { return nil }
        let box = strip.bounds
        let band = Self.far - Self.near
        let middle = (Self.near + Self.far) / 2
        smoke.frame = box
        smoke.emitterShape = .rectangle
        smoke.emitterMode = .surface
        smoke.renderMode = .additive
        smoke.seed = UInt32.random(in: 1...UInt32.max)
        let length: CGFloat
        let inward: CGFloat          // the direction away from the edge
        let along: (CGFloat) -> (x: CGFloat, y: CGFloat)   // a pull along the edge
        switch edge {
        case .top:
            length = box.width
            smoke.emitterPosition = CGPoint(x: box.midX, y: box.maxY - middle)
            smoke.emitterSize = CGSize(width: box.width, height: band)
            inward = -.pi / 2
            along = { ($0, 0) }
        case .right:
            length = box.height
            smoke.emitterPosition = CGPoint(x: box.maxX - middle, y: box.midY)
            smoke.emitterSize = CGSize(width: band, height: box.height)
            inward = .pi
            along = { (0, $0) }
        }
        let rate = EdgeDust.birthRate(edgeLength: length, per100: Self.per100)
        // (red, green, blue), the sprite, spin rad/s, pull along the edge pt/s², growth ×
        let looks: [(CGFloat, CGFloat, CGFloat, Int, CGFloat, CGFloat, CGFloat)] = [
            (1.00, 0.34, 0.46, 0, 0.22, 1.6, 1.00),    // rose
            (1.00, 0.66, 0.24, 1, -0.16, -1.1, 0.85),  // amber
            (0.34, 0.96, 0.52, 2, 0.12, 0.7, 1.10),    // green
            (0.28, 0.74, 1.00, 3, -0.24, -1.8, 1.00),  // sky
            (0.62, 0.42, 1.00, 0, -0.10, 1.0, 1.15),   // violet
            (1.00, 0.40, 0.88, 2, 0.18, -0.6, 0.90),   // magenta
        ]
        smoke.emitterCells = looks.map { r, g, b, sprite, spin, pull, growth in
            let cell = CAEmitterCell()
            cell.contents = Self.puffs[sprite]
            cell.birthRate = rate / Float(looks.count)
            cell.lifetime = 2.9
            cell.lifetimeRange = 0.2
            // 0.17…0.29, down 0.115 a second: every puff is at nothing 1.5…2.5 s in,
            // before the earliest death at 2.7 s.
            cell.color = CGColor(red: r, green: g, blue: b, alpha: 0.23)
            cell.redRange = 0.18; cell.greenRange = 0.18; cell.blueRange = 0.18
            cell.alphaRange = 0.06
            cell.alphaSpeed = -0.115
            // 128 px sprite: ~32 pt at birth, ~105 pt when it has faded.
            cell.scale = 0.25
            cell.scaleRange = 0.07
            cell.scaleSpeed = 0.23 * growth
            cell.emissionLongitude = inward
            cell.emissionRange = .pi * 0.55
            cell.velocity = 4
            cell.velocityRange = 3.5
            let a = along(pull)
            cell.xAcceleration = a.x
            cell.yAcceleration = a.y
            cell.spin = spin
            cell.spinRange = 0.35
            cell.emissionLatitude = 0
            return cell
        }
        smoke.birthRate = 0
        host.addSublayer(smoke)
    }

    func start() {
        let fresh = !running
        running = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The fog is already standing when the panel fades in, not built in front of him.
        if fresh { smoke.beginTime = CACurrentMediaTime() - 2.5 }
        CATransaction.commit()
        apply(force: true)
    }

    func stop() {
        running = false
        level = 0
        sentRate = -1; sentVelocity = -1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smoke.birthRate = 0
        CATransaction.commit()
    }

    func feed(_ samples: [Float]) {
        guard running else { return }
        var sum: Float = 0
        for v in samples { sum += v * v }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        let want = min(max((rms - 0.012) * 5, 0), 1)
        level += (want > level ? 0.30 : 0.06) * (want - level)
        apply(force: false)
    }

    func setIntensity(_ k: CGFloat) {
        intensity = Float(max(k, 0))
        if running { apply(force: true) }
    }

    /// The layer's two multipliers; written only when they have moved, so a silent
    /// microphone commits nothing.
    private func apply(force: Bool) {
        let rate = (Self.calm + (Self.loud - Self.calm) * level) * intensity
        let velocity = Self.still + (Self.lively - Self.still) * level
        let moved = abs(rate - sentRate) > 0.03 * max(sentRate, 0.1) || abs(velocity - sentVelocity) > 0.05
        guard force || moved else { return }
        sentRate = rate; sentVelocity = velocity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        smoke.birthRate = rate
        smoke.velocity = velocity
        CATransaction.commit()
    }
}
