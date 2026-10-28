import AppKit

/// **The agent's short answer to a question he dictated, beside the pointer**
/// (2026-10-07).
///
/// Victor: *"sometimes I'm asking questions, direct questions, not telling what
/// to do … there should be a way that the agent is able to reach me back … a
/// bit of a panel that appears next to the mouse carrying the response of the
/// model … I'm going to answer by just dictating more … it's super important to
/// be brief."* A prompt with a `?` in it carries one more footer line asking for
/// `walkie-reply "…"` (`AppDelegate.questionHint`); the script posts here through
/// `POST /reply` with the token in `~/.walkie-talkie/reply-token`.
///
/// **Only he dismisses it — the ✕, no clock, no bar** (the same evening: first
/// *"having an X icon in the corner for me to dismiss it explicitly"*, then,
/// over a countdown that started when the pointer moved: *"NO PROGRESSBAR. i
/// have to manually dismiss it"*). An answer that went away on a timer while he
/// was looking at the terminal is one he never got.
///
/// **Answers queue, one on screen at a time** (2026-10-08, Victor: *"să nu apară
/// una peste alta, să apară doar după ce am închis una … pe rând, stau la
/// coadă"*). A newer answer waits behind the open one and comes up, at the
/// pointer, when that one is closed (✕ or its link).
///
/// It sits where the pointer was when the answer arrived and does not follow —
/// it is read, and clicked once. **It zooms in out of the pointer, fading in**
/// (`zoom`; a toast rising from the screen's bottom until the same afternoon),
/// centred on the pointer's x, its top edge `belowPointer` under the pointer
/// (2026-10-08, Victor: *"marginea de sus a panelului … un pic sub mouse"*).
///
/// **Shared in a Teams/Zoom screen share, absent from the shutter's frames**
/// (2026-10-12, Victor: *"When I share with teams, this overlay … is not
/// displayed. Fix."*). It was `sharingType = .none`, which hid it from every
/// capture — the room's included. It is `.readOnly` now, and `outOfShot` drops
/// it to `.none` only for the length of the shutter's own `screencapture`, so
/// the next dictation's pictures are still of his screen, not of this. The flip
/// is invisible on his display; a viewer of the share sees it gone for the
/// ~0.3 s of the shot.
enum ReplyPanel {
    private static var panel: NSPanel?
    private static var queue: [(text: String, label: String?, tty: String?, images: [URL])] = []
    private static var arrivedAt: NSPoint = .zero

    /// 400 until 2026-10-09; the pop-up holds a long answer whole, so only a
    /// runaway one is cut.
    static let maxChars = 4000
    /// 380 until 2026-10-15 — widened so the ⚡ footer `— Opus 5.5 + 🌐 searched +
    /// 🧐 adversarial reviewed ✏️` (~400 pt) stays on one line. **5 % narrower**
    /// (2026-10-22, Victor: *"micșorează un pic lățimea ferestrei cu 5%"*) — the
    /// footer is `footerFont` since, so `🤖 Opus 5.5 + 🌐 Internet + 🤖 adversarial
    /// reviewed ✏️` (~365 pt) still holds on the 386 pt body.
    private static let width: CGFloat = 428
    /// **Always the whole answer, in the least room it needs** (2026-10-23,
    /// Victor: *"niciodată să nu poți să dimensionezi dialogul în așa fel încât
    /// să trunchezi răspunsul. Mereu să facă fit, să fie minim cât. Și dacă măresc
    /// fereastra să meargă și textul"*). The pop-up is its words' fitted size at
    /// `scale`: `baseWidth × scale` wide, as tall as they wrap to, growing down —
    /// only the wheel changes `scale`, the words with the window. **No corner
    /// resizes it** (the same evening: *"nici nu nevoie de redimensionare acelui
    /// dialog. Nu are sens"* — the corners resized it since 2026-10-09). An answer
    /// too tall for the screen at 428 pt widens `baseWidth` instead of scrolling
    /// (`fit`); the scroller is left for one no width on the screen can hold.
    private static var baseWidth: CGFloat = width
    /// The pictures, read once per pop-up — every wheel notch rebuilds it.
    private static var pictureCache: [URL: NSImage] = [:]
    /// **Everything in the pop-up is drawn `scale` times larger** while the wheel
    /// has zoomed it (`grow`, 2026-10-23); 1 for every new pop-up.
    private static var scale: CGFloat = 1
    private static var font: NSFont { .systemFont(ofSize: 15 * scale) }
    /// 26, up from 20, to carry the 26 pt walkie (2026-10-08, *"make the icon
    /// slightly larger … so I can click it easier"*); the name and the ✕ are
    /// centred in it.
    private static var headerH: CGFloat { 26 * scale }
    private static var iconSide: CGFloat { 26 * scale }

    private static let walkie: NSImage? = RelayWindow.walkieURL("walkie-bound").flatMap { NSImage(contentsOf: $0) }

    /// On by default since 2026-10-12, so a screen share shows the answer
    /// (`POST /test/quick {"capturable": false}` turns it off for the next pop-ups).
    static var capturable = true

    /// **Out of the frame while `body` takes a screenshot** — the shutter's
    /// `screencapture` runs off the main thread, the window is touched on it.
    static func outOfShot<T>(_ body: () throws -> T) rethrows -> T {
        func share(_ type: NSWindow.SharingType) {
            if Thread.isMainThread { panel?.sharingType = type }
            else { DispatchQueue.main.sync { panel?.sharingType = type } }
        }
        share(.none)
        defer { share(capturable ? .readOnly : .none) }
        return try body()
    }
    /// The open pop-up's frame, global Cocoa points.
    static var frame: NSRect? { panel?.frame }

    /// What is on screen — `GET /test/state`.
    static var shown: String?
    /// The open pop-up's words as built — links, dots and robots still marked;
    /// `shown` is them read plain, and a rebuild from it lost the links.
    private static var shownRaw: String?
    /// The terminal the open pop-up came from.
    private static var shownTTY: String?
    /// The pictures on the open pop-up.
    private static var shownImages: [URL] = []

    /// **The sender's tty while the pointer is over its pop-up** — 🔼 → there
    /// answers that session (`AppDelegate.replyBack`). Main thread.
    static var ttyUnderPointer: String? {
        guard let p = panel, let tty = shownTTY,
              p.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) else { return nil }
        return tty
    }

    /// **The pointer is over a ⚡ quick answer** — 🔼 → there asks it a
    /// follow-up (`AppDelegate.askFollowUp`, 2026-10-15). Main thread.
    static var quickUnderPointer: Bool {
        guard let p = panel, openLabel?.hasPrefix(quickMark) == true else { return false }
        return p.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    /// **The 📍 binds that terminal** (2026-10-08, Victor: *"the new icon … next
    /// to the death face … would rebind me, but it only displays if I'm not
    /// already bound to that terminal … the [pin] that shows caret"*) —
    /// `AppDelegate.rebindFromMenu`, with the border flying into the chip.
    /// It was the name's click until then.
    static var onBind: ((String) -> Void)?
    /// Is Walkie bound to this tty right now — decides whether the 📍 is drawn.
    static var isBound: ((String) -> Bool)?
    /// **A click on the terminal's name brings it in front, where it is**
    /// (2026-10-08, Victor: *"if I click the name of it, it's not rebind … it
    /// brings in front the wrong terminal"*) — nothing is bound; the 📍 binds.
    static var onRaise: ((String) -> Void)?

    /// **A click on the walkie puts that terminal in front, centred on the
    /// Retina, at once** (2026-10-08, Victor: *"if I click on the Walkie Talkie
    /// icon … that terminal should pop in front … on the retina in the center of
    /// the screen … with no animation"*) — to read more, or ask more, there.
    /// Nothing is bound; the name is the link that binds.
    static var onPresent: ((String) -> Void)?

    /// **The ☠️ left of the ✕ sends that session `kamikaze`** (2026-10-08,
    /// Victor: *"to the left of the X … an emoji with a skull … with a click, it
    /// sends kamikaze back to the session that sent this message"*) — the
    /// answer was the last thing he needed from it. The panel explodes from the
    /// skull (`ReplyBurst.Style.explode`, 2026-10-14).
    static var onKamikaze: ((String) -> Void)?

    /// **A ☠️ that cannot kill: red, as if already pressed** (2026-10-13, Victor:
    /// *"if I fire the question, or if it's a Kamikaze session, the skull should
    /// show up red … so that I can't really kill an already killed session … from
    /// a Claude session that has ended by now … the skull should show it's dead"*).
    /// Dead is a session told `kamikaze` (`doom`), or a tty with no agent left
    /// on it — asked when the pop-up opens and every `watchEvery` while it
    /// stays. Never back to alive. A ⚡ quick answer has no ☠️ at all: its
    /// `claude -p` was one-shot, never meant to survive (2026-10-13, evening).
    /// **Dead shows as a 🪦, not a red ☠️** (2026-10-13, late: *"replace that
    /// emoji with a tombstone … saying to me: the terminal died already"*) —
    /// on hover it says so (`deadHint`).
    static var agentRunning: ((String) -> Bool)?
    private static var shownDead = false
    private static weak var skullButton: ReplyCloseButton?
    private static var watchTimer: Timer?
    private static let watchEvery: TimeInterval = 2
    /// Short tty → when it was told `kamikaze`. Forgotten once seen dead, or
    /// after `doomFor` — the kernel hands the number to the next tab.
    private static var doomed: [String: Date] = [:]
    private static let doomFor: TimeInterval = 600

    /// `kamikaze` was delivered to this tty — any thread.
    static func doom(_ tty: String) {
        let short = (tty as NSString).lastPathComponent
        DispatchQueue.main.async {
            doomed[short] = Date()
            Log.info("💬 \(short) was told kamikaze — its answers show a 🪦")
            if shownTTY.map({ ($0 as NSString).lastPathComponent }) == short { markDead() }
        }
    }

    private static func isDoomed(_ tty: String) -> Bool {
        let short = (tty as NSString).lastPathComponent
        guard let since = doomed[short] else { return false }
        if Date().timeIntervalSince(since) < doomFor { return true }
        doomed[short] = nil
        return false
    }

    private static func markDead() {
        guard !shownDead else { return }
        shownDead = true
        skullButton?.dead = true
        watchTimer?.invalidate()
        watchTimer = nil
    }

    /// Asks the open pop-up's tty now, then every `watchEvery` until it is dead or closed.
    private static func watchSender() {
        watchTimer?.invalidate()
        watchTimer = nil
        guard let tty = shownTTY, !shownDead, let ask = agentRunning else { return }
        let check = {
            DispatchQueue.global(qos: .utility).async {
                let alive = ask(tty)
                DispatchQueue.main.async {
                    guard !alive, shownTTY == tty, !shownDead else { return }
                    Log.info("💬 no agent left on \(tty) — the reply pop-up shows a 🪦")
                    doomed[(tty as NSString).lastPathComponent] = nil
                    markDead()
                }
            }
        }
        check()
        watchTimer = Timer.scheduledTimer(withTimeInterval: watchEvery, repeats: true) { _ in check() }
    }

    static func show(_ raw: String, from label: String?, tty: String? = nil, images: [URL] = []) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(raw, from: label, tty: tty, images: images) }
            return
        }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        guard !text.isEmpty || !images.isEmpty else { return }
        if panel != nil {
            queue.append((text, label, tty, images))
            Log.info("💬 answer from \(label ?? "agent") queued behind the open one — \(queue.count) waiting")
            return
        }
        present(text, from: label, tty: tty, images: images)
    }

    // MARK: Pictures (2026-10-09)

    /// **Copies the pictures an agent sent into the cache**, so a scratch file
    /// it deletes after `walkie-reply` returns still opens on a click. Only
    /// what `NSImage` can read, at most `maxImages`; the folder keeps the
    /// newest 100.
    static func keep(_ paths: [String]) -> [URL] {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ro.victorrentea.wispr-relay/replies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        var kept: [URL] = []
        for (i, path) in paths.prefix(maxImages).enumerated() {
            let src = URL(fileURLWithPath: path)
            guard NSImage(contentsOf: src) != nil else {
                Log.error("💬 the reply's picture \(path) is not an image this Mac can read — left out")
                continue
            }
            let dst = dir.appendingPathComponent("\(stamp)-\(i)-\(src.lastPathComponent)")
            do { try FileManager.default.copyItem(at: src, to: dst); kept.append(dst) }
            catch { Log.error("💬 could not keep the reply's picture \(path): \(error)") }
        }
        let all = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in all.dropFirst(100) { try? FileManager.default.removeItem(at: old) }
        return kept
    }

    static let maxImages = 8
    /// One picture: up to this tall, across the pop-up's width. Several: one
    /// row this tall, as many as fit, the last one saying how many did not.
    private static let singleImageMax: CGFloat = 170
    private static let thumbHeight: CGFloat = 72
    private static let thumbGap: CGFloat = 6

    /// A click opens it in Preview, full size (Victor: *"small, but when
    /// clicked, opened up"*). The pop-up stays.
    /// The `+N` one opens itself and every picture that did not fit.
    static func open(_ urls: [URL]) {
        Log.info("💬 the reply pop-up's picture clicked — \(urls.count) opened in Preview (\(urls[0].lastPathComponent)…)")
        let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
        NSWorkspace.shared.open(urls, withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The thumbnails for `inner` points across: frames, bottom-left origin at
    /// (0, 0), and how many were left out.
    static func thumbLayout(_ sizes: [NSSize], inner: CGFloat) -> (frames: [NSRect], height: CGFloat, hidden: Int) {
        guard !sizes.isEmpty else { return ([], 0, 0) }
        func aspect(_ s: NSSize) -> CGFloat { s.height > 0 ? max(0.3, min(4, s.width / s.height)) : 1 }
        if sizes.count == 1 {
            let a = aspect(sizes[0])
            var h = min(singleImageMax, inner / a)
            var w = h * a
            if w > inner { w = inner; h = w / a }
            return ([NSRect(x: 0, y: 0, width: w, height: h)], h, 0)
        }
        var frames: [NSRect] = []
        var x: CGFloat = 0
        for s in sizes {
            let w = min(inner, thumbHeight * aspect(s))
            if x + w > inner, !frames.isEmpty { break }
            frames.append(NSRect(x: x, y: 0, width: w, height: thumbHeight))
            x += w + thumbGap
        }
        return (frames, thumbHeight, sizes.count - frames.count)
    }

    /// **⚡ The quick answer, as it streams** (2026-10-09, `QuickAsk`): the first
    /// call opens the pop-up at the pointer — at once, jumping the queue (the
    /// open one goes back to its head) — and every later call rewrites its words
    /// in place, the top edge fixed. Ends with `finishLive`; then it is an
    /// ordinary pop-up, up until the ✕.
    static func live(_ raw: String, from label: String?, question token: Int) {
        // ✕'d while it was still coming: the rest of it is not wanted.
        guard token != dismissedLive else { return }
        animateDots(raw, from: label)
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "…" }
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        if let p = panel, liveOpen {
            let root = fit(text, from: label, tty: nil)
            // The size first: assigning the content view resizes it to the
            // window's old frame, and the answer stayed cut to its first line.
            let size = root.frame.size
            p.setFrame(onScreen(NSRect(x: p.frame.minX, y: p.frame.maxY - size.height,
                                       width: size.width, height: size.height)), display: false)
            p.contentView = root
            p.invalidateShadow()
            // The pointer may be on a link: its tip again, on the new view.
            root.refreshHover()
            shown = plain(text)
            shownRaw = text
            // A follow-up asked while the last answer was still being checked
            // writes into the same pop-up — it is this question's now, or its
            // `finishLive` never matches and the pop-up stays `liveOpen`.
            openLabel = label
            liveToken = token
            return
        }
        if let p = panel, let open = shown {
            // An agent's answer waits its turn again; a finished ⚡ one is
            // simply replaced by the next question's.
            if openLabel?.hasPrefix(quickMark) != true {
                queue.insert((open, openLabel, shownTTY, shownImages), at: 0)
                Log.info("💬 the open reply pop-up steps back into the queue for a ⚡ quick answer")
            }
            p.orderOut(nil)
            panel = nil
        }
        present(text, from: label, tty: nil)
        liveOpen = true
        liveToken = token
    }

    /// The quick answer is complete: the pop-up stays, as any other.
    static func finishLive(question token: Int) { if liveToken == token { liveOpen = false } }

    /// **🌐 More** (2026-10-22, Victor: *"un buton mic acolo pe dialogul care
    /// apare să zică more, prin care să mai solicit mai mult research pe
    /// internet"*): a link in the ⚡ footer, right after `🌐 Internet`, that is
    /// not a page — `openLink` hands it to `onMore` (`AppDelegate.askQuick`).
    /// **It reads `🪏 dig more`** (2026-10-23, Victor: *"să se cheamă linkul dig more"*,
    /// then *"un emoji de lopată în fața lu D, d mic să fie"*).
    static let moreURL = URL(string: "walkie-quick:more")!
    static var more: String { link("🪏 dig more", moreURL) }
    static var onMore: (() -> Void)?
    /// The finished ⚡ pop-up is being written again (🌐 More): later `live`
    /// calls rewrite it in place instead of opening a new one. False when it
    /// is gone or is another question's.
    @discardableResult
    static func reopenLive(question token: Int) -> Bool {
        guard panel != nil, liveToken == token, token != dismissedLive else { return false }
        liveOpen = true
        return true
    }

    /// The ✕ took down a ⚡ pop-up still being written — its checks stop (`QuickAsk.cancel`).
    static var onLiveDismissed: (() -> Void)?

    /// The header of every ⚡ quick answer starts with it (`AppDelegate.askQuick`).
    static let quickMark = "⚡ "
    static let deadHint = "The terminal died already"

    /// The ⚡ pop-up is still being written.
    private(set) static var liveOpen = false
    private static var liveToken = 0, dismissedLive = -1
    private static var openLabel: String?

    /// **Under Victor Addons' ⌥⇧ zoom, the pop-up is zoomed with the rest**
    /// (2026-10-15, Victor: *"You shouldn't keep the small one … I should zoom in
    /// it. The top most basically has to disappear."*). That zoom (`ShareZoom`)
    /// is an opaque window at `.screenSaver` that films the display and shows it
    /// magnified; at the maximum level the pop-up was drawn twice — unmagnified
    /// above the glass and magnified in the film under it. While the zoom is on
    /// it drops just under the glass, so only the film shows it. Its ✕ and links
    /// still answer: the glass ignores the mouse, and the magnified pointer over
    /// a magnified ✕ is the real pointer over the real one. Off the zoom it is
    /// back at the top, over the effect panels (`spawn.md`'s reason).
    private static var level: NSWindow.Level {
        shareZoomOn
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
    }

    /// Addons posts the zoomed cursor ~30 Hz while it moves, every 0.5 s while it
    /// rests, an empty note when the zoom ends — the same feed victor-effects'
    /// `VisibleCursor` reads; silent for 1.5 s counts as ended (a crashed Addons).
    private static let shareZoomNote = Notification.Name("ro.victorrentea.share-zoom.cursor")
    private static var shareZoomObserver: NSObjectProtocol?
    private static var shareZoomSeenAt: CFAbsoluteTime = 0
    private static var shareZoomStale: Timer?
    private(set) static var shareZoomOn = false {
        didSet {
            guard shareZoomOn != oldValue else { return }
            Log.info("🔎 ⌥⇧ zoom \(shareZoomOn ? "on — the reply pop-up goes under it" : "off — the reply pop-up back on top")")
            panel?.level = level
            shareZoomChanged.forEach { $0(shareZoomOn) }
        }
    }
    /// Others drawn on the screen that must move round the zoom's glass too (`CaretHalo`).
    static var shareZoomChanged: [(Bool) -> Void] = []

    static func watchShareZoom() {
        guard shareZoomObserver == nil else { return }
        shareZoomObserver = DistributedNotificationCenter.default().addObserver(
            forName: shareZoomNote, object: nil, queue: .main
        ) { note in
            guard note.userInfo?["x"] != nil else {
                shareZoomOn = false
                shareZoomStale?.invalidate()
                shareZoomStale = nil
                return
            }
            shareZoomSeenAt = CFAbsoluteTimeGetCurrent()
            shareZoomOn = true
            guard shareZoomStale == nil else { return }
            shareZoomStale = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
                guard CFAbsoluteTimeGetCurrent() - shareZoomSeenAt > 1.5 else { return }
                shareZoomOn = false
                t.invalidate()
                shareZoomStale = nil
            }
        }
    }

    private static func present(_ text: String, from label: String?, tty: String?, images: [URL] = []) {
        allowCursorInBackground
        shown = plain(text)
        shownRaw = text
        shownTTY = tty
        shownImages = images
        openLabel = label
        arrivedAt = NSEvent.mouseLocation
        shownDead = tty.map(isDoomed) == true
        // A new pop-up opens at its own size — the last one's wheel is
        // forgotten (a ⚡ one replaced in place never passed through `close`).
        wheel = nil
        scale = 1
        baseWidth = width
        let root = fit(text, from: label, tty: tty, images: images)

        let p = ReplyWindow(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        watchShareZoom()
        p.level = level
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = capturable ? .readOnly : .none
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.contentView = root
        let target = origin(for: root.frame.size, at: arrivedAt)
        p.setFrameOrigin(target)
        p.orderFrontRegardless()
        panel = p
        zoom(p, around: arrivedAt)
        watchSender()
        Log.info("💬 answer from \(label ?? "agent") — \(text.count) chars\(images.isEmpty ? "" : ", \(images.count) picture(s)"); up until the ✕\(queue.isEmpty ? "" : ", \(queue.count) waiting")")
    }

    /// The visible frame of the pop-up's screen — the pointer's, before it is up.
    private static var visible: NSRect {
        (panel?.screen ?? screen(at: arrivedAt))?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// `r` moved, not resized, into the visible frame.
    private static func onScreen(_ r: NSRect) -> NSRect {
        let v = visible
        return NSRect(x: max(v.minX, min(r.minX, v.maxX - r.width)), y: max(v.minY, min(r.minY, v.maxY - r.height)),
                      width: r.width, height: r.height)
    }

    /// **The words built whole, on the screen**: wider than the screen at this
    /// `scale` → smaller; taller → smaller while zoomed, wider (`baseWidth`) at
    /// its own size. Only an answer the whole width cannot hold keeps a scroller.
    private static func fit(_ text: String, from label: String?, tty: String?, images: [URL] = []) -> ReplyRoot {
        let v = visible
        var root = build(text, from: label, tty: tty, images: images)
        for _ in 0..<40 {
            let size = root.frame.size
            if size.width > v.width + 0.5 { scale *= 0.95 }
            else if size.height <= v.height + 0.5 { break }
            else if scale > 1 { scale = max(1, scale * 0.95) }
            else if baseWidth * scale < v.width - 0.5 { baseWidth = min(v.width / scale, baseWidth * 1.15) }
            else { break }
            root = build(text, from: label, tty: tty, images: images)
        }
        return root
    }


    /// **The wheel over it grows it, up to the whole screen** (2026-10-23, Victor:
    /// *"dacă sunt cu mouse-ul pe acest popup, când dau scroll … să se mărească
    /// dimensiunea acestei ferestre până când devine mare cât tot ecranul"*). The
    /// wheel rolled up (zoom in, as in a map) grows it, rolled down shrinks it back
    /// to the size it had at the first notch; past either end the wheel scrolls the
    /// words, as before. **A zoom, not a bigger window** (same day, Victor: *"să se
    /// mărească și fereastra și textul … să se vadă pe tot ecranul centrat la maxim
    /// zoom … mărești tot, practic"*): the words, the icons and the margins grow with
    /// the window (`scale`), its proportions kept, until its width or its height
    /// meets the screen's visible frame — so the room can read it. `t` runs 0 → 1:
    /// the magnification goes 1 → `most` geometrically, the centre slides to the
    /// screen's. A drag of the pop-up moves `centre` so the next notch does not
    /// jump; a new answer streamed into it starts over from there. The size
    /// at each notch is the words' (`fit`), never a box they are cut to.
    private static var wheel: (size: NSSize, scale: CGFloat, centre: NSPoint, t: CGFloat, set: NSRect)?
    /// A wheel notch moves `t` this much — ~8 notches to the whole screen; a
    /// trackpad's points are divided by `wheelPoints`.
    private static let wheelStep: CGFloat = 0.12
    private static let wheelPoints: CGFloat = 500

    /// Took the wheel event (false: the words scroll instead).
    fileprivate static func grow(_ p: NSPanel, by dy: CGFloat, precise: Bool) -> Bool {
        guard panel === p, let text = shownRaw ?? shown, dy != 0 else { return false }
        let v = visible
        let f = p.frame
        var w = wheel ?? (f.size, scale, NSPoint(x: f.midX, y: f.midY), 0, f)
        if f.size != w.set.size {
            // **The words changed under the zoom** (2026-10-28, Victor: *"dacă mi-a
            // mai dat răspunsuri internetul sau adversarii … nu mai pot să-l zoomez
            // la cum era original"*): a 🔎 / 🧐 streamed in, or `fit` shrank it. The
            // first notch's scale stays the floor; its size there and `t` are read
            // back from the scale it is at now — it was re-taken as the floor, and
            // the wheel rolled down stopped at the zoomed size.
            let back = w.scale / scale
            w.size = NSSize(width: f.width * back, height: f.height * back)
            let most = max(min(v.width / w.size.width, v.height / w.size.height), 1 / back)
            w.t = most > 1.01 ? min(1, max(0, log(1 / back) / log(most))) : 0
            if w.t < 1 {
                w.centre = NSPoint(x: (f.midX - w.t * v.midX) / (1 - w.t), y: (f.midY - w.t * v.midY) / (1 - w.t))
            }
            w.set = f
        } else if f.origin != w.set.origin, w.t < 1 {
            w.centre = NSPoint(x: (f.midX - w.t * v.midX) / (1 - w.t), y: (f.midY - w.t * v.midY) / (1 - w.t))
        }
        // As much as it can grow whole: until one side meets the screen's —
        // never less than it is zoomed now, so rolling down still gets back.
        let most = max(min(v.width / w.size.width, v.height / w.size.height), scale / w.scale)
        guard most > 1.01 else { return false }
        let t = min(1, max(0, w.t + (precise ? dy / wheelPoints : dy * wheelStep)))
        guard t != w.t else { return false }
        scale = w.scale * pow(most, t)
        let root = fit(text, from: openLabel, tty: shownTTY, images: shownImages)
        let size = root.frame.size
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        p.setFrame(onScreen(NSRect(x: lerp(w.centre.x, v.midX) - size.width / 2, y: lerp(w.centre.y, v.midY) - size.height / 2,
                                   width: size.width, height: size.height)), display: false)
        p.contentView = root
        p.invalidateShadow()
        w.t = t
        w.set = p.frame
        wheel = w
        return true
    }

    /// Desk route: `notches` of the wheel over the open pop-up (+ = rolled up).
    static func wheelOpen(_ notches: Double) {
        guard let p = panel else { return }
        _ = grow(p, by: CGFloat(notches), precise: false)
    }

    /// **A link in the words** (2026-10-10, `QuickAsk.cited`): `\u{1}(site)\u{2}url\u{3}`
    /// shows `(site)`, clickable, its URL under the pointer on hover. Characters
    /// no answer contains, so an agent's text is never read as one.
    static func link(_ label: String, _ url: URL) -> String { "\u{1}\(label)\u{2}\(url.absoluteString)\u{3}" }

    /// The words with the links' labels only, and where those labels are.
    static func parseLinks(_ text: String) -> (plain: String, links: [(range: NSRange, url: URL)]) {
        guard text.contains("\u{1}") else { return (text, []) }
        var out = "", links: [(NSRange, URL)] = []
        var rest = Substring(text)
        while let a = rest.firstIndex(of: "\u{1}"), let b = rest[a...].firstIndex(of: "\u{2}"),
              let c = rest[b...].firstIndex(of: "\u{3}") {
            out += rest[..<a]
            let label = String(rest[rest.index(after: a)..<b])
            if let url = URL(string: String(rest[rest.index(after: b)..<c])) {
                links.append((NSRange(location: (out as NSString).length, length: (label as NSString).length), url))
            }
            out += label
            rest = rest[rest.index(after: c)...]
        }
        return (out + rest, links)
    }
    static func plain(_ text: String) -> String {
        parseLinks(text).plain.replacingOccurrences(of: dots, with: "…")
            .replacingOccurrences(of: signed, with: "🤖").replacingOccurrences(of: adversary, with: "😠")
    }

    /// **The ⚡ footer's two robots** (2026-10-22, Victor: *"în loc de minusul din
    /// fața numelui modelului … această poză [🤖] … în loc de fața cu thinking, cu
    /// monoclu … această poză"* — an angry robot, cut from his slide):
    /// `signed` starts the footer and is drawn 🤖 — from it to the end the words
    /// are `footerFont`; `adversary` is `robot-adversarial.png`, the 🧐's place.
    static let signed = "\u{5}"
    static let adversary = "\u{6}"
    private static var footerFont: NSFont { .systemFont(ofSize: 14 * scale) }
    private static let adversaryImage: NSImage? = RelayWindow.walkieURL("robot-adversarial").flatMap(NSImage.init(contentsOf:))

    /// **Three dots, one lit at a time, for a step still running** (2026-10-10,
    /// Victor: *"o mică animație subtilă … niște punctulețe"*): `🧐 reviewing` +
    /// this. Always three, so the line does not move as they pulse; repainted
    /// by `dotTimer` while the ⚡ pop-up is being written.
    static let dots = "\u{4}"
    private static var dotPhase = 0
    private static var dotTimer: Timer?
    private static var liveRaw: (text: String, label: String?)?

    private static func animateDots(_ raw: String, from label: String?) {
        liveRaw = (raw, label)
        guard raw.contains(dots), dotTimer == nil else { return }
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { t in
            guard liveOpen, let r = liveRaw, r.text.contains(dots) else {
                t.invalidate()
                dotTimer = nil
                return
            }
            dotPhase += 1
            live(r.text, from: r.label, question: liveToken)
        }
    }

    /// A link opened from the pop-up — the page in the browser, the quote
    /// selected on it (`#:~:text=`, `QuickAsk.cited`). The pop-up stays.
    static func openLink(_ url: URL) {
        if url == moreURL {
            Log.info("💬 🌐 More clicked on the ⚡ pop-up")
            lastOpened = url
            onMore?()
            return
        }
        Log.info("💬 the reply pop-up's link clicked — \(url.absoluteString.prefix(160))")
        lastOpened = url
        if openLinks { NSWorkspace.shared.open(url) }
    }
    private static var lastOpened: URL?
    private static var openLinks = true

    /// **Desk** (`POST /test/quick {"link": …}`): mouse events at the centre of
    /// the open pop-up's `index`-th link, sent to its root view as the window
    /// would — the hover's tip, and with `click` the URL a click opens.
    static func testLink(_ index: Int, click: Bool, open: Bool) -> [String: Any] {
        guard let p = panel, let root = p.contentView as? ReplyRoot else { return ["ok": false, "error": "no pop-up"] }
        guard let rect = root.linkRects.dropFirst(index).first else {
            return ["ok": false, "error": "no link \(index)", "links": root.linkRects.count]
        }
        let at = root.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        func event(_ t: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: t, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let e = event(.mouseMoved) { root.mouseMoved(with: e) }
        var out: [String: Any] = ["ok": true, "links": root.linkRects.count, "tip": root.tipText ?? NSNull(),
                                  "rect": ["x": rect.minX, "y": rect.minY, "w": rect.width, "h": rect.height]]
        if click, let down = event(.leftMouseDown), let up = event(.leftMouseUp) {
            lastOpened = nil
            openLinks = open
            root.mouseDown(with: down)
            root.mouseUp(with: up)
            openLinks = true
            out["opened"] = lastOpened?.absoluteString ?? NSNull()
        }
        return out
    }

    /// The pop-up's content for these words — the header, the body, the buttons —
    /// fitted to them, `baseWidth` wide. Every length is `scale` times its own.
    private static func build(_ text: String, from label: String?, tty: String?, images: [URL] = []) -> ReplyRoot {
        let s = scale
        let pad: CGFloat = 12 * s
        let width = (baseWidth * s).rounded()
        let inner = width - 2 * pad
        let gutter = 18 * s
        // **The walkie, not 💬** (Victor: *"change the 💬 icon with the one of
        // walkie"*) — `walkie-bound.png`, the menu bar's own picture.
        // **As large as the answer, cut with … at the end** (Victor, 2026-10-08:
        // *"increase the font of the title to be the same as the response,
        // possibly doing ellipsis at the end"*).
        let header = LinkLabel(labelWithString: label ?? "agent")
        header.lineBreakMode = .byTruncatingTail
        header.cell?.truncatesLastVisibleLine = true
        header.font = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        header.textColor = NSColor.white.withAlphaComponent(0.6)
        // **The click is the answer read: the pop-up goes** (Victor, 2026-10-08:
        // *"I clicked on the title … and it did not close the window. Should
        // have."*), and that terminal comes in front — bound by the 📍 only.
        if let tty = tty {
            header.onClick = {
                Log.info("💬 the reply pop-up's name clicked — \(tty) to the front, pop-up closed")
                close()
                onRaise?(tty)
            }
        }
        // **Not selectable; a press on the words drags the panel** (2026-10-08,
        // Victor: *"I should be able to drag the little window … by clicking
        // on the text and the text shouldn't be selectable"*) — the label
        // passes the click through to `ReplyRoot`.
        // **With links, a text view** — it knows where each word is laid out,
        // for the hover and the click (`LinkedBody`); otherwise the label.
        var (words, links) = parseLinks(text)
        let body: NSView
        let bodySize: NSSize
        if links.isEmpty && !words.contains(dots) && !words.contains(signed) {
            let label = InertLabel(wrappingLabelWithString: text)
            label.isSelectable = false
            label.font = font
            label.textColor = .white
            label.preferredMaxLayoutWidth = inner - gutter
            body = label
            bodySize = text.isEmpty ? .zero
                : label.sizeThatFits(NSSize(width: inner - gutter, height: .greatestFiniteMagnitude))
        } else {
            // The dots: three, one lit — and the links after them moved by two.
            var lit: [NSRange] = []
            while let r = words.range(of: dots) {
                let at = NSRange(r, in: words).location
                words.replaceSubrange(r, with: "...")
                links = links.map { $0.range.location > at ? (NSRange(location: $0.range.location + 2, length: $0.range.length), $0.url) : $0 }
                lit.append(NSRange(location: at, length: 3))
            }
            let styled = NSMutableAttributedString(string: words, attributes: [.font: font, .foregroundColor: NSColor.white])
            for r in lit {
                styled.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.3), range: r)
                styled.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: r.location + dotPhase % 3, length: 1))
            }
            for l in links {
                styled.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.4, green: 0.65, blue: 1, alpha: 1), range: l.range)
            }
            // The robots, once all the above is styled — the string carries its
            // attributes along; the links (`view.links`) are in the answer, above it.
            let ns = styled.string as NSString
            let foot = ns.range(of: signed)
            if foot.location != NSNotFound {
                styled.addAttribute(.font, value: footerFont, range: NSRange(location: foot.location, length: ns.length - foot.location))
                styled.replaceCharacters(in: foot, with: "🤖")
                // 🤖 is two UTF-16 units where the marker was one: a link in the
                // footer (🌐 More) moves by one.
                links = links.map { $0.range.location > foot.location
                    ? (NSRange(location: $0.range.location + 1, length: $0.range.length), $0.url) : $0 }
            }
            var at = (styled.string as NSString).range(of: adversary)
            while at.location != NSNotFound {
                if let image = adversaryImage {
                    let a = NSTextAttachment()
                    a.image = image
                    let side = ceil(footerFont.ascender - footerFont.descender)
                    a.bounds = NSRect(x: 0, y: footerFont.descender + 0.5, width: side, height: side)
                    let piece = NSMutableAttributedString(attachment: a)
                    piece.addAttribute(.font, value: footerFont, range: NSRange(location: 0, length: piece.length))
                    styled.replaceCharacters(in: at, with: piece)
                } else {
                    styled.replaceCharacters(in: at, with: "😠")
                    // Two units where the marker was one, as for 🤖 above.
                    links = links.map { $0.range.location > at.location
                        ? (NSRange(location: $0.range.location + 1, length: $0.range.length), $0.url) : $0 }
                }
                at = (styled.string as NSString).range(of: adversary)
            }
            let view = LinkedBody(styled, width: inner - gutter)
            view.links = links
            body = view
            bodySize = NSSize(width: inner - gutter, height: view.naturalHeight)
        }
        // **The pictures under the words**, as many as fit (2026-10-09).
        let pictures = images.compactMap { url -> (URL, NSImage)? in
            if let hit = pictureCache[url] { return (url, hit) }
            guard let image = NSImage(contentsOf: url) else { return nil }
            pictureCache[url] = image
            return (url, image)
        }
        // Laid out at their own size, then magnified with the rest.
        let laid = thumbLayout(pictures.map(\.1.size), inner: inner / s)
        let strip = (frames: laid.frames.map { NSRect(x: $0.minX * s, y: $0.minY * s, width: $0.width * s, height: $0.height * s) },
                     height: laid.height * s, hidden: laid.hidden)
        let stripH = strip.height > 0 ? strip.height + (text.isEmpty ? 0 : 8 * s) : 0
        let chrome = pad + headerH + 6 * s + stripH + pad
        // All the words need — cut to the screen only when `fit` has no width
        // left to give them; then, and only then, they scroll.
        let natural = ceil(bodySize.height)
        let bodyH = min(natural, max(22 * s, visible.height - chrome))
        let height = chrome + bodyH

        let root = ReplyRoot(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        // **Rounder** (2026-10-23, Victor: *"colțurile un pic mai rotunjite"*) — 10 until then.
        root.layer?.cornerRadius = 16 * s
        root.layer?.masksToBounds = true
        root.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        let icon = ReplyIcon(frame: NSRect(x: pad, y: height - pad - headerH, width: iconSide, height: iconSide))
        icon.image = Self.walkie
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let tty = tty {
            icon.onClick = {
                Log.info("💬 the reply pop-up's walkie clicked — \(tty) to the front, centred on the Retina, pop-up closed")
                close()
                onPresent?(tty)
            }
        }
        root.addSubview(icon)
        let gap = 6 * s
        let textX = pad + iconSide + gap
        let pinned = tty.map { !(isBound?($0) ?? false) } ?? false
        let buttons: CGFloat = tty == nil ? 1 : (pinned ? 3 : 2)
        header.frame = NSRect(x: textX, y: height - pad - headerH + 3 * s,
                              width: inner - (textX - pad) - buttons * (iconSide + gap), height: 20 * s)
        root.addSubview(header)
        if !text.isEmpty {
            let box = NSRect(x: pad, y: pad + stripH, width: inner - gutter, height: bodyH)
            if natural > bodyH + 1 {
                // **Scrolls when there is more than the room** — the wheel works on
                // a panel that is never key; a press still drags (it reaches
                // `ReplyRoot` through the clip view).
                body.frame = NSRect(x: 0, y: 0, width: inner - gutter, height: natural)
                let scroll = NSScrollView(frame: box)
                scroll.frame.size.width += 14
                scroll.drawsBackground = false
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = true
                scroll.scrollerStyle = .overlay
                scroll.scrollerKnobStyle = .light
                scroll.documentView = body
                // The beginning first. A text field is a flipped view: its top is
                // y 0 — scrolling to `natural - bodyH` opened on the last lines.
                scroll.contentView.scroll(to: NSPoint(x: 0, y: body.isFlipped ? 0 : natural - bodyH))
                root.addSubview(scroll)
            } else {
                body.frame = NSRect(x: pad, y: pad + stripH + bodyH - natural, width: inner - gutter, height: natural)
                root.addSubview(body)
            }
        }
        var thumbs: [NSRect] = []
        for (i, f) in strip.frames.enumerated() {
            let thumb = ReplyThumb(frame: f.offsetBy(dx: pad, dy: pad))
            thumb.image = pictures[i].1
            let rest = pictures[i...].map(\.0)
            let last = i == strip.frames.count - 1 && strip.hidden > 0
            if last { thumb.more = strip.hidden }
            thumb.onClick = { open(last ? rest : [rest[0]]) }
            root.addSubview(thumb)
            thumbs.append(thumb.frame)
        }
        // **The ✕ as large as the walkie** (2026-10-08, Victor: *"X-ul … aceeași
        // mărime ca și simbolul Walkie Talkie"*).
        let x = ReplyCloseButton(frame: NSRect(x: width - pad - iconSide, y: height - pad - headerH, width: iconSide, height: iconSide))
        x.onClick = { Log.info("💬 answer dismissed (✕)"); close() }
        root.addSubview(x)
        var hot = [x.frame] + thumbs
        if tty != nil { hot.append(icon.frame) }
        if let tty = tty {
            let skull = ReplyCloseButton(frame: x.frame.offsetBy(dx: -(iconSide + gap), dy: 0))
            skull.glyph = "☠️"
            skull.dead = shownDead
            // **The 🪦's words, on hover** — drawn under it: a tooltip never
            // shows on a panel of an app that is not active.
            let hint = InertLabel(labelWithString: deadHint)
            hint.font = .systemFont(ofSize: 12)
            hint.textColor = .white
            hint.alignment = .center
            hint.wantsLayer = true
            hint.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
            hint.layer?.cornerRadius = 5
            let hintW = ceil(hint.intrinsicContentSize.width) + 14
            hint.frame = NSRect(x: x.frame.maxX - hintW, y: skull.frame.minY - 24, width: hintW, height: 20)
            hint.isHidden = true
            skull.onHover = { [weak hint, weak skull] inside in hint?.isHidden = !(inside && skull?.dead == true) }
            let blast = CGPoint(x: skull.frame.midX, y: skull.frame.midY)
            skull.onClick = {
                Log.info("💬 the reply pop-up's ☠️ clicked — kamikaze to \(tty), pop-up blown up")
                shatter(.explode(from: blast))
                onKamikaze?(tty)
            }
            root.addSubview(skull)
            root.addSubview(hint)
            skullButton = skull
            hot.append(skull.frame)
            // **📍 left of the ☠️, only while another terminal is bound** — the
            // caret's map pin (`Glyphs.mapPin`), not 💬.
            if pinned {
                let pin = ReplyCloseButton(frame: skull.frame.offsetBy(dx: -(iconSide + gap), dy: 0))
                pin.image = Glyphs.mapPin(height: (iconSide * 0.6).rounded())
                pin.onClick = {
                    Log.info("💬 the reply pop-up's 📍 clicked — binding \(tty), pop-up closed")
                    close()
                    onBind?(tty)
                }
                root.addSubview(pin)
                hot.append(pin.frame)
            }
            let fit = min(header.frame.width, header.intrinsicContentSize.width)
            let link = NSRect(x: header.frame.minX, y: header.frame.minY, width: fit, height: header.frame.height)
            hot.append(link)
            root.link = (link, { header.onClick?() })
        }
        root.hot = hot
        if let linked = body as? LinkedBody {
            root.bodyLink = { [weak root, weak linked] p in
                guard let root, let linked, let hit = linked.link(at: linked.convert(p, from: root)) else { return nil }
                // Not over the part of the words scrolled out of sight.
                guard linked.visibleRect.contains(linked.convert(p, from: root)) else { return nil }
                return (hit.url, root.convert(hit.rect, from: linked))
            }
            root.linkRectsInRoot = { [weak root, weak linked] in
                guard let root, let linked else { return [] }
                return linked.rects().map { root.convert($0, from: linked) }
            }
        }
        return root
    }

    /// **A background app's `NSCursor.set()` is ignored unless the process asks
    /// for it** — the window server keeps the frontmost app's cursor. Once per
    /// launch; the same private property every pointer utility sets.
    private static let allowCursorInBackground: Void = {
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }()

    /// **Closed by 🔼 → over it: the pop-up bursts to the right** (2026-10-09) —
    /// `ReplyBurst`, his focus sent on to the terminal. The queue moves on as on
    /// any close. **☠️ blows it up** instead (`.explode(from:)`, 2026-10-14).
    static func shatter(_ style: ReplyBurst.Style = .dissolve) {
        guard let p = panel, let image = snapshot(p) else { return close() }
        let frame = p.frame, level = p.level
        close()
        guard ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        ReplyBurst.play(image: image.cg, scale: image.scale, from: frame, level: level, style: style)
    }

    /// The pop-up as it looks, rendered from its layer tree (the rounded dark
    /// body included — `cacheDisplay` draws views and skips the layer's fill).
    private static func snapshot(_ p: NSPanel) -> (cg: CGImage, scale: CGFloat)? {
        guard let layer = p.contentView?.layer else { return nil }
        let scale = p.backingScaleFactor
        let size = layer.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        return ctx.makeImage().map { ($0, scale) }
    }

    static func close() {
        panel?.orderOut(nil)
        panel = nil
        if liveOpen {
            dismissedLive = liveToken
            onLiveDismissed?()
        }
        liveOpen = false
        shown = nil
        shownRaw = nil
        shownTTY = nil
        shownDead = false
        watchTimer?.invalidate()
        watchTimer = nil
        shownImages = []
        wheel = nil
        pictureCache = [:]
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // The next hop, so a click that closed this one is over before the
        // next panel lands under the pointer.
        DispatchQueue.main.async {
            guard panel == nil else { queue.insert(next, at: 0); return }
            present(next.text, from: next.label, tty: next.tty, images: next.images)
        }
    }


    /// How far under the pointer the top edge settles.
    private static let belowPointer: CGFloat = 14
    private static let zoomSeconds = 0.3
    private static let zoomFrom: CGFloat = 0.3
    private static var zoomTimer: Timer?

    /// Centred on the pointer's x, top edge `belowPointer` under it — above the
    /// pointer instead when there is no room below; clamped into its screen.
    private static func origin(for size: NSSize, at point: NSPoint) -> NSPoint {
        let visible = screen(at: point)?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var x = point.x - size.width / 2
        var y = point.y - belowPointer - size.height
        if y < visible.minY { y = point.y + belowPointer }
        x = max(visible.minX, min(x, visible.maxX - size.width))
        y = max(visible.minY, min(y, visible.maxY - size.height))
        return NSPoint(x: x, y: y)
    }

    private static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// **It grows out of the pointer, small to full, fading in** (2026-10-08,
    /// Victor: *"should not swipe in from the bottom, but zoom in … from small to
    /// its final size, by also increasing in opacity. To be less disturbed of
    /// transition in the brain"*) — it was a toast rising from the screen's
    /// bottom edge that morning. Scale `zoomFrom` → 1 on an ease-out cubic, no
    /// overshoot, around the edge's centre nearest the pointer; alpha 0 → 1 over
    /// the same `zoomSeconds`. A timer on the root layer's transform, so nothing
    /// relayouts; the shadow is re-cut every frame to follow the shape.
    private static func zoom(_ p: NSPanel, around point: NSPoint) {
        zoomTimer?.invalidate()
        guard ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil,
              let layer = p.contentView?.layer else { return }
        let f = p.frame
        let a = CGPoint(x: min(max(point.x, f.minX), f.maxX) - f.minX,
                        y: point.y > f.midY ? f.height : 0)
        func scaled(_ k: CGFloat) -> CATransform3D {
            CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(a.x, a.y, 0), k, k, 1), -a.x, -a.y, 0)
        }
        let start = Date()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = scaled(zoomFrom)
        CATransaction.commit()
        p.alphaValue = 0
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { timer in
            guard panel === p else { timer.invalidate(); return }
            let u = min(1, Date().timeIntervalSince(start) / zoomSeconds)
            let e = 1 - pow(1 - u, 3)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = u >= 1 ? CATransform3DIdentity : scaled(zoomFrom + (1 - zoomFrom) * CGFloat(e))
            CATransaction.commit()
            p.alphaValue = CGFloat(e)
            p.invalidateShadow()
            if u >= 1 { timer.invalidate() }
        }
        RunLoop.main.add(t, forMode: .common)
        zoomTimer = t
    }
}


/// The pop-up's window: every wheel event over it — the scrolling words'
/// included — is offered to `ReplyPanel.grow` first.
private final class ReplyWindow: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            // The wheel as the hand rolled it: up = positive, natural scrolling or not.
            let dy = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            if abs(dy) > abs(event.scrollingDeltaX),
               ReplyPanel.grow(self, by: dy, precise: event.hasPreciseScrollingDeltas) { return }
        }
        super.sendEvent(event)
    }
}

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

/// **The panel's own surface: an arrow, and a press drags it** (2026-10-08).
/// The arrow because the window server keeps the frontmost app's cursor —
/// Victor saw Chrome's under the panel (*"the mouse has the icon from what's
/// underneath"*); `hot` are the clickable rects, where the hand is theirs.
private final class ReplyRoot: NSView {
    var hot: [NSRect] = []
    /// **The name is clicked through here, not through its label** (2026-10-08,
    /// Victor: *"even if I drag on the title, it should still be draggable"* —
    /// the `NSTextField` never moved the panel): a press on `link` that does not
    /// move is the name's click, one that moves drags.
    var link: (rect: NSRect, click: () -> Void)?
    /// **A link in the words under this point** (2026-10-10, `QuickAsk.cited`):
    /// its URL and its rect, both in this view.
    var bodyLink: ((NSPoint) -> (url: URL, rect: NSRect)?)?
    /// The pressed link in the words, opened on a release that did not drag.
    private var pressedURL: URL?
    /// **Its URL under it on hover** (Victor: *"la hover pe acela să apară
    /// URL-ul complet"*) — drawn here: AppKit's tool tips do not show for an
    /// app that is not frontmost, and this one never is.
    private var tip: NSTextField?
    private var tipFor: URL?
    private var press = PressOrDrag()
    private var onLink = false

    /// After the view replaced its predecessor under a still pointer.
    func refreshHover() {
        guard let w = window else { return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) { arrow(at: p) }
    }
    private func arrow(_ event: NSEvent) { arrow(at: convert(event.locationInWindow, from: nil)) }
    private func arrow(at p: NSPoint) {
        if let hit = bodyLink?(p) {
            NSCursor.pointingHand.set()
            showTip(for: hit.url, under: hit.rect)
            return
        }
        hideTip()
        if !hot.contains(where: { $0.contains(p) }) { NSCursor.arrow.set() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    /// The page's address, without the quote's `#:~:text=` and readable.
    static func shown(_ url: URL) -> String {
        // More is not a page (tester 2026-10-22: its tip read `walkie-quick:more`).
        if url == ReplyPanel.moreURL { return "Search the web again, for other sources" }
        var s = url.absoluteString
        if let r = s.range(of: ":~:") { s = String(s[..<r.lowerBound]) }
        if s.hasSuffix("#") { s.removeLast() }
        return s.removingPercentEncoding ?? s
    }

    private func showTip(for url: URL, under rect: NSRect) {
        guard tipFor != url else { return }
        hideTip()
        let t = InertLabel(wrappingLabelWithString: Self.shown(url))
        t.font = NSFont.systemFont(ofSize: 12)
        t.textColor = NSColor.white.withAlphaComponent(0.9)
        t.drawsBackground = true
        t.backgroundColor = NSColor(white: 0.25, alpha: 1)
        t.lineBreakMode = .byCharWrapping
        let maxW = bounds.width - 16
        t.preferredMaxLayoutWidth = maxW
        var size = t.sizeThatFits(NSSize(width: maxW, height: .greatestFiniteMagnitude))
        size.width = min(ceil(size.width) + 2, maxW)
        // Under the link, or over it when there is no room under.
        var y = rect.minY - size.height - 3
        if y < 4 { y = min(rect.maxY + 3, bounds.height - size.height - 4) }
        let x = min(max(8, rect.minX), bounds.width - 8 - size.width)
        t.frame = NSRect(x: x, y: y, width: size.width, height: ceil(size.height))
        t.wantsLayer = true
        t.layer?.cornerRadius = 4
        t.layer?.masksToBounds = true
        addSubview(t)
        tip = t
        tipFor = url
    }

    /// Desk: the tip on screen, and every link's rect in this view.
    var tipText: String? { tip?.stringValue }
    var linkRects: [NSRect] { linkRectsInRoot?() ?? [] }
    var linkRectsInRoot: (() -> [NSRect])?

    private func hideTip() {
        tip?.removeFromSuperview()
        tip = nil
        tipFor = nil
    }

    override func mouseExited(with event: NSEvent) { hideTip() }
    override func cursorUpdate(with event: NSEvent) { arrow(event) }
    override func mouseEntered(with event: NSEvent) { arrow(event) }
    override func mouseMoved(with event: NSEvent) { arrow(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pressedURL = bodyLink?(p)?.url
        onLink = pressedURL != nil || link?.rect.contains(p) == true
        if onLink { press.down(window) } else { window?.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { if onLink { hideTip(); press.dragged(window) } }
    override func mouseUp(with event: NSEvent) {
        guard onLink else { return }
        onLink = false
        let url = pressedURL
        pressedURL = nil
        guard press.up() else { return }
        if let url { ReplyPanel.openLink(url) } else { link?.click() }
    }
}

/// **A press on a clickable that moves is a drag, not a click** (2026-10-08,
/// Victor: *"I should be able to drag not only on the text but anything as long
/// as I don't click it but drag it"*). Past `slop` the panel follows the
/// pointer and the release clicks nothing.
private struct PressOrDrag {
    static let slop: CGFloat = 3
    private var from: NSPoint = .zero
    private var origin: NSPoint = .zero
    private var dragging = false

    mutating func down(_ window: NSWindow?) {
        from = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragging = false
    }

    mutating func dragged(_ window: NSWindow?) {
        let p = NSEvent.mouseLocation
        let dx = p.x - from.x, dy = p.y - from.y
        if !dragging, hypot(dx, dy) < Self.slop { return }
        dragging = true
        window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    /// True when the press was a click.
    mutating func up() -> Bool { defer { dragging = false }; return !dragging }
}

/// **Words with links** (2026-10-10): a text view, never hit like the label, so
/// a press is still `ReplyRoot`'s — which asks it which link is under it.
private final class LinkedBody: NSTextView {
    var links: [(range: NSRange, url: URL)] = []

    convenience init(_ text: NSAttributedString, width: CGFloat) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        self.init(frame: NSRect(x: 0, y: 0, width: width, height: 10), textContainer: container)
        isEditable = false
        isSelectable = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
    }

    var naturalHeight: CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 0 }
        lm.ensureLayout(for: tc)
        return ceil(lm.usedRect(for: tc).height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Each link's first laid-out rect, in order.
    func rects() -> [NSRect] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        return links.map { l in
            var first = NSRect.zero
            lm.enumerateEnclosingRects(forGlyphRange: lm.glyphRange(forCharacterRange: l.range, actualCharacterRange: nil),
                                       withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, stop in
                first = r; stop.pointee = true
            }
            return first
        }
    }

    /// The link under `p` (this view's points) and its laid-out rect.
    func link(at p: NSPoint) -> (url: URL, rect: NSRect)? {
        guard !links.isEmpty, let lm = layoutManager, let tc = textContainer else { return nil }
        let g = lm.glyphIndex(for: p, in: tc)
        // A few points around the glyph: a lone ↗ is a small target.
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: -4, dy: -2).contains(p)
        else { return nil }
        let c = lm.characterIndexForGlyph(at: g)
        guard let hit = links.first(where: { NSLocationInRange(c, $0.range) }) else { return nil }
        let glyphs = lm.glyphRange(forCharacterRange: hit.range, actualCharacterRange: nil)
        // The part of the link on the pointer's line, when it wraps.
        var rect = NSRect.zero
        lm.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                   in: tc) { r, stop in
            if r.insetBy(dx: -4, dy: -2).contains(p) { rect = r; stop.pointee = true }
        }
        return (hit.url, rect == .zero ? lm.boundingRect(forGlyphRange: glyphs, in: tc) : rect)
    }
}

/// The answer's words: never the target of a click, so a press on them is
/// `ReplyRoot`'s drag and no selection starts.
private final class InertLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The ✕ (and, with a `glyph`, the ☠️ — a 🪦 once `dead`) — drawn, not an `NSButton`: a button in
/// a non-activating panel looks disabled and eats the first click.
private final class ReplyCloseButton: NSView {
    var onClick: (() -> Void)?
    var glyph: String?
    /// A drawn picture in place of the glyph (the 📍's map pin).
    var image: NSImage?
    /// **A session already gone** — the ☠️ turns 🪦, no hand, a click does
    /// nothing (a press still drags the pop-up).
    var dead = false { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self); onHover?(hot) } }
    /// The pointer came in (true) or left (false).
    var onHover: ((Bool) -> Void)?
    private var hot = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hot && !dead ? 0.25 : 0.1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        if let image = image {
            image.draw(in: NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
            return
        }
        if let glyph = dead ? "🪦" : glyph {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: bounds.height * 0.55)]
            let size = (glyph as NSString).size(withAttributes: a)
            (glyph as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: a)
            return
        }
        let p = NSBezierPath()
        let r = bounds.insetBy(dx: bounds.width * 0.32, dy: bounds.height * 0.32)
        p.move(to: NSPoint(x: r.minX, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        p.move(to: NSPoint(x: r.minX, y: r.maxY)); p.line(to: NSPoint(x: r.maxX, y: r.minY))
        p.lineWidth = 1.8
        NSColor.white.withAlphaComponent(0.85).setStroke()
        p.stroke()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    private var hand: NSCursor { dead ? .arrow : .pointingHand }
    override func cursorUpdate(with event: NSEvent) { hand.set() }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true; hand.set(); onHover?(true) }
    override func mouseMoved(with event: NSEvent) { hand.set() }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true; NSCursor.arrow.set(); onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) {
        guard press.up() else { return }
        if dead { Log.info("💬 the 🪦 of a session already gone clicked — nothing to kill"); return }
        onClick?()
    }
}

/// **A picture the agent sent** (2026-10-09): drawn to fill its box, rounded,
/// a hairline round it; the hand on hover, a click opens it full size
/// (`ReplyPanel.open`), a press that moves drags the pop-up. `more` > 0 draws
/// `+N` over the last one shown — the pictures that did not fit.
private final class ReplyThumb: NSView {
    var image: NSImage?
    var more = 0
    var onClick: (() -> Void)?
    private var press = PressOrDrag()
    override func draw(_ dirtyRect: NSRect) {
        let clip = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if let image {
            // Fill the box, cropping the overflow — a strip of letterboxes reads
            // as broken pictures.
            let s = image.size
            let k = max(bounds.width / max(s.width, 1), bounds.height / max(s.height, 1))
            let w = s.width * k, h = s.height * k
            image.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h))
        }
        if more > 0 {
            NSColor.black.withAlphaComponent(0.55).setFill()
            bounds.fill()
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                                                    .foregroundColor: NSColor.white]
            let t = "+\(more)" as NSString
            let ts = t.size(withAttributes: a)
            t.draw(at: NSPoint(x: (bounds.width - ts.width) / 2, y: (bounds.height - ts.height) / 2), withAttributes: a)
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.2).setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        edge.lineWidth = 1
        edge.stroke()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
}

/// The walkie: a button only when the answer names a terminal — the hand on
/// hover, a click brings that terminal forward (`ReplyPanel.onPresent`).
private final class ReplyIcon: NSImageView {
    var onClick: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        guard onClick != nil else { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    /// Not a button → part of the surface, so a press there drags.
    override func hitTest(_ point: NSPoint) -> NSView? { onClick == nil ? nil : super.hitTest(point) }
    override func cursorUpdate(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseEntered(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseMoved(with event: NSEvent) { if onClick != nil { NSCursor.pointingHand.set() } }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
}

/// The header: plain text, or — when it names a terminal — a link: the hand
/// cursor and an underline while the pointer is on it, a click binds it.
private final class LinkLabel: NSTextField {
    var onClick: (() -> Void)? { didSet { window?.invalidateCursorRects(for: self) } }

    private func underline(_ on: Bool) {
        guard onClick != nil else { return }
        // The paragraph style carries the … : an attributed value without one
        // wraps instead, and the hovered title would lose its ellipsis.
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: stringValue,
                                          attributes: [.font: font as Any, .foregroundColor: textColor as Any,
                                                       .paragraphStyle: para])
        if on { s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                               range: NSRange(location: 0, length: s.length)) }
        attributedStringValue = s
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        guard onClick != nil else { return }
        let fit = NSRect(x: 0, y: 0, width: min(bounds.width, intrinsicContentSize.width), height: bounds.height)
        addTrackingArea(NSTrackingArea(rect: fit, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways],
                                       owner: self))
    }
    // **The hand on enter and on every move, not only `cursorUpdate`** (Victor,
    // 2026-10-08: *"the mouse should turn into a hand once I hover the title"*
    // — the underline came, the hand did not): the panel never becomes key, so
    // the frontmost terminal's I-beam won the cursor back.
    /// Never hit: a press on it is `ReplyRoot`'s — a drag, or the name's click.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { underline(true); NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { underline(false); NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
