import Foundation
import IOKit
import CoreGraphics
import IOKit.hid

/// **The Link button on the DJI Mic Mini transmitter, as a key of this app's**
/// (2026-11-13). Victor: *"La click pe Link pe TX DJI să pornești dialogul cu
/// ChatGPT, pentru moment"*.
///
/// With the receiver on USB-C it is a HID Consumer Control device (*Wireless
/// Mic Rx*, vendor `0x2CA3`; product `0x4011` on the units others measured)
/// and a short press of Link on the **transmitter** arrives as Volume
/// Increment (page `0x0C`, usage `0xE9`) — a momentary click, no hold, no
/// double. Not over Bluetooth. Sources: github.com/tusharxclaude/djilink,
/// conchoecia/dji-mic-button, saqibnizami/dji-mic-for-wispr-flow. **None of it
/// measured on his unit yet** — written with the receiver unplugged.
///
/// `hidutil` remaps that usage to **F20** for this vendor's devices only (the
/// keyboard's volume keys are untouched, the volume does not move), and
/// `HotkeyTap` takes F20 (`onDjiButton`). No Input Monitoring, no seized
/// device. F18 and F19 are Wispr's.
///
/// **The mapping lives in the HID service and dies with it** — unplug, sleep,
/// reboot — and `hidutil` exits 0 when nothing matched. So it is applied at
/// launch, at every arrival of a device of that vendor (an IOKit matching
/// notification — nothing polls), and on wake; and taken off at quit.
/// **Never press Link twice and hold: that is the transmitter's re-pairing.**
enum DjiButton {

    static let vendor = 0x2CA3
    /// F20 — `0x70000006F` on the wire, virtual key 90.
    static let keyCode: CGKeyCode = 90

    private static let queue = DispatchQueue(label: "dji-button")
    private static var port: IONotificationPortRef?
    private static var iterator: io_iterator_t = 0
    private static var lastApplied: [String: Any] = [:]

    static var describe: [String: Any] { queue.sync { lastApplied } }

    /// `--matching` and `--set` for `hidutil property`.
    static let matching = "{\"VendorID\":0x2CA3}"
    static func mapping(on: Bool) -> String {
        on ? "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":0xC000000E9,\"HIDKeyboardModifierMappingDst\":0x70000006F}]}"
           : "{\"UserKeyMapping\":[]}"
    }

    static func watch() {
        queue.async {
            guard port == nil, let p = IONotificationPortCreate(kIOMainPortDefault) else { return }
            port = p
            IONotificationPortSetDispatchQueue(p, queue)
            guard let match = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else { return }
            match[kIOHIDVendorIDKey] = vendor
            let arrived: IOServiceMatchingCallback = { _, iterator in
                var n = 0
                while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service); n += 1 }
                guard n > 0 else { return }
                // The HID services under a device just attached are not all up yet.
                DjiButton.queue.asyncAfter(deadline: .now() + 1.5) { DjiButton.apply(why: "a receiver arrived") }
            }
            guard IOServiceAddMatchingNotification(p, kIOFirstMatchNotification, match, arrived, nil, &iterator) == KERN_SUCCESS else {
                Log.error("🎙️ DJI button — no matching notification; the Link button stays the volume key")
                return
            }
            // Arms the notification, and counts what is plugged in already.
            var present = 0
            while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service); present += 1 }
            if present > 0 { apply(why: "at launch") }
            else { Log.info("🎙️ DJI button — no receiver on USB now; Link becomes F20 when one arrives") }
        }
    }

    static func reapply(why: String) { queue.async { if present() { apply(why: why) } } }

    /// At quit: the receiver is the volume key again.
    static func release() { queue.sync { if present() { _ = hidutil(["property", "--matching", matching, "--set", mapping(on: false)]) } } }

    private static func present() -> Bool {
        guard let match = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else { return false }
        match[kIOHIDVendorIDKey] = vendor
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(it) }
        var n = 0
        while case let service = IOIteratorNext(it), service != 0 { IOObjectRelease(service); n += 1 }
        return n > 0
    }

    private static func apply(why: String) {
        let set = hidutil(["property", "--matching", matching, "--set", mapping(on: true)])
        let got = hidutil(["property", "--matching", matching, "--get", "UserKeyMapping"])
        // 0x70000006F, as `hidutil` prints it back: decimal.
        let holds = got.out.contains("30064771183")
        lastApplied = ["at": ISO8601DateFormatter().string(from: Date()), "why": why, "exit": Int(set.status), "holds": holds]
        if holds { Log.info("🎙️ DJI button — Link is F20 now (\(why))") }
        else { Log.error("🎙️ DJI button — the remap did not take (\(why)); exit \(set.status), read back: \(got.out.prefix(200))") }
    }

    private static func hidutil(_ arguments: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
