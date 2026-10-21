import Foundation

/// **Where to cut a take that is still being spoken, so the local model can
/// start on the first part** (2026-10-21). Pure — the meter's hops in, a cut out.
///
/// Victor: *"if I'm exceeding let's say ten seconds of speech, start looking for
/// places in the WAV that don't seem to have me talking … take from what was
/// recorded up to this point the longest silence period … and chop the audio at
/// that position"* and *"don't feed too small chunks either, because that's
/// gonna lead to possibly more hallucinations"*. So: nothing before `trigger`
/// seconds since the last cut; then the **longest** pause (a run of unvoiced
/// 64 ms hops, `MeterHop.voiced`) of at least `minGap`, whose middle lies at
/// least `minChunk` after the last cut, with `minVoiced` of speech before it.
/// Past `hardCap` the gap may be as short as `capGap` — Whisper reads 30 s at a
/// time, and a monologue with no breath in it still wants to be started on.
/// A pause still going at `now` counts with its length so far and is cut
/// `ongoingPad` into it, so the chunk ends in silence and the next one starts
/// in silence.
///
/// `evals/chunked-decode/` is the Python port and the measurement behind the
/// numbers; `LocalWhisperSource` is the one caller.
enum ChunkPlanner {

    struct Tuning: Equatable {
        var trigger: TimeInterval = 10
        // 8 s / 0.9 s measured (2026-10-21, `evals/chunked-decode/`, 40 takes,
        // the Large LoRA): WER 12.6 % chunked vs 13.1 % whole; 6 s / 0.6 s cost
        // +0.9 pt, 4 s chunks or 0.4 s gaps +1.5…2.1 pt.
        var minChunk: TimeInterval = 8
        var minGap: TimeInterval = 0.9
        var hardCap: TimeInterval = 28
        var capGap: TimeInterval = 0.3
        var minVoiced: TimeInterval = 2
        var ongoingPad: TimeInterval = 0.4

        /// `WT_CHUNK_TRIGGER`, `WT_CHUNK_MIN`, `WT_CHUNK_GAP` (seconds) override
        /// the defaults for a run — environment, then `elevenlabs.env`.
        static var configured: Tuning {
            var t = Tuning()
            func read(_ key: String) -> Double? {
                (ProcessInfo.processInfo.environment[key] ?? ElevenLabsSource.fileValue(key)).flatMap(Double.init)
            }
            if let v = read("WT_CHUNK_TRIGGER"), v >= 3 { t.trigger = v }
            if let v = read("WT_CHUNK_MIN"), v >= 2 { t.minChunk = v }
            if let v = read("WT_CHUNK_GAP"), v >= 0.2 { t.minGap = v }
            return t
        }
    }

    /// One run of unvoiced hops, `[start, end)` on the take's ruler.
    struct Pause: Equatable {
        let start: TimeInterval
        let end: TimeInterval
        let ongoing: Bool
        var length: TimeInterval { end - start }
    }

    /// The cut, in seconds on the take's ruler, or nil to wait for more audio.
    static func cut(hops: [MeterHop], from lastCut: TimeInterval, now: TimeInterval,
                    tuning t: Tuning = Tuning()) -> TimeInterval? {
        guard now - lastCut >= t.trigger else { return nil }
        let gap = now - lastCut >= t.hardCap ? t.capGap : t.minGap
        let hop = MeterHop.seconds
        var pauses: [Pause] = []
        var runStart: TimeInterval?
        // Voiced seconds since the last cut, sampled at the start of each pause.
        var voiced: TimeInterval = 0
        var voicedAt: [TimeInterval] = []
        for h in hops where TimeInterval(h.t) >= lastCut {
            let at = TimeInterval(h.t)
            if h.voiced {
                if let s = runStart { pauses.append(Pause(start: s, end: at, ongoing: false)); runStart = nil }
                voiced += hop
            } else if runStart == nil {
                runStart = at
                voicedAt.append(voiced)
            }
        }
        if let s = runStart { pauses.append(Pause(start: s, end: max(s, now), ongoing: true)) }
        var best: (pause: Pause, cut: TimeInterval)?
        for (i, p) in pauses.enumerated() {
            guard p.length >= gap, voicedAt[i] >= t.minVoiced else { continue }
            let at = p.ongoing ? p.start + min(p.length / 2, t.ongoingPad) : p.start + p.length / 2
            guard at - lastCut >= t.minChunk, at <= now else { continue }
            if best == nil || p.length >= best!.pause.length { best = (p, at) }
        }
        return best?.cut
    }

    /// Voiced seconds in `[from, to)` by the meter's hops.
    static func voiced(_ hops: [MeterHop], from: TimeInterval, to: TimeInterval = .infinity) -> TimeInterval {
        hops.reduce(0) { sum, h in
            let at = TimeInterval(h.t)
            return h.voiced && at >= from && at < to ? sum + MeterHop.seconds : sum
        }
    }
}
