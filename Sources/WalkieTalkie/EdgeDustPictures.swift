import AppKit

/// **One way of drawing the dust on a prompt's edge** (2026-11-16). Victor, of the
/// glitter: *"dustul de pe margine nu arată a dust. mai încearcă încă 5 moduri …
/// să imite animația dust din jurul mouse-ului dar liniară … și redă-le alternativ
/// cu un label mare pe centru ecran, să le aleg"*. `EdgeDust` owns the panel, the
/// fade towards the screen's inside, the alpha and the swell; a picture only draws
/// into the strip it is handed.
///
/// - `strip` is layer-backed, not flipped, its bounds the strip: for `.top` the
///   screen's width × `EdgeDust.thickness` with **the screen's edge along its top
///   side** (`bounds.maxY`); for `.right` the thickness × the screen's height with
///   the edge along its right side (`bounds.maxX`). Add subviews or sublayers.
/// - `start` / `stop`: on screen / off it — nothing may run or burn CPU after `stop`,
///   and `start` may be called again later.
/// - `feed`: his voice, 30 times a second while the microphone is open (the last
///   ~128 ms at 16 kHz, floats in −1…1), zeros after it closes. Optional to use.
/// - `setIntensity`: 1 at rest; 2 for the half second before the edge goes — *"it
///   doubles its size and opacity"* is `EdgeDust`'s, the picture may add more dust.
protocol EdgeDustPicture: AnyObject {
    static var title: String { get }
    init?(strip: NSView, edge: EdgeDust.Edge)
    func start()
    func stop()
    func feed(_ samples: [Float])
    func setIntensity(_ k: CGFloat)
}

enum EdgeDustPictures {
    static let all: [EdgeDustPicture.Type] = [GlitterEdge.self, EdgeDustV1.self, EdgeDustV2.self, EdgeDustV3.self,
                                              EdgeDustV4.self, EdgeDustV5.self,
                                              // *"și încă 3 efecte tip «foc» dar cu praf"* (the same evening).
                                              EdgeDustV6.self, EdgeDustV7.self, EdgeDustV8.self]
    static let key = "edgeDust.variant"
    /// The one sentences wear: `defaults write … edgeDust.variant -int n`, or `POST /test/edge-dust-pick`.
    static var current: Int {
        let n = UserDefaults.standard.integer(forKey: key)
        return all.indices.contains(n) ? n : 0
    }
    static func type(_ n: Int) -> EdgeDustPicture.Type { all.indices.contains(n) ? all[n] : all[0] }
}

/// Variant 0, the evening's second try: still grains of every colour.
final class GlitterEdge: EdgeDustPicture {
    static let title = "Glitter"
    private let dust = CAEmitterLayer()

    private static let grainImage: CGImage? = {
        let px = 32
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let glow = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray,
                                    locations: [0, 0.35, 1]) else { return nil }
        let c = CGPoint(x: px / 2, y: px / 2)
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(px) / 2, options: [])
        return ctx.makeImage()
    }()

    init?(strip: NSView, edge: EdgeDust.Edge) {
        let box = strip.bounds
        let depth = min(EdgeDust.depth, edge == .top ? box.height : box.width)
        dust.frame = box
        dust.emitterShape = .rectangle
        dust.emitterMode = .surface
        dust.renderMode = .additive
        let length: CGFloat
        switch edge {
        case .top:
            length = box.width
            dust.emitterPosition = CGPoint(x: box.width / 2, y: box.height - depth / 2)
            dust.emitterSize = CGSize(width: box.width, height: depth)
        case .right:
            length = box.height
            dust.emitterPosition = CGPoint(x: box.width - depth / 2, y: box.height / 2)
            dust.emitterSize = CGSize(width: depth, height: box.height)
        }
        let life = Float(EdgeDust.life)
        dust.emitterCells = [(1.0, 0.5), (0.55, 0.35), (1.9, 0.15)].map { size, share in
            let cell = CAEmitterCell()
            cell.contents = Self.grainImage
            cell.birthRate = EdgeDust.birthRate(edgeLength: length) * Float(share)
            cell.lifetime = life
            cell.lifetimeRange = life * 0.5
            cell.color = CGColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 0.9)
            cell.redRange = 0.38; cell.greenRange = 0.38; cell.blueRange = 0.38
            cell.alphaRange = 0.1
            cell.alphaSpeed = -0.9 / life
            cell.scale = EdgeDust.grain * CGFloat(size) / 32
            cell.scaleRange = cell.scale * 0.5
            cell.scaleSpeed = cell.scale * 0.15
            cell.velocity = EdgeDust.drift / 2
            cell.velocityRange = EdgeDust.drift / 2
            cell.emissionRange = .pi * 2
            return cell
        }
        dust.birthRate = 0
        strip.layer?.addSublayer(dust)
    }
    func start() { dust.birthRate = 1 }
    func stop() { dust.birthRate = 0 }
    func feed(_ samples: [Float]) {}
    func setIntensity(_ k: CGFloat) { dust.birthRate = Float(k) }
}

/// **Every picture in turn, each named in the middle of the screen** — `POST
/// /test/edge-dust-show {"seconds": 7, "rounds": 2, "capturable": false}`. Both
/// edges at once, a synthetic voice fed in (`DemoVoice`), the last 1.2 s of each
/// turn at intensity 2.
final class EdgeDustShow {
    static let shared = EdgeDustShow()
    private var panels: [NSPanel] = []
    private var pictures: [EdgeDustPicture] = []
    private var label: NSPanel?
    private var feedTimer: Timer?
    private var voice = DemoVoice()
    private var turn = 0

    func run(seconds: Double, rounds: Int, only: [Int]?, capturable: Bool) {
        stop()
        turn += 1
        let order = (only ?? Array(EdgeDustPictures.all.indices)).filter { EdgeDustPictures.all.indices.contains($0) }
        guard !order.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        play(order, at: 0, left: max(1, rounds) * order.count, seconds: seconds, on: screen, capturable: capturable, mine: turn)
    }

    func stop() {
        turn += 1
        clear()
        label?.orderOut(nil); label = nil
    }

    private func clear() {
        feedTimer?.invalidate(); feedTimer = nil
        pictures.forEach { $0.stop() }
        panels.forEach { $0.orderOut(nil) }
        pictures = []; panels = []
    }

    private func play(_ order: [Int], at i: Int, left: Int, seconds: Double, on screen: NSScreen, capturable: Bool, mine: Int) {
        guard mine == turn else { return }
        clear()
        guard left > 0 else { label?.orderOut(nil); label = nil; Log.info("🌫️ the edge show is over"); return }
        let n = order[i % order.count]
        let type = EdgeDustPictures.type(n)
        say("\(n) · \(type.title)", on: screen, capturable: capturable)
        Log.info("🌫️ the edge show: \(n) · \(type.title)")
        for edge in [EdgeDust.Edge.top, .right] {
            guard let made = EdgeDust.build(edge, on: screen.frame, thickness: EdgeDust.thickness, variant: n) else { continue }
            made.panel.sharingType = capturable ? .readOnly : .none
            made.panel.alphaValue = EdgeDust.restAlpha
            made.picture.setIntensity(1)
            made.picture.start()
            made.panel.orderFrontRegardless()
            panels.append(made.panel); pictures.append(made.picture)
        }
        voice = DemoVoice()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let s = self.voice.samples()
            self.pictures.forEach { $0.feed(s) }
        }
        feedTimer = t
        RunLoop.main.add(t, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(seconds - 1.2, 0.5)) { [weak self] in
            guard let self, mine == self.turn else { return }
            self.pictures.forEach { $0.setIntensity(2) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.play(order, at: i + 1, left: left - 1, seconds: seconds, on: screen, capturable: capturable, mine: mine)
        }
    }

    private func say(_ text: String, on screen: NSScreen, capturable: Bool) {
        let size = NSSize(width: 900, height: 150)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2, width: size.width, height: size.height)
        let p = label ?? {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.hidesOnDeactivate = false
            p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let box = NSView(frame: NSRect(origin: .zero, size: size))
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
            box.layer?.cornerRadius = 28
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: 72, weight: .bold)
            field.textColor = .white
            field.alignment = .center
            field.frame = NSRect(x: 0, y: 26, width: size.width, height: 96)
            field.identifier = NSUserInterfaceItemIdentifier("label")
            box.addSubview(field)
            p.contentView = box
            return p
        }()
        (p.contentView?.subviews.first { $0.identifier?.rawValue == "label" } as? NSTextField)?.stringValue = text
        p.sharingType = capturable ? .readOnly : .none
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
        label = p
    }
}
