import AppKit
import QuartzCore
import CoreImage

/// Prototype "the screen was just captured, right here" effects — seven
/// different visual answers to the same brief: converge on the pointer the
/// way `CaptureFlash.markCursor` already does, but bigger and busier, so
/// Victor can watch them side by side and pick one. `CaptureEffectDemo`
/// below is a standalone tryout harness triggered by an env var, for
/// playing all of them (or a chosen one) back to back outside of any real
/// dictation.
///
/// **Two of these are also live-playtested for real** (2026-09-04, Victor's
/// ask): `CaptureFlash.announce(cycleMarker: true)` round-robins every
/// actual dictation start between the classic reticle, `.spikes`, and
/// `.tapRipple`, so he can compare them in day-to-day use, not just the
/// demo, before picking a favourite next week.
enum CaptureEffect: String, CaseIterable {
    case spikes
    case gatheringPixels
    case wave
    case pinch
    case iris
    case wireRings
    case tapRipple

    var label: String {
        switch self {
        case .spikes: return "Concentric spikes"
        case .gatheringPixels: return "Gathering pixels"
        case .wave: return "Undulating wave"
        case .pinch: return "Pinch / vortex"
        case .iris: return "Iris shutter"
        case .wireRings: return "Converging wire rings"
        case .tapRipple: return "Tap ripple (Android emulator style)"
        }
    }

    /// How long the panel must stay up for this effect's animations
    /// (including any staggered start delays) to fully play out.
    var totalDuration: CFTimeInterval {
        switch self {
        case .spikes: return 1.3
        case .gatheringPixels: return 1.0
        case .wave: return 1.1
        case .pinch: return 0.75
        case .iris: return 0.7
        case .wireRings: return 1.0
        case .tapRipple: return 0.6
        }
    }

    /// Fire this effect once, converging on `point` (global Cocoa
    /// coordinates, i.e. `NSEvent.mouseLocation`'s space) on whichever
    /// screen contains it. `speed` scales every duration involved — `1.5`
    /// plays it 1.5x slower, `0.5` twice as fast.
    func play(at point: NSPoint, speed: Double = 1.0) {
        guard let screen = Self.screen(containing: point) else { return }
        let (panel, view) = Self.makePanel(on: screen)
        let root = view.layer!
        // Screen-local, bottom-left-origin coordinates — CALayers on an
        // unflipped view (the AppKit default) share `NSScreen.frame`'s
        // convention once the screen's own origin is subtracted out.
        let target = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        let size = screen.frame.size

        switch self {
        case .spikes: Self.playSpikes(into: root, target: target, size: size, speed: speed)
        case .gatheringPixels: Self.playGatheringPixels(into: root, target: target, size: size)
        case .wave: Self.playWave(into: root, target: target, size: size, screen: screen)
        case .pinch: Self.playPinch(into: root, target: target, size: size)
        case .iris: Self.playIris(into: root, target: target, size: size)
        case .wireRings: Self.playWireRings(into: root, target: target, size: size)
        case .tapRipple: Self.playTapRipple(into: root, target: target)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration * speed + 0.2) {
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

    /// Sharp darts scattered across the whole screen, tips already aimed at
    /// the point, that fly straight in and vanish into it — the read is
    /// "everything on this screen just got pulled to that one pixel."
    ///
    /// **Bigger, brighter, slower** (2026-09-04, Victor's ask): the original
    /// darts were thin enough and quick enough to read as a flicker rather
    /// than shapes flying in. Wider, longer, fully opaque, outlined and
    /// glowing so they hold up over any background, and given almost a full
    /// second so the flight itself is watchable rather than guessed at.
    ///
    /// **Scattered, not ringed** (2026-09-04, Victor's ask): they used to
    /// stand in a ring just past every edge, arriving from "outside" the
    /// screen. Starting them at random points *on* the screen instead reads
    /// as "the whole desktop is being pulled in," not "something flew in
    /// from off-screen" — each dart's angle is now computed from wherever it
    /// actually starts rather than assigned to it.
    private static func playSpikes(into root: CALayer, target: CGPoint, size: CGSize, speed: Double = 1.0) {
        let count = 52
        // (2026-09-04, Victor's ask) 1.2x faster than the previous baseline —
        // the caller's `speed` multiplier still applies on top of that.
        let duration: CFTimeInterval = (0.95 / 1.2) * speed
        let jitter: Double = (0.25 / 1.2) * speed
        let now = CACurrentMediaTime()

        for _ in 0..<count {
            let start = CGPoint(x: CGFloat.random(in: 0...size.width),
                                y: CGFloat.random(in: 0...size.height))
            // The direction this dart actually has to travel — outward from
            // `target` through `start` — not a slot on a ring it was never
            // placed on.
            let angle = atan2(start.y - target.y, start.x - target.x)

            let dartLength: CGFloat = 90
            let dartWidth: CGFloat = 22
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: dartLength, y: dartWidth / 2))
            path.addLine(to: CGPoint(x: dartLength, y: -dartWidth / 2))
            path.closeSubpath()

            let dart = CAShapeLayer()
            dart.path = path
            dart.fillColor = NSColor.captureAccent.cgColor
            dart.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            dart.lineWidth = 2
            // (2026-09-04, Victor's ask) No glow — a flat fill/stroke only.
            // Also start fully invisible so the dart never sits there
            // statically before its (jittered) animation begins; it should
            // only ever be seen while already converging.
            dart.opacity = 0
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
            group.beginTime = now + Double.random(in: 0...jitter)
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = start
            move.toValue = target

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.1

            // (2026-09-04, Victor's ask) Starts fully invisible (0%) and
            // brightens to 50% so the dart is only ever seen while it's
            // already moving — never sitting there statically first — then
            // holds at 50% for most of the flight and dims out at the end.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 0.5, 0.5, 0.0]
            fade.keyTimes = [0.0, 0.08, 0.8, 1.0]

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

    // MARK: - 3. Undulating wave

    /// **Actually ripples the desktop** (2026-09-04, Victor's ask): the
    /// previous version drew rings *over* the screen; this grabs one real
    /// frame of it and pushes its own pixels through a pinch/bulge filter
    /// that oscillates and decays at the point, so what moves is the
    /// desktop itself, not a shape drawn on top of it. Falls back to the
    /// plain ring version if a frame can't be captured (no Screen Recording
    /// permission yet) rather than showing nothing.
    private static func playWave(into root: CALayer, target: CGPoint, size: CGSize, screen: NSScreen) {
        guard let cgImage = captureScreenImage(screen) else {
            playWaveRings(into: root, target: target, size: size)
            return
        }

        // Downsampled before filtering: a full Retina frame put through
        // CIPinchDistortion ~25 times in under a second is far more GPU work
        // than this needs, and the softness the downsample leaves behind
        // reads as part of the ripple rather than as a lower-quality image.
        let downscale: CGFloat = 0.5
        let fullImage = CIImage(cgImage: cgImage)
        let ciImage = fullImage.transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Everywhere else in this file works in the screen's points; Core
        // Image always works in its own image's pixel space, so the target
        // point and radius are scaled up to match once, here.
        let pixelsPerPoint = CGFloat(cgImage.width) / size.width * downscale
        let centerInImage = CGPoint(x: target.x * pixelsPerPoint, y: target.y * pixelsPerPoint)
        let radiusInImage = 320 * pixelsPerPoint

        let waveLayer = CALayer()
        waveLayer.frame = CGRect(origin: .zero, size: size)
        waveLayer.contentsGravity = .resizeAspectFill
        root.addSublayer(waveLayer)

        let duration: CFTimeInterval = 0.85
        let start = CACurrentMediaTime()
        let cycles: Double = 3 // three in-out swells, decaying to stillness

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { timer in
            let elapsed = CACurrentMediaTime() - start
            let progress = min(elapsed / duration, 1.0)
            guard progress < 1.0, let filter = CIFilter(name: "CIPinchDistortion") else {
                timer.invalidate()
                return
            }
            let decay = 1.0 - progress
            let scaleAmount = sin(progress * cycles * 2 * .pi) * decay * 0.7

            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgPoint: centerInImage), forKey: kCIInputCenterKey)
            filter.setValue(radiusInImage, forKey: kCIInputRadiusKey)
            filter.setValue(scaleAmount, forKey: kCIInputScaleKey)

            guard let output = filter.outputImage,
                  let rendered = context.createCGImage(output, from: ciImage.extent) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            waveLayer.contents = rendered
            CATransaction.commit()
        }
        RunLoop.main.add(timer, forMode: .common)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = start + duration
        fadeOut.duration = 0.2
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        waveLayer.add(fadeOut, forKey: "fadeOut")
    }

    /// A single frame of `screen`, in its own native pixel size. `nil` if
    /// Screen Recording permission isn't granted (same requirement
    /// `ScreenCapture.grab`'s `/usr/sbin/screencapture` subprocess has).
    private static func captureScreenImage(_ screen: NSScreen) -> CGImage? {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            return nil
        }
        return CGDisplayCreateImage(CGDirectDisplayID(displayID))
    }

    /// The fallback (and the original prototype): rings launched a beat
    /// apart, each collapsing from screen-covering to a dot and dissolving
    /// on the way in — a shutter's rings run backwards, like the screen was
    /// dropped into the point instead of blown out of it.
    private static func playWaveRings(into root: CALayer, target: CGPoint, size: CGSize) {
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

    // MARK: - 6. Converging wire rings

    /// A tight bundle of thin, translucent concentric circles — one visual
    /// "ring" built out of several close-set wires, the way a target
    /// reticle or a lock-on HUD is drawn — that shrinks and spins gently as
    /// a single unit down into the point. Kept translucent throughout so it
    /// reads as an overlay grid rather than a solid shape, and only really
    /// fades in its last moments as the bundle disappears.
    private static func playWireRings(into root: CALayer, target: CGPoint, size: CGSize) {
        let wires = 6
        let maxRadius = reach(from: target, size: size)
        let duration: CFTimeInterval = 0.9
        let now = CACurrentMediaTime()

        for i in 0..<wires {
            // A narrow band near the outer edge, not spread across the
            // whole screen — that's what keeps the wires reading as one
            // bundle rather than as separate independent rings.
            let spread = CGFloat(i) / CGFloat(wires - 1)
            let startRadius = maxRadius * (0.68 + 0.14 * spread)
            let base = CGRect(x: -startRadius, y: -startRadius, width: startRadius * 2, height: startRadius * 2)

            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: base, transform: nil)
            ring.bounds = base
            ring.position = target
            ring.fillColor = nil
            ring.strokeColor = NSColor.captureAccent.cgColor
            ring.lineWidth = 1.5
            root.addSublayer(ring)

            let group = CAAnimationGroup()
            group.duration = duration
            group.beginTime = now + Double(i) * 0.015
            group.timingFunction = CAMediaTimingFunction(name: .easeIn)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.01

            // Alternating spin direction per wire — nested rings visibly
            // turning past each other as they close in is what sells "wire
            // mesh" instead of "shrinking circle."
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            let direction: CGFloat = i % 2 == 0 ? 1 : -1
            spin.fromValue = 0
            spin.toValue = direction * 1.2

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 0.5, 0.42, 0.0]
            fade.keyTimes = [0.0, 0.12, 0.78, 1.0]

            group.animations = [shrink, spin, fade]
            ring.add(group, forKey: "converge")
        }
    }

    // MARK: - 7. Tap ripple (Android emulator style)

    /// A single solid yellow disc, the same "tap indicator" Android Studio's
    /// emulator draws over a touch point: fades in already centered on the
    /// point at 100pt diameter, grows out to 250pt while fading out, and is
    /// gone. No convergence — this is the opposite metaphor from the other
    /// six (it marks the point rather than gathering the screen toward it),
    /// added on request purely to compare against them.
    private static func playTapRipple(into root: CALayer, target: CGPoint) {
        let startDiameter: CGFloat = 100
        let endDiameter: CGFloat = 250
        let duration: CFTimeInterval = 0.55

        let dot = CAShapeLayer()
        let base = CGRect(x: -startDiameter / 2, y: -startDiameter / 2, width: startDiameter, height: startDiameter)
        dot.path = CGPath(ellipseIn: base, transform: nil)
        dot.bounds = base
        dot.position = target
        dot.fillColor = NSColor.systemYellow.cgColor
        dot.strokeColor = nil
        dot.opacity = 0
        root.addSublayer(dot)

        let group = CAAnimationGroup()
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = endDiameter / startDiameter

        // Fades in fast, holds briefly at full strength while still
        // growing, then fades out over the second half of the growth.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.6, 0.6, 0.0]
        fade.keyTimes = [0.0, 0.15, 0.4, 1.0]

        group.animations = [grow, fade]
        dot.add(group, forKey: "tap")
    }
}

/// The tryout harness for `CaptureEffect` — plays all seven, three times
/// each, in a fixed order, all converging on the same point so they can be
/// compared apples-to-apples. Triggered by `WALKIE_EFFECT_DEMO=1` in the
/// environment (see `AppDelegate`); not reachable any other way, because
/// this exists to be watched once while picking a favourite, not to become
/// a feature of its own.
enum CaptureEffectDemo {
    private static let gapBetweenReps: CFTimeInterval = 0.35
    private static let gapBetweenEffects: CFTimeInterval = 0.9

    /// The full-set tryout: every effect once each, three reps, normal speed.
    static func run() {
        runOne(nil, reps: 3, speed: 1.0)
    }

    /// `effect == nil` plays the whole set, in `CaptureEffect` order;
    /// otherwise plays just that one effect `reps` times. `speed` scales
    /// every duration in the played effect(s) — `1.5` runs 1.5x slower,
    /// `0.5` runs twice as fast. Driven by `WALKIE_EFFECT_ONLY` /
    /// `WALKIE_EFFECT_REPS` / `WALKIE_EFFECT_SPEED` (see `AppDelegate`), for
    /// exactly the "replay #1, 3 times, 1.5x slower" kind of ask.
    ///
    /// Each rep converges on wherever the mouse **is when that rep fires**,
    /// not on one point captured before the first — Victor can move the
    /// pointer between reps and watch each one chase it there.
    static func runOne(_ only: CaptureEffect?, reps: Int, speed: Double) {
        let effects = only.map { [$0] } ?? Array(CaptureEffect.allCases)
        Log.info("effect-demo: \(effects.count) effect(s) × \(reps) reps, speed ×\(speed)")
        var delay: CFTimeInterval = 0.3

        for effect in effects {
            for rep in 1...reps {
                let fireAt = delay
                DispatchQueue.main.asyncAfter(deadline: .now() + fireAt) {
                    let point = NSEvent.mouseLocation
                    Log.info("effect-demo: \(effect.label) (\(rep)/\(reps)) at \(point)")
                    EffectBanner.show(text: "\(effect.label)  ·  \(rep)/\(reps)")
                    effect.play(at: point, speed: speed)
                }
                delay += effect.totalDuration * speed + gapBetweenReps
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
