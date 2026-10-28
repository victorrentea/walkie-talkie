import AppKit

/// **What the macOS magnifier lets Victor see of a display** (2026-10-28).
///
/// The full-screen magnifier (⌥+scroll in its "Full screen" style) is applied at
/// scanout, after the composited frame every capture client reads — so
/// `screencapture -D` hands back the whole *unmagnified* display while he sees a
/// quarter of it at 2×. Victor: *"be sure to capture everything on the screen
/// according to the zoom level"*. A shot is therefore cut down to this rectangle,
/// and the flight's frame starts from it, which the magnifier then blows up to
/// the edges of the glass.
///
/// Read through SkyLight's `SLSGetZoomParametersForDisplay` (private, no public
/// equivalent): it answers the **centre** of the visible area and the factor, per
/// display. Measured on the ASUS the same evening: set to 2× around (−1900, 20),
/// it read back (−1440, 270) — the centre clamped so the 960×540 view stays on
/// the 1920×1080 display. At rest it answers factor 1 and the display's centre.
///
/// Victor Addons' own zoom (`ShareZoom`) needs none of this: it is an ordinary
/// window over the display, so `screencapture` already takes the magnified picture.
enum MagnifierViewport {

    /// Below this a zoom is the tail of an animation back to 1×, not a view.
    static let minFactor = 1.01

    /// The visible part of `display`, both in global **top-left** coordinates
    /// (`CGDisplayBounds`'s), or nil when the magnifier is not zoomed in.
    /// Clamped again here, so a centre read mid-animation cannot put the
    /// rectangle off the display.
    static func visible(display: CGRect, center: CGPoint, factor: Double) -> CGRect? {
        guard factor >= minFactor, display.width > 0, display.height > 0 else { return nil }
        let w = display.width / CGFloat(factor), h = display.height / CGFloat(factor)
        let x = min(max(center.x - w / 2, display.minX), display.maxX - w)
        let y = min(max(center.y - h / 2, display.minY), display.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The same rectangle in AppKit coordinates (y up from the primary's bottom).
    static func appKit(_ topLeft: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: topLeft.minX, y: primaryHeight - topLeft.maxY,
               width: topLeft.width, height: topLeft.height)
    }

    /// Live: the visible part of this display, top-left coordinates, nil at 1×.
    static func visibleRect(of displayID: CGDirectDisplayID) -> CGRect? {
        guard let cid = mainConnection?(), let get = getParameters else { return nil }
        var center = CGPoint.zero, factor = 1.0, smooth = false
        guard get(cid, displayID, &center, &factor, &smooth) == 0 else { return nil }
        return visible(display: CGDisplayBounds(displayID), center: center, factor: factor)
    }

    /// Live, for the screen under an AppKit point: the visible part in AppKit
    /// coordinates, or the whole screen's frame when nothing is magnified.
    static func visibleFrame(at point: NSPoint) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
        else { return nil }
        guard let id = displayID(of: screen), let rect = visibleRect(of: id),
              let primaryHeight = NSScreen.screens.first?.frame.height
        else { return screen.frame }
        return appKit(rect, primaryHeight: primaryHeight)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: - SkyLight

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias GetParameters = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGPoint>,
                                                      UnsafeMutablePointer<Double>,
                                                      UnsafeMutablePointer<Bool>) -> Int32

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let mainConnection: MainConnection? = skyLight.flatMap { dlsym($0, "SLSMainConnectionID") }
        .map { unsafeBitCast($0, to: MainConnection.self) }
    private static let getParameters: GetParameters? = skyLight.flatMap { dlsym($0, "SLSGetZoomParametersForDisplay") }
        .map { unsafeBitCast($0, to: GetParameters.self) }
}
