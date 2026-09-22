import AppKit
import CProjectM

/// **Sliders for the pure fluid, on screen for as long as it is the halo**
/// (Victor, 2026-09-23: *"can you provide some sliders for a few params on
/// screen permanent when using this animation?"*). A small panel in the bottom
/// right corner of the screen, there while a `ProjectMHalo` in modes 3–5
/// (Fluid cursor, Liquid cursor, Ink) exists — which is from the moment the
/// style is picked until another replaces it, dictating or not.
///
/// Every slider moves the live engine (`pmh_set_fluid_param`) and is saved per
/// mode (`fluidTune.mode<n>.<key>` in `UserDefaults`), so the next launch starts
/// where he left it. **Reset** puts the mode's constants back. **Preview** runs
/// the ring for 12 s on the voice clip, the F7/F9 preview, so the sliders can be
/// judged without dictating.
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

    private var panel: NSPanel?
    private var sliders: [NSSlider] = []
    private var readouts: [NSTextField] = []
    private weak var host: ProjectMHalo?
    private var hostID: ObjectIdentifier?
    private var mode = 0
    private var defaults: [Float] = []

    static func savedKey(_ mode: Int, _ knob: Knob) -> String { "fluidTune.mode\(mode).\(knob.key)" }

    /// The value to start the engine at: the saved one, else the mode's own.
    static func saved(mode: Int, knob: Knob) -> Float? {
        (UserDefaults.standard.object(forKey: savedKey(mode, knob)) as? Double).map(Float.init)
    }

    /// Called by the host once its engine is up, on the main thread.
    func attach(_ host: ProjectMHalo, mode: Int, title: String, defaults: [Float]) {
        self.host = host; self.hostID = ObjectIdentifier(host); self.mode = mode; self.defaults = defaults
        if panel == nil { build() }
        panel?.title = title
        for (i, knob) in Self.knobs.enumerated() {
            let v = Double(Self.saved(mode: mode, knob: knob) ?? defaults[i])
            sliders[i].doubleValue = v
            readouts[i].stringValue = Self.format(v, knob)
        }
        place()
        panel?.orderFrontRegardless()
    }

    /// Called when the host goes away. Another fluid host may already have
    /// attached (a style change builds the new one first), so only its own leaves.
    func detach(id: ObjectIdentifier) {
        guard hostID == id else { return }
        host = nil; hostID = nil
        panel?.orderOut(nil)
    }

    private static func format(_ v: Double, _ k: Knob) -> String {
        k.range.upperBound >= 100 ? String(format: "%.0f", v) : k.range.upperBound < 0.01 ? String(format: "%.4f", v) : String(format: "%.2f", v)
    }

    private func build() {
        let w: CGFloat = 300, rowH: CGFloat = 26
        let h = CGFloat(Self.knobs.count) * rowH + 44
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.titled, .utilityWindow, .nonactivatingPanel, .hudWindow],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: p.contentRect(forFrameRect: p.frame))
        for (i, knob) in Self.knobs.enumerated() {
            let y = h - 10 - CGFloat(i + 1) * rowH
            let label = NSTextField(labelWithString: knob.title)
            label.frame = NSRect(x: 10, y: y, width: 72, height: 18)
            label.textColor = .white
            let slider = NSSlider(value: knob.range.lowerBound, minValue: knob.range.lowerBound,
                                  maxValue: knob.range.upperBound, target: self, action: #selector(moved(_:)))
            slider.frame = NSRect(x: 82, y: y, width: 150, height: 20)
            slider.tag = i
            slider.isContinuous = true
            let readout = NSTextField(labelWithString: "")
            readout.frame = NSRect(x: 236, y: y, width: 58, height: 18)
            readout.textColor = .secondaryLabelColor
            readout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            [label, slider, readout].forEach(view.addSubview)
            sliders.append(slider); readouts.append(readout)
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

    @objc private func reset() {
        for (i, knob) in Self.knobs.enumerated() where i < defaults.count {
            UserDefaults.standard.removeObject(forKey: Self.savedKey(mode, knob))
            sliders[i].doubleValue = Double(defaults[i])
            readouts[i].stringValue = Self.format(Double(defaults[i]), knob)
            host?.setFluid(knob.id, defaults[i])
        }
    }

    @objc private func preview() { Self.onPreview?() }
}
