import AVFoundation
import ObjCTry
import CoreAudio

/// The relay's own microphone — the only one in the loop.
///
/// For months the relay read a finished transcript out of another app's database
/// and swallowed that app's paste on the way past. It owns the whole path now:
/// it opens the input itself, hands the WAV to the model, and nothing outside
/// this app hears the sentence or types it anywhere.
///
/// Samples are stamped `engine: "whisper-local"` in the corpus, so rows recorded
/// this way stay distinguishable from anything filed before it.
///
/// ## 16 kHz mono 16-bit, because that is what the other half already speaks
///
/// Whisper resamples to 16 kHz internally and `History.audio` is 16 kHz mono
/// PCM, so writing anything richer would only be thrown away twice — once by the
/// model and once by a corpus whose every existing sample is that format. The
/// input device is picked by `InputDevice` (the DJI receiver when it is plugged
/// in, the system's own choice otherwise) and is read at its native rate;
/// `AVAudioConverter` does the resampling on the audio thread's buffers, and
/// downmixes the receiver's two channels to the one Whisper wants.
/// **One 64 ms hop of the meter, kept per take** (2026-09-27, for `VoiceAffect`).
///
/// `t` is seconds from the top of the WAV — the ruler `TimedWord.start` is on —
/// taken from `writtenFrames`, not from a hop count (a marker spliced into the
/// file moves every later hop, and a count would not see it). `rms` is the
/// same int16 RMS the voiced bar is judged on, `voiced` is that verdict.
struct MeterHop: Equatable {
    let t: Float
    let rms: Float
    let voiced: Bool
    /// `VoicedMeter.hop` frames at 16 kHz.
    static let seconds: TimeInterval = Double(VoicedMeter.hop) / VoicedMeter.rate
}

/// **The voiced-seconds meter's arithmetic, on its own** (2026-09-27, Q13) —
/// fixed 1024-frame (64 ms) windows over the converted 16 kHz mono int16 stream,
/// RMS against an adaptive noise floor. `MicRecorder` owns one under its `lock`
/// and feeds it every converted buffer; nothing here locks, and the only audio
/// it keeps is the < 1024-sample carry.
///
/// **The windows run over the stream, not over each buffer.** Until Q13 every
/// buffer was cut into whole windows and its remainder thrown away, and the
/// remainder is not small: Loopback hands the tap 4096 frames at 48 kHz, which
/// convert to **1365** at 16 kHz — one window and 341 frames dropped, a quarter
/// of the audio never metered. A ten-word 3.5 s clip counted 1.1–1.9 s voiced
/// and fell under Q8's 2 s floor. Now the remainder is carried into the next
/// buffer, every sample is judged exactly once, and `flush()` judges the last
/// partial window at the close — which is what `evals/voiced-seconds.py` always
/// did, since it runs the windows over a whole file.
struct VoicedMeter {
    /// The window, in frames of the 16 kHz output — 64 ms. Fixed rather than
    /// "one converted buffer", because a buffer's length depends on the input
    /// device's rate and the constants below were calibrated at this hop over
    /// the whole corpus (`evals/voiced-seconds.py`).
    static let hop = 1024
    static let rate = 16000.0
    /// How far over the floor a window has to sit to count as speech. 9 dB is
    /// wide enough that room tone, a fan and the receiver's hiss never reach it,
    /// and narrow enough to catch the tail of a quiet word.
    static let overFloor: Float = 9
    /// And an absolute floor under that, for the case the adaptive one cannot
    /// see: a recording that is *entirely* room tone has a noise floor equal to
    /// its own content, and every window would clear a purely relative bar.
    static let absoluteFloor: Float = 180

    /// What one `feed` or `flush` found.
    struct Fed {
        /// Voiced seconds in the windows this call completed.
        var seconds: TimeInterval = 0
        /// One per *full* window completed — a `MeterHop` is 64 ms by contract
        /// (`VoiceAffect` counts them), so `flush()`'s partial window adds its
        /// seconds but no hop.
        var hops: [MeterHop] = []
        /// The loudest completed window's distance over its bar, in dB (−∞
        /// when none completed) — the beacon's `level` is read off it.
        var loudestOver: Float = -.infinity
        var spoke: Bool { seconds > 0 }
    }

    /// The noise floor this recording is being judged against, tracked rather
    /// than fixed.
    ///
    /// A fixed threshold cannot work here and the reason is already written down
    /// in `InputDevice`: measured on the same room, the DJI receiver peaks at
    /// 16552 where the built-in microphone manages 855. One number would call
    /// the built-in silent all day or the receiver's room tone speech.
    ///
    /// So: instant attack downwards, slow release upwards — the floor drops to
    /// any quiet window at once and climbs back at 2% a window, which is the
    /// standard cheap noise tracker and is what makes it settle into the gaps
    /// between his words rather than into his words. Seeded on the first window,
    /// which is the one place a recording is guaranteed not to have started
    /// mid-syllable.
    private(set) var noiseFloor: Float = -1
    /// The samples at the end of the last buffer that did not fill a window.
    private var carry: [Int16] = []
    /// Where `carry[0]` sits in the file, in frames — its hop's `t`.
    private var carryAt: Double = 0

    init() { carry.reserveCapacity(Self.hop) }

    /// Per recording: a floor carried over from the last sentence would be a
    /// floor for a room, a microphone and a distance from it that may all have
    /// changed since — and a carry from it is audio of another take.
    mutating func reset() {
        noiseFloor = -1
        carry.removeAll(keepingCapacity: true)
        carryAt = 0
    }

    /// Judges every window this buffer completes — the carried remainder of the
    /// last buffer topped up first — and carries its own remainder on.
    /// - Parameter base: where `samples[0]` sits in the file, in frames.
    mutating func feed(_ samples: UnsafeBufferPointer<Int16>, at base: Double) -> Fed {
        let hop = Self.hop, n = samples.count
        var fed = Fed()
        fed.hops.reserveCapacity((carry.count + n) / hop)
        var i = 0
        if !carry.isEmpty {
            i = min(hop - carry.count, n)
            carry.append(contentsOf: UnsafeBufferPointer(rebasing: samples[0..<i]))
            guard carry.count == hop else { return fed }
            let window = carry.withUnsafeBufferPointer { judge($0) }
            record(window, at: carryAt, frames: hop, into: &fed)
            carry.removeAll(keepingCapacity: true)
        }
        while i + hop <= n {
            let window = judge(UnsafeBufferPointer(rebasing: samples[i..<(i + hop)]))
            record(window, at: base + Double(i), frames: hop, into: &fed)
            i += hop
        }
        if i < n {
            carry.append(contentsOf: UnsafeBufferPointer(rebasing: samples[i..<n]))
            carryAt = base + Double(i)
        }
        return fed
    }

    /// Judges the last partial window, at the close: its RMS over the samples
    /// it has, its seconds at their true length. No hop (see `Fed.hops`).
    mutating func flush() -> Fed {
        var fed = Fed()
        guard !carry.isEmpty else { return fed }
        let frames = carry.count
        let window = carry.withUnsafeBufferPointer { judge($0) }
        record(window, at: carryAt, frames: frames, into: &fed)
        fed.hops.removeAll()
        carry.removeAll(keepingCapacity: true)
        return fed
    }

    private mutating func judge(_ s: UnsafeBufferPointer<Int16>) -> (rms: Float, bar: Float) {
        var sum: Float = 0
        for v in s { let f = Float(v); sum += f * f }
        let rms = (sum / Float(s.count)).squareRoot() + 1e-6
        if noiseFloor < 0 || rms < noiseFloor { noiseFloor = rms }      // instant attack
        else { noiseFloor += (rms - noiseFloor) * 0.02 }                // slow release
        let bar = max(Self.absoluteFloor, noiseFloor * pow(10, Self.overFloor / 20))
        return (rms, bar)
    }

    private func record(_ w: (rms: Float, bar: Float), at frame: Double, frames: Int, into fed: inout Fed) {
        let voiced = w.rms > w.bar
        if voiced { fed.seconds += Double(frames) / Self.rate }
        fed.hops.append(MeterHop(t: Float(frame / Self.rate), rms: w.rms, voiced: voiced))
        fed.loudestOver = max(fed.loudestOver, 20 * log10(w.rms / w.bar))
    }
}

/// **A (2026-09-28, wave 3): buffers flowing but every sample exactly zero — a
/// stall the missing-buffer watchdog cannot see.** Pure: fed each converted
/// buffer's peak and ticked by the watchdog, on one monotonic clock (seconds),
/// so `ZeroPeakWatchTests` can drive it over a timeline.
///
/// In the VM every DEAF take looked the same — `105 buffers, peak 0, 0 tap
/// restart(s)`, no `AVAudioEngineConfigurationChange` all night — on the first
/// Wispr mic open after a Wispr launch, both apps reading BlackHole 2ch. Buffers
/// arriving means the engine is running; digital zeros mean what reaches the
/// tap is not the device's signal (a driver handing this client silence, a
/// muted or zero-volume input, a denied grant). A real microphone never gives
/// exact zeros for a second — room tone, ADC noise — so the watch only ever
/// fires on a device that is feeding nothing.
///
/// - Armed until the take's first non-zero sample, then off for the rest of the
///   take: a Loopback that goes quiet after its clip ends is not a stall.
/// - Fires after `window` of zero buffers that are still arriving (the last one
///   under `flowing` ago — a gap is the missing-buffer watchdog's).
/// - At most `maxRestarts` per take; each restart starts a fresh window, so they
///   are at least `window` apart. After the last one, another window of zeros
///   is `gaveUp`: the take stays DEAF and goes to Recover.
/// - The first non-zero buffer after a restart is `cameBack` — the log says
///   whether the restart worked, which is the one thing only the VM can answer.
struct ZeroPeakWatch: Equatable {
    static let window: TimeInterval = 1.0
    static let flowing: TimeInterval = 0.5
    static let maxRestarts = 3
    /// Two buffers is "flowing"; one could be the only buffer before a gap.
    static let minBuffers = 2

    enum Event: Equatable {
        /// Restart number `step` (1…`maxRestarts`), after `buffers` zero buffers
        /// over `seconds` since the window opened.
        case restart(step: Int, buffers: Int, seconds: TimeInterval)
        /// Audio after restart `step`: the buffer's peak, `after` seconds past it.
        case cameBack(step: Int, peak: Int, after: TimeInterval)
        /// `maxRestarts` restarts and still zeros: `buffers` zero buffers over
        /// `seconds` since the first one of the take.
        case gaveUp(restarts: Int, buffers: Int, seconds: TimeInterval)
    }

    private(set) var restarts = 0
    /// A non-zero sample has arrived this take.
    private(set) var heard = false
    private(set) var gaveUp = false
    private var windowStart: TimeInterval?
    private var windowBuffers = 0
    private var lastBuffer: TimeInterval?
    private var firstZero: TimeInterval?
    private var zeroBuffers = 0
    private var restartedAt: TimeInterval?
    private var pending: Event?

    /// Still looking — the recorder only computes a buffer's peak while this is true.
    var armed: Bool { !heard }

    init() {}

    /// One converted buffer, its loudest |sample| (0 = digital silence).
    mutating func buffer(at t: TimeInterval, peak: Int) {
        lastBuffer = t
        guard !heard else { return }
        if peak > 0 {
            heard = true
            if restarts > 0, let r = restartedAt {
                pending = .cameBack(step: restarts, peak: peak, after: max(0, t - r))
            }
            return
        }
        if windowStart == nil { windowStart = t }
        if firstZero == nil { firstZero = t }
        windowBuffers += 1
        zeroBuffers += 1
    }

    /// The tap was restarted for another reason (a configuration change, a
    /// missing-buffer stall): the next window is measured from the buffers
    /// after it.
    mutating func tapRestarted(at t: TimeInterval) {
        windowStart = nil
        windowBuffers = 0
    }

    /// The watchdog's beat: what to do now, if anything.
    mutating func tick(at t: TimeInterval) -> Event? {
        if let e = pending { pending = nil; return e }
        guard !heard, !gaveUp, let start = windowStart, windowBuffers >= Self.minBuffers,
              t - start >= Self.window,
              let last = lastBuffer, t - last < Self.flowing else { return nil }
        let e: Event
        if restarts >= Self.maxRestarts {
            gaveUp = true
            e = .gaveUp(restarts: restarts, buffers: zeroBuffers, seconds: t - (firstZero ?? start))
        } else {
            restarts += 1
            restartedAt = t
            e = .restart(step: restarts, buffers: windowBuffers, seconds: t - start)
        }
        windowStart = nil
        windowBuffers = 0
        return e
    }
}

final class MicRecorder {

    /// **The device the last recording actually opened**, for
    /// `GET /test/state.micOpened` (gap G7) — `resolve()` says what *would* be
    /// used; this is what was. Written on `audioQueue`, read from main; a tuple
    /// of values, torn at worst into a stale-but-consistent pair.
    static var lastOpened: (device: String, rate: Int, channels: Int, at: Date)?


    /// **Test-only** (`POST /test/mic-hang`, 2026-11-22): how many of the next
    /// `start(to:)` calls never return — the open that wedged inside
    /// `-[AVAudioEngine inputNode]` at 13:47:48 that day, without CoreAudio.
    /// Before `lifecycle` is taken, so the hung recorder holds no lock.
    private static let hangLock = NSLock()
    private static var hangOpens = 0
    static var hangOpensForTest: Int {
        get { hangLock.withLock { hangOpens } }
        set { hangLock.withLock { hangOpens = newValue } }
    }
    private static func takeTestHang() -> Bool {
        hangLock.withLock {
            guard hangOpens > 0 else { return false }
            hangOpens -= 1
            return true
        }
    }

    /// Shorter than this and it was a misfire — a click he did not mean, or a
    /// button pressed and released while deciding. Sending an empty transcript
    /// costs an agent turn; dropping half a second of silence costs nothing.
    static let minimumDuration: TimeInterval = 0.35

    /// **What every WAV this recorder writes is in**, named once because two
    /// things now have to agree on it: the recording itself and anything spliced
    /// into it (`insert(_:)`). 16 kHz mono 16-bit for the reason at the top of
    /// this file — Whisper resamples to it and the whole corpus is already in it.
    static let fileFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                          sampleRate: 16000, channels: 1,
                                          interleaved: true)!

    /// **`var` since 2026-09-28 (A)**: the peak-0 watch's second step replaces
    /// it with a fresh engine — a new AUHAL, a new client of the device.
    /// Written only on `restartQueue` under `lifecycle`; read under `lifecycle`
    /// (`start`, `close`) or on `restartQueue` (the watchdog), never racing.
    private var engine = AVAudioEngine()
    /// Where a closed engine waits out `reopenSpacing` before it is released
    /// (see `close`), and when the last one closed — `start` waits out the
    /// rest of that spacing before opening the device again. Under `lifecycle`.
    private static let graveyard = DispatchQueue(label: "mic.retire", qos: .utility)
    private static let reopenSpacing: TimeInterval = 0.3
    private var lastClosedAt: Date?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var startedAt: Date?
    private var url: URL?
    /// The state lock — every field `append` reads on the audio thread.
    /// **Never held across a call into `AVAudioEngine`** (2026-09-24): the tap
    /// callback runs *inside* AVFAudio's realtime-messenger mutex and takes this
    /// lock, so `removeTap` under it is a lock-order inversion. It froze the app
    /// solid on a cancel — main in `closeLocked → removeTap →
    /// RealtimeMessenger::_PerformPendingMessages → mutex`, the messenger thread
    /// in `TapMessage::RealtimeMessenger_Perform → append → lock`, `sample`d.
    private let lock = NSLock()
    /// Serialises `start` and `stop` against each other, and is what is held
    /// across the device open and the teardown. `append` never takes it, so it
    /// can wait on AVFAudio's mutex without closing a cycle.
    private let lifecycle = NSLock()

    private(set) var isRecording = false

    // MARK: A (lab wave 2, 2026-09-28): a recording that got no audio

    /// **What the device actually handed this recording** — told apart from
    /// *he said nothing*. Four relay sentences started within ~5 s of a Wispr
    /// launch measured `0.0 s voiced` while a clip was playing into the device,
    /// and each was called *No speech was heard*, its WAV deleted. A take with
    /// no buffers, or only digital zeros, is a deaf recorder, not a quiet room.
    struct Health: Equatable {
        var device = ""
        var buffers = 0
        /// The loudest converted sample, |int16| — 0 is digital silence.
        var peak = 0
        /// `AVAudioEngineConfigurationChange`s (and stall restarts) survived.
        var restarts = 0
        var seconds: TimeInterval = 0
        var deaf: Bool { buffers == 0 || peak == 0 }
        var line: String {
            String(format: "%@: %d buffers, peak %d, %d tap restart(s), %.1f s", device, buffers, peak, restarts, seconds)
        }
    }
    /// The last closed recording's `Health` (read after `stop()`).
    private(set) var lastHealth: Health?
    private var health = Health()
    /// The peak-0 stall watch (`ZeroPeakWatch`), under `lock`, reset per take.
    private var zeroWatch = ZeroPeakWatch()
    private var configObserver: NSObjectProtocol?
    private var stallTimer: DispatchSourceTimer?
    private let restartQueue = DispatchQueue(label: "mic.restart")

    /// **How many seconds of this recording were actually speech**, updated on
    /// the audio thread as the buffers arrive.
    ///
    /// It exists because the chip's warmth ramp was counting the wrong thing.
    /// Victor: *"uneori eu pur și simplu tac — dacă tac pe microfon și nu vine
    /// semnal, nu știu cât de valoroasă e întârzierea asta"*. He is right, and
    /// the corpus says how right: the **median dictation is only 38% voiced**
    /// (p10 14%), so six seconds of wall clock is 2.3 seconds of speech on an
    /// ordinary sentence and 0.8 on a thoughtful one — and the risk the ramp
    /// forecasts tracks the speech, not the clock. Re-bucketed by this measure
    /// over the 803 clips the local model was re-decoded on
    /// (`evals/short-clip-lid.md`), the cliff is far sharper than the wall-clock
    /// one: **42%** of dictations with under one voiced second come back in a
    /// language he does not speak, **15%** between one and two, and **1% past
    /// two**.
    ///
    /// **Read with `try()`, never with `lock()`** — the same shape `level` and
    /// `quietSeconds` below have, and it is not a micro-optimisation: it is the
    /// difference between a stale number and a frozen Mac.
    ///
    /// `start(to:)` held `lock` from its first line to its last (it holds
    /// `lifecycle` there since 2026-09-24; the `try` stays), and inside it
    /// is a **synchronous CoreAudio device bind**. When the audio stack is wedged
    /// that bind never returns — measured 2026-09-19, twice, with `sample` — so
    /// the lock is held for ever, and the 15 Hz warmth ramp that reads this
    /// property *on the main thread* went down with it: no crash, no log, every
    /// route accepted and never answered. The stack was
    /// `RelayWindow.startWarmth → voicedSeconds → lock` behind
    /// `MicRecorder.start → AVAudioEngine.inputNode → mach_msg`.
    ///
    /// What it costs is the last buffer's worth of speech on a contended read,
    /// which is 64 ms of a ramp that fills over seconds. What it buys is that
    /// **no UI thread can ever wait on a device open**. The `Double` is read
    /// without the lock in that case, exactly as its two neighbours already
    /// accept — a torn read would cost one frame of the same ramp.
    var voicedSeconds: TimeInterval {
        guard lock.try() else { return voiced }
        defer { lock.unlock() }
        return voiced
    }
    private var voiced: TimeInterval = 0

    /// **Where in this recording a moment fell** — seconds from the top of the
    /// WAV, or nil when nothing is being recorded (2026-09-19).
    ///
    /// This is the number the whole timestamp marker rests on, and it is asked
    /// *backwards* on purpose: the caller is a shutter press being filed a beat
    /// after it happened, and what it knows is the `Date` it happened at. Taking
    /// the position now and subtracting the age of the press is exact where
    /// "how long since the recording started" is not — the microphone opens
    /// after the ring goes up, buffers can be dropped, and a marker spliced in
    /// makes the file longer than the clock. All three drift the two apart, and
    /// all three are already in `writtenFrames`.
    ///
    /// - Parameter moment: when the gesture happened, sampled at the gesture.
    /// - Returns: seconds into the file, never negative — a press from before
    ///   the microphone opened belongs at the very beginning, which is where
    ///   `0` puts it.
    func offset(of moment: Date) -> TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard isRecording, file != nil else { return nil }
        let written = Double(writtenFrames) / Self.fileFormat.sampleRate
        // The buffer in flight: audio that has been spoken but not yet written.
        // Clamped, because a stalled input would otherwise let this run away
        // past the end of a file that is not growing.
        let inFlight = lastAppendAt.map { min(Date().timeIntervalSince($0), 0.25) } ?? 0
        let now = written + inFlight
        return max(0, now - Date().timeIntervalSince(moment))
    }

    /// **How loud he is right now, 0…1** — the readout `RecordingBeacon` lights
    /// on, updated on the audio thread with every buffer.
    ///
    /// Deliberately *not* a second meter: it is the same per-hop RMS and the
    /// same adaptive floor `voiced` is counted against, read as a distance
    /// rather than as a yes/no. So the beacon brightens on exactly what the
    /// transcript will call speech — a fan that never clears the bar never
    /// lights it either, on the built-in microphone or on the receiver, which is
    /// the whole reason the floor is tracked instead of fixed.
    ///
    /// **Fast up, slow down**, and that asymmetry is the point: a syllable has
    /// to reach full brightness inside the buffer it arrives in or the light
    /// lags his voice visibly, while a light that drops as fast as it rises
    /// strobes on the gaps *inside* a word.
    ///
    /// **The fall takes three seconds, and it used to take a quarter of one.**
    /// It was 35% of the remaining gap per buffer — a tail chosen so that "the
    /// fade at the end of a sentence reads as him having stopped", which is the
    /// right length for a *readout* and the wrong one for a *beacon*. Victor
    /// reported the consequence on 2026-09-09: *"I find myself speaking a lot to
    /// keep it open"* — the light went out between his sentences, so the thing
    /// that is supposed to say *I am still hearing you* was answering a question
    /// about the last 200ms instead. Three seconds is his number, said twice
    /// (*"about, let's say, two seconds … let's put it even three seconds"*), and
    /// it comfortably outlasts a pause for breath.
    ///
    /// **Linear, not the one-pole it was.** An exponential's last stretch is a
    /// crawl nobody can time, so "three seconds" would have had to mean three
    /// time constants and a footnote; a fixed rate means the light falls from
    /// full to dark in exactly `levelFallSeconds` and from half in half that,
    /// which is the sentence he asked for. It is also what makes the rate
    /// independent of how big a buffer the hardware happens to hand us: the drop
    /// is `dt / levelFallSeconds`, so a device delivering 4096-frame buffers and
    /// one delivering 512 fade at the same speed. The old coefficient was per
    /// *buffer* and therefore silently faster or slower on a different device.
    /// **Never waits for the lock.** `start(to:)` held it (until 2026-09-24) across a synchronous
    /// device open — `AVAudioEngine.inputNode`, `InputDevice.select`,
    /// `installTap`, `engine.start()` — which is tens to hundreds of
    /// milliseconds on a good day and, measured 2026-09-12 on a build with no
    /// microphone grant, **forever**. This getter is called from the halo's
    /// 20 Hz timer on the main thread, so blocking on it freezes the whole app,
    /// ring included, for as long as the open takes: the beacon that exists to
    /// say *I am hearing you* would stop moving precisely because a microphone
    /// was being opened.
    ///
    /// A readout sampled at 20 Hz has nothing to gain from being exactly current
    /// and everything to lose from being late, so a contended read returns the
    /// last value it saw instead. `quietSeconds` is the same bargain for the
    /// same reason.
    var level: Float {
        guard lock.try() else { return live }
        defer { lock.unlock() }
        return live
    }
    private var live: Float = 0

    /// **How long it has been since he last said anything**, in seconds of
    /// audio — the signal `CaretHalo` swells on.
    ///
    /// Deliberately *not* read off `level`. That readout falls linearly over
    /// three seconds by design (see above), so "quiet" measured through it is
    /// "quiet, plus however loud the last syllable happened to be" — the lag
    /// would be two and a half seconds after a shout and nothing after a
    /// murmur. This is the **voiced bar itself**, the same test `voicedSeconds`
    /// counts and the same one the beacon's brightness is spread over: a hop
    /// clears it or it does not, and the clock restarts when one does.
    ///
    /// Counted in audio, not in wall clock, so it cannot run on while the
    /// microphone is closed or while buffers are late.
    var quietSeconds: TimeInterval {
        guard lock.try() else { return quiet }
        defer { lock.unlock() }
        return quiet
    }
    private var quiet: TimeInterval = 0

    /// **The last 128 ms of what the microphone heard**, oldest first, as floats
    /// in −1…1 — the raw material the audio-reactive halo effects
    /// (`HaloEffects.swift`, ported from `voice-halo` at tag `swift-port-01`)
    /// draw their waveforms and spectra from. A boolean and a level cannot
    /// drive a ring that deforms on the *shape* of a syllable, which is what
    /// every one of those effects does; this is the web page's
    /// `getFloatTimeDomainData` in the one place this app already has the
    /// samples in hand.
    ///
    /// Written on the audio thread inside `meter`, after the write and under
    /// the same lock; **read with `lock.try()` like `level`**, for `level`'s
    /// reason — a contended read hands back the previous copy rather than
    /// stalling the main thread behind a device open. Nothing is written to
    /// disk from it and nothing downstream may treat it as the recording.
    var recentSamples: [Float] {
        guard lock.try() else { return recentCopy }
        defer { lock.unlock() }
        var out = [Float](repeating: 0, count: Self.recentCount)
        for i in 0..<Self.recentCount {
            out[i] = recent[(recentHead + i) % Self.recentCount]
        }
        recentCopy = out
        return out
    }
    static let recentCount = 2048

    /// **The whole of this recording, kept in memory as well** (2026-09-23),
    /// for the halo's rewind: while a caret sentence is being transcribed the
    /// ring plays back what he has just said, backwards (`CaretHalo.setRewind`).
    /// Victor: *"pe durata transcrierii … să redai efectul de reverse tunnel pe
    /// baza sunetului la ceea ce ai abia dictat"*. The file is on its own queue
    /// and may be mid-upload, so the halo is handed a copy instead of a path.
    /// Int16, 32 kB a second; only the last `takeCap` seconds are kept, because
    /// a ten-minute monologue replayed at speed is noise either way. Reset at
    /// `start`, so it outlives `stop` — the rewind begins *after* the close.
    ///
    /// **Its own lock, not `lock`.** `lock` was held across a device open and a
    /// teardown — exactly when the settle asks for this, at the close — and a
    /// `try` on it came back empty-handed on the second desk run. `takeLock` is
    /// only ever held for an append or a copy.
    var lastTake: [Int16] {
        takeLock.lock(); defer { takeLock.unlock() }
        return take
    }
    private var take: [Int16] = []
    private let takeLock = NSLock()
    /// Samples trimmed off the front of `take` by the cap — so `take[i]` is
    /// sample `takeDropped + i` of the recording, a ruler that does not move.
    private var takeDropped = 0

    /// **The take on an absolute ruler, for the live caption** (2026-10-05):
    /// samples since the microphone opened (markers excluded — they are not in
    /// `take`). `takeEnd` is how many have been heard; `takeSlice` copies a
    /// stretch of them, clamped to what is still kept.
    var takeEnd: Int {
        takeLock.lock(); defer { takeLock.unlock() }
        return takeDropped + take.count
    }
    func takeSlice(from: Int, to: Int) -> [Int16] {
        takeLock.lock(); defer { takeLock.unlock() }
        let a = max(0, from - takeDropped), b = min(take.count, to - takeDropped)
        return a < b ? Array(take[a..<b]) : []
    }

    /// **The take's meter, hop by hop** (2026-09-27) — pauses and level for
    /// `VoiceAffect`, per sentence. Reset at `start`, kept after `stop` like
    /// `lastTake`, and read at the close on the queue that closed the take (the
    /// next sentence may start while this one uploads, Q12). Its own lock, only
    /// held for an append or a copy; bounded at `hopCap` (~12.8 min), the rest
    /// of a longer take goes unmetered here — the file is untouched either way.
    var meterHops: [MeterHop] {
        hopLock.lock(); defer { hopLock.unlock() }
        return hops
    }
    private var hops: [MeterHop] = []
    private let hopLock = NSLock()
    private static let hopCap = 12_000
    private static let takeCap = 16000 * 120
    private var recent = [Float](repeating: 0, count: MicRecorder.recentCount)
    private var recentHead = 0
    private var recentCopy = [Float](repeating: 0, count: MicRecorder.recentCount)
    /// The dynamic range the light is spread over, in dB above the voiced bar.
    /// 18 dB is ordinary speech's own span at a desk: under it the loud half of
    /// a sentence would sit pinned at full brightness with nothing left to say.
    private static let levelRange: Float = 18
    /// How long the light takes to fall from full brightness to nothing with
    /// nobody talking. See `level` for why it is three seconds and why it is a
    /// duration rather than a per-buffer coefficient.
    private static let levelFallSeconds: Float = 3

    /// The meter's arithmetic — windows, carry, adaptive floor (`VoicedMeter`).
    /// Written only on the audio thread under `lock`, reset at `start`, flushed
    /// in `close()` after the tap is gone.
    private var windows = VoicedMeter()

    /// Asks for the microphone **once, up front**, rather than at the first
    /// press: the grant dialog is modal and takes a few seconds of hunting in
    /// System Settings if it was ever refused, and the moment to discover that is
    /// while picking the engine from a menu — not mid-sentence with an agent
    /// waiting. `granted(false)` is a state the caller shows as a banner and then
    /// leaves alone; macOS only ever asks once.
    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: done(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    /// **The microphone open for a level and nothing else** — no file, no
    /// transcript, no corpus entry.
    ///
    /// It exists for the one dictation this app does not run: Wispr Flow's. The
    /// halo breathes on `level` and `WisprWatch` can only say *the microphone is
    /// open*, not *how loud he is* — a boolean cannot drive a ring that is meant
    /// to move on syllables, and a ring moving on a timer is the substitution the
    /// beacon was killed for. So the relay opens the input alongside Wispr, reads
    /// the meter and throws every sample away.
    ///
    /// **Two apps on one input device is ordinary on macOS** — each client gets
    /// its own tap on the hardware and neither sees the other; Wispr's audio is
    /// not touched, degraded or diverted. The orange dot is already lit by Wispr
    /// itself, so nothing new appears in the menu bar either.
    ///
    /// Nothing is written anywhere: `start(to: nil)` builds the converter and the
    /// tap but no `AVAudioFile`, so there is no path for audio to be kept even by
    /// accident, and `stopMetering` discards instead of handing a recording back.
    @discardableResult
    func startMetering() -> String? { start(to: nil) }

    /// Closes a metering session. Deliberately not `stop()`'s return value: there
    /// is no recording to hand anybody.
    func stopMetering() { _ = stop() }

    /// Opens the microphone and starts writing. Returns the reason on failure.
    ///
    /// The destination is handed in rather than invented here so the caller can
    /// put it where the rest of the per-dictation staging lives, and delete it on
    /// the same path that deletes the others.
    ///
    /// **`nil` means meter only** — see `startMetering`, the only caller that
    /// passes it.
    @discardableResult
    func start(to destination: URL?) -> String? {
        if Self.takeTestHang() {
            Log.error("mic: this open hangs on purpose (POST /test/mic-hang) — it will never return")
            while true { Thread.sleep(forTimeInterval: 3600) }
        }
        lifecycle.lock(); defer { lifecycle.unlock() }
        lock.lock()
        let wasOpen = isRecording, openURL = url
        lock.unlock()
        // **A session already open is not a reason to answer *yes* and record
        // nothing** (2026-09-20). This used to be `guard !isRecording else {
        // return nil }`, and nil here means *the microphone is open* — so a
        // session that outlived its dictation swallowed every sentence after it:
        // the caller logged `recording started`, the halo went up, the file it
        // named was never opened, and the upload of an empty WAV sat there until
        // it timed out. Measured on the live harness the same morning: one
        // cancelled dictation at 10:40:23, and the next two runs produced no
        // `mic: recording through …` line at all and lost their transcripts
        // after 33 s. Nothing anywhere said why — the whole failure was this one
        // silent `nil`.
        //
        // The two cases it was conflating:
        //
        // - **The same request twice** — same destination, nil included. That is
        //   a gesture arriving down two paths and it is genuinely harmless, so it
        //   keeps the old answer.
        // - **A different destination** — a metering session left open by a
        //   `cancel()` whose recogniser had nothing to cancel, or a `stop()` still
        //   tearing the device down on its own queue when the next gesture lands
        //   three seconds later. The open session is the stale one, the caller is
        //   the live one, and the live one must win.
        //
        // Metering is deliberately *not* allowed to pre-empt: `destination == nil`
        // asking over an open recording is a ring wanting a level, and a ring is
        // never worth a sentence. It reads the meter of the recording that is
        // already open, which is what it wanted anyway.
        if wasOpen {
            guard let destination, openURL != destination else { return nil }
            Log.error("mic: a \(openURL == nil ? "metering session" : "recording") was still open when a "
                      + "dictation asked for the microphone — closing it and starting fresh, "
                      + "so \(destination.lastPathComponent) is not written in silence")
            let (orphan, _) = close()
            if let orphan, orphan != destination { try? FileManager.default.removeItem(at: orphan) }
        }

        // The rest of `reopenSpacing` since the last close, so a device just put
        // down is not opened again while its old IO thread may still be leaving
        // (see `close`). Never on main — a ring is not worth a frozen app.
        if let closed = lastClosedAt, !Thread.isMainThread {
            let wait = Self.reopenSpacing - Date().timeIntervalSince(closed)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }

        let input = engine.inputNode
        // Point the engine at a device *before* asking what format it speaks —
        // the answer is the device's, and reading it first would describe the
        // one we are about to leave.
        guard let device = InputDevice.select(on: input) else {
            return "the only microphone left is one Victor never records through (WH-1000XM3)"
        }
        // **`inputFormat`, not `outputFormat` — and this is what a tap is checked
        // against.** They are two different questions and they disagree the
        // moment a device is chosen by hand: `outputFormat(forBus: 0)` is the
        // node's own cached idea of what it will hand downstream and it does
        // *not* refresh when `kAudioOutputUnitProperty_CurrentDevice` is set
        // under it, while `inputFormat(forBus: 0)` is the hardware talking.
        //
        // Measured on Victor's desk with the DJI receiver plugged in: after
        // selecting it, `outputFormat` still said **1ch 44100** (the built-in
        // microphone it had come from) and `inputFormat` said **2ch 48000** (the
        // receiver). `installTap` compares the format it is given against the
        // hardware and throws `Input HW format and tap format not matching` —
        // an **NSException**, which Swift cannot catch, so the app did not fail
        // to record: it aborted, every time, the instant a dictation started.
        //
        // The bug arrived with the receiver (it is only reachable when the
        // chosen device's format differs from the last one's) and it is exactly
        // the class of failure `InputDevice` was written to remove, so the fix
        // belongs here rather than in a guard: ask the hardware what it speaks,
        // and hand that same answer to the tap and to the converter.
        let inFormat = input.inputFormat(forBus: 0)
        // A device that reports zero channels is one that is not really there —
        // a Bluetooth headset mid-handoff, or no input selected at all. Starting
        // the engine on it throws from deep inside CoreAudio.
        guard inFormat.channelCount > 0, inFormat.sampleRate > 0 else {
            return "no input device"
        }
        let outFormat = Self.fileFormat
        guard let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            return "cannot convert \(Int(inFormat.sampleRate))Hz to 16kHz mono"
        }

        var newFile: AVAudioFile?
        if let destination {
            do {
                newFile = try AVAudioFile(forWriting: destination, settings: outFormat.settings,
                                          commonFormat: .pcmFormatInt16, interleaved: true)
            } catch {
                return "cannot write \(destination.lastPathComponent): \(error.localizedDescription)"
            }
        }
        // **One `lock.lock()`, and the session is marked open before the tap
        // goes in** (2026-09-24). `lock` is an `NSLock` and not recursive: when
        // `start` held it from its first line, a second `lock()` around the
        // meter reset below deadlocked the main thread on every dictation
        // (2026-09-07). `start` holds `lifecycle` across the device open now and
        // `lock` only here. `isRecording` goes true *before* `engine.start()` so
        // the first buffer is not turned away at `append`'s guard.
        lock.lock()
        file = newFile
        converter = conv
        outputFormat = outFormat
        url = destination
        startedAt = Date()
        // Per recording, both of them: a floor carried over from the last
        // sentence would be a floor for a room, a microphone and a distance from
        // it that may all have changed since.
        voiced = 0
        takeLock.lock(); take.removeAll(keepingCapacity: true); takeDropped = 0; takeLock.unlock()
        hopLock.lock(); hops.removeAll(keepingCapacity: true); hopLock.unlock()
        quiet = 0
        live = 0
        windows.reset()
        writtenFrames = 0
        lastAppendAt = nil
        health = Health(device: device)
        zeroWatch = ZeroPeakWatch()
        isRecording = true
        lock.unlock()

        // Belt and braces: a second tap on one bus is the other way this call
        // throws, and `removeTap` on a bus with none is a no-op.
        //
        // **Through `WTTry`** (2026-11-25, F4 of the 2026-10-13 audio review, still
        // open until the Fable review found it): a device that changes format
        // between `inputFormat` above and `installTap` here raises `Input HW format
        // and tap format not matching` — an NSException Swift cannot catch, the
        // 2026-09-01 SIGABRT. Now it fails the open, with its reason.
        func unwind() {
            _ = WTTry { input.removeTap(onBus: 0) }
            lock.lock()
            isRecording = false
            let failed = file
            file = nil; converter = nil; outputFormat = nil; url = nil; startedAt = nil
            lock.unlock()
            withExtendedLifetime(failed) {}   // released here, outside the lock
        }
        if let raised = WTTry({
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            engine.prepare()
        }) {
            unwind()
            return "the microphone changed while it was being opened: \(raised.localizedDescription)"
        }
        do { try engine.start() } catch {
            unwind()
            return "microphone unavailable: \(error.localizedDescription)"
        }
        Log.info("mic: \(destination == nil ? "metering" : "recording") through \(device) — \(Int(inFormat.sampleRate))Hz × \(inFormat.channelCount)ch")
        if destination != nil {
            Self.lastOpened = (device, Int(inFormat.sampleRate), Int(inFormat.channelCount), Date())
        }
        watchForSilentEngine()
        return nil
    }

    /// **A (2026-09-28): the tap restarts itself when the device changes under
    /// it.** Another process opening the same input (Wispr Flow's launch is the
    /// suspect: its CoreAudio set-up) can change the device's configuration;
    /// AVAudioEngine then **stops itself** and posts
    /// `AVAudioEngineConfigurationChange` — every buffer after that is simply
    /// never delivered, and the take reads `0.0 s voiced`. Also a watchdog for
    /// the same silence without a notification: no buffer for 1 s.
    ///
    /// **And for buffers that arrive holding nothing** (2026-09-28, wave 3's
    /// finding A): `ZeroPeakWatch` — 1 s of flowing buffers, every sample 0,
    /// before the take's first sound. Step 1 puts the tap back on the running
    /// engine (batch 2's restart — cheap, so a desk clip that starts late loses
    /// a buffer at most); steps 2 and 3 build a **new `AVAudioEngine`** and
    /// re-resolve the device (`InputDevice.select`) — a new HAL client with its
    /// own IO start and IO cycle. Each line carries a readout of the
    /// device (mute, input volume, nominal rate, whether another process runs it),
    /// the next says whether audio came back, and after the third a take still
    /// at peak 0 is said to stay DEAF (→ Recover, batch 2's path).
    private func watchForSilentEngine() {
        observeConfiguration()
        let t = DispatchSource.makeTimerSource(queue: restartQueue)
        let opened = Date()
        t.schedule(deadline: .now() + 1.0, repeating: 0.5)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let recording = self.isRecording
            let last = self.lastAppendAt ?? opened
            let restarts = self.health.restarts
            let zero = recording ? self.zeroWatch.tick(at: Self.clock()) : nil
            self.lock.unlock()
            guard recording else { self.stallTimer?.cancel(); self.stallTimer = nil; return }
            if let zero { self.handle(zero); return }
            let gap = Date().timeIntervalSince(last)
            guard gap >= 1.0, restarts < 5 else { return }
            self.restartTap(why: String(format: "no audio buffer for %.1f s", gap), notesStoppedEngine: true)
        }
        // **`stallTimer` belongs to `restartQueue`** (2026-11-25, F5): its handler
        // writes it there, and this ran on the lane's queue — two queues, one `var`.
        restartQueue.async { [weak self] in
            guard let self else { t.cancel(); return }
            self.stallTimer?.cancel()
            self.stallTimer = t
            t.resume()
        }
    }

    /// The one clock `ZeroPeakWatch` is fed on — monotonic, seconds.
    private static func clock() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// `restartQueue`. What the peak-0 watch said, acted on and said out loud.
    private func handle(_ event: ZeroPeakWatch.Event) {
        switch event {
        case let .restart(step, buffers, seconds):
            var why = String(format: "%d buffers with peak 0 for %.1f s", buffers, seconds)
            if step > 1 { why += " — restart \(step - 1) did not bring audio back" }
            restartTap(why: why, mode: step == 1 ? .tap : .rebuild, step: step, readout: true)
        case let .cameBack(step, peak, after):
            Log.error(String(format: "🔁 mic: audio came back after restart %d — peak %d, %.1f s after it", step, peak, after))
        case let .gaveUp(restarts, buffers, seconds):
            // Read under `lifecycle` and only on a take still open (F5): `close()`
            // replaces `engine` on the lane's queue.
            lifecycle.lock()
            lock.lock(); let recording = isRecording; lock.unlock()
            let readout = recording ? deviceReadout() : "closed"
            lifecycle.unlock()
            Log.error(String(format: "🔁 mic: %d restart(s) did not bring audio back — %d buffers with peak 0 over %.1f s [%@]; the take stays DEAF",
                             restarts, buffers, seconds, readout))
        }
    }

    /// `AVAudioEngineConfigurationChange` on the engine in use — re-registered
    /// when a rebuild replaces it (the old observer named the old engine).
    private func observeConfiguration() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.restartQueue.async { self?.restartTap(why: "the device's configuration changed (AVAudioEngineConfigurationChange)") }
            }
    }

    /// How hard a restart tries. `.tap`: the tap back on the running engine,
    /// the device re-selected (a configuration change, a missing buffer — batch
    /// 2 — and the peak-0 watch's step 1). `.rebuild`: the old engine stopped and
    /// dropped, a new `AVAudioEngine`, the device re-resolved on its fresh input
    /// node (steps 2 and 3).
    enum RestartMode { case tap, rebuild }

    /// Re-reads the device's format and puts the tap back; the WAV (16 kHz mono)
    /// goes on. `restartQueue`; takes `lifecycle`, never `lock` across the engine.
    /// `readout`: append `deviceReadout()`; `notesStoppedEngine`: say so when the
    /// engine had stopped — both read here, under `lifecycle`, not by the caller
    /// (F5 of the 2026-10-13 audio review: `close()` swaps `engine` under it).
    private func restartTap(why: String, mode: RestartMode = .tap, step: Int = 0,
                            readout: Bool = false, notesStoppedEngine: Bool = false) {
        lifecycle.lock(); defer { lifecycle.unlock() }
        lock.lock(); let recording = isRecording; let device = health.device; lock.unlock()
        guard recording else { return }
        var why = why
        if notesStoppedEngine, !engine.isRunning { why += " — the engine had stopped" }
        if readout { why += " [\(deviceReadout())]" }
        var retired: AVAudioEngine?
        switch mode {
        case .tap: break
        case .rebuild:
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            retired = engine
            engine = AVAudioEngine()
            observeConfiguration()
        }
        let input = engine.inputNode
        let chosen = InputDevice.select(on: input) ?? device
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.channelCount > 0, inFormat.sampleRate > 0,
              let conv = AVAudioConverter(from: inFormat, to: Self.fileFormat) else {
            Log.error("🔁 mic: \(why) — and \(chosen) now reports no usable format (\(Int(inFormat.sampleRate)) Hz × \(inFormat.channelCount) ch); the recording stays silent")
            return
        }
        lock.lock()
        converter = conv; health.restarts += 1; health.device = chosen; lastAppendAt = Date()
        zeroWatch.tapRestarted(at: Self.clock())
        lock.unlock()
        withExtendedLifetime(retired) {}   // the old engine goes here, outside the lock
        // **Through `WTTry`** (F4): a restart runs exactly when the format moves,
        // and a second change between `inputFormat` and `installTap` raised an
        // NSException Swift cannot catch — the process aborted mid-dictation.
        if let raised = WTTry({
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                self?.append(buffer)
            }
            engine.prepare()
        }) {
            Log.error("🔁 mic: \(why) — the tap on \(chosen) could not be put back, the device changed again: "
                      + "\(raised.localizedDescription); the recording stays silent")
            return
        }
        let how: String
        switch mode {
        case .tap: how = step > 0 ? "tap restarted (step \(step)) on" : "tap restarted on"
        case .rebuild: how = "tap restarted (step \(step): a new AVAudioEngine, device re-resolved) on"
        }
        do {
            try engine.start()
            Log.error("🔁 mic: \(why) — \(how) \(chosen), \(Int(inFormat.sampleRate)) Hz × \(inFormat.channelCount) ch (was \(device))")
        } catch {
            Log.error("🔁 mic: \(why) — restarting on \(chosen) failed (\(how.replacingOccurrences(of: " on", with: ""))): \(error.localizedDescription)")
        }
    }

    /// **What CoreAudio says about the device the engine is on** — the four
    /// things that turn a flowing stream into zeros from outside this process:
    /// the input muted, its volume at 0, a nominal rate that is no longer the
    /// one the tap was built for, and another process running the device.
    /// Reads only; `restartQueue`, under `lifecycle` (never `lock`).
    private func deviceReadout() -> String {
        guard let unit = engine.inputNode.audioUnit else { return "no audio unit" }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size) == noErr,
              id != 0 else { return "no current device" }
        func read<T>(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope,
                     _ elements: [AudioObjectPropertyElement], _ zero: T) -> T? {
            for element in elements {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
                guard AudioObjectHasProperty(id, &address) else { continue }
                var value = zero
                var sz = UInt32(MemoryLayout<T>.size)
                if AudioObjectGetPropertyData(id, &address, 0, nil, &sz, &value) == noErr { return value }
            }
            return nil
        }
        let main = kAudioObjectPropertyElementMain
        let mute: UInt32? = read(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, [main, 1], 0)
        let volume: Float32? = read(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput, [main, 1], 0)
        let rate: Float64? = read(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, [main], 0)
        let elsewhere: UInt32? = read(kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal, [main], 0)
        let frames: UInt32? = read(kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal, [main], 0)
        let tapRate = Int(engine.inputNode.inputFormat(forBus: 0).sampleRate)
        return [
            "mute " + (mute.map { $0 != 0 ? "ON" : "off" } ?? "n/a"),
            "input volume " + (volume.map { String(format: "%.2f", $0) } ?? "n/a"),
            "nominal " + (rate.map { "\(Int($0)) Hz" } ?? "n/a") + ", tap \(tapRate) Hz",
            "running somewhere " + (elsewhere.map { $0 != 0 ? "yes" : "no" } ?? "n/a"),
            "IO buffer " + (frames.map { "\($0)" } ?? "n/a"),
        ].joined(separator: ", ")
    }

    /// Closes the file and hands back what was recorded, or nil when there was
    /// nothing worth transcribing.
    /// **Splice a buffer into the recording between two of his**, rather than
    /// playing it over him (2026-09-14).
    ///
    /// This is the whole difference between a marker that survives and one that
    /// does not. Played into the Loopback device Wispr listens to, a marker is
    /// **summed** with his voice, and a recogniser handed two voices at once
    /// transcribes the one that makes a sentence — measured, with the marker as
    /// the *louder* of the two. Written into the file here it is not a second
    /// voice at all: his speech stops, the marker is the only thing there, and
    /// his speech resumes. The very first measurement of the idea worked for
    /// exactly this reason — it was a WAV with the markers spliced in.
    ///
    /// It lands at the next input buffer, so within one `bufferSize` of the
    /// press — 4096 frames, under 90 ms at 48 kHz. Nothing of his is lost or
    /// overwritten: the recording simply grows by the marker's length, and
    /// `stop()` adds it to the duration so the number still describes the file.
    ///
    /// The buffer must already be in the recorder's own format (16 kHz mono
    /// int16) — `ShotMarker.pcm(index:in:)` does that conversion once and caches
    /// it, because this is called from a gesture and `AVAudioConverter` is not
    /// something to build under a shutter press.
    ///
    /// - Note: **only for a source that transcribes this file.** The local model
    ///   does; Wispr Flow reads its own microphone and would never hear this, so
    ///   splicing there would put words in the corpus that Wispr's transcript
    ///   does not have. `DictationResult.markersInAudio` is how `deliver` tells
    ///   the two apart.
    func insert(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        // **Said out loud, both ways.** A marker that does not land leaves no
        // trace anywhere else: the file is simply a little shorter and nobody
        // notices until a transcript comes back without it.
        guard isRecording, file != nil, let format = outputFormat else {
            Log.error("mic: a marker arrived with no recording open "
                      + "(recording \(isRecording), file \(file != nil))")
            return
        }
        guard buffer.format.sampleRate == format.sampleRate,
              buffer.format.channelCount == format.channelCount else {
            Log.error("mic: refused a marker in the wrong format")
            return
        }
        pendingInserts.append(buffer)
        inserted += Double(buffer.frameLength) / format.sampleRate
        Log.info("✂️ marker queued into the recording — \(buffer.frameLength) frames")
    }

    /// **Where every buffer also goes, in the order it was produced** — markers
    /// included (2026-09-14).
    ///
    /// It exists so the relay can carry his voice somewhere as well as file it:
    /// `AudioBridge` hands these straight to a player node aimed at the Loopback
    /// device Wispr listens to, which turns a marker written into this stream
    /// into a marker Wispr hears **between** two of his words rather than over
    /// them. Set before `start(to:)`, cleared after `stop()`; read on the audio
    /// thread through the same lock as everything else here, and it must do as
    /// little as `meter` does.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return bufferSink }
        set { lock.lock(); bufferSink = newValue; lock.unlock() }
    }
    private var bufferSink: ((AVAudioPCMBuffer) -> Void)?

    /// Written on the gesture's thread, read on the audio thread — the same
    /// bargain every other field here makes, through the same lock.
    private var pendingInserts: [AVAudioPCMBuffer] = []
    /// How many seconds of this recording are not his, so `stop()` can report a
    /// duration that still matches the file.
    private var inserted: TimeInterval = 0

    /// **How many frames are in the file so far** — his and any spliced in, in
    /// the order they were written (2026-09-19).
    ///
    /// It exists so `offset(of:)` can answer *where in this recording was that
    /// moment*, which is the whole of the timestamp marker: a recogniser hands
    /// back every word with a `start` measured from the top of this file, so a
    /// shutter press addressed the same way lands between two of them without
    /// anything having to be *heard*. → `ShotMarker.place`
    ///
    /// Counted rather than read off `AVAudioFile.length`: the write happens
    /// outside the lock (see `append`), so reading the file's own length from
    /// the gesture's thread would be a race against CoreAudio's.
    private var writtenFrames: AVAudioFramePosition = 0

    /// When the last buffer was written, so `offset(of:)` can correct for the
    /// one that has not arrived yet. Buffers land every 4096 frames — 85 ms at
    /// 48 kHz — and without this the answer is *systematically* that much early
    /// rather than merely imprecise.
    private var lastAppendAt: Date?

    private func takeInserts() -> [AVAudioPCMBuffer] {
        lock.lock(); defer { lock.unlock() }
        guard !pendingInserts.isEmpty else { return [] }
        let taken = pendingInserts
        pendingInserts = []
        return taken
    }

    func stop() -> (url: URL, duration: TimeInterval)? {
        lifecycle.lock(); defer { lifecycle.unlock() }
        lock.lock(); let wasOpen = isRecording; lock.unlock()
        guard wasOpen else { return nil }
        let (out, elapsed) = close()
        guard let out = out else { return nil }
        guard elapsed >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: out)
            return nil
        }
        return (out, elapsed)
    }

    /// **Put the device down and hand back what was on it** — the body `stop()`
    /// and `start(to:)`'s pre-emption share, so the two cannot drift.
    ///
    /// It is one function because closing a recording is a sequence with an
    /// order that matters, and the order is the comment inside it. The caller
    /// decides what the file is *for*: `stop()` measures it against
    /// `minimumDuration` and returns it; the pre-emption deletes it, because a
    /// recording nobody is waiting for is an orphan by definition.
    ///
    /// **The caller holds `lifecycle`, and nobody may hold `lock` here.**
    /// `removeTap` waits for the buffer in flight, and that buffer's `append`
    /// is waiting for `lock` — held across it, the two threads wait on each
    /// other for ever (2026-09-24, see `lock`). So `isRecording` goes false
    /// first, under the lock, which turns every later buffer away at `append`'s
    /// guard; the teardown runs with no lock of ours held; the fields are
    /// cleared under it afterwards.
    private func close() -> (url: URL?, elapsed: TimeInterval) {
        lock.lock(); isRecording = false; lock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // **A stopped engine is never started again** (2026-10-13): the next
        // session gets a fresh AUHAL, and this one is released only after the
        // HAL's IO thread has had time to leave its IOProc. Re-aiming and
        // restarting the same unit ~1 s after a stop, then stopping it again,
        // crashed the app at 18:29:44 — CoreAudio's IO thread called a NULL
        // IOProc while `AudioOutputUnitStop` waited for it (the Wispr feed
        // hand-over: stop → his own sentence → start → ⌃Escape → stop).
        // `AudioBridge` and `restartTap(.rebuild)` already worked this way.
        let retired = engine
        engine = AVAudioEngine()
        lastClosedAt = Date()
        Self.graveyard.asyncAfter(deadline: .now() + Self.reopenSpacing) { withExtendedLifetime(retired) {} }

        lock.lock()
        // `AVAudioFile` finalises the RIFF header when it is released, so the
        // reference has to go before anyone reads the path — a file still held
        // here has a length field of zero and every reader believes it.
        // **Released after the unlock**, not under it: the finalise is disk
        // work, and `insert` / `offset` / the meter's readers would wait on it.
        let closing = file
        file = nil
        converter = nil
        outputFormat = nil
        // **The last partial window, now that no buffer can follow it**
        // (2026-09-27, Q13): the tap is gone, so the carry is final. Before the
        // readers — `voicedSeconds` is read right after `stop()` returns.
        voiced += windows.flush().seconds

        // The wall clock plus whatever was spliced in: the file is longer than
        // the sentence took, and every reader of this number — the corpus row,
        // `DecodeRate` — is describing the file.
        let elapsed = (startedAt.map { Date().timeIntervalSince($0) } ?? 0) + inserted
        health.seconds = elapsed
        lastHealth = health
        let closed = health
        startedAt = nil
        inserted = 0
        pendingInserts = []
        let out = url
        url = nil
        lock.unlock()
        withExtendedLifetime(closing) {}   // the header is written here
        // One line per recording, whatever the engine (2026-09-28): until now
        // only the Wispr path logged `Health`, so a DEAF take on the local model
        // or ElevenLabs said nothing about its device.
        if out != nil {
            Log.info("mic: closed — \(closed.line)\(closed.deaf ? " — DEAF" : "")")
        }
        return (out, elapsed)
    }

    /// Called on CoreAudio's own thread, once per buffer.
    ///
    /// The converter is driven in `.inputBlock` form because the rates differ:
    /// one input buffer is not one output buffer, and the pull API is what lets
    /// the converter say how much it actually produced. Capacity is computed from
    /// the ratio with a buffer to spare, since rounding down here truncates audio
    /// silently rather than failing.
    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        // **`file` is not in the guard** — a metering session has none, and the
        // meter below is the whole point of that session. Everything above the
        // write is shared: the same conversion to 16 kHz mono int16, because the
        // meter's constants were fitted on exactly that.
        guard isRecording, let conv = converter, let outFormat = outputFormat else {
            lock.unlock(); return
        }
        let file = self.file
        let sink = self.bufferSink
        lock.unlock()

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        let status = conv.convert(to: out, error: &error) { _, outStatus in
            // One buffer per call: handing the same one back twice would loop
            // the last 100ms of audio into the file forever.
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else {
            if let error = error { Log.error("mic: conversion failed — \(error.localizedDescription)") }
            return
        }
        // **Taken once, and the order is the product.** The markers go ahead of
        // his buffer — the moment they name is the shutter press, which has
        // already happened — and both destinations below see the same sequence,
        // which is what makes an insertion an insertion rather than two streams
        // that happen to agree.
        let spliced = takeInserts()
        if let file {
            for marker in spliced {
                do { try file.write(from: marker) } catch {
                    Log.error("mic: could not write marker — \(error.localizedDescription)")
                }
            }
            do { try file.write(from: out) } catch {
                Log.error("mic: could not write buffer — \(error.localizedDescription)")
            }
        }
        if let sink {
            for marker in spliced { sink(marker) }
            sink(out)
        }
        // **After the write and before the meter**, which is the order the whole
        // of `append` is in: the file is the product and this is a fact *about*
        // the file, so it may only be advanced by frames that reached it.
        lock.lock()
        writtenFrames += AVAudioFramePosition(out.frameLength)
            + spliced.reduce(0) { $0 + AVAudioFramePosition($1.frameLength) }
        lastAppendAt = Date()
        lock.unlock()
        meter(out)
    }

    /// Adds this buffer's speech to `voiced`. Same thread as `append`, and
    /// deliberately after the write: the file is the product, the meter is a
    /// readout, and a meter that threw would not be allowed to cost a sentence.
    ///
    /// Measured on the converted buffer rather than the input one so it sees the
    /// same 16 kHz mono int16 the model and the corpus see — which is also what
    /// makes `VoicedMeter`'s constants transferable from the corpus replay that
    /// set them (`evals/voiced-seconds.py`).
    private func meter(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.int16ChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        // **Every buffer is metered, whatever its length** (2026-09-27, Q13): the
        // windows run over the stream and carry the remainder into the next
        // call (`VoicedMeter`). The loudest window, not the average: a syllable
        // inside a buffer should light the beacon whole. Any voiced window
        // restarts the quiet clock — per buffer, because a buffer is at most a
        // fifth of a second, far below the two seconds anything downstream
        // cares about.
        lock.lock()
        // Where this buffer starts in the file: `append` advanced `writtenFrames`
        // past it (and past any splice in front of it) just before calling here.
        let base = Double(writtenFrames) - Double(count)
        // A: the device is heard at all — buffers and the loudest sample.
        health.buffers += 1
        // This buffer's own peak, while anyone still needs it: the take's peak
        // until it saturates, and the peak-0 watch until the first sound
        // (a saturated take has been heard, so the second implies the first).
        if health.peak < 32767 || zeroWatch.armed {
            var peak = 0
            for i in 0..<count { let v = Int(samples[i]); peak = max(peak, v < 0 ? -v : v) }
            health.peak = max(health.peak, min(peak, 32767))
            zeroWatch.buffer(at: Self.clock(), peak: peak)
        }
        let fed = windows.feed(UnsafeBufferPointer(start: samples, count: count), at: base)
        voiced += fed.seconds
        hopLock.lock()
        if hops.count < Self.hopCap { hops.append(contentsOf: fed.hops.prefix(Self.hopCap - hops.count)) }
        hopLock.unlock()
        quiet = fed.spoke ? 0 : quiet + Double(count) / 16000
        // Up instantly, down at a fixed rate — measured against the audio's own
        // clock, not against however many buffers the device chose to send.
        let loudest = min(1, max(0, fed.loudestOver / Self.levelRange))
        let dt = Float(count) / 16000
        live = max(loudest, live - dt / Self.levelFallSeconds)
        // The samples themselves, for the halo effects — see `recentSamples`.
        // Under the same lock, on the same thread, after everything the file
        // needed: a readout, never the product.
        for i in 0..<count {
            recent[recentHead] = Float(samples[i]) / 32768
            recentHead = (recentHead + 1) % Self.recentCount
        }
        takeLock.lock()
        take.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        // Trimmed in chunks of a quarter of the cap, so the shift is paid rarely.
        if take.count > Self.takeCap + Self.takeCap / 4 {
            let cut = take.count - Self.takeCap
            take.removeFirst(cut)
            takeDropped += cut
        }
        takeLock.unlock()
        lock.unlock()
    }
}
