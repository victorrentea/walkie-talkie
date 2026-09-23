import AppKit

/// **A reminder under the pointer, after every sentence, of which keys bring
/// it back** — `⌘⇧P`.
///
/// Victor's first ask, 2026-09-22: *"după ce ai dat cancel la dictare sau după
/// ce s-a încheiat o dictare la caret … ideea că paste-ul poate [se] pierde …
/// să apară foarte transparent, încă un hint, cu tastele pe care le apăs ca să
/// dau paste la acel prompt. Și cumva să apară foarte faint, și apoi să crească
/// opacitatea … și apoi să dispară. Un singur puls de la transparent la mai
/// opac și apoi din nou transparent."*
///
/// And the one that supersedes it, 2026-09-23: *"indiferent prin ce mecanism am
/// închis o dictare — că e la caret, că e bound, că e nou — să afișeze pentru
/// trei secunde, cu opțiunea de 80% pentru două secunde și jumătate, scurtătura
/// cu care pot să fac paste la ultimul prompt … Uneori îl plasez greșit, lasă-mă
/// să-mi amintesc constant ce este asta."*
///
/// ## After every delivered sentence, whatever the destination (2026-09-23)
///
/// `⌘⇧P` is the one gesture in the app that is *only* ever wanted after
/// something went slightly wrong: the words landed in the window that had the
/// focus rather than the one he meant, went to the bound terminal while he
/// meant another, or the panel's Cancel threw away a sentence he then wished
/// he had. A shortcut recalled at leisure is no use at a moment of mild alarm —
/// which is why it lived in a menu two clicks away and was forgotten.
///
/// On 2026-09-22 that reasoning put the hint at exactly two moments: a caret
/// sentence, as the one delivery this app cannot read back, and a cancelled
/// prompt. **That is superseded.** A terminal delivery *is* read back — but
/// only for *did it arrive*, never for *was that the terminal he meant*, which
/// only he can answer; *"uneori îl plasez greșit"* is him saying the bound and
/// spawned destinations get misaimed too. And a hint that appears only
/// sometimes cannot teach a shortcut — *"lasă-mă să-mi amintesc constant"* asks
/// for the repetition itself. So it follows **every** delivery: the caret, a
/// bound terminal, a new session, a sentence released by the bind it was held
/// for, and Wispr Flow's own dictations routed by the relay. The cancelled
/// prompt keeps its showing. A sentence held for a bind gets its hint when it
/// is **delivered**, not when it is parked — until then it has landed nowhere
/// it could be wrong about.
///
/// It is **still not** offered after a cancelled *dictation* (the ✕
/// mid-flight): that sentence never became words, so `⌘⇧P` there would paste
/// the *previous* one — the exact failure `copy_last_text` is under a standing
/// *never reintroduce* rule for. What that case has is *Recover Cancelled
/// Dictation*, which is a different offer and already made in the banner.
///
/// ## Plainly visible, and why the fifth of an opacity went (2026-09-23)
///
/// It was `0.20` at its peak, 0.8 s up and 1.2 s down — his number from
/// 2026-09-22 (*"10–20%"*), on the argument that a hint repeated dozens of
/// times a day over his work had to sit beneath notice or become an
/// interruption charged on every success. **Superseded by his own number**:
/// 80%, held 2.5 s, gone by 3 s. A mark beneath notice is a mark nobody reads,
/// and a reminder nobody reads reminds nobody. At 80% it is read at a glance;
/// at three seconds, beside the pointer, unmoving and click-through, it is still
/// not a thing he has to decide about.
///
/// **One showing, then gone for good.** Nothing here repeats, breathes or waits
/// to be dismissed. It arrives already at `peak` rather than fading up: the
/// 2.5 s he asked for is the stretch it is *legible*, and a rise would spend
/// the start of it too faint to read.
///
/// `WT_PASTE_HINT_PEAK` still moves the opacity for a run.
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
/// landed, and does not follow: while it is up he may well be reaching for the
/// keys, and a hint that walks away from the cursor as he
/// moves is the single dotted arrow `DropArrow` threw out — a thing to look at
/// rather than a thing to notice.
final class PasteHint {

    /// **How opaque it is while it is up** — Victor's *"80%"*, 2026-09-23. It
    /// was 0.20 until then (*"până la [două]zeci la sută"*); see above for why
    /// that went.
    static let peak: CGFloat = {
        guard let raw = ProcessInfo.processInfo.environment["WT_PASTE_HINT_PEAK"],
              let value = Double(raw), value > 0, value <= 1 else { return 0.80 }
        return CGFloat(value)
    }()

    /// **Held at `peak` for this long** from the instant it appears — his
    /// *"două secunde și jumătate"*.
    static let hold: TimeInterval = 2.5

    /// **Then faded out over this**, so the whole showing is `hold + fall`, his
    /// *"trei secunde"*. A fade rather than a cut, so its going does not read
    /// as an event of its own.
    static let fall: TimeInterval = 0.5

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
    /// A showing is in flight. A second one restarts rather than overlapping:
    /// two timers racing on one `alphaValue` is a flicker, and the case that
    /// produces it — a cancel immediately after a delivery — is one where only
    /// the later reason is still true.
    private var pulsing = false
    /// Which showing the pending fade and its completion belong to. Bumped by
    /// every `pulse` and `hide`, so a fade scheduled by an earlier showing finds
    /// itself stale and does nothing to the window a later one has put up.
    private var generation = 0

    /// What the window is actually doing, beside what the flag claims — the
    /// reading `DropArrow.report` exists for, and answered in
    /// `GET /test/state.pasteHint`.
    var report: [String: Any] {
        ["visible": panel?.isVisible ?? false,
         "alpha": Double(panel?.alphaValue ?? 0),
         "pulsing": pulsing, "peak": Double(Self.peak),
         "hold": Self.hold, "fall": Self.fall]
    }

    /// **Say it once, under the pointer, and be gone** — `peak` at once, for
    /// `hold`, then faded out over `fall`. `reason` is for the log only: the
    /// callers are far apart and *why is this on screen* is not a question the
    /// picture can answer.
    func pulse(reason: String) {
        let p = panel ?? makePanel()
        p.setFrameOrigin(Self.origin(for: p.frame.size))
        Log.info("⌨️ paste hint — \(reason)")
        generation += 1
        let mine = generation
        // Overrule anything still running: a zero-length group takes
        // `alphaValue` back from an animator mid-fade, and the new generation is
        // what stops the old fade's completion ordering out a window this call
        // has just put back up.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            p.animator().alphaValue = Self.peak
        }
        p.alphaValue = Self.peak
        if !p.isVisible { p.orderFrontRegardless() }
        pulsing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { [weak self] in
            guard let self, self.generation == mine else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fall
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == mine else { return }
                self.pulsing = false
                p.orderOut(nil)
            })
        }
    }

    /// The hard stop — the app is going away, or a new dictation has started and
    /// the hint is about the last one. A cut rather than a fade: what replaces
    /// it is the ring going up, which is its own event.
    func hide() {
        generation += 1
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
    /// and *how does it read over his work* is the question being asked of a
    /// hint whose design is mostly one opacity.
    ///
    /// **Two columns**: `peak` — the 80% it stands at for 2.5 s — over each
    /// ground, and then the same drawing at full ink, which is where the shape
    /// itself is judged.
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
/// through a window alpha over an unknown background (a fifth until
/// 2026-09-23, 80% since). **White ink with a dark shadow under it**, the
/// chip's own answer: the ink carries it over a terminal, the shadow carries it
/// over a page, and at any alpha both fade together so neither can win over the
/// other and leave a smear.
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
