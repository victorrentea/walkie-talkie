import Foundation
import Darwin

/// **How long a transcription takes, fitted to what the last fifty actually
/// cost.**
///
/// The countdown on the chip (`RelayWindow.setTranscribing`) is this estimate,
/// and it is measured on the fly: every decode files the audio it was handed,
/// the seconds it took and how loaded the machine was at the time, and the next
/// prediction is a line through that window with a measured amount of headroom
/// on top of it.
///
/// **It was a mean ratio, and the ratio filter was throwing away the truth.**
/// Reported 2026-09-07: *"secundele estimate … sunt mereu grav supraestimate,
/// 14 secunde și s-a terminat în 3"*. The floor was 0.04× and this machine
/// decodes at 0.033×, so nineteen representative pairs were rejected for being
/// too fast and the mean was left sitting on the short clips and the odd cold
/// decode. That is what the line below replaced, and the bounds have been wide
/// ever since.
///
/// **A line, not a ratio**, because the two regimes are different: a decode is a
/// fixed round trip (the JSON out, ffmpeg, the answer back) plus a cost per
/// second of audio, and a single ratio can fit one of those or the other.
///
/// ## The estimate is a quantile now, not a best guess (2026-09-16)
///
/// Reported the same way from the other side: *"estimările de timp cât durează
/// transcrierea sunt subestimate"*. Replayed over the **640 decodes in
/// `decode-rate.jsonl`**, the old line was not biased — median estimate/actual
/// **1.10** — and was still short of the truth on **40%** of dictations, because
/// what it fitted was the *middle* of a distribution whose spread is a factor of
/// 1.8 either way. A bar that fills to the end and then sits there is the app
/// claiming the words have landed; being right on average buys nothing, because
/// the half of the time it is short is the half he notices.
///
/// So the fit answers *how long will this take at worst, ordinarily* rather than
/// *how long will this take*: the line is multiplied by `headroom`, the 0.80
/// quantile of its own residual ratios over the same window. Replayed over the
/// same 640 decodes, against the old line:
///
/// ```
///                            covered   short clips   bar-full-early   bar-unfinished
/// least squares, mean          60%         52%           0.65s            0.45s
/// Theil–Sen × q0.80            74%         65%           0.55s            0.63s
/// ```
///
/// — where *covered* is the fraction of dictations whose words arrived before
/// the bar filled. It buys 14 points of that for 0.2s of average unfinished bar,
/// which is the trade the complaint asks for and the one the 09-07 complaint
/// asks not to overpay for: the median estimate moves 1.10 → **1.27**, nowhere
/// near the 4× that produced *"14 secunde și s-a terminat în 3"*.
///
/// **And the line is a median of slopes, not least squares.** A repetition loop
/// (see `bounds`) or a decode that hit a thermal wall lands in the window as one
/// point ten times the size of the others, and least squares hands it the fit
/// for the next fifty dictations. Theil–Sen — the median of the slopes of every
/// pair, intercept the median of the residuals — cannot see it. Measured over
/// the same replay it is the same coverage for **0.11s less** unfinished bar,
/// and 3 points better on the short clips, which is where the old fit was
/// weakest.
///
/// **The load is recorded and still deliberately not in the model**, and that
/// survived being asked again with real numbers rather than reasoning
/// (2026-09-16). It is a real effect — the median ratio runs **0.034×** with the
/// run queue under 2 and **0.085×** over 35 — and it is nonetheless already in
/// the window, because the last fifty decodes happened on the same machine in
/// the same hours. Against the residuals of the fitted line the correlation is
/// **0.13** with the load relative to the window's and **0.02** with the load
/// itself, and every form it was tried in — a `1 + c·ln(1+load)` term on the
/// slope, a second regressor fitted from the window, the whole fit in log space,
/// the twenty nearest samples in load — bought 1–3 points of coverage and paid
/// for them one for one in unfinished bar. A term that fits noise on fifty
/// points is a worse estimate that looks cleverer. The number stays in the file,
/// where a rule with more than fifty points behind it can still be derived.
///
/// **What is left over cannot be predicted from the length and the load, and it
/// is most of the remaining error** (2026-09-16). Pairing `decode-rate.jsonl`
/// against the `local whisper: … (cr N)` lines in `relay.log` — 577 decodes —
/// the strongest signal in the data is not the audio (log-log correlation 0.42)
/// nor the load (0.03) but the **compression ratio of the transcript**, 0.49,
/// and 0.52 against the residual of the line. The worst under-predictions are
/// all the same animal: 29.8s of audio decoded in 20.4s at `cr 56.8`, 10.2s in
/// 9.4s at `cr 51.5`, 4.1s in 9.6s at `cr 37.1` — Whisper caught in a repetition
/// loop, generating hundreds of tokens nobody said. An ordinary sentence is
/// `cr 1.3…1.5`. None of that is knowable when the row opens, so ~4% of decodes
/// will overrun any estimate this file can make by more than five seconds. The
/// ratio is filed beside the seconds now, so the next person to ask can tell a
/// slow machine from a Whisper talking to itself.
enum DecodeRate {

    /// What a decode costs before there is anything to learn from — the line the
    /// nineteen measured pairs of 2026-09-07 give, rounded up a little on both
    /// terms. Rounded **up** because a first estimate that is slightly long is a
    /// pleasant surprise and one that is short is wrong every second it shows.
    static let fallbackSlope = 0.045
    static let fallbackIntercept = 0.3

    /// How many decodes the estimate is drawn from.
    private static let window = 50

    /// Below this the line is not fitted at all: a fit needs points, and three
    /// decodes are three coin flips.
    private static let minimumSamples = 8

    /// Two samples this close together in audio say nothing about the slope —
    /// their ratio is the difference of two round trips divided by nothing — so
    /// the pair is left out of the median. With **no** usable pair left the
    /// window becomes a plain quantile ratio through the origin, which is what
    /// `minimumSpread` used to say one level up and says here without a second
    /// constant to keep in step.
    private static let minimumGap = 1.0

    /// The bounds a *sample* is allowed to have, as a ratio of audio. Wide on
    /// purpose: the old 0.04…0.60 excluded this machine's real answer. What is
    /// left out is only the genuinely uninformative — a reply that came back in
    /// no time at all (a race, a failure), and one that took longer than the
    /// sentence did to say, which on this model is a repetition loop rather than
    /// a decode, and is a fact about the words rather than about the machine.
    private static let bounds = 0.005...1.0

    /// The slope and intercept a *fit* is allowed to produce. A line is fitted
    /// to real points and can still come out absurd when they are clustered;
    /// these are the same guard the ratio bounds are, one level up.
    private static let slopeBounds = 0.005...0.60
    private static let interceptBounds = 0.0...5.0

    /// **Where on the distribution the estimate sits.** 0.80 of the residual
    /// ratios, from the replay above: 0.70 leaves the bar filling early on a
    /// third of dictations, 0.90 buys six more points of coverage for twice the
    /// unfinished bar, and the asymmetric loss between them is flat — so the
    /// choice is which complaint to answer, and the one on the table is *the
    /// estimates are short*.
    private static let headroomQuantile = 0.80

    /// …and how far that is ever allowed to move the line. Below 1 it would be
    /// a *discount*, which is the 09-07 fault in miniature; above 3 it is a
    /// window with a repetition loop in it promising a minute for four seconds
    /// of work.
    private static let headroomBounds = 1.0...3.0

    /// Which decode this is since the helper came up. The **first is skipped**:
    /// `whisper_helper.py` warms up on a second of silence, but the first real
    /// decode still pays for weights the allocator has not touched yet —
    /// measured at 2.8s against 1.3s warm, and 1.74× the warm median on clips
    /// under twelve seconds across the whole file. It is still *recorded*,
    /// marked cold, because it is a real fact about this app's first sentence
    /// after a launch; it is simply not fitted to.
    private static var decodesThisRun = 0

    private static let lock = NSLock()
    private static var samples: [Sample] = load()

    /// One decode, as it goes on disk. `load` is the 1-minute run queue at the
    /// moment the answer came back.
    ///
    /// `chars` and `compression` are what the recogniser said about its own
    /// output and are **optional**, because six hundred lines were written
    /// before there was anywhere to put them and a missing key must not cost
    /// the file its history. They are recorded and not modelled, for the reason
    /// in the header: they are known a second too late to predict anything, and
    /// they are the only thing that tells a slow machine from a repetition loop
    /// after the fact.
    struct Sample: Codable {
        let at: String
        let audio: Double
        let decode: Double
        let load: Double
        let cold: Bool
        var chars: Int?
        var compression: Double?
    }

    /// **Every sample, appended forever, one JSON object per line.** The window
    /// the estimate uses is the tail of this file; the rest of it is the record
    /// Victor asked for, which is what makes a better rule derivable later
    /// rather than guessable now — and what made both of the 2026-09-16
    /// measurements above possible at all. One line per dictation is a few
    /// kilobytes a day, and it sits beside the outbox for the outbox's reason: a
    /// log the system may purge under disk pressure is not a log.
    ///
    /// It supersedes `decode-rate.json`, which held bare ratios with no audio
    /// beside them — which is precisely why the 09-07 fault could only be
    /// diagnosed from `relay.log`, and only from the lines about the samples
    /// that were *discarded*.
    private static var fileURL: URL {
        Outbox.home.appendingPathComponent("decode-rate.jsonl")
    }

    /// The line and the headroom on it, as one answer.
    struct Fit {
        let intercept: Double
        let slope: Double
        /// What the line is multiplied by so it is a near-worst case rather than
        /// a middle one — `headroomQuantile` of the window's residual ratios.
        let headroom: Double

        func seconds(for audio: TimeInterval) -> TimeInterval {
            max(0.5, (intercept + slope * audio) * headroom)
        }
    }

    /// How long the next decode of `audio` seconds is expected to take. Read
    /// once per dictation, at the moment the row opens.
    static func seconds(for audio: TimeInterval) -> TimeInterval {
        fit(usableWindow()).seconds(for: audio)
    }

    private static func usableWindow() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return Array(samples.filter { !$0.cold }.suffix(window))
    }

    /// The line the window gives, and the headroom measured on it.
    ///
    /// Theil–Sen rather than least squares, and a quantile rather than the
    /// middle — both for the reasons in the header. The quantile ratio through
    /// the origin is the answer while there are too few points to have a slope
    /// worth the name; it is the *same* quantile, so the estimate does not jump
    /// the moment the eighth sample lands.
    static func fit(_ window: [Sample]) -> Fit {
        guard !window.isEmpty else {
            return Fit(intercept: fallbackIntercept, slope: fallbackSlope, headroom: 1)
        }
        let ratios = window.map { $0.decode / $0.audio }
        let throughOrigin = Fit(intercept: 0,
                                slope: clamp(quantile(ratios, headroomQuantile), to: slopeBounds),
                                headroom: 1)
        guard window.count >= minimumSamples else { return throughOrigin }

        var slopes: [Double] = []
        slopes.reserveCapacity(window.count * (window.count - 1) / 2)
        for i in 0..<window.count {
            for j in (i + 1)..<window.count {
                let dx = window[j].audio - window[i].audio
                guard abs(dx) >= minimumGap else { continue }
                slopes.append((window[j].decode - window[i].decode) / dx)
            }
        }
        guard !slopes.isEmpty else { return throughOrigin }

        let slope = clamp(quantile(slopes, 0.5), to: slopeBounds)
        let intercept = clamp(quantile(window.map { $0.decode - slope * $0.audio }, 0.5),
                              to: interceptBounds)
        // The headroom is measured against the line that is about to be used,
        // not against a fresh one: what it has to cover is *this* line's habit
        // of being short, and a residual read off any other is a different
        // number that happens to have the same name.
        let residuals = window.map { $0.decode / max(0.05, intercept + slope * $0.audio) }
        let headroom = clamp(quantile(residuals, headroomQuantile), to: headroomBounds)
        return Fit(intercept: intercept, slope: slope, headroom: headroom)
    }

    /// Linear interpolation between the two neighbouring order statistics — a
    /// window of ten has no ninth sample and rounding to one would make the
    /// quantile jump by a whole point every time a sample fell off the end.
    private static func quantile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let k = p * Double(sorted.count - 1)
        let lo = Int(k.rounded(.down)), hi = Int(k.rounded(.up))
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (k - Double(lo))
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// File what a decode actually cost. `audio` and `decode` are both seconds;
    /// `chars` and `compression` are the recogniser's own reading of what it
    /// produced, where the caller has them.
    ///
    /// Nonsense is dropped rather than clamped: a ratio outside `bounds` is
    /// evidence about something other than the model's speed — a decode that
    /// raced a sleep, a clip so short the JSON round-trip dominates it, a
    /// repetition loop — and letting it in would move the estimate for fifty
    /// dictations afterwards. **It is still written to the file**, marked,
    /// because "the answer came back in 40ms" is a fact worth having when the
    /// next fault is diagnosed from this file rather than from the log.
    static func record(audio: TimeInterval, decode: TimeInterval,
                       chars: Int? = nil, compression: Double? = nil) {
        guard audio > 0, decode > 0 else { return }
        lock.lock()
        decodesThisRun += 1
        let cold = decodesThisRun == 1
        lock.unlock()

        let ratio = decode / audio
        let usable = bounds.contains(ratio) && !cold
        let sample = Sample(at: ISO8601DateFormatter().string(from: Date()),
                            audio: audio, decode: decode, load: machineLoad(),
                            cold: !usable, chars: chars, compression: compression)
        append(sample)

        lock.lock()
        samples.append(sample)
        samples = Array(samples.suffix(window * 2))
        lock.unlock()

        let kept = usableWindow()
        let f = fit(kept)
        Log.info(String(format: "decode rate: %.1fs audio → %.1fs decode (%.3f×, load %.2f)%@ — %d samples, estimating (%.2fs + %.3f×) × %.2f",
                        audio, decode, ratio, sample.load,
                        usable ? "" : (cold ? " — cold, not fitted" : " — outside \(bounds), not fitted"),
                        kept.count, f.intercept, f.slope, f.headroom))
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
