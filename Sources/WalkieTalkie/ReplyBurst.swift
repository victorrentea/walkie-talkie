import AppKit

/// **🔼 → over the reply pop-up: it dissolves to the right** (2026-10-09, Victor:
/// *"that panel should swipe to right, fade out, and then in the same time turn
/// into pieces … something to suggest that I took my focus and send it to it"*,
/// then, over the first build's 9-column burst: *"I don't want to make it an
/// explosion, more of a dissolve effect, in smaller pieces"*). The pop-up's
/// picture is cut into ~`grain`-point grains; each, at its own moment — the
/// left edge first, with a random scatter — drifts a little right and up while
/// it shrinks and fades. `seconds` long, then gone.
///
/// Driven by a timer through `apply(_:)`, like `ReplyPanel.zoom`, so a test can
/// stop it at any moment and render it (`REPLY_BURST_PNG=<dir> swift test
/// --filter ReplyBurstTests`). `sharingType = .none` and mouse-transparent, like
/// the pop-up it replaces.
///
/// **☠️ blows it up** (2026-10-14, Victor: *"when I click on the skull to kill a
/// session … the dialogue should explode … breaking down into pieces and
/// exploding out"*) — `.explode(from:)`: the picture cracks into ~`shard`-point
/// triangles on a jittered grid, a flash goes off at the skull, and each shard,
/// as the blast front reaches it, flies away from the skull — the nearest
/// fastest, each a little off its ray — spinning, slowed by air, pulled down, fading over the
/// last half of `blastSeconds`.
///
/// **🔼 → over a ⚡ answer: question marks over it as it goes** (2026-10-22,
/// Victor: *"dacă apăs din nou … semnul de follow-up questions, fac gestul, să
/// apară semne de întrebare peste acest dialog pe măsură ce el dispare. Simt că
/// fac gestul de tras în dreapta"*) — `.questions`: the same grains drifting
/// right, and over them `marks` ❓, each popping up at its own moment (a small
/// overshoot), then riding right and up with the grains, fading, `askSeconds`.
final class ReplyBurst {
    enum Style {
        /// 🔼 →: grains drift off to the right.
        case dissolve
        /// ☠️: shards blown out from this point (pop-up points, bottom-left origin).
        case explode(from: CGPoint)
        /// 🔼 → over a ⚡ answer (a follow-up): the grains, and ❓ over them.
        case questions
    }

    static let seconds = 0.75
    static let blastSeconds = 0.9
    static let askSeconds = 1.0
    /// How many ❓, and their size range (points).
    static let marks = 12
    static let markSide: ClosedRange<CGFloat> = 18...38
    /// Room round the pop-up for the shards' flight.
    static let blastSide: CGFloat = 520, blastTop: CGFloat = 320, blastBottom: CGFloat = 720
    /// A shard's cell side, in points — larger on a large pop-up (≤ ~90 cells).
    static let shard: CGFloat = 30
    /// How far right a grain drifts.
    static let reach: CGFloat = 70
    /// Room above and below for the grains' drift.
    static let spread: CGFloat = 30
    /// A grain's side, in points.
    static let grain: CGFloat = 8

    private struct Tile {
        let layer: CALayer
        let dx: CGFloat, dy: CGFloat, spin: CGFloat
        /// When it starts: the left edge first, then a scatter.
        let delay: Double
        /// How long it takes to go.
        let span: Double
    }

    /// A shard of the blast: its launch velocity (pt/s) and spin (rad/s).
    private struct Shard {
        let layer: CALayer
        let vx: CGFloat, vy: CGFloat, spin: CGFloat
        /// When the blast front reaches it.
        let delay: Double
    }

    let host: CALayer
    let size: CGSize
    /// Where the pop-up's bottom-left sits inside `host`.
    let inset: CGPoint
    let style: Style
    private var tiles: [Tile] = []
    private var shards: [Shard] = []
    private var flash: CALayer?
    /// A ❓: where it pops, where it goes, when.
    private struct Mark {
        let layer: CALayer
        let dx: CGFloat, dy: CGFloat, spin: CGFloat
        let delay: Double
    }
    private var marks: [Mark] = []
    private static let lag = 0.3

    /// `image` is the pop-up at `scale` pixels per point; `panel` its size in points.
    init(image: CGImage, scale: CGFloat, panel: CGSize, style: Style = .dissolve, seed: UInt64 = 0x5eed) {
        self.style = style
        if case .explode(let o) = style {
            inset = CGPoint(x: Self.blastSide, y: Self.blastBottom)
            size = CGSize(width: panel.width + 2 * Self.blastSide, height: panel.height + Self.blastTop + Self.blastBottom)
            host = CALayer()
            host.frame = CGRect(origin: .zero, size: size)
            crack(image, scale: scale, panel: panel, from: o, seed: seed)
            return
        }
        inset = CGPoint(x: 0, y: Self.spread)
        size = CGSize(width: panel.width + Self.reach + 80, height: panel.height + 2 * Self.spread)
        host = CALayer()
        host.frame = CGRect(origin: .zero, size: size)
        var rng = SplitMix(seed)
        let cols = max(1, Int((panel.width / Self.grain).rounded()))
        let rows = max(1, Int((panel.height / Self.grain).rounded()))
        let w = panel.width / CGFloat(cols), h = panel.height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let fx = (CGFloat(c) + 0.5) / CGFloat(cols)        // 0 left … 1 right
                let fy = (CGFloat(r) + 0.5) / CGFloat(rows) - 0.5  // −½ bottom … ½ top
                let l = CALayer()
                // Whole pixels, no edge antialiasing: grains at fractional edges
                // drew a faint grid over the pop-up before it had moved.
                func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
                let x0 = px(CGFloat(c) * w), x1 = px(CGFloat(c + 1) * w)
                let y0 = px(CGFloat(r) * h), y1 = px(CGFloat(r + 1) * h)
                l.frame = CGRect(x: x0, y: Self.spread + y0, width: x1 - x0, height: y1 - y0)
                l.edgeAntialiasingMask = []
                l.contents = image
                l.contentsScale = scale
                // Unit coordinates of the image, bottom-left origin like the layer.
                l.contentsRect = CGRect(x: CGFloat(c) / CGFloat(cols), y: CGFloat(r) / CGFloat(rows),
                                        width: 1 / CGFloat(cols), height: 1 / CGFloat(rows))
                l.contentsGravity = .resize
                l.actions = ["position": NSNull(), "transform": NSNull(), "opacity": NSNull(), "bounds": NSNull()]
                host.addSublayer(l)
                let delay = Self.lag * Double(fx) * 0.6 + Double(rng.range(0, CGFloat(Self.lag) * 0.4))
                tiles.append(Tile(layer: l,
                                  dx: Self.reach * rng.range(0.5, 1),
                                  dy: fy * Self.spread * 0.6 + rng.range(-12, 18),
                                  spin: rng.range(-0.5, 0.5),
                                  delay: delay,
                                  span: Double(rng.range(0.35, 0.45)) * Self.seconds / 0.75))
            }
        }
        if case .questions = style { sprinkle(panel: panel, scale: scale, rng: &rng) }
    }

    /// The ❓ over the pop-up — one picture of the emoji, every mark a layer of it.
    private func sprinkle(panel: CGSize, scale: CGFloat, rng: inout SplitMix) {
        guard let glyph = Self.glyph("❓", side: Self.markSide.upperBound, scale: scale) else { return }
        for i in 0..<Self.marks {
            let side = rng.range(Self.markSide.lowerBound, Self.markSide.upperBound)
            // Spread over the pop-up: one per column of a loose grid, its height random.
            let fx = (CGFloat(i) + rng.range(0.15, 0.85)) / CGFloat(Self.marks)
            let l = CALayer()
            l.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            l.position = CGPoint(x: fx * panel.width * 0.92 + panel.width * 0.04,
                                 y: Self.spread + rng.range(0.15, 0.85) * panel.height)
            l.contents = glyph
            l.contentsScale = scale
            l.contentsGravity = .resizeAspect
            l.opacity = 0
            l.actions = ["position": NSNull(), "transform": NSNull(), "opacity": NSNull(), "bounds": NSNull()]
            host.addSublayer(l)
            marks.append(Mark(layer: l, dx: Self.reach * rng.range(0.6, 1.3), dy: rng.range(4, Self.spread - 6),
                              spin: rng.range(-0.5, 0.5), delay: Double(fx) * 0.25 + Double(rng.range(0, 0.12))))
        }
    }

    /// An emoji drawn once at `side` points.
    private static func glyph(_ s: String, side: CGFloat, scale: CGFloat) -> CGImage? {
        let text = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: side * 0.82)])
        let px = Int(ceil(side * scale))
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let was = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let size = text.size()
        text.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        NSGraphicsContext.current = was
        return ctx.makeImage()
    }

    /// Cracks the picture into triangles on a jittered grid — every shard its
    /// own small image, clipped (a layer mask is skipped by `render(in:)`, so a
    /// test could not look at it) and grown ½ pt round its centre so no seam
    /// shows before it moves.
    private func crack(_ image: CGImage, scale: CGFloat, panel: CGSize, from o: CGPoint, seed: UInt64) {
        var rng = SplitMix(seed)
        let side = max(Self.shard, (panel.width * panel.height / 90).squareRoot())
        let cols = max(1, Int((panel.width / side).rounded()))
        let rows = max(1, Int((panel.height / side).rounded()))
        let w = panel.width / CGFloat(cols), h = panel.height / CGFloat(rows)
        var grid = [[CGPoint]](repeating: [], count: rows + 1)
        for r in 0...rows {
            for c in 0...cols {
                let inner = c > 0 && c < cols && r > 0 && r < rows
                grid[r].append(CGPoint(x: CGFloat(c) * w + (inner ? rng.range(-0.35, 0.35) * w : 0),
                                       y: CGFloat(r) * h + (inner ? rng.range(-0.35, 0.35) * h : 0)))
            }
        }
        let reach = hypot(max(o.x, panel.width - o.x), max(o.y, panel.height - o.y))
        for r in 0..<rows {
            for c in 0..<cols {
                let a = grid[r][c], b = grid[r][c + 1], cc = grid[r + 1][c + 1], d = grid[r + 1][c]
                let tris = rng.range(0, 1) < 0.5 ? [[a, b, cc], [a, cc, d]] : [[a, b, d], [b, cc, d]]
                for tri in tris {
                    guard let l = shardLayer(tri, image: image, scale: scale, panel: panel) else { continue }
                    host.addSublayer(l)
                    let centre = CGPoint(x: (tri[0].x + tri[1].x + tri[2].x) / 3, y: (tri[0].y + tri[1].y + tri[2].y) / 3)
                    var dx = centre.x - o.x, dy = centre.y - o.y
                    let dist = hypot(dx, dy)
                    if dist < 1 { let t = rng.range(0, 2 * .pi); dx = cos(t); dy = sin(t) } else { dx /= dist; dy /= dist }
                    let turn = rng.range(-0.6, 0.6)                 // not every shard on its ray
                    let ux = dx * cos(turn) - dy * sin(turn), uy = dx * sin(turn) + dy * cos(turn)
                    let speed = (1900 - 700 * dist / max(reach, 1)) * rng.range(0.55, 1.3)
                    shards.append(Shard(layer: l, vx: ux * speed, vy: uy * speed + rng.range(80, 260),
                                        spin: rng.range(-12, 12), delay: Double(dist) / 2600))
                }
            }
        }
        // The flash: white at the skull, through yellow and orange, to nothing.
        let f = CAGradientLayer()
        f.type = .radial
        f.bounds = CGRect(x: 0, y: 0, width: 260, height: 260)
        f.position = CGPoint(x: inset.x + o.x, y: inset.y + o.y)
        f.colors = [NSColor.white, NSColor(calibratedRed: 1, green: 0.85, blue: 0.35, alpha: 0.95),
                    NSColor(calibratedRed: 1, green: 0.4, blue: 0.05, alpha: 0.55),
                    NSColor(calibratedRed: 1, green: 0.3, blue: 0, alpha: 0)].map(\.cgColor)
        f.locations = [0, 0.18, 0.5, 1]
        f.startPoint = CGPoint(x: 0.5, y: 0.5)
        f.endPoint = CGPoint(x: 1, y: 1)
        f.actions = ["transform": NSNull(), "opacity": NSNull()]
        host.addSublayer(f)
        flash = f
    }

    private func shardLayer(_ tri: [CGPoint], image: CGImage, scale: CGFloat, panel: CGSize) -> CALayer? {
        let centre = CGPoint(x: (tri[0].x + tri[1].x + tri[2].x) / 3, y: (tri[0].y + tri[1].y + tri[2].y) / 3)
        let grown = tri.map { p -> CGPoint in
            let dx = p.x - centre.x, dy = p.y - centre.y, len = max(hypot(dx, dy), 0.01)
            return CGPoint(x: p.x + dx / len * 0.5, y: p.y + dy / len * 0.5)
        }
        func px(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        let minX = px(max(0, grown.map(\.x).min()! - 1)), maxX = px(min(panel.width, grown.map(\.x).max()! + 1))
        let minY = px(max(0, grown.map(\.y).min()! - 1)), maxY = px(min(panel.height, grown.map(\.y).max()! + 1))
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard box.width > 0, box.height > 0 else { return nil }
        // `cropping(to:)` counts pixels from the top.
        let crop = CGRect(x: box.minX * scale, y: (panel.height - box.maxY) * scale,
                          width: box.width * scale, height: box.height * scale).integral
        guard let piece = image.cropping(to: crop),
              let ctx = CGContext(data: nil, width: Int(crop.width), height: Int(crop.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.move(to: CGPoint(x: grown[0].x - box.minX, y: grown[0].y - box.minY))
        ctx.addLine(to: CGPoint(x: grown[1].x - box.minX, y: grown[1].y - box.minY))
        ctx.addLine(to: CGPoint(x: grown[2].x - box.minX, y: grown[2].y - box.minY))
        ctx.closePath()
        ctx.clip()
        ctx.draw(piece, in: CGRect(origin: .zero, size: box.size))
        guard let cg = ctx.makeImage() else { return nil }
        let l = CALayer()
        l.frame = box.offsetBy(dx: inset.x, dy: inset.y)
        l.contents = cg
        l.contentsScale = scale
        l.contentsGravity = .resize
        l.edgeAntialiasingMask = []
        l.actions = ["position": NSNull(), "transform": NSNull(), "opacity": NSNull(), "bounds": NSNull()]
        return l
    }

    /// The burst at `u` ∈ 0…1 of `seconds` (`blastSeconds` for a blast, `askSeconds` for ❓).
    func apply(_ u: Double) {
        if case .explode = style { return blast(u) }
        let now: Double
        if case .questions = style { now = u * Self.askSeconds } else { now = u * Self.seconds }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for t in tiles {
            let local = u >= 1 ? 1 : max(0, min(1, (now - t.delay) / t.span))
            let move = CGFloat(local * local)                  // ease-in: it lifts off, no burst
            var m = CATransform3DMakeTranslation(t.dx * move, t.dy * move, 0)
            m = CATransform3DRotate(m, t.spin * move, 0, 0, 1)
            let k = 1 - 0.7 * move
            m = CATransform3DScale(m, k, k, 1)
            t.layer.transform = m
            t.layer.opacity = Float(max(0, 1 - local))
        }
        for m in marks {
            let t = max(0, now - m.delay)
            // Pops in 0.15 s with a little overshoot, then rides off with the grains.
            let pop = min(1, t / 0.15)
            let k = CGFloat(pop < 1 ? 1.18 * sin(pop * .pi / 2) : 1.18 - 0.18 * min(1, (t - 0.15) / 0.1))
            let ride = CGFloat(max(0, min(1, (t - 0.2) / 0.55)))
            let move = ride * ride
            var tr = CATransform3DMakeTranslation(m.dx * move, m.dy * move, 0)
            tr = CATransform3DRotate(tr, m.spin * move, 0, 0, 1)
            tr = CATransform3DScale(tr, max(0.01, k * (1 - 0.3 * move)), max(0.01, k * (1 - 0.3 * move)), 1)
            m.layer.transform = tr
            m.layer.opacity = u >= 1 || t <= 0 ? 0 : Float(max(0, min(1, (1 - ride) * 1.6)))
        }
        CATransaction.commit()
    }

    /// Air slows a shard (`drag`/s), gravity pulls it down (pt/s²).
    private static let drag: CGFloat = 1.9, gravity: CGFloat = 900

    private func blast(_ u: Double) {
        let now = u * Self.blastSeconds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for s in shards {
            let t = CGFloat(max(0, now - s.delay))
            let fly = (1 - exp(-Self.drag * t)) / Self.drag
            var m = CATransform3DMakeTranslation(s.vx * fly, s.vy * fly - Self.gravity * t * t / 2, 0)
            m = CATransform3DRotate(m, s.spin * t, 0, 0, 1)
            let k = 1 + 0.25 * min(1, t / 0.3)                      // toward the eye, a little
            m = CATransform3DScale(m, k, k, 1)
            s.layer.transform = m
            s.layer.opacity = u >= 1 ? 0 : Float(max(0, min(1, (1 - u) / 0.5)))
        }
        if let f = flash {
            let v = CGFloat(min(1, now / 0.22))                   // the flash: ~¼ s, out from the skull
            let k = 0.15 + 0.85 * (1 - (1 - v) * (1 - v))
            f.transform = CATransform3DMakeScale(k, k, 1)
            f.opacity = Float(v >= 1 ? 0 : 1 - v * v)
        }
        CATransaction.commit()
    }

    // MARK: On screen

    private static var live: [NSWindow] = []

    /// The pop-up whose picture this is sat at `frame` (screen points).
    static func play(image: CGImage, scale: CGFloat, from frame: NSRect, level: NSWindow.Level, style: Style = .dissolve) {
        let burst = ReplyBurst(image: image, scale: scale, panel: frame.size, style: style,
                               seed: UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)))
        let total: Double
        switch style {
        case .explode: total = blastSeconds
        case .questions: total = askSeconds
        case .dissolve: total = seconds
        }
        let w = NSWindow(contentRect: NSRect(x: frame.minX - burst.inset.x, y: frame.minY - burst.inset.y,
                                             width: burst.size.width, height: burst.size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = level
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.sharingType = .none
        w.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(origin: .zero, size: burst.size))
        view.wantsLayer = true
        view.layer?.addSublayer(burst.host)
        w.contentView = view
        burst.apply(0)
        w.orderFrontRegardless()
        live.append(w)
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            let u = min(1, Date().timeIntervalSince(start) / total)
            burst.apply(u)
            if u >= 1 {
                timer.invalidate()
                w.orderOut(nil)
                live.removeAll { $0 === w }
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }
}

/// A seeded generator, so a test renders the same burst every time.
private struct SplitMix {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed }
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        a + (b - a) * CGFloat(Double(next() >> 11) / Double(1 << 53))
    }
}
