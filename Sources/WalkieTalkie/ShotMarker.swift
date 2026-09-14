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

    /// **What a marker is naming** (2026-09-14, the same day the shot marker was
    /// built — Victor: *"Vreau același lucru și pentru selecție"*).
    ///
    /// Two kinds, one mechanism, and deliberately one file: the phrase, the
    /// number words, the digit forms and the pattern that reads them back are a
    /// single vocabulary, and a vocabulary spread over two files drifts the
    /// first time somebody rewords one end of it.
    ///
    /// What they do **not** share is what the marker becomes in the words. A
    /// shot marker turns into `[shot 2]`, a reference to a file listed below the
    /// sentence — there is no way to put a picture inside a line of text. A
    /// selection marker turns into **the selected text itself**, because that is
    /// a thing a sentence can hold, and holding it inline is the whole point:
    /// *"textul selectat trebuie inserat într-o etapă de postprocesare în
    /// transcripție, în locul markerului"*. → `resolve`
    enum Kind: String, CaseIterable {
        case shot
        case selection
        /// An element ⌘-clicked in a Chrome page. Inline since 2026-09-14, for
        /// the reason the highlight is: it belongs to the clause he said it in.
        case element

        /// The spoken form's opening words. English for the reason the whole
        /// phrase is (see `phrase`), and two words rather than one for the
        /// selection because `selection one` is a thing a recogniser hears in
        /// ordinary speech, while `selected text one` is not.
        var words: String {
            switch self {
            case .shot: return "screenshot"
            case .selection: return "selected text"
            // Two words again, and neither of them common on its own: `element
            // one` is a thing a sentence about code says by accident.
            case .element: return "picked element"
            }
        }

        /// The clip's file name. Hyphenated, because it is a path.
        var slug: String {
            switch self {
            case .shot: return "screenshot"
            case .selection: return "selected-text"
            case .element: return "picked-element"
            }
        }
    }

    /// One spoken clip: which kind of thing it names and which one of them.
    struct Clip: Hashable {
        let kind: Kind
        let index: Int
    }

    /// **Ten, because an eleventh picture in one sentence is not a thing that
    /// happens** — and every marker is a word cut out of what he was saying, so
    /// the vocabulary is deliberately small rather than open-ended. A shot past
    /// the ceiling is still taken, still attached and still listed by its
    /// offset; it simply gets no marker. The same ceiling counts each kind
    /// separately: a sentence with three pictures and three highlights in it
    /// says `screenshot three` and `selected text three`, and the two numbers
    /// never have to be told apart because the words in front of them differ.
    static let maximumIndex = 10

    /// The spoken form. English, like every other string this app renders, and
    /// for a sharper reason than the projector: the phrase has to survive Wispr's
    /// formatting pass intact inside a **Romanian** sentence, and an English
    /// token in a Romanian stream is exactly what a formatter leaves alone. It
    /// did, twice out of two, the first time it was measured.
    private static let words = ["one", "two", "three", "four", "five",
                                "six", "seven", "eight", "nine", "ten"]

    private static func phrase(_ clip: Clip) -> String {
        "\(clip.kind.words) \(words[clip.index - 1])"
    }

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
    private static var buffers: [Clip: AVAudioPCMBuffer] = [:]
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
            for kind in Kind.allCases {
                for index in 1...maximumIndex {
                    let clip = Clip(kind: kind, index: index)
                    guard buffers[clip] == nil else { continue }
                    guard let url = synthesise(clip) else { continue }
                    guard let file = try? AVAudioFile(forReading: url),
                          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                        frameCapacity: AVAudioFrameCount(file.length)),
                          (try? file.read(into: buffer)) != nil else {
                        Log.error("shot marker: could not load \(url.lastPathComponent)")
                        continue
                    }
                    buffers[clip] = buffer
                }
            }
            Log.info("📣 markers ready — \(buffers.count) of \(maximumIndex * Kind.allCases.count)")
        }
    }

    /// One `say` per clip, ever. AIFF because `AVAudioFile` reads it directly and
    /// a conversion step is one more thing to be wrong about.
    private static func synthesise(_ clip: Clip) -> URL? {
        let url = cacheDir.appendingPathComponent("\(clip.kind.slug)-\(clip.index).aiff")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // A named voice, because the default follows a system setting that can
        // be a novelty voice — `Bahh` says `screenshot one` as a goat — and the
        // whole feature rests on the recogniser hearing two ordinary words.
        // `-r 190` is a shade quicker than speech, to keep the bite out of his
        // sentence as short as it can be.
        task.arguments = ["-v", "Samantha", "-r", "190", "-o", url.path, phrase(clip)]
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
    static func play(_ kind: Kind = .shot, index: Int, whenQuiet: (() -> Bool)? = nil) {
        guard isEnabled, index >= 1, index <= maximumIndex else { return }
        let clip = Clip(kind: kind, index: index)
        guard let whenQuiet = whenQuiet else { queue.async { speak(clip, waited: 0) }; return }
        let askedAt = CFAbsoluteTimeGetCurrent()
        // `asyncAfter` rather than a sleep: the queue is serial and shared with
        // the engine, and a second shutter press must not queue behind this one's
        // wait for a gap.
        func look() {
            let waited = CFAbsoluteTimeGetCurrent() - askedAt
            guard !whenQuiet(), waited < maskCeiling else { return speak(clip, waited: waited) }
            queue.asyncAfter(deadline: .now() + gapTick) { look() }
        }
        queue.async { look() }
    }

    private static func speak(_ clip: Clip, waited: TimeInterval) {
        guard let buffer = buffers[clip] else { return }
        guard let player = startedPlayer(format: buffer.format) else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
        // The wait is logged because it is the number that says whether the gate
        // is earning its keep: a marker that always waits the full ceiling is a
        // marker being spoken into speech anyway.
        Log.info(String(format: "📣 marker: %@ (%.0f ms for a gap)", phrase(clip), waited * 1000))
    }

    /// The engine is built once and kept: the device is virtual, so a running
    /// output stream costs nothing, and building one inside the shutter's window
    /// would spend tens of milliseconds where the marker's whole value is landing
    /// at the right word.
    private static func startedPlayer(format: AVAudioFormat) -> AVAudioPlayerNode? {
        if let player = player, engine?.isRunning == true { return player }
        engine?.stop()
        engine = nil; player = nil

        guard let device = AudioDevices.output(matching: deviceNeedle) else {
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

    // MARK: - The same marker, as samples

    private static var converted: [Clip: AVAudioPCMBuffer] = [:]
    private static var convertedTo: AVAudioFormat?

    /// **The marker as PCM in someone else's format**, for a source that records
    /// the audio it transcribes and can therefore splice rather than play —
    /// `MicRecorder.insert(_:)`.
    ///
    /// Converted once and cached, because the caller is a shutter press and
    /// building an `AVAudioConverter` under one is the kind of work that turns a
    /// gesture into a stutter. Nil until `prepare()` has loaded the clips.
    static func pcm(_ kind: Kind = .shot, index: Int, in format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard isEnabled, index >= 1, index <= maximumIndex else { return nil }
        let clip = Clip(kind: kind, index: index)
        return queue.sync {
            if convertedTo?.sampleRate != format.sampleRate
                || convertedTo?.channelCount != format.channelCount {
                converted = [:]
                convertedTo = format
            }
            if let cached = converted[clip] { return cached }
            guard let source = buffers[clip], let out = convert(source, to: format) else { return nil }
            converted[clip] = out
            return out
        }
    }

    private static func convert(_ buffer: AVAudioPCMBuffer,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        // Rounded up with room to spare: a resampler's output length is not
        // exactly the ratio, and a buffer one frame short truncates the word.
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        // One buffer per call — `MicRecorder.append`'s reason: handing the same
        // one back twice loops it into the output for ever.
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else {
            Log.error("shot marker: could not convert — \(error?.localizedDescription ?? "no frames")")
            return nil
        }
        return out
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
        // **The homophones are gone, and the reasoning that put them here was
        // simply wrong** (2026-09-14, same evening, found in review).
        //
        // They were added because `selected text two` came back from the local
        // model as `Selected text to`. The comment then claimed a sentence never
        // says `screenshot` or `selected text` followed by a bare preposition by
        // accident — which it does, constantly: *attach the screenshot **to** the
        // PR*, *take a screenshot **for** the readme*, *copy the selected text
        // **to** the clipboard*. Every one of those became a marker, and the
        // sentence lost the words. `won`, `ate` and `fore` are ordinary words
        // with the same problem and were never even motivated by a measurement.
        //
        // What the miss costs is one highlight falling back to the list under
        // the words; what the false positive costs is his sentence. The trade is
        // not close. Digits and real number words only.
    ]

    /// **The whitespace around the marker is eaten with it.** Wispr promotes the
    /// marker to a paragraph of its own — blank line above, blank line below —
    /// and those blank lines are not his: they exist because this app put two
    /// English words in the middle of his sentence. Taking them out puts the
    /// sentence back the way he said it, with the reference inline where the
    /// words were.
    ///
    /// **One expression for both kinds, so one scan keeps their order.** A
    /// sentence can hold a picture and a highlight in either order — he presses
    /// the shutter, talks, selects a paragraph, talks — and two passes over the
    /// same text would each rewrite the string the other was measured against.
    /// Group 1 says it was a shot, group 2 a selection, group 3 is the number in
    /// whichever form it came back as.
    private static let pattern = try? NSRegularExpression(
        pattern: #"\s*\b(?:(screen[ -]?shots?)|(selected\s+texts?)|(picked\s+elements?))\s+(\w+)\s*[.,!;:]*\s*"#,
        options: [.caseInsensitive])

    /// **Rewrite the spoken markers — a shot into a reference an agent can
    /// resolve, a selection into the words he had highlighted — and say which
    /// of each were named.**
    ///
    /// - Parameter shots: the marker numbers that actually have a picture
    ///   behind them — `shotMarkerNumbers.values`. It is the **safety net**, and
    ///   it is a set rather than a count on purpose: a capture that failed leaves
    ///   a number spoken with nothing behind it, and a count would then renumber
    ///   every marker after it onto the wrong frame. The relay knows the truth;
    ///   the marker only ever supplies *position*.
    /// - Parameter selections: the marker number → **the text that was
    ///   highlighted at that moment**, already clamped by the caller. A selection
    ///   marker does not become a reference the way a shot does: it is replaced
    ///   by the words themselves, quoted, where he said them. What is not in
    ///   this map is a marker for a highlight that never got filed, and it is
    ///   taken out of the sentence like an unattached picture.
    /// - Parameter inline: false leaves the *sentence* without the
    ///   marker and without the highlight — the form the **corpus** takes. The
    ///   relay's own recording heard neither the marker nor the paragraph he
    ///   selected, and a transcript filed beside it that quotes a page of code
    ///   is a pair whose words are not in its audio. → `AppDelegate.deliver`
    /// - Returns: the rewritten text and, per kind, the indices it resolved in
    ///   the order they were spoken.
    static func resolve(text: String,
                        shots: Set<Int> = [],
                        selections: [Int: String] = [:],
                        elements: [Int: String] = [:],
                        inline: Bool = true)
        -> (text: String, shots: [Int], selections: [Int], elements: [Int]) {
        guard !(shots.isEmpty && selections.isEmpty && elements.isEmpty),
              let pattern = pattern, !text.isEmpty else { return (text, [], [], []) }
        let full = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: full)
        guard !matches.isEmpty else { return (text, [], [], []) }

        // **The seams are tidied, the insertions are not** (found in review,
        // 2026-09-14). `tidy` ran over the whole result, so a highlight of four
        // lines of Java arrived with every indent collapsed to one space — the
        // clause it replaced never went through that. So the pieces are kept
        // apart: what came out of *his* text may be squeezed, what this app put
        // in is delivered byte for byte.
        var pieces: [(text: String, verbatim: Bool)] = []
        var foundShots: [Int] = []
        var foundSelections: [Int] = []
        var foundElements: [Int] = []
        var cursor = text.startIndex
        var dropped = 0
        for match in matches {
            guard let range = Range(match.range, in: text),
                  let word = Range(match.range(at: 4), in: text) else { continue }
            // **One group per kind, and the number is the last group.** Adding a
            // kind means adding an alternative *and* moving the number's index;
            // the element marker shipped once with neither, so `picked element
            // one` stayed in his sentence as though he had said it.
            let kind: Kind
            if match.range(at: 1).location != NSNotFound { kind = .shot }
            else if match.range(at: 2).location != NSNotFound { kind = .selection }
            else { kind = .element }
            let token = text[word].lowercased()
            let index = spoken[token] ?? Int(token)
            // Not a marker at all — `screenshots and notes`, `screenshot folder`,
            // `selected text below`. Left exactly as it was, whitespace
            // included: only a match this app could have spoken is a match.
            guard let index = index else { continue }
            // A leading space rather than none, because the whitespace that was
            // there has just been eaten; the trailing one closes the gap to the
            // word after. Doubles are tidied below.
            let replacement: String?
            switch kind {
            case .shot:
                // **`(screenshot: shot#01)`** — Victor's own mock of the
                // envelope, 2026-09-14. A parenthesis rather than a bracket
                // because this is an aside inside his sentence and brackets are
                // what the envelope's *clauses* use; and the frame's real file
                // name rather than an index, so the reference and the row in the
                // list below are the same string.
                // **`inline` governs this arm too** — it did not, and the corpus
                // paid for it (found in review, 2026-09-14): a Wispr dictation
                // with one picture filed `pune asta (screenshot: shot#01) sub un
                // strat` against a recording that contains only `pune asta sub un
                // strat`. That is precisely the poisoned pair the flag exists to
                // prevent, and the shot was the one kind still ignoring it.
                guard shots.contains(index) else { replacement = nil; break }
                replacement = inline ? String(format: " (screenshot: shot#%02d) ", index) : " "
                foundShots.append(index)
            case .selection:
                guard let selected = selections[index] else { replacement = nil; break }
                // **Bracketed as well as quoted** (2026-09-14). Bare double
                // quotes are the ones he might have dictated himself — *"it
                // seemed to be inserted in dictation, but without clear double
                // quotes. Clearly delimitate them"* — and they break outright on
                // a highlight that contains a quote of its own, which a line of
                // code very often does. The bracket says what it is and cannot
                // be confused with anything he said.
                replacement = inline
                    ? " (selected text: \"\(selected)\") " : " "
                foundSelections.append(index)
            case .element:
                // **The whole description, not a reference.** A picked element
                // is three short facts — the selector, what it said, the page —
                // and a reader who has them needs nothing looked up; a `#01`
                // here would send him to a list to reassemble a sentence he is
                // already reading.
                guard let described = elements[index] else { replacement = nil; break }
                replacement = inline ? " (\(described)) " : " "
                foundElements.append(index)
            }
            // **A match with nothing behind it is left exactly as it was.**
            //
            // It used to be replaced with a space, which is how one wrong guess
            // turned into missing words: `screenshot to` with no second picture
            // attached deleted both words and delivered *attach the the PR*. The
            // relay is guessing when it decides a phrase was its own marker, and
            // a guess that turns out wrong must cost nothing — the text goes
            // through untouched and the fallback list still names the picture.
            guard let replacement = replacement else {
                dropped += 1
                continue
            }
            pieces.append((String(text[cursor..<range.lowerBound]), false))
            pieces.append((replacement, true))
            cursor = range.upperBound
        }
        pieces.append((String(text[cursor...]), false))
        let out = pieces.map { $0.verbatim ? $0.text : tidy($0.text) }.joined()

        if dropped > 0 {
            // `info`, not `error`: with the text now left alone this is a phrase
            // that merely *looked* like a marker, which is a thing his sentences
            // will do — `screenshot folder`, `selected text below`.
            Log.info("markers: \(dropped) phrase(s) looked like a marker with nothing "
                     + "attached — have shots \(shots.sorted()), selections "
                     + "\(selections.keys.sorted()). Left in the words untouched.")
        }
        // The ends are his text's, so trimming them is a seam like any other.
        return (out.trimmingCharacters(in: .whitespacesAndNewlines),
                foundShots, foundSelections, foundElements)
    }

    /// The seams the substitution leaves: a doubled space where two bits of
    /// whitespace met, and a space in front of the punctuation that followed the
    /// marker's own full stop.
    private static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "[ \t]{2,}", with: " ",
                                            options: .regularExpression)
        out = out.replacingOccurrences(of: " ([.,!?;:])", with: "$1",
                                       options: .regularExpression)
        return out
    }
}
