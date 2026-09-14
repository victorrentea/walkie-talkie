import AVFoundation
import CoreAudio
import Foundation

/// **A spoken marker, played into the recogniser's ear at the moment he presses
/// the shutter, so the transcript says *where in the sentence* the picture
/// belongs** (2026-09-14).
///
/// The problem it solves is Victor's: *"aș lua și referi precis … e mult mai
/// util dacă le-aș referi după index și le-aș trece direct în text care e
/// indexul care. Că, după timp, e greu să estimezi."* Every frame already
/// carries the second it was taken at (`shot-00:56…`), and an agent handed five
/// of those has to guess which clause of a forty-second sentence each one
/// belongs to. A marker does not need guessing: the words `screenshot one`
/// really were in the audio, between the word before and the word after, so the
/// recogniser puts them exactly where he pressed.
///
/// ## Why this can work at all: two microphones, one voice
///
/// Since 2026-09-13 Wispr Flow's microphone is pinned to the Loopback device
/// `🎓 TO Wispr`, whose sources are the physical `MacBook Pro Microphone` *and*
/// Pass-Thru. The relay's own `MicRecorder` opens the **physical** device
/// directly (`InputDevice`). So there are two independent recordings of the same
/// voice, and anything this app plays into the Loopback device's output side
/// reaches **Wispr and nothing else** — not the speakers, and not the corpus.
///
/// Measured the day it was built, on a 20 s clip of his own voice with two
/// markers spliced in:
///
/// | | |
/// |---|---|
/// | the markers in `asrText` | both, in position |
/// | the markers in `formattedText` | both, **promoted to their own paragraphs** |
/// | the corpus WAV recorded in parallel | `mean_volume: -91.0 dB` — digital silence |
/// | Wispr's round trip | row `formatted` ~5 s, ⌘V 4654 ms after the microphone closed |
///
/// The one cost measured: a marker **cuts the word it lands on**. `pus sub un
/// strat` came back as `pus sub un-` / `Strat` — and Wispr marks the break with
/// a dash, which is a more useful artefact than it sounds. He presses the
/// shutter between clauses, so this is the uncommon case rather than the
/// ordinary one.
///
/// ## The two halves are in one file on purpose
///
/// `play(index:)` says the words and `resolve(text:available:)` reads them back. They
/// are one vocabulary — the number words, the digit forms, the phrase itself —
/// and a vocabulary spread over two files is a vocabulary that drifts the first
/// time somebody changes the phrasing at one end. → `.claude/rules/dictation-source.md`
enum ShotMarker {

    // MARK: - What is said

    /// **Ten, because an eleventh picture in one sentence is not a thing that
    /// happens** — and every marker is a word cut out of what he was saying, so
    /// the vocabulary is deliberately small rather than open-ended. A shot past
    /// the ceiling is still taken, still attached and still listed by its
    /// offset; it simply gets no marker.
    static let maximumIndex = 10

    /// The spoken form. English, like every other string this app renders, and
    /// for a sharper reason than the projector: the phrase has to survive Wispr's
    /// formatting pass intact inside a **Romanian** sentence, and an English
    /// token in a Romanian stream is exactly what a formatter leaves alone. It
    /// did, twice out of two, the first time it was measured.
    private static let words = ["one", "two", "three", "four", "five",
                                "six", "seven", "eight", "nine", "ten"]

    private static func phrase(_ index: Int) -> String { "screenshot \(words[index - 1])" }

    // MARK: - Where it is played

    /// **The device Wispr is pinned to, matched by substring.** Not the system
    /// default input, which is the physical microphone and is what the relay's
    /// own recorder follows — playing there would put the marker in the corpus
    /// and nowhere near Wispr.
    ///
    /// `WT_MARKER_DEVICE` overrides, and a name that matches nothing disables the
    /// feature with one line in the log rather than failing per shutter press:
    /// a Mac where Wispr has been moved back to the built-in microphone is a Mac
    /// where a marker reaches nobody, and that is a thing to say once.
    private static var deviceNeedle: String {
        ProcessInfo.processInfo.environment["WT_MARKER_DEVICE"] ?? "TO Wispr"
    }

    /// **On by default, and it fails safe in every direction.** With no device it
    /// says nothing; with Wispr on another microphone the sound reaches a device
    /// nobody records; with a source that does not accept markers it is never
    /// asked. `WT_SHOT_MARKERS=0` turns it off for one run.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["WT_SHOT_MARKERS"] != "0"
    }

    /// Serial, and everything below happens on it: `AVAudioEngine` setup is not
    /// thread-safe, the cached buffers are shared mutable state, and two shutter
    /// presses a third of a second apart must not race each other into the same
    /// engine. Never the main thread — the shutter's whole contract is that the
    /// flash lands on the keypress.
    private static let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.shot-marker")

    private static var engine: AVAudioEngine?
    private static var player: AVAudioPlayerNode?
    private static var buffers: [Int: AVAudioPCMBuffer] = [:]
    /// Said once, not once per press — see `deviceNeedle`.
    private static var complained = false

    /// Regenerable, so Caches: the same folder `shots/` and `cancelled/` live in,
    /// beside them rather than inside them.
    private static let cacheDir = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ro.victorrentea.wispr-relay/markers")

    /// **Synthesise and load before a gesture is waiting on it.** `say` is a
    /// subprocess and takes a few hundred milliseconds per clip; a shutter press
    /// that had to wait for one would put the marker after the words it is
    /// supposed to sit between. Called from `prepare()`, off the main thread,
    /// and the files survive restarts so this is a one-time cost on a fresh Mac.
    static func prepare() {
        guard isEnabled else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            for index in 1...maximumIndex where buffers[index] == nil {
                guard let url = synthesise(index) else { continue }
                guard let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil else {
                    Log.error("shot marker: could not load \(url.lastPathComponent)")
                    continue
                }
                buffers[index] = buffer
            }
            Log.info("📣 shot markers ready — \(buffers.count) of \(maximumIndex)")
        }
    }

    /// One `say` per index, ever. AIFF because `AVAudioFile` reads it directly and
    /// a conversion step is one more thing to be wrong about.
    private static func synthesise(_ index: Int) -> URL? {
        let url = cacheDir.appendingPathComponent("screenshot-\(index).aiff")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // A named voice, because the default follows a system setting that can
        // be a novelty voice — `Bahh` says `screenshot one` as a goat — and the
        // whole feature rests on the recogniser hearing two ordinary words.
        // `-r 190` is a shade quicker than speech, to keep the bite out of his
        // sentence as short as it can be.
        task.arguments = ["-v", "Samantha", "-r", "190", "-o", url.path, phrase(index)]
        do { try task.run() } catch {
            Log.error("shot marker: say failed — \(error.localizedDescription)")
            return nil
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              FileManager.default.fileExists(atPath: url.path) else {
            // The voice is missing on this Mac. Once, with the name in it, so the
            // fix is obvious rather than a mystery about audio routing.
            Log.error("shot marker: `say -v Samantha` produced nothing — is the voice installed?")
            return nil
        }
        return url
    }

    /// **A marker played over continuous speech is lost, and that is measured**
    /// (2026-09-14). Three markers into a silent dictation came back
    /// `Screenshot one. Screenshot two. Screenshot three.` — the channel is
    /// perfect. The same marker played six seconds into an unbroken twelve-second
    /// sentence left **no trace at all** in `asrText`, although it is the louder
    /// of the two signals (mean −15.7 dB against the voice's −26.8). So this is
    /// not a level that can be turned up: a recogniser handed two voices at once
    /// transcribes the one that makes a sentence, and the marker is the one that
    /// does not.
    ///
    /// Hence the gate. It matters because overlapping **is** his gesture — *"De
    /// exemplu, ăsta acum"*, shutter pressed mid-clause — so a marker that only
    /// works in a pause he happens to leave is a marker that mostly does not work.
    static let maskCeiling: TimeInterval = 1.5
    /// How much silence counts as a gap. Short, because what the recogniser needs
    /// is a clean **onset** for the marker, not a hole big enough to hold it.
    static let gapNeeded: TimeInterval = 0.12
    /// How often the gate looks. Cheap — one lock-protected read of a `Double`.
    private static let gapTick: TimeInterval = 0.04

    /// **Say the marker for picture `index`.** Fire and forget: the caller is the
    /// shutter and must not wait for an audio device to open, still less for a
    /// gap in his sentence.
    ///
    /// - Parameter whenQuiet: *is he between words right now* — `MicRecorder`'s
    ///   `quietSeconds`, read through a closure so nothing here has to know what
    ///   a dictation source is. Waits up to `maskCeiling` for a yes and then says
    ///   it anyway: a marker that lands in the middle of a word is usually lost,
    ///   which costs nothing, while a marker never said is a picture with no
    ///   place in the sentence at all. Nil skips the gate entirely — the test
    ///   route, where there is no voice to collide with.
    static func play(index: Int, whenQuiet: (() -> Bool)? = nil) {
        guard isEnabled, index >= 1, index <= maximumIndex else { return }
        guard let whenQuiet = whenQuiet else { queue.async { speak(index, waited: 0) }; return }
        let askedAt = CFAbsoluteTimeGetCurrent()
        // `asyncAfter` rather than a sleep: the queue is serial and shared with
        // the engine, and a second shutter press must not queue behind this one's
        // wait for a gap.
        func look() {
            let waited = CFAbsoluteTimeGetCurrent() - askedAt
            guard !whenQuiet(), waited < maskCeiling else { return speak(index, waited: waited) }
            queue.asyncAfter(deadline: .now() + gapTick) { look() }
        }
        queue.async { look() }
    }

    private static func speak(_ index: Int, waited: TimeInterval) {
        guard let buffer = buffers[index] else { return }
        guard let player = startedPlayer(format: buffer.format) else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        // The wait is logged because it is the number that says whether the gate
        // is earning its keep: a marker that always waits the full ceiling is a
        // marker being spoken into speech anyway.
        Log.info(String(format: "📣 marker: %@ (%.0f ms for a gap)", phrase(index), waited * 1000))
    }

    /// The engine is built once and kept: the device is virtual, so a running
    /// output stream costs nothing, and building one inside the shutter's window
    /// would spend tens of milliseconds where the marker's whole value is landing
    /// at the right word.
    private static func startedPlayer(format: AVAudioFormat) -> AVAudioPlayerNode? {
        if let player = player, engine?.isRunning == true { return player }
        engine?.stop()
        engine = nil; player = nil

        guard let device = outputDevice(matching: deviceNeedle) else {
            if !complained {
                complained = true
                Log.error("shot markers: no output device matching '\(deviceNeedle)' — "
                          + "markers are off. Wispr's microphone is pinned to a Loopback "
                          + "device; if that has been changed, so must WT_MARKER_DEVICE.")
            }
            return nil
        }

        let engine = AVAudioEngine()
        // **Before `start()`, and on the output unit rather than the engine.**
        // `AVAudioEngine` has no device property of its own; the only way to aim
        // it anywhere but the system default is the underlying output audio unit,
        // and it is read when the unit is initialised.
        var id = device.id
        if let unit = engine.outputNode.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                              kAudioUnitScope_Global, 0, &id,
                                              UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else {
                Log.error("shot markers: could not aim the engine at \(device.name) (OSStatus \(status))")
                return nil
            }
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch {
            Log.error("shot markers: the engine would not start — \(error.localizedDescription)")
            return nil
        }
        Self.engine = engine; Self.player = player
        Log.info("📣 shot markers → \(device.name)")
        return player
    }

    private struct Device { let id: AudioDeviceID; let name: String }

    /// The output twin of `InputDevice.inputs()`, and deliberately a separate
    /// reading: a Loopback device has both sides, and asking for the input one
    /// here would aim the engine at the half Wispr is listening to rather than
    /// the half this app has to speak into.
    private static func outputDevice(matching needle: String) -> Device? {
        let wanted = needle.lowercased()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids where outputChannels(id) > 0 {
            guard let name = deviceName(id), name.lowercased().contains(wanted) else { continue }
            return Device(id: id, name: name)
        }
        return nil
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
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

    /// Variable-length `AudioBufferList`, sized by the same call that fills it —
    /// `InputDevice.inputChannels`'s reason, on the other scope.
    private static func outputChannels(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeOutput,
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

    // MARK: - Reading them back out

    /// Every form the marker has been measured to come back as.
    ///
    /// **Both the word and the digit, because one dictation produced both**
    /// (2026-09-14): `formattedText` said `Screenshot two.` and `pastedText`, of
    /// the same row, said `Screenshot 2.` — so a pattern written against either
    /// one alone silently half-works depending on which column delivered.
    /// Romanian number words are here because the phrase sits in a Romanian
    /// stream and a formatter that decides to translate it is a thing to survive,
    /// not to be surprised by.
    private static let spoken: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "unu": 1, "doi": 2, "trei": 3, "patru": 4, "cinci": 5,
        "șase": 6, "sase": 6, "șapte": 7, "sapte": 7,
        "opt": 8, "nouă": 9, "noua": 9, "zece": 10,
    ]

    /// **The whitespace around the marker is eaten with it.** Wispr promotes the
    /// marker to a paragraph of its own — blank line above, blank line below —
    /// and those blank lines are not his: they exist because this app put two
    /// English words in the middle of his sentence. Taking them out puts the
    /// sentence back the way he said it, with the reference inline where the
    /// words were.
    private static let pattern = try? NSRegularExpression(
        pattern: #"\s*\bscreen[ -]?shots?\s+(\w+)\s*[.,!;:]*\s*"#,
        options: [.caseInsensitive])

    /// **Rewrite the spoken markers into references an agent can resolve, and
    /// say which pictures were named.**
    ///
    /// - Parameter available: the marker numbers that actually have a picture
    ///   behind them — `shotMarkerNumbers.values`. It is the **safety net**, and
    ///   it is a set rather than a count on purpose: a capture that failed leaves
    ///   a number spoken with nothing behind it, and a count would then renumber
    ///   every marker after it onto the wrong frame. The relay knows the truth;
    ///   the marker only ever supplies *position*.
    /// - Returns: the rewritten text and the indices it resolved, in the order
    ///   they were spoken.
    static func resolve(text: String, available: Set<Int>) -> (text: String, found: [Int]) {
        guard !available.isEmpty, let pattern = pattern, !text.isEmpty else { return (text, []) }
        let full = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: full)
        guard !matches.isEmpty else { return (text, []) }

        var out = ""
        var found: [Int] = []
        var cursor = text.startIndex
        var dropped = 0
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let word = Range(match.range(at: 1), in: text) else { continue }
            let token = text[word].lowercased()
            let index = spoken[token] ?? Int(token)
            // Not a marker at all — `screenshots and notes`, `screenshot folder`.
            // Left exactly as it was, whitespace included: only a match this app
            // could have spoken is a match.
            guard let index = index else { continue }
            out += text[cursor..<range.lowerBound]
            if available.contains(index) {
                // A leading space rather than none, because the whitespace that
                // was there has just been eaten; the trailing one closes the gap
                // to the word after. Doubles are tidied below.
                out += " [shot \(index)] "
                found.append(index)
            } else {
                out += " "
                dropped += 1
            }
            cursor = range.upperBound
        }
        out += text[cursor...]

        if dropped > 0 {
            Log.error("shot markers: \(dropped) marker(s) named a picture that is "
                      + "not attached — have \(available.sorted()). Dropped from the text.")
        }
        return (tidy(out), found)
    }

    /// The seams the substitution leaves: a doubled space where two bits of
    /// whitespace met, and a space in front of the punctuation that followed the
    /// marker's own full stop.
    private static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "[ \t]{2,}", with: " ",
                                            options: .regularExpression)
        out = out.replacingOccurrences(of: " ([.,!?;:])", with: "$1",
                                       options: .regularExpression)
        // A marker at the very start or end of the sentence leaves its own edge.
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
