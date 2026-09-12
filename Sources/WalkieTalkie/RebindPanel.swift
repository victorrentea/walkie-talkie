import AppKit

/// **The *Rebind to…* list, with a search field on top of it** — the small
/// window that comes up at the pointer when that row is picked from the menu.
///
/// **Why it stopped being an `NSMenu`** (2026-09-12). The pop-up was right for
/// as long as the answer was always in the twelve destinations the relay had
/// spoken to. Victor's ask: *"când apare ecranul de sesiuni recente … trebuie să
/// pot să încep să tastez direct"* — and a menu cannot take typing. AppKit's
/// menus have type-select, which matches the first letters of a row's title and
/// nothing else; what he types is a sentence he remembers from inside a session,
/// which is not in any title. So the list moved into a panel that owns its
/// keyboard.
///
/// **Two halves, and the first one still answers instantly.** Above the line are
/// the bindings — the same rows, in the same order, from `RebindHistory` — and
/// they filter on every keystroke with a substring match, no disk, no wait.
/// Below the line are sessions found by `SessionSearch` in Claude Code's own
/// transcripts, which costs about a second, so it runs on a pause rather than on
/// a keystroke (`debounce`). The fast half is never made to wait for the slow
/// one: that is the whole layout of this file.
///
/// **It becomes key without activating the app**, `.nonactivatingPanel` and
/// `canBecomeKey`, exactly as `RelayPanel` does while the transcript is being
/// edited — the terminal behind it stays frontmost and takes the keyboard
/// straight back when the panel closes.
final class RebindPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {

    // MARK: - What a row is

    /// One line of the list, already decided: drawing does not go looking for
    /// anything, and neither does the ⏎ that fires it.
    struct Row {
        enum Kind { case destination, session }
        let kind: Kind
        /// Handed to `onRebind`. nil on a row that cannot be bound — a closed
        /// window, an IDE panel, a session whose tab has since been reused.
        let tty: String?
        let icon: NSImage?
        let title: String
        let subtitle: String
        let enabled: Bool
        /// Everything this row can be matched against by the instant filter —
        /// title and subtitle, lowercased once, here rather than per keystroke.
        let haystack: String
        /// The words to highlight inside `subtitle`, i.e. the query that found it.
        var terms: [String] = []
        /// **The session to reopen, for a row whose terminal is gone** — id and
        /// the folder it belongs to. Set only when there is no tty to bind to and
        /// the folder still exists; ⏎ then spawns `claude --resume` instead of
        /// rebinding. See `hint`.
        var resume: (session: String, cwd: String)?
        /// **What ⏎ would do to this row, in three words**, drawn on the selected
        /// row only. Victor's ask when the resume was offered: *"cu un visual
        /// hint, să ofere și asta"* — an action nothing on screen mentions is an
        /// action nobody uses, and a hint repeated down twenty-five rows is
        /// noise. The selected row is the one ⏎ is about.
        var hint: String? { resume != nil ? "⏎ resume it" : (enabled ? "⏎ bind" : nil) }
    }

    // MARK: - The pause before the disk is touched

    /// **370 ms.** Victor's number (*"live filtering la taste, cu [debounce]
    /// când mă [opresc] 370 … sau 500"*), and the low end of the two on purpose:
    /// the scan it gates is around a second, so the pause is what keeps four
    /// keystrokes from starting four scans, not what keeps the panel calm. The
    /// destinations above the line do not wait for it at all.
    private static let debounce: TimeInterval = 0.37

    /// Below two characters there is no query, only a corpus: `a` matches every
    /// session ever and the scan spends a second proving it.
    private static let minimumQuery = 2

    // MARK: - Wiring

    /// The destinations, asked for at the instant the panel opens — the same
    /// closure the menu used.
    var rows: (() -> [RebindHistory.Row])?
    /// `ttysNNN` → the title that tab is showing now, one AppleScript for the
    /// machine. Read once per opening: it is what says whether a remembered tty
    /// is still a window, and whether it is still *this* session's window.
    var liveTitles: (() -> [String: String])?
    /// Picked a row: point the relay at that tty.
    var onRebind: ((String) -> Void)?
    /// Something to say on the overlay, for the moment between ⏎ and a window
    /// appearing.
    var onMessage: ((String) -> Void)?
    /// **⏎ on a session whose terminal is gone**: open it again with
    /// `claude --resume <id>` in the folder it belongs to.
    var onResume: ((_ session: String, _ cwd: String) -> Void)?

    // MARK: - State

    private var panel: KeyPanel?
    private let field = NSTextField()
    private let spinner = NSProgressIndicator()
    private let countLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let listView = FlippedView()
    private let scroll = NSScrollView()

    /// The bindings as the panel was opened, unfiltered.
    private var destinations: [Row] = []
    /// The sessions the running scan has found so far, in the order they arrived.
    private var sessions: [Row] = []
    /// What is actually on screen — destinations that match, then sessions.
    private var shown: [Row] = []
    private var selected = 0

    private var live: [String: String] = [:]
    private var debounceTimer: Timer?
    private var search: SessionSearch?
    private var searching = false
    private var query = ""
    /// A panel that has never been key must not close on *not* being key.
    private var wasKey = false
    private var clickMonitor: Any?

    private let rowHeight: CGFloat = 46
    private let width: CGFloat = 660
    private let visibleRows: CGFloat = 7

    // MARK: - Opening

    /// **Put the panel up at the pointer and take the keyboard.**
    ///
    /// Called dispatched from the menu row, for the reason the pop-up was
    /// dispatched before it: the click that asks for this is still closing the
    /// menu it came from.
    /// `query` is only ever non-empty from `POST /test/rebind-panel`: a panel
    /// that comes up with a search already in it is how the second half of this
    /// file is reachable from a desk.
    func show(at point: NSPoint, query prefill: String = "") {
        if panel != nil { close(); return }          // the row is a toggle

        // **The tty is kept even on a row that cannot be clicked** — the one
        // already bound, a window since closed. `enabled` is what ⏎ and the
        // click test, while the tty is also what tells a session found in the
        // transcripts that it is already on this list: drop it from the row and
        // the bound destination comes back a second time, as a search hit.
        destinations = (rows?() ?? []).map { row in
            Row(kind: .destination, tty: row.tty,
                icon: Self.appIcon(bundleID: row.bundleID),
                title: row.title, subtitle: "", enabled: row.enabled,
                haystack: row.title.lowercased())
        }
        live = liveTitles?() ?? [:]
        sessions = []
        query = ""
        selected = 0
        wasKey = false
        // The field and its readout are the same objects every time this opens —
        // left as they were, the panel comes up showing the last search and a
        // count that belongs to a list it is not showing.
        field.stringValue = ""
        setSearching(false)

        let panel = build()
        self.panel = panel
        place(panel, near: point)
        rebuild()

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        if !prefill.isEmpty {
            field.stringValue = prefill
            queryChanged()
        }
        // A click anywhere else means he is done with the panel — the same
        // dismissal a menu has, which is the thing this replaced.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.close()
        }
    }

    func close() {
        debounceTimer?.invalidate(); debounceTimer = nil
        search?.cancel(); search = nil
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
    }

    var isOpen: Bool { panel != nil }

    // MARK: - Building the window

    private func build() -> KeyPanel {
        let height = 58 + 1 + rowHeight * visibleRows + 30
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        // **`.menu`, not `.hudWindow`.** A HUD is a dark slab in both
        // appearances, while `labelColor` and its dimmer siblings follow the
        // *system* one — so in light mode the rows came out dark grey on dark
        // grey, which is the contrast of a watermark (seen on the first build,
        // 2026-09-12). The menu material is the one that moves with the
        // appearance, and it is also what this panel replaced.
        blur.material = .menu
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        panel.contentView = blur

        // --- the field ---------------------------------------------------
        let glass = NSTextField(labelWithString: "🔎")
        glass.font = .systemFont(ofSize: 15)
        glass.frame = NSRect(x: 16, y: height - 42, width: 24, height: 22)
        blur.addSubview(glass)

        field.frame = NSRect(x: 44, y: height - 44, width: width - 44 - 130, height: 26)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = "Search what you or Claude said…"
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        blur.addSubview(field)

        spinner.frame = NSRect(x: width - 38, y: height - 40, width: 18, height: 18)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        blur.addSubview(spinner)

        countLabel.frame = NSRect(x: width - 200, y: height - 38, width: 152, height: 16)
        countLabel.alignment = .right
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor
        blur.addSubview(countLabel)

        let rule = NSView(frame: NSRect(x: 0, y: height - 58, width: width, height: 1))
        rule.wantsLayer = true
        rule.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        rule.autoresizingMask = [.width]
        blur.addSubview(rule)

        // --- the list ------------------------------------------------------
        scroll.frame = NSRect(x: 0, y: 30, width: width, height: rowHeight * visibleRows)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        listView.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        scroll.documentView = listView
        blur.addSubview(scroll)

        // --- the footer ----------------------------------------------------
        hintLabel.frame = NSRect(x: 16, y: 8, width: width - 32, height: 16)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        blur.addSubview(hintLabel)

        return panel
    }

    /// Under the pointer, and kept whole on the screen it is on — the opposite
    /// of what the chip wants, and the reason this panel does not borrow
    /// `RelayPanel`: a list that is half off the edge is a list with rows that
    /// cannot be clicked.
    private func place(_ panel: NSPanel, near point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        var origin = NSPoint(x: point.x - 40, y: point.y - size.height - 8)
        origin.x = min(max(origin.x, area.minX + 12), area.maxX - size.width - 12)
        origin.y = min(max(origin.y, area.minY + 12), area.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Typing

    func controlTextDidChange(_ obj: Notification) { queryChanged() }

    private func queryChanged() {
        query = field.stringValue.trimmingCharacters(in: .whitespaces)

        // **The instant half.** Substring over the rows already in hand; it runs
        // on the keystroke because it costs nothing and because a list that does
        // not move while he types is a list that feels broken.
        sessions = []
        selected = 0
        rebuild()

        // **The half that reads the disk** waits for him to stop.
        debounceTimer?.invalidate()
        search?.cancel(); search = nil
        guard query.count >= Self.minimumQuery else {
            setSearching(false)
            return
        }
        setSearching(true)          // the spinner starts on the keystroke, so the
                                    // pause reads as work rather than as nothing
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounce, repeats: false) {
            [weak self] _ in self?.startSearch()
        }
    }

    /// Keys the field does not own: the list's.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            activate(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        case #selector(NSResponder.scrollPageDown(_:)), #selector(NSResponder.pageDown(_:)):
            move(by: Int(visibleRows)); return true
        case #selector(NSResponder.scrollPageUp(_:)), #selector(NSResponder.pageUp(_:)):
            move(by: -Int(visibleRows)); return true
        default:
            return false
        }
    }

    private func move(by delta: Int) {
        guard !shown.isEmpty else { return }
        selected = min(max(0, selected + delta), shown.count - 1)
        draw()
        reveal(selected)
    }

    /// ⏎, or a click on a row.
    private func activate(_ index: Int? = nil) {
        let i = index ?? selected
        guard shown.indices.contains(i) else { return }
        let row = shown[i]
        // **Reopening comes first**, because a row only carries a resume when
        // there was no tty to prefer: the two are never both true.
        if let resume = row.resume {
            close()
            onResume?(resume.session, resume.cwd)
            return
        }
        guard let tty = row.tty, row.enabled else { return }
        close()
        onRebind?(tty)
    }

    // MARK: - Searching

    private func startSearch() {
        let asked = query
        setSearching(true)
        search = SessionSearch.run(query: asked, onRow: { [weak self] hit in
            guard let self = self, self.query == asked else { return }
            guard let row = self.row(for: hit, terms: asked.lowercased().split(separator: " ").map(String.init))
            else { return }
            // Newest first is the helper's order and the order they arrive in;
            // appending keeps the row he is looking at where it was.
            self.sessions.append(row)
            self.rebuild()
        }, onDone: { [weak self] _ in
            guard let self = self, self.query == asked else { return }
            self.setSearching(false)
            self.rebuild()
        })
        if search == nil { setSearching(false) }
    }

    private func setSearching(_ on: Bool) {
        searching = on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        refreshCount()
    }

    private func refreshCount() {
        if searching {
            countLabel.stringValue = sessions.isEmpty
                ? "searching your sessions…"
                : "\(sessions.count) session\(sessions.count == 1 ? "" : "s")…"
        } else if query.count >= Self.minimumQuery {
            countLabel.stringValue = sessions.isEmpty ? "no session said that" :
                "\(sessions.count) session\(sessions.count == 1 ? "" : "s")"
        } else {
            countLabel.stringValue = ""
        }
    }

    /// A hit becomes a row — which is where it is decided whether the tab that
    /// ran that session still exists.
    private func row(for hit: SessionSearch.Hit, terms: [String]) -> Row? {
        let tty = liveTTY(for: hit)
        // A session already listed above the line as a destination is not shown
        // twice; the binding row is the better of the two, since it knows when
        // the relay last spoke to it.
        if let tty, destinations.contains(where: { $0.tty == tty }) { return nil }

        // **A closed window is no longer a dead end.** The row knows the session
        // id and the folder, and `claude --resume` is one spawn away — so the
        // question is only whether the folder is still there to resume *in*: a
        // session id is scoped to it, and from anywhere else the id is not found.
        let resumable = tty == nil && !hit.cwd.isEmpty
            && FileManager.default.fileExists(atPath: hit.cwd)

        let who = hit.role == "me" ? "you" : "claude"
        let name = hit.title.isEmpty ? hit.label : hit.title
        var title = name
        if !hit.title.isEmpty { title += "  —  \(hit.label)" }
        title += "  ·  \(RebindHistory.elapsed(since: hit.when))"
        if tty == nil { title += resumable ? "  ·  closed" : "  ·  window closed" }
        let subtitle = "\(who): \(hit.snippet)"
        var row = Row(kind: .session, tty: tty, icon: Self.folderIcon(hit.cwd),
                      title: title, subtitle: subtitle,
                      enabled: tty != nil || resumable,
                      haystack: (title + " " + subtitle).lowercased(), terms: terms)
        if resumable { row.resume = (session: hit.session, cwd: hit.cwd) }
        return row
    }

    /// **Is this session still in the tab it last reported?**
    ///
    /// The tty comes from the cache Victor's `terminal-title.sh` hook keeps, and
    /// a tty is recycled the moment a tab is reused — so the answer is not "does
    /// `ttys016` exist" but "is `ttys016` still showing *this* session". What
    /// makes that answerable for free is that the same hook writes the session's
    /// own title into that tab: `✳ <folder> — <title>`, from the same two
    /// transcript records the search reads. Same string, two places, and the
    /// join between them.
    ///
    /// Matching on the folder alone is the fallback, for a session whose title
    /// was never generated. It can be wrong — two sessions in one repo — which
    /// is why the title is tried first and why a rebind is a reversible thing to
    /// get wrong.
    private func liveTTY(for hit: SessionSearch.Hit) -> String? {
        if let device = hit.tty {
            let short = (device as NSString).lastPathComponent
            if let shown = live[short], hit.ttyOwner || matches(shown, hit) {
                return device
            }
        }
        // No claim on file, or the claim was a former tenant's: one pass over the
        // live titles for a tab that is showing exactly this session's name.
        if !hit.title.isEmpty,
           let found = live.first(where: { $0.value.contains(hit.title) }) {
            return "/dev/" + found.key
        }
        return nil
    }

    /// **The title as corroboration, never as the only witness.** The hook
    /// refreshes a tab's title on the session's own turns, so a tab whose agent
    /// has been quiet since before the last `/rename` still shows the name of
    /// something else — measured here on 2026-09-12: `ttys016` was running
    /// *Lightning circle around mouse* and reading `✳ victor-vibe-board — Tablet
    /// star icon`, three sessions out of date. That is why `ttyOwner` decides and
    /// this only confirms.
    ///
    /// **The folder is not evidence, and briefly was.** Matching a tab on the
    /// repo name alone calls every session of a repo live as long as *any* tab is
    /// open in it — which pointed a bind at a stranger's window and, worse,
    /// silently swallowed the row: a hit that claims a tty already on the list
    /// above is dropped as a duplicate, so the session he searched for vanished
    /// instead of offering to reopen itself. A closed window is no longer a dead
    /// end, so there is nothing left to buy with a guess.
    private func matches(_ shownTitle: String, _ hit: SessionSearch.Hit) -> Bool {
        !hit.title.isEmpty && shownTitle.contains(hit.title)
    }

    // MARK: - The list

    private func rebuild() {
        let needle = query.lowercased()
        let terms = needle.split(separator: " ").map(String.init)
        let matching = terms.isEmpty ? destinations
            : destinations.filter { row in terms.allSatisfy { row.haystack.contains($0) } }
        shown = matching.map { row in
            var row = row
            row.terms = terms
            return row
        } + sessions
        if selected >= shown.count { selected = max(0, shown.count - 1) }
        refreshCount()
        draw()
    }

    private func draw() {
        listView.subviews.forEach { $0.removeFromSuperview() }
        let height = max(scroll.frame.height, CGFloat(shown.count) * rowHeight)
        listView.frame = NSRect(x: 0, y: 0, width: scroll.frame.width, height: height)

        for (i, row) in shown.enumerated() {
            let view = RowView(frame: NSRect(x: 0, y: CGFloat(i) * rowHeight,
                                             width: scroll.frame.width, height: rowHeight))
            view.row = row
            view.isSelected = (i == selected)
            view.onClick = { [weak self] in self?.activate(i) }
            view.onHover = { [weak self] in
                guard let self = self, self.selected != i else { return }
                self.selected = i
                self.draw()
            }
            listView.addSubview(view)
        }

        if shown.isEmpty {
            let empty = NSTextField(labelWithString: query.isEmpty
                ? "Nothing bound yet"
                : (searching ? "Reading your session journals…" : "Nothing matches “\(query)”"))
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .tertiaryLabelColor
            empty.frame = NSRect(x: 18, y: 14, width: width - 36, height: 20)
            listView.addSubview(empty)
        }

        // The footer says what ⏎ does **to the row he is on**, which is not one
        // sentence any more: most rows are a terminal to point at, and a session
        // whose window is gone is a terminal to open.
        let action = shown.indices.contains(selected) && shown[selected].resume != nil
            ? "⏎ reopen it with claude --resume"
            : "⏎ bind"
        hintLabel.stringValue = query.isEmpty
            ? "Type to search every message you and Claude exchanged   ·   ↑↓ choose   ·   \(action)   ·   esc close"
            : "↑↓ choose   ·   \(action)   ·   esc close"
    }

    private func reveal(_ index: Int) {
        let rect = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: 10, height: rowHeight)
        listView.scrollToVisible(rect)
    }

    // MARK: - Closing

    func windowDidResignKey(_ notification: Notification) {
        // It only counts once the panel has had the keyboard: the notification
        // also fires on the way in, before it ever becomes key.
        guard wasKey else { return }
        close()
    }

    func windowDidBecomeKey(_ notification: Notification) { wasKey = true }

    // MARK: - Icons

    /// The destination app's own icon — a Terminal tab, a VS Code panel and an
    /// IntelliJ panel are three things to be pointed at, and the folder name in
    /// the row is often the same for all three.
    static func appIcon(bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 18, height: 18)
        return icon
    }

    /// A session row is a folder, not an app: what it names is a repo. The cwd
    /// comes off the transcript's own records, so a project outside `~/workspace`
    /// gets its icon too; the speech bubble is for a folder that has since been
    /// deleted or renamed.
    private static func folderIcon(_ path: String) -> NSImage? {
        let icon = !path.isEmpty && FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path)
            : NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        icon?.size = NSSize(width: 18, height: 18)
        return icon
    }
}

// MARK: - One row

/// A row draws itself: two lines, an icon, and the searched words picked out of
/// the second one.
private final class RowView: NSView {

    var row: RebindPanel.Row? { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?

    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let row = row else { return }

        // **A grey plate and an accent bar, not a blue row.** A tinted fill under
        // the text is what a table view does and it is wrong here: the second
        // line of a row is a sentence in `secondaryLabelColor`, and over accent
        // blue it goes to the contrast of a watermark (measured on the first
        // build, 2026-09-12). The plate is the label colour itself, so the text
        // on it keeps exactly the contrast it has everywhere else.
        if isSelected {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 3), xRadius: 7, yRadius: 7).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 6, width: 3, height: bounds.height - 12),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }

        row.icon?.draw(in: NSRect(x: 16, y: 6, width: 18, height: 18))

        // A row that cannot be clicked is drawn dim rather than hidden — the
        // menu's rule, kept: *do not hide a row the app cannot act on, grey it*.
        // One rung down for a row that cannot be clicked, and no further:
        // `quaternaryLabelColor` is a separator's colour, and a sentence set in
        // it is not dimmed, it is gone.
        let strong: NSColor = row.enabled ? .labelColor : .secondaryLabelColor
        let weak: NSColor = row.enabled ? .secondaryLabelColor : .tertiaryLabelColor

        // **One line each, ellipsised.** A title is `folder@branch · ttys016 ·
        // 3 min ago` and a snippet is a sentence; both are longer than the panel
        // at times, and text that simply stops at the edge reads as a rendering
        // fault rather than as more text.
        let clip = NSMutableParagraphStyle()
        clip.lineBreakMode = .byTruncatingTail

        // **The hint, on this row only.** Drawn before the title so the title can
        // be given the width that is left: a hint the title runs under is worse
        // than no hint, and `…` in the right place is what says a row was cut.
        var reserved: CGFloat = 0
        if isSelected, let hint = row.hint {
            let text = NSAttributedString(string: hint, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
            ])
            let size = text.size()
            reserved = size.width + 16
            text.draw(at: NSPoint(x: bounds.width - 16 - size.width,
                                  y: (bounds.height - size.height) / 2))
        }

        let title = NSMutableAttributedString(string: row.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: strong,
            .paragraphStyle: clip,
        ])
        // A row with nothing under it is centred instead of hanging from the top:
        // the destinations have no second line, and half of a two-line row with
        // the bottom half empty reads as a row that failed to load.
        title.draw(in: NSRect(x: 44, y: row.subtitle.isEmpty ? 14 : 5,
                              width: bounds.width - 60 - reserved, height: 17))

        guard !row.subtitle.isEmpty else { return }
        let sub = NSMutableAttributedString(string: row.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: weak,
            .paragraphStyle: clip,
        ])
        // The words he typed, picked out of the sentence they were found in —
        // the row's whole job is to let him recognise the session without
        // reading it, and the match is what he is scanning for.
        let low = row.subtitle.lowercased() as NSString
        for term in row.terms where !term.isEmpty {
            var from = 0
            while from < low.length {
                let range = low.range(of: term, options: [],
                                      range: NSRange(location: from, length: low.length - from))
                guard range.location != NSNotFound else { break }
                sub.addAttributes([.foregroundColor: strong,
                                   .font: NSFont.systemFont(ofSize: 11.5, weight: .bold)],
                                  range: range)
                from = range.location + max(1, range.length)
            }
        }
        sub.draw(in: NSRect(x: 44, y: 24, width: bounds.width - 60 - reserved, height: 16))
    }
}

// MARK: - Plumbing

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A panel that takes the keyboard without activating the app — `RelayPanel`'s
/// trick, minus the switch: this one is only ever on screen to be typed into.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
