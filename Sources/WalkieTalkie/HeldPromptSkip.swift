import AppKit

/// **`»` on the sent prompt's dialog: take it off the screen now** (2026-10-22).
///
/// Victor: *"uneori rămâne fereastra de preview de prompt prea mult timp pe
/// ecran … chiar după ce deja s-a trimis … am văzut și 10 secunde … un buton
/// vizibil pe el, undeva în colț … care să arate ca două săgeți"*.
///
/// **Why it stays**: after the send the dialog is *held*, inactive, on purpose —
/// for a 🔼 ↑ new session until the prompt is in the new transcript (2026-10-04,
/// `AppDelegate.releaseWhenSessionStarts`; on 2026-10-22 that took 2.4–66 s,
/// usually 4–7 s), and for as long as the pointer rests on it (2026-10-05,
/// `RelayWindow.lingerWhileRead`). Both stay; this is the way out of them.
///
/// The dialog ignores the mouse while held (*"inactiv … să nu pot să dau hover
/// pe el sau click pe el"*), so the button is **its own small panel** over the
/// dialog's top-right corner — `FilmBorder`'s `REC` badges are built the same
/// way. A click fades the dialog and nothing else: the prompt has already gone
/// and its delivery (the Returns, the session watch) carries on.
final class HeldPromptSkip {
    private var panel: NSPanel?
    var onClick: (() -> Void)?

    static let side: CGFloat = 26
    static let inset: CGFloat = 6

    /// Up over `frame`'s top-right corner, at `level`, captured like the dialog.
    func show(over frame: NSRect, level: NSWindow.Level, sharing: NSWindow.SharingType) {
        let p = panel ?? make()
        p.level = NSWindow.Level(rawValue: level.rawValue + 1)
        p.sharingType = sharing
        p.setFrame(NSRect(x: frame.maxX - Self.side - Self.inset, y: frame.maxY - Self.side - Self.inset,
                          width: Self.side, height: Self.side), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    var isVisible: Bool { panel?.isVisible == true }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = SkipView(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        view.onClick = { [weak self] in self?.onClick?() }
        p.contentView = view
        panel = p
        return p
    }

    /// A dark rounded square with `»` — the two arrows — in white; brighter under
    /// the pointer, a hand cursor.
    private final class SkipView: NSView {
        var onClick: (() -> Void)?
        private var hot = false { didSet { needsDisplay = true } }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
                                           owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { hot = true }
        override func mouseExited(with event: NSEvent) { hot = false }
        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        }

        override func draw(_ dirtyRect: NSRect) {
            let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            NSColor(white: hot ? 0.32 : 0.16, alpha: 0.92).setFill()
            box.fill()
            NSColor(white: 1, alpha: 0.35).setStroke()
            box.lineWidth = 1
            box.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            guard let symbol = NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: "Hide")?
                    .withSymbolConfiguration(config) else { return }
            let tinted = NSImage(size: symbol.size, flipped: false) { r in
                symbol.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let s = tinted.size
            tinted.draw(in: NSRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2,
                                   width: s.width, height: s.height))
        }
    }
}
