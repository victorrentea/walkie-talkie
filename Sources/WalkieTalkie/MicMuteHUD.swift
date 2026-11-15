import AppKit

/// **The muted microphone stays on screen** (2026-11-15, Victor: *"trebuie să
/// apară, să rămână persistent pe ecran, undeva jos, ca și cum ar fi volumul
/// de la Mac, cum am implementat pentru addons … cât e microfonul oprit"* — and
/// the 🔇 the first build flashed is a speaker, not a microphone; no emoji is a
/// crossed microphone, so it is drawn: `mic.slash.fill`).
///
/// Victor Addons' `VolumeHUD` look, reproduced here (this app may not depend on
/// it): a 200 pt square of dark frosted glass, 140 pt above the bottom edge,
/// centred on the screen the pointer is on. Up for as long as the device the
/// apps listen through is muted — by Link ×2 (`MicMute`) or by anything else
/// (the Wave XLR's own tap) — read every 2 s off the main thread; live again →
/// the plain microphone for 1.5 s, then gone. Click-through, in no screenshot.
final class MicMuteHUD {
    static let shared = MicMuteHUD()

    private static let side: CGFloat = 200
    private let queue = DispatchQueue(label: "mic-mute-hud", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var panel: NSPanel?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var shownMuted = false
    private var hideWork: DispatchWorkItem?

    var describe: [String: Any] {
        ["muted": shownMuted, "visible": (panel?.isVisible ?? false) && (panel?.alphaValue ?? 0) > 0,
         "frame": panel.map { NSStringFromRect($0.frame) } ?? ""]
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 2)
        t.setEventHandler { [weak self] in self?.read() }
        t.resume()
        timer = t
    }

    /// Now, not at the next tick — after a toggle.
    func sync() { queue.async { self.read() } }

    private func read() {
        let state = MicMute.describe
        let muted = state["muted"] as? Bool ?? false
        let name = state["device"] as? String ?? ""
        DispatchQueue.main.async { self.show(muted: muted, device: name) }
    }

    private func show(muted: Bool, device: String) {
        if muted {
            hideWork?.cancel()
            let p = panel ?? build()
            panel = p
            set(symbol: "mic.slash.fill", tint: .systemRed, text: "Muted — \(device)")
            place(p)
            p.alphaValue = 1
            p.orderFrontRegardless()
            shownMuted = true
        } else if shownMuted {
            shownMuted = false
            guard let p = panel else { return }
            set(symbol: "mic.fill", tint: NSColor.white.withAlphaComponent(0.8), text: "Live — \(device)")
            // The fade's completion never comes with the display asleep (seen
            // 2026-11-15, the HUD stayed): the end is on a clock of its own.
            let work = DispatchWorkItem { [weak self, weak p] in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    p?.animator().alphaValue = 0
                }
                let gone = DispatchWorkItem { p?.alphaValue = 0; p?.orderOut(nil) }
                self?.hideWork = gone
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: gone)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func set(symbol: String, tint: NSColor, text: String) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 80, weight: .medium))
        icon.contentTintColor = tint
        label.stringValue = text
    }

    private func place(_ p: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.frame else { return }
        p.setFrameOrigin(NSPoint(x: f.midX - Self.side / 2, y: f.minY + 140))
    }

    private func build() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .screenSaver
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let glass = NSVisualEffectView(frame: rect)
        glass.material = .hudWindow
        glass.appearance = NSAppearance(named: .vibrantDark)
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.masksToBounds = true
        p.contentView = glass
        icon.frame = NSRect(x: 0, y: 56, width: Self.side, height: 120)
        icon.imageScaling = .scaleNone
        glass.addSubview(icon)
        label.frame = NSRect(x: 10, y: 22, width: Self.side - 20, height: 18)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.lineBreakMode = .byTruncatingTail
        glass.addSubview(label)
        return p
    }

    /// The panel as it is drawn, for a review (`sharingType = .none` keeps it
    /// out of every screenshot). On main.
    func writePNG(_ path: String) -> Bool {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
