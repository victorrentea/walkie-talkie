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
/// **Ends at 120 % of the prediction, front-loaded** (2026-09-25) — superseded
/// the same week, kept for the record: the approach ended at 1.2 × the
/// prediction (`1 − (1 − u)^1.5`), at rest and held there.
///
/// **Never quite arrives** (2026-09-28; superseded 2026-10-01, below). Victor: *"The reverse tunnel animation
/// that shows during the dictation should be logarithmically decreasing so that
/// we rarely hit the final size, and the final size should be 60 % of what it's
/// currently at … It should appear more time to be collapsing, although on a
/// slower pace as it gets slower and slower."* So:
///
/// - **Hyperbolic, not eased**: progress = `1 − 1 / (1 + 4u)`, `u` the
///   time since the picture showed over the time to the prediction. Steep at
///   first (slope 4), then each second brings it a smaller step closer —
///   and it is never 1: at the prediction 80 %, at twice it 89 %, at five times
///   95 %, still creeping. In the geometric size that is 1.5 × rest at the
///   prediction, 1.24 × at twice, 1.1 × at five times. The words interrupt it
///   from wherever it got to (`collapse`); a late answer finds it moving.
/// - **Every size 0.6 of what it was**: `sizeFactor` 0.7 → 0.42.
/// - **The opacity keeps the prediction's clock** (`Pose.time`), as before.
///
/// **Comes in slowly, at rest only at twice the prediction, then keeps
/// shrinking** (2026-10-01) — supersedes the hyperbola. Victor: *"să fie mai
/// lent și să se micșoreze în jurul țintei mult mai lent … să continue
/// logaritmic să scadă în dimensiune, să nu se oprească … să ajungă la
/// dimensiunea finală abia la dublu față de cât ar trebui estimat"*, then *"mai
/// puțin rapidă la început, să pară că vine spre centru. Ea imediat se duce
/// spre centru și rămâne acolo un pic"*. The hyperbola left at slope 4 — half
/// the way in at a quarter of the prediction — and the log showed why it then
/// sat still: Wispr Flow's words landed at 1.5–1.7 × the prediction (2.37 s
/// fitted, ~4 s real; 2.71 s, ~4 s), where the hyperbola was 87 % in and
/// moving too little to see. So:
///
/// - **Up to `reach` × the prediction**: progress = `ln(1 + u/ease) / ln(1 + reach/ease)` —
///   logarithmic but nearly even: slope 0.72 at the start (was 4), half of
///   that at `reach`. 58 % in at the prediction (2.2 × rest), 85 % at 1.6 ×
///   (1.3 × rest), at rest exactly at 2 ×.
/// - **Past it, still shrinking**: progress goes beyond 1, so the stamp gets
///   *smaller* than rest — `1 + k·beyond·ln(1 + (u − reach)/beyond)`, `k` the
///   slope it arrived with, so the speed does not jump, then slows forever:
///   0.57 × rest at 4 ×, 0.37 × at 10 ×. Never still.
///
/// Pure, so it is unit-tested (`Tests/WalkieTalkieTests/RewindTimingTests`).
enum RewindTimeline {
    /// At rest at this many predictions (2026-10-01: *"abia la dublu"*).
    static let reach = 2.0
    /// How even the approach is up to `reach`: the slope at the end is
    /// `ease / (ease + reach)` of the slope at the start — half, at 2.
    static let ease = 2.0
    /// How fast the shrinking past rest slows down, in predictions.
    static let beyond = 0.5
    /// The shortest approach worth drawing once the picture is visible — a
    /// prediction shorter than the warm-up would otherwise be a jump.
    static let minimumSpan = 0.6
    /// How fast the ring goes when the words land — *"fade out foarte repede"*.
    static let collapse: TimeInterval = 0.15

    struct Pose: Equatable {
        /// 0 = huge and invisible, 1 at rest round the pointer (at `reach`),
        /// past 1 smaller than rest and still shrinking.
        let progress: Double
        /// 0…1 of the time to the prediction, clamped — what the opacity reads.
        let time: Double
        /// 0 while the engine is still warming up hidden, rising to 1 over
        /// `fadeIn` once the picture can be seen.
        var shown: Double = 1
    }

    /// 0 at `u` ≤ 0, 1 at `reach`, logarithmic all the way and never flat:
    /// see the 2026-10-01 bullets above.
    static func creep(_ u: Double) -> Double {
        guard u > 0 else { return 0 }
        let norm = log(1 + reach / ease)
        if u <= reach { return log(1 + u / ease) / norm }
        let arrival = 1 / ((ease + reach) * norm)                   // d/du at `reach`
        return 1 + arrival * beyond * log(1 + (u - reach) / beyond)
    }

    /// - Parameters:
    ///   - elapsed: seconds since the transcription began (the microphone's close).
    ///   - predicted: the typical round trip for this audio on this engine.
    ///   - visibleFrom: when the picture can first be seen — the engine's
    ///     warm-up. `u` = 1 at the prediction.
    static func pose(elapsed: TimeInterval, predicted: TimeInterval, visibleFrom: TimeInterval) -> Pose {
        let since = elapsed - visibleFrom
        guard since > 0 else { return Pose(progress: 0, time: 0, shown: 0) }
        let span = max(predicted - visibleFrom, minimumSpan)
        return Pose(progress: creep(since / span), time: min(since / span, 1),
                    shown: min(since / fadeIn, 1))
    }

    /// **The whole tunnel 30 % smaller** (Victor, 2026-09-23: *"reduce the
    /// reverse tunnel's default size during transcription by 30%"*), then **60 %
    /// of that** (2026-09-28: *"the final size should be 60 % of what it's
    /// currently at"*): 0.7 × 0.6 = 0.42, a factor on every size of the run —
    /// the huge start, the creep, the rest and below it. Here rather
    /// than on the preset's `scale`, which would also change the engine's render
    /// resolution; `approach` is called for the rewind alone.
    static let sizeFactor = 0.42

    /// The stamp's scale (× the preset's resting size) and opacity for a pose,
    /// starting at `from` × `sizeFactor` — geometric in the scale, so each
    /// second shrinks it by the same ratio; the opacity rises ahead of it
    /// (t^0.6), so the tunnel is there, huge and faint, from the first frames.
    ///
    /// **Already 20 % opaque the moment it can be seen** (2026-10-04, Victor:
    /// *"un reverse tunnel vizibil deja trebuie să apară, dar … douăzeci la sută
    /// opac"*) — it rose from nothing, so the first second of the wait showed no
    /// tunnel at all. `startAlpha` is the floor, reached over `fadeIn` so it
    /// does not pop; the rise above it keeps its old curve.
    static func stamp(_ pose: Pose, from: Double) -> (scale: Double, alpha: Double) {
        (sizeFactor * pow(from, 1 - pose.progress),
         pose.shown * (startAlpha + (1 - startAlpha) * pow(pose.time, 0.6)))
    }
    static let startAlpha = 0.2
    /// How long the tunnel takes to reach `startAlpha` once it can be seen.
    static let fadeIn: TimeInterval = 0.15

    /// **`from` such that the ring starts as tall as the screen** (2026-10-04,
    /// Victor: *"de diametru egal cu înălțimea ecranului"*): the ring's diameter
    /// is `restRing × sizeFactor × from` of the long side at the start.
    static func from(screenHeight: Double, longSide: Double, restRing: Double) -> Double {
        max(1.01, screenHeight / max(longSide, 1) / (restRing * sizeFactor))
    }

    /// **On the window at half the predicted transcription** (2026-10-04,
    /// Victor: *"din loc în care era mouse-ul … începe să se ducă spre aplicația
    /// receptor, urmând să se centreze pe centrul ei progresiv, ca să ajungă
    /// acolo … la jumătatea duratei estimate a transcrierii, urmând ca apoi să se
    /// micșoreze"*). On the clock rather than on the ring's size (2026-10-02 to
    /// 10-04 it landed when the ring was half the screen across, ~15 % of the
    /// way): `elapsed` from the close, eased in and out so it leaves the pointer
    /// and settles on the window gently. The shrink is untouched.
    ///
    /// **It leaves the pointer only once it can be seen** (2026-10-05, Victor:
    /// *"trebuia să apară … în jurul mouse-ului cu opacitate 20% și … cât timp
    /// transcrie, să se deplaseze spre centrul ferestrei țintă"*). The clock
    /// started at the close, so with the tunnel hidden for its warm-up (~0.77 s)
    /// and a local transcription of ~1 s predicted, it had arrived (0.5 s) before
    /// it showed — it appeared on the window and was gone. Now `visibleFrom`
    /// holds it on the pointer until then, and the half is of what is left of
    /// the prediction (at least `minimumSpan`).
    ///
    /// - Returns: 0 on the pointer … 1 on the window.
    static func travel(elapsed: TimeInterval, predicted: TimeInterval, visibleFrom: TimeInterval = 0) -> Double {
        let span = arriveShare * (visibleFrom > 0 ? max(predicted - visibleFrom, minimumSpan) : predicted)
        guard span > 0 else { return 1 }
        let u = min(max((elapsed - visibleFrom) / span, 0), 1)
        return u * u * (3 - 2 * u)
    }
    /// The share of the prediction by which the tunnel is on the window.
    static let arriveShare = 0.5

    /// **A bound sentence's own effect flies from the pointer to the terminal**
    /// (2026-10-08, Victor: *"instead of the reverse tunnel that goes towards the
    /// receiving terminal … that effect from around the mouse to move from where
    /// it was currently towards that terminal by replaying the sound recorded up
    /// to that point backwards … condensed to fit the time estimated for the
    /// flight"*). The flight is the whole predicted transcription, eased in and
    /// out, so it lands on the terminal as the words are due; the take is read
    /// backwards at the speed that fits one pass into the same span
    /// (`CaretHalo.rewindSpeed`). No warm-up to wait out: the effect is already
    /// on screen.
    ///
    /// - Returns: 0 on the pointer … 1 on the terminal.
    static func flight(elapsed: TimeInterval, predicted: TimeInterval) -> Double {
        let span = max(predicted, minimumSpan)
        let u = min(max(elapsed / span, 0), 1)
        return u * u * (3 - 2 * u)
    }

    /// **Not straight there — a bow, like half an ellipse** (2026-10-08, Victor,
    /// for a prompt at the caret, then for both: *"the trajectory shouldn't be
    /// necessarily direct; should be a bit elliptical towards the center of the
    /// recipient"*). The straight line from `a` to `b` plus a sideways bulge of
    /// `bow` × its length at the middle (`sin(π·p)`).
    ///
    /// **Concave: it sags** (same afternoon, Victor: *"the trajectory … to the
    /// recipient app center should be concave"*) — the bulge always goes down
    /// the screen (Cocoa's y up, so the perpendicular whose y is negative), a ∪
    /// under the straight line whichever way it travels; it went to the left of
    /// travel for one build, which was a hump half the time. Straight up or down
    /// there is no "down" to the side: it bows left.
    static func arc(from a: CGPoint, to b: CGPoint, progress p: Double) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y, q = CGFloat(p)
        // (−dy, dx) is left of travel; flip it if that points up.
        let side: CGFloat = dx > 0 ? -1 : 1
        let bulge = CGFloat(bow * sin(.pi * p)) * side
        return CGPoint(x: a.x + dx * q - dy * bulge, y: a.y + dy * q + dx * bulge)
    }
    static let bow = 0.3

    /// **Arrived, it circles like a loading icon** (same message: *"and then
    /// there start circling like a loading icon"*): clockwise round `c`, one
    /// turn every `orbitPeriod`, the radius opening from 0 to `orbitRadius` over
    /// `orbitGrow` so the arrival does not jump. `since` is the time since it landed.
    static func orbit(around c: CGPoint, since t: TimeInterval) -> CGPoint {
        guard t > 0 else { return c }
        let r = orbitRadius * CGFloat(min(t / orbitGrow, 1))
        let angle = -2 * Double.pi * t / orbitPeriod
        return CGPoint(x: c.x + r * CGFloat(cos(angle)), y: c.y + r * CGFloat(sin(angle)))
    }
    static let orbitRadius: CGFloat = 50
    static let orbitPeriod: TimeInterval = 1.2
    static let orbitGrow: TimeInterval = 0.4

    /// **Sparks shrinks at the tunnel's own rate** (2026-10-02, Victor: *"dacă
    /// … Stars se micșorează în același stil în care se micșorează și Reverse
    /// Tunnel … în loc să rămână activ pe tot ecranul, să se micșoreze în timp
    /// ce redă animația"*). The tunnel's stamp is `sizeFactor × from^(1 − progress)`,
    /// so against where it started it is `from^(−progress)` — that ratio, from
    /// the picture's own full size: 1 as the transcription opens, ~0.32 at the
    /// prediction, 1/`from` at twice it, and on past it like the tunnel.
    static func shrink(_ pose: Pose, from: Double) -> Double {
        pow(from, -pose.progress)
    }
}
