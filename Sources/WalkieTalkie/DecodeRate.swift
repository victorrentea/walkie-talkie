import Foundation
import Darwin

/// **How long a transcription takes, fitted to what the last fifty actually
/// cost.**
///
/// The countdown on the chip (`RelayWindow.setTranscribing`) is this estimate,
/// and it is measured on the fly: every decode files the audio it was handed,
/// the seconds it took and how loaded the machine was at the time, and the next
/// prediction is a straight line through that window.
///
/// **It was a mean ratio, and the ratio filter was throwing away the truth.**
/// Reported 2026-09-07: *"secundele estimate … sunt mereu grav supraestimate,
/// 14 secunde și s-a terminat în 3"*. The cause is in `relay.log`, in the lines
/// the old code wrote as it dropped the samples:
///
/// ```
/// decode rate: ignoring 0.033× (45.5s audio, 1.5s decode) — outside 0.04…0.60
/// decode rate: ignoring 0.028× (67.4s audio, 1.9s decode) — outside 0.04…0.60
/// decode rate: ignoring 0.036× (206.7s audio, 7.5s decode) — outside 0.04…0.60
/// ```
///
/// Nineteen such pairs, spanning 22s to 207s of audio, all of them warm, all of
/// them **rejected for being too fast** — the floor was 0.04× and this machine
/// decodes at 0.033×. What was left in the window were the short clips and the
/// odd cold decode, whose ratios run 0.05…0.48, so the mean sat near 0.15 and a
/// two-minute dictation was promised twenty seconds for work that takes four.
/// The filter written to keep nonsense out was keeping every representative
/// sample out and nothing else in.
///
/// **A line, not a ratio**, because the two regimes are different: a decode is a
/// fixed round trip (the JSON out, ffmpeg, the answer back) plus a cost per
/// second of audio, and a single ratio can fit one of those or the other. Least
/// squares over those same nineteen pairs gives `0.0355 × audio − 0.10` with a
/// worst residual of **0.39s across the whole range** — the countdown is
/// essentially exact once the line is allowed to have an intercept, and a mean
/// ratio cannot express one.
///
/// **The load is recorded and deliberately not in the model.** Victor asked for
/// it — *"loghează … câtă încărcare are mașina și cât a durat efectiv"* — and
/// that is what it is for: it rides in the file so a later rule can be derived
/// from real numbers rather than guessed at. The fit does not use it because
/// the recent decodes already *are* the machine's current load, measured end to
/// end on the resource that matters; a second term fitted to a number nobody has
/// checked against would be a worse estimate that looked cleverer.
enum DecodeRate {

    /// What a decode costs before there is anything to learn from — the line the
    /// nineteen measured pairs above give, rounded up a little on both terms.
    /// Rounded **up** because a first estimate that is slightly long is a
    /// pleasant surprise and one that is short is wrong every second it shows.
    static let fallbackSlope = 0.045
    static let fallbackIntercept = 0.3

    /// How many decodes the estimate is drawn from.
    private static let window = 50

    /// Below this the line is not fitted at all: a fit needs points, and three
    /// decodes are three coin flips.
    private static let minimumSamples = 8

    /// A fit also needs the points to be *spread*. Fifty dictations that were
    /// all about twenty seconds long say nothing about the slope, and least
    /// squares asked anyway answers with a line through noise. Below this many
    /// seconds between the shortest and longest sample, the window is used as a
    /// plain median ratio instead.
    private static let minimumSpread = 15.0

    /// The bounds a *sample* is allowed to have, as a ratio of audio. Wide
    /// on purpose now: the old 0.04…0.60 excluded this machine's real answer.
    /// What is left out is only the genuinely uninformative — a reply that came
    /// back in no time at all (a race, a failure), and one that took longer than
    /// the sentence did to say, which on this model means something other than
    /// decoding was happening.
    private static let bounds = 0.005...1.0

    /// The slope and intercept a *fit* is allowed to produce. A line is fitted
    /// to real points and can still come out absurd when they are clustered;
    /// these are the same guard the ratio bounds were, one level up.
    private static let slopeBounds = 0.005...0.60
    private static let interceptBounds = 0.0...5.0

    /// Which decode this is since the helper came up. The **first is skipped**:
    /// `whisper_helper.py` warms up on a second of silence, but the first real
    /// decode still pays for weights the allocator has not touched yet —
    /// measured at 2.8s against 1.3s warm, and visible in the log as the 4.3s
    /// clip that took 7.3s. It is still *recorded*, marked cold, because it is a
    /// real fact about this app's first sentence after a launch; it is simply
    /// not fitted to.
    private static var decodesThisRun = 0

    private static let lock = NSLock()
    private static var samples: [Sample] = load()

    /// One decode, as it goes on disk. `load` is the 1-minute run queue at the
    /// moment the answer came back.
    struct Sample: Codable {
        let at: String
        let audio: Double
        let decode: Double
        let load: Double
        let cold: Bool
    }

    /// **Every sample, appended forever, one JSON object per line.** The window
    /// the estimate uses is the tail of this file; the rest of it is the record
    /// Victor asked for, which is what makes a better rule derivable later
    /// rather than guessable now. One line per dictation is a few kilobytes a
    /// day, and it sits beside the outbox for the outbox's reason: a log the
    /// system may purge under disk pressure is not a log.
    ///
    /// It supersedes `decode-rate.json`, which held bare ratios with no audio
    /// beside them — which is precisely why the fault above could only be
    /// diagnosed from `relay.log`, and only from the lines about the samples
    /// that were *discarded*.
    private static var fileURL: URL {
        Outbox.home.appendingPathComponent("decode-rate.jsonl")
    }

    /// How long the next decode of `audio` seconds is expected to take. Read
    /// once per dictation, at the moment the row opens.
    static func seconds(for audio: TimeInterval) -> TimeInterval {
        lock.lock()
        let usable = samples.filter { !$0.cold }
        lock.unlock()

        let (a, b) = model(usable)
        return max(0.5, a + b * audio)
    }

    /// The line the window gives: least squares when there are enough points
    /// spread over enough audio, the median ratio through the origin when there
    /// are not, and the measured constants when there is nothing at all.
    ///
    /// The median rather than the mean for the middle case: it is the same
    /// window that used to be averaged, and a single cold or raced decode moves
    /// a mean of ten by a third and a median of ten not at all.
    private static func model(_ window: [Sample]) -> (Double, Double) {
        guard window.count >= minimumSamples else {
            guard !window.isEmpty else { return (fallbackIntercept, fallbackSlope) }
            let ratios = window.map { $0.decode / $0.audio }.sorted()
            return (0, ratios[ratios.count / 2])
        }
        let spread = (window.map { $0.audio }.max() ?? 0) - (window.map { $0.audio }.min() ?? 0)
        guard spread >= minimumSpread else {
            let ratios = window.map { $0.decode / $0.audio }.sorted()
            return (0, ratios[ratios.count / 2])
        }
        let n = Double(window.count)
        let meanX = window.reduce(0) { $0 + $1.audio } / n
        let meanY = window.reduce(0) { $0 + $1.decode } / n
        let sxx = window.reduce(0) { $0 + ($1.audio - meanX) * ($1.audio - meanX) }
        guard sxx > 0 else { return (fallbackIntercept, fallbackSlope) }
        let sxy = window.reduce(0) { $0 + ($1.audio - meanX) * ($1.decode - meanY) }
        let slope = min(slopeBounds.upperBound, max(slopeBounds.lowerBound, sxy / sxx))
        // Clamped at zero from below: a negative intercept is what a fit with no
        // short clips in it produces (the measured one is −0.10s), and it is
        // honest about the long end while promising a 2s clip less than nothing.
        let intercept = min(interceptBounds.upperBound, max(interceptBounds.lowerBound, meanY - slope * meanX))
        return (intercept, slope)
    }

    /// File what a decode actually cost. `audio` and `decode` are both seconds.
    ///
    /// Nonsense is dropped rather than clamped: a ratio outside `bounds` is
    /// evidence about something other than the model's speed — a decode that
    /// raced a sleep, a clip so short the JSON round-trip dominates it — and
    /// letting it in would move the estimate for fifty dictations afterwards.
    /// **It is still written to the file**, marked, because "the answer came
    /// back in 40ms" is a fact worth having when the next fault is diagnosed
    /// from this file rather than from the log.
    static func record(audio: TimeInterval, decode: TimeInterval) {
        guard audio > 0, decode > 0 else { return }
        lock.lock()
        decodesThisRun += 1
        let cold = decodesThisRun == 1
        lock.unlock()

        let ratio = decode / audio
        let usable = bounds.contains(ratio) && !cold
        let sample = Sample(at: ISO8601DateFormatter().string(from: Date()),
                            audio: audio, decode: decode, load: machineLoad(),
                            cold: !usable)
        append(sample)

        lock.lock()
        samples.append(sample)
        if samples.count > window * 2 { samples.removeFirst(samples.count - window * 2) }
        let kept = samples.filter { !$0.cold }.suffix(window)
        samples = Array(samples.suffix(window * 2))
        lock.unlock()

        let (a, b) = model(Array(kept))
        Log.info(String(format: "decode rate: %.1fs audio → %.1fs decode (%.3f×, load %.2f)%@ — %d samples, estimating %.2fs + %.3f×",
                        audio, decode, ratio, sample.load,
                        usable ? "" : (cold ? " — cold, not fitted" : " — outside \(bounds), not fitted"),
                        kept.count, a, b))
    }

    /// The helper went away; the next decode is cold again.
    static func engineStopped() {
        lock.lock(); decodesThisRun = 0; lock.unlock()
    }

    /// The 1-minute run queue — what `uptime` prints. Not normalised by core
    /// count on purpose: it is being recorded for a human to read beside the
    /// seconds, and this is the number that machine reports about itself.
    private static func machineLoad() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return 0 }
        return loads[0]
    }

    // MARK: - On disk

    /// **Kept across launches.** The window is fifty dictations and Victor
    /// restarts this app several times a day, so an in-memory window would spend
    /// most of its life below `minimumSamples` and the learning would never
    /// take.
    ///
    /// Only the tail is parsed: the file grows forever by design, and the
    /// estimate has never wanted more than the last few dozen lines. A line that
    /// will not parse is skipped rather than thrown — this file is appended to
    /// by a live process and one truncated tail line is not a reason to forget
    /// what the machine costs.
    private static func load() -> [Sample] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        let lines = text.split(separator: "\n").suffix(window * 4)
        return lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(Sample.self, from: data)
        }.suffix(window * 2).map { $0 }
    }

    private static func append(_ sample: Sample) {
        guard let data = try? JSONEncoder().encode(sample) else { return }
        var line = data
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: Outbox.home, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL, options: .atomic)
        }
    }
}
