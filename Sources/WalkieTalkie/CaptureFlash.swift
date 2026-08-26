import AppKit
import QuartzCore

/// Red vignette confirming a screenshot was taken — the same shape as Victor
/// Addons' capture flash (gradient borders fading inward over the whole screen,
/// then fading out), in red rather than yellow so the two are never confused:
/// yellow means "Victor Addons captured it", red means "it went to the agent".
///
/// Click-through and above everything, so it never interrupts what he is doing.
enum CaptureFlash {
    private static var activePanels: [NSPanel] = []

    static func flash(on screen: NSScreen,
                      duration: CFTimeInterval = 1.2,
                      thickness: CGFloat = 30,
                      color: NSColor = .systemRed) {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Never let the confirmation of a screenshot land in the next screenshot.
        panel.sharingType = .none

        let size = screen.frame.size
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        // Translucent even at full opacity: the vignette tints the screen, it
        // does not cover it.
        let solid = color.withAlphaComponent(0.55).cgColor
        let clear = color.withAlphaComponent(0).cgColor

        let top = CAGradientLayer()
        top.frame = CGRect(x: 0, y: size.height - thickness, width: size.width, height: thickness)
        top.colors = [solid, clear]
        top.startPoint = CGPoint(x: 0.5, y: 1.0)
        top.endPoint = CGPoint(x: 0.5, y: 0.0)

        let bottom = CAGradientLayer()
        bottom.frame = CGRect(x: 0, y: 0, width: size.width, height: thickness)
        bottom.colors = [solid, clear]
        bottom.startPoint = CGPoint(x: 0.5, y: 0.0)
        bottom.endPoint = CGPoint(x: 0.5, y: 1.0)

        let left = CAGradientLayer()
        left.frame = CGRect(x: 0, y: 0, width: thickness, height: size.height)
        left.colors = [solid, clear]
        left.startPoint = CGPoint(x: 0.0, y: 0.5)
        left.endPoint = CGPoint(x: 1.0, y: 0.5)

        let right = CAGradientLayer()
        right.frame = CGRect(x: size.width - thickness, y: 0, width: thickness, height: size.height)
        right.colors = [solid, clear]
        right.startPoint = CGPoint(x: 1.0, y: 0.5)
        right.endPoint = CGPoint(x: 0.0, y: 0.5)

        for edge in [top, bottom, left, right] { view.layer?.addSublayer(edge) }

        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        view.layer?.add(fade, forKey: "fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            activePanels.removeAll { $0 === panel }
        }
    }

    /// Fire the vignette now, and drop a target on the spot the pointer was
    /// standing when the shutter went.
    ///
    /// **The border says what was captured; the reticle says where he was
    /// pointing while he said it.** Every shot the relay takes already carries
    /// that reading twice — burned into the picture for Victor, and in the file
    /// name for the agent — and both of those are things you find *afterwards*.
    /// This is the same fact at the only moment it can still be corrected: if
    /// the target lands somewhere he did not mean, the sentence is still being
    /// spoken and he can point again with F3.
    ///
    /// It is the mark Victor Addons drops after every ⌃P, and deliberately so —
    /// that desktop already means "here" by it, so there is nothing to learn.
    ///
    /// `cursor` is where the gesture happened, passed in for the same reason
    /// `ScreenCapture.grab` takes it: this runs a clipboard probe and a
    /// subprocess ahead of the capture, and by the time anything reads
    /// `NSEvent.mouseLocation` again the hand has moved on.
    ///
    /// Synchronous when already on the main thread. Callers use this *before*
    /// their slow work (AX probe, screencapture) precisely so the panel is on
    /// screen first; an unconditional async hop would queue the flash behind that
    /// work and reintroduce the lag it exists to remove.
    static func announce(cursor: NSPoint? = nil) {
        let point = cursor ?? NSEvent.mouseLocation
        let show = {
            if let screen = screen(containing: point) { flash(on: screen) }
            markCursor(at: point)
        }
        if Thread.isMainThread { show() } else { DispatchQueue.main.async(execute: show) }
    }

    /// The red target, on screen, at `point` in global Cocoa coordinates.
    ///
    /// The animation is Victor Addons' `ScreenCaptureFlash.markCursor`, values
    /// included: it lands at **1.3× and settles to 0.9× over 0.35s**, so it reads
    /// as a scope being brought down onto the spot rather than a badge appearing
    /// beside one, and what stays behind is the smaller, quieter mark. It is at
    /// **80% from the first frame** with the only fade in its last quarter — a
    /// mark that fades *in* asks to be watched arriving, and this one has to be
    /// already there when the eye gets to it.
    ///
    /// `sharingType = .none`, like the vignette: the relay photographs the
    /// screen milliseconds after this appears, and the confirmation of a capture
    /// must never be inside the capture it confirms.
    static func markCursor(at point: NSPoint, duration: CFTimeInterval = 2.0) {
        let reticle = CursorMarker.makeLayer(box: reticleBox)
        let side = reticle.bounds.width
        let frame = NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)

        let panel = NSPanel(contentRect: frame,
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

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        reticle.position = CGPoint(x: side / 2, y: side / 2)
        view.layer?.addSublayer(reticle)

        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        activePanels.append(panel)

        reticle.transform = CATransform3DMakeScale(0.9, 0.9, 1)   // the resting size
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.3
        zoom.toValue = 0.9
        zoom.duration = 0.35
        zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        reticle.add(zoom, forKey: "zoom")

        let life = CAKeyframeAnimation(keyPath: "opacity")
        life.values = [0.8, 0.8, 0.0]
        life.keyTimes = [0.0, 0.75, 1.0]
        life.duration = duration
        life.fillMode = .forwards
        life.isRemovedOnCompletion = false
        view.layer?.add(life, forKey: "life")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            activePanels.removeAll { $0 === panel }
        }
    }

    /// Roughly what the Addons reticle covers on his display — that one is
    /// `makeSniperReticle(scale: 1.25)` over a 65pt base.
    private static let reticleBox: CGFloat = 81

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// The screen the cursor is on — the one that was just captured.
    static func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
