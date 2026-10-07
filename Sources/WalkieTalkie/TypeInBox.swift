import AppKit

/// **A few typed letters, into the prompt being spoken** (2026-10-07).
///
/// Victor: *"sometimes I would like to type a word or two … when I'm dictating
/// it is hard to spell [it] … the back button moved to the bottom … would open
/// up a very tiny input text right next to the cursor, focused for me to type a
/// few letters … that would expand the more I write, and that would be
/// submitted by hitting enter … alt enter or shift enter … include an empty
/// line, and that should be annotated and inserted into the dictation."*
///
/// 🔽 ↓ while a prompt records (`HotkeyTap.onTypeIn`) puts this up just below
/// and right of the pointer. **Return** hands the text to `AppDelegate`, which
/// files it where the gesture fell in the sentence (`[typed: "…"]`, the
/// selection markers' machinery); **⌥⏎ / ⇧⏎** is a new line; **Esc** drops it.
/// The microphone keeps recording the whole time.
///
/// **It takes the keyboard without activating the app** — a non-activating
/// panel that is allowed to become key (`TypeInPanel`). *Nothing calls
/// `NSApp.activate`* still holds: the app in front stays in front, and when the
/// box goes its own key window has the keyboard again.
///
/// **It grows as he writes** — one line wide enough for what is typed, up to
/// `maxWidth`, then it wraps and grows down. Like everything near the pointer,
/// `sharingType = .none`: the shutter photographs the screen during this very
/// sentence and the box is not part of what he is pointing at.
enum TypeInBox {
    private static var panel: TypeInPanel?
    private static var view: NSTextView?
    private static var submit: ((String) -> Void)?
    private static var anchor: NSPoint = .zero

    private static let font = NSFont.systemFont(ofSize: 15)
    private static let minWidth: CGFloat = 140
    private static let maxWidth: CGFloat = 420
    private static let pad: CGFloat = 8
    private static let hint = "type · ⏎ add · ⌥⏎ new line · esc"

    static var isOpen: Bool { panel != nil }
    /// What the box holds right now — `GET /test/state`.
    static var text: String? { view?.string }

    /// Put the box up below-right of `point` (Cocoa screen coordinates) and call
    /// `done` with the text if he submits it. A second call replaces the first.
    static func show(at point: CGPoint, done: @escaping (String) -> Void) {
        close()
        submit = done
        let tv = Field(frame: NSRect(x: 0, y: 0, width: minWidth, height: 22))
        tv.font = font
        tv.textColor = .white
        tv.insertionPointColor = .white
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.onCommand = { command in handle(command) }
        tv.onChange = { relayout() }
        view = tv

        let p = TypeInPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = .none
        p.hidesOnDeactivate = false
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.94).cgColor
        root.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.9).cgColor
        root.layer?.borderWidth = 1.5
        let label = NSTextField(labelWithString: hint)
        label.font = NSFont.systemFont(ofSize: 10)
        label.textColor = NSColor.white.withAlphaComponent(0.45)
        label.tag = 7
        root.addSubview(label)
        root.addSubview(tv)
        p.contentView = root
        panel = p
        anchor = NSPoint(x: point.x + 12, y: point.y - 12)
        relayout()
        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(tv)
        Log.info("⌨️ typing box up at (\(Int(point.x)), \(Int(point.y)))")
    }

    /// The sentence's microphone closed with the box still up: what is typed so
    /// far goes in rather than being lost with the box.
    static func commitIfOpen() {
        guard let text = view?.string else { return }
        Log.info("⌨️ the microphone closed with the typing box up — its \(text.count) chars go in")
        finish(text)
    }

    /// Desk route only (`POST /test/type-in`): put text in the open box as if typed.
    static func type(_ text: String) {
        guard let tv = view else { return }
        tv.string = text
        relayout()
    }

    static func close() {
        panel?.orderOut(nil)
        panel = nil
        view = nil
        submit = nil
    }

    // MARK: - Keys

    private static func handle(_ command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.option) || flags.contains(.shift) {
                view?.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            finish(view?.string ?? "")
            return true
        case #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            view?.insertNewlineIgnoringFieldEditor(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            Log.info("⌨️ typing box dropped (esc)")
            close()
            return true
        default:
            return false
        }
    }

    private static func finish(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = submit
        close()
        guard !text.isEmpty else { Log.info("⌨️ typing box closed empty"); return }
        done?(text)
    }

    // MARK: - Size

    /// One line as wide as the text, `minWidth`…`maxWidth`; past that it wraps
    /// and grows downwards. The top-left corner stays where it opened.
    private static func relayout() {
        guard let p = panel, let tv = view, let root = p.contentView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let lines = tv.string.components(separatedBy: "\n")
        let widest = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let inner = min(maxWidth, max(minWidth, ceil(widest) + 12))
        tv.frame.size.width = inner
        tc.containerSize = NSSize(width: inner, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let textHeight = max(ceil(lm.usedRect(for: tc).height), ceil(font.ascender - font.descender + font.leading)) + 4
        let hintHeight: CGFloat = 14
        let size = NSSize(width: inner + 2 * pad, height: textHeight + hintHeight + 2 * pad)
        tv.frame = NSRect(x: pad, y: pad + hintHeight, width: inner, height: textHeight)
        if let label = root.viewWithTag(7) {
            label.frame = NSRect(x: pad, y: pad - 2, width: inner, height: hintHeight)
        }
        // Below-right of the pointer, flipped and clamped like the folder menu.
        let screen = NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var x = anchor.x, top = anchor.y
        if x + size.width > visible.maxX { x = anchor.x - 24 - size.width }
        if top - size.height < visible.minY { top = anchor.y + 24 + size.height }
        x = max(visible.minX, min(x, visible.maxX - size.width))
        top = min(visible.maxY, top)
        p.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel may not become key by default; this one must, or the
/// keys go to the app in front.
private final class TypeInPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class Field: NSTextView {
    var onCommand: ((Selector) -> Bool)?
    var onChange: (() -> Void)?

    override func doCommand(by selector: Selector) {
        if onCommand?(selector) == true { return }
        super.doCommand(by: selector)
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?()
    }

    // The app is never active, so the first click here is a first mouse.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
