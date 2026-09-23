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

    /// **The microphones Victor names by their picture** (four on 2026-09-19,
    /// the Bluetooth transmitter added 2026-09-22).
    ///
    /// He asked for the chip to say which one is open — `Listening(🎙️/E)...` —
    /// and for the menu to let him pick between them, with the ones that are not
    /// plugged in greyed out. That is two features and one list: a picture, a
    /// name and the strings CoreAudio answers with, in one place, because a
    /// glyph on the chip that disagreed with the tick in the menu would be worse
    /// than neither.
    ///
    /// **Matched on name *and* manufacturer**, joined into one haystack. The DJI
    /// receiver is the reason and is still the hardest case: its USB product
    /// name is `Wireless Mic Rx` and the only place the brand appears is the
    /// manufacturer string, which is what keeps it matching across the
    /// Mic 2 / Mic Mini / Mic 3 line. The Elgato is the mirror case — `Wave XLR`
    /// is the product and `Elgato Systems` the maker, while `Wave Link
    /// MicrophoneFX` and `Wave Link Stream` are the *virtual* devices its driver
    /// installs and are made by `Corsair Memory, Inc.`, so neither needle
    /// reaches them.
    ///
    /// **The order is the preference, and it is the same order in both places
    /// the list is used** (Victor, 2026-09-19: *"the preference of mic to use is:
    /// XLR>DJI>BOSE>MAC … order them like this in menu and impl
    /// autoselection"*). One array is the menu's rows top to bottom **and** the
    /// ladder `resolve()` walks for *automatic*: a menu whose order disagreed
    /// with the automatic pick would be teaching the wrong thing every time he
    /// opened it.
    ///
    /// It is a quality ranking, not a convenience one — the XLR on his desk is a
    /// condenser through a preamp, the DJI is a lavalier on his collar, the Bose
    /// is a headset, and the built-in is two feet away across a desk with a
    /// projector fan in the room. So the built-in is last: it is what is left
    /// when nothing he brought is plugged in.
    /// **Two names each, and that is `Engine`'s rule applied here**: the
    /// top-level menu row is read out of the corner of the eye while the menu is
    /// open over his work, so it gets `short`; the list under the arrow is where
    /// the question *which device exactly* is actually asked, so it gets
    /// `label`. `Engine` learnt this the expensive way, by stretching the whole
    /// menu to the width of `mlx-community/whisper-large-v3-turbo`.
    struct Known {
        let id: String
        let glyph: String
        let short: String
        let label: String
        let needles: [String]
    }

    static let known: [Known] = [
        Known(id: "xlr",  glyph: "🎙️", short: "XLR", label: "Elgato Wave XLR",
              needles: ["wave xlr", "elgato"]),
        // **One DJI row, and it is the receiver** (2026-09-23, Victor: *"vom
        // scoate DJI mic mini tx din lista. pastram doar RX pt moment cu emoji =
        // 🎤"*). The transmitter paired over Bluetooth had its own row for a day
        // (`tx`, 16 kHz HFP); it is gone, and the receiver took the microphone
        // glyph. The needles stay off a bare `dji mic`: the transmitter is named
        // `DJI Mic Mini-B83BBE` and would be pulled straight back in by it. The
        // receiver's brand is only in the manufacturer string
        // (`DJI Technology Co., Ltd.`), which is part of the haystack.
        Known(id: "rx",   glyph: "🎤", short: "DJI Rx", label: "DJI Wireless Mic Rx",
              needles: ["wireless mic rx", "wireless mic", "dji technology"]),
        // **The room's own microphone** (2026-09-22). It was only ever in
        // Victor Addons' list, which is how the two menus came to disagree:
        // addons ranked it *second*, above the XLR, because in a hall a
        // far-field speakerphone with AGC beats a condenser pointed at one
        // chair. That reasoning survives, the rank does not — Victor's order is
        // `XLR>DJI>BOSE>MAC` (2026-09-19) and the speakerphone slots in below
        // the lavaliers, which are on his collar wherever he walks.
        Known(id: "stage", glyph: "🏛️", short: "Stage", label: "Stage Speakerphone",
              needles: ["room speakerphone", "speakerphone"]),
        Known(id: "bose", glyph: "🎧", short: "Bose", label: "Bose",
              needles: ["bose"]),
        Known(id: "mac",  glyph: "💻", short: "Mac", label: "MacBook Pro Microphone",
              needles: ["macbook pro microphone", "built-in microph"]),
    ]

    /// The ladder, spelled with the glyphs, for the `Automatic` row — the menu
    /// says what automatic *does* rather than asking him to remember it.
    static var ladder: String { known.map(\.glyph).joined(separator: " ▸ ") }

    /// **Microphones this app never records through, whatever else happens**
    /// (2026-09-23, Victor: *"niciodata nu voi folosi mic de pe WH casti bt"* —
    /// *"e f prost"*). The Sony WH-1000XM3's microphone is a Bluetooth HFP
    /// capsule at 16 kHz, and opening it also drags the headphones' playback
    /// down to the same 16 kHz mono. None of `known` matches it, so the ladder
    /// never picks it; the one door left open was the system default, which
    /// macOS hands to the headphones the moment they connect. Lowercased
    /// substrings of the CoreAudio name.
    static let neverRecord: [String] = ["wh-1000"]

    static func isNeverRecord(_ device: Device) -> Bool {
        let name = device.name.lowercased()
        return neverRecord.contains { name.contains($0) }
    }

    // MARK: - Which one he picked

    /// **`auto`, or one of `known`'s ids** — stored beside `dictationSource`,
    /// and for its reason: a microphone is a setting of the room he is in, and a
    /// room outlives a launch.
    ///
    /// **`auto` is the default and stays the documented behaviour** (the DJI if
    /// it is there, otherwise the system's input). A picker with no *automatic*
    /// would have quietly retired the rule that makes the receiver work without
    /// anybody touching a menu — the whole point of which is that in a workshop
    /// the only thing he does is plug it in.
    static let preferenceKey = "micDevice"

    /// **On disk, not in `UserDefaults`, since 2026-09-22** — see `MicChoice`
    /// for why. `UserDefaults` is still read once, as a migration, so the
    /// device picked before the file existed survives the upgrade; the file
    /// wins from the first write.
    static var chosenId: String {
        get {
            let ids = known.map(\.id)
            let onDisk = MicChoice.read(known: ids)
            if onDisk != MicChoice.automatic { return onDisk }
            // Nothing published yet: adopt the old preference and publish it,
            // so the other app sees the same device from this launch on.
            if let legacy = UserDefaults.standard.string(forKey: preferenceKey),
               ids.contains(legacy), !FileManager.default.fileExists(atPath: MicChoice.url.path) {
                MicChoice.write(legacy)
                return legacy
            }
            return MicChoice.automatic
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferenceKey)
            MicChoice.write(newValue)
        }
    }

    /// Which of `known` this Mac can see right now. Asked at every menu open,
    /// never cached: a receiver is plugged in *while* the menu is up at least as
    /// often as before it.
    static func availableIds() -> Set<String> {
        let devices = inputs()
        return Set(known.filter { k in devices.contains { matches($0, k) } }.map(\.id))
    }

    /// **The device this recording will actually use, and which of `known` it
    /// is** — the one answer the chip, the menu and `select` all read, so they
    /// cannot disagree.
    ///
    /// A pick that is not plugged in **falls back to automatic** rather than to
    /// silence: the menu greys those rows, but a receiver can be unplugged after
    /// it was picked, and a dictation that records nothing because a setting
    /// outlived a cable is the failure this whole file exists to prevent. The
    /// glyph follows the fallback, so the chip says what he is actually being
    /// heard through and not what he once asked for.
    static func resolve() -> (known: Known?, device: Device?) {
        let devices = inputs()
        if chosenId != "auto", let want = known.first(where: { $0.id == chosenId }),
           let device = devices.first(where: { matches($0, want) }) {
            return (want, device)
        }
        // **Automatic, and the fallback for a pick that is not plugged in: the
        // first of `known` that is here, in its order.** It was *the DJI
        // whenever it is there, otherwise the system default* until 2026-09-19;
        // what that rule could not express is a desk with both the XLR and the
        // receiver on it, which is his ordinary desk.
        for k in known {
            if let device = devices.first(where: { matches($0, k) }) { return (k, device) }
        }
        // **None of his own — only then the system's own choice**, which is the
        // last line of defence and deliberately not a rung on the ladder: macOS
        // points the default input at whatever last claimed it, including the
        // eleven virtual devices on this Mac, and that is the failure this file
        // was written to stop being the normal case.
        //
        // **Never the WH-1000XM3, even here** (2026-09-23): when the system
        // default is a `neverRecord` device, any other input that is not one
        // records instead, and with nothing else on the Mac there is no device
        // at all — `select` then refuses the recording rather than open it.
        guard let device = systemDefault() else { return (nil, nil) }
        if isNeverRecord(device) {
            guard let other = devices.first(where: { !isNeverRecord($0) }) else { return (nil, nil) }
            return (known.first { matches(other, $0) }, other)
        }
        return (known.first { matches(device, $0) }, device)
    }

    /// **The glyph the chip wears, or empty** — empty for a device that is none
    /// of `known`, which is the honest answer for the day he records through
    /// Loopback or a headset nobody has named yet.
    static func currentGlyph() -> String { resolve().known?.glyph ?? "" }

    /// **Wispr Flow's name for its microphone, read onto this roster**
    /// (2026-09-22) — Wispr's own `History.micDevice`, so a Wispr sentence says
    /// what *Wispr* heard it through rather than what the relay's meter is on.
    /// Victor: *"ar trebui să-i citești microfonul activ al lui Wispr … să
    /// mapezi ce știe Wispr la ceea ce avem noi, nu invers"*.
    ///
    /// Wispr's vocabulary, as it stands in 16 000 rows: a CoreAudio name with a
    /// transport suffix (`Elgato Wave XLR (USB)`), `Auto-detect (<name>)`, its
    /// own `Built-in mic (recommended)`, and `🎓 TO Wispr (Virtual)` — the
    /// `AudioBridge` loopback, whose voice is the relay's own recorder, so that
    /// one honestly is `currentGlyph()`. Anything else (`krisp`, a Sony headset)
    /// is none of the six and says nothing, which the chip renders as a plain
    /// `Listening...`.
    static func glyph(wisprName name: String) -> String {
        var n = name.lowercased()
        if n.contains("to wispr") { return currentGlyph() }
        if n.hasPrefix("auto-detect (") {
            n = String(n.dropFirst("auto-detect (".count))
            if n.hasSuffix(")") { n.removeLast() }
        }
        if n.hasPrefix("built-in") || n == "macbook pro" {
            return known.first { $0.id == "mac" }?.glyph ?? ""
        }
        return known.first { k in k.needles.contains { n.contains($0) } }?.glyph ?? ""
    }

    /// What the menu's **top row** says: the glyph and the short name of the
    /// device that would record right now. A device that is none of `known`
    /// gets CoreAudio's own name, which is the only name it has.
    static func currentShortLabel() -> String {
        let r = resolve()
        if let k = r.known { return "\(k.glyph) \(k.short)" }
        return r.device?.name ?? "the system input"
    }

    /// The same device said in full, for a log line and for the harness.
    static func currentLabel() -> String {
        let r = resolve()
        if let k = r.known { return "\(k.glyph) \(k.label)" }
        return r.device?.name ?? "the system input"
    }

    private static func matches(_ device: Device, _ k: Known) -> Bool {
        let haystack = "\(device.name) \(device.manufacturer)".lowercased()
        return k.needles.contains { haystack.contains($0) }
    }

    /// Point `input` at the microphone this recording should use and return a
    /// human name for the log.
    ///
    /// Always sets a device, even when the choice is the default one: the audio
    /// unit holds whatever device it was last told about, so a recording made
    /// after the receiver was unplugged would otherwise still be aimed at a
    /// device that is gone.
    ///
    /// - Returns: nil when the only input left is a `neverRecord` one — the
    ///   caller refuses to record rather than open it (2026-09-23).
    static func select(on input: AVAudioInputNode) -> String? {
        guard let chosen = resolve().device else {
            if let fallback = systemDefault(), isNeverRecord(fallback) {
                Log.error("mic: the only input is \(fallback.name), which is never recorded through — refusing")
                return nil
            }
            return "the system input"
        }

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
            if let fallback = systemDefault(), isNeverRecord(fallback) { return nil }
            return "the system input"
        }
        return chosen.name
    }

    // MARK: - CoreAudio

    struct Device {
        let id: AudioDeviceID
        let name: String
        let manufacturer: String
    }

    /// Every device that can actually record. Outputs and the input-less halves
    /// of duplex devices are dropped here rather than at the match, so "first
    /// one that looks like a DJI" cannot land on a speaker.
    // MARK: - The system's default input, for the harness

    /// **The name of the system's chosen input**, so a test can put it back.
    static func systemDefaultName() -> String? { systemDefault()?.name }

    /// **Point the whole system's input at a device, by name.**
    ///
    /// This exists for `tools/wispr-test.sh` and nothing else. Wispr Flow's
    /// microphone is chosen in Wispr's own UI and stored as a Chromium
    /// `MediaDeviceInfo.deviceId` — a per-origin salted hash that cannot be
    /// computed from a device name and is rewritten by Wispr's own process, so
    /// it is not scriptable. What *is* scriptable is the system default, and
    /// Wispr follows it when its microphone is set to **Auto-detect**. That one
    /// setting is what turns "flip a preference by hand before and after every
    /// run" into a scripted end-to-end test.
    ///
    /// Substring, case-insensitive: CoreAudio names carry emoji and trailing
    /// model numbers, and asking a caller to type one exactly is asking for a
    /// typo that looks like *Wispr heard nothing*.
    ///
    /// - Returns: the name it actually selected, or nil if nothing matched.
    @discardableResult
    static func setSystemDefault(matching needle: String) -> String? {
        let wanted = needle.lowercased()
        guard let device = inputs().first(where: { $0.name.lowercased().contains(wanted) && !isNeverRecord($0) })
        else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil,
                                                UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        guard status == noErr else {
            Log.error("input: could not make \(device.name) the default (OSStatus \(status))")
            return nil
        }
        Log.info("🎚️ system default input → \(device.name)")
        return device.name
    }

    /// Every input this Mac can see, for a harness that has to say what it
    /// looked at when nothing matched.
    static func inputNames() -> [String] { inputs().map(\.name) }

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
