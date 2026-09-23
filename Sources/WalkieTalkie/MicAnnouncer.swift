import Cocoa
import CoreAudio

/// **"🎤 Listening to: DJI"** — a green tab that rises from the
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
final class MicAnnouncer {

    static let settle: TimeInterval = 0.6
    static let hold: TimeInterval = 2.5
    static let tint = NSColor.systemGreen.withAlphaComponent(0.85)

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.mic-announcer", qos: .utility)
    private var pending: DispatchWorkItem?
    private var listener: AudioObjectPropertyListenerBlock?
    /// What was last announced (or the baseline): `glyph + label`, or the bare
    /// CoreAudio name for a device none of `known` names. Queue only.
    private var last = ""
    private let tab = BottomTab()

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
        Log.info("🎤 mic → \(now.text)")
        DispatchQueue.main.async { [tab] in tab.show(now.text, tint: Self.tint, hold: Self.hold) }
    }

    /// The resolved device as a comparable key and the tab's copy.
    private static func current() -> (key: String, text: String) {
        let r = InputDevice.resolve()
        if let k = r.known { return ("\(k.id) \(r.device?.name ?? "")", cardText(glyph: k.glyph, label: k.label)) }
        guard let name = r.device?.name else { return ("", "") }
        return (name, cardText(glyph: "🎙️", label: name))
    }

    /// The exact copy — `🎤 Listening to: DJI`.
    static func cardText(glyph: String, label: String) -> String { "\(glyph) Listening to: \(label)" }
}

/// Victor Addons' `BottomTabBanner`, cut down to what the announcer uses: one
/// panel on the screen under the mouse, nailed to its bottom edge, with the
/// tab sliding *inside* it so no pixel of the motion lands on a display below.
private final class BottomTab {
    private static let height: CGFloat = 76
    private static let radius: CGFloat = 18
    private static let padding: CGFloat = 34
    private static let font = NSFont.boldSystemFont(ofSize: 40)

    private var panel: NSPanel?
    private var tabView: NSView?
    private var label: NSTextField?
    private var tintView: NSView?
    private var motion: Timer?
    private var holdTimer: Timer?

    func show(_ text: String, tint: NSColor, hold: TimeInterval) {
        if let label, let panel, let tabView {
            label.stringValue = text
            tintView?.layer?.backgroundColor = tint.cgColor
            resize(panel: panel, tab: tabView, label: label, text: text)
            startHold(hold)
            return
        }
        guard let screen = Self.screenUnderMouse() else { return }
        let width = Self.width(for: text, screen: screen)
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
        let l = NSTextField(labelWithString: text)
        l.font = Self.font
        l.textColor = .white
        l.alignment = .center
        l.lineBreakMode = .byTruncatingTail
        l.frame = Self.labelFrame(width: width)
        tab.addSubview(l)
        content.addSubview(tab)
        p.contentView = content
        p.alphaValue = 0.92
        p.orderFrontRegardless()

        panel = p; tabView = tab; label = l; tintView = tintV
        animate(rising: true, duration: 0.32) { [weak self] in self?.startHold(hold) }
    }

    private func resize(panel: NSPanel, tab: NSView, label: NSTextField, text: String) {
        guard let screen = panel.screen ?? Self.screenUnderMouse() else { return }
        let width = Self.width(for: text, screen: screen)
        let f = screen.frame
        let y = tab.frame.origin.y
        panel.setFrame(NSRect(x: f.minX + ((f.width - width) / 2).rounded(), y: f.minY,
                              width: width, height: Self.height), display: true)
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        tab.frame = NSRect(x: 0, y: y, width: width, height: Self.height)
        label.frame = Self.labelFrame(width: width)
    }

    private func startHold(_ hold: TimeInterval) {
        holdTimer?.invalidate()
        let t = Timer(timeInterval: hold, repeats: false) { [weak self] _ in
            self?.animate(rising: false, duration: 0.45) { [weak self] in self?.teardown() }
        }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    private func teardown() {
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

    private static func width(for text: String, screen: NSScreen) -> CGFloat {
        let probe = NSTextField(labelWithString: text)
        probe.font = font
        probe.maximumNumberOfLines = 1
        probe.lineBreakMode = .byClipping
        probe.sizeToFit()
        let hugging = ceil(probe.frame.width) + 8 + 2 * padding
        return max(220, min(hugging, screen.frame.width * 0.6))
    }

    private static func labelFrame(width: CGFloat) -> NSRect {
        let lm = NSLayoutManager()
        var h = lm.defaultLineHeight(for: font)
        if let emoji = NSFont(name: "AppleColorEmoji", size: font.pointSize) {
            h = max(h, lm.defaultLineHeight(for: emoji))
        }
        h = ceil(h)
        return NSRect(x: padding, y: (height - h) / 2, width: width - 2 * padding, height: h)
    }

    private static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main
    }
}
