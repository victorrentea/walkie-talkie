import CoreAudio
import Foundation

/// **The system's microphone is this app's choice** (2026-11-13). Victor,
/// after ChatGPT's voice turned out to listen on the MacBook's own microphone
/// while the XLR stood in front of him: *"cred că vreau ca walkie să seteze
/// oricum permanent mic OS la cel ales de el … Cumva app devine selectorul
/// dinamic smart de microfon"*.
///
/// The other direction is still forbidden — this app never *follows* the
/// system default (`InputDevice`, *Never follow the system default input*).
/// It now *sets* it: whenever the device list, the pick in either menu, or the
/// default itself changes, the default input is put on `InputDevice.followTarget`
/// — his pick when it is plugged in, else the first rung of the ladder that is.
/// With none of his own microphones present, nothing is touched.
///
/// Every app that listens on "the system microphone" (ChatGPT, a browser tab,
/// Zoom/Teams on *Same as System*) is thereby on the same microphone as the
/// dictation. Not while a desk harness holds the default (`POST /test/input`,
/// `hold`) or a test override names a device. Off: `defaults write
/// ro.victorrentea.wispr-relay systemMicFollows -bool false`.
enum SystemMic {

    static var isOn: Bool { UserDefaults.standard.object(forKey: "systemMicFollows") as? Bool ?? true }

    private static let queue = DispatchQueue(label: "system-mic")
    private static var pending: DispatchWorkItem?
    private static var heldUntil: CFAbsoluteTime = 0
    private static var recent: [CFAbsoluteTime] = []
    private static var last: [String: Any] = [:]

    static var describe: [String: Any] {
        queue.sync {
            var out = last
            out["on"] = isOn
            out["system"] = InputDevice.systemDefaultName() ?? ""
            return out
        }
    }

    /// A desk harness has pointed the default somewhere on purpose.
    static func hold(_ seconds: Double) { queue.async { heldUntil = CFAbsoluteTimeGetCurrent() + seconds } }

    static func watch() {
        queue.async {
            for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { _, _ in
                    settle(why: selector == kAudioHardwarePropertyDevices ? "the device list changed" : "the default moved")
                }
            }
            sync(why: "at launch")
        }
    }

    /// The pick changed in either app's menu.
    static func choiceChanged() { queue.async { settle(why: "the pick changed") } }

    /// One sync a second after the last change: a plug-in fires several.
    private static func settle(why: String) {
        pending?.cancel()
        let work = DispatchWorkItem { sync(why: why) }
        pending = work
        queue.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private static func sync(why: String) {
        guard isOn, CFAbsoluteTimeGetCurrent() >= heldUntil, (InputDevice.testOverride ?? "").isEmpty else { return }
        guard let target = InputDevice.followTarget() else { return }
        guard InputDevice.systemDefaultId() != target.id else { return }
        // Something else that insists on the default would make this a tug of
        // war: three moves in ten seconds, then it is left alone for a minute.
        let now = CFAbsoluteTimeGetCurrent()
        recent = recent.filter { now - $0 < 10 }
        guard recent.count < 3 else {
            Log.error("🎚️ system microphone — moved back 3 times in 10 s, something else wants \(InputDevice.systemDefaultName() ?? "?"); left alone for a minute")
            heldUntil = now + 60
            return
        }
        recent.append(now)
        let was = InputDevice.systemDefaultName() ?? "?"
        let ok = InputDevice.setSystemDefault(target)
        last = ["at": ISO8601DateFormatter().string(from: Date()), "why": why, "was": was, "now": target.name, "ok": ok]
        if ok { Log.info("🎚️ system microphone \(was) → \(target.name) (\(why))") }
    }
}
