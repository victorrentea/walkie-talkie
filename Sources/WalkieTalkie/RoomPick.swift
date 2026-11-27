import AppKit

/// **🎙️ What the room just said, as a ⚡ question's topic** (2026-11-25).
///
/// Victor: *"când deschid modul întrebare, să apară o modală care să-mi permită
/// să aleg 30 s sau 60 s din transcrierea continuă din spate, în care să
/// identifice o întrebare sau fact să verifice și să considere asta tema de
/// research pentru întrebare. Poate întreba victor-mac să obțină această
/// transcriere."*
///
/// Victor Mac transcribes the room all day; `GET 127.0.0.1:55123/transcript/tail
/// ?seconds=N` (`RecentSpeech` there, loopback only) answers its last N seconds.
/// A ⚡ question opened by 🔼 ← asks for both windows at once, **as they were
/// before he started speaking**, and `RoomPick` offers them: *Just heard* /
/// *Last 30 s* / *Last 60 s* (15 s since 2026-11-27, Victor: *"only pick the last
/// fifteen seconds … when I ask a question about the last spoken things"*). A click makes that window the research topic and **ends the
/// question** (as 🔼 would): whatever he said goes along as his question about
/// it; said nothing, the window alone is checked. It replaced Victor Mac' 🔬
/// Fact-check menu rows, which pushed the same window to `POST /ask`.
///
/// No click: the modal fades out as the spawn menu does (3.5 s solid, 1 s fade,
/// held while the pointer is on it) or goes with the question, and nothing changes.
/// `WT_ROOM_PICK=0` turns the offer off.
///
/// **🎙️ Just heard** (2026-11-27, Victor: *"The option 15s in question mode should
/// be called 'just heard' and grabs the transcript until the exact moment of the
/// click — this might mean waiting a bit to transcribe it … very important in the
/// prompt: only pick the last topic, question, idea, fact discussed"*). The 15 s
/// row is no longer the window as it was when the question opened: its click
/// starts `RoomSettle`, which waits for whisper to write what was said up to the
/// click, and the question goes with that window, its prompt naming only the last
/// topic.
struct RoomTranscript: Equatable {
    let seconds: Int
    /// `[HH:MM] words` lines, oldest first — what the model reads.
    let transcript: String
    /// The words alone — the header's quote.
    let speech: String
    let words: Int

    static let port = 55123
    /// Shortest first — the modal's rows top-down.
    static let windows = [15, 30, 60]
    /// The *Just heard* window: read again, settled, after the click.
    static let justHeard = 15
    /// Fewer words than this is not a discussion — the window is not offered.
    static let minWords = 5

    var usable: Bool { words >= Self.minWords }
    var isJustHeard: Bool { seconds == Self.justHeard }

    /// The row's and the flash's name.
    static func label(_ seconds: Int) -> String { seconds == justHeard ? "Just heard" : "Last \(seconds) s" }
    /// The pop-up header's tag.
    var tag: String { isJustHeard ? "Just heard" : "\(seconds) s" }

    /// Pure: Victor Mac' JSON → a window; nil for anything else.
    static func parse(_ data: Data) -> RoomTranscript? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              o["ok"] as? Bool == true,
              let seconds = o["seconds"] as? Int,
              let transcript = o["transcript"] as? String else { return nil }
        return RoomTranscript(seconds: seconds, transcript: transcript,
                              speech: o["speech"] as? String ?? "", words: o["words"] as? Int ?? 0)
    }

    /// Every window at once; `done` on main with the ones that answered.
    static func fetch(_ windows: [Int] = windows, timeout: TimeInterval = 1.5,
                      done: @escaping ([Int: RoomTranscript]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var got: [Int: RoomTranscript] = [:]
        for s in windows {
            guard let url = URL(string: "http://127.0.0.1:\(port)/transcript/tail?seconds=\(s)") else { continue }
            group.enter()
            URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: timeout)) { data, response, _ in
                defer { group.leave() }
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let room = parse(data) else { return }
                lock.lock(); got[s] = room; lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { done(got) }
    }

    /// The last `limit` characters said, `…` in front when cut.
    func quote(limit: Int = 60) -> String {
        let flat = speech.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.count > limit ? "…" + String(flat.suffix(limit)).trimmingCharacters(in: .whitespaces) : flat
    }

    /// The reply pop-up's header: his words when he said any, else the quote —
    /// so he can tell at a glance what is being checked.
    func header(asked: String?) -> String {
        let said = asked?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return said.isEmpty ? "🎙️ \(tag) «\(quote())»" : "\(said) · 🎙️ \(tag)"
    }

    /// What the quick model is asked. Its system prompt says "be brief, no lists
    /// unless asked" — so this asks for the list, one line per claim.
    func prompt(question: String?) -> String {
        if isJustHeard { return justHeardPrompt(question: question) }
        let head = """
        This discussion was just overheard in a live training room — its last \(seconds) seconds, \
        transcribed automatically, so some words may be misheard.

        \(transcript)
        """
        let q = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !q.isEmpty else {
            return head + """


            Find in it the question asked, or the facts claimed, and anything left unknown or \
            asked without an answer: that is the topic to research. Check them and answer as you \
            would answer a question: one short line each — ✅ true, ❌ false or ❓ unsure — then \
            the correct fact. Plain text, in the language of the discussion.
            """
        }
        return head + """


        My question, with that discussion as its topic:
        \(q)

        Answer my question. Where the discussion claims facts my question is about, check them: \
        one short line each — ✅ true, ❌ false or ❓ unsure — then the correct fact. Plain text, \
        in the language of my question.
        """
    }

    /// *Just heard*: the room's last moments up to his click — and of what was said
    /// in them, only the **last** topic counts (Victor: *"only pick the last topic,
    /// question, idea, fact discussed. Over stuff discussed earlier"*).
    private func justHeardPrompt(question: String?) -> String {
        let head = """
        This was just overheard in a live training room — its last moments, up to the instant I \
        clicked, transcribed automatically, so some words may be misheard. It may touch several \
        topics.

        \(transcript)

        Take ONLY the last topic discussed — the last question asked, idea raised or fact claimed, \
        at the very end. Ignore everything said earlier about other things, even if it fills most \
        of the transcript.
        """
        let q = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !q.isEmpty else {
            return head + """


            That last topic is what to research. Answer it as you would answer a question; where \
            it claims facts, check them: one short line each — ✅ true, ❌ false or ❓ unsure — then \
            the correct fact. Plain text, in the language of the discussion.
            """
        }
        return head + """


        My own words below may also be heard at the very end of the transcript: the topic is \
        what was discussed just before them.

        My question, about that last topic:
        \(q)

        Answer my question. Where that last topic claims facts my question is about, check them: \
        one short line each — ✅ true, ❌ false or ❓ unsure — then the correct fact. Plain text, \
        in the language of my question.
        """
    }
}

/// **🎙️ Just heard: the room up to the click** (2026-11-27). Whisper writes a line
/// several seconds after the words were said (a pause flushes it in ~0.6 s + ≤ 5 s
/// of batch + ~1 s of inference; non-stop talk waits for the 12 s chunk), so a
/// click on *Just heard* asks Victor Mac again every `poll` until the window has
/// stopped changing — the rule of Victor Mac's ⌘⌃V picker (`TranscriptSettlePolicy`):
/// at least `minWait`, then `quietSeconds` with no new line; `maxWait` gives up
/// and takes what is there. It starts at the click, so the wait runs while his
/// own words are still being transcribed; the question then `wait`s for it.
enum RoomSettle {
    static let minWait: TimeInterval = 8
    static let quietSeconds: TimeInterval = 2.5
    static let maxWait: TimeInterval = 18
    static let poll: TimeInterval = 0.35

    enum Decision: Equatable { case wait, ready, timedOut }

    /// Pure. `sinceChange` is seeded with `elapsed`, so a window that never
    /// changes (nobody spoke, whisper down) settles at the floor.
    static func decide(elapsed: TimeInterval, sinceChange: TimeInterval) -> Decision {
        if elapsed >= maxWait { return .timedOut }
        if elapsed < minWait { return .wait }
        return sinceChange >= quietSeconds ? .ready : .wait
    }

    private static var generation = 0
    private static var started: CFAbsoluteTime = 0
    private static var lastChange: CFAbsoluteTime = 0
    private static var lastText: String?
    private static var latest: RoomTranscript?
    private static var finished = true
    private static var waiters: [(RoomTranscript?) -> Void] = []

    /// At the click (main).
    static func start(_ seconds: Int = RoomTranscript.justHeard) {
        generation += 1
        started = CFAbsoluteTimeGetCurrent()
        lastChange = started
        lastText = nil
        latest = nil
        finished = false
        waiters = []
        tick(generation, seconds)
    }

    /// `done` on main with the settled window (nil if Victor Mac never answered);
    /// at once when it already settled.
    static func wait(_ done: @escaping (RoomTranscript?) -> Void) {
        if finished { done(latest) } else { waiters.append(done) }
    }

    private static func tick(_ gen: Int, _ seconds: Int) {
        RoomTranscript.fetch([seconds], timeout: 1) { got in
            guard gen == generation, !finished else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if let r = got[seconds] {
                // The first answer is the baseline; a later different one is a new line.
                if lastText != nil, r.transcript != lastText { lastChange = now }
                lastText = r.transcript
                latest = r
            }
            let elapsed = now - started
            switch decide(elapsed: elapsed, sinceChange: now - lastChange) {
            case .wait:
                DispatchQueue.main.asyncAfter(deadline: .now() + poll) { tick(gen, seconds) }
            case let d:
                Log.info("🎙️ Just heard \(d == .ready ? "settled" : "gave up waiting") after \(String(format: "%.1f", elapsed)) s — \(latest?.words ?? 0) words")
                finished = true
                let w = waiters
                waiters = []
                w.forEach { $0(latest) }
            }
        }
    }
}

/// **The modal — the spawn menu's twin** (2026-11-25, Victor: *"the modal showing
/// on question mode should look just like the one to open a new session. and
/// should fade out at the same delay"*). So it is built from `SpawnFolderMenu`'s
/// own parts rather than copies of them: the HUD-blur surface (`addSurface`), the
/// secondary 12 pt header, 17 pt rows `rowHeight` tall lit in the selection
/// colour under the hand, the hand cursor over the whole panel, and the same
/// place — down and to the right of the pointer (`SpawnFolderMenu.origin`).
/// The rows: *🎙️ Just heard* / *🎙️ Last 30 s* / *🎙️ Last 60 s*, each with its word count; a window
/// with too few words is dimmed and does not click. Under them, the quote of the
/// longer window, in the header's ink.
///
/// **The same clock**: `SpawnFolderMenu.solidSeconds` solid, then a linear fade
/// over `fadeSeconds`; the pointer on it holds it (mid-fade included — a click
/// still lands while it fades) and leaving lets the fade run. Faded out, the
/// question goes on without a topic, as if never offered. Never key, never
/// activating — the dictation keeps the keyboard and the front app its focus.
enum RoomPick {
    private static var panel: NSPanel?
    private static var rooms: [Int: RoomTranscript] = [:]
    private static var onPick: ((RoomTranscript) -> Void)?
    private static var token = 0
    /// The solid period; then `watch` follows the pointer every 0.1 s.
    private static var timer: Timer?
    private static var watch: Timer?
    private static var solidOver = false
    private static var fading = false
    /// Bumped by every fade and un-fade, so a stale fade's completion cannot
    /// hide a panel the hand has made solid again.
    private static var generation = 0

    static var isOpen: Bool { panel != nil }
    static var frame: NSRect? { panel?.frame }
    static var offered: [Int: RoomTranscript] { rooms }

    static var enabled: Bool { ProcessInfo.processInfo.environment["WT_ROOM_PICK"] != "0" }

    /// Ask Victor Mac, then show the modal near `point` if any window has words
    /// and `still()` says the question is still open. `pick` on main.
    static func offer(at point: NSPoint, still: @escaping () -> Bool, pick: @escaping (RoomTranscript) -> Void) {
        guard enabled else { return }
        close()
        token += 1
        let mine = token
        let asked = CFAbsoluteTimeGetCurrent()
        RoomTranscript.fetch { got in
            let ms = Int((CFAbsoluteTimeGetCurrent() - asked) * 1000)
            guard mine == token, still() else { return }
            guard got.values.contains(where: \.usable) else {
                Log.info("🎙️ no room transcript to offer (\(got.isEmpty ? "Victor Mac did not answer" : "fewer than \(RoomTranscript.minWords) words"), \(ms) ms)")
                return
            }
            let counts = RoomTranscript.windows.map { "\($0) s: \(got[$0]?.words ?? 0) words" }.joined(separator: ", ")
            Log.info("🎙️ the room's last seconds offered for the ⚡ question — \(counts) (\(ms) ms)")
            show(got, at: point, pick: pick)
        }
    }

    /// A click (or the desk route): that window, if offered and usable.
    @discardableResult
    static func choose(_ seconds: Int) -> Bool {
        guard let room = rooms[seconds], room.usable, let pick = onPick else { return false }
        close()
        if room.isJustHeard { RoomSettle.start(seconds) }
        pick(room)
        return true
    }

    static func close() {
        token += 1
        generation += 1
        timer?.invalidate()
        timer = nil
        watch?.invalidate()
        watch = nil
        solidOver = false
        fading = false
        if panel != nil { NSCursor.arrow.set() }
        panel?.orderOut(nil)
        panel = nil
        rooms = [:]
        onPick = nil
    }

    /// Desk route: the modal for these windows, drawn into a PNG, never on a screen.
    /// The blur has nothing behind it off screen, so a dark HUD-like ground
    /// stands in for it.
    static func snapshot(_ got: [Int: RoomTranscript], to url: URL) -> Bool {
        let view = RoomPickView(rooms: got)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.16, alpha: 1)
        window.contentView = view
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    private static func show(_ got: [Int: RoomTranscript], at point: NSPoint, pick: @escaping (RoomTranscript) -> Void) {
        rooms = got
        onPick = pick
        let view = RoomPickView(rooms: got)
        let p = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // In the room's share like the spawn menu; out of the shutter's frames.
        p.sharingType = ReplyPanel.capturable ? .readOnly : .none
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.contentView = view
        p.setFrameOrigin(SpawnFolderMenu.origin(for: view.frame.size, at: point))
        p.alphaValue = 1
        p.orderFrontRegardless()
        panel = p
        startClock()
    }

    // MARK: - The clock, as the spawn menu's

    private static func startClock() {
        timer?.invalidate()
        watch?.invalidate()
        watch = nil
        solidOver = false
        fading = false
        let t = Timer.scheduledTimer(withTimeInterval: SpawnFolderMenu.solidSeconds, repeats: false) { _ in
            solidOver = true
            let w = Timer(timeInterval: 0.1, repeats: true) { _ in followPointer() }
            RunLoop.main.add(w, forMode: .common)
            watch = w
            followPointer()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func pointerOnPanel() -> Bool {
        guard let p = panel else { return false }
        return NSMouseInRect(NSEvent.mouseLocation, p.frame, false)
    }

    /// The hand arriving or leaving (the view's tracking area), and every 0.1 s
    /// past the solid period: on it → solid, off it → fading.
    static func followPointer() {
        guard panel != nil else { return }
        let on = pointerOnPanel()
        if on && fading { unfade() } else if !on && !fading && solidOver { fade() }
    }

    private static func unfade() {
        guard let p = panel else { return }
        generation += 1
        fading = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
    }

    private static func fade() {
        guard let p = panel else { return }
        generation += 1
        let gen = generation
        fading = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = SpawnFolderMenu.fadeSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().alphaValue = 0
        }, completionHandler: {
            guard panel === p && generation == gen else { return }
            if pointerOnPanel() { unfade(); return }
            Log.info("🎙️ the ⚡ question's room modal faded out, nothing picked")
            close()
        })
    }
}

/// The modal's surface: the spawn menu's header, rows and ground.
private final class RoomPickView: NSView {
    private let rooms: [Int: RoomTranscript]
    private var rows: [(seconds: Int, rect: NSRect)] = []
    private var hover: Int?
    /// The rows are drawn here, over the blur — the root's own `draw` is under it.
    private let canvas = Canvas()

    private typealias M = SpawnFolderMenu
    private static let width: CGFloat = 300
    private static let header = "Research what was just said…"
    private static let countFont = NSFont.systemFont(ofSize: 13)

    init(rooms: [Int: RoomTranscript]) {
        self.rooms = rooms
        let quote = RoomTranscript.windows.reversed().compactMap { rooms[$0] }.first(where: \.usable)?.quote(limit: 90) ?? ""
        let textWidth = Self.width - 2 * (M.pad + M.rowInset)
        let hint = NSTextField(wrappingLabelWithString: quote.isEmpty ? "" : "«\(quote)»")
        hint.font = M.headerFont
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byTruncatingHead
        hint.preferredMaxLayoutWidth = textWidth
        hint.isSelectable = false
        let hintHeight = quote.isEmpty ? 0 : ceil(hint.sizeThatFits(NSSize(width: textWidth, height: 100)).height)
        let rowsHeight = CGFloat(RoomTranscript.windows.count) * M.rowHeight
        let height = M.pad + M.headerHeight + rowsHeight + (hintHeight > 0 ? 4 + hintHeight + 4 : 0) + M.pad
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        M.addSurface(to: self)
        canvas.frame = bounds
        canvas.autoresizingMask = [.width, .height]
        canvas.paint = { [unowned self] in self.drawRows() }
        addSubview(canvas)

        // Top-down: the header, the rows, the quote — in a view that is not flipped.
        var top = height - M.pad
        let title = NSTextField(labelWithString: Self.header)
        title.font = M.headerFont
        title.textColor = .secondaryLabelColor
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: M.pad + M.rowInset, y: top - M.headerHeight + (M.headerHeight - th) / 2,
                             width: textWidth, height: th)
        addSubview(title)
        top -= M.headerHeight
        for s in RoomTranscript.windows {
            top -= M.rowHeight
            rows.append((s, NSRect(x: M.pad, y: top, width: Self.width - 2 * M.pad, height: M.rowHeight)))
        }
        if hintHeight > 0 {
            hint.frame = NSRect(x: M.pad + M.rowInset, y: M.pad + 4, width: textWidth, height: hintHeight)
            addSubview(hint)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private func row(at p: NSPoint) -> Int? {
        rows.first { $0.rect.contains(p) && rooms[$0.seconds]?.usable == true }?.seconds
    }

    // The hand over the whole panel, as on the spawn menu.
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        RoomPick.followPointer()
    }
    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
        setHover(row(at: convert(event.locationInWindow, from: nil)))
    }
    override func mouseExited(with event: NSEvent) {
        setHover(nil)
        NSCursor.arrow.set()
        RoomPick.followPointer()
    }
    private func setHover(_ s: Int?) {
        guard s != hover else { return }
        hover = s
        canvas.needsDisplay = true
    }

    // A click on a row picks it, as the spawn menu's rows do.
    override func mouseDown(with event: NSEvent) {
        guard let s = row(at: convert(event.locationInWindow, from: nil)) else { return }
        Log.info("🎙️ \(s) s clicked in the ⚡ question's modal")
        RoomPick.choose(s)
    }

    private final class Canvas: NSView {
        var paint: (() -> Void)?
        override func draw(_ dirtyRect: NSRect) { paint?() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private func drawRows() {
        for r in rows {
            let room = rooms[r.seconds]
            let usable = room?.usable == true
            let lit = usable && hover == r.seconds
            if lit {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: r.rect.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            let ink = lit ? NSColor.white : (usable ? NSColor.labelColor : NSColor.tertiaryLabelColor)
            let name = NSAttributedString(string: "🎙️ \(RoomTranscript.label(r.seconds))",
                                          attributes: [.font: M.rowFont, .foregroundColor: ink])
            let ns = name.size()
            name.draw(at: NSPoint(x: r.rect.minX + M.rowInset, y: r.rect.midY - ns.height / 2))
            let count = NSAttributedString(
                string: room.map { "\($0.words) words" } ?? "no transcript",
                attributes: [.font: Self.countFont,
                             .foregroundColor: lit ? NSColor.white.withAlphaComponent(0.85)
                                 : (usable ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor)])
            let cs = count.size()
            count.draw(at: NSPoint(x: r.rect.maxX - M.rowInset - cs.width, y: r.rect.midY - cs.height / 2))
        }
    }
}
