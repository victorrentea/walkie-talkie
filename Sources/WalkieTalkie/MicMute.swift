import CoreAudio
import Foundation

/// **The microphone muted from the collar** (2026-11-15, Victor: *"două
/// click-uri, click, click, să pună pe mute microfonul, indiferent dacă e sau
/// nu, independent de modul de dialog"* — the DJI transmitter's Link pressed
/// twice, `HotkeyTap.onDjiDouble`).
///
/// It is the device every app listens through that goes quiet
/// (`InputDevice.resolve()`, which Victor Addons keeps as the system default
/// too) — a call, the room's transcription and the voice panel alike, not only
/// this app's takes. CoreAudio's own mute where the device has one; a device
/// without it is turned down to 0 and its level kept to go back to, and
/// `GainGuard` — which exists to undo exactly that — stands back while it is
/// ours (`holdsDown`).
enum MicMute {
    private static let lock = NSLock()
    /// Device name → the level it had before this turned it down.
    private static var turnedDown: [String: Float32] = [:]
    private static var last: [String: Any] = [:]

    static var describe: [String: Any] {
        guard let device = InputDevice.resolve().device else { return ["device": ""] }
        let mute: UInt32? = read(device.id, kAudioDevicePropertyMute, 0)
        let volume: Float32? = read(device.id, kAudioDevicePropertyVolumeScalar, 0)
        lock.lock(); defer { lock.unlock() }
        var out: [String: Any] = ["device": device.name, "muted": isMuted(device.name, mute: mute),
                                  "hasMute": settable(device.id, kAudioDevicePropertyMute),
                                  "hasVolume": settable(device.id, kAudioDevicePropertyVolumeScalar)]
        if let mute { out["mute"] = mute }
        if let volume { out["volume"] = volume }
        return out
    }

    static func holdsDown(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return turnedDown[name] != nil
    }

    private static func isMuted(_ name: String, mute: UInt32?) -> Bool { (mute ?? 0) != 0 || turnedDown[name] != nil }

    /// Toggles (or sets `to`); answers the words for the chip. Any thread.
    @discardableResult
    static func toggle(to wanted: Bool? = nil) -> String {
        guard let device = InputDevice.resolve().device else { return "⚠️ No microphone to mute" }
        let name = device.name
        let mute: UInt32? = read(device.id, kAudioDevicePropertyMute, 0)
        lock.lock()
        let was = isMuted(name, mute: mute)
        lock.unlock()
        let on = wanted ?? !was
        var how = ""
        if settable(device.id, kAudioDevicePropertyMute) {
            how = write(device.id, kAudioDevicePropertyMute, UInt32(on ? 1 : 0)) ? "mute" : ""
        }
        if how.isEmpty || !on {
            // No switch (or one that refused): the level. Also the way back from a
            // level this turned down.
            lock.lock()
            let kept = turnedDown[name]
            lock.unlock()
            if on, how.isEmpty, let level: Float32 = read(device.id, kAudioDevicePropertyVolumeScalar, 0) {
                lock.lock(); turnedDown[name] = max(level, GainGuard.floor); lock.unlock()
                if write(device.id, kAudioDevicePropertyVolumeScalar, Float32(0)) { how = "level" }
                else { lock.lock(); turnedDown[name] = nil; lock.unlock() }
            } else if !on, let kept {
                if write(device.id, kAudioDevicePropertyVolumeScalar, kept) { how = how.isEmpty ? "level" : how }
                lock.lock(); turnedDown[name] = nil; lock.unlock()
            }
        }
        guard !how.isEmpty || !on else {
            Log.error("🔇 mic mute: \(name) has neither a mute nor a level that can be set")
            return "⚠️ \(name) cannot be muted from here"
        }
        Log.info("🔇 mic mute: \(name) \(on ? "muted" : "live again") (\(how.isEmpty ? "it was live" : how))")
        return on ? "🔇 Microphone muted — \(name)" : "🎙️ Microphone live — \(name)"
    }

    private static func settable(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            var can: DarwinBoolean = false
            if AudioObjectHasProperty(id, &address), AudioObjectIsPropertySettable(id, &address, &can) == noErr, can.boolValue { return true }
        }
        return false
    }

    /// The master element first, then channel 1 — devices differ in which they expose.
    private static func read<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ zero: T) -> T? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            var value = zero
            var size = UInt32(MemoryLayout<T>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    private static func write<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
            var can: DarwinBoolean = false
            guard AudioObjectHasProperty(id, &address), AudioObjectIsPropertySettable(id, &address, &can) == noErr, can.boolValue else { continue }
            var v = value
            if AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr { return true }
        }
        return false
    }
}
