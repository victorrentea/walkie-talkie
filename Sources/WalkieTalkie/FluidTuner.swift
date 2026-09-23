import AppKit
import CProjectM

/// **Sliders for the pure fluid, on screen for as long as it is the halo**
/// (Victor, 2026-09-23: *"can you provide some sliders for a few params on
/// screen permanent when using this animation?"*). A small panel in the bottom
/// right corner of the screen, attached while a `ProjectMHalo` in modes 3–6
/// (Fluid cursor, Liquid cursor, Ink, Smoke) exists, and **shown only during
/// the F7/F9 preview** since 2026-09-23 — see `previewing`.
///
/// Every slider moves the live engine (`pmh_set_fluid_param`) and is saved per
/// mode (`fluidTune.mode<n>.<key>` in `UserDefaults`), so the next launch starts
/// where he left it. **Reset** puts the mode's constants back. **Preview** runs
/// the ring for 12 s on the voice clip, the F7/F9 preview, so the sliders can be
/// judged without dictating.
///
/// **And the voice, for the effects that answer it** (Victor, 2026-09-23: *"ambele
/// sa aiba si un combo cu acele filtre in setari + un threshold care sa seteze
/// sensibilitatea la voce … ca slider"*). Fairy dust, Liquid cursor and Smoke get two
/// rows on top: *Voice filter* — the same `HaloVoice` chain the menu row picks,
/// one preference for both — and *Voice threshold*, how loud a syllable has to be
/// before it stirs the effect, saved per effect (`voiceThreshold.<key>`). Fairy
/// dust is a page effect with no fluid knobs, so for it the panel is those two
/// rows alone (`attachVoice`).
///
/// A non-activating panel: clicking a slider never takes focus from the window he
/// is dictating into.
final class FluidTuner: NSObject {
    static let shared = FluidTuner()
    static var onPreview: (() -> Void)?

    struct Knob { let id: Int32; let key: String; let title: String; let range: ClosedRange<Double> }
    /// The ranges are absolute rather than a factor of the default, so the three
    /// modes share one scale and a value can be compared across them.
    static let knobs: [Knob] = [
        Knob(id: Int32(PMH_FLUID_RADIUS), key: "radius", title: "Size", range: 0.0005...0.008),
        Knob(id: Int32(PMH_FLUID_GAIN), key: "gain", title: "Brightness", range: 0.02...0.6),
        Knob(id: Int32(PMH_FLUID_FADE), key: "fade", title: "Fade", range: 0.2...6),
        Knob(id: Int32(PMH_FLUID_CURL), key: "curl", title: "Swirl", range: 0...40),
        Knob(id: Int32(PMH_FLUID_FORCE), key: "force", title: "Force", range: 500...20000),
        Knob(id: Int32(PMH_FLUID_OPACITY), key: "opacity", title: "Opacity", range: 0.05...1),
    ]

    /// What the voice rows move: `key` names the saved threshold, `apply` hands a
    /// new one to whatever is drawing.
    struct VoiceHook { let key: String; let apply: (Float) -> Void }
    static let thresholdRange: ClosedRange<Double> = 0...0.5
    static let defaultThreshold: Float = 0.1
    static func thresholdKey(_ key: String) -> String { "voiceThreshold.\(key)" }
    /// The saved threshold for `key`, else the default.
    static func threshold(_ key: String) -> Float {
        (UserDefaults.standard.object(forKey: thresholdKey(key)) as? Double).map(Float.init) ?? defaultThreshold
    }

    private var panel: NSPanel?
    private var sliders: [NSSlider] = []
    private var readouts: [NSTextField] = []
    private var voiceSlider: NSSlider?
    private var voiceReadout: NSTextField?
    private var voiceMenu: NSPopUpButton?
    private var voice: VoiceHook?
    private weak var host: ProjectMHalo?
    private var hostID: ObjectIdentifier?
    private var mode = 0
    private var defaults: [Float] = []

    /// **Only while previewing** (Victor, 2026-09-23: *"smoke sliders shouldn't
    /// display unless in F7/F9 iteration through effects, not in real use"*).
    /// The panel is attached whenever a fluid host exists, as before, but shown
    /// only between `CaretHalo.preview`'s start and end — over a real dictation
    /// it was a stray window in the corner of whatever he was working on.
    var previewing = false {
        didSet {
            guard previewing != oldValue else { return }
            if previewing, hostID != nil { place(); panel?.orderFrontRegardless() }
            if !previewing { panel?.orderOut(nil) }
        }
    }

    static func savedKey(_ mode: Int, _ knob: Knob) -> String { "fluidTune.mode\(mode).\(knob.key)" }

    /// The value to start the engine at: the saved one, else the mode's own.
    static func saved(mode: Int, knob: Knob) -> Float? {
        (UserDefaults.standard.object(forKey: savedKey(mode, knob)) as? Double).map(Float.init)
    }

    /// Called by the host once its engine is up, on the main thread.
    func attach(_ host: ProjectMHalo, mode: Int, title: String, defaults: [Float], voice: VoiceHook? = nil) {
        self.host = host; self.hostID = ObjectIdentifier(host); self.mode = mode; self.defaults = defaults
        self.voice = voice
        build(knobs: true)
        panel?.title = title
        for (i, knob) in Self.knobs.enumerated() {
            let v = Double(Self.saved(mode: mode, knob: knob) ?? defaults[i])
            sliders[i].doubleValue = v
            readouts[i].stringValue = Self.format(v, knob)
        }
        guard previewing else { return }
        place()
        panel?.orderFrontRegardless()
    }

    /// **The voice rows alone**, for an effect with no fluid behind it (Fairy
    /// dust, drawn by the page). `owner` is what `detach` is later called with.
    func attachVoice(owner: AnyObject, title: String, voice: VoiceHook) {
        host = nil; hostID = ObjectIdentifier(owner); self.voice = voice
        build(knobs: false)
        panel?.title = title
        guard previewing else { return }
        place()
        panel?.orderFrontRegardless()
    }

    /// Called when the host goes away. Another fluid host may already have
    /// attached (a style change builds the new one first), so only its own leaves.
    func detach(id: ObjectIdentifier) {
        guard hostID == id else { return }
        host = nil; hostID = nil; voice = nil
        panel?.orderOut(nil)
    }

    private static func format(_ v: Double, _ k: Knob) -> String {
        k.range.upperBound >= 100 ? String(format: "%.0f", v) : k.range.upperBound < 0.01 ? String(format: "%.4f", v) : String(format: "%.2f", v)
    }

    /// Rebuilt on every attach: which rows exist depends on what is drawing.
    private func build(knobs: Bool) {
        let w: CGFloat = 300, rowH: CGFloat = 26
        let voiceRows = voice == nil ? 0 : 2
        let knobRows = knobs ? Self.knobs.count : 0
        let h = CGFloat(voiceRows + knobRows) * rowH + 44
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .utilityWindow, .nonactivatingPanel, .hudWindow],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .statusBar
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            // `sharingType = .none`, like every window this app puts on screen — a
            // tuning panel is exactly the kind of thing that should not show up on
            // a projector or in a screenshot he takes while previewing.
            p.sharingType = .none
            return p
        }()
        p.setContentSize(NSSize(width: w, height: h))
        sliders = []; readouts = []; voiceSlider = nil; voiceReadout = nil; voiceMenu = nil
        let view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        var row = 0
        func y() -> CGFloat { h - 10 - CGFloat(row + 1) * rowH }
        func label(_ title: String) {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 10, y: y(), width: 72, height: 18)
            label.textColor = .white
            view.addSubview(label)
        }
        if let voice = voice {
            label("Voice filter")
            let menu = NSPopUpButton(frame: NSRect(x: 82, y: y() - 3, width: 208, height: 24), pullsDown: false)
            menu.controlSize = .small
            for v in HaloVoice.allCases {
                menu.addItem(withTitle: v.title)
                menu.lastItem?.representedObject = v.rawValue
            }
            menu.selectItem(at: HaloVoice.allCases.firstIndex(of: HaloVoice.current) ?? 0)
            menu.target = self; menu.action = #selector(pickedVoice(_:))
            view.addSubview(menu)
            voiceMenu = menu
            row += 1
            label("Threshold")
            let t = Double(Self.threshold(voice.key))
            let slider = NSSlider(value: t, minValue: Self.thresholdRange.lowerBound,
                                  maxValue: Self.thresholdRange.upperBound, target: self, action: #selector(movedThreshold(_:)))
            slider.frame = NSRect(x: 82, y: y(), width: 150, height: 20)
            slider.isContinuous = true
            let readout = NSTextField(labelWithString: String(format: "%.2f", t))
            readout.frame = NSRect(x: 236, y: y(), width: 58, height: 18)
            readout.textColor = .secondaryLabelColor
            readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            view.addSubview(slider); view.addSubview(readout)
            voiceSlider = slider; voiceReadout = readout
            row += 1
        }
        if knobs {
            for (i, knob) in Self.knobs.enumerated() {
                label(knob.title)
                let slider = NSSlider(value: knob.range.lowerBound, minValue: knob.range.lowerBound,
                                      maxValue: knob.range.upperBound, target: self, action: #selector(moved(_:)))
                slider.frame = NSRect(x: 82, y: y(), width: 150, height: 20)
                slider.tag = i
                slider.isContinuous = true
                let readout = NSTextField(labelWithString: "")
                readout.frame = NSRect(x: 236, y: y(), width: 58, height: 18)
                readout.textColor = .secondaryLabelColor
                readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                view.addSubview(slider); view.addSubview(readout)
                sliders.append(slider); readouts.append(readout)
                row += 1
            }
        }
        let reset = NSButton(title: "Reset", target: self, action: #selector(reset))
        reset.frame = NSRect(x: 10, y: 6, width: 80, height: 24)
        let preview = NSButton(title: "Preview", target: self, action: #selector(preview))
        preview.frame = NSRect(x: 96, y: 6, width: 90, height: 24)
        view.addSubview(reset); view.addSubview(preview)
        p.contentView = view
        panel = p
    }

    /// Bottom right of the screen the pointer is on, clear of the Dock's edge.
    private func place() {
        guard let p = panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: v.maxX - p.frame.width - 16, y: v.minY + 16))
    }

    @objc private func moved(_ slider: NSSlider) {
        let knob = Self.knobs[slider.tag]
        readouts[slider.tag].stringValue = Self.format(slider.doubleValue, knob)
        UserDefaults.standard.set(slider.doubleValue, forKey: Self.savedKey(mode, knob))
        host?.setFluid(knob.id, Float(slider.doubleValue))
    }

    @objc private func pickedVoice(_ menu: NSPopUpButton) {
        guard let raw = menu.selectedItem?.representedObject as? String, let v = HaloVoice(rawValue: raw) else { return }
        UserDefaults.standard.set(v.rawValue, forKey: HaloVoice.defaultsKey)
        VoicePrep.shared.refresh()
        Log.info("🎚️ halo voice: \(v.rawValue) — \(v.title) (tuner)")
    }

    @objc private func movedThreshold(_ slider: NSSlider) {
        guard let voice = voice else { return }
        voiceReadout?.stringValue = String(format: "%.2f", slider.doubleValue)
        UserDefaults.standard.set(slider.doubleValue, forKey: Self.thresholdKey(voice.key))
        voice.apply(Float(slider.doubleValue))
    }

    @objc private func reset() {
        if let voice = voice {
            UserDefaults.standard.removeObject(forKey: Self.thresholdKey(voice.key))
            voiceSlider?.doubleValue = Double(Self.defaultThreshold)
            voiceReadout?.stringValue = String(format: "%.2f", Self.defaultThreshold)
            voice.apply(Self.defaultThreshold)
        }
        for (i, knob) in Self.knobs.enumerated() where i < defaults.count && i < sliders.count {
            UserDefaults.standard.removeObject(forKey: Self.savedKey(mode, knob))
            sliders[i].doubleValue = Double(defaults[i])
            readouts[i].stringValue = Self.format(Double(defaults[i]), knob)
            host?.setFluid(knob.id, defaults[i])
        }
    }

    @objc private func preview() { Self.onPreview?() }
}
