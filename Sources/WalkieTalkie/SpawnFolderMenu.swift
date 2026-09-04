import AppKit

/// **The one thing a spawn could never say: *which* folder.**
///
/// ⌘ + the wheel (and the two chords that mean the same thing) opens a session
/// that does not exist yet, and it has always opened it in `~/workspace` — see
/// `AppDelegate.spawnDirectory` for why that was fixed rather than inferred. The
/// cost of a fixed answer is that the first sentence of every new session is
/// spent saying which repo it is about, out loud, to an agent that then has to
/// `cd` into it. Victor's ask, 2026-09-04: *"vreau să-mi arăt un modal în care
/// să pot să aleg în ce folder pornesc dictarea"*.
///
/// So: the instant a spawn dictation opens, a small menu appears **below and to
/// the left of where the mouse was when he started talking**, naming the five
/// folders he actually starts sessions in. A click picks one and is remembered
/// for that dictation; **no click means `~/workspace`**, exactly as before. It
/// stays solid for three and a half seconds and then fades out over one, because
/// a dictation is already running behind it and a menu that waits to be
/// dismissed is a menu in the way of the sentence being spoken.
///
/// **It is a menu, not a tooltip, so it draws a surface.** *Nothing beside the
/// pointer draws a window* is about the chip and the flashes — things that are
/// read and never touched. This one has to be **aimed at**: rows need edges to
/// tell them apart, and a target needs a ground to sit on. It is also the one
/// thing this app puts near the cursor that does not follow it — it stays where
/// the sentence started, so the hand can travel to it.
///
/// **It is not an `NSMenu`.** `popUp` runs a nested tracking run loop, which
/// would freeze the pulsing 🔴 and the chip's own cursor-following for as long as
/// it is up, and it offers neither a timed dismissal nor a fade.
enum SpawnFolderMenu {

    /// One row: the folder it opens, and where that is.
    struct Choice {
        let name: String
        let path: String
    }

    /// **Victor's five, in the order he said them**, under `~/workspace`.
    ///
    /// A hardcoded list and not a listing of the workspace: that folder holds
    /// ~150 directories, nearly all of them course material (see the workspace's
    /// own `CLAUDE.md`), and a menu of 150 rows is not a menu. These are the
    /// projects he starts sessions in.
    ///
    /// **The trust prompt does not apply to them, and that was checked rather
    /// than assumed.** The reason the spawn directory was frozen at `~/workspace`
    /// is that Claude Code stops on *"do you trust this folder"* in a directory
    /// it has never been started from, which costs the sentence already spoken.
    /// All five carry `hasTrustDialogAccepted` in `~/.claude.json` — he works in
    /// them by hand every day, which is the same reason they are on this list.
    /// A folder that does not exist is dropped rather than offered: the launcher
    /// falls back to `$HOME` on a failed `cd`, which is the one destination
    /// nobody meant.
    static let choices: [Choice] = ["victor-macos-addons", "training-assistant",
                                    "walkie-talkie", "victor-vsc", "petclinic"]
        .map { Choice(name: $0, path: workspace + "/" + $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }

    private static var workspace: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("workspace").path
    }

    /// **Three and a half seconds solid, then a second of fade.** Victor's
    /// numbers — it was two, and two is not long enough to read five names,
    /// decide and travel to one while a sentence is already being spoken. The
    /// fade is not only a way out: it is the part that says the menu was
    /// optional, since something that vanishes on its own was never asking to be
    /// answered.
    ///
    /// **A click still lands during the fade**, so the window to answer is four
    /// and a half seconds. Nothing turns hit-testing off; the panel is ordered
    /// out only once the animation has run to the end.
    static let solidSeconds: TimeInterval = 3.5
    static let fadeSeconds: TimeInterval = 1

    // MARK: - Geometry

    /// The chip's face, for the chip's reason — this is the same hand talking,
    /// an inch from the same pointer.
    private static let rowFont = NSFont.systemFont(ofSize: 17)
    private static let headerFont = NSFont.systemFont(ofSize: 12)
    private static let rowHeight: CGFloat = 28
    private static let headerHeight: CGFloat = 20
    private static let pad: CGFloat = 8
    /// The inset of a row's text inside its own highlight.
    static let rowInset: CGFloat = 10
    private static let radius: CGFloat = 10
    /// How far off the pointer the corner sits — `RelayWindow.anchorGap`'s width,
    /// mirrored, since this hangs off the other side of the cursor.
    private static let gap: CGFloat = 10

    /// It says what the rows are for. Every one of them is a bare folder name,
    /// which is unmistakable once you know what the menu is and says nothing at
    /// all the first three times it appears.
    private static let header = "Start Claude in…"

    // MARK: - State

    private static var panel: NSPanel?
    private static var timer: Timer?
    private static var chosen: ((Choice) -> Void)?

    // MARK: - Showing

    /// Put it up at `point` (Cocoa screen coordinates — `NSEvent.mouseLocation`),
    /// and call `pick` if he takes one. Nothing is called if he does not: the
    /// caller's default stands, which is the whole shape of this gesture.
    static func show(at point: CGPoint, pick: @escaping (Choice) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(at: point, pick: pick) }
            return
        }
        hide()
        guard !choices.isEmpty else { return }
        chosen = pick

        let size = measure()
        let root = build(size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // Above the chip and above a full-screen window, since the dictation it
        // belongs to is routinely started over one.
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The relay photographs the screen during the very dictation this menu
        // opens — the automatic frame and every back-button shot. Same rule `CaptureFlash`,
        // `RecordingBeacon` and the chip itself follow.
        p.sharingType = .none
        p.contentView = root
        p.setFrameOrigin(origin(for: size, at: point))
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p

        // `.common`, or it stops running the moment anything on the main thread
        // enters a tracking loop.
        let t = Timer.scheduledTimer(withTimeInterval: solidSeconds, repeats: false) { _ in fade() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Take it down now — a pick, a cancelled dictation, a second menu.
    static func hide() {
        timer?.invalidate()
        timer = nil
        chosen = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func fade() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().alphaValue = 0
        }, completionHandler: {
            // Only if it is still this menu: a pick, or a second spawn, has
            // already put it away and may have put another one up.
            if panel === p { hide() }
        })
    }

    private static func take(_ choice: Choice) {
        let callback = chosen
        hide()
        callback?(choice)
    }

    // MARK: - Layout

    private static func measure() -> NSSize {
        let widest = choices
            .map { ($0.name as NSString).size(withAttributes: [.font: rowFont]).width }
            .max() ?? 0
        let headerWidth = (header as NSString).size(withAttributes: [.font: headerFont]).width
        let width = max(widest, headerWidth) + 2 * (pad + rowInset)
        let height = 2 * pad + headerHeight + CGFloat(choices.count) * rowHeight
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private static func build(size: NSSize) -> NSView {
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.cornerRadius = radius
        root.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: root.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)

        // Cocoa's y grows upwards, so the rows are laid out from the bottom and
        // the header ends up on top.
        var y = pad
        for choice in choices.reversed() {
            let row = FolderRow(frame: NSRect(x: pad, y: y,
                                              width: size.width - 2 * pad, height: rowHeight),
                                choice: choice, font: rowFont)
            row.onClick = { take($0) }
            root.addSubview(row)
            y += rowHeight
        }

        let label = NSTextField(labelWithString: header)
        label.font = headerFont
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: pad + rowInset, y: y + (headerHeight - label.intrinsicContentSize.height) / 2,
                             width: size.width - 2 * (pad + rowInset),
                             height: label.intrinsicContentSize.height)
        root.addSubview(label)

        return root
    }

    /// **Down and to the left of the pointer** — Victor's ask, 2026-09-04. It is
    /// also the one quadrant the chip is never in: that hangs below-*right*
    /// (`RelayWindow.anchorGap`), and a menu underneath a chip following the
    /// same cursor cannot be clicked.
    ///
    /// **It is always wholly on screen**, which is the half worth saying out
    /// loud: a menu that opens near an edge opens there precisely when the hand
    /// is far from the middle. So it flips to the other side of the pointer when
    /// the preferred one would hang off, and is then clamped into the visible
    /// frame of **the screen the pointer is on** rather than the main one. At a
    /// corner the clamp can slide it under the pointer; a menu three rows from
    /// the cursor is answerable and one half off the edge is not.
    private static func origin(for size: NSSize, at point: CGPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)

        // Right edge just left of the pointer; flipped right if it would hang off.
        var x = point.x - gap - size.width
        if x < visible.minX { x = point.x + gap }
        x = max(visible.minX, min(x, visible.maxX - size.width))

        // Top edge just below the pointer; flipped above it if the rows would
        // run off the bottom of the screen.
        var y = point.y - gap - size.height
        if y < visible.minY { y = point.y + gap }
        y = max(visible.minY, min(y, visible.maxY - size.height))

        return NSPoint(x: x, y: y)
    }
}

// MARK: - A row

/// One folder, drawn rather than an `NSButton`: this panel never becomes key, and
/// standard controls in a non-activating panel look permanently disabled and eat
/// the first click. Same call `PillButton` and the ✕ already make.
private final class FolderRow: NSView {
    private let choice: SpawnFolderMenu.Choice
    private let font: NSFont
    private var hot = false
    var onClick: ((SpawnFolderMenu.Choice) -> Void)?

    init(frame: NSRect, choice: SpawnFolderMenu.Choice, font: NSFont) {
        self.choice = choice
        self.font = font
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        if hot {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        // White on the selection fill wins in either appearance, the way the ✕
        // does on its red disc.
        let ink = hot ? NSColor.white : NSColor.labelColor
        let text = NSAttributedString(string: choice.name,
                                      attributes: [.font: font, .foregroundColor: ink])
        let size = text.size()
        text.draw(at: NSPoint(x: SpawnFolderMenu.rowInset,
                              y: (bounds.height - size.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true }

    // The app is `.accessory` and never active, so *every* click here is a first
    // mouse. Without this the first one would be spent activating nothing.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?(choice) }
}
