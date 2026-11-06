import AppKit
import QuartzCore

/// **The stop press answers with a wave** (2026-11-05, Victor: *"un efect mai
/// vizibil atunci când apăs Transcribing … un fel de inel gros care să se ducă
/// din locul în care e mouse-ul în jur radial, semitransparent alb, abia vizibil
/// … până iese din ecran"*).
///
/// A thick white ring, barely there, leaves the pointer the moment he ends a
/// sentence and travels until it has left the screen the pointer is on. It is the
/// press's receipt, beside the chip's `Transcribing`: the chip says it in words
/// by the pointer, this says it to the whole screen.
///
/// **A screen-sized radial `CAGradientLayer` whose `locations` move**, not a ring
/// scaled up: a scale would fatten the band with the radius, and it would have to
/// be a bitmap several screens wide to keep its edges. Core Animation interpolates
/// `locations` itself, so main stays free for the stop, which is the busiest
/// moment of the sentence.
///
/// **And it wipes the screen as it goes** (2026-11-06, Victor: *"ringul acela să
/// curețe orice animație care a înghețat pe ecran la momentul opririi dictării …
/// să fie un fel de ștergere a ecranului"*). What froze at the stop is
/// `CaretHalo`'s effect: `wipe` hangs on it a mask with the wave's own geometry and
/// the wave's own clock, so the picture goes under the crest instead of fading
/// everywhere at once.
///
/// Click-through, on every Space, over Victor Addons' zoom
/// (`CaptureFlash.flightLevel`), and `sharingType = .none`, so a shot a moment
/// later cannot photograph it. Which is why `shoot` and the `capturable` flag of
/// `POST /test/stop-wave` exist. Main thread only.
enum StopWave {
    /// The ring's thickness.
    static let band: CGFloat = 480
    /// Its white at the crest: *"abia alb … abia vizibil"*.
    static let peak: CGFloat = 0.14
    /// Mean speed. The duration comes from the distance, so a press in a corner
    /// looks the same as a press in the middle, and only lasts longer.
    static let speed: CGFloat = 1600
    /// The floor for a very small screen.
    static let shortest: CFTimeInterval = 0.6
    /// Where the ring starts: a dot at the pointer, which opens into the band.
    private static let birth: CGFloat = 8

    /// The ring's brightest line, as a share of the band: what a wiped picture
    /// is gone behind.
    private static let crest: CGFloat = 0.82

    /// The ring's profile across the band, inside to outside: a long tail and a
    /// steep front, which is what makes it read as moving outward.
    private static let shape: [(at: CGFloat, ink: CGFloat)] = [
        (0, 0), (0.35, 0.35), (0.7, 0.9), (crest, 1), (0.92, 0.5), (1, 0),
    ]

    /// How the front spends its time: off the pointer fast and slowing, like
    /// anything struck. The `CAMediaTimingFunction`'s control points, because
    /// `clearing` has to run the same curve backwards.
    private static let ease = (x1: 0.3, y1: 0.6, x2: 0.6, y2: 1.0)

    /// **One wave on its way**: all a mask needs to travel exactly with it.
    private struct Sweep {
        let point: NSPoint
        let radius: CGFloat
        let duration: CFTimeInterval
        /// `CACurrentMediaTime` at the press, set as both animations' `beginTime`.
        let began: CFTimeInterval
    }

    private static var travelling: Sweep?
    private static var active: [NSPanel] = []
    private static var fired = 0
    private static var wiped = 0
    private static var last: [String: Any] = [:]
    private static var lastWipe: [String: Any] = [:]

    /// The distance at which the ring has left a rectangle: the farthest corner.
    static func reach(from point: NSPoint, in screen: NSRect) -> CGFloat {
        let dx = max(point.x - screen.minX, screen.maxX - point.x)
        let dy = max(point.y - screen.minY, screen.maxY - point.y)
        return hypot(dx, dy)
    }

    /// The gradient's radius: the ring's inner edge is at the corner when its
    /// outer edge is at the gradient's end, so no location ever passes 1.
    static func radius(reach: CGFloat) -> CGFloat { reach + band }

    static func duration(radius: CGFloat) -> CFTimeInterval {
        max(shortest, CFTimeInterval(radius / speed))
    }

    /// The gradient's `locations` with the ring's outer edge at `front`. The inner
    /// edge stays at the pointer until the band has opened, so no location is ever
    /// below 0, and the ring grows out of the pointer instead of appearing 200 pt
    /// from it.
    static func locations(front: CGFloat, radius: CGFloat) -> [CGFloat] {
        let inner = max(0, front - band)
        return shape.map { (inner + $0.at * (front - inner)) / radius }
    }

    /// How much of a wiped picture is left at this share of the band: nothing
    /// behind the crest, all of it at the ring's outer edge.
    static func left(at share: CGFloat) -> CGFloat {
        share <= crest ? 0 : (share - crest) / (1 - crest)
    }

    /// **The seconds after the press at which the crest has passed all of
    /// `frame`.** The landing of a bound effect waits for this, not for the wave's
    /// end: the ring is off a square in the middle of the screen long before it is
    /// out of the farthest corner. The band is still opening below `band`, with
    /// the crest at its share of `front`; after that the crest is a fixed distance
    /// behind it, and `min` picks the phase.
    static func clearing(_ frame: NSRect, from point: NSPoint, radius: CGFloat,
                         duration: CFTimeInterval) -> CFTimeInterval {
        let far = reach(from: point, in: frame)
        let front = min(far / crest, far + (1 - crest) * band)
        let travelled = (min(front, radius) - birth) / (radius - birth)
        return duration * timeShare(travelled: Double(max(0, travelled)))
    }

    /// `ease` backwards: the share of the time at which the front has travelled
    /// this share of the way. A Bézier has no closed inverse; 24 halvings of its
    /// parameter are far below a pixel.
    private static func timeShare(travelled: Double) -> Double {
        func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let s = (low + high) / 2
            if bezier(s, ease.y1, ease.y2) < travelled { low = s } else { high = s }
        }
        return bezier((low + high) / 2, ease.x1, ease.x2)
    }

    /// Start and end of the radial gradient, in the layer's unit space: an end
    /// `radius` away on both axes draws a circle on a screen that is not square.
    private static func place(_ layer: CAGradientLayer, at point: NSPoint, on screen: NSRect, radius: CGFloat) {
        let centre = CGPoint(x: (point.x - screen.minX) / screen.width,
                             y: (point.y - screen.minY) / screen.height)
        layer.startPoint = centre
        layer.endPoint = CGPoint(x: centre.x + radius / screen.width,
                                 y: centre.y + radius / screen.height)
    }

    private static func gradient(frame: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.frame = frame
        layer.colors = shape.map { NSColor.white.withAlphaComponent(peak * $0.ink).cgColor }
        return layer
    }

    /// The mask `wipe` hangs on a view: the ring's own stops, inked with what is
    /// left of the picture. Beyond its outer edge a radial gradient keeps its last
    /// colour, so everything the wave has not reached stays whole.
    private static func mask(frame: CGRect) -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.frame = frame
        layer.colors = shape.map { NSColor.black.withAlphaComponent(left(at: $0.at)).cgColor }
        return layer
    }

    /// `locations` moving outward: the same animation for the ring and the mask,
    /// which is why the two cannot drift. Both gradients are `radius` long.
    private static func travel(_ sweep: Sweep) -> CAKeyframeAnimation {
        let radius = sweep.radius
        func keyframe(_ front: CGFloat) -> [NSNumber] {
            locations(front: front, radius: radius).map { NSNumber(value: Double($0)) }
        }
        let wave = CAKeyframeAnimation(keyPath: "locations")
        wave.values = [keyframe(birth), keyframe(band), keyframe(radius)]
        wave.keyTimes = [0, NSNumber(value: Double((band - birth) / (radius - birth))), 1]
        wave.timingFunction = CAMediaTimingFunction(controlPoints: Float(ease.x1), Float(ease.y1),
                                                    Float(ease.x2), Float(ease.y2))
        wave.duration = sweep.duration
        wave.beginTime = sweep.began
        return wave
    }

    /// The gradient's stops once the wave has left: where a layer rests when its
    /// animation has been taken off.
    private static func gone(_ layer: CAGradientLayer, radius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.locations = locations(front: radius, radius: radius).map { NSNumber(value: Double($0)) }
        CATransaction.commit()
    }

    /// **Wipe `view` with the wave on its way** (`frame` is its window's, in global
    /// Cocoa coordinates): the picture goes as the crest reaches it. Answers the
    /// seconds until the crest has passed all of it, or nil with no wave travelling.
    /// Whoever asked takes the mask off once the window is out of sight, or the
    /// picture stays erased under it.
    static func wipe(_ view: NSView, in frame: NSRect) -> CFTimeInterval? {
        guard let sweep = travelling, let host = view.layer else { return nil }
        let wipe = mask(frame: view.bounds)
        place(wipe, at: sweep.point, on: frame, radius: sweep.radius)
        gone(wipe, radius: sweep.radius)
        wipe.add(travel(sweep), forKey: "wave")
        host.mask = wipe
        let cleared = clearing(frame, from: sweep.point, radius: sweep.radius, duration: sweep.duration)
        let left = max(0, cleared - (CACurrentMediaTime() - sweep.began))
        wiped += 1
        lastWipe = ["frame": NSStringFromRect(frame), "clearsAfter": cleared, "left": left]
        Log.info(String(format: "🌊 the wave wipes %.0f×%.0f, gone %.2f s after the press", frame.width, frame.height, cleared))
        return left
    }

    /// **Send one wave out of `point`** (global Cocoa coordinates), on the screen
    /// under it. `capturable` is for a desk: it lets a screenshot see this one.
    static func fire(at point: NSPoint, capturable: Bool = false) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
                ?? NSScreen.main else { return }
        let frame = screen.frame
        let radius = radius(reach: reach(from: point, in: frame))
        let duration = duration(radius: radius)

        let panel = RelayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = CaptureFlash.flightLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        panel.sharingType = capturable ? .readOnly : .none

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let ring = gradient(frame: view.bounds)
        place(ring, at: point, on: frame, radius: radius)
        view.layer?.addSublayer(ring)

        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        active.append(panel)

        let sweep = Sweep(point: point, radius: radius, duration: duration, began: CACurrentMediaTime())
        travelling = sweep
        gone(ring, radius: radius)
        ring.add(travel(sweep), forKey: "wave")

        fired += 1
        last = ["x": Double(point.x), "y": Double(point.y), "radius": Double(radius),
                "duration": duration, "screen": NSStringFromRect(frame)]
        Log.info(String(format: "🌊 the stop's wave leaves (%.0f, %.0f), off the screen in %.2f s",
                        point.x, point.y, duration))

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            panel.orderOut(nil)
            active.removeAll { $0 === panel }
            if travelling?.began == sweep.began { travelling = nil }
        }
    }

    /// `GET /test/state.stopWave`: nothing here can be screenshot.
    static var report: [String: Any] {
        ["fired": fired, "up": active.count, "last": last, "wiped": wiped, "lastWipe": lastWipe]
    }

    /// **`WT_SHOOT_WAVE=/tmp/wave.png`**: the real layers at four moments, on a dark
    /// ground and a light one, the pointer marked with a red cross, off-centre so
    /// that a mirrored axis shows. The blue square stands for a frozen effect, under
    /// the real mask.
    static func shoot(to path: String) {
        let screen = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let point = NSPoint(x: 520, y: 760)
        let radius = radius(reach: reach(from: point, in: screen))
        let shares: [CGFloat] = [0.1, 0.3, 0.6, 0.9]
        let grounds: [NSColor] = [NSColor(white: 0.1, alpha: 1), NSColor(white: 0.95, alpha: 1)]
        let scale: CGFloat = 0.28, gap: CGFloat = 12
        let cell = NSSize(width: screen.width * scale, height: screen.height * scale)
        let width = (cell.width + gap) * CGFloat(shares.count) + gap
        let height = (cell.height + gap) * CGFloat(grounds.count) + gap
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = CGContext(data: nil, width: Int(width * 2), height: Int(height * 2),
                                 bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        cg.scaleBy(x: 2, y: 2)
        cg.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (row, ground) in grounds.enumerated() {
            for (column, share) in shares.enumerated() {
                cg.saveGState()
                cg.translateBy(x: gap + CGFloat(column) * (cell.width + gap),
                               y: gap + CGFloat(row) * (cell.height + gap))
                cg.clip(to: CGRect(origin: .zero, size: cell))
                cg.scaleBy(x: scale, y: scale)
                cg.setFillColor(ground.cgColor)
                cg.fill(screen)
                let stops = locations(front: max(birth, share * radius), radius: radius)
                    .map { NSNumber(value: Double($0)) }
                let frozen = NSRect(x: 310, y: 0, width: 1117, height: 1117)
                let picture = CALayer()
                picture.frame = frozen
                picture.backgroundColor = NSColor.systemBlue.cgColor
                let wipe = mask(frame: picture.bounds)
                place(wipe, at: point, on: frozen, radius: radius)
                wipe.locations = stops
                picture.mask = wipe
                cg.saveGState()
                cg.translateBy(x: frozen.minX, y: frozen.minY)
                picture.render(in: cg)
                cg.restoreGState()
                let ring = gradient(frame: screen)
                place(ring, at: point, on: screen, radius: radius)
                ring.locations = stops
                ring.render(in: cg)
                cg.setStrokeColor(NSColor.systemRed.cgColor)
                cg.setLineWidth(6)
                cg.strokeLineSegments(between: [CGPoint(x: point.x - 24, y: point.y), CGPoint(x: point.x + 24, y: point.y),
                                                CGPoint(x: point.x, y: point.y - 24), CGPoint(x: point.x, y: point.y + 24)])
                cg.restoreGState()
            }
        }
        guard let image = cg.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
