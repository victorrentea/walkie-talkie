import AppKit
import ObjectiveC

/// **Under `RELAY_SHOOT` no window of this process ever reaches a screen**
/// (2026-10-08, Victor: *"când faci pozele la acele tooltipuri … și la panelul
/// din stânga sus, mereu mă frânez din a dicta … să nu mai văd alea … îmi apare
/// și în jurul mouse-ului, mă distrage"*).
///
/// The chip already parked itself 4000 pt off the displays while shooting
/// (`RelayWindow.reposition`), but only on that one path: the pointer-following
/// path, the panel unfolding into its corner, the hint bar, the halo and every
/// other window still put frames on his screen for a third of a second each.
/// Patching each was the losing game, so this catches them at the source: every
/// frame setter and every order-front of every `NSWindow` is swizzled to shift
/// the window `shift` points left of where it was asked to be. A snapshot is the
/// view drawing itself (`cacheDisplay`), which needs a window, not a visible
/// one, so the pictures do not change — sizes and everything inside are as asked.
///
/// Installed from `main.swift` before `NSApplication.shared`, and only when
/// `RELAY_SHOOT` is set; nothing else ever runs through it.
enum Offstage {
    /// Far enough left of the leftmost display any desk has; idempotent past
    /// `threshold`, because layout code reads the frame back and sets it again.
    static let shift: CGFloat = 12000
    private static let threshold: CGFloat = -8000

    static func offstage(_ r: NSRect) -> NSRect {
        r.minX < threshold ? r : r.offsetBy(dx: -shift, dy: 0)
    }

    static func install() {
        swap(#selector(NSWindow.setFrame(_:display:)), #selector(NSWindow.wt_setFrame(_:display:)))
        swap(#selector(NSWindow.setFrame(_:display:animate:)), #selector(NSWindow.wt_setFrame(_:display:animate:)))
        swap(#selector(NSWindow.setFrameOrigin(_:)), #selector(NSWindow.wt_setFrameOrigin(_:)))
        swap(#selector(NSWindow.setFrameTopLeftPoint(_:)), #selector(NSWindow.wt_setFrameTopLeftPoint(_:)))
        swap(#selector(NSWindow.orderFront(_:)), #selector(NSWindow.wt_orderFront(_:)))
        swap(#selector(NSWindow.orderFrontRegardless), #selector(NSWindow.wt_orderFrontRegardless))
        swap(#selector(NSWindow.makeKeyAndOrderFront(_:)), #selector(NSWindow.wt_makeKeyAndOrderFront(_:)))
        swap(#selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.wt_order(_:relativeTo:)))
    }

    private static func swap(_ original: Selector, _ replacement: Selector) {
        guard let a = class_getInstanceMethod(NSWindow.self, original),
              let b = class_getInstanceMethod(NSWindow.self, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

extension NSWindow {
    // After the exchange each `wt_` name calls the original implementation.
    @objc fileprivate func wt_setFrame(_ r: NSRect, display: Bool) {
        wt_setFrame(Offstage.offstage(r), display: display)
    }
    @objc fileprivate func wt_setFrame(_ r: NSRect, display: Bool, animate: Bool) {
        wt_setFrame(Offstage.offstage(r), display: display, animate: animate)
    }
    @objc fileprivate func wt_setFrameOrigin(_ p: NSPoint) {
        wt_setFrameOrigin(Offstage.offstage(NSRect(origin: p, size: frame.size)).origin)
    }
    @objc fileprivate func wt_setFrameTopLeftPoint(_ p: NSPoint) {
        let r = Offstage.offstage(NSRect(x: p.x, y: p.y - frame.height, width: frame.width, height: frame.height))
        wt_setFrameTopLeftPoint(NSPoint(x: r.minX, y: r.maxY))
    }
    private func wt_park() {
        if frame.minX >= -8000 { wt_setFrameOrigin(Offstage.offstage(frame).origin) }
    }
    @objc fileprivate func wt_orderFront(_ sender: Any?) { wt_park(); wt_orderFront(sender) }
    @objc fileprivate func wt_orderFrontRegardless() { wt_park(); wt_orderFrontRegardless() }
    @objc fileprivate func wt_makeKeyAndOrderFront(_ sender: Any?) { wt_park(); wt_makeKeyAndOrderFront(sender) }
    @objc fileprivate func wt_order(_ place: NSWindow.OrderingMode, relativeTo other: Int) {
        if place != .out { wt_park() }
        wt_order(place, relativeTo: other)
    }
}
