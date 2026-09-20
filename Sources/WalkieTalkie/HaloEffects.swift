import AppKit
import Accelerate
import QuartzCore

/// **The audio-reactive halo effects, ported from the `voice-halo` web page.**
///
/// Source of truth: `~/workspace/voice-halo/index.html` (and `water.js`) at
/// git tag **`swift-port-02`** (commit d832097; the first pass was
/// `swift-port-01`, 6717b17). Every formula, constant and comment about *why*
/// a number is what it is comes from those files; where this port deviates it
/// says so beside the line. A later pass resumes from the diff between tags.
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
/// *ORB rays* was ported in the first pass and **removed at `swift-port-02`**:
/// Victor marked it `−` in the review (his verdicts live in the effect names on
/// the page — `★` likes, `•` has potential, `−` dislikes — and a `−` is not
/// ported). No hand-written effect carries a `★` or `•` at this tag, so the
/// menu titles carry no marks yet; `HaloStyle.mark` is where they go when one
/// does.
///
/// **Since `swift-port-02` every effect on the page draws on a viewport-sized
/// canvas**, with the trail's zoom pivoting on the pointer — which is what this
/// panel has done from the start, so the change here is only that sizes derive
/// from the page's `scale` field (`0.40 / rest`, same size on screen). One
/// effect is genuinely screen-sized: **water** (`water.js`) puts a pool across
/// the bottom fifth of the *screen* and orbits the pointer with comets, so for
/// it `CaretHalo` builds a panel the size of the pointer's screen and hands the
/// pointer in as `center` every frame.
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
    /// Page 19 (`water.js`): *apă — comete oglindite în apa de jos*.
    case water
    /// **The MilkDrop presets pinned on the page**, run by the real engine in
    /// a web view (`MilkDropHalo`) — Victor's reversal of 2026-09-20, *"migrate
    /// the MilkDrop ones to Swift as well"*. The `−` ones (44, 77, 97) are not
    /// here. Numbers are the page's positions; `scale` and `fade` are his.
    case milkdrop7, milkdrop8, milkdrop20, milkdrop85, milkdrop87, milkdrop99, milkdrop103

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
        case .water:          return "Water with mirrored comets"
        case .milkdrop7:      return "MilkDrop 7 — Geiss, 3 layers (Tunnel Mix)"
        case .milkdrop8:      return "MilkDrop 8 — Geiss, Cauldron painterly 2"
        case .milkdrop20:     return "MilkDrop 20 — Aderrasi, Painterly Tendrils"
        case .milkdrop85:     return "MilkDrop 85 — Zylot, Star Ornament (small)"
        case .milkdrop87:     return "MilkDrop 87 — martin, chain breaker"
        case .milkdrop99:     return "MilkDrop 99 — martin, reflections on black tiles"
        case .milkdrop103:    return "MilkDrop 103 — fata morgana (water, mirrored)"
        }
    }

    /// Victor's review mark, as the page carries it in the effect's name
    /// (`★` likes a lot, `•` has potential) — the reason the list is ordered
    /// as it is. Empty for every hand-written effect at `swift-port-02`. A
    /// `−` is never here, because a `−` effect is not ported.
    var mark: String {
        switch self {
        case .milkdrop7, .milkdrop20:                return "•"
        case .milkdrop87, .milkdrop99, .milkdrop103: return "★"
        default:                                     return ""
        }
    }

    /// **A preset run by the engine**: the page's `preset:` row. `scale`
    /// shrinks the canvas on screen (the composition intact); `fade` is the
    /// radial dimming asked for on 7, where the rings coming at the viewer
    /// whited the whole screen.
    struct Preset { let number: Int; let name: String; let scale: CGFloat; let fade: Bool }
    var preset: Preset? {
        switch self {
        case .milkdrop7:   return Preset(number: 7, name: "Geiss - 3 layers (Tunnel Mix)", scale: 1, fade: true)
        case .milkdrop8:   return Preset(number: 8, name: "Geiss - Cauldron - painterly 2 (saturation remix)", scale: 0.70, fade: false)
        case .milkdrop20:  return Preset(number: 20, name: "Aderrasi + Geiss - Airhandler (Kali Mix) - Painterly Tendrils Colorfast", scale: 0.70, fade: false)
        case .milkdrop85:  return Preset(number: 85, name: "Zylot - Star Ornament", scale: 0.33, fade: false)
        case .milkdrop87:  return Preset(number: 87, name: "martin - chain breaker", scale: 1, fade: false)
        case .milkdrop99:  return Preset(number: 99, name: "martin - reflections on black tiles", scale: 1, fade: false)
        case .milkdrop103: return Preset(number: 103, name: "martin [shadow harlequins shape code] - fata morgana", scale: 1, fade: false)
        default:           return nil
        }
    }

    /// Can this style be drawn on this Mac right now? Only the presets can
    /// say no — when the engine is not bundled.
    var isAvailable: Bool { preset == nil || MilkDropHalo.engineAvailable }

    /// `mark` + `title`, for the menu.
    var menuTitle: String { mark.isEmpty ? title : "\(mark) \(title)" }

    /// **The page's `scale`** (since `swift-port-02`): the effect's reference
    /// radius as a fraction of the viewport's short side, replacing `rest`
    /// (`scale = 0.40 / rest`, so nothing moved on screen). Here the reference
    /// radius is `CaretHalo.core` at `scale` 0.40, so `R = core / 0.40 × scale`.
    var scale: CGFloat {
        switch self {
        case .lightning:      return 0.40
        case .lightningChain: return 0.50
        case .crown:          return 0.606
        case .segments:       return 0.625
        case .oscillogram:    return 0.606
        case .waveRing:       return 0.606
        case .twoBalls:       return 0.4545
        case .blockBeads:     return 0.80
        case .orbits:         return 0.348
        case .water:          return 0.40      // unused: the comets size off the screen
        default:              return 0.40      // the presets: `preset.scale` is the one that matters
        }
    }

    /// **Drawn on a panel the size of the pointer's screen**, not the ring's
    /// square — the water is anchored to the bottom of the screen and the
    /// comets orbit far wider than the panel.
    var coversScreen: Bool { self == .water }

    /// **Drawn on a square of side `max(w, h)` of the screen × `preset.scale`,
    /// centred on the pointer and following it** — the page's "cover" canvas
    /// for a pinned preset, with the cursor at its centre.
    var coversPointer: Bool { preset != nil }

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
    /// The panel's size, in points — the ring's square for every effect but
    /// the water, which gets the pointer's screen. Everything is drawn in the
    /// page's coordinates: y down, the origin at `center`.
    let width: CGFloat, height: CGFloat
    /// `min(width, height)`, the page's `min(innerWidth, innerHeight)`.
    var side: CGFloat { min(width, height) }
    /// **Where the pointer is**, in page coordinates (y down from the panel's
    /// top-left). The square effects keep it at the middle; `CaretHalo`
    /// writes it every frame for a screen-sized panel.
    var center: CGPoint
    /// The page's `rad(scale)`: the effect's reference radius, chosen so the
    /// ring sits at `CaretHalo.core` — the same diameter the lightning ring has.
    let R: CGFloat
    /// Device pixels per point. 2 for the ring's square; **1 for a
    /// screen-sized panel** — the water has no hairline in it, and at 2× a
    /// 3456×2234 bitmap copied twice a frame plus 73 slice blits ran under
    /// 20 fps. Every size in the effects is in points, so nothing else knows.
    private let scale: CGFloat
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
    init?(style: HaloStyle, size: CGSize, ringRadius: CGFloat) {
        self.style = style
        self.width = size.width
        self.height = size.height
        self.center = CGPoint(x: size.width / 2, y: size.height / 2)
        self.R = ringRadius / 0.40 * style.scale
        self.scale = style.coversScreen ? 1 : 2
        let px = Int((size.width * scale).rounded()), py = Int((size.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = style.coversScreen ? .low : .high
        bitmap = ctx
        layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
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

    private func currentSamples() -> [Float] {
        samples?() ?? nil ?? [Float](repeating: 0, count: MicRecorder.recentCount)
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
                if frames % 60 == 0 {
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
        default:
            bitmap.saveGState()
            bitmap.setBlendMode(.copy)
            bitmap.clear(full)
            bitmap.restoreGState()
        }

        // The page's frame: y down, the origin at the pointer, additive — the
        // page's `tunnelLayer` / `plainLayer` since `swift-port-02`.
        bitmap.saveGState()
        bitmap.translateBy(x: 0, y: H)
        bitmap.scaleBy(x: scale, y: -scale)
        bitmap.translateBy(x: center.x, y: center.y)
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
        case .water:          drawWater(t)
        default:              break            // the presets draw in a web view, not here
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
        // Pivot on the pointer, not the panel's middle — the page's
        // `tunnelLayer` since `swift-port-02` (*"urma să fie suflată din
        // efect, nu dintr-un punct fix de pe ecran"*). The same point for the
        // square effects, where the pointer is the middle.
        let px = center.x * scale, py = H - center.y * scale
        bitmap.translateBy(x: px, y: py)
        bitmap.rotate(by: -twist)
        bitmap.scaleBy(x: zoom, y: zoom)
        bitmap.translateBy(x: -px, y: -py)
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
            // The constant term is the resting floor, the `levelNow` term the
            // voice. At 0.006 the balls looked dead in silence; since
            // `swift-port-02` the floor is ~6× higher — a visible wisp — and
            // the gain on the voice is untouched, so loud looks the same.
            bitmap.fillRadial(cx: cx, cy: cy, r0: rb * 0.2, r1: rb * 2.1, stops: [
                (0.00, hsla(hue, 0.88, 0.60, (0.035 + 0.13 * levelNow) * puff)),
                (0.45, hsla(hue, 0.88, 0.58, (0.014 + 0.06 * levelNow) * puff)),
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
        let pw = bitmap.width, ph = bitmap.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func make(_ w: Int, _ h: Int) -> CGContext? {
            let c = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            c?.interpolationQuality = .low
            return c
        }
        func down(_ n: Int, _ k: CGFloat) -> Int { Int((CGFloat(n) / k).rounded()) }
        guard let s = make(pw, ph), let a = make(down(pw, Orb.BLOOM_TIGHT), down(ph, Orb.BLOOM_TIGHT)),
              let b = make(down(pw, Orb.BLOOM_WIDE), down(ph, Orb.BLOOM_WIDE)) else { return nil }
        s.setAllowsAntialiasing(true)
        scene = s; mipA = a; mipB = b
        return (s, a, b)
    }

    /// Runs `draw` in the scene (page coordinates, additive) and composites
    /// the bloom plus the scene onto the bitmap.
    private func withBloom(gWide: CGFloat, gTight: CGFloat, _ draw: (CGContext) -> Void) {
        guard let (s, a, b) = sceneContexts() else { return }
        let pw = CGFloat(s.width), ph = CGFloat(s.height)
        s.saveGState()
        s.setBlendMode(.copy)
        s.clear(CGRect(x: 0, y: 0, width: pw, height: ph))
        s.restoreGState()
        s.saveGState()
        s.translateBy(x: 0, y: ph)
        s.scaleBy(x: scale, y: -scale)
        s.translateBy(x: center.x, y: center.y)
        s.setBlendMode(.plusLighter)
        draw(s)
        s.restoreGState()
        guard let sceneImage = s.makeImage() else { return }
        for m in [a, b] {
            let mw = CGFloat(m.width), mh = CGFloat(m.height)
            m.saveGState(); m.setBlendMode(.copy); m.clear(CGRect(x: 0, y: 0, width: mw, height: mh)); m.restoreGState()
            m.draw(sceneImage, in: CGRect(x: 0, y: 0, width: mw, height: mh))
        }
        guard let ia = a.makeImage(), let ib = b.makeImage() else { return }
        // Back in the page frame the caller set up: the whole panel, with the
        // origin at the pointer.
        let box = CGRect(x: -center.x, y: -center.y, width: width, height: height)
        bitmap.saveGState()
        // Images are drawn upright in y-up space; the frame is flipped, so
        // flip back for the three blits (about the panel's own middle, so the
        // box lands where the scene was).
        bitmap.translateBy(x: 0, y: height - 2 * center.y)
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

    // MARK: Page 19 — water with mirrored comets (water.js)

    /// **The scene from `water.js`, on a panel the size of the screen.** A pool
    /// across the bottom fifth, four comets orbiting the pointer with tapering
    /// tails, and everything above the waterline mirrored into the pool with
    /// ripples that grow with depth and with the voice. Its file names what is
    /// load-bearing and every one of those is kept: the **draw order** (sky
    /// offscreen → sky on screen → water gradient → reflection slices →
    /// multiply tint → specular + waterline), the **blend modes** (`lighter`
    /// for the slices, `multiply` for the depth tint, `source-over` at the
    /// end), the single **vertical flip about the waterline** with
    /// `REFLECT_SQUASH`, and **`SKY_MARGIN` consumed by sampling** into the
    /// margin (`sx`) rather than offsetting the destination — the thing that
    /// stops a hard vertical seam at the pool's edge.
    ///
    /// **One deviation, and it is the overlay's**: the page's sky is opaque
    /// (`BG_TOP → BG_BOT`, and the canvas is `alpha: false`) because it is a
    /// scene; over his work the sky is left **transparent** — the stars, the
    /// centre halo and the comets draw over whatever is there, and the
    /// reflection adds only their light, exactly as `lighter` over a black sky
    /// would. The pool itself stays opaque, as on the page: a pool is a pool.
    private enum Water {
        static let WATER_Y: CGFloat = 0.80
        static let SKY_MARGIN: CGFloat = 56
        static let SLICE_H: CGFloat = 3
        static let REFLECT_ALPHA: CGFloat = 1.00, REFLECT_FADE: CGFloat = 1.35, REFLECT_SQUASH: CGFloat = 0.42
        static let TINT_TOP: [CGFloat] = [232, 240, 255], TINT_BOT: [CGFloat] = [126, 176, 255]
        static let RIPPLE_AMP: CGFloat = 9.0, RIPPLE_DEPTH_GAIN: CGFloat = 1.0, RIPPLE_MIN: CGFloat = 0.12
        static let RIPPLE_F1: CGFloat = 0.055, RIPPLE_S1: CGFloat = 1.25
        static let RIPPLE_F2: CGFloat = 0.017, RIPPLE_S2: CGFloat = 0.62
        static let RIPPLE_AUDIO: CGFloat = 2.4
        struct Comet { let r, spd, hue, w, tail, phase: CGFloat }
        static let COMETS = [
            Comet(r: 0.30, spd:  0.62, hue: 190, w: 3.4, tail: 1.05, phase: 0.0),
            Comet(r: 0.46, spd: -0.41, hue: 265, w: 2.8, tail: 0.85, phase: 2.1),
            Comet(r: 0.62, spd:  0.29, hue: 160, w: 2.2, tail: 0.70, phase: 4.0),
            Comet(r: 0.80, spd: -0.19, hue: 325, w: 1.7, tail: 0.55, phase: 5.4),
        ]
        static let TAIL_SEGMENTS = 22
        static let TAIL_AUDIO: CGFloat = 0.9, SPEED_AUDIO: CGFloat = 1.8, BRIGHT_AUDIO: CGFloat = 0.85
        static let HEAD_R: CGFloat = 5.5, BASS_RADIUS: CGFloat = 0.10, TREBLE_FLICKER: CGFloat = 0.35
        static let CENTER_CLEAR_R: CGFloat = 26, CENTER_HALO_R: CGFloat = 92
        static let STARS = 110
        static let WATER_TOP: [CGFloat] = [8, 16, 34], WATER_BOT: [CGFloat] = [2, 4, 11]
    }
    private struct Star { let x, y, r, a, tw: CGFloat }
    private var stars: [Star] = []
    private var skyCtx: CGContext?

    /// Canvas `drawImage` semantics inside the page frame: the image upright
    /// in page coordinates, whatever the CTM. CG hangs an image's top at the
    /// rect's *maximum* y, which in a flipped frame is its bottom; the local
    /// un-flip about the rect's middle puts it the way the page has it — and
    /// under the page's own mirror flip it therefore mirrors, as it should.
    private func pageImage(_ ctx: CGContext, _ img: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: rect.minX, y: -rect.height / 2, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private func linearFill(_ ctx: CGContext, rect: CGRect, from: CGPoint, to: CGPoint, stops: [(CGFloat, CGColor)]) {
        ctx.saveGState()
        ctx.clip(to: rect)
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 }) {
            ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
    }

    private func drawWater(_ t: CGFloat) {
        // The frame the caller set up has its origin at the pointer; the water
        // is in absolute page coordinates, so step back to the panel's corner.
        bitmap.translateBy(x: -center.x, y: -center.y)
        let W = width, H = height
        let waterY = (H * Water.WATER_Y).rounded(), waterH = H - waterY
        let M = Water.SKY_MARGIN
        let level = CGFloat(voice.levelNow)
        let (bassF, trebleF) = voice.bassTreble
        let bass = CGFloat(bassF), treble = CGFloat(trebleF)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!

        if skyCtx == nil {
            skyCtx = CGContext(data: nil, width: Int(((W + 2 * M) * scale).rounded()), height: Int((waterY * scale).rounded()),
                               bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            skyCtx?.setAllowsAntialiasing(true)
            stars = (0..<Water.STARS).map { _ in
                Star(x: -M + CGFloat.random(in: 0...1) * (W + 2 * M), y: CGFloat.random(in: 0...1) * waterY,
                     r: 0.4 + CGFloat.random(in: 0...1) * 1.2, a: 0.22 + CGFloat.random(in: 0...1) * 0.7,
                     tw: CGFloat.random(in: 0...1) * 6.28)
            }
        }
        guard let sky = skyCtx else { return }

        // ---------- 1. the sky (offscreen): everything that will reflect.
        // Page coordinates, shifted by the margin; transparent (see above).
        sky.saveGState()
        sky.setBlendMode(.copy)
        sky.clear(CGRect(x: 0, y: 0, width: sky.width, height: sky.height))
        sky.restoreGState()
        sky.saveGState()
        sky.translateBy(x: 0, y: CGFloat(sky.height))
        sky.scaleBy(x: scale, y: -scale)
        sky.translateBy(x: M, y: 0)
        sky.setBlendMode(.plusLighter)
        for s in stars {
            let a = s.a * (0.65 + 0.35 * sin(t * 0.8 + s.tw))
            sky.setFillColor(CGColor(srgbRed: 200 / 255, green: 220 / 255, blue: 1, alpha: a))
            sky.fillEllipse(in: CGRect(x: s.x - s.r, y: s.y - s.r, width: 2 * s.r, height: 2 * s.r))
        }
        // The centre halo: a soft ring whose inner edge ramps up only past
        // CENTER_CLEAR_R, so the cursor sits on untouched background — ramped,
        // not punched; a hard hole reads as a black disc against the glow.
        let HR = Water.CENTER_HALO_R * (1 + 0.5 * bass)
        let cf = min(0.85, Water.CENTER_CLEAR_R / HR)
        sky.fillRadial(cx: center.x, cy: center.y, r0: 0, r1: HR, stops: [
            (0, CGColor(srgbRed: 90 / 255, green: 150 / 255, blue: 1, alpha: 0)),
            (cf, CGColor(srgbRed: 90 / 255, green: 150 / 255, blue: 1, alpha: 0)),
            (min(0.98, cf + 0.26), CGColor(srgbRed: 110 / 255, green: 175 / 255, blue: 1, alpha: 0.11 + 0.24 * level)),
            (1, CGColor(srgbRed: 60 / 255, green: 90 / 255, blue: 200 / 255, alpha: 0)),
        ])
        // The comets.
        let unit = min(W, H) * 0.5
        let speed = 1 + Water.SPEED_AUDIO * level
        sky.setLineCap(.round)
        for (i, c) in Water.COMETS.enumerated() {
            let fi = CGFloat(i)
            let Rc = unit * c.r * (1 + Water.BASS_RADIUS * bass * sin(t * 0.7 + fi))
            let ang = c.phase + t * c.spd * speed
            let span = c.tail * (1 + Water.TAIL_AUDIO * level) * (c.spd < 0 ? -1 : 1)
            let flick = 1 + Water.TREBLE_FLICKER * treble * sin(t * 9.1 + fi * 2.3)
            let bri = (1 + Water.BRIGHT_AUDIO * level) * flick
            let col = { (a: CGFloat) in hsla(c.hue + 25 * level, 1, (62 + 12 * level) / 100, a) }
            var px = center.x + cos(ang) * Rc, py = center.y + sin(ang) * Rc
            for j in 1...Water.TAIL_SEGMENTS {
                let f = CGFloat(j) / CGFloat(Water.TAIL_SEGMENTS)
                let a2 = ang - span * f
                let nx = center.x + cos(a2) * Rc, ny = center.y + sin(a2) * Rc
                let fade = (1 - f) * (1 - f)
                sky.setStrokeColor(col(min(1, 0.55 * fade * bri)))
                sky.setLineWidth(c.w * (0.25 + 0.75 * (1 - f)))
                sky.beginPath(); sky.move(to: CGPoint(x: px, y: py)); sky.addLine(to: CGPoint(x: nx, y: ny)); sky.strokePath()
                px = nx; py = ny
            }
            let hx = center.x + cos(ang) * Rc, hy = center.y + sin(ang) * Rc
            let hr = Water.HEAD_R * (1 + 0.6 * level)
            sky.fillRadial(cx: hx, cy: hy, r0: 0, r1: hr * 3, stops: [
                (0, hsla(c.hue, 1, 0.92, min(1, 0.95 * bri))),
                (0.3, col(min(1, 0.55 * bri))),
                (1, hsla(c.hue, 1, 0.60, 0)),
            ])
        }
        sky.restoreGState()
        guard let skyImage = sky.makeImage() else { return }

        // ---------- 2. blit the sky, source-over.
        bitmap.setBlendMode(.normal)
        bitmap.setAlpha(1)
        if let visible = skyImage.cropping(to: CGRect(x: M * scale, y: 0, width: W * scale, height: waterY * scale)) {
            pageImage(bitmap, visible, in: CGRect(x: 0, y: 0, width: W, height: waterY))
        }

        // ---------- 3. the water body.
        linearFill(bitmap, rect: CGRect(x: 0, y: waterY, width: W, height: waterH),
                   from: CGPoint(x: 0, y: waterY), to: CGPoint(x: 0, y: H),
                   stops: [(0, rgba(Water.WATER_TOP, 1)), (1, rgba(Water.WATER_BOT, 1))])

        // ---------- 4. the reflection: one vertical flip about the waterline,
        // each slice shifted by the ripple — by sampling into the margin.
        let rip = 1 + Water.RIPPLE_AUDIO * level
        bitmap.saveGState()
        bitmap.clip(to: CGRect(x: 0, y: waterY, width: W, height: waterH))
        bitmap.translateBy(x: 0, y: waterY)
        bitmap.scaleBy(x: 1, y: -1)
        bitmap.setBlendMode(.plusLighter)
        let sh = Water.SLICE_H, K = Water.REFLECT_SQUASH, shSrc = sh / K
        var d: CGFloat = 0
        while d < waterH {
            let sy = waterY - (d + sh) / K
            if sy < 0 { break }
            let dn = d / waterH
            let amp = Water.RIPPLE_AMP * (Water.RIPPLE_MIN + Water.RIPPLE_DEPTH_GAIN * dn) * rip
            let dx = amp * (sin(d * Water.RIPPLE_F1 - t * Water.RIPPLE_S1)
                            + 0.6 * sin(d * Water.RIPPLE_F2 + t * Water.RIPPLE_S2 + 1.7))
            bitmap.setAlpha(Water.REFLECT_ALPHA * exp(-dn * Water.REFLECT_FADE))
            let sx = (M - max(-M, min(M, dx))) * scale
            if let slice = skyImage.cropping(to: CGRect(x: sx, y: sy * scale, width: W * scale, height: shSrc * scale)) {
                pageImage(bitmap, slice, in: CGRect(x: 0, y: -(d + sh), width: W, height: sh))
            }
            d += sh
        }
        bitmap.restoreGState()
        bitmap.setAlpha(1)

        // ---------- 5. the blue shift with depth: one multiply rect.
        bitmap.saveGState()
        bitmap.setBlendMode(.multiply)
        linearFill(bitmap, rect: CGRect(x: 0, y: waterY, width: W, height: waterH),
                   from: CGPoint(x: 0, y: waterY), to: CGPoint(x: 0, y: H),
                   stops: [(0, rgba(Water.TINT_TOP, 1)), (1, rgba(Water.TINT_BOT, 1))])
        bitmap.restoreGState()

        // ---------- 6. the surface: specular streaks and the waterline.
        bitmap.setBlendMode(.plusLighter)
        for k in 0..<7 {
            let fk = CGFloat(k)
            let y = waterY + 2 + fk * 3.1
            let ph = t * (0.7 + fk * 0.23) + fk * 1.9
            let x = (sin(ph) * 0.5 + 0.5) * W
            let w = (34 + 26 * sin(ph * 1.7)) * (1 + level)
            linearFill(bitmap, rect: CGRect(x: x - w, y: y, width: 2 * w, height: 1.4),
                       from: CGPoint(x: x - w, y: 0), to: CGPoint(x: x + w, y: 0), stops: [
                        (0, CGColor(srgbRed: 150 / 255, green: 200 / 255, blue: 1, alpha: 0)),
                        (0.5, CGColor(srgbRed: 170 / 255, green: 215 / 255, blue: 1, alpha: (0.10 + 0.18 * level) * (1 - fk / 8))),
                        (1, CGColor(srgbRed: 150 / 255, green: 200 / 255, blue: 1, alpha: 0)),
                       ])
        }
        linearFill(bitmap, rect: CGRect(x: 0, y: waterY - 0.5, width: W, height: 1.6),
                   from: CGPoint(x: 0, y: 0), to: CGPoint(x: W, y: 0), stops: [
                    (0, CGColor(srgbRed: 120 / 255, green: 180 / 255, blue: 1, alpha: 0.10)),
                    (min(0.95, max(0.05, center.x / W)), CGColor(srgbRed: 190 / 255, green: 225 / 255, blue: 1, alpha: 0.55 + 0.35 * level)),
                    (1, CGColor(srgbRed: 120 / 255, green: 180 / 255, blue: 1, alpha: 0.10)),
                   ])
        bitmap.setFillColor(CGColor(srgbRed: 120 / 255, green: 170 / 255, blue: 1, alpha: 0.10 + 0.10 * level))
        bitmap.fill(CGRect(x: 0, y: waterY - 3, width: W, height: 6))
        bitmap.setBlendMode(.normal)
    }
}
