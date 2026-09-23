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

    func testNothingMovesBeforeThePictureIsVisible() {
        XCTAssertEqual(p(0, predicted: 3), 0)
        XCTAssertEqual(p(visible, predicted: 3), 0)
    }

    /// On time: at the predicted instant it has converged to 90 % — close, and
    /// visibly not at rest.
    func testOnTimeReachesNinetyPercentAtThePrediction() {
        XCTAssertEqual(p(3, predicted: 3), RewindTimeline.onTime, accuracy: 1e-9)
        XCTAssertEqual(RewindTimeline.pose(elapsed: 3, predicted: 3, visibleFrom: visible).time, 1, accuracy: 1e-9)
    }

    /// Early: the words at half the prediction find it part-way, and the collapse
    /// that takes it from there is ≤ 150 ms — the animation holds nothing up.
    func testEarlyLandsMidApproachAndCollapsesFast() {
        let mid = p(1.8, predicted: 3)
        XCTAssertGreaterThan(mid, 0.1)
        XCTAssertLessThan(mid, RewindTimeline.onTime)
        XCTAssertLessThanOrEqual(RewindTimeline.collapse, 0.15)
    }

    /// Late: it keeps creeping, never reaches the ceiling, never looks done.
    func testLateCreepsTowardTheCeilingAndNeverArrives() {
        var last = p(3, predicted: 3)
        // Five times the prediction — past the settle's own give-up (8 s) and
        // well inside Double's resolution of the tail.
        for elapsed in stride(from: 3.1, through: 15, by: 0.1) {
            let now = p(elapsed, predicted: 3)
            XCTAssertGreaterThan(now, last, "still moving at \(elapsed) s")
            XCTAssertLessThan(now, RewindTimeline.ceiling)
            last = now
        }
        XCTAssertLessThanOrEqual(p(600, predicted: 3), RewindTimeline.ceiling)
        XCTAssertGreaterThan(p(6, predicted: 3), 0.95)                     // mostly there, not there
    }

    func testMonotonicAndNeverAtRest() {
        var last = -1.0
        for elapsed in stride(from: 0.0, through: 20, by: 0.01) {
            let now = p(elapsed, predicted: 2.4)
            XCTAssertGreaterThanOrEqual(now, last)
            XCTAssertLessThan(now, 1)
            last = now
        }
    }

    /// No stop-and-go at the predicted instant: the slope just before equals the
    /// slope just after.
    func testNoKinkAtThePrediction() {
        let h = 1e-4, t = 3.0
        let before = (p(t, predicted: t) - p(t - h, predicted: t)) / h
        let after = (p(t + h, predicted: t) - p(t, predicted: t)) / h
        XCTAssertEqual(before, after, accuracy: 0.01)
    }

    /// A prediction inside the warm-up (a Wispr sentence, ~0.7 s) still gets a
    /// real approach rather than a jump.
    func testShortPredictionStillHasASpan() {
        XCTAssertLessThan(p(visible + 0.3, predicted: 0.7), 0.6)
        XCTAssertEqual(p(visible + RewindTimeline.minimumSpan, predicted: 0.7), RewindTimeline.onTime, accuracy: 1e-9)
    }

    func testStampComesFromHugeAndFaintToNearRest() {
        let start = RewindTimeline.stamp(RewindTimeline.Pose(progress: 0, time: 0), from: 7)
        XCTAssertEqual(start.scale, 7, accuracy: 1e-9)
        XCTAssertEqual(start.alpha, 0, accuracy: 1e-9)
        let onTime = RewindTimeline.stamp(RewindTimeline.pose(elapsed: 3, predicted: 3, visibleFrom: visible), from: 7)
        XCTAssertEqual(onTime.alpha, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(onTime.scale, 1.1)                            // still a little large
        XCTAssertLessThan(onTime.scale, 1.3)
    }
}
