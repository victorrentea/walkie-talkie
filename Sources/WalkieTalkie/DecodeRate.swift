import Foundation

/// **How long a transcription takes, learned from the last fifty.**
///
/// The countdown on the chip (`RelayWindow.setTranscribing`) is the audio's own
/// length times a factor, and that factor is measured **on the fly**: every
/// decode files what it actually cost against the audio it was given, and the
/// estimate for the next one comes off that window.
///
/// **The estimate is the mean, since 2026-09-04.** It was the 80th percentile
/// of the last twenty before — deliberately high, on the argument that over is
/// a pleasant surprise and under is a number that is wrong every second it is
/// on screen. Measured against reality that argument failed: the window's p80
/// sat at 0.225× while the decodes actually landing came in at 0.09–0.11×, so a
/// sentence was promised 33s and arrived in 3 — and a countdown that is wrong
/// by a whole order of magnitude in the "safe" direction is still wrong every
/// second it is on screen. Victor's call: *"average over the last let's say
/// 50 transcriptions"*.
///
/// The mean of fifty is what a bigger window buys: a single slow decode — a
/// sleep raced, a thermal spike — moves the estimate by its own ÷50 instead of
/// sitting at the 16th rank of twenty for a whole afternoon. GPU load is not
/// sampled separately: the ratio of the *most recent* decodes already is the
/// load on whatever resource the model uses, measured end to end.
///
/// A constant measured once is right until something moves under it, and three
/// things do: the model can be swapped (`RELAY_WHISPER_MODEL`), the Mac can be
/// doing something else at the time, and thermal throttling makes the same
/// machine two machines. None of those announce themselves; a fifty-deep window
/// still follows a real change within a day of dictating.
enum DecodeRate {

    /// What the estimate falls back to before there is anything to learn from —
    /// the constant this replaced, and the number in `CLAUDE.md`.
    static let fallback = 0.12

    /// How many decodes the estimate is drawn from.
    private static let window = 50

    /// Below this many samples the measured factor is not trusted at all: three
    /// decodes are three coin flips, and the fallback is a number that came off
    /// 442 of them.
    private static let minimumSamples = 5

    /// The bounds a learned factor is clamped into. A model that answered in
    /// nothing and one that took three times the audio are both real readings and
    /// neither is a countdown worth showing — the first promises instant, the
    /// second parks a minute-long number beside the cursor.
    private static let bounds = 0.04...0.60

    /// Which decode this is since the helper came up. The **first is skipped**:
    /// `whisper_helper.py` warms up on a second of silence, but the first real
    /// decode still pays for weights the allocator has not touched yet — measured
    /// at 2.8s against 1.3s warm — and one cold sample in a window of twenty
    /// drags every estimate after it.
    private static var decodesThisRun = 0

    private static let lock = NSLock()
    private static var samples: [Double] = load()

    private static var fileURL: URL {
        Outbox.home.appendingPathComponent("decode-rate.json")
    }

    /// The factor to multiply the audio's duration by. Read once per dictation,
    /// at the moment the row opens.
    static var factor: Double {
        lock.lock(); defer { lock.unlock() }
        guard samples.count >= minimumSamples else { return fallback }
        // The mean — see the type's doc for why the 80th percentile was given
        // up: it promised 33s for decodes that landed in 3.
        let mean = samples.reduce(0, +) / Double(samples.count)
        return min(bounds.upperBound, max(bounds.lowerBound, mean))
    }

    /// File what a decode actually cost. `audio` and `decode` are both seconds.
    ///
    /// Nonsense is dropped rather than clamped: a ratio outside the bounds is
    /// evidence about something other than the model's speed — a decode that
    /// raced a sleep, a clip so short the JSON round-trip dominates it — and
    /// letting it in would move the estimate for fifty dictations afterwards.
    static func record(audio: TimeInterval, decode: TimeInterval) {
        guard audio > 0, decode > 0 else { return }
        lock.lock()
        decodesThisRun += 1
        let cold = decodesThisRun == 1
        lock.unlock()

        let ratio = decode / audio
        guard bounds.contains(ratio) else {
            Log.info(String(format: "decode rate: ignoring %.3f× (%.1fs audio, %.1fs decode) — outside %.2f…%.2f",
                            ratio, audio, decode, bounds.lowerBound, bounds.upperBound))
            return
        }
        guard !cold else {
            Log.info(String(format: "decode rate: first decode of this helper — %.3f×, not filed", ratio))
            return
        }

        lock.lock()
        samples.append(ratio)
        if samples.count > window { samples.removeFirst(samples.count - window) }
        let kept = samples
        lock.unlock()

        save(kept)
        Log.info(String(format: "decode rate: %.3f× filed — %d samples, estimating %.3f×",
                        ratio, kept.count, factor))
    }

    /// The helper went away; the next decode is cold again.
    static func engineStopped() {
        lock.lock(); decodesThisRun = 0; lock.unlock()
    }

    // MARK: - On disk

    /// **Kept across launches, beside the outbox and not in Caches.** The window
    /// is fifty dictations and Victor restarts this app several times a day, so
    /// an in-memory window would spend most of its life below `minimumSamples`
    /// and the learning would never take.
    private static func load() -> [Double] {
        guard let data = try? Data(contentsOf: fileURL),
              let read = try? JSONDecoder().decode([Double].self, from: data)
        else { return [] }
        return Array(read.filter { bounds.contains($0) }.suffix(window))
    }

    private static func save(_ values: [Double]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
