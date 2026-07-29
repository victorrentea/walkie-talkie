import AppKit

/// The floating, translucent, always-on-top bubble.
///
/// Interaction model:
///   drag            move it anywhere
///   single click    pause / resume forwarding (an escape hatch — while paused,
///                   dictation keeps working normally in whatever app has focus
///                   but nothing is sent to Claude)
///   double click    expand into a text area; ⏎ sends, ⇧⏎ newline, esc collapses
///
/// It renders the stashed screen selection on one truncated line at half the
/// screen width, so Victor can see exactly what will be prefixed to his next
/// dictation before he starts talking.
final class BubbleWindow: NSObject, NSWindowDelegate {

    private let panel: BubblePanel
    private let root: BubbleView
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    /// Restored when the editor closes, so typing in the bubble doesn't steal
    /// Victor's place in whatever app he was actually working in.
    private var previousApp: NSRunningApplication?

    var onSubmit: ((String) -> Void)?
    var onTogglePause: (() -> Void)?

    private(set) var selection: String?
    private var paused = false
    private var editing = false
    private var listening = false
    private var pendingSingleClick: DispatchWorkItem?

    /// Mouse 5 is deliberately absent: it is Wispr's own push-to-talk, which
    /// Victor already has in his fingers — the legend is for the bindings this
    /// tool adds.
    private static let hints = "⌃⌥P shot · ⌃⌥S select · 2×click type"

    // MARK: Geometry
    private let collapsedWidth: CGFloat = 380
    private let pad: CGFloat = 12
    private let rowGap: CGFloat = 6
    private let minEditorHeight: CGFloat = 24
    private let maxEditorHeight: CGFloat = 168     // ~8 lines before it scrolls

    private var screenWidth: CGFloat {
        (panel.screen ?? NSScreen.main)?.frame.width.rounded() ?? 1440
    }

    override init() {
        panel = BubblePanel(
            contentRect: NSRect(x: 0, y: 0, width: collapsedWidth, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        root = BubbleView(frame: panel.contentLayoutRect)
        super.init()

        configurePanel()
        configureViews()
        layoutContent()
        positionInitially()
        panel.orderFrontRegardless()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false      // we drag manually
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Second line of defence for screenshots; the panel is also hidden
        // outright while `screencapture` runs.
        panel.sharingType = .none
        panel.delegate = self
        panel.contentView = root
        root.owner = self
    }

    private func configureViews() {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        root.addSubview(blur)
        root.blur = blur

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        root.addSubview(titleLabel)

        hintLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = Self.hints
        root.addSubview(hintLabel)

        selectionLabel.font = .systemFont(ofSize: 11)
        selectionLabel.textColor = .secondaryLabelColor
        selectionLabel.lineBreakMode = .byTruncatingTail
        selectionLabel.maximumNumberOfLines = 1
        selectionLabel.cell?.truncatesLastVisibleLine = true
        selectionLabel.isHidden = true
        root.addSubview(selectionLabel)

        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.isHidden = true
        root.addSubview(scrollView)

        refreshTitle()
    }

    private func positionInitially() {
        guard let screen = NSScreen.main else { return }
        // Bottom-left: the quietest corner of Victor's screen, and where the
        // Addons banners already live, so his eye knows to look there.
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.minX + 24,
            y: screen.visibleFrame.minY + 24
        ))
    }

    // MARK: - Layout

    /// Manual layout in one pass: build the visible rows top-down with their
    /// heights, size the window to their total, then place them. Keeping the
    /// height sum and the placement loop driven by the *same* list is what stops
    /// the two drifting apart as rows appear and disappear.
    private func layoutContent() {
        // Only a selection widens the bubble to half the screen — that preview
        // needs the room. Typing does not: a half-screen box for a one-line
        // message is mostly empty space, so the editor keeps the narrow width
        // and grows downward instead.
        let width = selection != nil ? max(collapsedWidth, screenWidth / 2) : collapsedWidth
        let innerWidth = width - pad * 2

        // Top-down order: title, selection preview, editor, hints.
        var rows: [(view: NSView, height: CGFloat)] = []

        titleLabel.frame.size = NSSize(width: innerWidth, height: 16)
        rows.append((titleLabel, 16))

        if let selection = selection {
            selectionLabel.stringValue = "↪ " + singleLine(selection)
            selectionLabel.frame.size = NSSize(width: innerWidth, height: 15)
            selectionLabel.isHidden = false
            rows.append((selectionLabel, 15))
        } else {
            selectionLabel.isHidden = true
        }

        if editing {
            let editorHeight = min(max(measuredTextHeight(width: innerWidth), minEditorHeight), maxEditorHeight)
            scrollView.frame.size = NSSize(width: innerWidth, height: editorHeight)
            scrollView.isHidden = false
            rows.append((scrollView, editorHeight))
        } else {
            scrollView.isHidden = true
        }

        hintLabel.frame.size = NSSize(width: innerWidth, height: 13)
        rows.append((hintLabel, 13))

        let contentHeight = rows.reduce(0) { $0 + $1.height }
        let height = contentHeight + rowGap * CGFloat(rows.count - 1) + pad * 2

        // Anchor the BOTTOM edge: the bubble lives in the bottom-left corner, so
        // it has to grow upward — growing downward would walk it off-screen.
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.minY, width: width, height: height),
                       display: true)
        root.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        root.blur?.frame = root.bounds

        // Place top-down (Cocoa's origin is bottom-left, so walk y downward).
        var y = height - pad
        for row in rows {
            y -= row.height
            row.view.frame.origin = NSPoint(x: pad, y: y)
            y -= rowGap
        }
        root.needsDisplay = true
    }

    private func measuredTextHeight(width: CGFloat) -> CGFloat {
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return minEditorHeight }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height + 6
    }

    private func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func refreshTitle() {
        if paused {
            titleLabel.stringValue = "⏸ Claude Bubble — paused"
        } else if listening {
            titleLabel.stringValue = "🎙️ Wispr dictează… ascult"
        } else {
            titleLabel.stringValue = "💬 Claude Bubble"
        }
        titleLabel.textColor = (paused || !listening) ? .secondaryLabelColor : .labelColor
        refreshOpacity()
    }

    /// Translucent while idle so it sits quietly over Victor's work; fully
    /// opaque the moment Wispr starts listening, because that is when he needs
    /// to be sure it is actually capturing. Paused fades further still.
    private func refreshOpacity() {
        let target: CGFloat
        if paused          { target = 0.30 }
        else if listening || editing { target = 1.00 }
        else               { target = 0.45 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = target
        }
    }

    // MARK: - Public API (main thread)

    func setSelection(_ text: String?) {
        selection = (text?.isEmpty == false) ? text : nil
        layoutContent()
    }

    func clearSelection() { setSelection(nil) }

    func setPaused(_ value: Bool) {
        paused = value
        refreshTitle()
    }

    /// Wispr started / stopped listening.
    func setListening(_ value: Bool) {
        guard listening != value else { return }
        listening = value
        refreshTitle()
    }

    /// Flash a transient status in place of the hint line.
    func flash(_ message: String, duration: TimeInterval = 2.0) {
        let restore = Self.hints
        hintLabel.stringValue = message
        hintLabel.textColor = .labelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.hintLabel.stringValue == message else { return }
            self.hintLabel.stringValue = restore
            self.hintLabel.textColor = .secondaryLabelColor
        }
    }

    func hideForCapture() { panel.orderOut(nil) }
    func showAfterCapture() { panel.orderFrontRegardless() }

    // MARK: - Editing

    func beginEditing() {
        guard !editing else { return }
        editing = true
        previousApp = NSWorkspace.shared.frontmostApplication
        textView.string = ""
        layoutContent()
        refreshOpacity()
        // An accessory app must activate to receive keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    func endEditing(submit: Bool) {
        guard editing else { return }
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        textView.string = ""
        panel.resignKey()
        layoutContent()
        refreshOpacity()
        // Hand focus back to whatever Victor was actually working in.
        previousApp?.activate()
        previousApp = nil
        if submit, !text.isEmpty { onSubmit?(text) }
    }

    // MARK: - Hit handling (called from BubbleView)

    /// macOS delivers a `clickCount == 1` mouseUp *before* the `== 2` one, so
    /// acting on a single click immediately would toggle pause on the way into
    /// every double-click — and then silently drop whatever was typed. The
    /// single-click action is therefore deferred by one double-click interval
    /// and cancelled if the second click arrives.
    fileprivate func handleClick(count: Int) {
        if count >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            beginEditing()
            return
        }
        guard !editing else { return }
        pendingSingleClick?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSingleClick = nil
            self?.onTogglePause?()
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    fileprivate func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }
}

// MARK: - NSTextViewDelegate

extension BubbleWindow: NSTextViewDelegate {
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            endEditing(submit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endEditing(submit: false)
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        layoutContent()   // the box grows with what's written in it
    }
}

// MARK: - Panel

/// Borderless panels refuse key status by default, which would make the text
/// area untypeable.
final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Content view (drag + click)

final class BubbleView: NSView {
    weak var owner: BubbleWindow?
    var blur: NSVisualEffectView?

    private var dragOrigin: NSPoint?
    private var dragged = false

    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x
        let dy = now.y - start.y
        if abs(dx) > 1 || abs(dy) > 1 { dragged = true }
        owner?.moveBy(dx: dx, dy: dy)
        dragOrigin = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        guard !dragged else { return }     // a drag is not a click
        owner?.handleClick(count: event.clickCount)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
