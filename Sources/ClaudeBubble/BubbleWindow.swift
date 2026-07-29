import AppKit

/// The floating, translucent, always-on-top bubble.
///
/// It is a **dictation helper only** — there is no text entry and no selection
/// shortcut. Everything it reports happens by itself: Wispr starts listening,
/// the selection and the screen are captured, the transcript is relayed.
///
/// Interaction is therefore minimal:
///   drag           move it
///   single click   pause / resume forwarding
///   hover          reveal the ✕ (ends the session) and go opaque
///
/// Because it never takes keyboard focus, `canBecomeKey` stays false: the bubble
/// must never steal the caret from whatever Victor is actually working in.
final class BubbleWindow: NSObject, NSWindowDelegate {

    private let panel: BubblePanel
    private let root: BubbleView
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let closeButton = CloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))

    var onTogglePause: (() -> Void)?
    var onEndSession: (() -> Void)?

    private(set) var selection: String?
    private var paused = false
    private var listening = false
    private var hovering = false

    private var followTimer: Timer?
    private var dotTimer: Timer?
    private var shineTimer: Timer?
    private var dotPhase = 0
    /// Temporary title override (e.g. "Plus One Shot"); nil = show the state title.
    private var titleOverride: String?
    private weak var homeScreen: NSScreen?

    // MARK: Geometry
    private let pad: CGFloat = 12
    private let rowGap: CGFloat = 6
    private let margin: CGFloat = 24
    /// Space kept clear on the title row for the hover-revealed ✕.
    private let closeReserve: CGFloat = 26

    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let hintFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)   // 10 × 1.3

    /// Every label the title can show. Width is taken from the widest so the
    /// bubble keeps a stable size across state changes.
    private static let titleCandidates = [
        "💬 Agent on stand-by",
        "🎙️ Agent listening...",
        "⏸ Agent paused",
    ]

    private func measure(_ s: String, font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// Mouse 5 and ⌃⌥S are gone from the legend — the first is Wispr's own
    /// push-to-talk, the second no longer exists.
    private static let hints = "⌃⌥P  📸"

    private var screenWidth: CGFloat {
        (panel.screen ?? NSScreen.main)?.frame.width.rounded() ?? 1440
    }

    override init() {
        panel = BubblePanel(
            // Placeholder — `layoutContent()` sizes the panel to its content
            // before it is ever shown.
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 64),
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
        // Keeps the bubble out of every screenshot — verified: a capture taken by
        // a separate process, with no hiding at all, does not contain it.
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

        titleLabel.font = titleFont
        titleLabel.textColor = .labelColor
        root.addSubview(titleLabel)

        hintLabel.font = hintFont
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

        closeButton.isHidden = true          // revealed on hover, like a notification
        closeButton.onClick = { [weak self] in self?.onEndSession?() }
        root.addSubview(closeButton)

        refreshTitle()
    }

    // MARK: - Placement

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
            guard let self = self, NSEvent.pressedMouseButtons == 0 else { return }
            guard let screen = Self.screenUnderMouse(), screen !== self.homeScreen else { return }
            self.moveToTopLeft(of: screen)
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Layout

    /// Manual layout in one pass: build the visible rows top-down with their
    /// heights, size the window to their total, then place them.
    private func layoutContent() {
        // Hug the content. The title is measured against every state label, not
        // just the current one, so the bubble does not twitch wider and narrower
        // as the listening dots animate or the state changes.
        let titleWidth = Self.titleCandidates
            .map { measure($0, font: titleFont) }
            .max() ?? 0
        let hintWidth = measure(hintLabel.stringValue, font: hintFont)
        let natural = ceil(max(titleWidth + closeReserve, hintWidth)) + pad * 2

        // Only a selection widens it to half the screen — that preview needs the
        // room. Flashes may push it out temporarily, but never past half.
        let width = selection != nil
            ? max(natural, screenWidth / 2)
            : min(natural, screenWidth / 2)
        let innerWidth = width - pad * 2

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

        hintLabel.frame.size = NSSize(width: innerWidth, height: 17)
        rows.append((hintLabel, 17))

        let contentHeight = rows.reduce(0) { $0 + $1.height }
        let height = contentHeight + rowGap * CGFloat(rows.count - 1) + pad * 2

        // Anchor the TOP edge: the bubble sits in the top-left corner, so it
        // grows downward into empty screen rather than up under the menu bar.
        let oldTop = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: oldTop - height, width: width, height: height),
                       display: true)
        root.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        root.blur?.frame = root.bounds

        var y = height - pad
        for row in rows {
            y -= row.height
            row.view.frame.origin = NSPoint(x: pad, y: y)
            y -= rowGap
        }

        closeButton.frame.origin = NSPoint(x: width - closeButton.frame.width - 6,
                                           y: height - closeButton.frame.height - 6)
        root.needsDisplay = true
    }

    private func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Title / opacity

    private func refreshTitle() {
        applyTitleText()
        titleLabel.textColor = (paused || !listening) ? .secondaryLabelColor : .labelColor
        refreshOpacity()
    }

    /// Just the string — kept separate from `refreshTitle` because the dot
    /// animation ticks several times a second and must not restart the opacity
    /// fade on every frame.
    private func applyTitleText() {
        if let override = titleOverride {
            titleLabel.stringValue = override
        } else if paused {
            titleLabel.stringValue = "⏸ Agent paused"
        } else if listening {
            titleLabel.stringValue = "🎙️ Agent listening" + String(repeating: ".", count: dotPhase + 1)
        } else {
            titleLabel.stringValue = "💬 Agent on stand-by"
        }
    }

    /// Show `text` as the title for a moment, then fall back to the state title.
    func flashTitle(_ text: String, duration: TimeInterval = 1.6) {
        titleOverride = text
        applyTitleText()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.titleOverride == text else { return }
            self.titleOverride = nil
            self.applyTitleText()
        }
    }

    /// Translucent while idle so it sits quietly over Victor's work; fully
    /// opaque the moment Wispr starts listening or he looks straight at it.
    private func refreshOpacity() {
        let target: CGFloat
        if paused                    { target = 0.30 }
        else if listening || hovering { target = 1.00 }
        else                         { target = 0.45 }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = target
        }
    }

    // MARK: - Animations

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

    private func stopDots() { dotTimer?.invalidate(); dotTimer = nil }

    /// Every 5s while listening, a narrow tilted highlight sweeps across the
    /// bubble like glare across glass. Deliberately slow and rare: a sign of
    /// life in peripheral vision, not something to look at.
    private func startShine() {
        stopShine()
        playShine()
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.playShine()
        }
        RunLoop.main.add(timer, forMode: .common)
        shineTimer = timer
    }

    private func stopShine() { shineTimer?.invalidate(); shineTimer = nil }

    private func playShine() {
        guard let host = root.layer else { return }
        let w = root.bounds.width, h = root.bounds.height
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

    /// Transient status in place of the hint line.
    func flash(_ message: String, duration: TimeInterval = 2.0) {
        hintLabel.stringValue = message
        hintLabel.textColor = .labelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.hintLabel.stringValue == message else { return }
            self.hintLabel.stringValue = Self.hints
            self.hintLabel.textColor = .secondaryLabelColor
        }
    }

    fileprivate func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        closeButton.isHidden = !value
        if value {
            // A hidden view gets no mouse events, so its tracking area is stale
            // by the time it is revealed — without this the ✕ never lights up.
            closeButton.updateTrackingAreas()
            closeButton.needsDisplay = true
        }
        refreshOpacity()
    }

    // MARK: - Hit handling (called from BubbleView)

    /// No double-click to disambiguate any more, so a click acts immediately.
    fileprivate func handleClick() {
        onTogglePause?()
    }

    fileprivate func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }
}

// MARK: - Panel

final class BubblePanel: NSPanel {
    // The bubble has no text entry, so it must never take the caret away from
    // the app Victor is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Close button

/// The round ✕ in the top-right, in the style of a macOS notification: hidden
/// until the pointer is over the bubble, then a grey disc with a dark cross.
final class CloseButton: NSView {
    var onClick: (() -> Void)?
    private var hot = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Dynamic system colours, resolved against `effectiveAppearance` at draw
        // time, so the button reads correctly in both light and dark mode:
        //   disc  = secondaryLabelColor — dark grey on light, light grey on dark
        //   cross = textBackgroundColor — the inverse of that in both modes
        // A hardcoded white cross looked fine on light mode's dark disc and
        // vanished against dark mode's light one.
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        if hot {
            NSColor.systemRed.withAlphaComponent(0.90).setFill()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()
        }
        disc.fill()

        let inset = bounds.width * 0.32
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset, y: inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        cross.move(to: NSPoint(x: inset, y: bounds.height - inset))
        cross.line(to: NSPoint(x: bounds.width - inset, y: inset))
        cross.lineWidth = 1.6
        cross.lineCapStyle = .round
        // On the red hover disc, white always wins in either appearance.
        (hot ? NSColor.white : NSColor.textBackgroundColor).withAlphaComponent(0.95).setStroke()
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

    // Swallow the whole click so it never reaches BubbleView's pause handling.
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
        let dx = now.x - start.x, dy = now.y - start.y
        if abs(dx) > 1 || abs(dy) > 1 { dragged = true }
        owner?.moveBy(dx: dx, dy: dy)
        dragOrigin = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        guard !dragged else { return }     // a drag is not a click
        owner?.handleClick()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // .activeAlways: the bubble belongs to an accessory app that is never
        // frontmost, so .activeInActiveApp would never fire.
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { owner?.setHovering(true) }
    override func mouseExited(with event: NSEvent)  { owner?.setHovering(false) }
}
