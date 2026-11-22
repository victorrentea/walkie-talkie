import AppKit

/// **The "Custom gestures" window** (2026-11-22) — one row per Logi gesture,
/// each with a recorder for the trigger that stands in for it (`CustomGestures`).
/// Opened by ticking *Gestures ▸ Custom*. Written for somebody who has an
/// ordinary three-button mouse and has never seen Options+.
///
/// An ordinary titled window that may take the keyboard — it is not the overlay
/// — but, like every window here, it comes forward without `NSApp.activate`:
/// a `.nonactivatingPanel` that can become key (`RebindPanel`'s way).
enum CustomGesturesWindow {
    private static var panel: NSPanel?
    private static var content: CustomGesturesView?
    private static let closer = Closer()

    static var isVisible: Bool { panel?.isVisible == true }

    static func show(store: CustomGestures = .shared) {
        if let p = panel, let v = content {
            v.refresh()
            p.orderFrontRegardless()
            p.makeKey()
            return
        }
        let v = CustomGesturesView(store: store)
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: v.frame.size),
                         styleMask: [.titled, .closable, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.title = "Custom gestures"
        p.isFloatingPanel = false
        p.level = .normal
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = closer
        p.contentView = v
        panel = p
        content = v
        p.center()
        p.orderFrontRegardless()
        p.makeKey()
        Log.info("🎛️ custom gestures window \(Int(p.frame.width))×\(Int(p.frame.height))")
    }

    static func close() {
        content?.stopRecording()
        panel?.orderOut(nil)
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { CustomGesturesWindow.content?.stopRecording() }
        func windowDidResignKey(_ notification: Notification) { CustomGesturesWindow.content?.stopRecording() }
    }
}

/// The window's whole content, laid out by hand so a test can render it.
final class CustomGesturesView: NSView {
    static let width: CGFloat = 660
    private static let margin: CGFloat = 20
    private static let rowHeight: CGFloat = 46
    private static let recorderWidth: CGFloat = 200

    static let intro = "For a mouse without Logi Options+. On a Logitech mouse, Options+ turns the two side buttons "
        + "into the gestures below. Here each one gets a trigger of your own: a mouse button — left, right or the "
        + "wheel pressed — with ⌘ ⌥ ⌃ ⇧ held, or a key combination."
    static let howTo = "Click a field, then make the trigger with the pointer over this window. Esc cancels, ✕ clears."

    private let store: CustomGestures
    private var recorders: [CustomGestureAction: RecorderField] = [:]
    private var clears: [CustomGestureAction: NSButton] = [:]
    private let status = NSTextField(labelWithString: "")
    private(set) var recordingAction: CustomGestureAction?
    private var monitor: Any?

    override var isFlipped: Bool { true }

    init(store: CustomGestures) {
        self.store = store
        super.init(frame: .zero)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor, wraps: Bool = false) -> NSTextField {
        let l = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.isSelectable = false
        if !wraps { l.lineBreakMode = .byTruncatingTail }
        return l
    }

    private func build() {
        let m = Self.margin, inner = Self.width - 2 * m
        var y = m

        for (text, color) in [(Self.intro, NSColor.labelColor), (Self.howTo, NSColor.secondaryLabelColor)] {
            let l = label(text, size: 12.5, color: color, wraps: true)
            let h = l.sizeThatFits(NSSize(width: inner, height: 1000)).height
            l.frame = NSRect(x: m, y: y, width: inner, height: h)
            addSubview(l)
            y += h + 8
        }
        y += 6

        let textWidth = inner - Self.recorderWidth - 26 - 16
        for (i, action) in CustomGestureAction.allCases.enumerated() {
            if action == .forwardClick || action == .backClick {
                let head = label(action == .forwardClick ? "FORWARD SIDE BUTTON, ON A LOGITECH MOUSE" : "BACK SIDE BUTTON",
                                 size: 10.5, weight: .semibold, color: .tertiaryLabelColor)
                head.frame = NSRect(x: m, y: y + (i == 0 ? 0 : 8), width: inner, height: 14)
                addSubview(head)
                y += (i == 0 ? 0 : 8) + 20
            }
            let line = NSBox(frame: NSRect(x: m, y: y, width: inner, height: 1))
            line.boxType = .separator
            addSubview(line)

            let title = NSTextField(labelWithAttributedString: {
                let s = NSMutableAttributedString(string: action.title, attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor])
                s.append(NSAttributedString(string: "   \(action.logi)", attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]))
                return s
            }())
            title.lineBreakMode = .byTruncatingTail
            title.frame = NSRect(x: m, y: y + 7, width: textWidth, height: 17)
            addSubview(title)

            let detail = label(action.detail, size: 11, color: .secondaryLabelColor)
            detail.frame = NSRect(x: m, y: y + 25, width: textWidth, height: 15)
            addSubview(detail)

            let field = RecorderField(frame: NSRect(x: Self.width - m - 26 - Self.recorderWidth, y: y + 10,
                                                    width: Self.recorderWidth, height: 26))
            field.onClick = { [weak self] in self?.toggleRecording(action) }
            field.setAccessibilityLabel("Trigger for \(action.title)")
            addSubview(field)
            recorders[action] = field

            let clear = NSButton(title: "✕", target: self, action: #selector(clearClicked(_:)))
            clear.isBordered = false
            clear.font = .systemFont(ofSize: 12)
            clear.contentTintColor = .secondaryLabelColor
            clear.tag = i
            clear.toolTip = "Clear"
            clear.frame = NSRect(x: Self.width - m - 22, y: y + 11, width: 22, height: 24)
            addSubview(clear)
            clears[action] = clear

            y += Self.rowHeight
        }

        y += 6
        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        status.frame = NSRect(x: m, y: y, width: inner, height: 16)
        addSubview(status)
        y += 16 + m
        frame = NSRect(x: 0, y: 0, width: Self.width, height: y)
    }

    /// Every row from the store; the footer says whether the set is live.
    func refresh() {
        let bound = store.bindings
        for action in CustomGestureAction.allCases {
            let trigger = bound[action]
            recorders[action]?.show(trigger?.display, recording: recordingAction == action)
            clears[action]?.isHidden = trigger == nil
        }
        if recordingAction == nil { say(nil) }
    }

    /// A refusal in red, or the standing line.
    private func say(_ refusal: String?) {
        if let refusal {
            status.stringValue = refusal
            status.textColor = .systemRed
        } else {
            status.stringValue = store.enabled
                ? "On — these work in every app, beside the Logi gestures."
                : "Off — tick Gestures ▸ Custom in the menu to use them. Your triggers are kept."
            status.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Recording

    private func toggleRecording(_ action: CustomGestureAction) {
        if recordingAction == action { stopRecording(); return }
        stopRecording()
        recordingAction = action
        store.recording = true
        window?.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.recorded(event) ? nil : event
        }
        refresh()
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recordingAction != nil else { return }
        recordingAction = nil
        store.recording = false
        refresh()
    }

    /// One event while a field listens. True = it was the recorder's.
    private func recorded(_ event: NSEvent) -> Bool {
        guard let action = recordingAction, event.window === window else { return false }
        guard let trigger = CustomTrigger(recording: event) else { return false }
        // Esc, bare: never mind.
        if trigger == CustomTrigger(.key(0x35), []) { stopRecording(); return true }
        // A plain left click is the window's own: on this field it ends the
        // recording, anywhere else it does what a click does there.
        if trigger == CustomTrigger(.mouse(0), []) {
            let onOwnField = recorders[action].map { $0.frame.contains(convert(event.locationInWindow, from: nil)) } ?? false
            stopRecording()
            return onOwnField
        }
        if let no = offer(trigger, for: action) {
            say(no.message)
            return true
        }
        return true
    }

    /// What the recorder does with a trigger: bound and done, or refused with
    /// the field still listening. Internal for the tests.
    @discardableResult
    func offer(_ trigger: CustomTrigger, for action: CustomGestureAction) -> CustomTriggerRefusal? {
        if let no = store.set(trigger, for: action) { return no }
        Log.info("🎛️ custom gesture: \(action.glyph) = \(trigger.display)")
        stopRecording()
        refresh()
        return nil
    }

    @objc private func clearClicked(_ sender: NSButton) {
        let action = CustomGestureAction.allCases[sender.tag]
        stopRecording()
        store.set(nil, for: action)
        Log.info("🎛️ custom gesture: \(action.glyph) cleared")
        refresh()
    }
}

/// The recorder: a field that shows the trigger, or that it is listening.
final class RecorderField: NSView {
    var onClick: (() -> Void)?
    private var text: String?
    private var recording = false

    override var isFlipped: Bool { true }

    func show(_ text: String?, recording: Bool) {
        self.text = text
        self.recording = recording
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // With modifiers it is a trigger being made over another row's field.
        guard CustomTrigger.Modifiers(event.modifierFlags).isEmpty else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
        box.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        box.lineWidth = recording ? 2 : 1
        box.stroke()

        let (words, color, weight): (String, NSColor, NSFont.Weight) =
            recording ? ("Make the trigger…", .controlAccentColor, .regular)
            : text.map { ($0, .labelColor, .medium) } ?? ("Click to record", .tertiaryLabelColor, .regular)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let s = NSAttributedString(string: words, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: weight), .foregroundColor: color, .paragraphStyle: style])
        let h = s.size().height
        s.draw(in: NSRect(x: 6, y: (bounds.height - h) / 2, width: bounds.width - 12, height: h))
    }
}
