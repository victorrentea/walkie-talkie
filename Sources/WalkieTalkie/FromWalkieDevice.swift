import CoreAudio
import Foundation

/// **The "From Walkie" microphone exists only while the relay runs** (2026-09-29).
///
/// "From Walkie" is a pass-through device built from BlackHole in `../from-walkie`
/// (whatever is played into its output comes out of its input). It reports itself
/// as USB, because Wispr Flow's microphone list hides every Virtual device.
///
/// It is switched through the driver's own `kAudioBoxPropertyAcquired`: 0 removes
/// the device from CoreAudio, 1 brings it back — no GUI, no sudo, no coreaudiod
/// restart, ~0.2 s. So Wispr, with "From Walkie" first in its ranking, listens to
/// the relay while it runs, and falls back to the next microphone the moment the
/// device disappears — which is why a quit turns it off. A crash cannot; Victor
/// Addons' watchdog turns it off within 5 s of the relay being gone.
///
/// A Mac without the driver installed simply has no box: every call is a logged no-op.
enum FromWalkieDevice {
    static let boxUID = "FromWalkie_UID"

    private static var acquired = AudioObjectPropertyAddress(
        mSelector: kAudioBoxPropertyAcquired,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static func box() -> AudioObjectID? {
        var uid = boxUID as CFString
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToBox,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let err = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return (err == noErr && id != kAudioObjectUnknown) ? id : nil
    }

    static func set(_ on: Bool, reason: String) {
        // The photo run is a second process beside the installed app: its quit
        // turned the device off under the running relay (2026-10-21, 17:07:45).
        guard !RelayWindow.shooting else { return }
        guard let box = box() else {
            Log.info("🎚️ From Walkie: driver not installed — nothing to turn \(on ? "on" : "off") (\(reason))")
            return
        }
        var value: UInt32 = on ? 1 : 0
        let err = AudioObjectSetPropertyData(box, &acquired, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if err == noErr {
            Log.info("🎚️ From Walkie \(on ? "on" : "off") (\(reason))")
        } else {
            Log.error("🎚️ From Walkie: could not turn \(on ? "on" : "off") — OSStatus \(err) (\(reason))")
        }
    }
}
