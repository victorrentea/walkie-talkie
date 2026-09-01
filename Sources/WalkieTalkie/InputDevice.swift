import AVFoundation
import CoreAudio

/// Which microphone the relay records through.
///
/// ## The DJI receiver wins whenever it is plugged in
///
/// Victor teaches with a DJI lavalier: the transmitter is on his collar and the
/// receiver hangs off the Mac's USB-C. The built-in microphone is two feet away
/// across a desk, in a room with a projector fan, an audience and often his own
/// voice coming back off the far wall — and Whisper hears exactly that
/// difference. So when the receiver is there, it is the one that records, and
/// the system's default input is what he gets when it is not.
///
/// **The system default is not consulted for this**, deliberately. macOS points
/// the default input wherever the last thing to arrive claims it: plugging in
/// the DJI usually does select it, but so does joining a Zoom call, waking a
/// Bluetooth headset, or any of the four virtual devices (Loopback, Wave Link,
/// Iriun, Teams) that live on this Mac and can quietly become the default while
/// he is not looking. A relay that follows the default would record a sentence
/// through Loopback's silence and hand back an empty transcript. Choosing the
/// device by name, per recording, is what makes the gesture mean the same thing
/// every time.
///
/// ## Per recording, never cached
///
/// The receiver goes in and out of the port between sessions, and the numeric
/// `AudioDeviceID` is reassigned every time it does. Nothing here is remembered
/// across a dictation: each `select` enumerates and matches afresh, which is
/// also what makes unplugging the receiver mid-workshop degrade to the built-in
/// microphone rather than to an error.
enum InputDevice {

    /// What the DJI receiver calls itself. It does *not* say "DJI" — the USB
    /// product name is `Wireless Mic Rx` — so the manufacturer string is the
    /// half that identifies the brand, and it is the one that stays put across
    /// the Mic 2 / Mic Mini / Mic 3 line.
    private static let djiNeedles = ["dji", "wireless mic rx"]

    /// Point `input` at the microphone this recording should use and return a
    /// human name for the log.
    ///
    /// Always sets a device, even when the choice is the default one: the audio
    /// unit holds whatever device it was last told about, so a recording made
    /// after the receiver was unplugged would otherwise still be aimed at a
    /// device that is gone.
    static func select(on input: AVAudioInputNode) -> String {
        let dji = inputs().first { device in
            let haystack = "\(device.name) \(device.manufacturer)".lowercased()
            return djiNeedles.contains { haystack.contains($0) }
        }
        guard let chosen = dji ?? systemDefault() else { return "the system input" }

        guard let unit = input.audioUnit else { return chosen.name }
        var id = chosen.id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            // Not fatal: the engine still has whatever device it had, which is
            // very likely the right one anyway. Worth a line, because it is the
            // only explanation for a recording that sounds like the built-in
            // microphone with the receiver plugged in.
            Log.error("mic: could not switch to \(chosen.name) — OSStatus \(status)")
            return "the system input"
        }
        return chosen.name
    }

    // MARK: - CoreAudio

    private struct Device {
        let id: AudioDeviceID
        let name: String
        let manufacturer: String
    }

    /// Every device that can actually record. Outputs and the input-less halves
    /// of duplex devices are dropped here rather than at the match, so "first
    /// one that looks like a DJI" cannot land on a speaker.
    private static func inputs() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.filter { inputChannels($0) > 0 }.map {
            Device(id: $0,
                   name: string($0, kAudioObjectPropertyName) ?? "input \($0)",
                   manufacturer: string($0, kAudioObjectPropertyManufacturer) ?? "")
        }
    }

    private static func systemDefault() -> Device? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return Device(id: id,
                      name: string(id, kAudioObjectPropertyName) ?? "the system input",
                      manufacturer: string(id, kAudioObjectPropertyManufacturer) ?? "")
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
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
    /// would truncate a device with several input streams.
    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeInput,
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
}
