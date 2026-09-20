import AppKit
import Accelerate
import QuartzCore

/// **The audio-reactive halo effects, ported from the `voice-halo` web page.**
///
/// Source of truth: `~/workspace/voice-halo/index.html` at git tag
/// **`swift-port-01`** (commit 6717b17). Every formula, constant and comment
/// about *why* a number is what it is comes from that file; where this port
/// deviates it says so beside the line. A later pass resumes from that tag.
///
/// What the page does in a `<canvas>` with `mix-blend-mode: screen`, this does
/// in a `CGContext` bitmap handed to a `CALayer` every frame. Two things are
/// worth knowing before touching it:
///
/// - **The "fog" is a feedback buffer, not a blur.** Each frame the previous
///   frame is redrawn slightly scaled up, rotated a hair and dimmed, and the new
///   ink is added on top. The decay step must `setBlendMode(.copy)` + `clear()`
///   before redrawing the snapshot, or the previous frame composites onto
///   itself and the trail saturates to white instead of fading (proven in the
///   scratchpad demo this was built from).
/// - **Spectrum bands carry a noise floor and a slow ceiling** with a
///   compressive response (`VoiceAnalyser.updateBands`) — without it the
///   background hiss saturates every band within seconds.
///
/// Every effect keeps the **centre free** (the pointer is there) and pulses
/// **outward only** — `|sample|`, never the signed sample, which reads as
/// threatening. Both rules are the page's and are preserved verbatim.
///
/// **Not ported, by Victor's decision (2026-09-20)**: the nine MilkDrop presets
/// (numbers 7, 8, 20, 44, 77, 85, 87, 97, 99 on the page) run the real
/// butterchurn engine in WebGL and are out of scope for this pass — nothing here
/// approximates them. For the record, the only faithful desktop route would be
/// a hidden `WKWebView`, which needs either a second microphone open inside the
/// web view or the PCM piped in over a JS bridge every frame, plus ~1 MB fetched
/// from unpkg at run time — none of which belongs in an overlay that has to be
/// up before he starts talking.
///
/// *ORB rays* is the one hand-written effect that takes its shapes from a
/// preset; it has no engine behind it and is ported like the rest. On the page
/// it runs on a full-viewport canvas and is the one effect allowed to cross the
/// cursor; here its `S` is the panel's side, so the petals reach the panel's
/// edge and still pass over the pointer, faded to nothing at the centre as the
/// page has them.
enum HaloStyle: String, CaseIterable {
    /// **What ships and what he uses every day** — the rotating lightning film
    /// in `CaretHalo`. Nothing in this file runs when this is the style.
    case lightning
    /// Page 5: *lanț de fulgere — lasă valuri de ceață în urmă*.
    case lightningChain
    /// Page 3: *coroană — numai barele, fără cerc fix*.
    case crown
    /// Page 4: *inel de segmente — nuanța se închide fără cusătură*.
    case segments
    /// Page 2: *oscilogramă mov — albastrul și roșul suprapuse*.
    case oscillogram
    /// Page 1: *inel de undă — cerc perfect în tăcere, se rotește*.
    case waveRing
    /// Page 7: *două bile — ceață suflată din contur spre exterior*.
    case twoBalls
    /// Page 18: *inel de blocuri — cerc în repaus, crește doar în afară*.
    case blockBeads
    /// Page 6: *orbite rare — gaură mare, blocuri clare*.
    case orbits
    /// Page 8: *raze ORB — petale rotitoare, fără flash*.
    case orbRays

    /// The menu row's wording. English, like every string the app renders.
    var title: String {
        switch self {
        case .lightning:      return "Lightning ring"
        case .lightningChain: return "Lightning chain with fog"
        case .crown:          return "Crown of bars"
        case .segments:       return "Ring of segments"
        case .oscillogram:    return "Purple oscillogram"
        case .waveRing:       return "Wave ring"
        case .twoBalls:       return "Two balls with fog"
        case .blockBeads:     return "Block-bead ring"
        case .orbits:         return "Sparse particle orbits"
        case .orbRays:        return "ORB rays, no flash"
        }
    }

    /// The page's `rest`: where the effect's **visible** edge sits as a
    /// fraction of its canvas radius. The canvas radius is derived from it so
    /// every effect comes out at the same diameter on screen — here the
    /// lightning ring's `CaretHalo.core`.
    var rest: CGFloat {
        switch self {
        case .lightning:      return 1
        case .lightningChain: return 0.80
        case .crown:          return 0.66
        case .segments:       return 0.64
        case .oscillogram:    return 0.66
        case .waveRing:       return 0.66
        case .twoBalls:       return 0.88
        case .blockBeads:     return 0.50
        case .orbits:         return 1.15
        case .orbRays:        return 1
        }
    }

    /// **Persisted like the app's other preferences**: `UserDefaults`, not
    /// `~/.walkie-talkie` — it is a preference, not data, and `--home` has no
    /// business moving it. `WT_HALO_STYLE=<case>` overrides it for one run, the
    /// way `WT_HALO_DESIGN` does for the film's texture.
    static let defaultsKey = "haloStyle"

    static var current: HaloStyle {
        if let name = ProcessInfo.processInfo.environment["WT_HALO_STYLE"],
           let forced = HaloStyle(rawValue: name) { return forced }
        guard let name = UserDefaults.standard.string(forKey: defaultsKey),
              let saved = HaloStyle(rawValue: name) else { return .lightning }
        return saved
    }

    static func save(_ style: HaloStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: defaultsKey)
    }
}

// MARK: - The voice, as the page sees it

/// **What the page computes from the analyser every frame**, kept here in one
/// object: the waveform, the byte spectrum, the 64 bands with their floors and
/// ceilings, the smoothed ring shape (`SHAPE`, `LIVE`) and the low/high split
/// the oscillogram uses.
///
/// The page's analyser runs at 48 kHz with `fftSize` 2048 (a 43 ms window);
/// this app's microphone is 16 kHz, so the waveform is the last **704**
/// samples (44 ms) and the spectrum a 1024-point FFT (64 ms, 512 bins to
/// 8 kHz). The bands are spread over those bins with the page's own quadratic
/// law and the same `× 0.85` cut, so band 63 reads sibilants at ~6.8 kHz where
/// the page's read hiss at 20 kHz — a deliberate improvement, not a bug.
///
/// The page asks the browser for `autoGainControl: true`; there is no such
/// thing on a raw CoreAudio tap, so a slow AGC (`gain`) stands in for it — the
/// time-domain amplitudes drive ring displacement directly and would otherwise
/// depend on which microphone happens to be plugged in.
final class VoiceAnalyser {
    static let waveN = 704
    static let fftN = 1024
    static let bins = fftN / 2
    static let NB = 64
    static let shapeN = 512

    private(set) var wave = [Float](repeating: 0, count: VoiceAnalyser.waveN)
    /// The page's `spec`: 0…255 per bin, smoothed 0.72 like `smoothingTimeConstant`.
    private(set) var spec = [Float](repeating: 0, count: VoiceAnalyser.bins)
    private var mag = [Float](repeating: 0, count: VoiceAnalyser.bins)
    private var peak = [Float](repeating: 60, count: VoiceAnalyser.NB)
    private var floorA = [Float](repeating: 6, count: VoiceAnalyser.NB)
    private(set) var band = [Float](repeating: 0, count: VoiceAnalyser.NB)
    private(set) var levelNow: Float = 0
    private(set) var shape = [Float](repeating: 0, count: VoiceAnalyser.shapeN)
    private(set) var live = [Float](repeating: 0, count: VoiceAnalyser.shapeN)
    private(set) var idleMix: Float = 1
    private(set) var low = [Float](repeating: 0, count: 256)
    private(set) var high = [Float](repeating: 0, count: 256)

    private var envelope: Float = 0
    private let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(VoiceAnalyser.fftN))),
                               radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: VoiceAnalyser.fftN, isHalfWindow: false)
    private var re = [Float](repeating: 0, count: VoiceAnalyser.bins)
    private var im = [Float](repeating: 0, count: VoiceAnalyser.bins)
    private var windowed = [Float](repeating: 0, count: VoiceAnalyser.fftN)

    /// One frame: take the samples, window them, compute everything.
    func update(samples: [Float], t: Double) {
        guard samples.count >= Self.fftN else { return }
        // Slow AGC in place of the browser's: attack at once, release over ~2 s
        // of frames, and a gain capped so silence never gets amplified into
        // a shape.
        var pk: Float = 0
        for s in samples.suffix(Self.waveN) { pk = max(pk, abs(s)) }
        envelope = pk > envelope ? pk : envelope * 0.985
        let gain = min(6, max(1, 0.45 / max(envelope, 0.02)))

        let tail = samples.suffix(Self.waveN)
        var i = 0
        for s in tail { wave[i] = s * gain; i += 1 }

        // The spectrum, WebAudio-style: window, FFT, |X|/N, smoothed on the
        // magnitude, then dB mapped −100…−30 → 0…255.
        let block = Array(samples.suffix(Self.fftN))
        vDSP.multiply(block, window, result: &windowed)
        windowed.withUnsafeBufferPointer { src in
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.bins) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.bins))
                    }
                    fft.forward(input: split, output: &split)
                }
            }
        }
        let norm = gain / Float(Self.fftN)
        for k in 0..<Self.bins {
            let m = (re[k] * re[k] + im[k] * im[k]).squareRoot() * norm
            mag[k] = 0.72 * mag[k] + 0.28 * m
            let db = 20 * log10(max(mag[k], 1e-9))
            spec[k] = max(0, min(255, (db + 100) / 70 * 255))
        }

        updateBands()
        updateShape(t: Float(t))
        splitWave()
    }

    /// `v(i)` on the page: the waveform at a fraction of its length.
    func v(_ u: Float) -> Float {
        let i = Int(u * Float(Self.waveN - 1))
        return wave[max(0, min(Self.waveN - 1, i))]
    }

    /// The page's `updateBands`, verbatim: a floor that climbs slowly toward
    /// the background, a ceiling that falls very slowly, and a compressive
    /// `^1.7` between them so ordinary speech sits mid-way and only a shout
    /// reaches the top.
    private func updateBands() {
        let NB = Self.NB, n = Float(Self.bins)
        var sum: Float = 0
        for i in 0..<NB {
            let lo = Int(floor(pow(Float(i) / Float(NB), 2) * n * 0.85))
            let hi = max(lo + 1, Int(floor(pow(Float(i + 1) / Float(NB), 2) * n * 0.85)))
            var acc: Float = 0
            for j in lo..<hi { acc += spec[min(Self.bins - 1, j)] }
            let val = acc / Float(hi - lo)
            peak[i] = max(val, peak[i] * 0.9985)
            floorA[i] = val < floorA[i] ? val : floorA[i] + 0.06
            let span = max(22, peak[i] - floorA[i])
            band[i] = pow(max(0, (val - floorA[i] - 2) / span), 1.7)
            sum += band[i]
        }
        let l = min(1, (sum / Float(NB)) * 2.4)
        levelNow += (l - levelNow) * (l > levelNow ? 0.35 : 0.06)
    }

    /// `e(i)` / `eAt(u)`: a band by index, or by fraction of the 64.
    func eAt(_ u: Float) -> Float {
        let i = Int(u * Float(Self.NB - 1))
        return band[min(Self.NB - 1, max(0, i))]
    }

    /// The page's `idleWave`: the slow, ample oscillation that stands in for
    /// the voice while nothing is being said.
    private static func idleWave(_ u: Float, _ t: Float) -> Float {
        0.52 * sin(u * .pi * 2 * 3 + t * 0.42)
            + 0.31 * sin(u * .pi * 2 * 5 - t * 0.29)
            + 0.17 * sin(u * .pi * 2 * 8 + t * 0.19)
    }

    /// The page's `updateShape`: `SHAPE` mixes the idle wave in as the voice
    /// falls away; `LIVE` is strictly the voice, so in silence it is zero and a
    /// ring drawn from it is a perfect circle. Both follow their target with
    /// inertia (0.12 per frame) — *"rămâne un pic în urmă"*.
    private func updateShape(t: Float) {
        idleMix += ((1 - min(1, levelNow * 1.6)) - idleMix) * 0.04
        for i in 0..<Self.shapeN {
            let u = Float(i) / Float(Self.shapeN)
            let liveS = abs(v(u))
            let idle = 0.42 * abs(Self.idleWave(u, t))
            let target = liveS * (1 - idleMix) + idle * idleMix
            shape[i] += (target - shape[i]) * 0.12
            live[i] += (liveS - live[i]) * 0.12
        }
    }

    /// `vs(u)`: the shape with the idle wave in it.
    func vs(_ u: Float) -> Float {
        shape[min(Self.shapeN - 1, max(0, Int(u * Float(Self.shapeN))))]
    }
    /// `vl(u)`: the shape from the voice alone — zero in silence.
    func vl(_ u: Float) -> Float {
        live[min(Self.shapeN - 1, max(0, Int(u * Float(Self.shapeN))))]
    }

    /// The page's `splitWave`: a running mean is the LOW part (the slow
    /// contour), what is left after subtracting it is the HIGH part (the
    /// consonants).
    private func splitWave() {
        let W = 16, n = Self.waveN
        for i in 0..<256 {
            let c = Int(Float(i) / 256 * Float(n - 1))
            var m: Float = 0
            for k in -W...W { m += wave[min(n - 1, max(0, c + k))] }
            m /= Float(2 * W + 1)
            low[i] = m
            high[i] = wave[c] - m
        }
    }

    /// `bass` and `treble` as `drawOrbits` computes them — the page's loop
    /// bounds are fractional (`i < NB/3`), so the first covers 22 bands and
    /// the second the last 22, each divided by 21.33.
    var bassTreble: (Float, Float) {
        let third = Float(Self.NB) / 3
        var bass: Float = 0, treble: Float = 0
        var i = 0
        while Float(i) < third { bass += band[i]; i += 1 }
        i = Int(Float(Self.NB) * 2 / 3)
        while i < Self.NB { treble += band[i]; i += 1 }
        return (bass / third, treble / third)
    }
}

// MARK: - Drawing helpers, in the page's vocabulary

private typealias Pt = (CGFloat, CGFloat)

/// `hsla(h, s%, l%, a)` as a `CGColor`. HSL, not HSB — the page's colours are
/// all written as HSL and `NSColor(hue:saturation:brightness:)` is a different
/// model that would shift every one of them.
private func hsla(_ h: CGFloat, _ s: CGFloat, _ l: CGFloat, _ a: CGFloat) -> CGColor {
    var hue = h.truncatingRemainder(dividingBy: 360)
    if hue < 0 { hue += 360 }
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
    switch hue {
    case ..<60:   (r, g, b) = (c, x, 0)
    case ..<120:  (r, g, b) = (x, c, 0)
    case ..<180:  (r, g, b) = (0, c, x)
    case ..<240:  (r, g, b) = (0, x, c)
    case ..<300:  (r, g, b) = (x, 0, c)
    default:      (r, g, b) = (c, 0, x)
    }
    return CGColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: max(0, min(1, a)))
}

private func rgba(_ c: [CGFloat], _ a: CGFloat) -> CGColor {
    CGColor(srgbRed: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, alpha: max(0, min(1, a)))
}

private extension CGContext {
    func path(_ pts: [Pt], close: Bool) {
        beginPath()
        for (i, p) in pts.enumerated() {
            i == 0 ? move(to: CGPoint(x: p.0, y: p.1)) : addLine(to: CGPoint(x: p.0, y: p.1))
        }
        if close { closePath() }
    }

    /// The page's `strokePath`: a round-capped stroke with a strong glow.
    /// Canvas `shadowBlur` is a Gaussian of σ = blur / 2; CG's `blur` is in
    /// base-space pixels and roughly the same convention, so it is scaled by
    /// the bitmap's scale and nothing else.
    func strokeGlow(_ pts: [Pt], close: Bool, hue: CGFloat, width: CGFloat, alpha: CGFloat, scale: CGFloat) {
        path(pts, close: close)
        setLineWidth(width)
        setLineJoin(.round); setLineCap(.round)
        setStrokeColor(hsla(hue, 0.85, 0.62, alpha))
        setShadow(offset: .zero, blur: width * 5 * scale, color: hsla(hue, 0.95, 0.60, 0.9))
        strokePath()
        setShadow(offset: .zero, blur: 0, color: nil)
    }

    /// The page's `fogPath`: the same path pushed outward by `push` and blown
    /// wide, drawn onto the trail buffer where the feedback will carry it.
    func fogPath(_ pts: [Pt], close: Bool, hue: CGFloat, width: CGFloat, alpha: CGFloat, push: CGFloat, scale: CGFloat) {
        let k = 1 + push
        path(pts.map { ($0.0 * k, $0.1 * k) }, close: close)
        setLineWidth(width)
        setLineJoin(.round); setLineCap(.round)
        setStrokeColor(hsla(hue, 0.80, 0.62, alpha))
        setShadow(offset: .zero, blur: width * 2.4 * scale, color: hsla(hue, 0.90, 0.64, 0.85))
        strokePath()
        setShadow(offset: .zero, blur: 0, color: nil)
    }

    /// The page's `spike`: a bar whose last 25 % fades to nothing instead of
    /// being cut off. A stroke cannot carry a gradient in CG, so the stroked
    /// outline becomes a clip and the gradient is drawn through it; the caller
    /// wraps a whole crown of these in one transparency layer so the glow is
    /// one blur pass rather than a hundred.
    func spike(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat,
               hue: CGFloat, width: CGFloat, alpha: CGFloat) {
        saveGState()
        beginPath()
        move(to: CGPoint(x: ax, y: ay)); addLine(to: CGPoint(x: bx, y: by))
        setLineWidth(width); setLineCap(.butt)
        replacePathWithStrokedPath()
        clip()
        let colors = [hsla(hue, 0.85, 0.62, alpha), hsla(hue, 0.85, 0.62, alpha), hsla(hue, 0.85, 0.62, 0)] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: colors, locations: [0, 0.75, 1]) {
            drawLinearGradient(g, start: CGPoint(x: ax, y: ay), end: CGPoint(x: bx, y: by), options: [])
        }
        restoreGState()
    }

    func fillRadial(cx: CGFloat, cy: CGFloat, r0: CGFloat, r1: CGFloat, stops: [(CGFloat, CGColor)]) {
        saveGState()
        beginPath()
        addEllipse(in: CGRect(x: cx - r1, y: cy - r1, width: r1 * 2, height: r1 * 2))
        clip()
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: stops.map { $0.1 } as CFArray,
                              locations: stops.map { $0.0 }) {
            drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: r0,
                               endCenter: CGPoint(x: cx, y: cy), endRadius: r1,
                               options: [.drawsAfterEndLocation])
        }
        restoreGState()
    }
}

// MARK: - The bead sprites and the orbit strands (page: ORB, orbBuild)

private enum Orb {
    static let STRANDS = 14, BEADS_PER_TURN: CGFloat = 110, BEADS_MAX = 170
    static let ARC_MIN: CGFloat = 0.55, ARC_MAX: CGFloat = 1.35
    static let COMET_FRACTION: CGFloat = 0.34, COMET_RADIUS_BOOST: CGFloat = 1.16
    static let TILT_MIN_DEG: CGFloat = 6, TILT_MAX_DEG: CGFloat = 58, TILT_CAP_DEG: CGFloat = 72
    static let RADIUS_SPREAD: CGFloat = 0.30, WOBBLE: CGFloat = 0.055, WOBBLE_LOBES: CGFloat = 3
    static let PERSPECTIVE: CGFloat = 2.7, RING_FRAC: CGFloat = 0.30, HOLE_FRAC: CGFloat = 0.56
    static let HOLE_SOFT: CGFloat = 0.30, INNER_FADE: CGFloat = 0.34
    static let DOT_NEAR: CGFloat = 7.6, DOT_FAR: CGFloat = 2.4, TAPER: CGFloat = 0.62
    static let GLOW_NEAR: CGFloat = 1.45, GLOW_FAR: CGFloat = 2.2
    static let GLOW_A_NEAR: CGFloat = 0.22, GLOW_A_FAR: CGFloat = 0.20
    static let CORE_A_NEAR: CGFloat = 0.82, CORE_A_FAR: CGFloat = 0.42
    static let CYAN: [CGFloat] = [45, 200, 255], MAGENTA: [CGFloat] = [238, 72, 214], VIOLET: [CGFloat] = [138, 74, 248]
    static let STEPS = 17
    static let IDLE_SPIN: CGFloat = 0.052, SPIN_VAR: CGFloat = 0.55, RETRO: CGFloat = 0.23, PRECESS: CGFloat = 0.021
    static let BREATH_RATE: CGFloat = 0.045, BREATH_AMT: CGFloat = 0.16
    static let A_SPIN: CGFloat = 2.6, A_RADIUS: CGFloat = 0.15, A_SIZE: CGFloat = 0.50
    static let A_BRIGHT: CGFloat = 0.40, A_TILT: CGFloat = 0.55
    static let PULSE_AMP: CGFloat = 0.10, PULSE_LOBES: CGFloat = 2, PULSE_SPEED: CGFloat = 1.35
    static let BLOOM_TIGHT: CGFloat = 5, BLOOM_WIDE: CGFloat = 16
    static let BLOOM_G_TIGHT: CGFloat = 0.40, BLOOM_G_WIDE: CGFloat = 1.05

    static func mix(_ a: [CGFloat], _ b: [CGFloat], _ k: CGFloat) -> [CGFloat] {
        [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k]
    }
    /// 0 = cyan … 1 = magenta, violet in the middle, with the page's `^0.42`
    /// warp so the ends linger.
    static func ramp(_ k: CGFloat) -> [CGFloat] {
        let q = (k - 0.5 >= 0 ? 1 : -1) * pow(abs(2 * k - 1), 0.42)
        let u = 0.5 + 0.5 * q
        return u < 0.5 ? mix(CYAN, VIOLET, u * 2) : mix(VIOLET, MAGENTA, (u - 0.5) * 2)
    }

    struct Sprite { let blob: CGImage; let sq: CGImage }

    /// `orbBuildSprites`: seventeen hues, each a soft blob and a rounded square
    /// bead with a highlight.
    static let sprites: [Sprite] = (0..<STEPS).compactMap { i in
        let c = ramp(CGFloat(i) / CGFloat(STEPS - 1))
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let BS = 96
        guard let bg = CGContext(data: nil, width: BS, height: BS, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let half = CGFloat(BS) / 2
        if let g = CGGradient(colorsSpace: cs, colors: [
            rgba(mix(c, [255, 255, 255], 0.4), 1), rgba(c, 0.88), rgba(c, 0.26), rgba(c, 0.05), rgba(c, 0)
        ] as CFArray, locations: [0, 0.16, 0.40, 0.72, 1]) {
            bg.drawRadialGradient(g, startCenter: CGPoint(x: half, y: half), startRadius: 0,
                                  endCenter: CGPoint(x: half, y: half), endRadius: half, options: [])
        }
        let SS = 48
        guard let sc = CGContext(data: nil, width: SS, height: SS, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(SS), pad = s * 0.10, rr = s * 0.15
        sc.setFillColor(rgba(c, 1))
        sc.addPath(CGPath(roundedRect: CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad),
                          cornerWidth: rr, cornerHeight: rr, transform: nil))
        sc.fillPath()
        if let fg = CGGradient(colorsSpace: cs, colors: [
            rgba(mix(c, [255, 255, 255], 0.12), 0.95), rgba(mix(c, [255, 255, 255], 0.10), 0.35)
        ] as CFArray, locations: [0, 1]) {
            sc.saveGState()
            sc.addPath(CGPath(roundedRect: CGRect(x: s * 0.26, y: s * 0.26, width: s * 0.48, height: s * 0.48),
                              cornerWidth: rr * 0.8, cornerHeight: rr * 0.8, transform: nil))
            sc.clip()
            // The page's gradient runs top-left → bottom-right in y-down space;
            // this context is y-up, so the y ends are swapped to match.
            sc.drawLinearGradient(fg, start: CGPoint(x: s * 0.2, y: s * 0.8), end: CGPoint(x: s * 0.85, y: s * 0.15), options: [])
            sc.restoreGState()
        }
        guard let blob = bg.makeImage(), let sq = sc.makeImage() else { return nil }
        return Sprite(blob: blob, sq: sq)
    }

    final class Strand {
        let hueFrom, hueSpan: CGFloat
        let comet: Bool
        let arc, radius: CGFloat
        let family: Int
        let beads: Int
        let azimuth, tiltBase, tiltPhase, wobblePh, spin: CGFloat
        var theta: CGFloat
        init(i: Int) {
            let fi = CGFloat(i), u = fi / CGFloat(STRANDS)
            let GOLDEN = CGFloat.pi * (3 - sqrt(5))
            comet = (fi * 0.8090169944).truncatingRemainder(dividingBy: 1) < COMET_FRACTION
            arc = 2 * .pi * (comet ? ARC_MIN + 0.25 * (fi * 0.4142).truncatingRemainder(dividingBy: 1)
                                   : 0.95 + (ARC_MAX - 0.95) * (fi * 0.2718).truncatingRemainder(dividingBy: 1))
            let jit = (fi * 0.6180339887).truncatingRemainder(dividingBy: 1)
            radius = (1 + RADIUS_SPREAD * ((fi * 0.7548776662).truncatingRemainder(dividingBy: 1) * 2 - 1))
                * (comet ? COMET_RADIUS_BOOST : 1)
            hueFrom = i % 2 == 0 ? 0.02 + 0.16 * jit : 0.98 - 0.16 * jit
            hueSpan = (0.30 + 0.06 * (fi * 0.3819).truncatingRemainder(dividingBy: 1)) * (i % 2 == 0 ? 1 : -1)
            family = hueFrom + hueSpan * 0.5 < 0.5 ? 0 : 1
            beads = min(BEADS_MAX, max(12, Int((BEADS_PER_TURN * (arc / (2 * .pi)) * radius).rounded())))
            azimuth = fi * GOLDEN + u * 0.6
            tiltBase = (TILT_MIN_DEG + (TILT_MAX_DEG - TILT_MIN_DEG) * jit) * .pi / 180
            tiltPhase = u * 2 * .pi
            wobblePh = u * 2 * .pi * 1.7
            spin = (IDLE_SPIN * (1 + SPIN_VAR * ((fi * 0.3301).truncatingRemainder(dividingBy: 1) * 2 - 1)))
                * ((fi * 0.5391).truncatingRemainder(dividingBy: 1) < RETRO ? -1 : 1)
            theta = u * 2 * .pi * 1.3
        }
    }
}

// MARK: - The renderer

/// **One effect, one bitmap, sixty frames a second.** Built by `CaretHalo`
/// for any style but `.lightning`; `layer` goes where the film would have
/// gone, `step()` is driven by the halo's render timer, and `reset()` clears
/// the fog so a new sentence never starts with the last one's trail.
final class HaloEffectRenderer {
    let style: HaloStyle
    let layer = CALayer()
    /// The panel's side, in points. Everything is drawn in the page's
    /// coordinates — y down, the centre at the origin — inside a square of
    /// this size.
    let side: CGFloat
    /// The page's `R`: the canvas radius, chosen so the effect's resting edge
    /// sits at `CaretHalo.core` — the same diameter the lightning ring has.
    let R: CGFloat
    private let scale: CGFloat = 2
    private let bitmap: CGContext
    private let voice = VoiceAnalyser()
    private var t0 = CFAbsoluteTimeGetCurrent()
    private var lastT: CGFloat = 0
    private var strands: [Orb.Strand] = (0..<Orb.STRANDS).map { Orb.Strand(i: $0) }
    private var scene: CGContext?
    private var mipA: CGContext?
    private var mipB: CGContext?

    /// The voice: the microphone's recent samples, oldest first. Nil while
    /// no meter is running (a foreign microphone, `/test/dictation/start`),
    /// in which case the effect idles on its own slow wave exactly as the
    /// page does before the microphone is turned on.
    var samples: (() -> [Float]?)?
    /// A stand-in for `samples` when there is no microphone at all — the
    /// `WT_HALO_DEMO` run fabricates a voice from `level` this way.
    var syntheticLevel: (() -> Float)?

    init?(style: HaloStyle, side: CGFloat, ringRadius: CGFloat) {
        self.style = style
        self.side = side
        self.R = ringRadius / style.rest
        let px = Int((side * scale).rounded())
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        bitmap = ctx
        layer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        layer.contentsScale = scale
        layer.contentsGravity = .resize
        layer.isOpaque = false
    }

    /// A clean canvas and a fresh clock: called when the ring comes up.
    func reset() {
        let full = CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)
        bitmap.saveGState()
        bitmap.setBlendMode(.copy)
        bitmap.clear(full)
        bitmap.restoreGState()
        t0 = CFAbsoluteTimeGetCurrent()
        lastT = 0
        layer.contents = nil
    }

    private var synthPhase: Float = 0
    private func currentSamples() -> [Float] {
        if let real = samples?() ?? nil { return real }
        // A voice-shaped signal scaled by the demo's level: a few harmonics
        // whose pitch and mix wander, under a syllable envelope, with a little
        // noise — enough for every effect to be seen moving. A steady tone
        // would average out under the shape's inertia into a perfect circle,
        // which is what a steady tone should do and not what a voice does.
        let level = syntheticLevel?() ?? 0
        var out = [Float](repeating: 0, count: MicRecorder.recentCount)
        let f0: Float = 140 + 60 * sin(synthPhase * 1.7)
        for i in 0..<out.count {
            let n = Float(i) / 16000
            let ph = synthPhase + n
            let env = 0.35 + 0.65 * abs(sin(ph * .pi * 4.3))
            let noise = Float.random(in: -1...1) * 0.08
            out[i] = level * env * (0.5 * sin(ph * 2 * .pi * f0) + 0.3 * sin(ph * 2 * .pi * f0 * 2.02 + 1)
                                    + 0.15 * sin(ph * 2 * .pi * f0 * 3.1 + 2) + 0.1 * sin(ph * 2 * .pi * 2900) + noise)
        }
        synthPhase += Float(out.count) / 16000
        return out
    }

    /// **What a frame costs**, logged every 300 frames under `WT_HALO_TRACE=1`.
    /// Every DECAY, ZOOM and TWIST above is *per frame* and was tuned at the
    /// browser's 60 Hz, so a renderer that cannot keep 60 changes every trail's
    /// length and every spiral's pitch; this is the number that says whether
    /// it does.
    private static let trace = ProcessInfo.processInfo.environment["WT_HALO_TRACE"] != nil
    private var frames = 0
    private var busy: CFAbsoluteTime = 0
    private var traceStarted: CFAbsoluteTime = 0

    /// One frame.
    func step() {
        let now = CFAbsoluteTimeGetCurrent()
        let t = CGFloat(now - t0)
        voice.update(samples: currentSamples(), t: now - t0)
        defer {
            if Self.trace {
                busy += CFAbsoluteTimeGetCurrent() - now
                frames += 1
                if traceStarted == 0 { traceStarted = now }
                if frames % 300 == 0 {
                    let wall = now - traceStarted
                    Log.info(String(format: "◯ halo %@: %.1f fps over %d frames, %.1f ms drawing per frame",
                                    style.rawValue, Double(frames) / wall, frames, busy / Double(frames) * 1000))
                }
            }
        }

        let W = CGFloat(bitmap.width), H = CGFloat(bitmap.height)
        let full = CGRect(x: 0, y: 0, width: W, height: H)

        switch style {
        case .lightningChain: feedback(decay: 0.84, zoom: 1.022, twist: 0.004, full: full)
        case .oscillogram:    feedback(decay: 0.80, zoom: 1.007, twist: 0.002, full: full)
        case .twoBalls:       feedback(decay: 0.930, zoom: 1.022, twist: 0.009, full: full)
        case .waveRing:       feedback(decay: 0.88, zoom: 1.006, twist: 0.004, full: full)
        case .orbRays:        feedback(decay: 0.90, zoom: 1.0, twist: 0, full: full)
        default:
            bitmap.saveGState()
            bitmap.setBlendMode(.copy)
            bitmap.clear(full)
            bitmap.restoreGState()
        }

        // The page's frame: y down, the origin at the centre, additive.
        bitmap.saveGState()
        bitmap.translateBy(x: 0, y: H)
        bitmap.scaleBy(x: scale, y: -scale)
        bitmap.translateBy(x: side / 2, y: side / 2)
        bitmap.setBlendMode(.plusLighter)
        switch style {
        case .lightning:      break
        case .lightningChain: drawLightningChain(t)
        case .crown:          drawCrown(t)
        case .segments:       drawSegments(t)
        case .oscillogram:    drawOscillogram(t)
        case .waveRing:       drawWaveRing(t)
        case .twoBalls:       drawTwoBalls(t)
        case .blockBeads:     drawBlockBeads(t)
        case .orbits:         drawOrbits(t, density: 0.5, holeFrac: 1.40, ringFrac: 0.22)
        case .orbRays:        drawOrbRays(t)
        }
        bitmap.restoreGState()
        lastT = t
        layer.contents = bitmap.makeImage()
    }

    /// **The trail.** The previous frame, redrawn a hair bigger, a hair
    /// turned and dimmed to `decay`, and only then is the new ink added. The
    /// `.copy` + `clear` first is what makes it a fade and not a pile-up.
    /// The twist is negated because this pass runs in the bitmap's own y-up
    /// space, and the page's positive angle is clockwise on screen.
    private func feedback(decay: CGFloat, zoom: CGFloat, twist: CGFloat, full: CGRect) {
        guard let prev = bitmap.makeImage() else { return }
        let W = full.width, H = full.height
        bitmap.saveGState()
        bitmap.setBlendMode(.copy)
        bitmap.clear(full)
        bitmap.setBlendMode(.normal)
        bitmap.setAlpha(decay)
        bitmap.translateBy(x: W / 2, y: H / 2)
        bitmap.rotate(by: -twist)
        bitmap.scaleBy(x: zoom, y: zoom)
        bitmap.translateBy(x: -W / 2, y: -H / 2)
        bitmap.draw(prev, in: full)
        bitmap.restoreGState()
    }

    // MARK: Page 1 — wave ring (milkdropRing, LIVE_ONLY)

    /// *inel de undă — cerc perfect în tăcere, se rotește*: the MilkDrop
    /// formula proper — a PCM wave on a circle over feedback — with the shape
    /// taken strictly from the voice so silence leaves a circle. Three strokes
    /// of one path: a wide faint halo, a mid glow, and the line.
    private func drawWaveRing(_ t: CGFloat) {
        let R0: CGFloat = 0.42, AMP: CGFloat = 0.21, W: CGFloat = 1.1, SPIN: CGFloat = 0.30, SEGS = 512
        var pts: [Pt] = []
        for k in 0...SEGS {
            let i = CGFloat(k) / CGFloat(SEGS), th = i * 2 * .pi + t * SPIN
            let seam = max(0, (i - 0.9) / 0.1)
            let sample = CGFloat(voice.vl(Float(i))) * (1 - seam) + CGFloat(voice.vl(0)) * seam
            let r = R * (R0 + AMP * sample)
            pts.append((cos(th) * r, sin(th) * r))
        }
        bitmap.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        bitmap.setLineJoin(.round); bitmap.setLineCap(.round)
        for (width, alpha) in [(W * 14, CGFloat(0.090)), (W * 5.2, 0.22), (W, 0.85)] {
            bitmap.path(pts, close: true)
            bitmap.setLineWidth(width)
            bitmap.setAlpha(alpha)
            bitmap.strokePath()
        }
        bitmap.setAlpha(1)
    }

    // MARK: Page 2 — purple oscillogram

    /// *oscilogramă mov — albastrul și roșul suprapuse*: the LOW half of the
    /// wave in blue and the HIGH half in red, on the same radius, turning
    /// against each other, with a fog of each pushed outward by the trail.
    private func drawOscillogram(_ t: CGFloat) {
        let idleMix = CGFloat(voice.idleMix)
        for kind in 0...1 {
            let src = kind == 1 ? voice.high : voice.low
            let gain: CGFloat = kind == 1 ? 2.4 : 1.1
            let hue: CGFloat = kind == 1 ? 348 : 214
            let N = 256
            var pts: [Pt] = []
            for i in 0...N {
                let u = CGFloat(i % N) / CGFloat(N)
                let th = u * 2 * .pi + t * (kind == 1 ? -0.06 : 0.06)
                let live = min(1, CGFloat(abs(src[i % N])) * gain)
                let amp = live * (1 - idleMix) + CGFloat(voice.vs(Float(u))) * 1.5 * idleMix
                let r = R * (0.52 + 0.225 * amp)
                pts.append((cos(th) * r, sin(th) * r))
            }
            bitmap.fogPath(pts, close: true, hue: hue, width: 22, alpha: 0.030, push: 0.02, scale: scale)
            bitmap.strokeGlow(pts, close: true, hue: hue, width: 3.0, alpha: 0.42, scale: scale)
        }
    }

    // MARK: Page 3 — crown of bars

    /// *coroană — numai barele, fără cerc fix*: 96 spikes on a fixed inner
    /// radius, each lit by a band (spread with `k*7 % N` so neighbours do not
    /// read the same band), amber drifting with time.
    private func drawCrown(_ t: CGFloat) {
        let r0 = R * 0.48, N = 96, WIDTH: CGFloat = 3.4
        bitmap.setShadow(offset: .zero, blur: WIDTH * 2.2 * scale, color: hsla(45, 0.95, 0.60, 0.9))
        bitmap.beginTransparencyLayer(auxiliaryInfo: nil)
        for k in 0..<N {
            let u = CGFloat(k) / CGFloat(N), th = u * 2 * .pi - t * 0.21
            let en = CGFloat(voice.eAt(Float((k * 7) % N) / Float(N)))
            let len = R * (0.022 + 0.087 * en)
            let hue = 32 + t * 5 + en * 40
            bitmap.spike(cos(th) * r0, sin(th) * r0, cos(th) * (r0 + len), sin(th) * (r0 + len),
                         hue: hue, width: WIDTH, alpha: 0.40 + 0.5 * en)
        }
        bitmap.endTransparencyLayer()
        bitmap.setShadow(offset: .zero, blur: 0, color: nil)
    }

    // MARK: Page 4 — ring of segments

    /// *inel de segmente — nuanța se închide fără cusătură*: 150 segments whose
    /// hue makes one full 360° turn round the ring, so the last has the hue of
    /// the first; the energy is read off four quarters doing the same thing.
    private func drawSegments(_ t: CGFloat) {
        let r0 = R * 0.50, M = 150, REST: CGFloat = 0.020
        bitmap.setShadow(offset: .zero, blur: 3.6 * 2.2 * scale, color: hsla(250 + t * 6 + 180, 0.95, 0.60, 0.9))
        bitmap.beginTransparencyLayer(auxiliaryInfo: nil)
        for k in 0..<M {
            let u = CGFloat(k) / CGFloat(M), th = u * 2 * .pi + t * 0.13
            let en = CGFloat(voice.eAt(Float((u * 4).truncatingRemainder(dividingBy: 1))))
            let len = R * (REST + 0.115 * en)
            let hue = 250 + 360 * u + t * 6
            bitmap.spike(cos(th) * r0, sin(th) * r0, cos(th) * (r0 + len), sin(th) * (r0 + len),
                         hue: hue, width: 3.6, alpha: 0.55 + 0.4 * en)
        }
        bitmap.endTransparencyLayer()
        bitmap.setShadow(offset: .zero, blur: 0, color: nil)
    }

    // MARK: Page 5 — lightning chain with fog

    /// *lanț de fulgere — lasă valuri de ceață în urmă*: seven arcs vibrating
    /// on the voice, each **emitting** puffs of fog on its own rhythm which the
    /// trail then pushes outward. The light is emitted, not drawn as a shape.
    private func drawLightningChain(_ t: CGFloat) {
        let M = 7, SEG = 20, r0 = R * 0.46
        let levelNow = CGFloat(voice.levelNow)
        for m in 0..<M {
            let fm = CGFloat(m)
            let a0 = (fm / CGFloat(M)) * 2 * .pi + t * 0.20
            let span = (2 * CGFloat.pi / CGFloat(M)) * 0.80
            let hue = 195 + fm * 6 + t * 12
            let own = 0.35 + 0.65 * pow(max(0, sin(t * (0.7 + fm * 0.23) + fm * 2.1)), 3)
            var pts: [Pt] = []
            for k in 0...SEG {
                let u = CGFloat(k) / CGFloat(SEG), th = a0 + span * u
                let j = CGFloat(voice.vs(Float(m * SEG + k) / Float(M * SEG)))
                let r = r0 * (1 + 0.51 * j + 0.02 * sin(t * 3.1 + fm * 1.7))
                pts.append((cos(th) * r, sin(th) * r))
                if k % 7 == 0 {
                    let a = (0.002 + 0.020 * j) * own * (0.15 + 0.85 * levelNow)
                    if a > 0.004 {
                        let px = cos(th) * r, py = sin(th) * r
                        let rad = R * (0.05 + 0.05 * j)
                        bitmap.fillRadial(cx: px, cy: py, r0: 0, r1: rad,
                                          stops: [(0, hsla(hue, 0.88, 0.64, a)), (1, hsla(hue, 0.88, 0.64, 0))])
                    }
                }
            }
            bitmap.strokeGlow(pts, close: false, hue: hue, width: 3.4, alpha: 0.92, scale: scale)
        }
    }

    // MARK: Page 7 — two balls with fog

    /// *două bile — ceață suflată din contur spre exterior*: two balls opposite
    /// each other, blue and red, turning slowly round the centre; a fog rises
    /// off their contours in waves and only while something is being said,
    /// and the trail's zoom and twist carry it outward in the spiral from the
    /// film. The contours pulse on the voice.
    private func drawTwoBalls(_ t: CGFloat) {
        let orbit = R * 0.52, rb = R * 0.095
        let spin = t * 0.45
        let levelNow = CGFloat(voice.levelNow)
        for side in 0...1 {
            let fs = CGFloat(side)
            let a = spin + fs * .pi
            let cx = cos(a) * orbit, cy = sin(a) * orbit
            let hue: CGFloat = side == 1 ? 210 : 2
            let puff = 0.30 + 0.70 * pow(max(0, sin(t * 1.45 + fs * .pi * 0.7)), 4)
            bitmap.fillRadial(cx: cx, cy: cy, r0: rb * 0.2, r1: rb * 2.1, stops: [
                (0.00, hsla(hue, 0.88, 0.60, (0.006 + 0.13 * levelNow) * puff)),
                (0.45, hsla(hue, 0.88, 0.58, (0.002 + 0.06 * levelNow) * puff)),
                (1.00, hsla(hue, 0.85, 0.60, 0)),
            ])
            let N = 96
            var pts: [Pt] = []
            for k in 0...N {
                let u = CGFloat(k) / CGFloat(N), th = u * 2 * .pi
                let v = CGFloat(voice.vl(Float((u + fs * 0.5).truncatingRemainder(dividingBy: 1))))
                let r = rb * (1 + 0.85 * v + 0.05 * sin(t * 2.3 + fs))
                pts.append((cx + cos(th) * r, cy + sin(th) * r))
            }
            bitmap.strokeGlow(pts, close: true, hue: hue + 10, width: 2.0, alpha: 0.55, scale: scale)
            bitmap.strokeGlow(pts, close: true, hue: hue + 10, width: 7.0, alpha: 0.045, scale: scale)
        }
    }

    // MARK: The bead scene and its bloom (page: orbSC, orbBloom)

    /// The page draws beads into a scene canvas and blooms it through two
    /// mip levels — *cheap bloom: two mip levels instead of `ctx.filter`, ~4×
    /// cheaper*. Same here: a scene context at the bitmap's size, two small
    /// ones, drawn back additively at their gains.
    private func sceneContexts() -> (CGContext, CGContext, CGContext)? {
        if let s = scene, let a = mipA, let b = mipB { return (s, a, b) }
        let px = bitmap.width
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func make(_ n: Int) -> CGContext? {
            let c = CGContext(data: nil, width: max(1, n), height: max(1, n), bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            c?.interpolationQuality = .low
            return c
        }
        guard let s = make(px), let a = make(Int((CGFloat(px) / Orb.BLOOM_TIGHT).rounded())),
              let b = make(Int((CGFloat(px) / Orb.BLOOM_WIDE).rounded())) else { return nil }
        s.setAllowsAntialiasing(true)
        scene = s; mipA = a; mipB = b
        return (s, a, b)
    }

    /// Runs `draw` in the scene (page coordinates, additive) and composites
    /// the bloom plus the scene onto the bitmap.
    private func withBloom(gWide: CGFloat, gTight: CGFloat, _ draw: (CGContext) -> Void) {
        guard let (s, a, b) = sceneContexts() else { return }
        let px = CGFloat(s.width)
        s.saveGState()
        s.setBlendMode(.copy)
        s.clear(CGRect(x: 0, y: 0, width: px, height: px))
        s.restoreGState()
        s.saveGState()
        s.translateBy(x: 0, y: px)
        s.scaleBy(x: scale, y: -scale)
        s.translateBy(x: side / 2, y: side / 2)
        s.setBlendMode(.plusLighter)
        draw(s)
        s.restoreGState()
        guard let sceneImage = s.makeImage() else { return }
        for m in [a, b] {
            let n = CGFloat(m.width)
            m.saveGState(); m.setBlendMode(.copy); m.clear(CGRect(x: 0, y: 0, width: n, height: n)); m.restoreGState()
            m.draw(sceneImage, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        guard let ia = a.makeImage(), let ib = b.makeImage() else { return }
        // Back in the page frame the caller set up: a square of `side` points
        // centred on the origin.
        let box = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
        bitmap.saveGState()
        // Images are drawn upright in y-up space; the frame is flipped, so
        // flip back for the three blits.
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.setAlpha(gWide);  bitmap.draw(ib, in: box)
        bitmap.setAlpha(gTight); bitmap.draw(ia, in: box)
        bitmap.setAlpha(1);      bitmap.draw(sceneImage, in: box)
        bitmap.restoreGState()
    }

    /// A sprite in the page frame — the frame is y-flipped, so the image is
    /// drawn through a local un-flip about its own centre.
    private func blit(_ ctx: CGContext, _ img: CGImage, x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: x, y: y)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setAlpha(alpha)
        ctx.draw(img, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
        ctx.restoreGState()
    }

    // MARK: Page 18 — block-bead ring

    /// *inel de blocuri — cerc în repaus, crește doar în afară*: 132 square
    /// beads on a circle, a perfect circle at rest (the amplitude is strictly
    /// the voice's), pushed outward only, the bead size breathing even in
    /// silence — the shimmer.
    private func drawBlockBeads(_ t: CGFloat) {
        withBloom(gWide: 0.95, gTight: 0.40) { s in
            let M = 132
            for k in 0..<M {
                let u = CGFloat(k) / CGFloat(M)
                let th = u * 2 * .pi + t * 0.22
                let amp = CGFloat(voice.vl(Float(u)))
                let r = R * (0.35 + 0.12 * amp)
                let X = cos(th) * r, Y = sin(th) * r
                let shimmer = 0.5 + 0.5 * sin(t * 2.1 + u * .pi * 12)
                let size = 4.2 + 1.2 * shimmer + 8.0 * min(1, amp * 1.6)
                let hue = (u + t * 0.05).truncatingRemainder(dividingBy: 1)
                let spr = Orb.sprites[min(Orb.STEPS - 1, Int(hue * CGFloat(Orb.STEPS)))]
                let gm = size * 2.1
                blit(s, spr.blob, x: X, y: Y, size: gm, alpha: 0.18 + 0.27 * amp)
                blit(s, spr.sq, x: X, y: Y, size: size, alpha: 0.55 + 0.45 * min(1, amp * 1.5))
            }
        }
    }

    // MARK: Page 6 — sparse particle orbits (drawOrbits)

    /// *orbite rare — gaură mare, blocuri clare*: the orbit reconstruction from
    /// the film, at half density with a hole 2.5× larger and the ring drawn
    /// closer in so the front beads are not cut by the square's edge. Each
    /// strand is a chain of beads on its own orbital plane; depth is
    /// normalised per strand, bead count follows arc length, and the spread
    /// of tilts is what the voice drives.
    private func drawOrbits(_ t: CGFloat, density: CGFloat, holeFrac: CGFloat, ringFrac: CGFloat) {
        let used = max(3, Int((CGFloat(strands.count) * density).rounded()))
        let gain: CGFloat = density < 1 ? 0.55 : 1
        let dt = min(0.05, lastT > 0 ? t - lastT : 0.016)
        let (bassF, trebleF) = voice.bassTreble
        let bass = CGFloat(bassF), treble = CGFloat(trebleF)
        let level = CGFloat(voice.levelNow)
        let R0 = (R * 2) * ringFrac * (1 + Orb.A_RADIUS * level)
        let holeR = R0 * holeFrac, F = Orb.PERSPECTIVE
        let dotNear = Orb.DOT_NEAR * (1 + Orb.A_SIZE * level)
        let dotFar = Orb.DOT_FAR * (1 + Orb.A_SIZE * level * 0.5)
        let bright = 1 + Orb.A_BRIGHT * level
        let spinMul = 1 + Orb.A_SPIN * level

        withBloom(gWide: Orb.BLOOM_G_WIDE * gain, gTight: Orb.BLOOM_G_TIGHT * gain) { s in
            for si in 0..<used {
                let st = strands[si]
                let famDrive = st.family == 0 ? 1 + 0.55 * treble : 1 + 0.55 * bass
                st.theta += st.spin * spinMul * famDrive * dt
                let azim = st.azimuth + Orb.PRECESS * t * (st.family == 0 ? 1 : -0.7)
                let tilt = st.tiltBase
                    * (1 + Orb.BREATH_AMT * sin(t * Orb.BREATH_RATE * 2 * .pi + st.tiltPhase))
                    * (1 + Orb.A_TILT * level)
                let tc = min(tilt, Orb.TILT_CAP_DEG * .pi / 180)
                let ca = cos(azim), sa = sin(azim), ct = cos(tc), stt = sin(tc)
                let N = st.beads
                for i in 0..<N {
                    let u = CGFloat(i) / CGFloat(N - 1), th = st.theta + u * st.arc
                    var rr = R0 * st.radius * (1 + Orb.WOBBLE * sin(Orb.WOBBLE_LOBES * th + st.wobblePh))
                    rr += R0 * Orb.PULSE_AMP * level
                        * (0.5 + 0.5 * sin(Orb.PULSE_LOBES * th - t * Orb.PULSE_SPEED * 2 * .pi))
                    let cth = cos(th), sth = sin(th)
                    let x3 = rr * (cth * ca + sth * (-sa * ct))
                    let y3 = rr * (cth * sa + sth * (ca * ct))
                    let z3 = rr * (sth * stt)
                    let zn = z3 / R0, persp = F / (F - zn)
                    let zAmp = max(0.12, stt * st.radius)
                    let depth = min(1, max(0, (zn / zAmp + 1) * 0.5))
                    var X = x3 * persp, Y = y3 * persp
                    let d = hypot(X, Y)
                    if d < holeR * (1 + Orb.HOLE_SOFT) {           // nothing enters the hole
                        let target = holeR * (1 + Orb.HOLE_SOFT * (d / (holeR * (1 + Orb.HOLE_SOFT))))
                        let k = target / max(d, 1e-3); X *= k; Y *= k
                    }
                    let dist = hypot(X, Y)
                    let innerFade = min(1, max(0, (dist - holeR) / (holeR * Orb.INNER_FADE)))
                    if innerFade <= 0.001 { continue }
                    let taper = st.comet
                        ? pow(u, 0.45) * (1 - Orb.TAPER * pow(1 - u, 1.4))
                        : 1 - Orb.TAPER * 0.45 * pow(abs(2 * u - 1), 2.2)
                    let size = (dotFar + (dotNear - dotFar) * pow(depth, 1.35)) * taper
                    if size < 0.35 { continue }
                    var hue = st.hueFrom + st.hueSpan * u; hue -= floor(hue)
                    let spr = Orb.sprites[min(Orb.STEPS - 1, Int(hue * CGFloat(Orb.STEPS)))]
                    let glowA = (Orb.GLOW_A_FAR + (Orb.GLOW_A_NEAR - Orb.GLOW_A_FAR) * depth) * taper * bright * innerFade
                    let coreA = (Orb.CORE_A_FAR + (Orb.CORE_A_NEAR - Orb.CORE_A_FAR) * pow(depth, 1.6)) * taper * bright * innerFade
                    let gm = (depth > 0.5 ? Orb.GLOW_NEAR : Orb.GLOW_FAR) * size
                    blit(s, spr.blob, x: X, y: Y, size: gm, alpha: min(1, glowA * (density < 1 ? 0.45 : 1)))
                    blit(s, spr.sq, x: X, y: Y, size: size, alpha: min(1, coreA))
                }
            }
        }
    }

    // MARK: Page 8 — ORB rays, no flash

    /// *raze ORB — petale rotitoare, fără flash*: from the preset "ORB - Waaa".
    /// Three overlaid shapes (7, 6 and 5 petals), turned at close speeds with
    /// one in reverse — `q2`, `−1.05 q2`, `0.899 q2`, which is where the slow
    /// beat between layers comes from — coloured by the preset's own sinusoids.
    /// What was taken out is the core: in the preset the petals converge into a
    /// blinding white point; here each petal **fades to nothing toward the
    /// centre** through its gradient, so the rays pass but nothing lights up in
    /// the middle. The page draws this on a full-viewport canvas; here `S` is
    /// the panel's side.
    private func drawOrbRays(_ t: CGFloat) {
        struct Layer { let n: Int; let spin, len, wide, a: CGFloat; let ph: [CGFloat] }
        let S = side
        let q2 = t * 0.55
        let layers = [
            Layer(n: 7, spin:  1.000, len: 0.30, wide: 0.055, a: 0.70, ph: [0.350, 0.578, 0.689]),
            Layer(n: 6, spin: -1.050, len: 0.44, wide: 0.045, a: 0.60, ph: [0.450, 0.678, 0.689]),
            Layer(n: 5, spin:  0.899, len: 0.60, wide: 0.036, a: 0.50, ph: [0.450, 0.578, 0.789]),
        ]
        let lit = 0.45 + 0.85 * CGFloat(voice.levelNow)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        for L in layers {
            let col: [CGFloat] = L.ph.map { (255 * (0.5 + 0.5 * sin($0 * q2))).rounded() }
            for k in 0..<L.n {
                let fk = CGFloat(k) / CGFloat(L.n)
                let a = q2 * L.spin + fk * 2 * .pi
                let en = 0.35 + 0.65 * CGFloat(voice.eAt(Float((fk + L.len).truncatingRemainder(dividingBy: 1))))
                let rOut = S * L.len * (0.75 + 0.45 * en)
                let halfW = S * L.wide * (0.6 + 0.6 * en)
                let ca = cos(a), sa = sin(a)
                // The petal: a spindle from the centre outward, widest mid-way.
                let P = 22
                var pts: [Pt] = []
                for i in 0...P {
                    let u = CGFloat(i) / CGFloat(P), w = sin(.pi * u) * halfW
                    pts.append((ca * rOut * u - sa * w, sa * rOut * u + ca * w))
                }
                for i in stride(from: P, through: 0, by: -1) {
                    let u = CGFloat(i) / CGFloat(P), w = -sin(.pi * u) * halfW
                    pts.append((ca * rOut * u - sa * w, sa * rOut * u + ca * w))
                }
                guard let g = CGGradient(colorsSpace: cs, colors: [
                    rgba(col, 0), rgba(col, 0.10 * L.a * lit), rgba(col, 0.55 * L.a * lit), rgba(col, 0)
                ] as CFArray, locations: [0, 0.22, 0.55, 1]) else { continue }
                bitmap.saveGState()
                bitmap.path(pts, close: true)
                bitmap.clip()
                bitmap.drawLinearGradient(g, start: .zero, end: CGPoint(x: ca * rOut, y: sa * rOut), options: [])
                bitmap.restoreGState()
            }
        }
    }
}
