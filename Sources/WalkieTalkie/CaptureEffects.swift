import AppKit
import QuartzCore

/// Prototype "the screen was just captured, right here" effects — five
/// different visual answers to the same brief: converge on the pointer the
/// way `CaptureFlash.markCursor` already does, but bigger and busier, so
/// Victor can watch them side by side and pick one. **Nothing here is wired
/// into a real dictation start** — `CaptureEffectDemo` below is the only
/// caller, triggered by an env var for exactly this tryout. Whichever one
/// wins gets folded into the real trigger as a separate change.
enum CaptureEffect: String, CaseIterable {
    case spikes
    case gatheringPixels
    case wave
    case pinch
    case iris

    var label: String {
        switch self {
        case .spikes: return "Concentric spikes"
        case .gatheringPixels: return "Gathering pixels"
        case .wave: return "Converging wave"
        case .pinch: return "Pinch / vortex"
        case .iris: return "Iris shutter"
        }
    }

    /// How long the panel must stay up for this effect's animations
    /// (including any staggered start delays) to fully play out.
    var totalDuration: CFTimeInterval {
        switch self {
        case .spikes: return 0.75
        case .gatheringPixels: return 1.0
        case .wave: return 0.95
        case .pinch: return 0.75
        case .iris: return 0.7
        }
    }

    /// Fire this effect once, converging on `point` (global Cocoa
    /// coordinates, i.e. `NSEvent.mouseLocation`'s space) on whichever
    /// screen contains it.
    func play(at point: NSPoint) {
        guard let screen = Self.screen(containing: point) else { return }
        let (panel, view) = Self.makePanel(on: screen)
        let root = view.layer!
        // Screen-local, bottom-left-origin coordinates — CALayers on an
        // unflipped view (the AppKit default) share `NSScreen.frame`'s
        // convention once the screen's own origin is subtracted out.
        let target = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        let size = screen.frame.size

        switch self {
        case .spikes: Self.playSpikes(into: root, target: target, size: size)
        case .gatheringPixels: Self.playGatheringPixels(into: root, target: target, size: size)
        case .wave: Self.playWave(into: root, target: target, size: size)
        case .pinch: Self.playPinch(into: root, target: target, size: size)
        case .iris: Self.playIris(into: root, target: target, size: size)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.2) {
            panel.orderOut(nil)
            Self.activePanels.removeAll { $0 === panel }
        }
    }

    // MARK: - Panel plumbing (same shape as `CaptureFlash.flash`)

    private static var activePanels: [NSPanel] = []

    private static func makePanel(on screen: NSScreen) -> (NSPanel, NSView) {
        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)
        return (panel, view)
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// Far enough that spokes/rings visibly start off past every corner,
    /// whichever screen and whichever corner `target` is nearest.
    private static func reach(from target: CGPoint, size: CGSize) -> CGFloat {
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        return corners.map { hypot($0.x - target.x, $0.y - target.y) }.max() ?? 800
    }

    // MARK: - 1. Concentric spikes converging

    /// Sharp darts stationed all around the screen, tips already aimed at
    /// the point, that fly straight in and vanish into it — the read is
    /// "everything on this screen just got pulled to that one pixel."
    private static func playSpikes(into root: CALayer, target: CGPoint, size: CGSize) {
        let count = 20
        let radius = reach(from: target, size: size)
        let duration: CFTimeInterval = 0.5
        let now = CACurrentMediaTime()

        for i in 0..<count {
            let angle = (2 * .pi * Double(i) / Double(count)) + Double.random(in: -0.05...0.05)
            let a = CGFloat(angle)
            let start = CGPoint(x: target.x + radius * cos(a), y: target.y + radius * sin(a))

            let dartLength: CGFloat = 46
            let dartWidth: CGFloat = 9
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: dartLength, y: dartWidth / 2))
            path.addLine(to: CGPoint(x: dartLength, y: -dartWidth / 2))
            path.closeSubpath()

            let dart = CAShapeLayer()
            dart.path = path
            dart.fillColor = NSColor.captureAccent.withAlphaComponent(0.85).cgColor
            dart.anchorPoint = .zero
            dart.bounds = CGRect(x: 0, y: -dartWidth / 2, width: dartLength, height: dartWidth)
            dart.position = start
            // Local +x points from the tip (apex, at the anchor) toward the
            // base — aim that away from `target`, i.e. along the outward
            // radial direction, so the apex leads the flight inward.
            dart.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
            root.addSublayer(dart)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now + Double.random(in: 0...0.15)
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = start
            move.toValue = target

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.08

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0.0

            group.animations = [move, shrink, fade]
            dart.add(group, forKey: "converge")
        }
    }

    // MARK: - 2. Gathering pixels

    /// A field of loose squares scattered across the whole screen, each
    /// vacuumed toward the point at the same speed rather than the same
    /// duration — the far ones arrive later, so the point keeps "catching"
    /// new pixels for most of a second instead of everything landing at once.
    private static func playGatheringPixels(into root: CALayer, target: CGPoint, size: CGSize) {
        let count = 70
        let speed: CGFloat = 2200 // points/second
        let now = CACurrentMediaTime()

        for _ in 0..<count {
            let start = CGPoint(x: CGFloat.random(in: 0...size.width),
                                y: CGFloat.random(in: 0...size.height))
            let distance = hypot(target.x - start.x, target.y - start.y)
            let duration = max(0.25, min(0.9, Double(distance / speed)))
            let dot = CGFloat.random(in: 4...9)

            let pixel = CALayer()
            pixel.backgroundColor = NSColor.captureAccent.withAlphaComponent(0.8).cgColor
            pixel.cornerRadius = dot * 0.3
            pixel.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
            pixel.position = start
            root.addSublayer(pixel)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = start
            move.toValue = target

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.15

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.85, 0.85, 0.0]
            fade.keyTimes = [0.0, 0.7, 1.0]

            group.animations = [move, shrink, fade]
            pixel.add(group, forKey: "gather")
        }
    }

    // MARK: - 3. Converging wave

    /// Rings launched a beat apart, each collapsing from screen-covering to
    /// a dot and dissolving on the way in — a shutter's rings run backwards,
    /// like the screen was dropped into the point instead of blown out of it.
    private static func playWave(into root: CALayer, target: CGPoint, size: CGSize) {
        let radius = reach(from: target, size: size)
        let rings = 5
        let ringGap: CFTimeInterval = 0.11
        let duration: CFTimeInterval = 0.55
        let now = CACurrentMediaTime()

        for i in 0..<rings {
            let ring = CAShapeLayer()
            let base = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            ring.path = CGPath(ellipseIn: base, transform: nil)
            ring.position = target
            ring.fillColor = nil
            ring.strokeColor = NSColor.captureAccent.cgColor
            ring.lineWidth = 5
            ring.bounds = base
            root.addSublayer(ring)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now + Double(i) * ringGap
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.0

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 0.8, 0.3, 0.0]
            fade.keyTimes = [0.0, 0.08, 0.6, 1.0]

            group.animations = [shrink, fade]
            ring.add(group, forKey: "collapse")
        }
    }

    // MARK: - 4. Pinch / vortex

    /// The same darts as `playSpikes`, but each one travels a curved rather
    /// than a straight line — a quadratic path bowed the same way for every
    /// spoke, so the whole field spins into the point instead of just
    /// sliding into it. That shared rotation is the "pinch": the screen
    /// reads as wrung around the point, not just drained toward it.
    private static func playPinch(into root: CALayer, target: CGPoint, size: CGSize) {
        let count = 22
        let radius = reach(from: target, size: size) * 0.8
        let duration: CFTimeInterval = 0.55
        let now = CACurrentMediaTime()

        for i in 0..<count {
            let angle = 2 * .pi * Double(i) / Double(count)
            let a = CGFloat(angle)
            let start = CGPoint(x: target.x + radius * cos(a), y: target.y + radius * sin(a))
            let dx = target.x - start.x
            let dy = target.y - start.y
            // Perpendicular offset, same sign for every spoke — that
            // consistency is what makes it a swirl instead of a starburst.
            let perp = CGPoint(x: -dy, y: dx)
            let perpLength: CGFloat = max(hypot(perp.x, perp.y), 1)
            let bow: CGFloat = 0.42
            let midX: CGFloat = (start.x + target.x) / 2
            let midY: CGFloat = (start.y + target.y) / 2
            let bowMagnitude: CGFloat = radius * bow
            let controlX: CGFloat = midX + (perp.x / perpLength) * bowMagnitude
            let controlY: CGFloat = midY + (perp.y / perpLength) * bowMagnitude
            let control = CGPoint(x: controlX, y: controlY)

            let bladeLength: CGFloat = 60
            let bladeWidth: CGFloat = 7
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: bladeLength, y: bladeWidth / 2))
            path.addLine(to: CGPoint(x: bladeLength, y: -bladeWidth / 2))
            path.closeSubpath()

            let blade = CAShapeLayer()
            blade.path = path
            blade.fillColor = NSColor.captureAccent.withAlphaComponent(0.8).cgColor
            blade.anchorPoint = .zero
            blade.bounds = CGRect(x: 0, y: -bladeWidth / 2, width: bladeLength, height: bladeWidth)
            blade.position = start
            blade.transform = CATransform3DMakeRotation(CGFloat(angle + .pi), 0, 0, 1)
            root.addSublayer(blade)

            let travel = CGMutablePath()
            travel.move(to: start)
            travel.addQuadCurve(to: target, control: control)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = travel

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = CGFloat(angle + .pi)
            spin.toValue = CGFloat(angle + .pi) + 2.4

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.05

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0.0

            group.animations = [move, spin, shrink, fade]
            blade.add(group, forKey: "vortex")
        }
    }

    // MARK: - 5. Iris shutter

    /// Camera-aperture blades closing from every edge of the screen down to
    /// nothing at the point, then a single bright pop right as they meet —
    /// the literal read: a shutter just closed on that spot.
    private static func playIris(into root: CALayer, target: CGPoint, size: CGSize) {
        let count = 10
        let radius = reach(from: target, size: size)
        let duration: CFTimeInterval = 0.4
        let now = CACurrentMediaTime()

        for i in 0..<count {
            let angle = 2 * .pi * Double(i) / Double(count)
            let a = CGFloat(angle)
            let start = CGPoint(x: target.x + radius * cos(a), y: target.y + radius * sin(a))
            let arc = (2 * .pi / Double(count)) * 1.35 // blades overlap slightly, like a real aperture

            let bladeLength: CGFloat = radius * 0.35
            let bladeSpan = radius * CGFloat(tan(arc / 2))
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: bladeLength, y: bladeSpan))
            path.addLine(to: CGPoint(x: bladeLength, y: -bladeSpan))
            path.closeSubpath()

            let blade = CAShapeLayer()
            blade.path = path
            blade.fillColor = NSColor.captureAccent.withAlphaComponent(0.75).cgColor
            blade.anchorPoint = .zero
            blade.bounds = CGRect(x: 0, y: -bladeSpan, width: bladeLength, height: bladeSpan * 2)
            blade.position = start
            blade.transform = CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1)
            root.addSublayer(blade)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = start
            move.toValue = target

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.02

            group.animations = [move, shrink]
            blade.add(group, forKey: "close")
        }

        // The shutter's click: a small bright disc that pops as the blades
        // meet and is gone a moment later — the one part of this effect
        // that says "photo taken" rather than "thing sucked away."
        let flash = CAShapeLayer()
        let flashBase = CGRect(x: -18, y: -18, width: 36, height: 36)
        flash.path = CGPath(ellipseIn: flashBase, transform: nil)
        flash.bounds = flashBase
        flash.position = target
        flash.fillColor = NSColor.white.cgColor
        root.addSublayer(flash)

        let pop = CAAnimationGroup()
        pop.duration = 0.3
        pop.beginTime = now + duration * 0.85
        pop.fillMode = .forwards
        pop.isRemovedOnCompletion = false

        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.2, 1.4, 0.0]
        grow.keyTimes = [0.0, 0.3, 1.0]
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let flashFade = CAKeyframeAnimation(keyPath: "opacity")
        flashFade.values = [0.0, 1.0, 0.0]
        flashFade.keyTimes = [0.0, 0.3, 1.0]

        pop.animations = [grow, flashFade]
        flash.add(pop, forKey: "click")
    }
}

/// The tryout harness for `CaptureEffect` — plays all five, three times
/// each, in a fixed order, all converging on the same point so they can be
/// compared apples-to-apples. Triggered by `WALKIE_EFFECT_DEMO=1` in the
/// environment (see `AppDelegate`); not reachable any other way, because
/// this exists to be watched once while picking a favourite, not to become
/// a feature of its own.
enum CaptureEffectDemo {
    private static let repeats = 3
    private static let gapBetweenReps: CFTimeInterval = 0.35
    private static let gapBetweenEffects: CFTimeInterval = 0.9

    static func run() {
        let point = NSEvent.mouseLocation
        Log.info("effect-demo: starting at \(point), 5 effects × \(repeats) reps")
        var delay: CFTimeInterval = 0.3

        for effect in CaptureEffect.allCases {
            for rep in 1...repeats {
                let fireAt = delay
                DispatchQueue.main.asyncAfter(deadline: .now() + fireAt) {
                    Log.info("effect-demo: \(effect.label) (\(rep)/\(repeats))")
                    EffectBanner.show(text: "\(effect.label)  ·  \(rep)/\(repeats)")
                    effect.play(at: point)
                }
                delay += effect.totalDuration + gapBetweenReps
            }
            delay += gapBetweenEffects
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Log.info("effect-demo: done")
            EffectBanner.hide()
        }
    }
}

/// A small label at the top of the main screen naming whichever effect is
/// currently playing, so the demo is legible without reading the log.
private enum EffectBanner {
    private static var panel: NSPanel?

    static func show(text: String) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width: CGFloat = 420
        let height: CGFloat = 40
        let frame = NSRect(x: screen.frame.midX - width / 2,
                          y: screen.frame.maxY - height - 60,
                          width: width, height: height)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.sharingType = .none
            self.panel = panel
        }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        label.layer?.cornerRadius = 8
        label.frame = NSRect(origin: .zero, size: frame.size)

        panel.contentView = label
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
