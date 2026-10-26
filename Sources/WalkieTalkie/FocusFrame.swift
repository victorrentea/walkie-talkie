import AppKit
import ApplicationServices
import QuartzCore

/// **A red outline (orange until 2026-10-26) round the window a caret sentence will be typed into,
/// and the caret in it for the heads** (2026-10-13).
///
/// Victor: *"When I'm dictating at caret, be sure to highlight in an orange line
/// visible the window which is receiving currently my prompt, basically the one
/// that have the focus … The same should happen for the plain dictation. And of
/// course, only show this border if the window … is visible … Clearly tell what
/// window will receive my dictation or my prompt."*
///
/// A caret sentence goes wherever the keyboard focus is when it lands, and
/// nothing on screen said where that was: the ring and the heads rode the
/// pointer, which in a wall of tiled terminals is routinely over one window
/// while the focus sits in another. So this names the window itself, by
/// drawing on it, and hands the caret's position to `CaretHalo.headsAt` so the
/// six heads converge on the place the words will actually appear.
///
/// ## Read, not pushed
///
/// The frontmost app is asked through Accessibility every `tick` (0.2 s) while
/// a caret sentence is open — a click into another window, or the caret moving
/// as he types, re-aims both within a fifth of a second. An `AXObserver` would
/// be one per app, re-registered on every switch, and still blind where the
/// polling is (VS Code's lazy tree). The reads run on a serial queue; one still
/// in flight makes the next tick skip rather than queue behind it.
///
/// ## Visible, or nothing
///
/// *"Only show this border if the window … is visible."* The focused window has
/// to be in the window server's on-screen list (not minimised, not on another
/// Space) and not wholly covered by ordinary windows in front of it — sampled on
/// a 9 × 9 grid. The caret has to be uncovered and on a screen too, or the heads
/// stay down. No focused window at all (the desktop, an app with none) draws
/// nothing.
///
/// ## Inside the window's edge
///
/// The line is drawn **on** the window, just inside its edge, never outside it:
/// a maximised window, or one tiled against a screen edge, has no outside on
/// that side, and the tiled wall he works in has a neighbour's content there.
/// Rounded like the window's own corners (macOS 15: 10 pt).
///
/// `sharingType = .none`, like everything else this app draws — it must not be
/// in the shutter's pictures (`evals/test_capture_decorations.py`).
final class FocusFrame {

    /// What the last read found. `window` and `caret` in Cocoa global space.
    struct Reading: Equatable {
        var app: String?
        var window: CGRect?
        var visible = false
        var caret: NSPoint?
        /// **Nowhere to type** (2026-10-14): where the crossed-out pin goes —
        /// the window's middle when its focus is known to take no text
        /// (`TerminalBinding.focusTakesNoText`), the pointer's screen's
        /// middle when the app has no window at all. Nil when there is a caret,
        /// or when Accessibility cannot tell.
        var noCaret: NSPoint?
        /// Why there is no caret, for the log (`TerminalBinding.caretReading`).
        var miss: String?
    }

    /// The caret the pin should stand on, or nil — main thread.
    var onCaret: ((NSPoint?) -> Void)?
    /// Where the crossed-out pin should stand, or nil — main thread.
    var onNoCaret: ((NSPoint?) -> Void)?

    private(set) var active = false
    private(set) var reading = Reading()

    private static let tick: TimeInterval = 0.2
    /// **The map pin's red** (2026-10-26, Victor: *"border-ul care apare în jurul
    /// ferestrei … să fie aceeași culoare cu pin-ul roșu, să se înțeleagă că e
    /// aceeași poveste"*): the outline and the pin standing on the caret inside
    /// it are one sign, so they share `Glyphs.mapPin`'s fill. Orange from
    /// 2026-10-13 until then — not the heads' amber, which on a light page
    /// needed a shadow; red reads as a line round a window on every theme too.
    private static let ink = NSColor.systemRed
    static let lineWidth: CGFloat = 4
    private static let corner: CGFloat = 10
    private static let fadeIn: TimeInterval = 0.15

    private let queue = DispatchQueue(label: "ro.victorrentea.walkie-talkie.focus-frame", qos: .userInitiated)
    private var timer: Timer?
    private var probing = false
    /// Bumped on every edge, so a read that started before an off cannot land after it.
    private var generation = 0
    private var panel: RelayPanel?
    private var outline: CAShapeLayer?

    /// Driven from `AppDelegate.syncBorrowedGestures`: a caret sentence is open
    /// — recording, or its words still in flight to the caret.
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        generation &+= 1
        if on {
            Log.info("🟧 focus frame on — outlining the window the words will be typed into")
            probe()
            let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.probe() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
            reading = Reading()
            hide()
            onCaret?(nil)
            onNoCaret?(nil)
            Log.info("🟧 focus frame off")
        }
    }

    var report: [String: Any] {
        var r: [String: Any] = ["active": active, "visible": reading.visible,
                                "shown": panel?.isVisible ?? false, "app": reading.app ?? ""]
        if let w = reading.window { r["window"] = [w.minX, w.minY, w.width, w.height] }
        if let c = reading.caret { r["caret"] = [c.x, c.y] }
        if let n = reading.noCaret { r["noCaret"] = [n.x, n.y] }
        return r
    }

    // MARK: - Reading

    private func probe() {
        guard active, !probing else { return }
        let gen = generation
        // `frontmostApplication` is a main-thread question (`WindowContext`).
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return apply(Reading())
        }
        probing = true
        let pid = app.processIdentifier
        let name = app.localizedName
        let bundle = app.bundleIdentifier
        let screen = (RelayWindow.screenUnderMouse() ?? NSScreen.main).map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
        queue.async { [weak self] in
            let r = Self.read(pid: pid, app: name, bundle: bundle, screenMiddle: screen)
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing = false
                guard gen == self.generation, self.active else { return }
                self.apply(r)
            }
        }
    }

    private struct ServerWindow { let pid: pid_t; let layer: Int; let alpha: Double; let frame: CGRect }

    /// Off the main thread.
    static func read(pid: pid_t, app: String?, bundle: String? = nil, screenMiddle: NSPoint? = nil) -> Reading {
        var r = Reading(app: app)
        guard let window = TerminalBinding.focusedWindow(pid: pid).frame else {
            // No window anywhere: a ⌘V lands nowhere (the desktop, an app with
            // every window closed) — the crossed pin on the pointer's screen.
            r.noCaret = screenMiddle
            return r
        }
        r.window = window
        let list = serverWindows()
        // The focused window as the window server has it: the first ordinary
        // window of that app at the same place. Absent = minimised, or on
        // another Space.
        guard let index = list.firstIndex(where: { $0.pid == pid && $0.layer == 0 && same($0.frame, window) })
        else { return r }
        let inFront = list[..<index].filter { $0.layer == 0 && $0.alpha > 0.05 }.map(\.frame)
        func uncovered(_ p: NSPoint) -> Bool {
            NSScreen.screens.contains { $0.frame.contains(p) } && !inFront.contains { $0.contains(p) }
        }
        let steps = 9
        r.visible = (0..<steps).contains { i in
            (0..<steps).contains { j in
                uncovered(NSPoint(x: window.minX + window.width * (CGFloat(i) + 0.5) / CGFloat(steps),
                                  y: window.minY + window.height * (CGFloat(j) + 0.5) / CGFloat(steps)))
            }
        }
        guard r.visible else { return r }
        let found = TerminalBinding.caretReading(pid: pid, in: window)
        guard let caret = found.point, uncovered(caret) else {
            r.miss = found.miss ?? "its caret is covered"
            if TerminalBinding.focusTakesNoText(pid: pid, bundle: bundle) {
                r.noCaret = NSPoint(x: window.midX, y: window.midY)
            }
            return r
        }
        r.caret = caret
        return r
    }

    /// Front to back, in Cocoa global space.
    private static func serverWindows() -> [ServerWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"], w > 1, h > 1
            else { return nil }
            return ServerWindow(pid: pid, layer: info[kCGWindowLayer as String] as? Int ?? 0,
                                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                                frame: CGRect(x: x, y: primary.frame.maxY - y - h, width: w, height: h))
        }
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2
            && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    // MARK: - Drawing

    private func apply(_ r: Reading) {
        let old = reading
        reading = r
        if r.window != old.window || r.visible != old.visible || r.app != old.app || (r.noCaret == nil) != (old.noCaret == nil) {
            if let w = r.window {
                Log.info(String(format: "🟧 the words go to %@ — window %.0f×%.0f at (%.0f, %.0f), %@%@",
                                r.app ?? "?", w.width, w.height, w.minX, w.minY,
                                r.visible ? "outlined" : "not visible — no outline, no pin",
                                r.visible ? (r.caret != nil ? "" : r.noCaret != nil ? ", nothing in it takes text — the pin crossed out"
                                                                                    : ", no caret found in it (\(r.miss ?? "?")) — no pin") : ""))
            } else {
                Log.info("🟧 the words go to \(r.app ?? "nothing") — no focused window, nothing outlined\(r.noCaret != nil ? ", the pin crossed out on the screen" : "")")
            }
        }
        if let w = r.window, r.visible { show(around: w) } else { hide() }
        if r.caret != old.caret { onCaret?(r.caret) }
        if r.noCaret != old.noCaret { onNoCaret?(r.noCaret) }
    }

    private func show(around window: CGRect) {
        let p = panel ?? makePanel()
        if p.frame != window {
            p.setFrame(window, display: false)
            let box = CGRect(origin: .zero, size: window.size).insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            outline?.frame = CGRect(origin: .zero, size: window.size)
            outline?.path = CGPath(roundedRect: box, cornerWidth: Self.corner, cornerHeight: Self.corner, transform: nil)
            CATransaction.commit()
        }
        guard !p.isVisible else { return }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            p.animator().alphaValue = 1
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> RelayPanel {
        // `RelayPanel` for its `constrainFrameRect`: a window at the top of a
        // screen must be outlined where it is, not where AppKit would push this.
        let p = RelayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = CaretHalo.capturable ? .readOnly : .none
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        let line = CAShapeLayer()
        line.fillColor = nil
        line.strokeColor = Self.ink.cgColor
        line.lineWidth = Self.lineWidth
        view.layer?.addSublayer(line)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        outline = line
        panel = p
        return p
    }
}
