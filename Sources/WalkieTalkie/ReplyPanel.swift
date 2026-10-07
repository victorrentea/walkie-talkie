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

    /// What is on screen — `GET /test/state`.
    static var shown: String?

    static func show(_ raw: String, from label: String?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(raw, from: label) }
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
        let header = NSTextField(labelWithString: "💬 " + (label ?? "agent"))
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = NSColor.white.withAlphaComponent(0.55)
        let body = NSTextField(wrappingLabelWithString: text)
        body.font = font
        body.textColor = .white
        body.preferredMaxLayoutWidth = inner - 18
        let bodySize = body.sizeThatFits(NSSize(width: inner - 18, height: .greatestFiniteMagnitude))
        let height = pad + 16 + 4 + ceil(bodySize.height) + pad

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        header.frame = NSRect(x: pad, y: height - pad - 16, width: inner - 24, height: 16)
        body.frame = NSRect(x: pad, y: pad, width: inner - 18, height: ceil(bodySize.height))
        root.addSubview(header)
        root.addSubview(body)
        let x = ReplyCloseButton(frame: NSRect(x: width - 28, y: height - 28, width: 20, height: 20))
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
