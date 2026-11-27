import AppKit

/// **The whoosh of a sentence leaving** (2026-11-27, Victor: *"put a sound like a
/// push, like sending a mail … something flashing out fast when the prompt is
/// actually shipped, delivered into the terminal, bound, caret or wherever it
/// goes"*). Mail's own *Mail Sent* sound, played from `recordDelivery` — the one
/// place every route reports a landing (bound terminal, caret, new session, ⚡
/// question). Never for an `undelivered` prompt or a desk test route.
///
/// On unless the `sentWhoosh` default says off (no menu row yet).
enum SentSound {

    static let defaultsKey = "sentWhoosh"

    static var isOn: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static let path = "/System/Applications/Mail.app/Contents/Resources/Mail Sent.aiff"

    private static let sound: NSSound? = {
        guard let s = NSSound(contentsOfFile: path, byReference: true) else { return nil }
        s.volume = 0.5
        return s
    }()

    /// `to`: the landing's label, only for the log.
    static func play(to: String) {
        guard isOn, ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        guard let sound else { Log.error("📨 sent whoosh: \(path) did not load — silent"); return }
        DispatchQueue.main.async {
            if sound.isPlaying { sound.stop() }
            let ok = sound.play()
            Log.info("📨 sent whoosh → \(to)\(ok ? "" : " — play() REFUSED")")
        }
    }
}
