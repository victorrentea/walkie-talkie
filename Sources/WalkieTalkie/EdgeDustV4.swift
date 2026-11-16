import AppKit

// CORE-BEGIN — copied verbatim into the offline check (scratchpad/v4): Foundation only.

/// **The fluid's look without a solver.** A low-resolution dye field in the strip's
/// own axes — `s` along the screen's edge, `d` away from it, both in points, one cell
/// per `cell` points — that every frame is carried a fraction of a cell by a curl-noise
/// velocity field (the curl of a smooth, slowly changing stream function: no
/// divergence, so swirls that stay where they are instead of a stream), multiplied by
/// `decay`, and fed soft one-colour splats from emitters that stand still.
struct CurlDustSim {
    // The knobs, all in points and seconds so both orientations get the same dust.
    static let cell: Float = 2
    static let fps: Float = 30
    /// What is left of the dye after one frame (Smoke: 0.98 at 60 Hz ≈ 0.96 at 30).
    static let decay: Float = 0.97
    /// Emitters standing per 100 pt of edge, and how likely each throws a splat a frame at rest.
    static let emittersPer100: Float = 3.2
    static let splatChance: Float = 0.55
    /// The stream function's octaves: lattice spacing (pt), peak speed (pt/s).
    static let octaves: [(spacing: Float, speed: Float)] = [(36, 18), (15, 15)]

    let ns: Int, nd: Int
    private var r: [Float], g: [Float], b: [Float]
    private var r2: [Float], g2: [Float], b2: [Float]
    private var psi: [Float]                 // (ns+2) × (nd+2), row-major by d
    private var keep: [Float]                // decay per depth row
    private var ramp: [Float]                // psi → 0 at the screen's edge: nothing flows through it
    private var time: Float = 0
    private var seed: UInt64

    private struct Octave {
        var gw: Int, gh: Int, amp: Float
        var phase: [Float], omega: [Float], val: [Float]
        var ix: [Int32], fx: [Float], iy: [Int32], fy: [Float]
    }
    private var oct: [Octave] = []

    private struct Emitter {
        var s: Float = 0, d: Float = 0, sigma: Float = 4
        var cr: Float = 0, cg: Float = 0, cb: Float = 0
        var age: Int = 0, life: Int = 1
    }
    private var emitters: [Emitter] = []
    // the voice: its envelope against a slow average — a syllable throws a puff
    private var slow: Float = 0
    private var puffCool: Int = 0
    private var puffSide: Float = 1

    init(lengthPt: Float, depthPt: Float, seed: UInt64 = 0x9E3779B97F4A7C15) {
        let c = Self.cell
        ns = max(4, Int((lengthPt / c).rounded(.up)))
        nd = max(4, Int((depthPt / c).rounded(.up)))
        let n = ns * nd
        r = [Float](repeating: 0, count: n); g = r; b = r; r2 = r; g2 = r; b2 = r
        psi = [Float](repeating: 0, count: (ns + 2) * (nd + 2))
        self.seed = seed
        keep = (0..<nd).map { j in
            // deep in the strip the dye dies faster: nothing piles up where the mask is thin
            let d = (Float(j) + 0.5) * c
            let far = min(max((d - 45) / 50, 0), 1)
            // and on the edge itself, where the flow can only run along it, no streak is left to draw a line
            let near = min(max(1 - d / 7, 0), 1)
            return Self.decay - 0.07 * far - 0.15 * near
        }
        ramp = (0..<(nd + 2)).map { j in
            let x = min(max((Float(j) - 0.5) * c / 9, 0), 1)
            return x * x * (3 - 2 * x)
        }
        for o in Self.octaves {
            let sp = o.spacing / c                                  // in cells
            let gw = Int(Float(ns + 2) / sp) + 3, gh = Int(Float(nd + 2) / sp) + 3
            var oc = Octave(gw: gw, gh: gh, amp: o.speed * o.spacing * 0.42 / (c * c * Self.fps),
                            phase: [], omega: [], val: [Float](repeating: 0, count: gw * gh),
                            ix: [], fx: [], iy: [], fy: [])
            for _ in 0..<(gw * gh) {
                oc.phase.append(rnd() * 2 * .pi)
                oc.omega.append((0.5 + rnd() * 0.9) * (rnd() < 0.5 ? -1 : 1))
            }
            let off = rnd()
            for i in 0..<(ns + 2) {
                let x = Float(i) / sp + off, f = x - x.rounded(.down)
                oc.ix.append(Int32(x)); oc.fx.append(f * f * (3 - 2 * f))
            }
            for j in 0..<(nd + 2) {
                let y = Float(j) / sp + off, f = y - y.rounded(.down)
                oc.iy.append(Int32(y)); oc.fy.append(f * f * (3 - 2 * f))
            }
            oct.append(oc)
        }
        let count = max(2, Int(lengthPt / 100 * Self.emittersPer100))
        emitters = (0..<count).map { _ in
            var e = Emitter(); respawn(&e); e.age = Int(rnd() * Float(e.life)); return e
        }
    }

    private mutating func rnd() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 24)
    }

    /// Smoke's colour — three random channels + 0.2, ×0.3 — with the grey they share
    /// mostly taken out, so that many of them overlapping stay colours and not a fog.
    private mutating func colour() -> (Float, Float, Float) {
        var c = ((rnd() + 0.2) * 0.3, (rnd() + 0.2) * 0.3, (rnd() + 0.2) * 0.3)
        let lo = min(c.0, c.1, c.2) * 0.75
        c = (c.0 - lo, c.1 - lo, c.2 - lo)
        let k = 0.36 / max(c.0, c.1, c.2, 0.01)
        return (c.0 * k, c.1 * k, c.2 * k)
    }

    private mutating func respawn(_ e: inout Emitter) {
        let c = Self.cell
        e.s = rnd() * Float(ns) * c
        // hugging the edge: most within ~20 pt, none beyond ~34
        let u = rnd()
        e.d = 5 + u * u * 29
        e.sigma = 3 + rnd() * rnd() * 5.5
        (e.cr, e.cg, e.cb) = colour()
        e.age = 0
        e.life = 14 + Int(rnd() * 34)
    }

    mutating func clear() {
        for i in r.indices { r[i] = 0; g[i] = 0; b[i] = 0 }
    }

    /// One frame. `level`: the voice, 0…1 (smoothed by the caller); `amount`: 1 at rest, 2 for the swell.
    mutating func step(level: Float, amount: Float) {
        time += (1 + 2.2 * level) / Self.fps
        flow(gain: 1 + 1.3 * level)
        advect()
        feed(level: level, amount: amount)
    }

    private mutating func flow(gain: Float) {
        let w = ns + 2, h = nd + 2, t = time
        psi.withUnsafeMutableBufferPointer { p in
            for k in 0..<(w * h) { p[k] = 0 }
            for o in oct.indices {
                var oc = oct[o]
                let n = oc.val.count
                oc.val.withUnsafeMutableBufferPointer { v in
                    for k in 0..<n { v[k] = sinf(oc.phase[k] + oc.omega[k] * t) }
                }
                oct[o].val = oc.val
                let gw = oc.gw, amp = oc.amp * gain
                oc.val.withUnsafeBufferPointer { v in
                oc.ix.withUnsafeBufferPointer { ix in
                oc.fx.withUnsafeBufferPointer { fx in
                    for j in 0..<h {
                        let row = Int(oc.iy[j]) * gw, fy = oc.fy[j], a = amp * ramp[j]
                        var k = j * w
                        for i in 0..<w {
                            let n = row + Int(ix[i]), f = fx[i]
                            let top = v[n] + (v[n + 1] - v[n]) * f
                            let bot = v[n + gw] + (v[n + gw + 1] - v[n + gw]) * f
                            p[k] += a * (top + (bot - top) * fy)
                            k += 1
                        }
                    }
                }}}
            }
        }
    }

    /// Semi-Lagrangian: each cell takes the dye from where the flow says it was a frame ago.
    private mutating func advect() {
        let w = ns, h = nd, pw = ns + 2
        let maxX = Float(w) - 1.001, maxY = Float(h) - 1.001
        psi.withUnsafeBufferPointer { p in
        r.withUnsafeBufferPointer { sr in g.withUnsafeBufferPointer { sg in b.withUnsafeBufferPointer { sb in
        r2.withUnsafeMutableBufferPointer { dr in g2.withUnsafeMutableBufferPointer { dg in b2.withUnsafeMutableBufferPointer { db in
            for j in 0..<h {
                let kp = keep[j]
                var c = (j + 1) * pw + 1, o = j * w
                for i in 0..<w {
                    // velocity = curl ψ, in cells a frame
                    let u = (p[c + pw] - p[c - pw]) * 0.5
                    let v = (p[c - 1] - p[c + 1]) * 0.5
                    let x = min(max(Float(i) - u, 0), maxX), y = min(max(Float(j) - v, 0), maxY)
                    let x0 = Int(x), y0 = Int(y)
                    let fx = x - Float(x0), fy = y - Float(y0)
                    let a = y0 * w + x0, bq = a + w
                    let w00 = (1 - fx) * (1 - fy) * kp, w10 = fx * (1 - fy) * kp
                    let w01 = (1 - fx) * fy * kp, w11 = fx * fy * kp
                    dr[o] = sr[a] * w00 + sr[a + 1] * w10 + sr[bq] * w01 + sr[bq + 1] * w11
                    dg[o] = sg[a] * w00 + sg[a + 1] * w10 + sg[bq] * w01 + sg[bq + 1] * w11
                    db[o] = sb[a] * w00 + sb[a + 1] * w10 + sb[bq] * w01 + sb[bq + 1] * w11
                    c += 1; o += 1
                }
            }
        }}}}}}}
        swap(&r, &r2); swap(&g, &g2); swap(&b, &b2)
    }

    private mutating func feed(level: Float, amount: Float) {
        let chance = Self.splatChance * (1 + 1.6 * level) * amount
        for n in emitters.indices {
            var e = emitters[n]
            e.age += 1
            if e.age >= e.life { respawn(&e) }
            var owed = chance
            while owed > 0 {
                if rnd() < owed {
                    let env = sinf(.pi * Float(e.age) / Float(e.life))
                    let k = (0.22 + 0.48 * rnd()) * (0.35 + 0.65 * env)
                    splat(s: e.s + (rnd() - 0.5) * 22, d: max(1.5, e.d + (rnd() - 0.5) * 12),
                          sigma: e.sigma * (0.7 + 0.6 * rnd()), e.cr * k, e.cg * k, e.cb * k)
                    // and a few motes in it: grains a cell wide, carried and blurred with the wisp
                    for _ in 0..<3 {
                        let m = k * (0.5 + 1.1 * rnd())
                        splat(s: e.s + (rnd() - 0.5) * 30, d: max(3, e.d + (rnd() - 0.5) * 20),
                              sigma: 0.9, e.cr * m, e.cg * m, e.cb * m)
                    }
                }
                owed -= 1
            }
            emitters[n] = e
        }
        // A syllable: one little gesture of smoke, to one side then the other.
        slow += (level - slow) * 0.06
        puffCool -= 1
        if puffCool <= 0, level > 0.12, level > slow * 1.25 {
            puffCool = 3 + Int(rnd() * 4)
            puffSide = -puffSide
            let puffs = max(1, Int(Float(ns) * Self.cell / 500 * (0.6 + level)))
            for _ in 0..<puffs {
                let s0 = rnd() * Float(ns) * Self.cell, d0 = 4 + rnd() * 12
                let ang = puffSide * (0.35 + rnd() * 0.9)
                let (cr, cg, cb) = colour()
                let reach = 10 + 26 * level, k = (0.10 + 0.14 * level) * amount
                for q in 0..<5 {
                    let f = Float(q) / 4
                    splat(s: s0 + sinf(ang) * reach * f, d: d0 + cosf(ang) * reach * f,
                          sigma: 3 + 3 * f, cr * k * (1 - 0.6 * f), cg * k * (1 - 0.6 * f), cb * k * (1 - 0.6 * f))
                }
            }
        }
    }

    private mutating func splat(s: Float, d: Float, sigma: Float, _ cr: Float, _ cg: Float, _ cb: Float) {
        let c = Self.cell
        let x = s / c - 0.5, y = d / c - 0.5, sg = max(sigma / c, 0.45)
        let rad = Int(sg * 2.6) + 1
        let x0 = max(0, Int(x) - rad), x1 = min(ns - 1, Int(x) + rad + 1)
        let y0 = max(0, Int(y) - rad), y1 = min(nd - 1, Int(y) + rad + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        let inv = 1 / (2 * sg * sg)
        // the same dye whatever the splat's size would make the big ones blinding
        let gain = min(1, 2.2 / sg)
        for j in y0...y1 {
            let dy = Float(j) - y
            for i in x0...x1 {
                let dx = Float(i) - x
                let a = expf(-(dx * dx + dy * dy) * inv) * gain
                let k = j * ns + i
                r[k] += cr * a; g[k] += cg * a; b[k] += cb * a
            }
        }
    }

    /// Premultiplied RGBA, row 0 on top. `edgeOnTop`: `ns` × `nd` with the screen's edge
    /// in row 0; else `nd` × `ns` with the edge in the last column.
    func render(into px: inout [UInt8], edgeOnTop: Bool) {
        var noise = seed
        px.withUnsafeMutableBufferPointer { out in
            for j in 0..<nd {
                for i in 0..<ns {
                    let k = j * ns + i
                    let o = (edgeOnTop ? k : i * nd + (nd - 1 - j)) * 4
                    let cr = r[k], cg = g[k], cb = b[k]
                    let m = max(cr, cg, cb)
                    if m < 0.004 { out[o] = 0; out[o + 1] = 0; out[o + 2] = 0; out[o + 3] = 0; continue }
                    // soft shoulder: piles of dye saturate towards their colour, never to white
                    let sc = 255 * 1.5 / (1 + 1.5 * m)
                    noise ^= noise << 13; noise ^= noise >> 7; noise ^= noise << 17
                    let dz = Float(noise >> 40) / Float(1 << 24)        // dither: no bands in the faint tail
                    out[o] = UInt8(min(255, cr * sc + dz)); out[o + 1] = UInt8(min(255, cg * sc + dz))
                    out[o + 2] = UInt8(min(255, cb * sc + dz)); out[o + 3] = UInt8(min(255, m * sc * 0.7 + dz))
                }
            }
        }
    }
}

// CORE-END

/// **Variant 4 — "Curl dust".** The pointer's Smoke (`pmhalo.cpp`, `kSmoke`) laid along
/// an edge, without its solver: `CurlDustSim` on a serial queue, 30 times a second, its
/// dye shown as the contents of one layer (1 cell = 2 pt, linear upscale). Nothing
/// travels — the emitters stand, the flow is a curl noise — and the voice throws more
/// dye, stirs faster, and puffs on a syllable.
final class EdgeDustV4: EdgeDustPicture {
    static let title = "Curl dust"

    private let layer = CALayer()
    private let edge: EdgeDust.Edge
    private let queue = DispatchQueue(label: "ro.victorrentea.walkie.edge-dust-v4", qos: .userInteractive)
    // the queue's own
    private var sim: CurlDustSim
    private var pixels: [UInt8]
    // main's
    private var timer: Timer?
    private var run = 0                 // raised by every start and stop: frames of an older run are dropped
    private var busy = false
    private var level: Float = 0
    private var amount: Float = 1
    private let wide: Int, high: Int
    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init?(strip: NSView, edge: EdgeDust.Edge) {
        let box = strip.bounds
        let length = edge == .top ? box.width : box.height
        let depth = edge == .top ? box.height : box.width
        guard length > 8, depth > 8, let host = strip.layer else { return nil }
        self.edge = edge
        sim = CurlDustSim(lengthPt: Float(length), depthPt: Float(depth), seed: edge == .top ? 0x9E3779B97F4A7C15 : 0xD1B54A32D192ED03)
        wide = edge == .top ? sim.ns : sim.nd
        high = edge == .top ? sim.nd : sim.ns
        pixels = [UInt8](repeating: 0, count: wide * high * 4)
        // Whole cells, anchored on the screen's edge; the overhang is on the inner side and the far end.
        let c = CGFloat(CurlDustSim.cell)
        let size = CGSize(width: CGFloat(wide) * c, height: CGFloat(high) * c)
        switch edge {
        case .top:   layer.frame = CGRect(x: 0, y: box.maxY - size.height, width: size.width, height: size.height)
        case .right: layer.frame = CGRect(x: box.maxX - size.width, y: box.maxY - size.height, width: size.width, height: size.height)
        }
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        host.addSublayer(layer)
    }

    deinit { timer?.invalidate() }

    func start() {
        guard timer == nil else { return }
        run += 1
        let mine = run
        busy = false
        layer.contents = nil
        queue.async { [weak self] in
            guard let self else { return }
            // No stale frame, and no empty one either: the first shown already has its wisps.
            self.sim.clear()
            for _ in 0..<24 { self.sim.step(level: 0, amount: 1) }
        }
        let t = Timer(timeInterval: 1.0 / Double(CurlDustSim.fps), repeats: true) { [weak self] _ in self?.tick(mine) }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        run += 1
        busy = false
    }

    func feed(_ samples: [Float]) {
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        // speech sits around 0.03–0.15 RMS
        let target = min(1, rms * 7)
        level += (target - level) * (target > level ? 0.5 : 0.18)
    }

    func setIntensity(_ k: CGFloat) { amount = Float(max(0, k)) }

    private func tick(_ mine: Int) {
        guard mine == run, !busy else { return }       // the last frame is still being made: skip this one
        busy = true
        let level = self.level, amount = self.amount
        let top = edge == .top, w = wide, h = high
        queue.async { [weak self] in
            guard let self else { return }
            self.sim.step(level: level, amount: amount)
            self.sim.render(into: &self.pixels, edgeOnTop: top)
            let data = self.pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
            let image = CGDataProvider(data: data).flatMap {
                CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: Self.space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, mine == self.run else { return }
                self.busy = false
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer.contents = image
                CATransaction.commit()
            }
        }
    }
}
