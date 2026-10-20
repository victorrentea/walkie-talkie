import Foundation
import IOKit.ps

/// **No 𝓯𝔁 on battery** (2026-10-20). Victor: *"Have an option in the menu for
/// the effects to say disable on battery, which is automatically set to true.
/// On the battery I should not see any animation on my desktop. It eats the
/// battery."* Measured long ago (`replace-wispr-and-halo.md`, *What it costs*):
/// a MilkDrop preset is ~30 % of a core in WebContent + ~67 % in the GPU process,
/// a page effect up to 95 % of a core — on battery that is the whole budget.
///
/// While `holdsEffects` is true, `AppDelegate.syncBorrowedGestures` keeps the
/// halo, the rewind, the coast, the pin and the dock down; the chip, the orange
/// outline and every delivery are untouched. An F7/F9 preview still plays — it
/// is a deliberate press, not something the desktop does on its own.
///
/// The power source is read once and then on IOKit's own notification, never
/// per sync: `syncBorrowedGestures` runs on every edge of every dictation.
enum BatteryFx {
    static let defaultsKey = "fxOffOnBattery"

    /// The menu's tick — **on by default**, as he asked.
    static var isOn: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        Log.info("🔋 𝓯𝔁 off on battery: \(on ? "on" : "off")\(onBattery ? " — on battery now" : "")")
        changed?()
    }

    private(set) static var onBattery = readOnBattery()

    /// The effects are held right now: the switch is on and the Mac runs on battery.
    static var holdsEffects: Bool { isOn && onBattery }

    /// Called on the main thread when the power source flips or the switch moves.
    private static var changed: (() -> Void)?
    private static var source: CFRunLoopSource?

    static func watch(_ onChange: @escaping () -> Void) {
        changed = onChange
        guard source == nil else { return }
        guard let s = IOPSNotificationCreateRunLoopSource({ _ in
            let now = BatteryFx.readOnBattery()
            guard now != BatteryFx.onBattery else { return }
            BatteryFx.onBattery = now
            Log.info(now ? "🔋 on battery\(BatteryFx.isOn ? " — 𝓯𝔁 held" : "")" : "🔌 on power — 𝓯𝔁 back")
            BatteryFx.changed?()
        }, nil)?.takeRetainedValue() else {
            Log.error("🔋 no power-source notification — the battery state is read once, at launch")
            return
        }
        source = s
        CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        Log.info("🔋 power source at launch: \(onBattery ? "battery" : "AC")")
    }

    private static func readOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    static var describe: [String: Bool] { ["on": isOn, "onBattery": onBattery, "held": holdsEffects] }
}
