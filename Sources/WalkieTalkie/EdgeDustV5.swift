import AppKit
import SpriteKit

/// **Variant 5 of the prompt's edge — "Field dust"** (2026-11-16). The Smoke round
/// the pointer, laid along an edge and standing where it is: SpriteKit particles
/// born all along the edge, pushed about by a *noise field* that changes slowly, so
/// the grains curl in eddies instead of flying straight or sitting still.
///
/// - **Two populations.** *Grains*: thousands of small soft dots (1–7 pt), additive,
///   each alive ~2.3 s. *Puffs*: large faint wisps (growing to 50–70 pt, a lumpy
///   texture, slowly turning) — the smoky body under the grains.
/// - **Each grain one colour, never white**: six emitters of each kind, one per hue
///   round the wheel, each with a per-channel spread — as the fluid's puffs are one
///   random colour each. Additive only where they overlap.
/// - **Nothing travels along the edge**: no emitter moves; particles are born at
///   rest (a few pt/s, any direction) anywhere on the edge, the field stirs them, a
///   drag field keeps their speed bounded. **Nothing pops**: a particle is born a
///   point or two wide and grows while its alpha runs down to nothing before its
///   life ends — no `particleAlphaSequence`: stepped at 1/30 s offscreen
///   (`advanceSimulationTime`) a keyframe sequence evaluated to 0 for every
///   particle, and the live path could not be checked from a desk.
/// - **His voice** (RMS, fast up, slow down) raises the birth rate and the field's
///   strength; silence keeps the calm base. `setIntensity(2)`: twice the births.
/// - `stop()` pauses the view and takes the scene off it — no frame is drawn, no
///   particle simulated; `start()` clears the old particles and pre-ages new ones.
final class EdgeDustV5: EdgeDustPicture {
    static let title = "Field dust"

    private let view: SKView
    private let rig: Rig
    private var level: CGFloat = 0
    private var intensity: CGFloat = 1
    private var running = false

    init?(strip: NSView, edge: EdgeDust.Edge) {
        let box = strip.bounds
        guard box.width > 1, box.height > 1, let rig = Rig(size: box.size, edge: edge) else { return nil }
        self.rig = rig
        view = SKView(frame: box)
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.autoresizingMask = [.width, .height]
        view.isPaused = true
        strip.addSubview(view)
    }

    func start() {
        guard !running else { return }
        running = true
        level = 0
        rig.apply(level: 0, intensity: intensity)
        rig.restart()
        view.presentScene(rig.scene)
        view.isPaused = false
    }

    func stop() {
        guard running else { return }
        running = false
        view.isPaused = true
        view.presentScene(nil)
    }

    func feed(_ samples: [Float]) {
        guard running else { return }
        var sum: Float = 0
        for v in samples { sum += v * v }
        let rms = samples.isEmpty ? 0 : (sum / Float(samples.count)).squareRoot()
        let now = min(1, CGFloat(rms) / Rig.loud)
        level += (now > level ? 0.35 : 0.06) * (now - level)
        rig.apply(level: level, intensity: intensity)
    }

    func setIntensity(_ k: CGFloat) {
        intensity = k
        rig.apply(level: level, intensity: k)
    }

    /// The scene and its knobs — apart from the view, so it can be rendered offscreen.
    final class Rig {
        /// Births a second per 100 pt of edge, at rest.
        static let grainRate: CGFloat = 70
        static let puffRate: CGFloat = 9
        static let grainLife: CGFloat = 2.3
        static let puffLife: CGFloat = 3.2
        /// The noise field at rest; the voice takes it to `(1 + stirByVoice) ×`.
        static let stir: Float = 0.14
        static let stirByVoice: Float = 1.6
        static let drag: Float = 0.9
        /// The voice takes the births to `(1 + birthsByVoice) ×`.
        static let birthsByVoice: CGFloat = 0.6
        /// The RMS that counts as a full voice (after `CaretHalo.lift`, ~0.10).
        static let loud: CGFloat = 0.12
        static let hues = 6

        let scene: SKScene
        private var grains: [SKEmitterNode] = []
        private var puffs: [SKEmitterNode] = []
        private let noise: SKFieldNode
        private let length: CGFloat

        init?(size: CGSize, edge: EdgeDust.Edge) {
            guard let dot = Self.dot, let wisp = Self.wisp else { return nil }
            scene = SKScene(size: size)
            scene.anchorPoint = .zero
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            scene.physicsWorld.gravity = .zero

            // Born 10–35 pt from the edge, all along it.
            let middle: CGPoint, spread: CGVector, puffMiddle: CGPoint
            switch edge {
            case .top:
                length = size.width
                middle = CGPoint(x: size.width / 2, y: size.height - 22)
                puffMiddle = CGPoint(x: size.width / 2, y: size.height - 16)
                spread = CGVector(dx: size.width, dy: 26)
            case .right:
                length = size.height
                middle = CGPoint(x: size.width - 22, y: size.height / 2)
                puffMiddle = CGPoint(x: size.width - 16, y: size.height / 2)
                spread = CGVector(dx: 26, dy: size.height)
            }

            noise = SKFieldNode.noiseField(withSmoothness: 0.75, animationSpeed: 0.35)
            noise.categoryBitMask = 1
            noise.strength = Self.stir
            noise.position = CGPoint(x: size.width / 2, y: size.height / 2)
            scene.addChild(noise)
            let drag = SKFieldNode.dragField()
            drag.categoryBitMask = 1
            drag.strength = Self.drag
            drag.position = noise.position
            scene.addChild(drag)

            for i in 0..<Self.hues {
                let hue = (CGFloat(i) + 0.15) / CGFloat(Self.hues)

                let g = SKEmitterNode()
                g.particleTexture = dot
                g.particleSize = dot.size()
                g.position = middle
                g.particlePositionRange = spread
                g.particleLifetime = Self.grainLife
                g.particleLifetimeRange = 0.6
                g.particleScale = 2.2 / dot.size().width
                g.particleScaleRange = 2.4 / dot.size().width        // born 1…3.4 pt
                g.particleScaleSpeed = 1.5 / dot.size().width         // …4–7 pt as it goes out
                g.particleSpeed = 3
                g.particleSpeedRange = 4
                g.emissionAngleRange = .pi * 2
                g.particleBlendMode = .add
                g.particleColorBlendFactor = 1
                g.particleColor = NSColor(calibratedHue: hue, saturation: 0.72, brightness: 1, alpha: 1)
                g.particleColorRedRange = 0.3; g.particleColorGreenRange = 0.3; g.particleColorBlueRange = 0.3
                g.particleAlpha = 0.6
                g.particleAlphaRange = 0.4
                g.particleAlphaSpeed = -0.8 / (Self.grainLife - 0.3)
                g.fieldBitMask = 1
                g.zPosition = 1
                scene.addChild(g)
                grains.append(g)

                let p = SKEmitterNode()
                p.particleTexture = wisp
                p.particleSize = wisp.size()
                p.position = puffMiddle
                p.particlePositionRange = spread
                p.particleLifetime = Self.puffLife
                p.particleLifetimeRange = 0.6
                p.particleScale = 14 / wisp.size().width
                p.particleScaleRange = 18 / wisp.size().width        // born 5…23 pt
                p.particleScaleSpeed = 15 / wisp.size().width         // …50–70 pt as it goes out
                p.particleSpeed = 2
                p.particleSpeedRange = 3
                p.emissionAngleRange = .pi * 2
                p.particleRotationRange = .pi * 2
                p.particleRotationSpeed = 0.25
                p.particleBlendMode = .add
                p.particleColorBlendFactor = 1
                p.particleColor = NSColor(calibratedHue: hue + 0.08, saturation: 0.8, brightness: 1, alpha: 1)
                p.particleColorRedRange = 0.25; p.particleColorGreenRange = 0.25; p.particleColorBlueRange = 0.25
                p.particleAlpha = 0.3
                p.particleAlphaRange = 0.16
                p.particleAlphaSpeed = -0.38 / (Self.puffLife - 0.3)
                p.fieldBitMask = 1
                scene.addChild(p)
                puffs.append(p)
            }
            apply(level: 0, intensity: 1)
        }

        /// `level` 0…1: the voice, smoothed. `intensity`: 1, or 2 as the edge goes.
        func apply(level: CGFloat, intensity: CGFloat) {
            let per = length / 100 / CGFloat(Self.hues) * max(0, intensity) * (1 + Self.birthsByVoice * level)
            grains.forEach { $0.particleBirthRate = Self.grainRate * per }
            puffs.forEach { $0.particleBirthRate = Self.puffRate * per }
            noise.strength = Self.stir * (1 + Self.stirByVoice * Float(level))
        }

        /// No particle of the last time; the strip already full, mid-life.
        func restart() {
            (grains + puffs).forEach {
                $0.resetSimulation()
                $0.advanceSimulationTime(1.6)
            }
        }

        private static func bitmap(_ px: Int, _ draw: (CGContext) -> Void) -> SKTexture? {
            guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            draw(ctx)
            return ctx.makeImage().map { SKTexture(cgImage: $0) }
        }

        private static func blob(_ ctx: CGContext, at c: CGPoint, radius: CGFloat, alpha: CGFloat) {
            guard let glow = CGGradient(colorsSpace: nil,
                                        colors: [CGColor(gray: 1, alpha: alpha), CGColor(gray: 1, alpha: alpha * 0.4),
                                                 CGColor(gray: 1, alpha: 0)] as CFArray,
                                        locations: [0, 0.4, 1]) else { return }
            ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
        }

        /// A grain: a soft round dot.
        private static let dot: SKTexture? = bitmap(32) { blob($0, at: CGPoint(x: 16, y: 16), radius: 16, alpha: 1) }

        /// A puff: a lumpy wisp — soft blobs on a bent line, so a turning puff is not a disc.
        private static let wisp: SKTexture? = bitmap(128) { ctx in
            let lumps: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (64, 64, 44, 0.42), (40, 74, 30, 0.5), (86, 52, 32, 0.5), (56, 44, 24, 0.45),
                (78, 82, 22, 0.4), (30, 54, 20, 0.35), (98, 70, 20, 0.35), (66, 96, 18, 0.3),
            ]
            for (x, y, r, a) in lumps { blob(ctx, at: CGPoint(x: x, y: y), radius: r, alpha: a) }
        }
    }
}
