import AppKit
import Accelerate

/// **Variant 8 — "Ember dust": a fire whose substance is dust** (2026-11-16, Victor:
/// *"și încă 3 efecte tip «foc» dar cu praf"*). The edge is the base of the fire;
/// tongues of fine grains lick inward from it, flicker, curl, taper and dissolve —
/// dense at the edge, sparse at the tips, a few embers flying further. Everything
/// moves *across* the strip; along the edge the tongues only rise and fall where
/// they stand (the fuel is a noise of the place and of time, never of place − time).
///
/// A CPU particle simulation (`EmberSim`) into a trail buffer of 1.5 pt cells that
/// keeps `EmberSim.decay` of itself a frame — the mouse dust's look (dye that
/// fades, additive, soft saturated hues, never white) in the shape of a fire. 30
/// times a second, off the main thread; the buffer is the `contents` of one layer.
/// Measured offline (`swiftc -O`, M-series): ~0.55 ms a frame for the top strip of
/// a 1728 pt screen (~4500 grains), ~0.4 ms for the right one — about 3 % of a core
/// for both at rest.
///
/// His voice (RMS, fast up, ~600 ms down) is fuel: taller, denser flames. Silence
/// leaves low calm ones, never an empty edge. `setIntensity(2)`: twice the grains,
/// a third taller.
final class EdgeDustV8: EdgeDustPicture {
    static let title = "Ember dust"

    private let flame = CALayer()
    private let sim: EmberSim
    private let queue = DispatchQueue(label: "walkie.edge-dust.embers", qos: .userInteractive)
    private let colours = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var timer: Timer?
    private var inWork = false
    /// Raised by every `start` and `stop`: a frame simulated for an earlier run is not shown.
    private var run = 0
    private var lastTick: CFAbsoluteTime = 0
    private var voice: Float = 0
    private var intensity: Float = 1
    private var intensityShown: Float = 1

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard let host = strip.layer else { return nil }
        let box = strip.bounds
        let length = edge == .top ? box.width : box.height
        let depth = edge == .top ? box.height : box.width
        guard length >= 120, depth >= 20 else { return nil }
        sim = EmberSim(length: Float(length), depth: Float(depth), acrossRows: edge == .right,
                       seed: UInt64.random(in: 1...1_000_000))
        flame.frame = box
        flame.contentsGravity = .resize
        flame.magnificationFilter = .linear
        flame.minificationFilter = .linear
        flame.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        host.addSublayer(flame)
    }

    deinit { timer?.invalidate() }

    func start() {
        guard timer == nil else { return }
        run += 1
        flame.contents = nil
        let sim = self.sim
        queue.async { sim.reset() }
        lastTick = CFAbsoluteTimeGetCurrent()
        intensityShown = intensity
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.004
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        run += 1
        flame.contents = nil
        voice = 0
    }

    func feed(_ samples: [Float]) {
        var sum: Float = 0
        for v in samples { sum += v * v }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        let want = min(max((rms - 0.012) * 5, 0), 1)
        // Up in a couple of frames, down over ~600 ms.
        voice += (want - voice) * (want > voice ? 0.5 : 0.054)
    }

    func setIntensity(_ k: CGFloat) { intensity = Float(min(max(k, 0.5), 3)) }

    private func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        // The last frame is still being made: this one is dropped, time is not.
        guard !inWork else { return }
        let dt = Float(min(max(now - lastTick, 1.0 / 120), 1.0 / 15))
        lastTick = now
        intensityShown += (intensity - intensityShown) * 0.25
        inWork = true
        let mine = run, voice = self.voice, k = intensityShown
        let sim = self.sim, colours = self.colours
        queue.async { [weak self] in
            sim.step(dt: dt, voice: voice, intensity: k)
            sim.paint()
            let image = Self.image(of: sim, in: colours)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inWork = false
                guard mine == self.run, let image else { return }
                self.flame.contents = image
            }
        }
    }

    private static func image(of sim: EmberSim, in colours: CGColorSpace) -> CGImage? {
        let w = sim.imageWidth, h = sim.imageHeight
        let data = Data(bytes: sim.pixels, count: w * h * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: colours,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The fire of dust, simulated: grains in points (`u` along the edge, `d` away from
/// it), drawn into a trail buffer of `cell`-point cells that fades every frame.
fileprivate final class EmberSim {
    /// Points per buffer cell.
    static let cell: Float = 1.5
    /// What is left of the trail after one 30 fps frame.
    static let decay: Float = 0.76
    /// How tall the tallest tongue stands at rest, in points.
    static let restHeight: Float = 88
    /// Births tried a second per point of edge at rest (about half are taken).
    static let attempts: Float = 4.8
    static let emberShare: Float = 0.03
    static let palette: [(Float, Float, Float)] = [
        (1.00, 0.40, 0.60),   // rose
        (1.00, 0.68, 0.26),   // amber
        (0.42, 0.92, 0.52),   // green
        (0.36, 0.70, 1.00),   // sky
        (0.70, 0.48, 1.00),   // violet
    ]

    let length: Float, depth: Float
    let nu: Int, nd: Int
    let acrossRows: Bool           // false: u is the image's x (top edge); true: u is its y (right edge)
    let imageWidth: Int, imageHeight: Int
    /// The trail, one plane a channel, laid out as the image (row 0 its top).
    private let tr, tg, tb, tm, tk: UnsafeMutablePointer<Float>
    let pixels: UnsafeMutablePointer<UInt8>                 // imageWidth × imageHeight × 4, premultiplied RGBA
    private let capacity: Int
    private var count = 0
    private let pu, pd, pv, pvt, page, plife, pr, pg, pb, pgain, pseed, plean: UnsafeMutablePointer<Float>
    private var rng: UInt64
    private var t: Float
    private var owed: Float = 0
    private let seedA: Float, seedB: Float, seedC: Float

    init(length: Float, depth: Float, acrossRows: Bool, seed: UInt64) {
        self.length = length; self.depth = depth; self.acrossRows = acrossRows
        nu = max(2, Int((length / Self.cell).rounded(.up)))
        nd = max(2, Int((depth / Self.cell).rounded(.up)))
        imageWidth = acrossRows ? nd : nu
        imageHeight = acrossRows ? nu : nd
        let cells = nu * nd
        func plane() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: cells)
            p.initialize(repeating: 0, count: cells)
            return p
        }
        tr = plane(); tg = plane(); tb = plane(); tm = plane(); tk = plane()
        pixels = .allocate(capacity: nu * nd * 4)
        pixels.initialize(repeating: 0, count: nu * nd * 4)
        let room = Int(length * 9) + 64
        capacity = room
        func column() -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: room)
            p.initialize(repeating: 0, count: room)
            return p
        }
        pu = column(); pd = column(); pv = column(); pvt = column(); page = column(); plife = column()
        pr = column(); pg = column(); pb = column(); pgain = column(); pseed = column(); plean = column()
        rng = seed &* 0x9E3779B97F4A7C15 | 1
        seedA = Float(seed % 977) * 1.37
        seedB = Float(seed % 613) * 2.11
        seedC = Float(seed % 389) * 0.73
        t = Float(seed % 101)
    }

    deinit {
        pixels.deallocate()
        for p in [tr, tg, tb, tm, tk] { p.deallocate() }
        for p in [pu, pd, pv, pvt, page, plife, pr, pg, pb, pgain, pseed, plean] { p.deallocate() }
    }

    func reset() {
        count = 0
        owed = 0
        for p in [tr, tg, tb] { p.update(repeating: 0, count: nu * nd) }
        pixels.update(repeating: 0, count: nu * nd * 4)
    }

    // MARK: Noise

    @inline(__always) private func rand() -> Float {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Float(rng >> 40) * (1.0 / 16777216.0)
    }

    @inline(__always) private static func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374761393 &+ UInt32(bitPattern: y) &* 668265263 &+ UInt32(bitPattern: z) &* 2147483647
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) * (1.0 / 16777216.0)
    }

    /// Value noise, 0…1, smooth.
    @inline(__always) private static func noise(_ x: Float, _ y: Float) -> Float {
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let ix = Int32(fx), iy = Int32(fy)
        var ax = x - fx, ay = y - fy
        ax = ax * ax * (3 - 2 * ax); ay = ay * ay * (3 - 2 * ay)
        let a = hash(ix, iy, 0), b = hash(ix &+ 1, iy, 0), c = hash(ix, iy &+ 1, 0), d = hash(ix &+ 1, iy &+ 1, 0)
        return a + (b - a) * ax + (c - a) * ay + (a - b - c + d) * ax * ay
    }

    @inline(__always) private static func noise(_ x: Float, _ y: Float, _ z: Float) -> Float {
        let fz = z.rounded(.down)
        let iz = Int32(fz)
        var az = z - fz
        az = az * az * (3 - 2 * az)
        let fx = x.rounded(.down), fy = y.rounded(.down)
        let ix = Int32(fx), iy = Int32(fy)
        var ax = x - fx, ay = y - fy
        ax = ax * ax * (3 - 2 * ax); ay = ay * ay * (3 - 2 * ay)
        @inline(__always) func plane(_ k: Int32) -> Float {
            let a = hash(ix, iy, k), b = hash(ix &+ 1, iy, k), c = hash(ix, iy &+ 1, k), d = hash(ix &+ 1, iy &+ 1, k)
            return a + (b - a) * ax + (c - a) * ay + (a - b - c + d) * ax * ay
        }
        let p0 = plane(iz), p1 = plane(iz &+ 1)
        return p0 + (p1 - p0) * az
    }

    /// The slope of the 3-D noise across x and y, from one lattice cell.
    @inline(__always) private static func slope(_ x: Float, _ y: Float, _ z: Float) -> (Float, Float) {
        let fx = x.rounded(.down), fy = y.rounded(.down), fz = z.rounded(.down)
        let ix = Int32(fx), iy = Int32(fy), iz = Int32(fz)
        let ax = x - fx, ay = y - fy
        var az = z - fz
        az = az * az * (3 - 2 * az)
        let sx = ax * ax * (3 - 2 * ax), sy = ay * ay * (3 - 2 * ay)
        let gx = 6 * ax * (1 - ax), gy = 6 * ay * (1 - ay)
        @inline(__always) func plane(_ k: Int32) -> (Float, Float) {
            let a = hash(ix, iy, k), b = hash(ix &+ 1, iy, k), c = hash(ix, iy &+ 1, k), d = hash(ix &+ 1, iy &+ 1, k)
            let q = a - b - c + d
            return (((b - a) + q * sy) * gx, ((c - a) + q * sx) * gy)
        }
        let p0 = plane(iz), p1 = plane(iz &+ 1)
        return (p0.0 + (p1.0 - p0.0) * az, p0.1 + (p1.1 - p0.1) * az)
    }

    /// The fuel under a point of the edge, 0…1: tongues that rise, fall and lean a
    /// little where they stand. Time only ever moves the noise's *other* axis.
    @inline(__always) private func fuel(_ u: Float) -> Float {
        let slow = Self.noise(u / 42 + seedA, t * 0.42)
        let quick = Self.noise(u / 15 + seedB, t * 1.5 + 40)
        let n = slow * 0.72 + quick * 0.28
        var f = (n - 0.34) / 0.36
        f = f < 0 ? 0 : (f > 1 ? 1 : f)
        f = f * f * (3 - 2 * f)
        // To nothing at the strip's two ends.
        let ends = min(u, length - u) / 48
        let e = ends < 0 ? 0 : (ends > 1 ? 1 : ends)
        return f * e * e * (3 - 2 * e)
    }

    // MARK: A frame

    /// `voice` 0…1 (smoothed by the caller), `intensity` 1 at rest, 2 for the swell.
    func step(dt: Float, voice: Float, intensity: Float) {
        t += dt
        let lift = (1 + 0.75 * voice) * (1 + 0.3 * (intensity - 1))
        let crowd = (1 + 0.9 * voice) * intensity

        // Births, on the edge line.
        owed += Self.attempts * length * dt * crowd
        var tries = Int(owed)
        owed -= Float(tries)
        tries = min(tries, capacity / 4)
        let ends = Float(48)
        for _ in 0..<tries where count < capacity {
            let u = rand() * length
            let f = fuel(u)
            let e0 = min(u, length - u) / ends
            let e = e0 > 1 ? 1 : e0
            // Low calm flames everywhere, the tongues on top of them.
            let weight = (0.14 + 0.86 * f) * e
            if rand() > weight { continue }
            let i = count
            count += 1
            let ember = rand() < Self.emberShare
            let height = Self.restHeight * (0.16 + 0.84 * f * f.squareRoot()) * lift * (0.4 + 0.6 * e)
            // Most grains stop low in the tongue, few reach its tip.
            let r = rand()
            var reach = height * (0.12 + 0.88 * r)
            var life = (0.5 + 1.1 * rand()) * (0.75 + 0.25 * f)
            var gain: Float = 0.35 + 0.65 * rand()
            if ember {
                life *= 2 + rand()
                reach = height * (1.15 + 0.9 * rand())
                gain = 1.25
            }
            pu[i] = u
            pd[i] = rand() * 4
            pvt[i] = reach / life * 0.80            // where buoyancy and drag settle
            pv[i] = reach / life * 1.45              // the launch
            page[i] = 0
            plife[i] = life
            pgain[i] = ember ? -gain : gain         // the sign marks an ember
            pseed[i] = rand() * 40
            // Grains on a tongue's flank lean towards its middle as they rise: the taper.
            let slope = (fuel(u + 4) - fuel(u - 4)) * 60
            plean[i] = ember ? 0 : (slope > 16 ? 16 : (slope < -16 ? -16 : slope))
            // The tongue's colour: a slow noise along the edge, round the palette.
            var h = Self.noise(u / 210 + seedC, t * 0.06 + 9) * 2.6 + (rand() - 0.5) * 0.22 + 5
            h -= h.rounded(.down)
            let hp = h * Float(Self.palette.count)
            let k = Int(hp) % Self.palette.count
            let k1 = (k + 1) % Self.palette.count
            let m = hp - hp.rounded(.down)
            let c0 = Self.palette[k], c1 = Self.palette[k1]
            pr[i] = c0.0 + (c1.0 - c0.0) * m
            pg[i] = c0.1 + (c1.1 - c0.1) * m
            pb[i] = c0.2 + (c1.2 - c0.2) * m
        }

        // The trail fades.
        var keep = powf(Self.decay, dt * 30)
        let cells = vDSP_Length(nu * nd)
        vDSP_vsmul(tr, 1, &keep, tr, 1, cells)
        vDSP_vsmul(tg, 1, &keep, tg, 1, cells)
        vDSP_vsmul(tb, 1, &keep, tb, 1, cells)

        // Grains move and leave their dot.
        let drag = 1 - expf(-3.2 * dt)
        let inv = 1 / Self.cell
        let tz = t * 0.8
        let umax = Float(nu) - 1.001, dmax = Float(nd) - 1.001
        let across = imageWidth
        var i = 0
        while i < count {
            let age = page[i] + dt
            let life = plife[i]
            var d = pd[i]
            if age >= life || d >= depth - 1 {
                count -= 1
                let j = count
                pu[i] = pu[j]; pd[i] = pd[j]; pv[i] = pv[j]; pvt[i] = pvt[j]; page[i] = page[j]; plife[i] = plife[j]
                pr[i] = pr[j]; pg[i] = pg[j]; pb[i] = pb[j]; pgain[i] = pgain[j]; pseed[i] = pseed[j]; plean[i] = plean[j]
                continue
            }
            var u = pu[i]
            let u0 = u, d0 = d
            // Curl of a time-evolving potential: bends the path, never carries it along.
            let x = u / 27, y = d / 27, z = tz + pseed[i] * 0.004
            let (dpdx, dpdy) = Self.slope(x, y, z)
            // The base holds still, the tips waver.
            let loose = 0.25 + min(d / 36, 1) * 0.75
            let swirl: Float = 46 * loose
            var v = pv[i]
            v += (pvt[i] - v) * drag
            // A grain of dust is jostled; a hair-fine line would be a fibre.
            u += (rand() - 0.5) * 1.3
            d += (rand() - 0.5) * 1.0
            u += (dpdy * swirl + plean[i] * min(d / 20, 1)) * dt
            d += (v - dpdx * swirl * 0.55) * dt
            if d < 0 { d = 0 }
            pu[i] = u; pd[i] = d; pv[i] = v; page[i] = age

            let a = age / life
            let ember = pgain[i] < 0
            let g = abs(pgain[i])
            // Bright at birth, gone at the end; an ember holds its glow longer.
            var w = ember ? (1 - a * a * a) : (1 - a * a) * (1 - a * 0.3)
            w *= min(age * 40, 1) * g * 0.47
            // Young: paler. Cooling: its own colour, deeper.
            let pale = max(0, 0.42 - a * 1.5)
            let deep = 1 - 0.22 * a
            let cr = (pr[i] + (1 - pr[i]) * pale) * deep * w
            let cg = (pg[i] + (1 - pg[i]) * pale) * deep * w
            let cb = (pb[i] + (1 - pb[i]) * pale) * deep * w

            // Two dots a frame, the second halfway back: a streak, not a dotted line.
            var su = u, sd = d
            for _ in 0..<2 {
                let gu = su * inv - 0.5
                var gd = sd * inv - 0.5
                if gd < 0 { gd = 0 }
                if gu >= 0, gu < umax, gd < dmax {
                    // Into the image: the edge is its top row, or its right column.
                    let gx = acrossRows ? dmax - gd : gu, gy = acrossRows ? gu : gd
                    let ix = Int(gx), iy = Int(gy)
                    let fx = gx - Float(ix), fy = gy - Float(iy)
                    let o = iy * across + ix
                    let o2 = o + across
                    let w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy), w01 = (1 - fx) * fy, w11 = fx * fy
                    tr[o] += cr * w00; tr[o + 1] += cr * w10; tr[o2] += cr * w01; tr[o2 + 1] += cr * w11
                    tg[o] += cg * w00; tg[o + 1] += cg * w10; tg[o2] += cg * w01; tg[o2 + 1] += cg * w11
                    tb[o] += cb * w00; tb[o + 1] += cb * w10; tb[o2] += cb * w01; tb[o2 + 1] += cb * w11
                }
                su = (u + u0) * 0.5; sd = (d + d0) * 0.5
            }
            i += 1
        }
    }

    var grains: Int { count }

    /// The trail as premultiplied RGBA, row 0 the image's top. Alpha is the colour's
    /// strongest channel, so nothing is drawn where there is no dust; a crowded cell
    /// keeps its hue instead of burning to white.
    func paint() {
        let n = vDSP_Length(nu * nd)
        vDSP_vmax(tr, 1, tg, 1, tm, 1, n)
        vDSP_vmax(tm, 1, tb, 1, tm, 1, n)
        // A soft shoulder, k = 255·g / (1 + m·g/top): a crowded cell tends to `top`, hue kept.
        var one: Float = 1, bend: Float = 1.25 / 0.95, scale: Float = 255 * 1.25
        vDSP_vsmsa(tm, 1, &bend, &one, tk, 1, n)
        vDSP_svdiv(&scale, tk, 1, tk, 1, n)
        vDSP_vmul(tm, 1, tk, 1, tm, 1, n)
        vDSP_vfixu8(tm, 1, pixels + 3, 4, n)
        vDSP_vmul(tr, 1, tk, 1, tm, 1, n)
        vDSP_vfixu8(tm, 1, pixels, 4, n)
        vDSP_vmul(tg, 1, tk, 1, tm, 1, n)
        vDSP_vfixu8(tm, 1, pixels + 1, 4, n)
        vDSP_vmul(tb, 1, tk, 1, tm, 1, n)
        vDSP_vfixu8(tm, 1, pixels + 2, 4, n)
    }
}

