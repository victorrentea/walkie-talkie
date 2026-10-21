import XCTest
@testable import WalkieTalkie

final class ChunkPlannerTests: XCTestCase {

    /// Hops from a voiced/unvoiced pattern: each `(seconds, voiced)` stretch.
    private func hops(_ pattern: [(TimeInterval, Bool)]) -> [MeterHop] {
        var out: [MeterHop] = []
        var t: TimeInterval = 0
        for (len, v) in pattern {
            let n = Int((len / MeterHop.seconds).rounded())
            for _ in 0..<n {
                out.append(MeterHop(t: Float(t), rms: v ? 2000 : 50, voiced: v))
                t += MeterHop.seconds
            }
        }
        return out
    }

    private func end(_ h: [MeterHop]) -> TimeInterval { TimeInterval(h.last!.t) + MeterHop.seconds }

    func testNothingBeforeTheTrigger() {
        let h = hops([(4, true), (1, false), (4, true)])
        XCTAssertNil(ChunkPlanner.cut(hops: h, from: 0, now: end(h)))
    }

    func testCutsInTheMiddleOfTheLongestPause() {
        // 7 s speech, 0.7 s pause, 2 s speech, 1.5 s pause, 2 s speech = 13.2 s
        let h = hops([(7, true), (0.7, false), (2, true), (1.5, false), (2, true)])
        let cut = ChunkPlanner.cut(hops: h, from: 0, now: end(h))!
        // The 1.5 s pause starts at ~9.7 s; its middle is ~10.45 s.
        XCTAssertEqual(cut, 10.45, accuracy: 0.1)
    }

    func testAPauseTooEarlyIsNotACut() {
        // The only long pause sits 3 s in — under minChunk.
        let h = hops([(3, true), (2, false), (6, true)])
        XCTAssertNil(ChunkPlanner.cut(hops: h, from: 0, now: end(h)))
    }

    func testShortBreathsAreNotACut() {
        let h = hops([(4, true), (0.3, false), (4, true), (0.3, false), (4, true)])
        XCTAssertNil(ChunkPlanner.cut(hops: h, from: 0, now: end(h)))
    }

    func testAnOngoingPauseIsCutAPadIn() {
        let h = hops([(10, true), (0.8, false)])
        let cut = ChunkPlanner.cut(hops: h, from: 0, now: end(h))!
        XCTAssertEqual(cut, 10.4, accuracy: 0.1)
    }

    func testPastTheHardCapABreathWillDo() {
        let h = hops([(15, true), (0.32, false), (14, true)])
        let cut = ChunkPlanner.cut(hops: h, from: 0, now: end(h))
        XCTAssertNotNil(cut)
        XCTAssertEqual(cut!, 15.16, accuracy: 0.1)
    }

    func testCountsFromTheLastCut() {
        let h = hops([(8, true), (1, false), (8, true), (1, false), (3, true)])
        // From 8.5 s: 12.5 s of take, one pause at 17–18 s → cut ~17.5.
        let cut = ChunkPlanner.cut(hops: h, from: 8.5, now: end(h))!
        XCTAssertEqual(cut, 17.5, accuracy: 0.1)
    }

    func testSilenceAloneIsNotAChunk() {
        // Long silence, a little speech: under minVoiced before any pause.
        let h = hops([(9, false), (1, true), (1, false)])
        XCTAssertNil(ChunkPlanner.cut(hops: h, from: 0, now: end(h)))
    }

    func testVoicedSeconds() {
        let h = hops([(2, true), (1, false), (3, true)])
        XCTAssertEqual(ChunkPlanner.voiced(h, from: 0), 5, accuracy: 0.1)
        XCTAssertEqual(ChunkPlanner.voiced(h, from: 2.5), 3, accuracy: 0.1)
    }
}
