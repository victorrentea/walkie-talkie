import AVFoundation
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
final class MicRecorder {

    /// Shorter than this and it was a misfire — a click he did not mean, or a
    /// button pressed and released while deciding. Sending an empty transcript
    /// costs an agent turn; dropping half a second of silence costs nothing.
    static let minimumDuration: TimeInterval = 0.35

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var startedAt: Date?
    private var url: URL?
    private let lock = NSLock()

    private(set) var isRecording = false

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
    /// Read from the main thread while the ramp ticks, written from CoreAudio's
    /// thread; `Double` is not atomic on any platform this ships to, so it goes
    /// through the same `lock` the rest of the state does. Fifteen reads a
    /// second against a lock held for one addition is not a contention anybody
    /// will measure.
    var voicedSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return voiced
    }
    private var voiced: TimeInterval = 0

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
    var level: Float {
        lock.lock(); defer { lock.unlock() }
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
        lock.lock(); defer { lock.unlock() }
        return quiet
    }
    private var quiet: TimeInterval = 0
    /// The dynamic range the light is spread over, in dB above the voiced bar.
    /// 18 dB is ordinary speech's own span at a desk: under it the loud half of
    /// a sentence would sit pinned at full brightness with nothing left to say.
    private static let levelRange: Float = 18
    /// How long the light takes to fall from full brightness to nothing with
    /// nobody talking. See `level` for why it is three seconds and why it is a
    /// duration rather than a per-buffer coefficient.
    private static let levelFallSeconds: Float = 3

    /// The noise floor this recording is being judged against, tracked rather
    /// than fixed.
    ///
    /// A fixed threshold cannot work here and the reason is already written down
    /// in `InputDevice`: measured on the same room, the DJI receiver peaks at
    /// 16552 where the built-in microphone manages 855. One number would call
    /// the built-in silent all day or the receiver's room tone speech.
    ///
    /// So: instant attack downwards, slow release upwards — the floor drops to
    /// any quiet buffer at once and climbs back at 2% a buffer, which is the
    /// standard cheap noise tracker and is what makes it settle into the gaps
    /// between his words rather than into his words. Seeded on the first buffer,
    /// which is the one place a recording is guaranteed not to have started
    /// mid-syllable.
    private var noiseFloor: Float = -1
    /// How far over the floor a buffer has to sit to count as speech. 9 dB is
    /// wide enough that room tone, a fan and the receiver's hiss never reach it,
    /// and narrow enough to catch the tail of a quiet word.
    private static let voicedOverFloor: Float = 9
    /// And an absolute floor under that, for the case the adaptive one cannot
    /// see: a recording that is *entirely* room tone has a noise floor equal to
    /// its own content, and every buffer would clear a purely relative bar.
    private static let voicedAbsoluteFloor: Float = 180
    /// The window the meter runs on, in frames of the 16 kHz output — 64ms.
    /// Fixed rather than "one converted buffer", because a buffer's length
    /// depends on the input device's rate and the constants above were
    /// calibrated at this hop over the whole corpus.
    private static let voicedHop = 1024

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

    /// Opens the microphone and starts writing. Returns the reason on failure.
    ///
    /// The destination is handed in rather than invented here so the caller can
    /// put it where the rest of the per-dictation staging lives, and delete it on
    /// the same path that deletes the others.
    @discardableResult
    func start(to destination: URL) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !isRecording else { return nil }

        let input = engine.inputNode
        // Point the engine at a device *before* asking what format it speaks —
        // the answer is the device's, and reading it first would describe the
        // one we are about to leave.
        let device = InputDevice.select(on: input)
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
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: 16000, channels: 1, interleaved: true),
              let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            return "cannot convert \(Int(inFormat.sampleRate))Hz to 16kHz mono"
        }

        do {
            file = try AVAudioFile(forWriting: destination, settings: outFormat.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            return "cannot write \(destination.lastPathComponent): \(error.localizedDescription)"
        }
        converter = conv
        outputFormat = outFormat
        url = destination

        // Belt and braces: a second tap on one bus is the other way this call
        // throws, and `removeTap` on a bus with none is a no-op.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            file = nil
            return "microphone unavailable: \(error.localizedDescription)"
        }

        startedAt = Date()
        // Per recording, both of them: a floor carried over from the last
        // sentence would be a floor for a room, a microphone and a distance from
        // it that may all have changed since.
        //
        // **No `lock.lock()` around this pair.** It is the one place in the file
        // where that reflex is wrong: `start` has held the lock since its first
        // line, `lock` is an `NSLock` and NSLock is not recursive, so taking it
        // again here deadlocked the thread that opened the microphone — the main
        // thread — and froze the whole app on every dictation. Shipped in the
        // commit that added the meter and found on the forward button the same
        // afternoon (2026-09-07); the button was innocent.
        voiced = 0
        quiet = 0
        live = 0
        noiseFloor = -1
        isRecording = true
        Log.info("mic: recording through \(device) — \(Int(inFormat.sampleRate))Hz × \(inFormat.channelCount)ch")
        return nil
    }

    /// Closes the file and hands back what was recorded, or nil when there was
    /// nothing worth transcribing.
    func stop() -> (url: URL, duration: TimeInterval)? {
        lock.lock(); defer { lock.unlock() }
        guard isRecording else { return nil }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // `AVAudioFile` finalises the RIFF header when it is released, so the
        // reference has to go before anyone reads the path — a file still held
        // here has a length field of zero and every reader believes it.
        file = nil
        converter = nil
        outputFormat = nil

        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        guard let out = url else { return nil }
        url = nil
        guard elapsed >= Self.minimumDuration else {
            try? FileManager.default.removeItem(at: out)
            return nil
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
        guard isRecording, let conv = converter, let outFormat = outputFormat, let file = file else {
            lock.unlock(); return
        }
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
        do { try file.write(from: out) } catch {
            Log.error("mic: could not write buffer — \(error.localizedDescription)")
        }
        meter(out)
    }

    /// Adds this buffer's speech to `voiced`. Same thread as `append`, and
    /// deliberately after the write: the file is the product, the meter is a
    /// readout, and a meter that threw would not be allowed to cost a sentence.
    ///
    /// Measured on the converted buffer rather than the input one so it sees the
    /// same 16 kHz mono int16 the model and the corpus see — which is also what
    /// makes the constants above transferable from the corpus replay that set
    /// them (`evals/voiced-seconds.py`).
    private func meter(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.int16ChannelData?[0] else { return }
        let hop = Self.voicedHop
        let count = Int(buffer.frameLength)
        guard count >= hop else { return }

        var seconds: TimeInterval = 0
        // The buffer's loudest hop, not its average: a buffer is a fifth of a
        // second at most and a syllable inside it should light the beacon whole.
        var loudest: Float = 0
        // Any voiced hop anywhere in this buffer restarts the quiet clock. Per
        // buffer rather than per hop because the whole buffer is at most a fifth
        // of a second, which is far below the two seconds anything downstream
        // cares about.
        var spoke = false
        lock.lock()
        var floor = noiseFloor
        for start in stride(from: 0, through: count - hop, by: hop) {
            var sum: Float = 0
            for i in start..<(start + hop) {
                let s = Float(samples[i])
                sum += s * s
            }
            let rms = (sum / Float(hop)).squareRoot() + 1e-6
            if floor < 0 || rms < floor { floor = rms }        // instant attack
            else { floor += (rms - floor) * 0.02 }             // slow release
            let bar = max(Self.voicedAbsoluteFloor, floor * pow(10, Self.voicedOverFloor / 20))
            if rms > bar { seconds += Double(hop) / 16000; spoke = true }
            let over = 20 * log10(rms / bar)
            loudest = max(loudest, min(1, max(0, over / Self.levelRange)))
        }
        noiseFloor = floor
        voiced += seconds
        quiet = spoke ? 0 : quiet + Double(count) / 16000
        // Up instantly, down at a fixed rate — measured against the audio's own
        // clock, not against however many buffers the device chose to send.
        let dt = Float(count) / 16000
        live = max(loudest, live - dt / Self.levelFallSeconds)
        lock.unlock()
    }
}
