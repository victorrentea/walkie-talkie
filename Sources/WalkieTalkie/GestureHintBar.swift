import AppKit

/// **The gestures that work right now, bottom right of the screen** (2026-09-29).
///
/// Victor: *"during dictation, show a small hint bar in the bottom right of the
/// screen with the key combos available at that stage (eg 🔽↑ stop video,
/// 🔼 end dictation...)"*. The chip by the pointer says what the sentence *is*;
/// this says what he can *do* to it, and changes with the stage: a prompt
/// offers the shutter, the film, kamikaze and a new session; a plain dictation
/// only its stop, its stop-and-Return and the cancel.
///
/// **Drawn as two crosses, one per side button** (2026-09-30, from his sketch):
/// 🔼 on top, 🔽 under it, as the buttons sit on the mouse. The centre box is the
/// click, the arms are the swipes, and a gesture with nothing to do right now
/// keeps an empty box so the shape — and where his thumb goes — never moves.
/// 🔼 → has no box at all: mid-sentence it flips bound ⇄ caret (2026-10-05),
/// which the chip's destination row already shows.
///
/// **Off the Retina, against its edge** (2026-09-30, Victor: *"displayed on any
/// secondary monitor if there are any, otherwise on the Retina. Prefer the monitor
/// to the right of Retina. Keep them small and close to the edge which is adjoined
/// to Retina"*). The Retina is where he works; the bar sits just across the seam,
/// bottom of that seam, so a glance sideways finds it. See `placement`.
///
/// **Three times bigger off the Retina** (2026-10-01, Victor: *"when the shortcuts
/// appear on the secondary screen, make them twice as big. Even three times. Plenty
/// of room, so I see them easily. If it's not on the Retina."*). A glance sideways
/// at a farther, low-density screen needs the size; on the Retina it stays small.
///
/// **Opaque across the seam; when the pointer follows it there, it flees back**
/// (2026-10-01, Victor: *"when the hints appear on the other screen, fully opaque.
/// My mouse goes there, but they should come back to the other screen, even on the
/// side if needed. But there extremely transparent, flee from the screen the mouse
/// is on"*). Off the Retina nothing is underneath that he is looking at, so it is
/// solid; once the pointer is on that screen it is in the way, so it moves to the
/// Retina's side of the same seam, small and nearly see-through. See `spot`.
///
/// **Alone, it hides from the pointer** (2026-10-08): with one screen there is
/// nowhere to flee, so the pointer within `dodge` of the corner fades it out
/// and leaving fades it back. See `spot`.
///
/// Only in Logi mode — the glyphs are the side buttons' (`AboutWindow.logiGesturesOn`).
/// Never in a screenshot (`sharingType = .none`), never takes the mouse, and it
/// does not ride the pointer: a fixed spot, so it is read at a glance.
final class GestureHintBar {

    /// What the chip knows about the sentence, which is all the bar needs.
    struct Stage: Equatable {
        var listening = false
        /// A prompt (🔼 / 🔼 → / 🔼 ↑); false for a plain dictation.
        var prompting = false
        var filming = false
        var kamikaze = false
        /// The sentence already opens a new session — 🔼 ↑ has nothing left to do.
        var spawn = false
        /// Right ⌘⌥ is held for it: his hand is on the keyboard, not the mouse,
        /// so there is nothing to show (2026-09-30, Victor: *"no need to display
        /// those shortcuts while cmd-opt pressed down dictation"*).
        var held = false
        /// A wheel crop is on screen: the bar draws the mouse instead of the two
        /// side buttons, because that is the hand the crop is in (2026-10-07).
        var crop: CropPhase? = nil
        /// A ⚡ quick question: its stop asks the model, nothing is typed and
        /// no Return follows (2026-10-09).
        var quick = false
    }

    /// Where the wheel crop is — `CropSelectionOverlay.Phase`, without `done`.
    enum CropPhase: Equatable { case selecting, locked, parked, drawing }

    /// **The mouse, drawn, for the length of a crop** (2026-10-07). Victor, on
    /// the right click that now locks the box: *"aș vrea să poți să reprezinți
    /// chestia asta cumva vizual … pe acele hint-uri"*. Same rules as a cross:
    /// `""` is an empty gray box (the button does nothing right now).
    struct MouseHint: Equatable {
        var left = ""
        var wheel = ""
        var right = ""
        /// Under the buttons, on the mouse's body: the keyboard's way out.
        var body = ""
    }

    /// The mouse for a stage, or nil when no crop is up. Pure, like `crosses`.
    static func mouse(for s: Stage) -> MouseHint? {
        guard s.listening, !s.held, let crop = s.crop else { return nil }
        switch crop {
        case .selecting:
            return MouseHint(wheel: "✂️ drag", right: "➡️ move to", body: "Esc cancel")
        case .locked:
            return MouseHint(wheel: "⬆️ let go", right: "↩️ unlock", body: "Esc cancel")
        case .parked:
            return MouseHint(wheel: "🎯 drag there", right: "🗑️ cancel", body: "Esc cancel")
        case .drawing:
            return MouseHint(wheel: "🎯 drag there", body: "Esc cancel")
        }
    }

    /// One button's gestures. `nil` = no box is drawn, `""` = an empty box.
    struct Cross: Equatable {
        var click: String? = ""
        var up: String? = ""
        var down: String? = ""
        var left: String? = ""
        var right: String? = ""
    }

    /// The two crosses for a stage — 🔼 first, 🔽 second. Pure, so the wording
    /// can be checked without a screen.
    static func crosses(for s: Stage) -> [Cross] {
        guard s.listening, !s.held else { return [] }
        var front = Cross(right: nil)
        var back = Cross()
        front.left = "🗑️ cancel"
        if s.prompting {
            front.click = "🏁 end"
            front.up = s.spawn ? "" : "✨ new"
            // Kamikaze is its emoji alone, crossed out once it is on (2026-09-30,
            // Victor: *"instead of 'no kamikaze', kamikaze crossed out"*).
            front.down = s.kamikaze ? Self.struck + "☠️" : "☠️"
            back.click = "📸 shot"
            // Stop is ⏹️, never the word (2026-09-30).
            back.up = s.filming ? "⏹️ video" : "🔴 video"
            // The typing box (2026-10-08, Victor: *"nu-l văd nici în sugestia
            // de taste din colț"*) — `HotkeyTap.onTypeIn`.
            back.down = "⌨️ type"
        } else if s.quick {
            back.click = "⚡ ask"
            back.right = "⚡ ask"
        } else {
            back.click = "⏹️ + ⏎"
            back.right = "⏹️"
        }
        return [front, back]
    }

    /// A label starting with this is drawn crossed out, without it.
    static let struck = "~"

    private var panel: NSPanel?
    private var board: Board?
    private var shown = Stage()
    /// The screens as of the last `show` — read once, not on every mouse move.
    private var displays: [Display] = []
    private var placed: Spot?

    fileprivate static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    fileprivate static let boxHeight: CGFloat = 24
    fileprivate static let minBoxWidth: CGFloat = 68
    fileprivate static let padding: CGFloat = 6
    fileprivate static let gap: CGFloat = 4
    /// Between the 🔼 cross and the 🔽 one: a row's worth, as in the sketch —
    /// widened 2026-09-30 so the two read as two buttons.
    fileprivate static let crossGap: CGFloat = 24
    /// The Retina alone: see-through (2026-09-30, Victor: *"should be semi-transparent"*),
    /// it sits over whatever he is working on in that corner.
    static let aloneOpacity: CGFloat = 0.6
    /// Across the seam nothing he reads is under it: solid (2026-10-01).
    static let acrossOpacity: CGFloat = 1
    /// Fled back to the Retina, over his work: nearly gone (2026-10-01).
    static let fledOpacity: CGFloat = 0.3
    static let margin: CGFloat = 16
    /// **The pointer this close to a bar with nowhere to flee hides it**
    /// (2026-10-08, Victor: *"when the mouse goes towards the area where the
    /// tooltips are on a single monitor setup, those should disappear when my
    /// mouse gets there because they get in the way"*). It fades back once the
    /// pointer is this far away again.
    static let dodge: CGFloat = 80
    /// How much bigger the bar is drawn on a screen that is not the Retina.
    static let offRetinaScale: CGFloat = 3

    func update(_ stage: Stage) {
        let visible = stage.listening && !stage.held && AboutWindow.logiGesturesOn
        guard stage != shown || (panel != nil) != visible else { return }
        shown = stage
        guard visible else { hide(); return }
        let mouse = Self.mouse(for: stage)
        show(mouse == nil ? Self.crosses(for: stage) : [], mouse: mouse)
    }

    /// Every mouse move, from the chip's own monitors: the bar leaves the screen
    /// the pointer is on (2026-10-01).
    func pointerMoved(_ pointer: NSPoint) {
        guard let board, !board.crosses.isEmpty || board.mouse != nil else { return }
        place(board.crosses, mouse: board.mouse, pointer: pointer)
    }

    private func show(_ crosses: [Cross], mouse: MouseHint? = nil) {
        displays = NSScreen.screens.map { s -> Display in
            let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return Display(frame: s.frame, visible: s.visibleFrame,
                           builtIn: id.map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
        if let board {
            board.crosses = crosses
            board.mouse = mouse
            placed = nil
            place(crosses, mouse: mouse, pointer: NSEvent.mouseLocation)
            return
        }
        guard let spot = Self.spot(base: Board.size(for: crosses, mouse: mouse), on: displays,
                                   pointer: NSEvent.mouseLocation) else { return }
        Log.info("⌨️ hint bar ×\(Int(spot.scale)) α\(spot.opacity): \(crosses.map(Self.describe).joined(separator: " / "))")
        let p = NSPanel(contentRect: spot.rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = .none

        let b = Board(frame: NSRect(origin: .zero, size: spot.rect.size))
        b.scale = spot.scale
        b.opacity = spot.opacity > 0 ? spot.opacity : Self.aloneOpacity
        b.crosses = crosses
        b.mouse = mouse
        b.autoresizingMask = [.width, .height]
        p.contentView = b
        p.alphaValue = 0
        p.orderFrontRegardless()
        if spot.opacity > 0 {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 1 }
        }
        panel = p
        board = b
        placed = spot
    }

    private func place(_ crosses: [Cross], mouse: MouseHint? = nil, pointer: NSPoint) {
        guard let panel, let board,
              let spot = Self.spot(base: Board.size(for: crosses, mouse: mouse), on: displays, pointer: pointer),
              spot != placed else { return }
        let dodged = spot.opacity == 0, wasDodged = placed?.opacity == 0, first = placed == nil
        if placed == nil {
            Log.info("⌨️ hint bar ×\(Int(spot.scale)) α\(spot.opacity): \(crosses.map(Self.describe).joined(separator: " / "))")
        } else if dodged != wasDodged, placed?.rect == spot.rect {
            Log.info(dodged ? "⌨️ hint bar hides from the pointer" : "⌨️ hint bar back")
        } else {
            Log.info("⌨️ hint bar moved ×\(Int(spot.scale)) α\(spot.opacity)")
        }
        placed = spot
        board.scale = spot.scale
        // A dodge is the panel fading, not the drawing: the board keeps its
        // opacity for the moment the pointer leaves.
        if !dodged { board.opacity = spot.opacity }
        panel.setFrame(spot.rect, display: true)
        if dodged != wasDodged || first {
            NSAnimationContext.runAnimationGroup { $0.duration = dodged ? 0.15 : 0.3; panel.animator().alphaValue = dodged ? 0 : 1 }
        }
    }

    private func hide() {
        guard let p = panel else { return }
        panel = nil
        board = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                            completionHandler: { p.orderOut(nil) })
    }

    private static func describe(_ c: Cross) -> String {
        [("·", c.click), ("↑", c.up), ("↓", c.down), ("←", c.left), ("→", c.right)]
            .compactMap { k, v in v.flatMap { $0.isEmpty ? nil : "\(k) \($0)" } }
            .joined(separator: ", ")
    }

    /// A screen as `placement` needs it — plain values, so it is tested without one.
    struct Display: Equatable {
        var frame: NSRect
        var visible: NSRect
        var builtIn: Bool
    }

    /// Where the bar is drawn, how big and how solid.
    struct Spot: Equatable {
        var rect: NSRect
        var scale: CGFloat
        var opacity: CGFloat
    }

    /// The bar for a pointer. Across the seam it is `offRetinaScale` and solid;
    /// with the pointer on that same screen it flees to the Retina's side of the
    /// seam, at its small size and `fledOpacity`. The Retina alone, or the lid
    /// closed, has nowhere to flee to: it stays put.
    static func spot(base: NSSize, on screens: [Display], pointer: NSPoint) -> Spot? {
        let big = NSSize(width: base.width * offRetinaScale, height: base.height * offRetinaScale)
        guard let home = screens.first(where: \.builtIn),
              screens.contains(where: { !$0.builtIn }) else {
            let scale = scale(on: screens)
            let size = NSSize(width: base.width * scale, height: base.height * scale)
            return placement(size: size, on: screens).map {
                let near = NSMouseInRect(pointer, $0.insetBy(dx: -dodge, dy: -dodge), false)
                return Spot(rect: $0, scale: scale, opacity: near ? 0 : scale == 1 ? aloneOpacity : acrossOpacity)
            }
        }
        guard let (across, seam) = host(on: screens),
              let rect = placement(size: big, on: screens) else { return nil }
        guard NSMouseInRect(pointer, across.frame, false) else {
            return Spot(rect: rect, scale: offRetinaScale, opacity: acrossOpacity)
        }
        let v = home.visible, m = margin
        let w = base.width, h = base.height
        let y = max(v.minY, across.visible.minY) + m
        let x = min(v.maxX, across.visible.maxX) - w - m
        let fled: NSRect
        switch seam {
        case .right: fled = NSRect(x: v.maxX - w - m, y: y, width: w, height: h)
        case .left: fled = NSRect(x: v.minX + m, y: y, width: w, height: h)
        case .below: fled = NSRect(x: x, y: v.minY + m, width: w, height: h)
        case .above: fled = NSRect(x: x, y: v.maxY - h - m, width: w, height: h)
        case .none: fled = NSRect(x: v.maxX - w - m, y: v.minY + m, width: w, height: h)
        }
        return Spot(rect: fled, scale: 1, opacity: fledOpacity)
    }

    /// `placement` puts the bar on the Retina only when it is the sole screen;
    /// anywhere else (a secondary, or the lid closed) it is drawn `offRetinaScale`.
    static func scale(on screens: [Display]) -> CGFloat {
        screens.contains { !$0.builtIn } ? offRetinaScale : 1
    }

    /// Which side of the Retina the secondary that holds the bar touches.
    enum Seam { case right, left, below, above, none }

    /// The secondary the bar goes on — the one right of the Retina first, then
    /// any touching it, then any — and the Retina's edge it shares. Nil without
    /// a Retina or without a secondary.
    static func host(on screens: [Display]) -> (Display, Seam)? {
        guard let home = screens.first(where: \.builtIn) else { return nil }
        let others = screens.filter { !$0.builtIn }
        let r = home.frame, slack: CGFloat = 2
        func overlapsV(_ f: NSRect) -> Bool { f.minY < r.maxY && f.maxY > r.minY }
        func overlapsH(_ f: NSRect) -> Bool { f.minX < r.maxX && f.maxX > r.minX }
        if let s = others.first(where: { abs($0.frame.minX - r.maxX) <= slack && overlapsV($0.frame) }) {
            return (s, .right)
        }
        if let s = others.first(where: { abs($0.frame.maxX - r.minX) <= slack && overlapsV($0.frame) }) {
            return (s, .left)
        }
        if let s = others.first(where: { abs($0.frame.maxY - r.minY) <= slack && overlapsH($0.frame) }) {
            return (s, .below)
        }
        if let s = others.first(where: { abs($0.frame.minY - r.maxY) <= slack && overlapsH($0.frame) }) {
            return (s, .above)
        }
        return others.first.map { ($0, .none) }
    }

    /// Where the bar goes. The Retina alone (or no Retina at all, lid closed):
    /// its bottom-right corner, as before. Otherwise the `host` secondary,
    /// against the edge it shares with the Retina, at the bottom (left/right
    /// seam) or the right end (top/bottom seam).
    static func placement(size: NSSize, on screens: [Display]) -> NSRect? {
        let m = margin
        func corner(_ v: NSRect) -> NSRect {
            NSRect(x: v.maxX - size.width - m, y: v.minY + m, width: size.width, height: size.height)
        }
        guard let home = screens.first(where: \.builtIn) else {
            return screens.first.map { corner($0.visible) }
        }
        guard let (s, seam) = host(on: screens) else { return corner(home.visible) }
        let r = home.frame, v = s.visible
        // The part of the seam both screens own, so the bar stays by the Retina.
        let seamY = max(v.minY, r.minY) + m
        let seamX = min(v.maxX, r.maxX) - size.width - m
        switch seam {
        case .right: return NSRect(x: v.minX + m, y: seamY, width: size.width, height: size.height)
        case .left: return NSRect(x: v.maxX - size.width - m, y: seamY, width: size.width, height: size.height)
        case .below: return NSRect(x: seamX, y: v.maxY - size.height - m, width: size.width, height: size.height)
        case .above: return NSRect(x: seamX, y: v.minY + m, width: size.width, height: size.height)
        case .none: return corner(v)
        }
    }

    /// The crosses, drawn. A three-column grid shared by both, so their centre
    /// boxes line up; every box is as wide as the widest label, so the board
    /// does not change width when a label does.
    final class Board: NSView {
        var crosses: [Cross] = [] { didSet { needsDisplay = true } }
        /// Set during a crop, in place of the crosses.
        var mouse: MouseHint? { didSet { needsDisplay = true } }
        /// Drawn at `size(for:)` × this; the frame is already that big.
        var scale: CGFloat = 1 { didSet { needsDisplay = true } }
        /// The whole board's alpha; at 1 the boxes are solid too ("fully opaque").
        var opacity: CGFloat = GestureHintBar.aloneOpacity { didSet { needsDisplay = true } }

        override var isFlipped: Bool { true }

        static func boxWidth(for crosses: [Cross]) -> CGFloat {
            let labels = crosses.flatMap { [$0.click, $0.up, $0.down, $0.left, $0.right] }.compactMap { $0 }
            let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: GestureHintBar.font]).width }
                .max() ?? 0
            return max(GestureHintBar.minBoxWidth, ceil(widest) + GestureHintBar.padding * 2)
        }

        static func mouseBoxWidth(for m: MouseHint) -> CGFloat {
            let widest = [m.left, m.wheel, m.right]
                .map { ($0 as NSString).size(withAttributes: [.font: GestureHintBar.font]).width }.max() ?? 0
            return max(GestureHintBar.minBoxWidth, ceil(widest) + GestureHintBar.padding * 2)
        }

        /// The mouse: three buttons side by side, as tall as two boxes, over a
        /// body as tall as two more.
        static func size(for crosses: [Cross], mouse: MouseHint?) -> NSSize {
            guard let mouse else { return size(for: crosses) }
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            return NSSize(width: mouseBoxWidth(for: mouse) * 3 + gap * 2, height: h * 4 + gap)
        }

        static func size(for crosses: [Cross]) -> NSSize {
            let w = boxWidth(for: crosses)
            let crossHeight = GestureHintBar.boxHeight * 3 + GestureHintBar.gap * 2
            let n = CGFloat(crosses.count)
            return NSSize(width: w * 3 + GestureHintBar.gap * 2,
                          height: crossHeight * n + GestureHintBar.crossGap * max(0, n - 1))
        }

        override func draw(_ dirtyRect: NSRect) {
            let w = Self.boxWidth(for: crosses)
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            let crossHeight = h * 3 + gap * 2
            let cg = NSGraphicsContext.current?.cgContext
            cg?.scaleBy(x: scale, y: scale)
            cg?.setAlpha(opacity)
            cg?.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { cg?.endTransparencyLayer() }
            if let mouse {
                drawMouse(mouse)
                return
            }
            for (i, c) in crosses.enumerated() {
                let top = CGFloat(i) * (crossHeight + GestureHintBar.crossGap)
                func box(_ text: String?, col: Int, row: Int) {
                    guard let text else { return }
                    let r = NSRect(x: CGFloat(col) * (w + gap), y: top + CGFloat(row) * (h + gap),
                                   width: w, height: h)
                    drawBox(text, in: r)
                }
                box(c.up, col: 1, row: 0)
                box(c.left, col: 0, row: 1)
                box(c.click, col: 1, row: 1)
                box(c.right, col: 2, row: 1)
                box(c.down, col: 1, row: 2)
            }
        }

        /// Left, wheel and right across the top — the outer two rounded at their
        /// outer top corner so the row reads as a mouse — and the body under
        /// them, rounded at the bottom.
        private func drawMouse(_ m: MouseHint) {
            let w = Self.mouseBoxWidth(for: m)
            let h = GestureHintBar.boxHeight, gap = GestureHintBar.gap
            let buttonHeight = h * 2
            let big = buttonHeight * 0.6
            func button(_ label: String, col: Int, topLeft: CGFloat, topRight: CGFloat) {
                let r = NSRect(x: CGFloat(col) * (w + gap), y: 0, width: w, height: buttonHeight)
                drawBox(label, in: r, path: Self.roundedPath(r.insetBy(dx: 0.5, dy: 0.5),
                                                              topLeft: topLeft, topRight: topRight,
                                                              bottomLeft: 4, bottomRight: 4))
            }
            button(m.left, col: 0, topLeft: big, topRight: 4)
            button(m.wheel, col: 1, topLeft: 4, topRight: 4)
            button(m.right, col: 2, topLeft: 4, topRight: big)
            let body = NSRect(x: 0, y: buttonHeight + gap, width: w * 3 + gap * 2, height: h * 2 - gap)
            drawBox(m.body, in: body, path: Self.roundedPath(body.insetBy(dx: 0.5, dy: 0.5),
                                                              topLeft: 4, topRight: 4,
                                                              bottomLeft: big, bottomRight: big))
        }

        /// A rectangle with its own radius per corner, in this flipped view.
        static func roundedPath(_ r: NSRect, topLeft: CGFloat, topRight: CGFloat,
                                bottomLeft: CGFloat, bottomRight: CGFloat) -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + topLeft, y: r.minY))
            p.line(to: NSPoint(x: r.maxX - topRight, y: r.minY))
            p.appendArc(withCenter: NSPoint(x: r.maxX - topRight, y: r.minY + topRight), radius: topRight,
                        startAngle: 270, endAngle: 360)
            p.line(to: NSPoint(x: r.maxX, y: r.maxY - bottomRight))
            p.appendArc(withCenter: NSPoint(x: r.maxX - bottomRight, y: r.maxY - bottomRight), radius: bottomRight,
                        startAngle: 0, endAngle: 90)
            p.line(to: NSPoint(x: r.minX + bottomLeft, y: r.maxY))
            p.appendArc(withCenter: NSPoint(x: r.minX + bottomLeft, y: r.maxY - bottomLeft), radius: bottomLeft,
                        startAngle: 90, endAngle: 180)
            p.line(to: NSPoint(x: r.minX, y: r.minY + topLeft))
            p.appendArc(withCenter: NSPoint(x: r.minX + topLeft, y: r.minY + topLeft), radius: topLeft,
                        startAngle: 180, endAngle: 270)
            p.close()
            return p
        }

        private func drawBox(_ label: String, in r: NSRect, path given: NSBezierPath? = nil) {
            let struck = label.hasPrefix(GestureHintBar.struck)
            let text = struck ? String(label.dropFirst(GestureHintBar.struck.count)) : label
            let empty = text.isEmpty
            let path = given ?? NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            // An unused gesture is a plain gray box (2026-09-30, Victor: *"place
            // gray boxes on all unused gestures"*) — seen, and plainly not a label.
            let solid = opacity >= 1
            (empty ? NSColor(white: 0.5, alpha: solid ? 1 : 0.55)
                   : NSColor.black.withAlphaComponent(solid ? 1 : 0.66)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(empty ? 0.3 : 0.45).setStroke()
            path.lineWidth = 1
            path.stroke()
            guard !empty else { return }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byClipping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: GestureHintBar.font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
                .paragraphStyle: style,
            ]
            let s = text as NSString
            let ts = s.size(withAttributes: attrs)
            s.draw(in: NSRect(x: r.minX + 4, y: r.midY - ts.height / 2, width: r.width - 8, height: ts.height),
                   withAttributes: attrs)
            guard struck else { return }
            let half = min(ts.width, r.width - 8) / 2 + 3
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: r.midX - half, y: r.maxY - 3))
            slash.line(to: NSPoint(x: r.midX + half, y: r.minY + 3))
            slash.lineWidth = 2.5
            slash.lineCapStyle = .round
            NSColor.systemRed.setStroke()
            slash.stroke()
        }
    }
}
