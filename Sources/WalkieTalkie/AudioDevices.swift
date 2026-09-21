import CoreAudio
import Foundation

/// **Finding an audio device to speak into, by name.**
///
/// The output twin of `InputDevice`'s enumeration, and deliberately a separate
/// reading: a Loopback device has both sides, and asking for the input one when
/// what is wanted is the output aims at the half Wispr is *listening* to rather
/// than the half this app has to *speak* into.
///
/// It lives on its own because two things need it now — `ShotMarker`, which says
/// one clip, and `AudioBridge`, which says his whole sentence.
enum AudioDevices {

    struct Device { let id: AudioDeviceID; let name: String }

    /// Substring, case-insensitive: CoreAudio names carry emoji and trailing
    /// model numbers, and asking a caller to type one exactly is asking for a
    /// typo that looks like *nothing came out*.
    static func output(matching needle: String) -> Device? {
        let wanted = needle.lowercased()
        for id in all() where channels(id, scope: kAudioObjectPropertyScopeOutput) > 0 {
            guard let name = name(id), name.lowercased().contains(wanted) else { continue }
            return Device(id: id, name: name)
        }
        return nil
    }

    private static func all() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func name(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    /// The channel counts live in a variable-length `AudioBufferList`, so the
    /// buffer has to be sized by the same call that fills it — a fixed struct
    /// would truncate a device with several streams. `InputDevice`'s reason, on
    /// whichever scope is asked for.
    static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// **The default input device's own gain, 0…1 — the slider in System
    /// Settings ▸ Sound ▸ Input.**
    ///
    /// It is not a user preference that sits where it is put. macOS's voice
    /// processing runs an AGC on it, and Victor watched it happen: *"dacă țip
    /// mai tare, el într-adevăr coboară, și dacă tac mai mult timp se ridică la
    /// loc la 100%"*. Measured on his built-in microphone the evening of
    /// 2026-09-21, it walked 100 → 94 → 87 → 72 → 60 % inside five minutes of
    /// dictation, which is 1.7× of signal gone without anything in this app
    /// changing.
    ///
    /// **`osascript` cannot answer this.** `input volume of (get volume
    /// settings)` returned 100 while the slider and CoreAudio both said 72 — it
    /// does not read per device. Only this does.
    ///
    /// nil when the device exposes no input gain at all (several virtual ones
    /// here do not), which is not a failure and means *nothing is moving*.
    static func inputVolume() -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &id) == noErr, id != 0 else { return nil }
        // The master element first, then channel 1: devices differ in which of
        // the two they expose, and reading only the master misses some.
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                    mScope: kAudioDevicePropertyScopeInput,
                                                    mElement: element)
            guard AudioObjectHasProperty(id, &volume) else { continue }
            var v: Float32 = 0
            var sz = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(id, &volume, 0, nil, &sz, &v) == noErr else { continue }
            return v
        }
        return nil
    }
}
