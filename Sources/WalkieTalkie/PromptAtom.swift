import AppKit
import QuartzCore

/// **The prompt at rest is an atom in the corner, not a panel** (2026-11-06).
///
/// Victor: *"în loc de panoul acela din stânga sus semitransparent care mai mult
/// îmi obscurează privirea, vreau să pui în loc o animație … niște arcuri de cerc,
/// niște elipse … suprapuse, albastru și albastru și roz … cam atât de mare … dacă
/// dau cu mouse-ul pe el apare abia atunci dialogul acela opac … el stă acolo atâta
/// cât ar fi stat dialogul"*. It is up exactly while the panel would have rested;
/// `RelayWindow.syncPromptAtom` decides, this only draws.
///
/// **Three tilted rings, in Core Animation.** A comet painted on a flat ring, spun
/// about its own axis, seen tilted: the head really runs along an ellipse. The
/// tilted plane then turns slowly, and that is the whole animation — a dozen layers
/// the render server moves on its own, so the app spends nothing on it per frame.
/// `CATransformLayer` is not needed: `CALayer` flattens, and a flattened tilt is the
/// orthographic ellipse wanted here.
///
/// **It ignores the mouse.** The hover is geometry (`RelayWindow.pointerReachedPanel`,
/// the rule the panel already had), so 170 pt of corner never eats a click on the
/// page under it, and the pointer over it is what brings the dialog that does.
final class PromptAtom {
    /// Victor's box on 2026-11-06 was 178 × 163 pt.
    static let side: CGFloat = 170
    /// …and its top-left corner stood 28 pt in and about 44 pt under the menu bar.
    static let inset = NSSize(width: 28, height: 44)

    /// A desk's switch, as on `StopWave`: lets a screenshot see it.
    static var capturable = false

    private struct Orbit {
        let red, green, blue: CGFloat
        /// Where the ellipse's long axis points at the start, degrees.
        let turned: CGFloat
        /// 0 is a circle, 90 a line.
        let tilt: CGFloat
        /// Seconds for the comet's lap, and for the ellipse's own turn; a negative one runs backwards.
        let lap, drift: CFTimeInterval
        /// **Off the centre, a fraction of `side`**: *"nu concentrice"*.
        let dx, dy: CGFloat
    }

    /// *"albastru și albastru și roz"*.
    private static let orbits = [
        Orbit(red: 0.13, green: 0.42, blue: 1.00, turned: 15, tilt: 70, lap: 2.6, drift: 31, dx: -0.025, dy: 0.02),
        Orbit(red: 0.20, green: 0.78, blue: 1.00, turned: 75, tilt: 66, lap: -3.3, drift: -43, dx: 0.03, dy: 0.015),
        Orbit(red: 1.00, green: 0.22, blue: 0.64, turned: 135, tilt: 73, lap: 2.1, drift: 37, dx: -0.005, dy: -0.03),
    ]

    private static let ringRadius: CGFloat = 0.44
    private static let scale: CGFloat = 2

    private var panel: NSPanel?
    private var spinning: [CALayer] = []
    private var up = false
    /// Bumped by every show and hide, so a fade that finishes late orders nothing out.
    private var turn = 0

    // MARK: - Pure

    /// The corner it stands in, on a screen's `visibleFrame`.
    static func home(in area: NSRect) -> NSRect {
        NSRect(x: area.minX + inset.width, y: area.maxY - inset.height - side, width: side, height: side)
    }

    /// **Where a hand counts as being on the prompt.** At rest, only the atom: the
    /// dialog is not there, and its rectangle is someone else's page. Revealed, the
    /// dialog and the atom's corner together, or a short dialog would end above the
    /// pointer that brought it, go, and come back under the same pointer forever.
    static func zone(atom: NSRect, panel: NSRect, revealed: Bool) -> NSRect {
        revealed ? atom.union(panel) : atom
    }

    // MARK: - Up and down

    var frame: NSRect? { up ? panel?.frame : nil }

    func show(at frame: NSRect, level: NSWindow.Level, sharing: NSWindow.SharingType) {
        let p = panel ?? make()
        p.sharingType = Self.capturable ? .readOnly : sharing
        guard !up else { return }
        up = true
        turn += 1
        p.level = NSWindow.Level(rawValue: level.rawValue + 1)
        p.setFrame(frame, display: false)
        if !p.isVisible { p.alphaValue = 0 }
        startSpinning()
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }
    }

    /// Follows the panel while it is up: the share-zoom can start under it.
    func setSharing(_ sharing: NSWindow.SharingType) {
        panel?.sharingType = Self.capturable ? .readOnly : sharing
    }

    func hide(fadeOver seconds: TimeInterval = 0.12) {
        guard up, let p = panel else { return }
        up = false
        turn += 1
        let hiding = turn
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = seconds
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.turn == hiding else { return }
            p.orderOut(nil)
            self.spinning.forEach { $0.removeAllAnimations() }
        })
    }

    // MARK: - The layers

    private func make() -> NSPanel {
        let box = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let p = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: box)
        view.wantsLayer = true
        let root = view.layer ?? CALayer()
        for orbit in Self.orbits { root.addSublayer(tilted(orbit, in: box)) }
        root.addSublayer(nucleus(in: box))
        p.contentView = view
        panel = p
        return p
    }

    /// turn (the ellipse's axis, slowly) › tilt (makes the circle an ellipse) › ring (the comet's lap).
    private func tilted(_ orbit: Orbit, in box: NSRect) -> CALayer {
        let centre = CGPoint(x: box.midX + orbit.dx * box.width, y: box.midY + orbit.dy * box.height)
        let turn = CALayer()
        turn.frame = box
        turn.position = centre
        turn.setValue(Self.radians(orbit.turned), forKeyPath: "transform.rotation.z")
        turn.setValue(orbit.drift, forKey: "period")
        let tilt = CALayer()
        tilt.frame = box
        tilt.transform = CATransform3DMakeRotation(Self.radians(orbit.tilt), 1, 0, 0)
        let ring = CALayer()
        ring.frame = box
        ring.contents = Self.ring(orbit)
        ring.contentsScale = Self.scale
        ring.setValue(orbit.lap, forKey: "period")
        tilt.addSublayer(ring)
        turn.addSublayer(tilt)
        spinning += [turn, ring]
        return turn
    }

    private func nucleus(in box: NSRect) -> CALayer {
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
        dot.position = CGPoint(x: box.midX, y: box.midY)
        dot.cornerRadius = 5.5
        dot.backgroundColor = CGColor(red: 0.62, green: 0.34, blue: 1, alpha: 1)
        dot.shadowColor = dot.backgroundColor
        dot.shadowOpacity = 0.9
        dot.shadowRadius = 7
        dot.shadowOffset = .zero
        return dot
    }

    private func startSpinning() {
        for layer in spinning where layer.animation(forKey: "spin") == nil {
            guard let period = layer.value(forKey: "period") as? CFTimeInterval else { continue }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.byValue = period < 0 ? -2 * CGFloat.pi : 2 * CGFloat.pi
            spin.duration = abs(period)
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            layer.add(spin, forKey: "spin")
        }
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    /// The faint whole ring, so an ellipse reads as one, and the comet on it: a
    /// head, and a tail that thins and fades over 300°.
    private static func ring(_ orbit: Orbit) -> CGImage? {
        let px = Int(side * scale)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: side / 2, y: side / 2)
        let radius = side * ringRadius
        let colour = { (alpha: CGFloat) in CGColor(red: orbit.red, green: orbit.green, blue: orbit.blue, alpha: alpha) }
        ctx.setLineCap(.round)
        ctx.setStrokeColor(colour(0.30))
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        ctx.setShadow(offset: .zero, blur: 8, color: colour(0.75))
        let steps = 150
        for step in stride(from: steps, to: 0, by: -1) {
            let along = CGFloat(step) / CGFloat(steps)              // 1 at the tail's end, 0 at the head
            let from = -along * radians(300)
            let to = from + radians(300) / CGFloat(steps) * 1.4
            ctx.setStrokeColor(colour(pow(1 - along, 1.6)))
            ctx.setLineWidth(1.5 + 5 * (1 - along))
            ctx.addArc(center: .zero, radius: radius, startAngle: from, endAngle: to, clockwise: false)
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    // MARK: - The picture

    /// **One frame, drawn by hand.** The rings cannot be photographed (`.none`) and
    /// a flat render of 3D transforms loses the tilt, so the page gets the same
    /// three matrices in Core Graphics: the shot and the tests read this.
    static func still() -> CGImage? {
        let px = Int(side * scale)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        for orbit in orbits {
            guard let ring = ring(orbit) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: side * (0.5 + orbit.dx), y: side * (0.5 + orbit.dy))
            ctx.rotate(by: radians(orbit.turned))
            ctx.scaleBy(x: 1, y: cos(radians(orbit.tilt)))
            ctx.rotate(by: radians(orbit.turned * 2))
            ctx.draw(ring, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
            ctx.restoreGState()
        }
        ctx.setFillColor(CGColor(red: 0.62, green: 0.34, blue: 1, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: side / 2 - 5.5, y: side / 2 - 5.5, width: 11, height: 11))
        return ctx.makeImage()
    }

    @discardableResult
    static func writeStill(to path: String) -> Bool {
        guard let image = still(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
