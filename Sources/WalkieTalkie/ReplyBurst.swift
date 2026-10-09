import AppKit

/// **🔼 → over the reply pop-up: it bursts to the right** (2026-10-09, Victor:
/// *"that panel should swipe to right, fade out, and then in the same time turn
/// into pieces … a bit of an explosion to the right … something to suggest that I
/// took my focus and send it to it"*). The pop-up's picture is cut into tiles that
/// fly right — the far column furthest, each with its own spin and drift — while
/// they shrink and fade; `seconds` long, then gone.
///
/// Driven by a timer through `apply(_:)`, like `ReplyPanel.zoom`, so a test can
/// stop it at any moment and render it (`REPLY_BURST_PNG=<dir> swift test
/// --filter ReplyBurstTests`). `sharingType = .none` and mouse-transparent, like
/// the pop-up it replaces.
final class ReplyBurst {
    static let seconds = 0.55
    /// How far right the far column travels, beyond the pop-up's own width.
    static let reach: CGFloat = 320
    /// Room above and below for the tiles' drift.
    static let spread: CGFloat = 110

    private struct Tile {
        let layer: CALayer
        let dx: CGFloat, dy: CGFloat, spin: CGFloat
        /// 0 for the right edge, up to `lag` for the left: the right side goes first.
        let delay: Double
    }

    let host: CALayer
    let size: CGSize
    private var tiles: [Tile] = []
    private static let lag = 0.12

    /// `image` is the pop-up at `scale` pixels per point; `panel` its size in points.
    init(image: CGImage, scale: CGFloat, panel: CGSize, seed: UInt64 = 0x5eed) {
        size = CGSize(width: panel.width + Self.reach + 80, height: panel.height + 2 * Self.spread)
        host = CALayer()
        host.frame = CGRect(origin: .zero, size: size)
        var rng = SplitMix(seed)
        let cols = 9
        let rows = max(3, Int((panel.height / 34).rounded()))
        let w = panel.width / CGFloat(cols), h = panel.height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let fx = (CGFloat(c) + 0.5) / CGFloat(cols)        // 0 left … 1 right
                let fy = (CGFloat(r) + 0.5) / CGFloat(rows) - 0.5  // −½ bottom … ½ top
                let l = CALayer()
                l.frame = CGRect(x: CGFloat(c) * w, y: Self.spread + CGFloat(r) * h, width: w, height: h)
                l.contents = image
                l.contentsScale = scale
                // Unit coordinates of the image, bottom-left origin like the layer.
                l.contentsRect = CGRect(x: CGFloat(c) / CGFloat(cols), y: CGFloat(r) / CGFloat(rows),
                                        width: 1 / CGFloat(cols), height: 1 / CGFloat(rows))
                l.contentsGravity = .resize
                l.actions = ["position": NSNull(), "transform": NSNull(), "opacity": NSNull(), "bounds": NSNull()]
                host.addSublayer(l)
                tiles.append(Tile(layer: l,
                                  dx: Self.reach * (0.45 + 0.55 * fx) + rng.range(-40, 40),
                                  dy: fy * Self.spread * 1.5 + rng.range(-30, 30),
                                  spin: rng.range(-1.4, 1.4),
                                  delay: Self.lag * Double(1 - fx)))
            }
        }
    }

    /// The burst at `u` ∈ 0…1 of `seconds`.
    func apply(_ u: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for t in tiles {
            let local = max(0, min(1, (u * Self.seconds - t.delay) / (Self.seconds - Self.lag)))
            let move = CGFloat(1 - pow(1 - local, 3))          // ease-out: a burst, then drift
            var m = CATransform3DMakeTranslation(t.dx * move, t.dy * move, 0)
            m = CATransform3DRotate(m, t.spin * move, 0, 0, 1)
            let k = 1 - 0.45 * move
            m = CATransform3DScale(m, k, k, 1)
            t.layer.transform = m
            t.layer.opacity = Float(max(0, 1 - pow(local, 1.6)))
        }
        CATransaction.commit()
    }

    // MARK: On screen

    private static var live: [NSWindow] = []

    /// The pop-up whose picture this is sat at `frame` (screen points).
    static func play(image: CGImage, scale: CGFloat, from frame: NSRect, level: NSWindow.Level) {
        let burst = ReplyBurst(image: image, scale: scale, panel: frame.size,
                               seed: UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)))
        let w = NSWindow(contentRect: NSRect(x: frame.minX, y: frame.minY - spread,
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
            let u = min(1, Date().timeIntervalSince(start) / seconds)
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
