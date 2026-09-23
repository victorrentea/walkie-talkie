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
/// here rather than by the words:
///
/// - **On time**: at the predicted instant the approach is at `onTime` (90 %):
///   visibly converged, and still a little large, so it never reads as *done*
///   before the words are.
/// - **Late**: past the prediction it keeps creeping toward `ceiling`, which it
///   never reaches — slower and slower, never still, never at rest.
/// - **Early**: nothing here waits for anything. The words are delivered the
///   moment they arrive and the ring goes out in `collapse`, from wherever it
///   has got to.
///
/// Pure, so it is unit-tested (`Tests/WalkieTalkieTests/RewindTimingTests`).
enum RewindTimeline {
    /// The approach's progress at the predicted end.
    static let onTime = 0.9
    /// Where a late answer is heading, asymptotically.
    static let ceiling = 0.97
    /// How quickly a late approach closes on `ceiling`, in units of the span:
    /// one span late it has covered 1 − e^(−1/τ) of what is left.
    static let lateTau = 0.35
    /// The shortest approach worth drawing once the picture is visible — a
    /// prediction shorter than the warm-up would otherwise be a jump.
    static let minimumSpan = 0.6
    /// How fast the ring goes when the words land — *"fade out foarte repede"*.
    static let collapse: TimeInterval = 0.15

    struct Pose: Equatable {
        /// 0 = huge and invisible, 1 = at rest round the pointer. Never 1.
        let progress: Double
        /// 0…1 of the time to the prediction, clamped — what the opacity reads.
        let time: Double
    }

    /// - Parameters:
    ///   - elapsed: seconds since the transcription began (the microphone's close).
    ///   - predicted: the typical round trip for this audio on this engine.
    ///   - visibleFrom: when the picture can first be seen — the engine's
    ///     warm-up. The approach is drawn between that and the prediction.
    static func pose(elapsed: TimeInterval, predicted: TimeInterval, visibleFrom: TimeInterval) -> Pose {
        let span = max(predicted - visibleFrom, minimumSpan)
        let u = (elapsed - visibleFrom) / span
        guard u > 0 else { return Pose(progress: 0, time: 0) }
        guard u > 1 else {
            // Cubic Hermite from (0, slope 0) to (1, slope m): eased in, and
            // leaving u = 1 at exactly the slope the late branch starts with, so
            // there is no stop-and-go at the predicted instant.
            let m = (ceiling - onTime) / lateTau / onTime
            let h = (-2 * u * u * u + 3 * u * u) + m * (u * u * u - u * u)
            return Pose(progress: onTime * h, time: u)
        }
        let late = (ceiling - onTime) * (1 - exp(-(u - 1) / lateTau))
        return Pose(progress: onTime + late, time: 1)
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
