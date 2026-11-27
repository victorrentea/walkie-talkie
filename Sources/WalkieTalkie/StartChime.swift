import AppKit

/// **The sound of the microphone opening.** It was a falling "womp" for one
/// morning (2026-10-01); Victor then asked for it out — *"înlocuiește-l cu un
/// hârâit ca de transmisie (white noise scurt), debifat by default în meniu"* —
/// and it plays only while the `Radio Squelch` row is ticked. Synthesised white
/// noise until 2026-10-05, when he picked a real one from youtu.be/nt71N59hydQ
/// and cut it himself (*"Am pus clipul pe care îl doresc în Downloads tăiat
/// frumos. Pune-l pe ăla la volum mic"*): `assets/start-squelch.wav` is his
/// 0.26 s mp3, mono 44.1 kHz, −15 dB (peak −19 dBFS), led by 150 ms of silence —
/// `play()` was starting and he heard nothing, because the built-in speakers
/// wake late and swallowed the whole short clip, where the old 0.32 s hiss
/// outlasted the wake.
/// The silence goes on **both** channels before the mono mix (`adelay=150:all=1`):
/// on the left alone it summed two copies 150 ms apart — *"să hârâie o singură
/// dată, nu de 2 ori"*.
///
/// **A sentence bound for the terminal opens with the other radio** (2026-11-26,
/// Victor: *"use the second type of radio squelch when I start a conversation
/// bound to a terminal. Use that other sound to distinguish"*): ChatGPT voice's
/// `chat-voice-on.wav` — the squelch 22 % higher plus a rising roger beep — so
/// the ear tells a prompt to the bound agent from every other sentence (caret,
/// plain, ⚡ question, new session), which keep `start-squelch.wav`. Same
/// `Radio Squelch` tick for both.
enum StartChime {

    /// `UserDefaults` beside `autosend`: a preference, not data. Absent = off.
    static let defaultsKey = "startSquelch"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The menu row's title.
    static let menuTitle = "Radio Squelch"

    static let plainFile = "start-squelch.wav"
    static let boundFile = "chat-voice-on.wav"
    /// Read by Victor Net, which hands the squelch to the phone.
    static let phoneNote = Notification.Name("ro.victorrentea.walkie.squelch")

    private static let plainSound: NSSound? = load(plainFile)
    private static let boundSound: NSSound? = load(boundFile)

    /// The file a start plays: the other radio for a sentence bound for the terminal.
    static func file(bound: Bool) -> String { bound ? boundFile : plainFile }

    static func play(bound: Bool = false) {
        guard isOn else { return }
        let name = file(bound: bound)
        // **And in the phone's headphones** (2026-11-27): Victor Net forwards this to the
        // phone, which plays the same radio only while its music plays — the sign he is
        // wearing them (`PhoneMediaPause.watchSquelch` there).
        DistributedNotificationCenter.default().postNotificationName(
            phoneNote, object: nil, userInfo: ["file": name], deliverImmediately: true)
        guard let sound = bound ? boundSound : plainSound else { Log.error("📻 radio squelch: no \(name) loaded — silent"); return }
        if sound.isPlaying { sound.stop() }
        let ok = sound.play()
        Log.info(String(format: "📻 radio squelch: play() %@ %@, %.2f s, volume %.2f", name, ok ? "started" : "REFUSED", sound.duration, sound.volume))
    }

    /// `Resources/<name>` installed, `assets/<name>` from a `.build` binary;
    /// nil (silence) when neither is there.
    private static func load(_ name: String) -> NSSound? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourcePath { candidates.append(URL(fileURLWithPath: res).appendingPathComponent(name)) }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 { candidates.append(dir.appendingPathComponent("assets/\(name)")); dir = dir.deletingLastPathComponent() }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            .flatMap { NSSound(contentsOf: $0, byReference: false) }
    }
}
