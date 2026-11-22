import Foundation

/// **Live captions from the local model** (2026-10-05). Victor: *"Pe stilul
/// Eleven Labs Live Captions nu putem face ceva similar cu ajutorul modelului
/// local … un fel de sliding window. Aceste window-uri să le trimiți atunci când
/// fac o pauză în vorbire … de jumătate de secundă"*, then *"în niciun caz nu
/// trebuie să întârzii transcrierea finală … când închid dictarea, instantaneu
/// anulezi orice se întâmpla în curs … vei tăia unde pare că nu mai vorbesc"*.
///
/// - **When**: a pause of `pause` (0.5 s of the meter's own quiet) after new
///   speech, or every `steadyEvery` while he talks on without one.
/// - **What**: the take from `anchor` to where the voice stopped (+ `tail`),
///   copied out of memory (`MicRecorder.takeSlice`) — never the trailing
///   silence, which is where Whisper invents sentences.
/// - **Window size is free up to 30 s** — Whisper pads every window to 30 s, so
///   a 3 s window costs what a 20 s one does (his own decodes on this Mac:
///   median 1.24 s at 3–6 s of audio, 1.65 s at 6–10, 1.68 s at 20–60). The
///   window is cut only when it nears `maxWindow`.
/// - **What stays fixed**: a segment two decodes in a row agree on, ending at
///   least `LiveAgreement.settle` before the voice stopped, is committed and the
///   window starts after it (`LiveAgreement`, LocalAgreement on Whisper's own
///   segments — no word timings, which cost +45 %).
/// - **Its own helper** (`LocalWhisper(live: true)`, a second copy of the
///   weights): at the close a window still decoding is **SIGKILLed** and the
///   final decode runs on the sentence's helper, alone. A signal-raised cancel
///   inside one helper was measured first and did not do it — MLX held the
///   interpreter for up to 0.7 s, a whole decode. The killed helper comes back
///   after the sentence's words have landed (`warmLater`).
final class LocalLiveCaption {

    let whisper = LocalWhisper(live: true)
    /// Asked each time: the source's recorder is replaced when a microphone
    /// call never comes back (2026-11-22, `MicLanes`).
    private let meterNow: () -> MicRecorder
    private var meter: MicRecorder { meterNow() }

    /// Everything settled, then the tail still moving — `DictationSource.didHearLive`'s shape.
    var onCaption: ((_ committed: String, _ partial: String) -> Void)?

    static let rate = 16000
    /// The pause that sends a window (Victor: *"jumătate de secundă"*).
    static let pause: TimeInterval = 0.5
    /// A window anyway, this often, while he talks with no pause.
    static let steadyEvery: TimeInterval = 2.5
    /// Kept after the voice stops: the end of the last word, not the silence after it.
    static let tail: TimeInterval = 0.25
    /// Under this much new speech since the last window, nothing is sent.
    static let minNew: TimeInterval = 0.3
    /// Whisper's window is 30 s; past this the oldest unsettled text is committed
    /// as heard and the window keeps its last `keepOnOverflow` seconds.
    static let maxWindow: TimeInterval = 28
    static let keepOnOverflow: TimeInterval = 20

    private var timer: Timer?
    private(set) var active = false
    private var agreement = LiveAgreement()
    /// Absolute sample (`MicRecorder.takeEnd`'s ruler) where the window starts.
    private var anchor = 0
    private var inFlight = false
    /// The speech end the last window covered — new speech is measured from it.
    private var decodedThrough = 0
    private var lastDecodeAt = Date.distantPast
    /// Bumped at `end`, so an answer from a closed sentence is dropped.
    private var epoch = 0
    private var loading = false
    private var decodes = 0, failures = 0

    private static let window = FileManager.default.temporaryDirectory
        .appendingPathComponent("walkie-live-window.pcm")

    init(meter: @escaping () -> MicRecorder) { self.meterNow = meter }

    var ready: Bool { whisper.ready }

    /// Brings the live helper up, if live captions are on and it is not.
    func warm() {
        guard LocalLive.isOn, !whisper.ready, !loading else { return }
        loading = true
        whisper.start { [weak self] why in
            DispatchQueue.main.async {
                self?.loading = false
                if let why { Log.error("💬 live: the helper did not come up — \(why)") }
            }
        }
    }

    /// After the sentence's own words have landed — never beside its decode.
    func warmLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.warm() }
    }

    func shutDown() {
        guard whisper.pid != nil else { return }
        whisper.stop()
    }

    /// A new model picked: the live helper reloads with it.
    func restart() {
        guard whisper.pid != nil else { return warm() }
        whisper.stop()
        warm()
    }

    /// The microphone is open on a new take. Main queue.
    func begin() {
        guard LocalLive.isOn, whisper.ready else { return }
        active = true
        agreement = LiveAgreement()
        anchor = 0
        decodedThrough = 0
        lastDecodeAt = Date()
        inFlight = false
        decodes = 0; failures = 0
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The take is closed (stop or cancel). **Before** the final decode is asked
    /// for: a window still decoding is killed here, so it cannot hold the GPU.
    func end() {
        guard active else { return }
        active = false
        timer?.invalidate(); timer = nil
        epoch += 1
        if inFlight {
            inFlight = false
            whisper.killNow()
            Log.info("💬 live: a window was still decoding at the close — its helper killed, the final decode goes alone")
        }
        Log.info("💬 live: \(decodes) window(s) this take, \(failures) failed — \(agreement.committed.count) segment(s) settled")
    }

    private func tick() {
        guard active, !inFlight, whisper.ready else { return }
        let end = meter.takeEnd
        let quiet = meter.quietSeconds
        let speechEnd = max(anchor, end - Int(quiet * Double(Self.rate)))
        guard speechEnd - decodedThrough >= Int(Self.minNew * Double(Self.rate)) else { return }
        let paused = quiet >= Self.pause
        let steady = !paused && Date().timeIntervalSince(lastDecodeAt) >= Self.steadyEvery
        guard paused || steady else { return }
        let to = min(end, speechEnd + Int(Self.tail * Double(Self.rate)))
        if Double(to - anchor) / Double(Self.rate) > Self.maxWindow {
            let keepFrom = Double(to - anchor) / Double(Self.rate) - Self.keepOnOverflow
            if let shift = agreement.commitBefore(keepFrom) {
                anchor += Int(shift * Double(Self.rate))
            } else {
                anchor = to
                decodedThrough = speechEnd
            }
            Log.info("💬 live: nothing settled in \(Int(Self.maxWindow)) s — the oldest of it is kept as heard")
            guard anchor < to else { return onCaption?(agreement.committedText, agreement.pendingText) ?? () }
        }
        let samples = meter.takeSlice(from: anchor, to: to)
        guard samples.count >= Self.rate / 2 else { return }
        do {
            try samples.withUnsafeBufferPointer { try Data(buffer: $0).write(to: Self.window) }
        } catch {
            Log.error("💬 live: could not write the window — \(error.localizedDescription)")
            return
        }
        inFlight = true
        decodedThrough = speechEnd
        lastDecodeAt = Date()
        let e = epoch, from = anchor, asked = Date()
        let speech = Double(speechEnd - from) / Double(Self.rate)
        let seconds = Double(samples.count) / Double(Self.rate)
        whisper.transcribeWindow(pcm: Self.window.path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, e == self.epoch else { return }
                self.inFlight = false
                self.absorb(result, from: from, speech: speech, seconds: seconds, asked: asked, paused: paused)
            }
        }
    }

    private func absorb(_ result: LocalWhisper.WindowResult?, from: Int, speech: Double,
                        seconds: Double, asked: Date, paused: Bool) {
        decodes += 1
        guard let r = result else {
            failures += 1
            Log.error("💬 live: the window got no answer")
            if !whisper.ready { warmLater() }
            return
        }
        guard r.compressionRatio <= LocalWhisper.loopCeiling else {
            Log.info(String(format: "💬 live: the window looped (cr %.1f) — not shown", r.compressionRatio))
            return
        }
        let shift = agreement.absorb(r.segments, speechSeconds: speech)
        if shift > 0 { anchor = from + Int(shift * Double(Self.rate)) }
        onCaption?(agreement.committedText, agreement.pendingText)
        Log.info(String(format: "💬 live: %.1f s window (%@) decoded in %.2f s, on screen %.2f s after the ask — %d settled, %d moving",
                        seconds, paused ? "pause" : "steady", r.decodeSeconds, Date().timeIntervalSince(asked),
                        agreement.committed.count, agreement.pending.count))
    }
}

/// **Which segments of a window are settled** — the pure half of
/// `LocalLiveCaption`, unit-tested (`LiveAgreementTests`). A segment is
/// committed when the decode before agreed on it, word for word (case and
/// punctuation aside), and it ended at least `settle` before the voice stopped —
/// the last segment of a window is never committed, it is the one still being
/// said. Times are seconds from the window's start; a commit moves the start to
/// the end of the last settled segment and shifts what is pending with it.
struct LiveAgreement {
    static let settle: TimeInterval = 1.0

    private(set) var committed: [String] = []
    private(set) var pending: [LocalWhisper.Segment] = []

    var committedText: String { Self.join(committed) }
    var pendingText: String { Self.join(pending.map(\.text)) }

    /// The seconds the window's start moves by (0: nothing settled).
    mutating func absorb(_ raw: [LocalWhisper.Segment], speechSeconds: Double) -> Double {
        // Nothing past the voice: a segment that starts in the trailing silence
        // is the model talking to itself.
        let segs = raw.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.start < speechSeconds
        }
        var k = 0
        while k + 1 < segs.count, k < pending.count, Self.same(segs[k].text, pending[k].text),
              segs[k].end <= speechSeconds - Self.settle {
            k += 1
        }
        guard k > 0 else { pending = segs; return 0 }
        committed += segs[..<k].map(\.text)
        let shift = segs[k - 1].end
        pending = segs[k...].map { .init(text: $0.text, start: $0.start - shift, end: $0.end - shift) }
        return shift
    }

    /// **The window outgrew the model** (no settled pause in `maxWindow`): the
    /// pending segments that end by `seconds` are kept as heard and the window
    /// starts after them — never at a point inside a kept segment, or its words
    /// would be heard twice. Returns the new start, or nil when no segment ends
    /// that early: then everything pending is kept and the window starts afresh
    /// at the caller's end.
    mutating func commitBefore(_ seconds: Double) -> Double? {
        let k = pending.prefix { $0.end <= seconds }.count
        guard k > 0 else {
            committed += pending.map(\.text)
            pending = []
            return nil
        }
        committed += pending[..<k].map(\.text)
        let shift = pending[k - 1].end
        pending = pending[k...].map { .init(text: $0.text, start: $0.start - shift, end: $0.end - shift) }
        return shift
    }

    static func same(_ a: String, _ b: String) -> Bool { norm(a) == norm(b) }

    private static func norm(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " })
            .split(separator: " ").joined(separator: " ")
    }

    private static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// The switch: Engine submenu `Live captions (local)`, `UserDefaults`
/// `localLiveCaptions`, `WT_LOCAL_LIVE=0|1` for one run.
///
/// **Off unless he ticks it** (2026-11-22, Victor: *"subtitrarea live: da, off by default"* —
/// it was on by default since 2026-10-05; his own Mac had it unticked, and a fresh install
/// paid a second ~2 GB helper for it). A saved value, on or off, still wins.
enum LocalLive {
    static let defaultsKey = "localLiveCaptions"
    static let menuTitle = "Live captions (local)"
    /// With no preference saved.
    static let unset = false

    static func on(defaults: UserDefaults = .standard,
                   environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if let env = environment["WT_LOCAL_LIVE"] { return env != "0" }
        return defaults.object(forKey: defaultsKey) as? Bool ?? unset
    }

    static var isOn: Bool {
        get { on() }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
