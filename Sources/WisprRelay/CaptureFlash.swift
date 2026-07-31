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

    /// Fire the vignette now, on the screen under the cursor.
    ///
    /// Synchronous when already on the main thread. Callers use this *before*
    /// their slow work (AX probe, screencapture) precisely so the panel is on
    /// screen first; an unconditional async hop would queue the flash behind that
    /// work and reintroduce the lag it exists to remove.
    static func announce() {
        let show = { if let screen = screenUnderCursor() { flash(on: screen) } }
        if Thread.isMainThread { show() } else { DispatchQueue.main.async(execute: show) }
    }

    /// The screen the cursor is on — the one that was just captured.
    static func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
