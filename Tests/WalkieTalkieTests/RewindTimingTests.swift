import XCTest
@testable import WalkieTalkie

/// The per-engine transcription estimate (`DecodeRate`) and the rewind's
/// progress mapping (`RewindTimeline`), 2026-09-23.
final class DecodeRateTests: XCTestCase {

    private func sample(_ audio: Double, _ decode: Double, _ engine: String?, cold: Bool = false) -> DecodeRate.Sample {
        DecodeRate.Sample(at: "2026-09-23T00:00:00Z", audio: audio, decode: decode, load: 1,
                          cold: cold, chars: nil, compression: nil, engine: engine)
    }

    /// Twenty sentences spread 3…60 s on a known line, with ±10 % noise.
    private func line(_ intercept: Double, _ slope: Double, engine: String?) -> [DecodeRate.Sample] {
        (0..<20).map { i in
            let audio = 3 + Double(i) * 3
            let noise = 1 + 0.1 * sin(Double(i) * 1.7)
            return sample(audio, (intercept + slope * audio) * noise, engine)
        }
    }

    func testEmptyWindowIsTheEnginePrior() {
        let f = DecodeRate.fit([], prior: DecodeRate.prior(for: DecodeRate.elevenLabs))
        XCTAssertEqual(f.typical(for: 25), 0.9 + 0.08 * 25, accuracy: 1e-9)
        XCTAssertEqual(f.headroom, 1)
    }

    func testEachEngineIsFittedOnItsOwnSamples() {
        let all = line(0.3, 0.035, engine: nil)                      // legacy = local model
            + line(0.9, 0.08, engine: DecodeRate.elevenLabs)
            + line(0.6, 0.002, engine: DecodeRate.wisprFlow)
        func typical(_ e: String, _ audio: Double) -> Double {
            DecodeRate.fit(DecodeRate.fitWindow(of: all, engine: e), prior: DecodeRate.prior(for: e)).typical(for: audio)
        }
        XCTAssertEqual(typical(DecodeRate.whisperLocal, 30), 0.3 + 0.035 * 30, accuracy: 0.25)
        XCTAssertEqual(typical(DecodeRate.elevenLabs, 30), 0.9 + 0.08 * 30, accuracy: 0.35)
        XCTAssertEqual(typical(DecodeRate.wisprFlow, 30), 0.6 + 0.002 * 30, accuracy: 0.15)
    }

    func testLegacyLineWithoutEngineIsTheLocalModel() throws {
        let json = #"{"at":"2026-09-18T11:27:57Z","cold":false,"audio":31.9,"decode":2.2,"chars":401,"load":35.6}"#
        let s = try JSONDecoder().decode(DecodeRate.Sample.self, from: Data(json.utf8))
        XCTAssertNil(s.engine)
        XCTAssertEqual(s.engineKey, DecodeRate.whisperLocal)
    }

    func testColdSamplesAreLeftOutOfTheWindow() {
        let w = DecodeRate.fitWindow(of: [sample(10, 9, DecodeRate.elevenLabs, cold: true),
                                          sample(10, 1.7, DecodeRate.elevenLabs)],
                                     engine: DecodeRate.elevenLabs)
        XCTAssertEqual(w.count, 1)
    }

    /// A handful of samples rescales the prior rather than drawing a line
    /// through the origin — a hosted engine's cost is mostly its round trip.
    func testFewSamplesRescaleThePrior() {
        let few = [sample(5, 2.6, DecodeRate.elevenLabs), sample(20, 5.0, DecodeRate.elevenLabs),
                   sample(12, 3.8, DecodeRate.elevenLabs)]               // twice the prior
        let f = DecodeRate.fit(few, prior: DecodeRate.prior(for: DecodeRate.elevenLabs))
        XCTAssertEqual(f.typical(for: 2), 2 * (0.9 + 0.08 * 2), accuracy: 0.3)
        XCTAssertGreaterThan(f.intercept, 1)                              // the round trip survives
    }

    func testOneRunawayDoesNotMoveTheTypical() {
        var w = line(0.9, 0.08, engine: DecodeRate.elevenLabs)
        let before = DecodeRate.fit(w, prior: DecodeRate.prior(for: DecodeRate.elevenLabs)).typical(for: 20)
        w.append(sample(20, 40, DecodeRate.elevenLabs))                   // one 20× outlier
        let after = DecodeRate.fit(w, prior: DecodeRate.prior(for: DecodeRate.elevenLabs)).typical(for: 20)
        XCTAssertEqual(after, before, accuracy: 0.15)
    }

    func testTypicalIsNeverAboveTheCeiling() {
        let f = DecodeRate.fit(line(0.9, 0.08, engine: DecodeRate.elevenLabs), prior: DecodeRate.prior(for: DecodeRate.elevenLabs))
        for audio in stride(from: 1.0, through: 120, by: 7) {
            XCTAssertLessThanOrEqual(f.typical(for: audio), f.seconds(for: audio) + 1e-9)
        }
    }
}

final class RewindTimelineTests: XCTestCase {
    private let visible = 0.6

    private func p(_ elapsed: Double, predicted: Double) -> Double {
        RewindTimeline.pose(elapsed: elapsed, predicted: predicted, visibleFrom: visible).progress
    }
    /// The stamp's size × its resting size, `predictions` × the span in.
    private func size(at predictions: Double) -> Double {
        let span = 2.4                                                    // predicted 3, visible 0.6
        let pose = RewindTimeline.pose(elapsed: visible + predictions * span, predicted: 3, visibleFrom: visible)
        return RewindTimeline.stamp(pose, from: 7).scale / RewindTimeline.sizeFactor
    }

    func testNothingMovesBeforeThePictureIsVisible() {
        XCTAssertEqual(p(0, predicted: 3), 0)
        XCTAssertEqual(p(visible, predicted: 3), 0)
    }

    /// 2026-10-01: *"să ajungă la dimensiunea finală abia la dublu față de cât
    /// ar trebui estimat"* — at rest exactly at twice the prediction.
    func testAtRestOnlyAtTwiceThePrediction() {
        XCTAssertEqual(RewindTimeline.creep(RewindTimeline.reach), 1, accuracy: 1e-9)
        XCTAssertEqual(size(at: 2), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(size(at: 1.9), 1.03)
    }

    /// *"mai puțin rapidă la început … imediat se duce spre centru"*: at a
    /// quarter of the prediction it is barely a sixth of the way (the
    /// hyperbola was half), and at the prediction still more than twice its rest.
    func testSlowStart() {
        XCTAssertLessThan(RewindTimeline.creep(0.25), 0.2)
        XCTAssertGreaterThan(size(at: 1), 2)
        let h = 1e-4
        XCTAssertLessThan(RewindTimeline.creep(h) / h, 0.75)              // was 4
    }

    /// *"să continue logaritmic să scadă în dimensiune, să nu se oprească"*:
    /// every step smaller than the one before, none of them zero — through the
    /// rest and below it, with no jump in speed where it passes rest.
    func testShrinksForeverEverSlower() {
        var lastStep = Double.infinity
        for i in 1...400 {
            let u = Double(i) / 20
            let step = RewindTimeline.creep(u) - RewindTimeline.creep(u - 0.05)
            XCTAssertLessThanOrEqual(step, lastStep + 1e-12)
            XCTAssertGreaterThan(step, 0)
            lastStep = step
        }
        let h = 1e-6, r = RewindTimeline.reach
        let before = (RewindTimeline.creep(r) - RewindTimeline.creep(r - h)) / h
        let after = (RewindTimeline.creep(r + h) - RewindTimeline.creep(r)) / h
        XCTAssertEqual(before, after, accuracy: 1e-3)
    }

    /// Past rest it keeps getting smaller, but slowly: never vanishing.
    func testBelowRestButNotGone() {
        XCTAssertLessThan(size(at: 4), 0.65)
        XCTAssertGreaterThan(size(at: 4), 0.5)
        XCTAssertGreaterThan(size(at: 10), 0.3)
        XCTAssertLessThan(size(at: 10), size(at: 9))
    }

    /// Early: the words at half the prediction find it part-way, and the collapse
    /// that takes it from there is ≤ 150 ms — the animation holds nothing up.
    func testEarlyLandsMidApproachAndCollapsesFast() {
        let mid = p(1.8, predicted: 3)
        XCTAssertGreaterThan(mid, 0.2)
        XCTAssertLessThan(mid, p(3, predicted: 3))
        XCTAssertLessThanOrEqual(RewindTimeline.collapse, 0.15)
    }

    func testMonotonic() {
        var last = -1.0
        for elapsed in stride(from: 0.0, through: 20, by: 0.01) {
            let now = p(elapsed, predicted: 2.4)
            XCTAssertGreaterThanOrEqual(now, last)
            last = now
        }
    }

    /// A prediction inside the warm-up (a Wispr sentence, ~0.7 s) still gets a
    /// real approach rather than a jump.
    func testShortPredictionStillHasASpan() {
        XCTAssertLessThan(p(visible + 0.1, predicted: 0.7), 0.5)
        XCTAssertEqual(p(visible + RewindTimeline.reach * RewindTimeline.minimumSpan, predicted: 0.7), 1, accuracy: 1e-9)
    }

    func testStampComesFromHugeAndFaintTowardRest() {
        // 0.7 (2026-09-23, *"reduce … by 30%"*) × 0.6 (2026-09-28, *"60 % of what it's currently at"*).
        XCTAssertEqual(RewindTimeline.sizeFactor, 0.42, accuracy: 1e-9)
        let start = RewindTimeline.stamp(RewindTimeline.Pose(progress: 0, time: 0), from: 7)
        XCTAssertEqual(start.scale, 7 * 0.42, accuracy: 1e-9)
        // 2026-10-04: already 20 % opaque once it can be seen, nothing while it warms up hidden.
        XCTAssertEqual(start.alpha, 0.2, accuracy: 1e-9)
        let warming = RewindTimeline.stamp(RewindTimeline.pose(elapsed: visible / 2, predicted: 3, visibleFrom: visible), from: 7)
        XCTAssertEqual(warming.alpha, 0, accuracy: 1e-9)
        let justShown = RewindTimeline.stamp(RewindTimeline.pose(elapsed: visible + RewindTimeline.fadeIn, predicted: 3, visibleFrom: visible), from: 7)
        XCTAssertGreaterThanOrEqual(justShown.alpha, 0.2)                       // the floor, plus the rise above it
        XCTAssertLessThan(justShown.alpha, 0.4)
        let late = RewindTimeline.stamp(RewindTimeline.pose(elapsed: 60, predicted: 3, visibleFrom: visible), from: 7)
        XCTAssertEqual(late.alpha, 1, accuracy: 1e-9)
        XCTAssertLessThan(late.scale, 0.42)                                    // past rest, still going
        XCTAssertGreaterThan(late.scale, 0.42 * 0.2)                           // but not gone
    }

    /// 2026-10-04: on the window at half the predicted transcription, eased; on the pointer at the close.
    func testTravelLandsAtHalfThePrediction() {
        XCTAssertEqual(RewindTimeline.travel(elapsed: 0, predicted: 4), 0)
        XCTAssertEqual(RewindTimeline.travel(elapsed: 1, predicted: 4), 0.5, accuracy: 1e-9)   // half-way at a quarter
        XCTAssertEqual(RewindTimeline.travel(elapsed: 2, predicted: 4), 1)
        XCTAssertEqual(RewindTimeline.travel(elapsed: 9, predicted: 4), 1)                     // and stays there
        XCTAssertLessThan(RewindTimeline.travel(elapsed: 0.2, predicted: 4), 0.1)             // leaves gently
        XCTAssertEqual(RewindTimeline.travel(elapsed: 0, predicted: 0), 1)
        // held on the pointer until it can be seen, then half of what is left
        XCTAssertEqual(RewindTimeline.travel(elapsed: 0.25, predicted: 1, visibleFrom: 0.25), 0)
        XCTAssertLessThan(RewindTimeline.travel(elapsed: 0.3, predicted: 1, visibleFrom: 0.25), 0.1)
        XCTAssertEqual(RewindTimeline.travel(elapsed: 0.25 + 0.375, predicted: 1, visibleFrom: 0.25), 1)
        XCTAssertEqual(RewindTimeline.travel(elapsed: 0.25 + 0.3, predicted: 0.5, visibleFrom: 0.25), 1)  // minimumSpan
    }

    /// 2026-10-08: a bound sentence's effect flies to the terminal over the whole prediction.
    func testFlightLandsAtThePrediction() {
        XCTAssertEqual(RewindTimeline.flight(elapsed: 0, predicted: 3), 0)
        XCTAssertLessThan(RewindTimeline.flight(elapsed: 0.2, predicted: 3), 0.05)              // leaves gently
        XCTAssertEqual(RewindTimeline.flight(elapsed: 1.5, predicted: 3), 0.5, accuracy: 1e-9)  // half-way at half
        XCTAssertEqual(RewindTimeline.flight(elapsed: 3, predicted: 3), 1)                      // on the terminal as the words are due
        XCTAssertEqual(RewindTimeline.flight(elapsed: 9, predicted: 3), 1)                      // and stays there
        XCTAssertEqual(RewindTimeline.flight(elapsed: 0.6, predicted: 0.1), 1)                 // minimumSpan
    }

    /// 2026-10-08: Tendrils shrinks to a fifth on its way to the window.
    func testFlightShrinksToAFifth() {
        XCTAssertEqual(RewindTimeline.flightScale(elapsed: 0, predicted: 3), 1)
        XCTAssertEqual(RewindTimeline.flightScale(elapsed: 1.5, predicted: 3), 0.6, accuracy: 1e-9)
        XCTAssertEqual(RewindTimeline.flightScale(elapsed: 3, predicted: 3), 0.2, accuracy: 1e-9)
        XCTAssertEqual(RewindTimeline.flightScale(elapsed: 9, predicted: 3), 0.2, accuracy: 1e-9)
    }

    /// 2026-10-09: the dust lands on the ring where it is nearest the pointer, and circles from there.
    func testDustLandsOnTheNearestPointThenOrbits() {
        let c = CGPoint(x: 500, y: 300)
        let r = RewindTimeline.orbitRadius(for: CGSize(width: 958, height: 525))
        XCTAssertEqual(r, 131.25, accuracy: 1e-9)                      // ½ of the shorter side, as a diameter
        // Pointer left of the window: it lands on the ring's left side, not its far right.
        let left = CGPoint(x: 100, y: 300)
        let entry = RewindTimeline.orbitEntry(around: c, radius: r, angle: RewindTimeline.entryAngle(around: c, from: left))
        XCTAssertEqual(entry.x, c.x - r, accuracy: 1e-9)
        XCTAssertEqual(entry.y, c.y, accuracy: 1e-9)
        // Nearest point: on the segment from the pointer to the centre, r from the centre.
        let diag = CGPoint(x: 900, y: 700)
        let a = RewindTimeline.entryAngle(around: c, from: diag)
        let e = RewindTimeline.orbitEntry(around: c, radius: r, angle: a)
        XCTAssertEqual(hypot(e.x - c.x, e.y - c.y), r, accuracy: 1e-9)
        XCTAssertEqual(hypot(diag.x - e.x, diag.y - e.y), hypot(diag.x - c.x, diag.y - c.y) - r, accuracy: 1e-9)
        // A pointer inside the ring goes out to it; one on the centre takes angle 0.
        XCTAssertEqual(RewindTimeline.entryAngle(around: c, from: c), 0)
        // The orbit starts exactly where the flight landed, stays on the ring, turns clockwise.
        XCTAssertEqual(RewindTimeline.orbit(around: c, radius: r, since: 0, from: a).x, e.x, accuracy: 1e-9)
        XCTAssertEqual(RewindTimeline.orbit(around: c, radius: r, since: 0, from: a).y, e.y, accuracy: 1e-9)
        for t in [0.3, 1.0, 1.7] {
            let p = RewindTimeline.orbit(around: c, radius: r, since: t, from: a)
            XCTAssertEqual(hypot(p.x - c.x, p.y - c.y), r, accuracy: 1e-9)
        }
        let quarter = RewindTimeline.orbit(around: .zero, radius: r, since: RewindTimeline.orbitPeriod / 4)
        XCTAssertEqual(quarter.y, -r, accuracy: 1e-9)                  // clockwise
    }

    /// 2026-10-04: the ring starts as tall as the screen.
    func testRingStartsAsTallAsTheScreen() {
        let restRing = 0.66 * 0.317
        let from = RewindTimeline.from(screenHeight: 1080, longSide: 1920, restRing: restRing)
        let ring = restRing * RewindTimeline.stamp(.init(progress: 0, time: 0), from: from).scale
        XCTAssertEqual(ring * 1920, 1080, accuracy: 0.5)
    }

    /// 2026-10-02: Sparks shrinks by the same ratio the tunnel's stamp does, from full size.
    func testShrinkFollowsTheTunnelsRatio() {
        XCTAssertEqual(RewindTimeline.shrink(.init(progress: 0, time: 0), from: 7), 1, accuracy: 1e-9)
        for p in [0.2, 0.58, 1, 1.4] {
            let pose = RewindTimeline.Pose(progress: p, time: 1)
            let tunnel = RewindTimeline.stamp(pose, from: 7).scale / RewindTimeline.stamp(.init(progress: 0, time: 0), from: 7).scale
            XCTAssertEqual(RewindTimeline.shrink(pose, from: 7), tunnel, accuracy: 1e-9)
        }
        XCTAssertEqual(RewindTimeline.shrink(.init(progress: 1, time: 1), from: 7), 1.0 / 7, accuracy: 1e-9)
    }
}
