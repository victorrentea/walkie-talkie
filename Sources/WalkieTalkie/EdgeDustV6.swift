import AppKit

/// **Variant 6 — "Dust flames"** (2026-11-16). Victor: *"un efect tip foc dar cu
/// praf"*. The edge is the base of a fire whose substance is fine dust: tongues of
/// tiny soft grains lick inward from it, taper and dissolve, a few stray grains fly
/// further like embers. Nothing travels along the edge — every grain moves across
/// the strip, away from the edge.
///
/// Pure Core Animation, nothing per frame in this app:
/// - The edge is cut into **segments ~`pitch` pt wide**, one `CAEmitterLayer` each
///   (a thin rectangle on the edge, 1.4× its pitch so neighbours blend). Each has
///   its own seed, its own hue family (rose, amber, green, sky, violet … never the
///   neighbour's) and three cells: a dense low *body*, a narrow taller *tongue*,
///   sparse *embers*. Grains are born pale ("hot"), run to their saturated hue and
///   on to dim, shrinking, decelerated by an acceleration back towards the edge.
/// - **The flicker** is two looping keyframe animations per segment, on the layer's
///   `velocity` and `birthRate` multipliers, random values, random durations — so
///   neighbouring tongues rise and fall out of phase. No timer.
/// - **His voice** (the RMS of `feed`, smoothed) and `setIntensity` go to the
///   *cells* (`emitterCells.<name>.velocity|birthRate`), which the layer animations
///   multiply — touched only when the level moves by more than `step`.
final class EdgeDustV6: EdgeDustPicture {
    static let title = "Dust flames"

    /// A segment's share of the edge, in points (the real one divides the edge evenly).
    private static let pitch: CGFloat = 55
    /// Grains a second per point of edge, at rest: body, tongue, ember.
    private static let density: (body: Float, tongue: Float, ember: Float) = (0.85, 0.7, 0.045)
    /// The voice level has to move this much before any layer is touched.
    private static let step: CGFloat = 0.05

    /// Soft, fairly saturated — the pointer dust's kind of colour, in a fire's families.
    private static let hues: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (1.00, 0.34, 0.52),   // rose
        (1.00, 0.60, 0.20),   // amber
        (0.38, 0.95, 0.45),   // green
        (0.30, 0.70, 1.00),   // sky
        (0.66, 0.42, 1.00),   // violet
        (1.00, 0.82, 0.28),   // gold
        (0.25, 0.92, 0.85),   // aqua
        (1.00, 0.42, 0.90),   // magenta
    ]

    private struct Kind {
        let name: String
        let velocity: CGFloat      // pt/s away from the edge, at rest
        let velocityRange: CGFloat
        let life: Float
        let lifeRange: Float
        let spread: CGFloat        // emissionRange, radians
        let size: CGFloat          // pt
        let sizeRange: CGFloat
        let alpha: Float
        let brake: CGFloat         // pt/s² back towards the edge
        let pale: CGFloat          // how much white in the grain at birth
    }
    private static let kinds: [Kind] = [
        Kind(name: "body", velocity: 58, velocityRange: 24, life: 0.55, lifeRange: 0.2, spread: 0.75,
             size: 4.6, sizeRange: 1.8, alpha: 0.6, brake: 60, pale: 0.5),
        Kind(name: "tongue", velocity: 88, velocityRange: 30, life: 0.95, lifeRange: 0.3, spread: 0.3,
             size: 4.0, sizeRange: 1.5, alpha: 0.55, brake: 60, pale: 0.35),
        Kind(name: "ember", velocity: 100, velocityRange: 40, life: 1.4, lifeRange: 0.4, spread: 1.0,
             size: 2.8, sizeRange: 0.9, alpha: 0.7, brake: 28, pale: 0.2),
    ]

    private let edge: EdgeDust.Edge
    private var segments: [CAEmitterLayer] = []
    /// Each segment's cells' birth rates at rest, in `kinds` order.
    private var restRates: [Float] = []
    private var running = false
    private var intensity: CGFloat = 1
    private var level: CGFloat = 0
    private var applied: (level: CGFloat, intensity: CGFloat) = (-1, -1)

    private static let grainImage: CGImage? = {
        let px = 32
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let glow = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.45), CGColor(gray: 1, alpha: 0)] as CFArray,
                                    locations: [0, 0.4, 1]) else { return nil }
        let c = CGPoint(x: px / 2, y: px / 2)
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(px) / 2, options: [])
        return ctx.makeImage()
    }()

    init?(strip: NSView, edge: EdgeDust.Edge) {
        guard let host = strip.layer, let grain = Self.grainImage else { return nil }
        self.edge = edge
        let box = strip.bounds
        let length = edge == .top ? box.width : box.height
        guard length > 1 else { return nil }
        let count = max(1, Int((length / Self.pitch).rounded()))
        let pitch = length / CGFloat(count)
        restRates = [Self.density.body, Self.density.tongue, Self.density.ember].map { $0 * Float(pitch) }

        var lastHue = -1
        for i in 0..<count {
            var hue = Int.random(in: 0..<Self.hues.count)
            if hue == lastHue { hue = (hue + 1 + Int.random(in: 0..<(Self.hues.count - 1))) % Self.hues.count }
            lastHue = hue

            let e = CAEmitterLayer()
            e.frame = box
            e.emitterShape = .rectangle
            e.emitterMode = .surface
            e.renderMode = .additive
            e.seed = UInt32.random(in: 1..<UInt32.max)
            let along = (CGFloat(i) + 0.5) * pitch
            switch edge {
            case .top:
                e.emitterPosition = CGPoint(x: along, y: box.maxY - 1)
                e.emitterSize = CGSize(width: pitch * 1.4, height: 3)
            case .right:
                e.emitterPosition = CGPoint(x: box.maxX - 1, y: along)
                e.emitterSize = CGSize(width: 3, height: pitch * 1.4)
            }
            e.emitterCells = zip(Self.kinds, restRates).map { kind, rate in
                Self.cell(kind, rate: rate, hue: Self.hues[hue], edge: edge, grain: grain)
            }
            e.birthRate = 0
            host.addSublayer(e)
            segments.append(e)
        }
    }

    private static func cell(_ k: Kind, rate: Float, hue: (r: CGFloat, g: CGFloat, b: CGFloat),
                             edge: EdgeDust.Edge, grain: CGImage) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.name = k.name
        c.contents = grain
        c.birthRate = rate
        c.lifetime = k.life
        c.lifetimeRange = k.lifeRange
        // Inward: down from the top edge, leftwards from the right one — braked back towards it.
        switch edge {
        case .top:   c.emissionLongitude = -.pi / 2; c.yAcceleration = k.brake
        case .right: c.emissionLongitude = .pi;      c.xAcceleration = k.brake
        }
        c.emissionRange = k.spread
        c.velocity = k.velocity
        c.velocityRange = k.velocityRange
        // Pale at birth, the hue itself at 60% of its life, dimmer after.
        let born = (r: hue.r + (1 - hue.r) * k.pale, g: hue.g + (1 - hue.g) * k.pale, b: hue.b + (1 - hue.b) * k.pale)
        c.color = CGColor(red: born.r, green: born.g, blue: born.b, alpha: CGFloat(k.alpha))
        c.redRange = 0.08; c.greenRange = 0.08; c.blueRange = 0.08
        let run = 0.6 * k.life
        c.redSpeed = Float(hue.r - born.r) / run - 0.12 / k.life
        c.greenSpeed = Float(hue.g - born.g) / run - 0.12 / k.life
        c.blueSpeed = Float(hue.b - born.b) / run - 0.12 / k.life
        c.alphaRange = 0.2
        c.alphaSpeed = -k.alpha / (k.life + k.lifeRange / 2)
        c.scale = k.size / 32
        c.scaleRange = k.sizeRange / 32
        c.scaleSpeed = -0.55 * c.scale / CGFloat(k.life)
        return c
    }

    // MARK: - EdgeDustPicture

    func start() {
        running = true
        level = 0
        applied = (-1, -1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in segments {
            e.removeAllAnimations()
            e.add(Self.flicker("velocity", low: 0.5, high: 1.3, beat: 0.4...1.0), forKey: "tongues")
            e.add(Self.flicker("birthRate", low: 0.4, high: 1.35, beat: 0.5...1.3), forKey: "breath")
            e.birthRate = 1
        }
        CATransaction.commit()
        apply()
    }

    func stop() {
        running = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in segments {
            e.removeAllAnimations()
            e.birthRate = 0
        }
        CATransaction.commit()
    }

    func feed(_ samples: [Float]) {
        guard running, !samples.isEmpty else { return }
        var sum: Float = 0
        for v in samples { sum += v * v }
        let heard = CGFloat(min(1, (sum / Float(samples.count)).squareRoot() * 6))
        // Up fast, down slowly: a flame fed and then left to settle.
        level += (heard > level ? 0.35 : 0.1) * (heard - level)
        if level < 0.01 { level = 0 }
        if abs(level - applied.level) >= Self.step || (level == 0 && applied.level != 0) { apply() }
    }

    func setIntensity(_ k: CGFloat) {
        intensity = min(max(k, 0), 3)
        if running, intensity != applied.intensity { apply() }
    }

    // MARK: - The fire

    /// The voice and the intensity, into every segment's cells: how tall and how much.
    private func apply() {
        applied = (level, intensity)
        let extra = max(0, intensity - 1)
        // Silence: low calm flames. A loud voice: about twice as tall, half again the dust.
        let tall = (0.8 + 0.75 * level) * (1 + 0.25 * extra)
        let much = Float((0.85 + 0.55 * level) * (1 + extra))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in segments {
            for (kind, rate) in zip(Self.kinds, restRates) {
                // Embers fly on their own; the voice mostly makes more of them.
                let reach = kind.name == "ember" ? 1 + (tall - 1) * 0.4 : tall
                e.setValue(kind.velocity * reach, forKeyPath: "emitterCells.\(kind.name).velocity")
                e.setValue(rate * much, forKeyPath: "emitterCells.\(kind.name).birthRate")
            }
        }
        CATransaction.commit()
    }

    /// A slow random wander of one of the emitter's multipliers, looping: a handful
    /// of values, each held for a `beat`, eased into the next, back to the first.
    private static func flicker(_ keyPath: String, low: Float, high: Float, beat: ClosedRange<Double>) -> CAKeyframeAnimation {
        let n = Int.random(in: 6...9)
        var values = (0..<n).map { _ in Float.random(in: low...high) }
        values.append(values[0])
        let beats = (0..<n).map { _ in Double.random(in: beat) }
        let total = beats.reduce(0, +)
        var times: [NSNumber] = [0]
        var t = 0.0
        for b in beats { t += b; times.append(NSNumber(value: min(1, t / total))) }
        times[times.count - 1] = 1
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values.map { NSNumber(value: $0) }
        a.keyTimes = times
        a.timingFunctions = (0..<n).map { _ in CAMediaTimingFunction(name: .easeInEaseOut) }
        a.duration = total
        a.repeatCount = .infinity
        a.timeOffset = Double.random(in: 0..<total)
        a.isRemovedOnCompletion = false
        return a
    }
}
