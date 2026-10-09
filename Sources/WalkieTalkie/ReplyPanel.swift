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
/// (2026-10-08, Victor: *"marginea de sus a panelului … un pic sub mouse"*). `sharingType = .none`: the next dictation's
/// pictures are of his screen, not of this.
enum ReplyPanel {
    private static var panel: NSPanel?
    private static var queue: [(text: String, label: String?, tty: String?, images: [URL])] = []
    private static var arrivedAt: NSPoint = .zero

    static let maxChars = 400
    private static let width: CGFloat = 380
    private static let font = NSFont.systemFont(ofSize: 15)
    /// 26, up from 20, to carry the 26 pt walkie (2026-10-08, *"make the icon
    /// slightly larger … so I can click it easier"*); the name and the ✕ are
    /// centred in it.
    private static let headerH: CGFloat = 26
    private static let iconSide: CGFloat = 26

    private static let walkie: NSImage? = RelayWindow.walkieURL("walkie-bound").flatMap { NSImage(contentsOf: $0) }

    /// **Desk only** (`POST /test/quick {"capturable": true}`): the next pop-ups
    /// show up in a screenshot, so a desk can see what Victor sees.
    static var capturable = false
    /// The open pop-up's frame, global Cocoa points.
    static var frame: NSRect? { panel?.frame }

    /// What is on screen — `GET /test/state`.
    static var shown: String?
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
    /// answer was the last thing he needed from it. Closes the panel.
    static var onKamikaze: ((String) -> Void)?

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
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "…" }
        if text.count > maxChars { text = String(text.prefix(maxChars)) + "…" }
        if let p = panel, liveOpen {
            let root = build(text, from: label, tty: nil)
            // The size first: assigning the content view resizes it to the
            // window's old frame, and the answer stayed cut to its first line.
            let size = root.frame.size
            p.setFrame(NSRect(x: p.frame.minX, y: p.frame.maxY - size.height,
                              width: size.width, height: size.height), display: false)
            p.contentView = root
            p.invalidateShadow()
            shown = text
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

    /// The header of every ⚡ quick answer starts with it (`AppDelegate.askQuick`).
    static let quickMark = "⚡ "

    /// The ⚡ pop-up is still being written.
    private(set) static var liveOpen = false
    private static var liveToken = 0, dismissedLive = -1
    private static var openLabel: String?

    private static func present(_ text: String, from label: String?, tty: String?, images: [URL] = []) {
        allowCursorInBackground
        shown = text
        shownTTY = tty
        shownImages = images
        openLabel = label
        arrivedAt = NSEvent.mouseLocation
        let root = build(text, from: label, tty: tty, images: images)

        let p = NSPanel(contentRect: root.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
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
        Log.info("💬 answer from \(label ?? "agent") — \(text.count) chars\(images.isEmpty ? "" : ", \(images.count) picture(s)"); up until the ✕\(queue.isEmpty ? "" : ", \(queue.count) waiting")")
    }

    /// The pop-up's content for these words — the header, the body, the buttons.
    private static func build(_ text: String, from label: String?, tty: String?, images: [URL] = []) -> ReplyRoot {
        let pad: CGFloat = 12
        let inner = width - 2 * pad
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
        let body = InertLabel(wrappingLabelWithString: text)
        body.isSelectable = false
        body.font = font
        body.textColor = .white
        body.preferredMaxLayoutWidth = inner - 18
        let bodySize = text.isEmpty ? .zero
            : body.sizeThatFits(NSSize(width: inner - 18, height: .greatestFiniteMagnitude))
        // **The pictures under the words**, as many as fit (2026-10-09).
        let pictures = images.compactMap { url in NSImage(contentsOf: url).map { (url, $0) } }
        let strip = thumbLayout(pictures.map(\.1.size), inner: inner)
        let stripH = strip.height > 0 ? strip.height + (text.isEmpty ? 0 : 8) : 0
        let height = pad + headerH + 6 + ceil(bodySize.height) + stripH + pad

        let root = ReplyRoot(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
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
        let textX = pad + iconSide + 6
        let pinned = tty.map { !(isBound?($0) ?? false) } ?? false
        let buttons: CGFloat = tty == nil ? 1 : (pinned ? 3 : 2)
        header.frame = NSRect(x: textX, y: height - pad - headerH + 3,
                              width: inner - (textX - pad) - buttons * (iconSide + 6), height: 20)
        body.frame = NSRect(x: pad, y: pad + stripH, width: inner - 18, height: ceil(bodySize.height))
        root.addSubview(header)
        if !text.isEmpty { root.addSubview(body) }
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
            let skull = ReplyCloseButton(frame: x.frame.offsetBy(dx: -(iconSide + 6), dy: 0))
            skull.glyph = "☠️"
            skull.onClick = {
                Log.info("💬 the reply pop-up's ☠️ clicked — kamikaze to \(tty), pop-up closed")
                close()
                onKamikaze?(tty)
            }
            root.addSubview(skull)
            hot.append(skull.frame)
            // **📍 left of the ☠️, only while another terminal is bound** — the
            // caret's map pin (`Glyphs.mapPin`), not 💬.
            if pinned {
                let pin = ReplyCloseButton(frame: skull.frame.offsetBy(dx: -(iconSide + 6), dy: 0))
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
    /// any close.
    static func shatter() {
        guard let p = panel, let image = snapshot(p) else { return close() }
        let frame = p.frame, level = p.level
        close()
        guard ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        ReplyBurst.play(image: image.cg, scale: image.scale, from: frame, level: level)
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
        if liveOpen { dismissedLive = liveToken }
        liveOpen = false
        shown = nil
        shownTTY = nil
        shownImages = []
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
    private var press = PressOrDrag()
    private var onLink = false
    private func arrow(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !hot.contains(where: { $0.contains(p) }) { NSCursor.arrow.set() }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func cursorUpdate(with event: NSEvent) { arrow(event) }
    override func mouseEntered(with event: NSEvent) { arrow(event) }
    override func mouseMoved(with event: NSEvent) { arrow(event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onLink = link?.rect.contains(convert(event.locationInWindow, from: nil)) == true
        if onLink { press.down(window) } else { window?.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { if onLink { press.dragged(window) } }
    override func mouseUp(with event: NSEvent) {
        guard onLink else { return }
        onLink = false
        if press.up() { link?.click() }
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

/// The answer's words: never the target of a click, so a press on them is
/// `ReplyRoot`'s drag and no selection starts.
private final class InertLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The ✕ (and, with a `glyph`, the ☠️) — drawn, not an `NSButton`: a button in
/// a non-activating panel looks disabled and eats the first click.
private final class ReplyCloseButton: NSView {
    var onClick: (() -> Void)?
    var glyph: String?
    /// A drawn picture in place of the glyph (the 📍's map pin).
    var image: NSImage?
    private var hot = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(hot ? 0.25 : 0.1).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        if let image = image {
            image.draw(in: NSRect(x: bounds.midX - image.size.width / 2, y: bounds.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
            return
        }
        if let glyph = glyph {
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
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true; NSCursor.pointingHand.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true; NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var press = PressOrDrag()
    override func mouseDown(with event: NSEvent) { press.down(window) }
    override func mouseDragged(with event: NSEvent) { press.dragged(window) }
    override func mouseUp(with event: NSEvent) { if press.up() { onClick?() } }
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
