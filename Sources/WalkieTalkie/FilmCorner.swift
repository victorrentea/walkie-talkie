import CoreGraphics
import Foundation

/// **Where the box ends when 🔽 ↑ films it from inside the wheel drag**
/// (2026-11-22). Pure (`FilmCornerTests`).
///
/// The side button never reaches a tap — only the ⌃⌥⌘F4 Options+ posts once it
/// has recognised the swipe — so *when 🔽 went down* is not observable. If the
/// pointer moves during that swipe, the drag events of the swipe itself have
/// been resizing the box, upwards, by the gesture's own travel. So the box is
/// frozen where the pointer was **before the last upward run** of the drag:
/// walking back from the chord while the samples go up (never down), inside
/// `window`, as far as the sample the hand rested on (a gap over `pause`). That run is the swipe only if
/// it is a swipe's shape — at least `travel` points and more up than sideways;
/// anything else (the pointer held still by Options+, a drag that was simply
/// still going) leaves the box where the pointer is at the chord.
enum FilmCorner {
    struct Sample: Equatable {
        /// Seconds, the event's own clock.
        var at: TimeInterval
        /// Global CG points — y grows downwards.
        var point: CGPoint
    }

    /// How far back a swipe can have begun.
    static let window: TimeInterval = 1.0
    /// A gap this long between two drag events is the hand at rest.
    static let pause: TimeInterval = 0.12
    /// The least upward travel that reads as the swipe.
    static let travel: CGFloat = 24
    /// How much of the trail the tap keeps.
    static let kept: TimeInterval = 1.5

    /// `trail`: oldest first. Nil with no sample at all.
    static func corner(of trail: [Sample], chordAt: TimeInterval) -> CGPoint? {
        guard let last = trail.last else { return nil }
        // The hand stood still before the chord: nothing of the swipe reached the box.
        guard chordAt - last.at <= pause else { return last.point }
        var start = trail.count - 1
        while start > 0 {
            let newer = trail[start], older = trail[start - 1]
            guard newer.point.y <= older.point.y + 0.5, chordAt - older.at <= window else { break }
            start -= 1
            // Across a pause the older sample is where the hand rested: the run's
            // origin, and nothing before it belongs to the swipe.
            if newer.at - older.at > pause { break }
        }
        let from = trail[start].point
        let up = from.y - last.point.y, sideways = abs(last.point.x - from.x)
        return up >= travel && up > sideways ? from : last.point
    }
}
