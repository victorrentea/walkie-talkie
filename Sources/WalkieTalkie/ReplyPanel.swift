import AppKit

/// **The agent's short answer to a question he dictated, beside the pointer**
/// (2026-10-07).
///
/// Victor: *"sometimes I'm asking questions, direct questions, not telling what
/// to do … there should be a way that the agent is able to reach me back … a
/// bit of a panel that appears next to the mouse carrying the response of the
/// model … I'm going to answer by just dictating more … it's super important to
/// be brief."* A prompt with a `?` in it carries one more footer line asking for
/// `walkie-reply "…"` (`AppDelegate.questionHint`); the script posts here through
/// `POST /reply` with the token in `~/.walkie-talkie/reply-token`.
///
/// **Only he dismisses it — the ✕, no clock, no bar** (the same evening: first
/// *"having an X icon in the corner for me to dismiss it explicitly"*, then,
/// over a countdown that started when the pointer moved: *"NO PROGRESSBAR. i
/// have to manually dismiss it"*). An answer that went away on a timer while he
/// was looking at the terminal is one he never got.
///
/// **Answers queue, one on screen at a time** (2026-10-08, Victor: *"să nu apară
/// una peste alta, să apară doar după ce am închis una … pe rând, stau la
/// coadă"*). A newer answer waits behind the open one and comes up, at the
/// pointer, when that one is closed (✕ or its link).
///
/// It sits where the pointer was when the answer arrived and does not follow —
/// it is read, and clicked once. **It rises from the bottom of the screen like
/// a toast, a little past its place, and settles back** (2026-10-08, Victor:
/// *"să intre din josul ecranului, up, ca un fel de toaster până în dreptul meu
/// … să vină un pic peste și să vină puțin înapoi … marginea de sus a panelului
/// … un pic sub mouse"*): centred on the pointer's x, its top edge `belowPointer`
/// under the pointer. `sharingType = .none`: the next dictation's
/// pictures are of his screen, not of this.
enum ReplyPanel {
    private static var panel: NSPanel?
    private static var queue: [(text: String, label: String?, tty: String?)] = []
    private static var arrivedAt: NSPoint = .zero

    static let maxChars = 400
    private static let width: CGFloat = 380
    private static let font = NSFont.systemFont(ofSize: 15)
    /// 26, up from 20, to carry the 26 pt walkie (2026-10-08, *"make the icon
    /// slightly larger … so I can click it easier"*); the name and the ✕ are
    /// centred in it.
    private static let headerH: CGFloat = 26
    private static let iconSide: CGFloat = 26

    private static let walkie: NSImage? = RelayWindow.walkieURL("walkie-bound").flatMap { NSImage(contentsOf: $0) }

    /// What is on screen — `GET /test/state`.
    static var shown: String?

    /// **A click on the terminal's name binds it** (Victor: *"if I click on it,
    /// I will rebind my Walkie to that terminal … underlined if I hover it, in
    /// the hand of the mouse"*) — `AppDelegate.rebindFromMenu`.
    static var onBind: ((String) -> Void)?

    /// **A click on the walkie puts that terminal in front, centred on the
    /// Retina, at once** (2026-10-08, Victor: *"if I click on the Walkie Talkie
    /// icon … that terminal should pop in front … on the retina in the center of
    /// the screen … with no animation"*) — to read more, or ask more, there.
    /// Nothing is bound; the name is the link that binds.
    static var onPresent: ((String) -> Void)?

    /// **The ☠️ left of the ✕ sends that session `kamikaze`** (2026-10-08,
    /// Victor: *"to the left of the X … an emoji with a skull … with a click, it
    /// sends kamikaze back to the session that sent this message"*) — the
    /// answer was the last thing he needed from it. Closes the panel.
    static var onKamikaze: ((String) -> Void)?

    static func show(_ raw: String, from label: String?, tty: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(raw, from: label, tty: tty) }
            return
        }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        guard !text.isEmpty else { return }
        if panel != nil {
            queue.append((text, label, tty))
            Log.info("💬 answer from \(label ?? "agent") queued behind the open one — \(queue.count) waiting")
            return
        }
        present(text, from: label, tty: tty)
    }

    private static func present(_ text: String, from label: String?, tty: String?) {
        allowCursorInBackground
        shown = text
        arrivedAt = NSEvent.mouseLocation

        let pad: CGFloat = 12
        let inner = width - 2 * pad
        // **The walkie, not 💬** (Victor: *"change the 💬 icon with the one of
        // walkie"*) — `walkie-bound.png`, the menu bar's own picture.
        // **As large as the answer, cut with … at the end** (Victor, 2026-10-08:
        // *"increase the font of the title to be the same as the response,
        // possibly doing ellipsis at the end"*).
        let header = LinkLabel(labelWithString: label ?? "agent")
        header.lineBreakMode = .byTruncatingTail
        header.cell?.truncatesLastVisibleLine = true
        header.font = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        header.textColor = NSColor.white.withAlphaComponent(0.6)
        // **The click is the answer read: the panel goes** (Victor, 2026-10-08:
        // *"I clicked on the title … and it did not close the window. Should
        // have."*), and the terminal's border flies into the chip.
        if let tty = tty {
            header.onClick = {
                Log.info("💬 the answer's terminal clicked — binding \(tty), panel closed")
                close()
                onBind?(tty)
            }
        }
        // **Not selectable; a press on the words drags the panel** (2026-10-08,
        // Victor: *"I should be able to drag the little window … by clicking
        // on the text and the text shouldn't be selectable"*) — the label
        // passes the click through to `ReplyRoot`.
        let body = InertLabel(wrappingLabelWithString: text)
        body.isSelectable = false
        body.font = font
        body.textColor = .white
        body.preferredMaxLayoutWidth = inner - 18
        let bodySize = body.sizeThatFits(NSSize(width: inner - 18, height: .greatestFiniteMagnitude))
        let height = pad + headerH + 6 + ceil(bodySize.height) + pad

        let root = ReplyRoot(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        let icon = ReplyIcon(frame: NSRect(x: pad, y: height - pad - headerH, width: iconSide, height: iconSide))
        icon.image = Self.walkie
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let tty = tty {
            icon.onClick = {
                Log.info("💬 the answer's walkie clicked — \(tty) to the front, centred on the Retina, panel closed")
                close()
                onPresent?(tty)
            }
        }
        root.addSubview(icon)
        let textX = pad + iconSide + 6
        let buttons: CGFloat = tty == nil ? 1 : 2
        header.frame = NSRect(x: textX, y: height - pad - headerH + 3,
                              width: inner - (textX - pad) - buttons * (iconSide + 6), height: 20)
        body.frame = NSRect(x: pad, y: pad, width: inner - 18, height: ceil(bodySize.height))
        root.addSubview(header)
        root.addSubview(body)
        // **The ✕ as large as the walkie** (2026-10-08, Victor: *"X-ul … aceeași
        // mărime ca și simbolul Walkie Talkie"*).
        let x = ReplyCloseButton(frame: NSRect(x: width - pad - iconSide, y: height - pad - headerH, width: iconSide, height: iconSide))
        x.onClick = { Log.info("💬 answer dismissed (✕)"); close() }
        root.addSubview(x)
        var hot = [x.frame]
        if tty != nil { hot.append(icon.frame) }
        if let tty = tty {
            let skull = ReplyCloseButton(frame: x.frame.offsetBy(dx: -(iconSide + 6), dy: 0))
            skull.glyph = "☠️"
            skull.onClick = {
                Log.info("💬 the answer's ☠️ clicked — kamikaze to \(tty), panel closed")
                close()
                onKamikaze?(tty)
            }
            root.addSubview(skull)
            hot.append(skull.frame)
            let fit = min(header.frame.width, header.intrinsicContentSize.width)
            hot.append(NSRect(x: header.frame.minX, y: header.frame.minY, width: fit, height: header.frame.height))
        }
        root.hot = hot

        let p = NSPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = .none
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.contentView = root
        let target = origin(for: root.frame.size, at: arrivedAt)
        p.setFrameOrigin(target)
        p.orderFrontRegardless()
        panel = p
        rise(p, to: target)
        Log.info("💬 answer from \(label ?? "agent") — \(text.count) chars; up until the ✕\(queue.isEmpty ? "" : ", \(queue.count) waiting")")
    }

    /// **A background app's `NSCursor.set()` is ignored unless the process asks
    /// for it** — the window server keeps the frontmost app's cursor. Once per
    /// launch; the same private property every pointer utility sets.
    private static let allowCursorInBackground: Void = {
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()

    static func close() {
        panel?.orderOut(nil)
        panel = nil
        shown = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // The next hop, so a click that closed this one is over before the
        // next panel lands under the pointer.
        DispatchQueue.main.async {
            guard panel == nil else { queue.insert(next, at: 0); return }
            present(next.text, from: next.label, tty: next.tty)
        }
    }


    /// How far under the pointer the top edge settles.
    private static let belowPointer: CGFloat = 14
    private static let riseSeconds = 0.5
    private static var riseTimer: Timer?

    /// Centred on the pointer's x, top edge `belowPointer` under it — above the
    /// pointer instead when there is no room below; clamped into its screen.
    private static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let visible = screen(at: point)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var x = point.x - size.width / 2
        var y = point.y - belowPointer - size.height
        if y < visible.minY { y = point.y + belowPointer }
        x = max(visible.minX, min(x, visible.maxX - size.width))
        y = max(visible.minY, min(y, visible.maxY - size.height))
        return NSPoint(x: x, y: y)
    }

    private static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// **The toast**: from just under the screen's bottom edge up to `target`,
    /// on an ease-out-back curve — past the place by ~10 %, then back. A timer,
    /// not `animator()`: a borderless panel's frame animation has no overshoot,
    /// and the curve is the gesture. Fades in over the first third so a display
    /// below this one never shows it passing.
    private static func rise(_ p: NSPanel, to target: NSPoint) {
        riseTimer?.invalidate()
        guard ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        let bottom = (screen(at: arrivedAt)?.frame.minY ?? 0) - p.frame.height
        let start = Date()
        p.alphaValue = 0
        p.setFrameOrigin(NSPoint(x: target.x, y: bottom))
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            guard panel === p else { timer.invalidate(); return }
            let u = min(1, Date().timeIntervalSince(start) / riseSeconds)
            // easeOutBack, s = 1.4: peaks ≈ 9 % past the target near u = 0.7.
            let s = 1.4, v = u - 1
            let k = 1 + (s + 1) * v * v * v + s * v * v
            p.setFrameOrigin(NSPoint(x: target.x, y: bottom + (target.y - bottom) * CGFloat(k)))
            p.alphaValue = CGFloat(min(1, u * 3))
            if u >= 1 { timer.invalidate(); p.setFrameOrigin(target); p.alphaValue = 1 }
        }
        RunLoop.main.add(t, forMode: .common)
        riseTimer = t
    }
}


@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// **The panel's own surface: an arrow, and a press drags it** (2026-10-08).
/// The arrow because the window server keeps the frontmost app's cursor —
/// Victor saw Chrome's under the panel (*"the mouse has the icon from what's
/// underneath"*); `hot` are the clickable rects, where the hand is theirs.
private final class ReplyRoot: NSView {
    var hot: [NSRect] = []
    private func arrow(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !hot.contains(where: { $0.contains(p) }) { NSCursor.arrow.set() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { arrow(event) }
    override func mouseEntered(with event: NSEvent) { arrow(event) }
    override func mouseMoved(with event: NSEvent) { arrow(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

/// **A press on a clickable that moves is a drag, not a click** (2026-10-08,
/// Victor: *"I should be able to drag not only on the text but anything as long
/// as I don't click it but drag it"*). Past `slop` the panel follows the
/// pointer and the release clicks nothing.
private struct PressOrDrag {
    static let slop: CGFloat = 3
    private var from: NSPoint = .zero
    private var origin: NSPoint = .zero
    private var dragging = false

    mutating func down(_ window: NSWindow?) {
        from = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragging = false
    }

    mutating func dragged(_ window: NSWindow?) {
        let p = NSEvent.mouseLocation
        let dx = p.x - from.x, dy = p.y - from.y
        if !dragging, hypot(dx, dy) < Self.slop { return }
        dragging = true
        window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    /// True when the press was a click.
    mutating func up() -> Bool { defer { dragging = false }; return !dragging }
}

/// The answer's words: never the target of a click, so a press on them is
/// `ReplyRoot`'s drag and no selection starts.
private final class InertLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The ✕ (and, with a `glyph`, the ☠️) — drawn, not an `NSButton`: a button in
/// a non-activating panel looks disabled and eats the first click.
private final class ReplyCloseButton: NSView {
    var onClick: (() -> Void)?
    var glyph: String?
    private var hot = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hot ? 0.25 : 0.1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        if let glyph = glyph {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: bounds.height * 0.55)]
            let size = (glyph as NSString).size(withAttributes: a)
            (glyph as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: a)
            return
        }
        let p = NSBezierPath()
        let r = bounds.insetBy(dx: bounds.width * 0.32, dy: bounds.height * 0.32)
        p.move(to: NSPoint(x: r.minX, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        p.move(to: NSPoint(x: r.minX, y: r.maxY)); p.line(to: NSPoint(x: r.maxX, y: r.minY))
        p.lineWidth = 1.8
        NSColor.white.withAlphaComponent(0.85).setStroke()
        p.stroke()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true; NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true; NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
}

/// The walkie: a button only when the answer names a terminal — the hand on
/// hover, a click brings that terminal forward (`ReplyPanel.onPresent`).
private final class ReplyIcon: NSImageView {
    var onClick: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        guard onClick != nil else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    /// Not a button → part of the surface, so a press there drags.
    override func hitTest(_ point: NSPoint) -> NSView? { onClick == nil ? nil : super.hitTest(point) }
    override func cursorUpdate(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseEntered(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseMoved(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
}

/// The header: plain text, or — when it names a terminal — a link: the hand
/// cursor and an underline while the pointer is on it, a click binds it.
private final class LinkLabel: NSTextField {
    var onClick: (() -> Void)? { didSet { window?.invalidateCursorRects(for: self) } }

    private func underline(_ on: Bool) {
        guard onClick != nil else { return }
        // The paragraph style carries the … : an attributed value without one
        // wraps instead, and the hovered title would lose its ellipsis.
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: stringValue,
                                          attributes: [.font: font as Any, .foregroundColor: textColor as Any,
                                                       .paragraphStyle: para])
        if on { s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                               range: NSRange(location: 0, length: s.length)) }
        attributedStringValue = s
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        guard onClick != nil else { return }
        let fit = NSRect(x: 0, y: 0, width: min(bounds.width, intrinsicContentSize.width), height: bounds.height)
        addTrackingArea(NSTrackingArea(rect: fit, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways],
                                       owner: self))
    }
    // **The hand on enter and on every move, not only `cursorUpdate`** (Victor,
    // 2026-10-08: *"the mouse should turn into a hand once I hover the title"*
    // — the underline came, the hand did not): the panel never becomes key, so
    // the frontmost terminal's I-beam won the cursor back.
    override func hitTest(_ point: NSPoint) -> NSView? { onClick == nil ? nil : super.hitTest(point) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { underline(true); NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { underline(false); NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
}
