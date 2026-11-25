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
/// before he started speaking**, and `RoomPick` offers them: *Last 30 s* /
/// *Last 60 s*. A click makes that window the research topic and **ends the
/// question** (as 🔼 would): whatever he said goes along as his question about
/// it; said nothing, the window alone is checked. It replaced Victor Mac' 🔬
/// Fact-check menu rows, which pushed the same window to `POST /ask`.
///
/// No click: the modal goes with the question, and nothing changes.
/// `WT_ROOM_PICK=0` turns the offer off.
struct RoomTranscript: Equatable {
    let seconds: Int
    /// `[HH:MM] words` lines, oldest first — what the model reads.
    let transcript: String
    /// The words alone — the header's quote.
    let speech: String
    let words: Int

    static let port = 55123
    static let windows = [30, 60]
    /// Fewer words than this is not a discussion — the window is not offered.
    static let minWords = 5

    var usable: Bool { words >= Self.minWords }

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
        return said.isEmpty ? "🎙️ \(seconds) s «\(quote())»" : "\(said) · 🎙️ \(seconds) s"
    }

    /// What the quick model is asked. Its system prompt says "be brief, no lists
    /// unless asked" — so this asks for the list, one line per claim.
    func prompt(question: String?) -> String {
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
}

/// **The modal**: two buttons by the pointer, *Last 30 s* / *Last 60 s*, each
/// with its word count; a window with too few words is greyed and does not click.
/// It sits where the pointer was when the question opened and does not follow
/// (nothing rides the pointer but the chip). Never key, never activating —
/// the dictation keeps the keyboard and the front app keeps its focus.
enum RoomPick {
    private static var panel: NSPanel?
    private static var rooms: [Int: RoomTranscript] = [:]
    private static var onPick: ((RoomTranscript) -> Void)?
    private static var token = 0

    static var isOpen: Bool { panel != nil }
    static var frame: NSRect? { panel?.frame }
    static var offered: [Int: RoomTranscript] { rooms }

    /// Clay, the Claude blog's selection colour (`--color-clay`, claude.com).
    static let clay = NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)

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
        pick(room)
        return true
    }

    static func close() {
        token += 1
        panel?.orderOut(nil)
        panel = nil
        rooms = [:]
        onPick = nil
    }

    /// Desk route: the modal for these windows, drawn into a PNG, never on a screen.
    static func snapshot(_ got: [Int: RoomTranscript], to url: URL) -> Bool {
        let view = RoomPickView(rooms: got)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
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
        // In the room's share like the reply pop-up; out of the shutter's frames.
        p.sharingType = ReplyPanel.capturable ? .readOnly : .none
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.contentView = view
        p.setFrameOrigin(origin(for: view.frame.size, at: point))
        p.orderFrontRegardless()
        panel = p
    }

    /// Centred on the pointer's x, its bottom edge `above` over the pointer —
    /// clear of the chip and the halo — and inside the pointer's screen.
    static let above: CGFloat = 70
    private static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let v = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var o = NSPoint(x: point.x - size.width / 2, y: point.y + above)
        // No room above: under the pointer instead.
        if o.y + size.height > v.maxY { o.y = point.y - above - size.height }
        o.x = min(max(o.x, v.minX + 8), v.maxX - size.width - 8)
        o.y = min(max(o.y, v.minY + 8), v.maxY - size.height - 8)
        return o
    }
}

/// The modal's surface: a title, two buttons, the quote of the longer window.
private final class RoomPickView: NSView {
    private let rooms: [Int: RoomTranscript]
    private var buttons: [(seconds: Int, rect: NSRect)] = []
    private var hover: Int?
    private var pressed: Int?

    private static let width: CGFloat = 300
    private static let pad: CGFloat = 12
    private static let buttonHeight: CGFloat = 46

    init(rooms: [Int: RoomTranscript]) {
        self.rooms = rooms
        let quote = RoomTranscript.windows.reversed().compactMap { rooms[$0] }.first(where: \.usable)?.quote(limit: 90) ?? ""
        let title = Self.label("🎙️ Research what was just said", size: 13, weight: .semibold, color: .white)
        let hint = Self.label(quote.isEmpty ? "" : "«\(quote)»", size: 11, weight: .regular,
                              color: NSColor(white: 1, alpha: 0.55))
        hint.maximumNumberOfLines = 2
        hint.lineBreakMode = .byTruncatingHead
        hint.preferredMaxLayoutWidth = Self.width - 2 * Self.pad
        let hintHeight = quote.isEmpty ? 0 : ceil(hint.sizeThatFits(NSSize(width: Self.width - 2 * Self.pad, height: 100)).height)
        let height = Self.pad + 18 + 8 + Self.buttonHeight + (hintHeight > 0 ? 8 + hintHeight : 0) + Self.pad
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor

        title.frame = NSRect(x: Self.pad, y: height - Self.pad - 18, width: Self.width - 2 * Self.pad, height: 18)
        addSubview(title)
        let count = CGFloat(RoomTranscript.windows.count)
        let gap: CGFloat = 10
        let w = (Self.width - 2 * Self.pad - gap * (count - 1)) / count
        let y = title.frame.minY - 8 - Self.buttonHeight
        for (i, s) in RoomTranscript.windows.enumerated() {
            buttons.append((s, NSRect(x: Self.pad + CGFloat(i) * (w + gap), y: y, width: w, height: Self.buttonHeight)))
        }
        if hintHeight > 0 {
            hint.frame = NSRect(x: Self.pad, y: Self.pad, width: Self.width - 2 * Self.pad, height: hintHeight)
            addSubview(hint)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let t = NSTextField(labelWithString: text)
        t.font = .systemFont(ofSize: size, weight: weight)
        t.textColor = color
        t.isSelectable = false
        return t
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    private func button(at p: NSPoint) -> Int? {
        buttons.first { $0.rect.contains(p) && rooms[$0.seconds]?.usable == true }?.seconds
    }

    override func mouseMoved(with event: NSEvent) { setHover(button(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }
    private func setHover(_ s: Int?) {
        guard s != hover else { return }
        hover = s
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = button(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let s = button(at: convert(event.locationInWindow, from: nil))
        defer { pressed = nil; needsDisplay = true }
        guard let s, s == pressed else { return }
        Log.info("🎙️ \(s) s clicked in the ⚡ question's modal")
        RoomPick.choose(s)
    }

    override func draw(_ dirtyRect: NSRect) {
        for b in buttons {
            let room = rooms[b.seconds]
            let usable = room?.usable == true
            let path = NSBezierPath(roundedRect: b.rect, xRadius: 8, yRadius: 8)
            let lit = usable && (hover == b.seconds || pressed == b.seconds)
            (lit ? RoomPick.clay : NSColor(white: 1, alpha: usable ? 0.12 : 0.05)).setFill()
            path.fill()
            if usable && !lit {
                RoomPick.clay.withAlphaComponent(0.8).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let ink = NSColor(white: 1, alpha: usable ? 1 : 0.35)
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            let top = NSAttributedString(string: "Last \(b.seconds) s", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink, .paragraphStyle: center])
            let sub = NSAttributedString(string: room.map { "\($0.words) words" } ?? "no transcript", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink.withAlphaComponent(usable ? 0.75 : 0.35),
                .paragraphStyle: center])
            top.draw(in: NSRect(x: b.rect.minX, y: b.rect.midY - 1, width: b.rect.width, height: 19))
            sub.draw(in: NSRect(x: b.rect.minX, y: b.rect.minY + 6, width: b.rect.width, height: 15))
        }
    }
}
