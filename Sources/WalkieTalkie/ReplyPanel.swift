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
/// was looking at the terminal is one he never got. A newer answer replaces it.
///
/// It sits where the pointer was when the answer arrived and does not follow —
/// it is read, and clicked once. `sharingType = .none`: the next dictation's
/// pictures are of his screen, not of this.
enum ReplyPanel {
    private static var panel: NSPanel?
    private static var arrivedAt: NSPoint = .zero

    static let maxChars = 400
    private static let width: CGFloat = 380
    private static let font = NSFont.systemFont(ofSize: 15)
    private static let headerH: CGFloat = 20

    private static let walkie: NSImage? = RelayWindow.walkieURL("walkie-bound").flatMap { NSImage(contentsOf: $0) }

    /// What is on screen — `GET /test/state`.
    static var shown: String?

    /// **A click on the terminal's name binds it** (Victor: *"if I click on it,
    /// I will rebind my Walkie to that terminal … underlined if I hover it, in
    /// the hand of the mouse"*) — `AppDelegate.rebindFromMenu`.
    static var onBind: ((String) -> Void)?

    static func show(_ raw: String, from label: String?, tty: String? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(raw, from: label, tty: tty) }
            return
        }
        close()
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        guard !text.isEmpty else { return }
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
        let body = NSTextField(wrappingLabelWithString: text)
        body.font = font
        body.textColor = .white
        body.preferredMaxLayoutWidth = inner - 18
        let bodySize = body.sizeThatFits(NSSize(width: inner - 18, height: .greatestFiniteMagnitude))
        let height = pad + headerH + 6 + ceil(bodySize.height) + pad

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        let icon = NSImageView(frame: NSRect(x: pad, y: height - pad - headerH + 1, width: 18, height: 18))
        icon.image = Self.walkie
        icon.imageScaling = .scaleProportionallyUpOrDown
        root.addSubview(icon)
        header.frame = NSRect(x: pad + 24, y: height - pad - headerH, width: inner - 24 - 24, height: headerH)
        body.frame = NSRect(x: pad, y: pad, width: inner - 18, height: ceil(bodySize.height))
        root.addSubview(header)
        root.addSubview(body)
        let x = ReplyCloseButton(frame: NSRect(x: width - 28, y: height - pad - headerH, width: 20, height: 20))
        x.onClick = { Log.info("💬 answer dismissed (✕)"); close() }
        root.addSubview(x)

        let p = NSPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = .none
        p.hidesOnDeactivate = false
        p.contentView = root
        p.setFrameOrigin(origin(for: root.frame.size, at: arrivedAt))
        p.orderFrontRegardless()
        panel = p
        Log.info("💬 answer from \(label ?? "agent") — \(text.count) chars; up until the ✕")
    }

    static func close() {
        panel?.orderOut(nil)
        panel = nil
        shown = nil
    }


    /// Below-right of the pointer, flipped and clamped into its screen.
    private static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var x = point.x + 16
        if x + size.width > visible.maxX { x = point.x - 16 - size.width }
        var y = point.y - 16 - size.height
        if y < visible.minY { y = point.y + 16 }
        x = max(visible.minX, min(x, visible.maxX - size.width))
        y = max(visible.minY, min(y, visible.maxY - size.height))
        return NSPoint(x: x, y: y)
    }
}


/// The ✕ — drawn, not an `NSButton`: a button in a non-activating panel looks
/// disabled and eats the first click.
private final class ReplyCloseButton: NSView {
    var onClick: (() -> Void)?
    private var hot = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hot ? 0.25 : 0.1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        let p = NSBezierPath()
        let r = bounds.insetBy(dx: 6.5, dy: 6.5)
        p.move(to: NSPoint(x: r.minX, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        p.move(to: NSPoint(x: r.minX, y: r.maxY)); p.line(to: NSPoint(x: r.maxX, y: r.minY))
        p.lineWidth = 1.6
        NSColor.white.withAlphaComponent(0.85).setStroke()
        p.stroke()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
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
        addTrackingArea(NSTrackingArea(rect: fit, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { underline(true) }
    override func mouseExited(with event: NSEvent) { underline(false); NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
}
