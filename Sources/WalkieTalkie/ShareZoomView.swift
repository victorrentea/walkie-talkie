import AppKit

/// **Where Victor Mac' ⌥⇧ zoom (`ShareZoom`) has the desktop on its glass** (2026-11-27).
///
/// Victor: *"If I take a screenshot while I'm doing synthetic zoom, the picture that got
/// cropped, it doesn't respect the synthetic zoom."* The zoom is an opaque window that
/// films the display and draws a slice of it enlarged over the whole screen; input is
/// never remapped, so the wheel-drag box is measured in **desktop** points, while
/// `screencapture` photographs the **glass**. Laid on that frame as if it were the
/// desktop, the box cut out the wrong place at the wrong size.
///
/// Victor Mac publishes the slice with the drawn cursor (`vx vy vw vh`, global Cocoa
/// points, on `ro.victorrentea.share-zoom.cursor`, ~30 Hz while anything moves, every
/// 0.5 s at rest, an empty note when the zoom ends). `carry` maps a desktop rectangle onto
/// the glass with it. A note older than 1.5 s is a crashed Addons, not a zoom — the same
/// rule `ReplyPanel.watchShareZoom` keeps.
enum ShareZoomView {

    private static let lock = NSLock()
    private static var slice: CGRect?
    private static var seenAt: CFAbsoluteTime = 0
    static let stale: CFAbsoluteTime = 1.5

    /// Every note on the zoom's channel, as it arrives (main queue).
    static func note(_ info: [AnyHashable: Any]?) {
        let read: CGRect? = {
            guard let x = info?["vx"] as? Double, let y = info?["vy"] as? Double,
                  let w = info?["vw"] as? Double, let h = info?["vh"] as? Double,
                  w > 0, h > 0 else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }()
        lock.lock()
        slice = read
        seenAt = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    /// The slice on the glass right now, or nil (no zoom, an older Victor Mac that does
    /// not publish it, or a channel silent for longer than `stale`).
    static func current(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> CGRect? {
        lock.lock(); defer { lock.unlock() }
        guard now - seenAt <= stale else { return nil }
        return slice
    }

    /// `rect` (desktop, global Cocoa points) where it shows on the glass covering
    /// `screen`, cut to the screen — what scrolled off the glass during the drag was not
    /// on it. Unchanged when the slice is not on this screen or is not a magnification.
    static func carry(_ rect: CGRect, slice: CGRect?, screen: CGRect) -> CGRect {
        guard let slice, slice.width > 0, slice.height > 0,
              screen.contains(CGPoint(x: slice.midX, y: slice.midY)),
              slice.width < screen.width - 0.5 else { return rect }
        let sx = screen.width / slice.width, sy = screen.height / slice.height
        let glass = CGRect(x: screen.minX + (rect.minX - slice.minX) * sx,
                           y: screen.minY + (rect.minY - slice.minY) * sy,
                           width: rect.width * sx, height: rect.height * sy)
        let cut = glass.intersection(screen)
        return cut.isNull ? rect : cut
    }
}
