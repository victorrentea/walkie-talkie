import CoreAudio
import Foundation

/// **The microphone's gain never sits at zero for long** (2026-10-15).
///
/// The Wave XLR's input volume went to 0.00 at 19:02 that evening — nothing in
/// Walkie or Addons writes an input volume, Wave Link was not running, the
/// system log has no line about it; the knob is the only suspect — and every
/// sentence for twenty minutes came back *No words heard* while Victor was
/// talking normally. Victor: *"I'd like to prevent it if possible in the
/// future."* The knob cannot be locked from here; its effect can be undone.
///
/// Every 2 s, off the main thread, the device the relay records through
/// (`InputDevice.resolve`) is read:
/// - **volume ≥ `floor`** → remembered, per device name (`UserDefaults`), as the
///   level to go back to;
/// - **volume < `floor`** → set back to the remembered level, and the chip says
///   so (`🎚️ Elgato Wave XLR gain fell to 0% — put back to 72%`). No level
///   remembered yet (first run, or a device never seen up) → said once, nothing
///   written: there is no level of his to restore.
/// - **muted** → said once per mute, **never undone**: the XLR's tap-to-mute is
///   a deliberate gesture as often as an accidental one.
///
/// Log: `🎚️ gain guard: …`.
enum GainGuard {
    /// Under 5 % a take is ~-60 dB — measured: peak 10–39 against 5,000–32,000.
    static let floor: Float32 = 0.05
    private static let interval: TimeInterval = 2
    private static let queue = DispatchQueue(label: "gain-guard", qos: .utility)
    private static var timer: DispatchSourceTimer?
    private static var saidMuted: String?
    private static var saidNoLevel: String?

    /// `say` is called on the main queue with what the chip should flash.
    static func start(say: @escaping (String) -> Void) {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { check(say: say) }
        t.resume()
        timer = t
    }

    private static func key(_ name: String) -> String { "gainGuard.level.\(name)" }

    private static func check(say: @escaping (String) -> Void) {
        guard let device = InputDevice.resolve().device else { return }
        let name = device.name
        let main = { (text: String) in DispatchQueue.main.async { say(text) } }

        if let muted: UInt32 = read(device.id, kAudioDevicePropertyMute, 0), muted != 0 {
            if saidMuted != name {
                saidMuted = name
                Log.info("🎚️ gain guard: \(name) is muted — said, not undone")
                main("🔇 \(name) is muted")
            }
        } else {
            saidMuted = nil
        }

        guard let volume: Float32 = read(device.id, kAudioDevicePropertyVolumeScalar, 0) else { return }
        let defaults = UserDefaults.standard
        if volume >= floor {
            saidNoLevel = nil
            if abs(defaults.float(forKey: key(name)) - volume) > 0.005 { defaults.set(volume, forKey: key(name)) }
            return
        }
        // Turned down on purpose (`MicMute`, a device with no mute switch).
        if MicMute.holdsDown(name) { return }
        let was = Int((volume * 100).rounded())
        let level = defaults.float(forKey: key(name))
        guard level >= floor else {
            if saidNoLevel != name {
                saidNoLevel = name
                Log.error("🎚️ gain guard: \(name) at \(was)% and no earlier level to put back")
                main("🎚️ \(name) gain is at \(was)% — turn it up")
            }
            return
        }
        let ok = write(device.id, kAudioDevicePropertyVolumeScalar, level)
        // A device that refuses the write is said once, not every 2 s.
        if !ok { if saidNoLevel == name { return }; saidNoLevel = name }
        let to = Int((level * 100).rounded())
        Log.error("🎚️ gain guard: \(name) fell to \(was)% — " + (ok ? "put back to \(to)%" : "could not be set back"))
        main(ok ? "🎚️ \(name) gain fell to \(was)% — put back to \(to)%"
                : "🎚️ \(name) gain is at \(was)% — turn it up")
    }

    /// The master element first, then channel 1 — devices differ in which they expose.
    private static func read<T>(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ zero: T) -> T? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            var value = zero
            var size = UInt32(MemoryLayout<T>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    private static func write(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: Float32) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(id, &address),
                  AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue else { continue }
            var v = value
            if AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
                return true
            }
        }
        return false
    }
}
