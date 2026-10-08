import Cocoa
import CoreAudio

/// **"(walkie) Listening 🎤"** — a green tab that rises from the
/// bottom edge of the screen under the mouse when the microphone this app would
/// record through changes, holds ~2.5 s and falls away (2026-09-23).
///
/// Victor: *"pune notificarea verde de jos sa vina de la walkie"*. It was Victor
/// Addons' for one afternoon, announcing the **system default input** — and on
/// the first real plug-in it said nothing at all: the DJI receiver went in,
/// this app and addons' Whisper both moved to it, and the system default stayed
/// on the WH-1000XM3 headphones, so an announcer watching the default had
/// nothing to announce. What is worth saying is what *records*, which is
/// `InputDevice.resolve()` — the choice file plus the ladder over the devices
/// present, the same answer the chip, the menu and `MicRecorder` read.
///
/// **Triggers:** a CoreAudio device-list change (a plug or an unplug) and a
/// change of `~/.walkie-talkie/mic/choice` (either app's menu). Every trigger
/// only restarts a 0.6 s settle — a plug-in fires a burst — and the resolver is
/// asked once when it expires; a burst that ends where it began says nothing.
/// **Never at launch**: the device present then is the baseline. The system
/// default input is deliberately **not** a trigger: it is not what this app
/// records through, and Victor Addons now moves it off the WH-1000XM3 on its
/// own, which would otherwise raise a second tab about a device nobody records.
///
/// **The look is Victor Addons' `BottomTabBanner`, reproduced** — green, flush
/// on the bottom edge, top corners rounded, click-through, non-activating.
/// Reproduced rather than shared because this app must not depend on that
/// private one; the ~100 lines here are the accepted price.
///
/// **Same words as addons' pill, behind the app's own icon** (2026-09-26,
/// Victor: *"walkie talkie sa aiba acelasi mesaj, dar precedat de iconul lui
/// cu portocaliu in jur"*). Both apps now say `Listening 🎤`; the orange-ringed
/// `walkie-bound` device in front is what says *which* app is saying it.
final class MicAnnouncer {

    static let settle: TimeInterval = 0.6
    static let hold: TimeInterval = 2.5
    static let tint = NSColor.systemGreen.withAlphaComponent(0.85)
    /// **The launch tab** (2026-09-28, Victor: *"when walkie starts up, it should
    /// show an overlay on the bottom saying what source/engine it uses. this way
    /// I know when it restarted"*) — the same tab, blue so it is not mistaken for
    /// the microphone's green, up for 3 s with the Engine row's words.
    static let startupTint = NSColor.systemBlue.withAlphaComponent(0.85)
    static let startupHold: TimeInterval = 3.0
    /// What the launch tab said — `GET /test/state.startupBanner`, the wave
    /// spelled `〰`.
    private(set) var startupText: String?

    /// **A sound wave between the microphone and the engine** (2026-10-08,
    /// Victor, over a seven-bar wave: *"put such a wave, but symmetrical both
    /// sides … in between the microphone and the engine"* — the ` / ` of the
    /// same morning, drawn). A private-use character in the text; `BottomTab`
    /// draws `WaveGlyph` in its place.
    static let wave = "\u{E000}"
    static func readable(_ text: String) -> String { text.replacingOccurrences(of: wave, with: "〰") }

    /// The Engine row's words for the green tab — read on main when it rises,
    /// so a device change names the engine that will hear it.
    var engine: (() -> String?)?

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.mic-announcer", qos: .utility)
    private var pending: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?
    /// What was last announced (or the baseline): `glyph + label`, or the bare
    /// CoreAudio name for a device none of `known` names. Queue only.
    private var last = ""
    private let tab = BottomTab(icon: MicAnnouncer.icon)

    /// `walkie-bound.png` — the device inside its orange ring, the Dock tile's
    /// artwork. nil (no file) leaves the tab with the text alone.
    private static let icon: NSImage? = RelayWindow.walkieURL("walkie-bound")
        .flatMap { NSImage(contentsOf: $0) }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.last = Self.current().key
            Log.info("🎤 mic announcer: baseline \(self.last.isEmpty ? "none" : self.last)")
            var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.poke() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &addr, self.queue, block) == noErr {
                self.listener = block
            } else {
                Log.error("🎤 mic announcer: cannot watch the device list")
            }
        }
    }

    /// The choice file changed (either app's menu). Called from `MicChoice.watch`.
    func choiceChanged() { queue.async { [weak self] in self?.poke() } }

    /// **Say what engine this launch runs on** — main thread, once, right after
    /// the engine is decided. Never under `RELAY_SHOOT`.
    ///
    /// **The microphone in front of it** (2026-10-05, Victor: *"să afișeze
    /// înaintea motorului folosit și device-ul de microfon, simbolul pentru
    /// microfonul în folosire la pornire"*) — the resolved device's glyph, the
    /// green tab's own, or `🎙️ <name>` for one `known` does not name.
    func announceStartup(engine: String) {
        guard !RelayWindow.shooting else { return }
        let r = InputDevice.resolve()
        let mic = r.known?.glyph ?? r.device.map { "🎙️ \($0.name)" }
        // **A slash between the microphone and the engine** (2026-10-08, Victor:
        // *"put a slash between the emoji meaning the input source and … the
        // transcription engine"*) — `🎤 / ElevenLabs ☁️ + Live`.
        let text = [mic, engine].compactMap { $0 }.joined(separator: " \(Self.wave) ")
        startupText = Self.readable(text)
        Log.info("🚀 up on \(Self.readable(text)) — the launch tab")
        tab.show(text, tint: Self.startupTint, hold: Self.startupHold)
    }

    /// Restart the settle. Runs on `queue`.
    private func poke() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settled() }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    private func settled() {
        let now = Self.current()
        guard !now.key.isEmpty, now.key != last else { return }
        last = now.key
        DispatchQueue.main.async { [weak self, tab] in
            let text = [now.text, self?.engine?()].compactMap { $0 }.joined(separator: " \(Self.wave) ")
            Log.info("🎤 mic → \(Self.readable(text))")
            tab.show(text, tint: Self.tint, hold: Self.hold)
        }
    }

    /// The resolved device as a comparable key and the tab's copy.
    private static func current() -> (key: String, text: String) {
        let r = InputDevice.resolve()
        if let k = r.known { return ("\(k.id) \(r.device?.name ?? "")", cardText(glyph: k.glyph)) }
        guard let name = r.device?.name else { return ("", "") }
        return (name, cardText(glyph: "🎙️ \(name)"))
    }

    /// The exact copy — `Listening 🎤`, Victor Addons' wording. A device none
    /// of `known` names passes `🎙️ <its name>`, the only thing that says which.
    static func cardText(glyph: String) -> String { "Listening \(glyph)" }
}

/// Victor Addons' `BottomTabBanner`, cut down to what the announcer uses: one
/// panel on the screen under the mouse, nailed to its bottom edge, with the
/// tab sliding *inside* it so no pixel of the motion lands on a display below.
private final class BottomTab {
    private static let height: CGFloat = 76
    private static let radius: CGFloat = 18
    private static let padding: CGFloat = 34
    private static let font = NSFont.boldSystemFont(ofSize: 40)
    private static let iconSide: CGFloat = 56
    private static let iconGap: CGFloat = 14

    private let icon: NSImage?
    /// Room the icon takes before the label: 0 without one.
    private var lead: CGFloat { icon == nil ? 0 : Self.iconSide + Self.iconGap }

    init(icon: NSImage?) { self.icon = icon }

    private var panel: NSPanel?
    private var tabView: NSView?
    private var label: NSTextField?
    private var tintView: NSView?
    private var motion: Timer?
    private var holdTimer: Timer?
    /// The wave's glint, 30 fps while the tab shows a wave (`WaveGlyph.glint`).
    private var glintTimer: Timer?
    private var shownText = ""
    /// The tab sliding up, and down, in seconds.
    private static let rise: TimeInterval = 0.32, fall: TimeInterval = 0.45
    /// The dim wire before the light sets off, and after it has gone — see `startGlint`.
    private static let glintLead: TimeInterval = 0.5, glintQuiet: TimeInterval = 0.3

    func show(_ text: String, tint: NSColor, hold: TimeInterval) {
        shownText = text
        // One pass inside the hold, a quiet wire on either side of it: the light
        // starts `glintLead` after the tab is in and is gone `glintQuiet` before
        // it falls away.
        startGlint(after: (panel == nil ? Self.rise : 0) + Self.glintLead,
                   lasting: max(hold - Self.glintLead - Self.glintQuiet, 0.3))
        if let label, let panel, let tabView {
            label.attributedStringValue = Self.attributed(text)
            tintView?.layer?.backgroundColor = tint.cgColor
            resize(panel: panel, tab: tabView, label: label, text: text)
            startHold(hold)
            return
        }
        guard let screen = Self.screenUnderMouse() else { return }
        let width = width(for: text, screen: screen)
        let f = screen.frame
        let rect = NSRect(x: f.minX + ((f.width - width) / 2).rounded(), y: f.minY,
                          width: width, height: Self.height)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isFloatingPanel = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Never in a screenshot (`sharingType = .none`), like every other overlay
        // this app puts on screen — a green tab announcing the microphone is a
        // decoration, not something that belongs in a captured frame.
        p.sharingType = .none

        let content = NSView(frame: NSRect(origin: .zero, size: rect.size))
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        let tab = NSView(frame: NSRect(x: 0, y: -Self.height, width: width, height: Self.height))
        tab.wantsLayer = true
        tab.layer?.cornerRadius = Self.radius
        tab.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        tab.layer?.masksToBounds = true
        let effect = NSVisualEffectView(frame: tab.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        tab.addSubview(effect)
        let tintV = NSView(frame: tab.bounds)
        tintV.autoresizingMask = [.width, .height]
        tintV.wantsLayer = true
        tintV.layer?.backgroundColor = tint.cgColor
        tab.addSubview(tintV)
        let l = NSTextField(labelWithString: "")
        l.font = Self.font
        l.lineBreakMode = .byTruncatingTail
        l.attributedStringValue = Self.attributed(text)
        l.frame = labelFrame(width: width)
        tab.addSubview(l)
        if let icon {
            let iv = NSImageView(frame: NSRect(x: Self.padding, y: ((Self.height - Self.iconSide) / 2).rounded(),
                                               width: Self.iconSide, height: Self.iconSide))
            iv.image = icon
            iv.imageScaling = .scaleProportionallyUpOrDown
            tab.addSubview(iv)
        }
        content.addSubview(tab)
        p.contentView = content
        p.alphaValue = 0.92
        p.orderFrontRegardless()

        panel = p; tabView = tab; label = l; tintView = tintV
        animate(rising: true, duration: Self.rise) { [weak self] in self?.startHold(hold) }
    }

    private func resize(panel: NSPanel, tab: NSView, label: NSTextField, text: String) {
        guard let screen = panel.screen ?? Self.screenUnderMouse() else { return }
        let width = width(for: text, screen: screen)
        let f = screen.frame
        let y = tab.frame.origin.y
        panel.setFrame(NSRect(x: f.minX + ((f.width - width) / 2).rounded(), y: f.minY,
                              width: width, height: Self.height), display: true)
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        tab.frame = NSRect(x: 0, y: y, width: width, height: Self.height)
        label.frame = labelFrame(width: width)
    }

    private func startHold(_ hold: TimeInterval) {
        holdTimer?.invalidate()
        let t = Timer(timeInterval: hold, repeats: false) { [weak self] _ in
            self?.animate(rising: false, duration: Self.fall) { [weak self] in self?.teardown() }
        }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    /// **A bright spot runs along the wave, microphone → engine** (2026-10-08,
    /// Victor: *"a bit animated … from the microphone towards the
    /// transcription … like a bright section moving, from left to right …
    /// something gentle"*). The attachment is redrawn with the glint further on.
    ///
    /// **Once, timed to the tab** (same day, Victor: *"the light moving through
    /// should get at its end when the overlay disappears, (not restart from
    /// left)"*), then *"it finishes too late now. When it's done … only then …
    /// falls out of screen"*: `lasting` is the rise and the hold, so the head
    /// reaches the wave's right end as the fall begins. A `show` over a tab
    /// already up starts a new pass over its new hold.
    ///
    /// **A beat of nothing on either side** (2026-10-08, Victor: *"should start
    /// animating half a second after the overlay flies in from the bottom, and
    /// end … 300 milliseconds … [before], to be a time that there is no more
    /// signal to increase the suspense"*): the wire sits dim and empty for
    /// `after` (the rise + `glintLead`), the light runs for `lasting`, and it has
    /// left the wave — tail included — `glintQuiet` before the fall.
    private func startGlint(after delay: TimeInterval, lasting: TimeInterval) {
        glintTimer?.invalidate()
        glintTimer = nil
        guard shownText.contains(MicAnnouncer.wave) else { return }
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] tm in
            guard let self, let label = self.label else {
                if self?.panel == nil { tm.invalidate() }
                return
            }
            // Below 0 the head has not reached the wave yet: a dim, empty wire.
            let phase = min(1, (Date().timeIntervalSince(start) - delay) / lasting)
            label.attributedStringValue = Self.attributed(self.shownText, glint: CGFloat(phase))
        }
        RunLoop.main.add(t, forMode: .common)
        glintTimer = t
    }

    private func teardown() {
        glintTimer?.invalidate()
        glintTimer = nil
        panel?.orderOut(nil)
        panel = nil; tabView = nil; label = nil; tintView = nil
    }

    /// Rising eases out, falling eases in — the plain quadratics addons uses.
    private func animate(rising: Bool, duration: TimeInterval, completion: @escaping () -> Void) {
        motion?.invalidate()
        let start = Date()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] tm in
            guard let self, let tab = self.tabView else { tm.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(start) / duration)
            let eased = rising ? 1 - (1 - p) * (1 - p) : p * p
            tab.frame.origin.y = -Self.height * CGFloat(rising ? 1 - eased : eased)
            if p >= 1 { tm.invalidate(); self.motion = nil; completion() }
        }
        RunLoop.main.add(t, forMode: .common)
        motion = t
        t.fire()
    }

    /// White, centred, bold 40 — with `MicAnnouncer.wave` drawn as `WaveGlyph`.
    private static func attributed(_ text: String, glint: CGFloat? = nil) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: para]
        let out = NSMutableAttributedString()
        for (i, part) in text.components(separatedBy: MicAnnouncer.wave).enumerated() {
            if i > 0 {
                let a = NSTextAttachment()
                let img = WaveGlyph.image(height: font.capHeight * 1.25, glint: glint)
                a.image = img
                a.bounds = NSRect(x: 0, y: (font.capHeight - img.size.height) / 2,
                                  width: img.size.width, height: img.size.height)
                let s = NSMutableAttributedString(attachment: a)
                s.addAttributes(attrs, range: NSRange(location: 0, length: s.length))
                out.append(s)
            }
            out.append(NSAttributedString(string: part, attributes: attrs))
        }
        return out
    }

    private func width(for text: String, screen: NSScreen) -> CGFloat {
        let probe = NSTextField(labelWithString: "")
        probe.font = Self.font
        probe.attributedStringValue = Self.attributed(text)
        probe.maximumNumberOfLines = 1
        probe.lineBreakMode = .byClipping
        probe.sizeToFit()
        let hugging = ceil(probe.frame.width) + 8 + 2 * Self.padding + lead
        return max(220, min(hugging, screen.frame.width * 0.6))
    }

    private func labelFrame(width: CGFloat) -> NSRect {
        let lm = NSLayoutManager()
        var h = lm.defaultLineHeight(for: Self.font)
        if let emoji = NSFont(name: "AppleColorEmoji", size: Self.font.pointSize) {
            h = max(h, lm.defaultLineHeight(for: emoji))
        }
        h = ceil(h)
        return NSRect(x: Self.padding + lead, y: (Self.height - h) / 2,
                      width: width - 2 * Self.padding - lead, height: h)
    }

    private static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}

/// **The wave Victor picked** (2026-10-08, an icon he pasted: *"use this"*) —
/// a flat lead-in, a zigzag of sharp peaks with rounded corners, a flat
/// lead-out, drawn as one white wire at the text's size. It replaced the same
/// morning's seven mirrored bars and then the rounded serpentine through them.
enum WaveGlyph {
    /// The icon's corners, traced off his picture (960 px, the flat line at
    /// y 490, the tallest peak 250 px above it): x across the wave 0…1, y
    /// −1…1 about the flat line, up positive.
    static let corners: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0.086, y: 0), CGPoint(x: 0.136, y: 0.248),
        CGPoint(x: 0.164, y: -0.24), CGPoint(x: 0.240, y: 0.56), CGPoint(x: 0.286, y: -0.62),
        CGPoint(x: 0.371, y: 1.0), CGPoint(x: 0.460, y: -0.992), CGPoint(x: 0.546, y: 0.44),
        CGPoint(x: 0.621, y: -0.488), CGPoint(x: 0.707, y: 0.82), CGPoint(x: 0.800, y: -0.808),
        CGPoint(x: 0.857, y: 0.328), CGPoint(x: 0.893, y: 0), CGPoint(x: 1, y: 0),
    ]
    /// Width over height, as in his picture (700 × 500 px between the ends and
    /// the extremes).
    static let aspect: CGFloat = 1.4

    /// The wire's brightness away from the light.
    static let dim: CGFloat = 0.5

    /// `glint`: nil draws the wire white; 0…1 is where the light's head is along
    /// it — the left end at 0, and at 1 past the right end by its own tail, so
    /// the last of it has just left (2026-10-08). Below 0: a dim, empty wire.
    ///
    /// **The light travels the wave's own trajectory** (2026-10-08, Victor drew
    /// it on screen: a short bright segment running along the wave's line —
    /// *"draw segments of it … progressing through, glowing … following the
    /// trajectory of the wavelength itself"*): a stroke of the wire's width
    /// along it, a bright head and a fading tail, glowing, over the wire at
    /// `dim`.
    static func image(height h: CGFloat, glint: CGFloat? = nil) -> NSImage {
        let wire = max(1.5, (h * 0.085).rounded())
        // Room for the round caps and the glow, on every frame alike — a glyph
        // that grew when the light came on would nudge the words beside it.
        let pad = (wire * 1.5).rounded(.up)
        let w = (h * aspect).rounded()
        return NSImage(size: NSSize(width: w + 2 * pad, height: h + 2 * pad), flipped: false) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.translateBy(x: pad, y: pad)
            // The corners in points, inset by half the wire so the peaks' round
            // ends stay inside the glyph.
            let half = (h - wire) / 2
            let pts = corners.map { CGPoint(x: wire / 2 + $0.x * (w - wire), y: h / 2 + $0.y * half) }
            cg.setLineWidth(wire)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            // Opaque inside a layer, the layer dimmed as a whole: a translucent
            // stroke shows brighter dots wherever it meets itself at a join.
            cg.saveGState()
            cg.setAlpha(glint == nil ? 1 : dim)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            cg.setStrokeColor(NSColor.white.cgColor)
            cg.addLines(between: pts)
            cg.strokePath()
            cg.endTransparencyLayer()
            cg.restoreGState()
            guard let glint else { return true }
            let path = sampled(pts, step: 0.5)
            // Arc length at every point, then the light: the head at `head`, a
            // tail `tail` long behind it.
            var at: [CGFloat] = [0]
            for j in 1..<path.count { at.append(at[j - 1] + hypot(path[j].x - path[j - 1].x, path[j].y - path[j - 1].y)) }
            let total = at[at.count - 1], tail = h * 0.75
            let head = glint * (total + tail)
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: wire * 1.6, color: NSColor.white.withAlphaComponent(0.85).cgColor)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            // A disc the wire's width at every sample from the tail's end to the
            // head, each one *replacing* what is under it (`.copy`), so the stroke
            // is as bright as its brightest point, never brighter where the discs
            // overlap — no beads, and no separate dot for the head.
            cg.setBlendMode(.copy)
            for j in 0..<path.count {
                let d = head - at[j]
                guard d >= 0, d <= tail else { continue }
                let alpha = pow(1 - d / tail, 1.2)
                cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: path[j].x - wire / 2, y: path[j].y - wire / 2, width: wire, height: wire))
            }
            cg.endTransparencyLayer()
            cg.restoreGState()
            return true
        }
    }

    /// The polyline through `pts`, a point every `step` along it.
    private static func sampled(_ pts: [CGPoint], step: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let n = max(1, Int(hypot(b.x - a.x, b.y - a.y) / step))
            for s in 0..<n {
                let t = CGFloat(s) / CGFloat(n)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }
}
