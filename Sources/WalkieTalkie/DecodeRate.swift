import Foundation

/// **How long a transcription takes, learned from the last twenty.**
///
/// The countdown on the chip (`RelayWindow.setTranscribing`) is the audio's own
/// length times a factor, and that factor was the constant `0.12` — 0.105×
/// realtime measured over 442 dictations, rounded up because over is a pleasant
/// surprise and under is a number that is wrong every second it is on screen.
///
/// A constant measured once is right until something moves under it, and three
/// things do: the model can be swapped (`RELAY_WHISPER_MODEL`), the Mac can be
/// doing something else at the time, and thermal throttling makes the same
/// machine two machines. None of those announce themselves, and all of them show
/// up as a countdown that is quietly wrong for weeks.
///
/// So the factor is measured **on the fly**: every decode files what it actually
/// cost against the audio it was given, and the estimate for the next one comes
/// off that window. Small enough (20) to follow a change within one sitting,
/// large enough that a single slow decode does not move it far.
///
/// **It is still an estimate that runs out rather than one that stalls**, which
/// is why the window is read at a *high* percentile and not at its median. The
/// old constant was the median with 14% added on top for the same reason; here
/// the padding is measured rather than guessed — the 80th percentile of the last
/// twenty ratios is the number four decodes in five come in under.
enum DecodeRate {

    /// What the estimate falls back to before there is anything to learn from —
    /// the constant this replaced, and the number in `CLAUDE.md`.
    static let fallback = 0.12

    /// How many decodes the estimate is drawn from.
    private static let window = 20

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
        let sorted = samples.sorted()
        // The 80th percentile, by nearest rank: with 20 samples that is the 16th,
        // i.e. the value four decodes in five land under.
        let rank = Int((0.8 * Double(sorted.count)).rounded(.up))
        let p80 = sorted[min(sorted.count - 1, max(0, rank - 1))]
        return min(bounds.upperBound, max(bounds.lowerBound, p80))
    }

    /// File what a decode actually cost. `audio` and `decode` are both seconds.
    ///
    /// Nonsense is dropped rather than clamped: a ratio outside the bounds is
    /// evidence about something other than the model's speed — a decode that
    /// raced a sleep, a clip so short the JSON round-trip dominates it — and
    /// letting it in would move the estimate for twenty dictations afterwards.
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
    /// is twenty dictations and Victor restarts this app several times a day, so
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
