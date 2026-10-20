import Foundation
import IOKit
import IOKit.hid

/// **Is a Logitech mouse attached?** (2026-10-20) — the corner hint bar's
/// question. Victor: *"once you don't see the Logitech mouse attached … the
/// tooltips you display in the bottom right should make sense. Should be usable
/// for trackpad only."* With no Logitech mouse the side buttons' crosses describe
/// buttons that are not there, so the bar shows the trackpad's instead
/// (`GestureHintBar.Stage.noMouse`).
///
/// A registry read, polled: every HID device whose primary usage is a mouse
/// (page 1, usage 2), asked for its vendor — Logitech is 0x046D, over USB, the
/// Bolt receiver and Bluetooth LE alike. No `IOHIDManager`, so no Input
/// Monitoring prompt; one `IOServiceGetMatchingServices` every few seconds.
enum MouseDevices {

    static let logitechVendor = 0x046D

    /// The mice in the registry right now, as (vendor, product name).
    static func mice() -> [(vendor: Int, name: String)] {
        guard let match = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else { return [] }
        match[kIOHIDPrimaryUsagePageKey] = kHIDPage_GenericDesktop
        match[kIOHIDPrimaryUsageKey] = kHIDUsage_GD_Mouse
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [(Int, String)] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let vendor = IORegistryEntryCreateCFProperty(service, kIOHIDVendorIDKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int ?? 0
            let name = IORegistryEntryCreateCFProperty(service, kIOHIDProductKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String ?? "?"
            found.append((vendor, name))
        }
        return found
    }

    static var logitechAttached: Bool { mice().contains { $0.vendor == logitechVendor } }

    private static var timer: DispatchSourceTimer?
    private static var last: Bool?

    /// Calls `changed` on main with the answer at once and on every change,
    /// asking every `every` seconds off main.
    static func watch(every: TimeInterval = 3, _ changed: @escaping (Bool) -> Void) {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: every)
        t.setEventHandler {
            let mice = mice()
            let now = mice.contains { $0.vendor == logitechVendor }
            guard now != last else { return }
            last = now
            Log.info("🖱️ \(now ? "a Logitech mouse is attached" : "no Logitech mouse — the corner bar speaks trackpad") (mice: \(mice.map(\.name).joined(separator: ", ")))")
            DispatchQueue.main.async { changed(now) }
        }
        t.resume()
        timer = t
    }
}
