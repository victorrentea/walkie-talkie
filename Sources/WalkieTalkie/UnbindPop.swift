import AppKit
import QuartzCore

/// The chip blowing up, in place of a sentence saying it is gone.
///
/// Unbinding used to flash `unbound — nothing is relayed now`, which is a panel
/// appearing in order to say that something disappeared — the news arrives in
/// the same instant as, and a few pixels away from, the thing it is about. A
/// burst says it where it happened: the label under his hand comes apart, and
/// there is nothing left there afterwards, which *is* the message.
///
/// Deliberately one screen and one animation. `BindFlight` spans every display
/// because it travels across them; this happens entirely inside the chip's own
/// frame, so it only has to exist where that frame is.
enum UnbindPop {
    /// Long enough to read as an event, short enough not to be in the way of
    /// whatever he does next — unbinding is usually followed immediately by
    /// binding somewhere else.
    private static let duration: CFTimeInterval = 0.42
    private static let shardCount = 12

    private static var panel: NSPanel?

    /// Blow the chip apart. `frame` is the chip's own frame in screen
    /// coordinates, read *before* the overlay relayouts itself away.
    static func burst(at frame: CGRect) {
        cancel()
        guard frame.width > 1, frame.height > 1 else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
                ?? NSScreen.main else { return }

        // `RelayPanel`, not `NSPanel`, for the same reason `BindFlight` uses it:
        // AppKit's `constrainFrameRect` drags a borderless window back under the
        // menu bar, and a chip on a display above the primary is exactly where
        // that shows.
        let host = RelayPanel(contentRect: screen.frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        host.isOpaque = false
        host.backgroundColor = .clear
        host.hasShadow = false
        host.ignoresMouseEvents = true
        // **Above the overlay**, unlike the bind flight, which slides underneath
        // it on purpose. There is nothing left to slide under: the chip is being
        // taken down in this same frame, and the burst is what replaces it.
        host.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        host.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // An unbind is often followed by a bind and then a dictation, whose first
        // act is to photograph the screen. This must never be in that picture.
        host.sharingType = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true

        // Panel coordinates: the chip's frame, moved into this screen's space.
        let local = CGRect(x: frame.minX - screen.frame.minX,
                           y: frame.minY - screen.frame.minY,
                           width: frame.width, height: frame.height)
        let centre = CGPoint(x: local.midX, y: local.midY)

        // **The ring is the blast.** It starts as the chip's own outline, so the
        // first frame is indistinguishable from the thing that was there, and
        // that is what makes the rest read as that thing coming apart rather than
        // as a new decoration appearing over it.
        let ring = CALayer()
        ring.frame = local
        ring.cornerRadius = min(10, local.height / 2)
        ring.borderWidth = 2
        ring.borderColor = NSColor.white.cgColor
        ring.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        view.layer?.addSublayer(ring)

        // **And the shards are what it was made of.** Thrown on a circle rather
        // than at random: a ring of debris reads as one event, where scattered
        // pieces read as several. The spread is uneven only in *distance*, which
        // is enough to stop it looking like a clock face.
        var shards: [CALayer] = []
        let reach = max(local.width, 90) * 0.75
        for i in 0..<shardCount {
            let angle = (Double(i) / Double(shardCount)) * 2 * .pi
            let size = CGFloat(4 + (i % 3) * 2)
            let shard = CALayer()
            shard.frame = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
            shard.cornerRadius = size / 3
            shard.backgroundColor = (i % 3 == 0 ? NSColor.systemOrange : NSColor.white).cgColor
            view.layer?.addSublayer(shard)
            shards.append(shard)

            let distance = reach * CGFloat(0.6 + Double(i % 4) * 0.18)
            let dx = CGFloat(Foundation.cos(angle)) * distance
            let dy = CGFloat(Foundation.sin(angle)) * distance
            let fly = CABasicAnimation(keyPath: "position")
            fly.fromValue = NSValue(point: NSPoint(x: centre.x, y: centre.y))
            fly.toValue = NSValue(point: NSPoint(x: centre.x + dx, y: centre.y + dy))
            // Everything decelerates: debris slows as it goes, and an ease-out is
            // the whole difference between thrown and merely moved.
            fly.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fly.duration = duration
            fly.fillMode = .forwards
            fly.isRemovedOnCompletion = false
            shard.add(fly, forKey: "fly")
            shard.add(fade(from: 1, to: 0, begin: duration * 0.35), forKey: "fade")
        }

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = 2.4
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        grow.duration = duration
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        ring.add(grow, forKey: "grow")
        // The ring goes before the shards do: the outline is the first thing that
        // stops being true.
        ring.add(fade(from: 1, to: 0, begin: 0), forKey: "fade")

        host.contentView = view
        host.setFrame(screen.frame, display: true)
        host.orderFrontRegardless()
        panel = host
        _ = shards   // held by the layer tree; named for what they are

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            // Only if it is still ours: a second unbind inside half a second has
            // already replaced this panel, and closing it here would take the new
            // burst down mid-flight.
            guard panel === host else { return }
            cancel()
        }
    }

    private static func fade(from: CGFloat, to: CGFloat, begin: CFTimeInterval) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = to
        a.beginTime = CACurrentMediaTime() + begin
        a.duration = max(0.01, duration - begin)
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        return a
    }

    static func cancel() {
        panel?.orderOut(nil)
        panel = nil
    }
}
