import AVFoundation

/// The relay's own microphone, used only when Local Whisper is the engine.
///
/// ## Why this exists at all, after arguing it should not
///
/// `VoiceCorpus` and `Transcriber` both say, at length, that the local engine
/// transcribes **Wispr's** recording — that a second capture would be a different
/// signal from the one Wispr scored, and a comparison between two models that
/// heard different audio measures nothing. That argument is still correct, and it
/// is still why the *corpus* is collected from `History.audio` whenever Wispr is
/// the one recording.
///
/// What changed is the goal. As long as Wispr held the microphone, every local
/// dictation still went through Wispr's push-to-talk, its recording, and — the
/// part Victor actually wanted gone — its paste into whatever had the caret. The
/// local engine was a second opinion on Wispr's audio; it is now allowed to be
/// the whole path, and a path that owns its own microphone is the only kind that
/// can leave Wispr out of the loop entirely.
///
/// The two modes therefore hear different signals *by design*, and nothing in the
/// corpus mixes them: a sample recorded here is stamped `engine: "whisper-local"`
/// so a later evaluation can keep the like-for-like rows apart from these.
///
/// ## 16 kHz mono 16-bit, because that is what the other half already speaks
///
/// Whisper resamples to 16 kHz internally and `History.audio` is 16 kHz mono
/// PCM, so writing anything richer would only be thrown away twice — once by the
/// model and once by a corpus whose every existing sample is that format. The
/// input device is whatever the system has selected and is read at its native
/// rate; `AVAudioConverter` does the resampling on the audio thread's buffers.
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
        let inFormat = input.outputFormat(forBus: 0)
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
        isRecording = true
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
    }
}
