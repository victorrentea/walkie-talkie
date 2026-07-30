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
    private let promptLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = CloseButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    private let cancelButton = PillButton(frame: NSRect(x: 0, y: 0, width: 96, height: 22))

    var onTogglePause: (() -> Void)?
    var onEndSession: (() -> Void)?
    /// How a displayed prompt ended: `true` — release it to the agent (the hold
    /// ran out, or he clicked the bubble away), `false` — he pressed Cancel and
    /// it must never be written. Fires exactly once per prompt.
    var onPromptResolved: ((Bool) -> Void)?

    private(set) var selection: String?
    private var paused = false
    private var listening = false
    private var hovering = false

    private var followTimer: Timer?
    private var labelTimer: Timer?
    private var dotTimer: Timer?
    private var shineTimer: Timer?
    private var dotPhase = 0
    /// The prompt about to be relayed to the agent, shown whole while it is held
    /// back — the seconds during which Cancel can still stop it.
    private var sentPrompt: String?
    private var promptTimer: Timer?
    /// When the held prompt is due to be released. Drives the Cancel countdown,
    /// so the button says how long Victor still has rather than making him guess.
    private var promptDeadline: Date?
    private var countdownTimer: Timer?
    /// Temporary title override (e.g. "+1 📸"); nil = show the state title.
    private var titleOverride: String?
    /// Transient status occupying the subtitle row; nil = no flash in progress.
    private var flashMessage: String?
    private weak var homeScreen: NSScreen?

    // MARK: Geometry
    private let pad: CGFloat = 12
    private let rowGap: CGFloat = 6
    private let margin: CGFloat = 24
    /// Space kept clear on the title row for the hover-revealed ✕.
    private let closeReserve: CGFloat = 26

    private let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let promptFont = NSFont.systemFont(ofSize: 12)
    private let hintFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)   // 10 × 1.3

    private func measure(_ s: String, font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// Height of `s` wrapped into `width`.
    private func measureWrapped(_ s: String, font: NSFont, width: CGFloat) -> CGFloat {
        let rect = (s as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(rect.height) + 2
    }

    /// Mouse 5 and ⌃⌥S are gone from the legend — the first is Wispr's own
    /// push-to-talk, the second no longer exists.
    private static let hints = "⌃⌥P 📸"

    /// The subtitle row. A flash outranks everything; otherwise the ⌃⌥P legend
    /// shows **only while dictating**, which is the only moment the shortcut can
    /// do anything. At rest the bubble is nothing but its title.
    ///
    /// Flashes must survive the idle case: the Accessibility warning fires at
    /// launch, long before any dictation, and would be invisible if this row
    /// only ever appeared while listening.
    /// Paused is excluded on purpose: Wispr keeps reporting that it is listening
    /// while forwarding is off, but ⌃⌥P is refused in that state, so advertising
    /// it would be a lie.
    private var hintText: String? {
        flashMessage ?? (listening && !paused ? Self.hints : nil)
    }

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
        startWatchingTyping()
        startWatchingBranch()
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
        hintLabel.isHidden = true            // summoned by layoutContent when there is something to say
        root.addSubview(hintLabel)

        selectionLabel.font = .systemFont(ofSize: 11)
        selectionLabel.textColor = .secondaryLabelColor
        selectionLabel.lineBreakMode = .byTruncatingTail
        selectionLabel.maximumNumberOfLines = 1
        selectionLabel.cell?.truncatesLastVisibleLine = true
        selectionLabel.isHidden = true
        root.addSubview(selectionLabel)

        promptLabel.font = promptFont
        promptLabel.textColor = .labelColor
        promptLabel.isHidden = true
        promptLabel.maximumNumberOfLines = 0        // wrap freely; the height follows
        root.addSubview(promptLabel)

        closeButton.isHidden = true          // revealed on hover, like a notification
        closeButton.onClick = { [weak self] in self?.onEndSession?() }
        root.addSubview(closeButton)

        // Not hover-revealed like the ✕: this one is on a clock, so it has to be
        // visible and clickable the instant the prompt appears.
        cancelButton.isHidden = true
        cancelButton.onClick = { [weak self] in self?.resolvePrompt(send: false) }
        root.addSubview(cancelButton)

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

    private func positionInitially() { reposition() }

    /// At rest the bubble is an **anchor**, not a panel: nothing is happening, so
    /// the only thing worth saying is *which agent this is* — 🤖 folder@branch —
    /// and the only place worth saying it is wherever Victor is already looking,
    /// which is wherever his cursor is. Parked in a corner it was either unseen
    /// or pointless; here it is a label on the work in front of him.
    ///
    /// The moment anything happens — dictation, a prompt, a warning — it stops
    /// trailing him and becomes the panel it is today, back in its corner.
    ///
    /// Paused is deliberately **not** anchored. It is the one state he enters by
    /// hand, and the state he leaves by hand — so it becomes a panel again,
    /// parked in its corner with its ✕ back. That is also the route to ending a
    /// session at rest, now that the chip has no ✕ of its own: click it to pause,
    /// then hover the panel and close it.
    private var anchored: Bool { !listening && !paused && sentPrompt == nil && flashMessage == nil }

    /// Where the chip rides relative to the pointer: below and to the right, out
    /// of the way of the thing being pointed at.
    private let anchorGap = NSSize(width: 10, height: 22)

    /// Tracking has two states, and the second one is what keeps the ✕ reachable.
    ///
    /// **Engaged** — the cursor is moving, so the chip is pinned to it every
    /// frame. Anything less (a leash, a "catch up when far enough" rule) reads as
    /// lag, because it *is* lag: the chip visibly trails behind the pointer.
    ///
    /// **Settled** — the cursor has stopped, so the chip stops with it and stays
    /// put until he goes somewhere (`wakeDistance`). That is the window in which
    /// he can walk the pointer over to it and click: a chip that re-engages on
    /// the first pixel of movement can never be caught, and with the ✕ living on
    /// it that would mean no way to end a session at rest.
    private var engaged = false
    /// He is typing, so macOS has hidden the pointer and the chip has nothing
    /// left to be anchored to.
    private var typing = false
    private var typingMonitor: Any?
    private var settlePoint = NSPoint.zero
    private var lastMouse = NSPoint.zero
    private var stillTicks = 0
    /// ~0.25s of stillness at 60 Hz.
    private let settleTicks = 15
    private let wakeDistance: CGFloat = 70

    /// macOS hides the pointer the moment he starts typing — in a terminal, in an
    /// editor — and a chip anchored to an invisible pointer is a label sitting in
    /// the middle of his text with nothing to explain it. There is no supported
    /// API left to ask whether the pointer is drawn (`CGCursorIsDrawnInFramebuffer`
    /// is gone), so the chip watches the cause instead of the effect: a keystroke
    /// sends it away, the next mouse movement brings it back.
    ///
    /// A passive global monitor — it observes, never intercepts, and needs the
    /// Accessibility grant the bubble already has for its own shortcut.
    private func startWatchingTyping() {
        typingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            guard let self = self, !self.typing else { return }
            self.typing = true
            self.refreshOpacity()
        }
    }

    private func startFollowingMouse() {
        // 60 Hz: while engaged this is a window move per frame, which is what
        // "follows the mouse" costs. Settled, it is two point comparisons.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.followCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func followCursor() {
        // The first real movement of the pointer brings the chip back after
        // typing sent it away.
        if typing, hypot(NSEvent.mouseLocation.x - lastMouse.x,
                         NSEvent.mouseLocation.y - lastMouse.y) > 1 {
            typing = false
            refreshOpacity()
        }

        guard NSEvent.pressedMouseButtons == 0 else { return }   // he may be dragging it
        guard let screen = Self.screenUnderMouse() else { return }

        // In the panel states only the *screen* follows: Victor works on whichever
        // screen he points at, and a panel stranded on the other monitor is a
        // panel he cannot see. Where it sits on that screen is left alone, so a
        // bubble he dragged out of the way stays out of the way.
        guard anchored else {
            if screen !== homeScreen { moveToTopLeft(of: screen) }
            return
        }

        let mouse = NSEvent.mouseLocation
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        lastMouse = mouse

        if engaged {
            stillTicks = moved < 1 ? stillTicks + 1 : 0
            if stillTicks >= settleTicks {
                engaged = false
                settlePoint = mouse
                return
            }
            moveNextTo(mouse, on: screen)
            return
        }

        // Settled: wake on a real journey, not on the nudge that is him reaching
        // for the chip itself.
        if hypot(mouse.x - settlePoint.x, mouse.y - settlePoint.y) > wakeDistance || screen !== homeScreen {
            engaged = true
            stillTicks = 0
            moveNextTo(mouse, on: screen)
        }
    }

    /// Below-right of the cursor, flipped at the screen edges so it is never
    /// half off-screen, and never exactly under the pointer.
    private func moveNextTo(_ mouse: NSPoint, on screen: NSScreen) {
        let area = screen.visibleFrame
        let size = panel.frame.size
        var x = mouse.x + anchorGap.width
        var y = mouse.y - anchorGap.height - size.height
        if x + size.width > area.maxX - 4 { x = mouse.x - anchorGap.width - size.width }
        if y < area.minY + 4 { y = mouse.y + anchorGap.height }
        panel.setFrameOrigin(NSPoint(
            x: min(max(x, area.minX + 4), area.maxX - size.width - 4),
            y: min(max(y, area.minY + 4), area.maxY - size.height - 4)
        ))
        homeScreen = screen
    }

    /// Called on every entry to and exit from a panel state, so the move happens
    /// with the state change rather than whenever the leash next gives.
    private func reposition() {
        guard let screen = Self.screenUnderMouse() ?? NSScreen.main else { return }
        if anchored {
            engaged = true
            stillTicks = 0
            moveNextTo(NSEvent.mouseLocation, on: screen)
        } else {
            moveToTopLeft(of: screen)
        }
    }

    /// The title is `folder@branch`, and he switches branches mid-session — a
    /// bubble still claiming `@master` would be quietly wrong about which branch
    /// is receiving his dictation. Ten seconds is slow enough to be free (one
    /// `git rev-parse`) and fast enough that he never reads a stale name.
    private func startWatchingBranch() {
        let timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self, SessionLabel.refresh() else { return }
            self.applyTitleText()
            self.layoutContent()          // the title drives the bubble's width
        }
        RunLoop.main.add(timer, forMode: .common)
        labelTimer = timer
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: - Layout

    /// Manual layout in one pass: build the visible rows top-down with their
    /// heights, size the window to their total, then place them.
    private func layoutContent(animated: Bool = false) {
        // Hug the content of the *current* state, not the widest state there is:
        // standing by is what the bubble does for hours, and it should take no
        // more room than "⏸️ ai@master: Stand by" needs. Changing state resizes it,
        // which is fine — the dots are what must not, and `titleWidthProbe`
        // already measures them at full length.
        let titleWidth = measure(titleWidthProbe, font: titleFont)
        // The legend's width only counts while its row is actually there. It used
        // to be reserved permanently to keep the bubble from jumping sideways when
        // dictation starts, but that reservation is exactly the empty space that
        // has no business being there the rest of the time.
        let hintWidth = hintText.map { measure($0, font: hintFont) } ?? 0
        // No ✕ at rest means no room kept for one: the chip is exactly its text.
        let reserve = anchored ? 0 : closeReserve
        let natural = ceil(max(titleWidth + reserve, hintWidth)) + pad * 2

        // Only a prompt earns the full half-screen. It has to be read whole, and
        // read *fast*, because the Cancel clock is running.
        //
        // A selection does not. Widening the moment dictation starts throws a
        // half-screen panel across whatever Victor is looking at for the entire
        // time he talks — to show him text he highlighted himself a second ago.
        // It rides along truncated in the narrow bubble instead, which is all the
        // receipt it needs, and the bubble grows only at the end, when there is
        // finally something he has *not* seen: what Wispr actually heard.
        // …and even then it takes only what the text needs. Half the screen is the
        // ceiling, not the size: a four-word dictation in a half-screen panel is
        // mostly empty space parked over his work.
        let promptWidth = sentPrompt.map { prompt in
            (prompt.split(whereSeparator: { $0.isNewline })
                   .map { measure(String($0), font: promptFont) }.max() ?? 0) + pad * 2
        } ?? 0
        let width = sentPrompt != nil
            ? min(max(natural, promptWidth), screenWidth / 2)
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

        if let prompt = sentPrompt {
            // Vertically: whatever it takes to show the prompt whole, bounded
            // only by the screen so a very long dictation can't grow a bubble
            // taller than the display.
            let maxHeight = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - margin * 2 - 80
            promptLabel.stringValue = prompt
            promptLabel.preferredMaxLayoutWidth = innerWidth
            let h = min(measureWrapped(prompt, font: promptFont, width: innerWidth), maxHeight)
            promptLabel.frame.size = NSSize(width: innerWidth, height: h)
            promptLabel.isHidden = false
            rows.append((promptLabel, h))
        } else {
            promptLabel.isHidden = true
        }

        // Its own row rather than an overlay in a corner: the prompt can be many
        // lines long, and a button floating over the last one is a button that
        // sometimes sits on top of a word.
        if sentPrompt != nil {
            cancelButton.isHidden = false
            rows.append((cancelButton, cancelButton.frame.height))
        } else {
            cancelButton.isHidden = true
        }

        if let hint = hintText {
            hintLabel.stringValue = hint
            hintLabel.textColor = flashMessage == nil ? .secondaryLabelColor : .labelColor
            hintLabel.frame.size = NSSize(width: innerWidth, height: 17)
            hintLabel.isHidden = false
            rows.append((hintLabel, 17))
        } else {
            hintLabel.isHidden = true
        }

        let contentHeight = rows.reduce(0) { $0 + $1.height }
        let height = contentHeight + rowGap * CGFloat(rows.count - 1) + pad * 2

        // Anchor the TOP edge: the bubble sits in the top-left corner, so it
        // grows downward into empty screen rather than up under the menu bar.
        let oldTop = panel.frame.maxY
        let frame = NSRect(x: panel.frame.minX, y: oldTop - height, width: width, height: height)
        if animated {
            // The jump from a one-line "Listening…" to a half-screen prompt is the
            // biggest thing this window ever does, and done instantly it reads as
            // a new window appearing rather than as this one unfolding.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        root.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        root.blur?.frame = root.bounds

        var y = height - pad
        for row in rows {
            y -= row.height
            row.view.frame.origin = NSPoint(x: pad, y: y)
            y -= rowGap
        }

        // Bottom-right, where Victor asked for it — and where a destructive
        // button belongs, far from the drag area his cursor arrives through.
        if !cancelButton.isHidden {
            cancelButton.frame.origin.x = width - pad - cancelButton.frame.width
        }

        closeButton.frame.origin = NSPoint(x: width - closeButton.frame.width - 6,
                                           y: height - closeButton.frame.height - 6)
        refreshChrome()
        root.needsDisplay = true
    }

    /// At rest there is no bubble — only the text. A blurred, rounded, shadowed
    /// panel riding along beside the cursor all day is a window following him
    /// around; the same words with nothing behind them are a label on his work.
    /// The panel comes back the moment there is something to *contain*: a
    /// dictation, a prompt, a warning.
    private func refreshChrome() {
        let bare = anchored
        root.blur?.isHidden = bare
        root.layer?.cornerRadius = bare ? 0 : 14
        if panel.hasShadow != !bare {
            panel.hasShadow = !bare
            panel.invalidateShadow()
        }
        // Enforced here and not only on hover: leaving a panel state while the
        // cursor happens to be over the bubble would otherwise strand a ✕ on the
        // chip, since nothing re-enters `setHovering` on the way out.
        closeButton.isHidden = bare || !hovering
    }

    private func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Title / opacity

    private func refreshTitle() {
        applyTitleText()
        // Full-strength label on the chip: there is no panel behind it to
        // separate it from his work, so a secondary grey would read as smudge.
        titleLabel.textColor = anchored ? .labelColor
                                        : ((paused || !listening) ? .secondaryLabelColor : .labelColor)
        refreshOpacity()
    }

    /// Just the string — kept separate from `refreshTitle` because the dot
    /// animation ticks several times a second and must not restart the opacity
    /// fade on every frame.
    private func applyTitleText() {
        let text = titleText(dots: dotPhase + 1)
        guard anchored else {
            titleLabel.stringValue = text
            return
        }
        // The one place in the app where a hardcoded colour is right. Everywhere
        // else the backdrop is the bubble's own blur, which follows the system
        // appearance; here there is no backdrop at all — the text sits on his
        // terminal, his editor, a photograph. A dynamic `labelColor` resolves to
        // black in light mode and vanishes on a dark terminal, which is exactly
        // what happened. White with a dark outline is the subtitle trick, and it
        // reads on anything.
        titleLabel.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black.withAlphaComponent(0.85),
            .strokeWidth: -3.5,          // negative: fill *and* stroke
            .shadow: {
                let s = NSShadow()
                s.shadowColor = NSColor.black.withAlphaComponent(0.5)
                s.shadowBlurRadius = 3
                s.shadowOffset = NSSize(width: 0, height: -1)
                return s
            }(),
        ])
    }

    /// The title for the current state. `dots` exists only so the width probe can
    /// ask for the widest form of the listening label while the animation asks for
    /// the live one.
    private func titleText(dots: Int) -> String {
        if let override = titleOverride { return override }
        // Stand-by already wears ⏸️, so paused takes the harder stop glyph: the
        // two states differ by one word otherwise, and they are read at a glance
        // from across the room.
        if paused { return "⏹️ \(SessionLabel.value): Paused" }
        if listening {
            // No "Listening" word: the mic and the running dots already say it,
            // and what he actually needs to read at that moment is which session
            // is about to receive what he says.
            return "🎙️ \(SessionLabel.value)" + String(repeating: ".", count: dots)
        }
        // At rest, no state word at all. "Stand by" is the one thing he can infer
        // from the fact that nothing is happening; what he cannot infer, and what
        // this chip exists to tell him, is which agent is sitting there waiting.
        return "🤖 \(SessionLabel.value)"
    }

    /// What the width must accommodate: the current state's title at its widest.
    /// Three dots, always — measuring the live string would make the bubble
    /// breathe in and out twice a second while he dictates.
    private var titleWidthProbe: String { titleText(dots: 3) }

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

    /// Fully opaque whenever it has something to say. The idle chip sits at 0.80:
    /// it now rides along near the cursor, over Victor's actual work, so it has
    /// to read as an overlay rather than as part of the page — but not so faint
    /// that the one thing it carries (which session it is) is hard to read.
    ///
    /// Paused keeps its 0.30: there, fading is the message. The relay is off, and
    /// the bubble looking switched off is the point.
    private func refreshOpacity() {
        // The chip belongs to the pointer: no pointer, no chip. Panels are their
        // own reason to be on screen and stay put.
        let target: CGFloat = (anchored && typing) ? 0.0
                            : paused ? 0.30
                            : (anchored ? 0.80 : 1.00)
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
        layoutContent()          // pausing mid-dictation retracts the ⌃⌥P row
        reposition()             // …and takes it out of the cursor's wake
    }

    /// Wispr started / stopped listening.
    func setListening(_ value: Bool) {
        guard listening != value else { return }
        listening = value
        if value { startDots(); startShine() } else { stopDots(); stopShine() }
        refreshTitle()
        layoutContent()          // the ⌃⌥P row lives and dies with this state
        reposition()             // …and so does trailing the cursor
    }

    /// Show the prompt on its way to the agent, whole, so Victor can see exactly
    /// what Wispr heard — a mis-transcription is much cheaper to catch here than
    /// three tool calls later.
    ///
    /// The prompt is **held**, not already gone: for `hold` seconds it sits here
    /// with a Cancel button, and only then does it reach the outbox. That is what
    /// makes the button mean something — a prompt already written cannot be
    /// recalled, since the agent polls the queue every couple of seconds and may
    /// have started acting on it before Victor's hand reaches the mouse.
    ///
    /// Returns false if there was nothing worth showing, in which case the caller
    /// still owns the message and must release it itself.
    @discardableResult
    func showSentPrompt(_ text: String, hold: TimeInterval) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // A prompt still on screen has not been released yet. Let it go first, so
        // two dictations in quick succession reach the agent in the order spoken.
        resolvePrompt(send: true)

        sentPrompt = trimmed
        // The selection is already part of what is displayed here, so drop the
        // separate preview row rather than showing it twice.
        selection = nil
        promptDeadline = Date().addingTimeInterval(hold)
        updateCancelTitle()
        // Park first, then unfold: repositioning after an animated resize would
        // snap the window to its destination and eat the animation.
        reposition()
        layoutContent(animated: true)
        refreshOpacity()

        promptTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            self?.resolvePrompt(send: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        promptTimer = timer

        // Four ticks a second: the number on the button should count down
        // smoothly rather than jump, since it is the only thing telling him
        // whether he still has time to reach for it.
        countdownTimer?.invalidate()
        let tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateCancelTitle()
        }
        RunLoop.main.add(tick, forMode: .common)
        countdownTimer = tick
        return true
    }

    private func updateCancelTitle() {
        guard let deadline = promptDeadline else { return }
        let left = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        cancelButton.title = "✕ Cancel \(left)s"
    }

    /// The single exit from the displayed-prompt state: collapse back to the
    /// small bubble and tell the delegate whether to release the message or bin
    /// it. Fires once — every later call finds `sentPrompt` already nil.
    private func resolvePrompt(send: Bool) {
        guard sentPrompt != nil else { return }
        promptTimer?.invalidate()
        promptTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        promptDeadline = nil
        sentPrompt = nil
        layoutContent()
        reposition()
        refreshOpacity()
        // Last, and with the state already cleared: the delegate may well show
        // the next prompt from inside this call.
        onPromptResolved?(send)
    }

    /// Release anything still being held — used when the app is going away and
    /// the choice is between sending it now and losing it.
    func flushHeldPrompt() { resolvePrompt(send: true) }

    /// Transient status in the subtitle row — which it also *summons*, since at
    /// rest that row is not on screen at all.
    func flash(_ message: String, duration: TimeInterval = 2.0) {
        flashMessage = message
        layoutContent()
        reposition()             // a warning is a panel, not a chip: back to the corner
        refreshOpacity()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.flashMessage == message else { return }
            self.flashMessage = nil
            self.layoutContent()
            self.reposition()
            self.refreshOpacity()
        }
    }

    fileprivate func setHovering(_ value: Bool) {
        guard hovering != value else { return }
        hovering = value
        // No ✕ while it is trailing the cursor. There it is a label, not a
        // window: an end-session button on something that moves away as you
        // reach for it is a button that means nothing. It comes back with the
        // panel — during a dictation, and on the prompt.
        closeButton.isHidden = !value || anchored
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
    ///
    /// While a prompt is up, clicking the bubble body means "yes, that's right,
    /// go" — it releases the message immediately instead of waiting out the
    /// countdown, and gets the wide panel off his work. The one place where a
    /// click means *no* is the Cancel button, which swallows its own clicks.
    /// Toggling pause here would be the mistake he would never notice.
    fileprivate func handleClick() {
        if sentPrompt != nil {
            resolvePrompt(send: true)
            return
        }
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

// MARK: - Cancel button

/// The button that stops a held prompt from ever reaching the agent.
///
/// Drawn rather than an `NSButton` because the bubble's panel never becomes key:
/// standard controls in a non-activating panel look permanently disabled and
/// swallow the first click activating the window. This one is always live.
final class PillButton: NSView {
    var onClick: (() -> Void)?
    var title: String = "" {
        didSet { guard title != oldValue else { return }; needsDisplay = true }
    }
    private var hot = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        // Red only under the cursor. At rest it is one more quiet control: the
        // bubble is on screen all day and a permanently red button reads as an
        // error rather than as an offer.
        if hot {
            NSColor.systemRed.withAlphaComponent(0.92).setFill()
        } else {
            NSColor.secondaryLabelColor.withAlphaComponent(0.22).setFill()
        }
        pill.fill()
        NSColor.secondaryLabelColor.withAlphaComponent(hot ? 0.0 : 0.35).setStroke()
        pill.lineWidth = 1
        pill.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: hot ? NSColor.white : NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(
            in: NSRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height),
            withAttributes: attrs)
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

    // Swallow the whole click — reaching BubbleView would release the very
    // prompt this button exists to stop.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
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
