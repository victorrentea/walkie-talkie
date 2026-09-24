import Foundation

/// **How far Reverse tunnel has come in, as a function of the clock** (2026-09-23).
///
/// Victor: *"The reverse tunnel effect sometimes takes too long, and the
/// transcription finishes earlier than the animation completes … start the
/// reverse tunnel effect as early as the beginning of the transcription process,
/// and fit it to the expected duration of the transcription."* It was running
/// over **twice** the chip's estimate and never less than 3 s
/// (`max((estimate − warmup) × 2, 3)`), against an estimate taken from the local
/// model's curve whatever engine was live — so a 0.7 s Wispr sentence and a 3 s
/// Scribe one both landed with the tunnel barely a third of the way in.
///
/// Now the approach is fitted to `DecodeRate.predict` — the engine's *typical*
/// round trip, not its near-worst — and both ways of being wrong are absorbed
/// here rather than by the words (the first two bullets superseded on
/// 2026-09-25, below):
///
/// - **On time**: at the predicted instant the approach was at 90 %:
///   visibly converged, and still a little large, so it never reads as *done*
///   before the words are.
/// - **Late**: past the prediction it kept creeping toward 97 %, which it
///   never reached — slower and slower, never still, never at rest.
/// - **Early**: nothing here waits for anything. The words are delivered the
///   moment they arrive and the ring goes out in `collapse`, from wherever it
///   has got to.
///
/// **Ends at 120 % of the prediction, front-loaded** (2026-09-25). Victor:
/// *"the reverse tunnel showed at transcription time should be estimate to
/// finish in 120% of the time estimated for the transcription to take. (so
/// that the animation is interrupted half way by the transcription done rather
/// than having to continue the reverse tunnel effect after scaling down to its
/// final size. also, decrease size more accelerated at start"*. What the
/// above became:
///
/// - **The approach ends at `end(predicted:)`** = `overrun` (1.2) × the
///   prediction, at rest (progress 1), and stays there if the words are later
///   still. The 90 % pose at the prediction and the creep toward 97 % after it
///   are gone: a late answer used to find the tunnel at its final size and
///   still being played — the thing he no longer wants to see.
/// - **Eased out, not in** (`easeOut`, `1 − (1 − u)^1.5`): it leaves at 1.5×
///   the linear rate and flattens toward the end. The Hermite it replaces left
///   at slope 0 — the first fifth of the span barely moved the size.
/// - **The words still land mid-approach**: on time, `u` is ≈ 0.8, which the
///   curve puts at progress ≈ 0.91 — the stamp about 1.2× its resting size,
///   visibly still coming in, where the old on-time pose was. A power of 2
///   would have been ≈ 0.96 there, 1.08× rest — read as *arrived*.
/// - **The opacity keeps the prediction's clock** (`Pose.time`): full ink at
///   the predicted instant, as before — he asked about the size, not the fade,
///   and stretched to 1.2× it would still be at ~87 % when the words land.
///
/// Pure, so it is unit-tested (`Tests/WalkieTalkieTests/RewindTimingTests`).
enum RewindTimeline {
    /// The approach ends at this multiple of the prediction (2026-09-25).
    static let overrun = 1.2
    /// The ease-out's power: 1 would be linear, 2 quadratic.
    static let easeOutPower = 1.5
    /// The shortest approach worth drawing once the picture is visible — a
    /// prediction shorter than the warm-up would otherwise be a jump.
    static let minimumSpan = 0.6
    /// How fast the ring goes when the words land — *"fade out foarte repede"*.
    static let collapse: TimeInterval = 0.15

    struct Pose: Equatable {
        /// 0 = huge and invisible, 1 = at rest round the pointer.
        let progress: Double
        /// 0…1 of the time to the prediction, clamped — what the opacity reads.
        let time: Double
    }

    /// When the approach reaches its final size, in seconds since the
    /// transcription began: `overrun` × the prediction.
    static func end(predicted: TimeInterval) -> TimeInterval {
        overrun * predicted
    }

    /// Front-loaded: steep at `u` = 0, flat at `u` = 1, clamped to 0…1.
    static func easeOut(_ u: Double) -> Double {
        let c = min(max(u, 0), 1)
        return 1 - pow(1 - c, easeOutPower)
    }

    /// - Parameters:
    ///   - elapsed: seconds since the transcription began (the microphone's close).
    ///   - predicted: the typical round trip for this audio on this engine.
    ///   - visibleFrom: when the picture can first be seen — the engine's
    ///     warm-up. The approach is drawn between that and `end(predicted:)`.
    static func pose(elapsed: TimeInterval, predicted: TimeInterval, visibleFrom: TimeInterval) -> Pose {
        let since = elapsed - visibleFrom
        guard since > 0 else { return Pose(progress: 0, time: 0) }
        let span = max(end(predicted: predicted) - visibleFrom, minimumSpan)
        let fadeSpan = max(predicted - visibleFrom, minimumSpan)
        return Pose(progress: easeOut(since / span), time: min(since / fadeSpan, 1))
    }

    /// **The whole tunnel 30 % smaller** (Victor, 2026-09-23: *"reduce the
    /// reverse tunnel's default size during transcription by 30%"*) — a factor on
    /// every size of the run: the huge start, the ~1.2× near the end, the rest.
    /// Here rather than on the preset's `scale`, which would also change the
    /// engine's render resolution; `approach` is called for the rewind alone.
    static let sizeFactor = 0.7

    /// The stamp's scale (× the preset's resting size) and opacity for a pose,
    /// starting at `from` × `sizeFactor` — geometric in the scale, so each
    /// second shrinks it by the same ratio; the opacity rises ahead of it
    /// (t^0.6), so the tunnel is there, huge and faint, from the first frames.
    static func stamp(_ pose: Pose, from: Double) -> (scale: Double, alpha: Double) {
        (sizeFactor * pow(from, 1 - pose.progress), pow(pose.time, 0.6))
    }
}
