import AppKit

/// **One faint pulse under the pointer, saying which keys bring the sentence
/// back** — `⌘⇧P`.
///
/// Victor's ask, 2026-09-22: *"după ce ai dat cancel la dictare sau după ce s-a
/// încheiat o dictare la caret … ideea că paste-ul poate [se] pierde … să apară
/// foarte transparent, încă un hint, cu tastele pe care le apăs ca să dau paste
/// la acel prompt. Și cumva să apară foarte faint, și apoi să crească
/// opacitatea … și apoi să dispară. Un singur puls de la transparent la mai
/// opac și apoi din nou transparent."*
///
/// ## Why it exists at exactly these two moments
///
/// `⌘⇧P` has been in the app since the day the clipboard stopped being restored
/// after a caret paste, and it is the one gesture in it that is *only* ever
/// wanted after something went slightly wrong: the ⌘V landed in the window that
/// had the focus rather than the one he meant, or the panel's Cancel threw a
/// sentence away he then wished he had. Both are moments of mild alarm, and a
/// shortcut recalled at leisure is no use at a moment of mild alarm — which is
/// why it has lived in a menu two clicks away and been forgotten.
///
/// So it is said where the loss happens, at the instant it happens, and nowhere
/// else. It is **not** offered after a cancelled *dictation* (the ✕ mid-flight):
/// that sentence never became words, so `⌘⇧P` there would paste the *previous*
/// one — the exact failure `copy_last_text` is under a standing *never
/// reintroduce* rule for. What that case has is *Recover Cancelled Dictation*,
/// which is a different offer and already made in the banner.
///
/// ## Why it is nearly invisible, and why that is the point
///
/// He asked for `10`–`20%`, twice, unprompted — and the ceiling here is his
/// number rather than a designer's. A hint that appears after *every* caret
/// sentence is a hint that appears dozens of times a day over the thing he is
/// working in; at full ink that is an interruption charged on every success in
/// order to help with the occasional failure. At a fifth of full ink it is
/// visible to a glance that goes looking and beneath notice to one that does
/// not, which is the only setting at which something can be said this often.
///
/// **One pulse, and then it is gone for good** (*"un singur puls"*). Nothing
/// here repeats, breathes or waits to be dismissed: a mark that lingers is one
/// more thing on screen to decide about.
///
/// `WT_PASTE_HINT_PEAK` moves the ceiling for a run, because the one number in
/// here that is a matter of taste is the one that cannot be judged from code.
///
/// ## A window of its own
///
/// `DropArrow`'s reason, one door down: everything else this app draws near the
/// pointer hangs its meaning on the window's own alpha — the ring *is* the
/// voice — and a layer inside one of those panels is drawn through a number
/// that has nothing to do with it. This owns its alpha, which is the whole of
/// what it has to say.
///
/// It is placed **once**, at the pointer where it stood when the sentence
/// landed, and does not follow: by the time it has faded up he may well be
/// reaching for the keys, and a hint that walks away from the cursor as he
/// moves is the single dotted arrow `DropArrow` threw out — a thing to look at
/// rather than a thing to notice.
final class PasteHint {

    /// **The most opaque this ever gets** — Victor's *"până la [zece] la sută …
    /// până la [două]zeci la sută"*, taken at the top of the range he named
    /// because the bottom of it is invisible over a photograph.
    static let peak: CGFloat = {
        guard let raw = ProcessInfo.processInfo.environment["WT_PASTE_HINT_PEAK"],
              let value = Double(raw), value > 0, value <= 1 else { return 0.20 }
        return CGFloat(value)
    }()

    /// Up, then down, and nothing in between: the pause is what would make it a
    /// notice rather than a breath. Together they are the two seconds he asked
    /// for, split so the fade out is the longer half — an arrival wants to be
    /// noticed, a departure does not.
    private static let rise: TimeInterval = 0.8
    private static let fall: TimeInterval = 1.2

    /// How far below the pointer's hot spot the box's top edge sits. Clear of
    /// the macOS arrow cursor, whose body hangs below the hot spot, and clear of
    /// `DropArrow`'s innermost heads at 18 — those are down by the time this is
    /// up, but a hint that lands where the arrows were is one he reads as an
    /// arrow that failed to fade.
    private static let drop: CGFloat = 26

    /// The keys, as they are written on his keyboard. **Not spelled out** —
    /// `Command-Shift-P` is a sentence to read where the symbols are the things
    /// his fingers are already looking for.
    private static let keys = "⌘⇧P"

    private var panel: RelayPanel?
    /// A pulse is in flight. A second one restarts rather than overlapping: two
    /// animations racing on one `alphaValue` is a flicker, and the case that
    /// produces it — a cancel immediately after a paste — is one where only the
    /// later reason is still true.
    private var pulsing = false

    /// What the window is actually doing, beside what the flag claims — the
    /// reading `DropArrow.report` exists for, and answered in
    /// `GET /test/state.pasteHint`.
    var report: [String: Any] {
        ["visible": panel?.isVisible ?? false,
         "alpha": Double(panel?.alphaValue ?? 0),
         "pulsing": pulsing, "peak": Double(Self.peak)]
    }

    /// **Say it once, under the pointer, and be gone.** `reason` is for the log
    /// only — the two callers are far apart and *why is this on screen* is not
    /// a question the picture can answer.
    func pulse(reason: String) {
        let p = panel ?? makePanel()
        p.setFrameOrigin(Self.origin(for: p.frame.size))
        Log.info("⌨️ paste hint — \(reason)")
        // Overrule anything still running: the animator owns `alphaValue` until
        // it is told otherwise, and `pulsing` going down is what stops the old
        // fade's completion handler ordering out a window this call has just put
        // back up.
        pulsing = false
        p.alphaValue = 0
        if !p.isVisible { p.orderFrontRegardless() }
        pulsing = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.rise
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = Self.peak
        }, completionHandler: { [weak self] in
            guard let self, self.pulsing else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fall
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.pulsing else { return }
                self.pulsing = false
                p.orderOut(nil)
            })
        })
    }

    /// The hard stop — the app is going away, or a new dictation has started and
    /// the hint is about the last one. A cut rather than a fade: what replaces
    /// it is the ring going up, which is its own event.
    func hide() {
        pulsing = false
        panel?.orderOut(nil)
        panel?.alphaValue = 0
    }

    /// Centred on the pointer's column, hanging below it — and put **above** the
    /// pointer instead when there is no room below, because a box clamped to the
    /// bottom of the screen is a box that has stopped pointing at anything.
    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var y = mouse.y - drop - size.height
        if let frame = screen?.visibleFrame, y < frame.minY + 4 {
            y = mouse.y + drop
        }
        return NSPoint(x: (mouse.x - size.width / 2).rounded(), y: y.rounded())
    }

    private func makePanel() -> RelayPanel {
        let view = KeycapView(keys: Self.keys)
        let size = view.intrinsicContentSize
        // `RelayPanel` for `CaretHalo`'s reason: `constrainFrameRect` drags a
        // borderless window back under the menu bar, which for something placed
        // against the pointer near an edge means it stops being against the
        // pointer.
        let p = RelayPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.sharingType = CaretHalo.capturable ? .readOnly : .none
        p.alphaValue = 0
        view.frame = NSRect(origin: .zero, size: size)
        p.contentView = view
        panel = p
        return p
    }

    /// **Draw it onto a dark ground and a light one, and quit** —
    /// `WT_SHOOT_HINT=/tmp/hint.png`, `CaretHalo.shoot`'s route and its reason:
    /// the panel is `sharingType = .none`, so no screen capture can contain it,
    /// and *is it there* is not the question being asked of a hint whose whole
    /// design is a number between nothing and not much.
    ///
    /// **Three columns**: the peak he asked for, over each ground, and then the
    /// same drawing at full ink — which is the only column in which the shape
    /// itself can be judged at all.
    static func shoot(to path: String) {
        let view = KeycapView(keys: keys)
        let cell = view.intrinsicContentSize
        let pad: CGFloat = 20
        let box = NSSize(width: cell.width + pad * 2, height: cell.height + pad * 2)
        let grounds: [NSColor] = [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.97, alpha: 1)]
        let alphas: [CGFloat] = [peak, 1]
        let sheet = NSImage(size: NSSize(width: box.width * CGFloat(alphas.count),
                                         height: box.height * CGFloat(grounds.count)))
        sheet.lockFocus()
        for (row, ground) in grounds.enumerated() {
            for (col, alpha) in alphas.enumerated() {
                let at = NSRect(x: box.width * CGFloat(col),
                                // Top row first: `NSImage` counts up from the bottom.
                                y: box.height * CGFloat(grounds.count - 1 - row),
                                width: box.width, height: box.height)
                ground.setFill()
                at.fill()
                let host = KeycapView(keys: keys)
                host.frame = NSRect(origin: .zero, size: cell)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    NSImage(size: cell, flipped: false) { r in rep.draw(in: r) }
                        .draw(in: NSRect(x: at.minX + pad, y: at.minY + pad,
                                         width: cell.width, height: cell.height),
                              from: .zero, operation: .sourceOver, fraction: alpha)
                }
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return print("could not render the paste hint")
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("paste hint: \(path)")
    }
}

/// **The keys, drawn as a key**: the chord inside a rounded outline, which is
/// what a keycap is and what makes three symbols read as *press this* rather
/// than as three more glyphs on a busy screen.
///
/// Drawn rather than set in a label for `Glyphs`' standing reason — these rows
/// carry a halo, in which an inline glyph turns every other character
/// transparent — and because the one thing this has to survive is being drawn
/// at a fifth of an opacity over an unknown background. **White ink with a dark
/// shadow under it**, the chip's own answer: the ink carries it over a terminal,
/// the shadow carries it over a page, and at 20% both fade together so neither
/// can win over the other and leave a smear.
final class KeycapView: NSView {

    private let text: NSAttributedString
    /// The gap between the ink and the outline, and the outline's own weight.
    private static let padX: CGFloat = 9
    private static let padY: CGFloat = 5
    private static let stroke: CGFloat = 1.5

    init(keys: String) {
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        text = NSAttributedString(string: keys, attributes: [.font: font,
                                                             .foregroundColor: NSColor.white,
                                                             .shadow: shadow])
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { false }

    override var intrinsicContentSize: NSSize {
        let drawn = text.size()
        return NSSize(width: ceil(drawn.width) + Self.padX * 2,
                      height: ceil(drawn.height) + Self.padY * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: Self.stroke / 2, dy: Self.stroke / 2)
        let radius = min(6, box.height / 3)
        let outline = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        outline.lineWidth = Self.stroke
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = .zero
        shadow.set()
        NSColor.white.setStroke()
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let drawn = text.size()
        text.draw(at: NSPoint(x: ((bounds.width - drawn.width) / 2).rounded(),
                              y: ((bounds.height - drawn.height) / 2).rounded()))
    }
}
