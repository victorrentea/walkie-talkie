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
/// dismissed is a menu in the way of the sentence being spoken — **unless the
/// hand is on it**: the pointer arriving suspends the clock, mid-fade included,
/// and leaving lets the fade run (2026-09-04).
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
///
/// # Two halves, and a line between them (2026-09-08)
///
/// The list was six names hardcoded here — the projects Victor happened to be
/// working on the afternoon it was written. He asked for the other half:
/// *"determin care sunt proiectele în care am lucrat … să le adaugi sub o linie
/// separatoare … pe lângă cele fixate de sus"*. So:
///
/// ```
///   Start Claude in…
///   petclinic                    ★     ← pinned, alphabetical
///   walkie-talkie                ★
///   ─────────────────────────────
///   petclinic-pr                 ☆     ← measured, alphabetical
///   victor-skills-private        ☆
/// ```
///
/// Above the line is `PinnedProjects`, which is his own decision and survives
/// everything. Below it is `RecentProjects` — the five repos he has burned the
/// most tokens in over the last fortnight, read off Claude Code's own
/// transcripts by `helpers/recent_projects.py`. **The star moves a row between
/// the two**, and clicking one does *not* close the menu: it is a change to what
/// the menu is, not an answer to what it asks.
///
/// **Chosen by rank, shown alphabetically**, both on his instruction — *"în
/// ordine descrescătoare după… nu, alfabetic"*. The measurement decides which
/// five; the eye gets a list it can find a name in. A leaderboard that reorders
/// itself between two openings puts the row he reached for last time somewhere
/// else.
///
/// **Unpinning is not a delete.** A row taken off the pinned half falls into the
/// recent half if it qualifies, and disappears if it does not — *"acel proiect
/// să apară în lista de proiecte recente, doar dacă am deschis recent în acel
/// folder vreo muncă"*. That is `RecentProjects.offered` with the pin removed,
/// and it needs no code of its own here: the qualification is already what the
/// bottom half means.
enum SpawnFolderMenu {

    /// One row: the folder it opens, where that is, and which side of the line
    /// it is on.
    struct Choice {
        let name: String
        let path: String
        var pinned: Bool = false
    }

    /// **The rows, in the order they are drawn**: the pinned half first, then
    /// the recent half, each sorted alphabetically. The separator goes between
    /// them, and only if both halves have something in them.
    ///
    /// **The trust prompt does not apply to either half, and neither half is a
    /// guess.** The reason the spawn directory was frozen at `~/workspace` is
    /// that Claude Code stops on *"do you trust this folder"* in a directory it
    /// has never been started from, which costs the sentence already spoken. A
    /// pinned folder is one he works in by hand; a recent one is, by
    /// construction, a folder a Claude Code session has already run in — which
    /// is the same fact the trust flag records. A folder that no longer exists
    /// is dropped by both halves rather than offered: the launcher falls back to
    /// `$HOME` on a failed `cd`, which is the one destination nobody meant.
    static func rows() -> (pinned: [Choice], recent: [Choice]) {
        let pins = PinnedProjects.paths()
        let pinned = pins
            .map { Choice(name: ($0 as NSString).lastPathComponent, path: $0, pinned: true) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let recent = RecentProjects.offered(excluding: Set(pins))
            .map { Choice(name: $0.name, path: $0.path, pinned: false) }
        return (pinned, recent)
    }

    /// **Three and a half seconds solid, then a second of fade — unless the
    /// hand is on it.** Victor's numbers for the clock, and Victor's exception
    /// for the hover (2026-09-04): *"the modal to pick the folder should not
    /// fade out while I hover it"*. The fade exists to say the menu was
    /// optional; a pointer resting on a row is the answer being made, and a
    /// target that dims as the hand arrives punishes the one gesture it exists
    /// for. So the mouse arriving stops the clock — mid-fade included, a click
    /// lands during the fade so the menu is still answering — and leaving it
    /// lets the fade run from wherever the clock had got to.
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
    /// The star's box, at the trailing edge of every row.
    ///
    /// **On the right, which is where a favourite toggle lives** — mail, IDE
    /// bookmarks, everything that has ever had one. It is also what keeps the
    /// folder names in one flush-left column: the names are what he is aiming
    /// at, and a glyph in front of them would push each one in by the width of
    /// something he is not reading.
    static let starSize: CGFloat = 16
    /// The gap between the longest name and the star column, so a row that fills
    /// its width does not run into the glyph.
    private static let starGap: CGFloat = 12
    /// The line itself: a hairline, inset to the rows' own edges so it reads as
    /// dividing the list rather than crossing the panel.
    private static let separatorHeight: CGFloat = 9
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
    /// The rows as they are currently drawn. Computed once when the menu opens
    /// and again on every star, so a toggle relays out against what it just
    /// changed rather than re-reading the disk mid-gesture.
    private static var rendered: (pinned: [Choice], recent: [Choice]) = ([], [])
    /// Where the panel's **top-left** corner is, kept so a rebuild can put it
    /// back there. A menu that grows or shrinks under the hand must not move the
    /// rows the hand is already over, and it hangs *below* the pointer — so the
    /// top edge is the one that has to stay still.
    private static var anchor: NSPoint = .zero
    private static var chosen: ((Choice) -> Void)?
    /// The hand on the menu, which suspends the fade — see `solidSeconds`.
    private static var hovered = false
    /// Whether the solid period has run out; the fade an exit triggers only
    /// makes sense once it has.
    private static var solidOver = false
    /// Bumped on every state change, so a fade's completion can tell it has
    /// been superseded by an un-fade and must not hide the panel.
    private static var generation = 0

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
        // **Ask for a fresh ranking on the way past.** One `stat`, and on the
        // one day in a hundred it says the file is stale, a detached process
        // this app never waits on. See `RecentProjects.refreshIfStale`.
        RecentProjects.refreshIfStale()
        rendered = rows()
        guard !rendered.pinned.isEmpty || !rendered.recent.isEmpty else { return }
        chosen = pick

        let size = measure()
        let root = build(size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        // **Above the chip, above a full-screen window, and above the capture
        // effect** — the dictation this menu belongs to is routinely started
        // over a full-screen window, and it is *always* started on top of the
        // marker that blooms out of the pointer.
        //
        // `.popUpMenu` (101) cleared the chip (`.statusBar`, 25) but lost to the
        // effect panels, which sit at `CGWindowLevelForKey(.maximumWindow)` —
        // and the effect is created *after* the menu (the menu opens at the
        // press, the context shot fires at the release), so ordering could not
        // save it either: the tap ripple played over the top of the menu.
        // Victor, 2026-09-06. One above the maximum is the only level that wins
        // by construction rather than by luck, and `kCGMaximumWindowLevel` is
        // `INT32_MAX - 16`, so there is room above it.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The relay photographs the screen during the very dictation this menu
        // opens — the automatic frame and every back-button shot. Same rule `CaptureFlash`,
        // `RecordingBeacon` and the chip itself follow.
        p.sharingType = .none
        p.contentView = root
        let where_ = origin(for: size, at: point)
        p.setFrameOrigin(where_)
        // The top-left corner, which is what a rebuild puts back — see `rebuild`.
        anchor = NSPoint(x: where_.x, y: where_.y + size.height)
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        hovered = false
        solidOver = false
        generation += 1

        // `.common`, or it stops running the moment anything on the main thread
        // enters a tracking loop.
        let t = Timer.scheduledTimer(withTimeInterval: solidSeconds, repeats: false) { _ in
            solidOver = true
            // Hovered, the clock has run out and nothing happens: the exit is
            // what lets the fade start, whenever the hand leaves.
            if !hovered { fade() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// **The pointer arriving on the menu stops the fade; leaving restarts it.**
    /// Called from the content view's tracking area. Arriving mid-fade is not
    /// too late — clicks land during the fade, so the menu is still answering,
    /// and a target that dims under the hand is one being taken away as it is
    /// aimed at.
    static func setHovered(_ on: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { setHovered(on) }
            return
        }
        hovered = on
        if on {
            guard let p = panel, p.alphaValue < 1 else { return }
            // Invalidate the in-flight fade's completion before reversing it.
            generation += 1
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                p.animator().alphaValue = 1
            }
        } else if solidOver {
            fade()
        }
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
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = fadeSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().alphaValue = 0
        }, completionHandler: {
            // Only if it is still this menu **and this fade**: a pick or a
            // second spawn has already put it away, and an un-fade (the hand
            // arriving mid-fade) reversed it — a stale completion must not hide
            // a panel that is solid again.
            if panel === p && generation == gen { hide() }
        })
    }

    private static func take(_ choice: Choice) {
        let callback = chosen
        hide()
        callback?(choice)
    }

    // MARK: - Layout

    private static func measure() -> NSSize {
        let all = rendered.pinned + rendered.recent
        let widest = all
            .map { ($0.name as NSString).size(withAttributes: [.font: rowFont]).width }
            .max() ?? 0
        let headerWidth = (header as NSString).size(withAttributes: [.font: headerFont]).width
        // The star sits inside every row, so the rows have to be wide enough for
        // the longest name *and* the glyph; the header has no star and is
        // measured on its own.
        let width = max(widest + starGap + starSize, headerWidth) + 2 * (pad + rowInset)
        let divider = (rendered.pinned.isEmpty || rendered.recent.isEmpty) ? 0 : separatorHeight
        let height = 2 * pad + headerHeight + CGFloat(all.count) * rowHeight + divider
        return NSSize(width: ceil(width), height: ceil(height))
    }

    private static func build(size: NSSize) -> NSView {
        let root = HoverRoot(frame: NSRect(origin: .zero, size: size))
        root.onHover = { SpawnFolderMenu.setHovered($0) }
        root.wantsLayer = true
        root.layer?.cornerRadius = radius
        root.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: root.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        root.addSubview(blur)

        // Cocoa's y grows upwards, so the groups are laid out bottom-up — the
        // recent half first, then the line, then the pinned half, and the header
        // ends up on top.
        var y = pad
        for choice in rendered.recent.reversed() { y = add(choice, at: y, size: size, to: root) }
        if !rendered.pinned.isEmpty && !rendered.recent.isEmpty {
            let line = NSView(frame: NSRect(x: pad + rowInset, y: y + (separatorHeight - 1) / 2,
                                            width: size.width - 2 * (pad + rowInset), height: 1))
            line.wantsLayer = true
            // A hairline in the label's own ink at a tenth of its weight: it has
            // to be visible over the blur in both appearances and must not read
            // as a row of its own.
            line.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor
            root.addSubview(line)
            y += separatorHeight
        }
        for choice in rendered.pinned.reversed() { y = add(choice, at: y, size: size, to: root) }

        let label = NSTextField(labelWithString: header)
        label.font = headerFont
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: pad + rowInset, y: y + (headerHeight - label.intrinsicContentSize.height) / 2,
                             width: size.width - 2 * (pad + rowInset),
                             height: label.intrinsicContentSize.height)
        root.addSubview(label)

        return root
    }

    private static func add(_ choice: Choice, at y: CGFloat, size: NSSize, to root: NSView) -> CGFloat {
        let row = FolderRow(frame: NSRect(x: pad, y: y,
                                          width: size.width - 2 * pad, height: rowHeight),
                            choice: choice, font: rowFont)
        row.onClick = { take($0) }
        row.onStar = { starred($0) }
        root.addSubview(row)
        return y + rowHeight
    }

    // MARK: - The star

    /// **A star toggles a pin and leaves the menu up.** It is a change to what
    /// the menu *is*, not an answer to what it asks — Victor's ask spells that
    /// out (*"dacă debifezi steluța, fără să se închidă dialogul"*), and it is
    /// the only reading that works: the reason to pin a project is so that it is
    /// there the next time, and a star that dismissed the menu would make him
    /// re-open it to use what he had just arranged.
    ///
    /// It rebuilds rather than redraws, because the row it was clicked on has
    /// just moved to the other side of the line — which is the visible half of
    /// what a star means, and the only confirmation the gesture gets.
    private static func starred(_ choice: Choice) {
        PinnedProjects.toggle(choice.path)
        rendered = rows()
        rebuild()
    }

    /// Lay the panel out again around the same top-left corner, and give the
    /// clock back its full solid period.
    ///
    /// **The clock restarts because a star is engagement.** The fade exists to
    /// say the menu was optional and to get it out of the way of a sentence
    /// already being spoken; a hand that has just arranged the list is a hand
    /// about to use it, and taking the menu away three seconds after it opened
    /// would be taking it away mid-gesture. (Hovering already suspends the
    /// clock, so in practice this matters for the moment the pointer leaves.)
    private static func rebuild() {
        guard let p = panel else { return }
        let size = measure()
        p.contentView = build(size: size)
        p.setFrame(NSRect(x: anchor.x, y: anchor.y - size.height,
                          width: size.width, height: size.height),
                   display: true)
        // The hand is on the menu, so an in-flight fade has to be reversed as
        // well as re-timed — the same invalidate-then-reverse `setHovered` does.
        generation += 1
        p.alphaValue = 1
        timer?.invalidate()
        solidOver = false
        let t = Timer.scheduledTimer(withTimeInterval: solidSeconds, repeats: false) { _ in
            solidOver = true
            if !hovered { fade() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The glyph, drawn once per state and cached: a rebuild makes a new view
    /// for every row, and asking the symbol catalogue on each of them is work
    /// for a picture that never changes.
    ///
    /// **SF Symbols and not a Unicode star**, which is the call `StatusItem`
    /// already made for `mappin` / `mappin.slash`: this is an on/off *pair*, and
    /// a pair whose halves are drawn by two different hands reads as two
    /// unrelated marks. ★ and ☆ are also at the mercy of whatever face the
    /// system falls back to.
    static func star(filled: Bool) -> NSImage? {
        if let cached = starCache[filled] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: starSize - 2, weight: .regular)
        let image = NSImage(systemSymbolName: filled ? "star.fill" : "star",
                            accessibilityDescription: filled ? "pinned" : "not pinned")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        starCache[filled] = image
        return image
    }

    private static var starCache: [Bool: NSImage?] = [:]

    /// **Down and to the right of the pointer** — Victor's ask, 2026-09-06,
    /// replacing the down-and-*left* he asked for on 09-04. That one was picked
    /// as the quadrant the chip is never in, since the chip hangs below-right
    /// (`RelayWindow.anchorGap`) and a menu buried under a chip following the
    /// same cursor cannot be clicked. The overlap is real but harmless: the chip
    /// is a `.statusBar` window and this one now sits above every level in use,
    /// so it is the menu that covers the chip and the clicks land on the menu.
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

        // Left edge just right of the pointer; flipped left if it would hang off.
        var x = point.x + gap
        if x + size.width > visible.maxX { x = point.x - gap - size.width }
        x = max(visible.minX, min(x, visible.maxX - size.width))

        // Top edge just below the pointer; flipped above it if the rows would
        // run off the bottom of the screen.
        var y = point.y - gap - size.height
        if y < visible.minY { y = point.y + gap }
        y = max(visible.minY, min(y, visible.maxY - size.height))

        return NSPoint(x: x, y: y)
    }
}

// MARK: - The panel's content view

/// Watches the pointer for the menu's clock: entered/exited on the whole menu,
/// which is what suspends and releases the fade (`SpawnFolderMenu.setHovered`).
/// The rows' own tracking areas are about highlighting one folder; this one is
/// about the menu as a target being aimed at.
private final class HoverRoot: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
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
    var onStar: ((SpawnFolderMenu.Choice) -> Void)?

    init(frame: NSRect, choice: SpawnFolderMenu.Choice, font: NSFont) {
        self.choice = choice
        self.font = font
        super.init(frame: frame)
        let box = NSRect(x: frame.width - SpawnFolderMenu.rowInset - SpawnFolderMenu.starSize,
                         y: (frame.height - SpawnFolderMenu.starSize) / 2,
                         width: SpawnFolderMenu.starSize, height: SpawnFolderMenu.starSize)
        let star = StarButton(frame: box, pinned: choice.pinned)
        star.onClick = { [weak self] in
            guard let self else { return }
            self.onStar?(self.choice)
        }
        addSubview(star)
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
                                       options: [.mouseEnteredAndExited, .cursorUpdate,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// **A pointing hand over a row**, the same convention `inspect.js` follows
    /// in Chrome with `grab`: this is something to take, not text to select. The
    /// arrow says nothing, and over a row drawn with text in it the pointer can
    /// read as an I-beam — which is the one thing this panel never offers, since
    /// it never becomes key and there is nothing to type into.
    ///
    /// **Through the tracking area, not `resetCursorRects`.** Cursor rects are
    /// reset by the *key* window, and this panel is deliberately never one, so
    /// they would simply never fire. `.activeAlways` on a `.cursorUpdate` area is
    /// what makes a background app's cursor stick. The area covers the star as
    /// well, which is right — it is the other thing on the row that is clicked.
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    // The star sits inside the row, so the pointer resting on it is still on the
    // row — which is what keeps the highlight up while he reaches for it, and is
    // why these two are not `mouseEntered`-exclusive.
    override func mouseEntered(with event: NSEvent) { hot = true; setStarHot(true); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hot = false; setStarHot(false); needsDisplay = true }

    private func setStarHot(_ on: Bool) {
        for v in subviews { (v as? StarButton)?.rowHot = on }
    }

    // The app is `.accessory` and never active, so *every* click here is a first
    // mouse. Without this the first one would be spent activating nothing.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?(choice) }
}

// MARK: - The star

/// **The pin, as a thing to click.** A subview rather than a region tested
/// inside `FolderRow.mouseUp`, because the two clicks mean opposite things —
/// one opens a session and dismisses the menu, the other rearranges the menu and
/// keeps it up — and a hit test that got the boundary wrong by two points would
/// start a session he did not ask for. A subview cannot get it wrong: the window
/// server decides.
///
/// An unpinned row's star is **dim but always drawn**, never revealed on hover.
/// It is the only thing on this menu that has to be *discovered*, and a control
/// that appears when the pointer is already on it is one he has to find by
/// accident first.
private final class StarButton: NSView {
    private let pinned: Bool
    var onClick: (() -> Void)?
    /// Whether the row underneath is highlighted, which flips the ink the way
    /// the row's own text flips.
    var rowHot = false { didSet { if rowHot != oldValue { needsDisplay = true } } }

    init(frame: NSRect, pinned: Bool) {
        self.pinned = pinned
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = SpawnFolderMenu.star(filled: pinned) else { return }
        // Filled reads as a state and hollow as an offer, so the hollow one is
        // additionally held back in weight — otherwise five equally solid
        // outlines below the line look like five half-pinned projects.
        let ink: NSColor = rowHot ? .white
            : (pinned ? .labelColor : NSColor.labelColor.withAlphaComponent(0.35))
        // **The tint has to happen inside an image of its own.** A template
        // image drawn straight ignores the fill colour, and the obvious repair —
        // draw it, then `fill(using: .sourceAtop)` over the same rectangle —
        // paints the *whole box*, because the destination it composites against
        // is the row and the blur behind it, both opaque. The stars came out as
        // five solid squares. `NSImage(size:flipped:)` hands the handler a
        // transparent backing of its own, so `.sourceAtop` there can only reach
        // the glyph's own pixels.
        let box = NSRect(origin: .zero, size: bounds.size)
        let tinted = NSImage(size: box.size, flipped: false) { rect in
            image.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: box)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }
}

// MARK: - Looking at it

/// **Draw the menu into a PNG and quit** — `WT_SHOOT_MENU=/tmp/menu.png`.
///
/// This panel is `sharingType = .none`, like everything else this app puts near
/// the pointer, so **no screen capture can contain it**: the one route to seeing
/// a layout change was to make a spawn dictation and look with your own eyes,
/// inside three and a half seconds, at a menu that then faded. That is the same
/// problem `docs/overlay-states.html` was built to solve for the chip, and the
/// same answer — the real views drawing themselves — minus the catalogue, since
/// this one has a single layout rather than 36 states.
///
/// It paid for itself immediately: the star came out as five solid squares (see
/// `StarButton.draw`), which is invisible in code review and obvious in a
/// picture.
extension SpawnFolderMenu {
    static func shoot(to path: String) {
        rendered = rows()
        let size = measure()
        let root = build(size: size)
        root.wantsLayer = true
        guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
