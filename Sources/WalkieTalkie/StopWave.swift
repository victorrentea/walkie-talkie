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

    /// The ring's profile across the band, inside to outside: a long tail and a
    /// steep front, which is what makes it read as moving outward.
    private static let shape: [(at: CGFloat, ink: CGFloat)] = [
        (0, 0), (0.35, 0.35), (0.7, 0.9), (0.82, 1), (0.92, 0.5), (1, 0),
    ]

    private static var active: [NSPanel] = []
    private static var fired = 0
    private static var last: [String: Any] = [:]

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

        func keyframe(_ front: CGFloat) -> [NSNumber] {
            locations(front: front, radius: radius).map { NSNumber(value: Double($0)) }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.locations = keyframe(radius)
        CATransaction.commit()

        let wave = CAKeyframeAnimation(keyPath: "locations")
        wave.values = [keyframe(birth), keyframe(band), keyframe(radius)]
        wave.keyTimes = [0, NSNumber(value: Double((band - birth) / (radius - birth))), 1]
        // Off the pointer fast and slowing, like anything struck.
        wave.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.6, 0.6, 1)
        wave.duration = duration
        ring.add(wave, forKey: "wave")

        fired += 1
        last = ["x": Double(point.x), "y": Double(point.y), "radius": Double(radius),
                "duration": duration, "screen": NSStringFromRect(frame)]
        Log.info(String(format: "🌊 the stop's wave leaves (%.0f, %.0f), off the screen in %.2f s",
                        point.x, point.y, duration))

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            panel.orderOut(nil)
            active.removeAll { $0 === panel }
        }
    }

    /// `GET /test/state.stopWave`: nothing here can be screenshot.
    static var report: [String: Any] {
        ["fired": fired, "up": active.count, "last": last]
    }

    /// **`WT_SHOOT_WAVE=/tmp/wave.png`**: the real layer at four moments, on a dark
    /// ground and a light one, the pointer marked with a red cross, off-centre so
    /// that a mirrored axis shows.
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
                let ring = gradient(frame: screen)
                place(ring, at: point, on: screen, radius: radius)
                ring.locations = locations(front: max(birth, share * radius), radius: radius)
                    .map { NSNumber(value: Double($0)) }
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
