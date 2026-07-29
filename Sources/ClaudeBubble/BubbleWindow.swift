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
    private let closeButton = CloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))

    /// Restored when the editor closes, so typing in the bubble doesn't steal
    /// Victor's place in whatever app he was actually working in.
    private var previousApp: NSRunningApplication?

    var onSubmit: ((String) -> Void)?
    var onTogglePause: (() -> Void)?
    var onEndSession: (() -> Void)?

    private(set) var selection: String?
    private var paused = false
    private var editing = false
    private var listening = false
    private var hovering = false
    private var pendingSingleClick: DispatchWorkItem?
    private var followTimer: Timer?
    private var dotTimer: Timer?
    private var shineTimer: Timer?
    private var dotPhase = 0
    private weak var homeScreen: NSScreen?
    private let margin: CGFloat = 24

    /// Mouse 5 is deliberately absent: it is Wispr's own push-to-talk, which
    /// Victor already has in his fingers — the legend is for the bindings this
    /// tool adds.
    private static let hints = "⌃⌥P shot · ⌃⌥S select · 2×click type"

    // MARK: Geometry
    private let collapsedWidth: CGFloat = 266    // 380 × 0.7
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
        startFollowingMouse()
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
        // The shine sweeps as a sublayer of the root layer, so the root needs to
        // be layer-backed and clip to the same rounded rect as the blur.
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true

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

        closeButton.isHidden = true          // revealed on hover, like a notification
        closeButton.onClick = { [weak self] in self?.onEndSession?() }
        root.addSubview(closeButton)

        refreshTitle()
    }

    /// Park the bubble at the top-left of `screen`.
    private func moveToTopLeft(of screen: NSScreen) {
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: area.minX + margin,
            y: area.maxY - panel.frame.height - margin
        ))
        homeScreen = screen
    }

    private func positionInitially() {
        guard let screen = Self.screenUnderMouse() ?? NSScreen.main else { return }
        moveToTopLeft(of: screen)
    }

    /// Follow the cursor across displays: Victor works on whichever screen he is
    /// pointing at, and a bubble stranded on the other monitor is a bubble he
    /// cannot see. Only the *screen* follows — a bubble dragged somewhere on the
    /// current screen stays put until the cursor leaves for another one.
    private func startFollowingMouse() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Never teleport out from under him mid-interaction.
            guard !self.editing, NSEvent.pressedMouseButtons == 0 else { return }
            guard let screen = Self.screenUnderMouse() else { return }
            guard screen !== self.homeScreen else { return }
            self.moveToTopLeft(of: screen)
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
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

        // Anchor the TOP edge: the bubble sits in the top-left corner, so it
        // grows downward into empty screen rather than up under the menu bar.
        let oldTop = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: oldTop - height, width: width, height: height),
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

        // Top-right corner, straddling the edge slightly like a notification's.
        closeButton.frame.origin = NSPoint(x: width - closeButton.frame.width - 6,
                                           y: height - closeButton.frame.height - 6)
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
        applyTitleText()
        titleLabel.textColor = (paused || !listening) ? .secondaryLabelColor : .labelColor
        refreshOpacity()
    }

    /// Just the string — kept separate from `refreshTitle` because the dot
    /// animation ticks several times a second and must not restart the opacity
    /// fade on every frame.
    private func applyTitleText() {
        if paused {
            titleLabel.stringValue = "⏸ Agent paused"
        } else if listening {
            titleLabel.stringValue = "🎙️ Agent listening" + String(repeating: ".", count: dotPhase + 1)
        } else {
            titleLabel.stringValue = "💬 Agent on stand-by"
        }
    }

    /// Cycle the trailing dots 1→2→3→1 while Wispr is listening, so the bubble
    /// visibly *lives* — a frozen "listening" label is indistinguishable from a
    /// hung app, and the whole point is reassurance that speech is being caught.
    private func startDots() {
        stopDots()
        dotPhase = 0
        applyTitleText()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.dotPhase = (self.dotPhase + 1) % 3
            self.applyTitleText()
        }
        RunLoop.main.add(timer, forMode: .common)
        dotTimer = timer
    }

    private func stopDots() {
        dotTimer?.invalidate()
        dotTimer = nil
    }

    // MARK: - Glass shine

    /// Every 5s while listening, a narrow tilted highlight sweeps across the
    /// bubble like glare across glass. Deliberately slow and rare: it is a sign
    /// of life in Victor's peripheral vision while he is talking to a screen,
    /// not something to look at.
    private func startShine() {
        stopShine()
        playShine()
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.playShine()
        }
        RunLoop.main.add(timer, forMode: .common)
        shineTimer = timer
    }

    private func stopShine() {
        shineTimer?.invalidate()
        shineTimer = nil
    }

    private func playShine() {
        guard let host = root.layer else { return }
        let w = root.bounds.width
        let h = root.bounds.height
        guard w > 0, h > 0 else { return }

        let bandWidth: CGFloat = 70
        let band = CAGradientLayer()
        // Taller than the bubble so the tilt never exposes a cut-off corner.
        band.frame = CGRect(x: 0, y: -h, width: bandWidth, height: h * 3)
        band.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.22).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        band.locations = [0, 0.5, 1]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.transform = CATransform3DMakeRotation(.pi / 9, 0, 0, 1)   // ~20° tilt
        // Added last => on top of the blur and the labels.
        host.addSublayer(band)

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bandWidth
        sweep.toValue = w + bandWidth
        sweep.duration = 0.85
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.fillMode = .forwards
        sweep.isRemovedOnCompletion = false
        band.add(sweep, forKey: "sweep")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { band.removeFromSuperlayer() }
    }

    /// Translucent while idle so it sits quietly over Victor's work; fully
    /// opaque the moment Wispr starts listening, because that is when he needs
    /// to be sure it is actually capturing. Paused fades further still.
    private func refreshOpacity() {
        let target: CGFloat
        // Hovering counts as "he is looking at it" — reading the stashed
        // selection or aiming for a double-click both need it legible.
        if paused                                { target = 0.30 }
        else if listening || editing || hovering { target = 1.00 }
        else                                     { target = 0.45 }
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
        if value { startDots(); startShine() } else { stopDots(); stopShine() }
        refreshTitle()
    }

    fileprivate func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        closeButton.isHidden = !value
        refreshOpacity()
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

// MARK: - Close button

/// The round ✕ in the top-right, in the style of a macOS notification: hidden
/// until the pointer is over the bubble, then a grey disc with a dark cross.
/// Ends the whole bubble session.
final class CloseButton: NSView {
    var onClick: (() -> Void)?
    private var hot = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        (hot ? NSColor.systemRed : NSColor.secondaryLabelColor).withAlphaComponent(hot ? 0.95 : 0.75).setFill()
        disc.fill()

        let inset = bounds.width * 0.32
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset, y: inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        cross.move(to: NSPoint(x: inset, y: bounds.height - inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: inset))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.95).setStroke()
        cross.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { hot = false; needsDisplay = true }

    // Swallow the whole click so it never reaches BubbleView's pause/edit handling.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // .activeAlways: the bubble belongs to an accessory app that is almost
        // never frontmost, so .activeInActiveApp would never fire.
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { owner?.setHovering(true) }
    override func mouseExited(with event: NSEvent)  { owner?.setHovering(false) }
}
