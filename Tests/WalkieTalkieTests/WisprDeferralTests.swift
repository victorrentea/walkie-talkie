import XCTest
@testable import WalkieTalkie

/// Q12 for Wispr Flow (2026-10-21): a start that meets Wispr still on the last
/// sentence is recorded by the relay and handed to Wispr when it is free.
final class WisprDeferralTests: XCTestCase {

    private typealias D = WisprDeferral

    private func facts(_ now: CFAbsoluteTime, _ edit: (inout D.Facts) -> Void = { _ in }) -> D.Facts {
        var f = D.Facts(now: now, gestureAt: 100)
        edit(&f)
        return f
    }

    // MARK: When a start is deferred

    func testWisprFreeIsNotBusy() {
        XCTAssertNil(D.startBusy(machineRecording: false, speculative: false, capturing: false,
                                 discarding: false, finishingRow: nil, endingInFlight: 0, take: "3"))
    }

    func testAWordsInFlightCaptureDefers() {
        let why = D.startBusy(machineRecording: false, speculative: false, capturing: true,
                              discarding: false, finishingRow: nil, endingInFlight: 0, take: "3")
        XCTAssertEqual(why, "Wispr Flow is still transcribing take 3")
    }

    func testACancelledRowWispIsStillFinishingDefersByItsRow() {
        // A discarded capture is not the words in flight — the row it waits on is.
        XCTAssertNil(D.startBusy(machineRecording: false, speculative: false, capturing: true,
                                 discarding: true, finishingRow: nil, endingInFlight: 0, take: "3"))
        XCTAssertEqual(D.startBusy(machineRecording: false, speculative: false, capturing: true,
                                   discarding: true, finishingRow: 18414, endingInFlight: 0, take: "3"),
                       "Wispr Flow is still finishing row 18414")
    }

    func testAnEndOnItsWayDefers() {
        XCTAssertEqual(D.startBusy(machineRecording: false, speculative: false, capturing: false,
                                   discarding: false, finishingRow: nil, endingInFlight: 1, take: "3"),
                       "take 3 is still ending")
    }

    // MARK: Is the sentence before it over

    func testOlderDoneOnceAnswered() {
        XCTAssertTrue(D.olderDone(owes: false, machineRecording: false, speculative: false, capturing: true,
                                  endingInFlight: 0, ownTake: false))
    }

    func testOlderNotDoneWhileItsCaptureOrEndIsOut() {
        XCTAssertFalse(D.olderDone(owes: true, machineRecording: false, speculative: false, capturing: true,
                                   endingInFlight: 0, ownTake: false))
        XCTAssertFalse(D.olderDone(owes: true, machineRecording: false, speculative: false, capturing: false,
                                   endingInFlight: 1, ownTake: false))
    }

    func testOlderWithNothingLeftAnywhereIsDoneEvenUnanswered() {
        // The belt: a sentence that ended without a word to the relay must not
        // hold the next one until the ceiling.
        XCTAssertTrue(D.olderDone(owes: true, machineRecording: false, speculative: false, capturing: false,
                                  endingInFlight: 0, ownTake: false))
    }

    // MARK: The verdict

    func testWaitsWhileTheSentenceBeforeIsInFlight() {
        XCTAssertEqual(D.verdict(facts(110)), .wait("the sentence before it is still in flight"))
    }

    func testReleasesWhileHeIsStillTalking() {
        XCTAssertEqual(D.verdict(facts(103) { $0.olderDone = true; $0.olderDoneAt = 102 }), .release)
    }

    func testAStoppedTakeWaitsForItsRecordingToClose() {
        let f = facts(103) { $0.olderDone = true; $0.olderDoneAt = 102; $0.stoppedAt = 102.5 }
        XCTAssertEqual(D.verdict(f), .wait("the recording of his stop is still closing"))
        XCTAssertEqual(D.verdict(facts(103) { $0.olderDone = true; $0.olderDoneAt = 102; $0.stoppedAt = 102.5
                                              $0.closedKnown = true }), .release)
    }

    func testBusyWispWaitsWithNoClockWhileHeTalks() {
        let f = facts(300) { $0.olderDone = true; $0.olderDoneAt = 101; $0.busy = "Wispr Flow is still finishing row 7" }
        XCTAssertEqual(D.verdict(f), .wait("Wispr Flow is still finishing row 7"))
    }

    func testBusyWisprAfterHisStopGivesUpPastTheFreeCeiling() {
        let base: (inout D.Facts) -> Void = { $0.olderDone = true; $0.olderDoneAt = 101; $0.stoppedAt = 105
                                             $0.closedKnown = true; $0.busy = "Wispr Flow's microphone is still open" }
        XCTAssertEqual(D.verdict(facts(105 + D.freeCeiling - 0.1, base)), .wait("Wispr Flow's microphone is still open"))
        guard case .giveUp(let why) = D.verdict(facts(105 + D.freeCeiling + 0.1, base)) else {
            return XCTFail("a Wispr busy past the ceiling after his stop gives the take up")
        }
        XCTAssertTrue(why.hasPrefix("Wispr Flow's microphone is still open"), why)
    }

    func testTheFreeCeilingCountsFromTheLaterOfHisStopAndTheOlderEnd() {
        // He stopped at 105, the sentence before ended at 120: 10 s from 120.
        let base: (inout D.Facts) -> Void = { $0.olderDone = true; $0.olderDoneAt = 120; $0.stoppedAt = 105
                                             $0.closedKnown = true; $0.busy = "busy" }
        XCTAssertEqual(D.verdict(facts(125, base)), .wait("busy"))
        XCTAssertNotEqual(D.verdict(facts(131, base)), .wait("busy"))
    }

    func testAnOlderSentenceThatNeverEndsIsANetNotAWaitForever() {
        XCTAssertEqual(D.verdict(facts(100 + D.olderCeiling - 1)), .wait("the sentence before it is still in flight"))
        guard case .giveUp = D.verdict(facts(100 + D.olderCeiling + 1)) else {
            return XCTFail("past the ceiling the take stops waiting")
        }
    }

    func testWisprGoneGivesUpAtOnce() {
        XCTAssertEqual(D.verdict(facts(101) { $0.wisprRunning = false }), .giveUp("Wispr Flow is not running"))
    }

    func testAnOwnTakeEndsOnlyAfterHisStopClosedTheRecording() {
        XCTAssertEqual(D.verdict(facts(101) { $0.ownTake = true }), .wait("the relay's own recording carries it"))
        XCTAssertEqual(D.verdict(facts(101) { $0.ownTake = true; $0.stoppedAt = 100.5 }),
                       .wait("the relay's own recording carries it"))
        XCTAssertEqual(D.verdict(facts(101) { $0.ownTake = true; $0.stoppedAt = 100.5; $0.closedKnown = true }),
                       .endOwnTake)
    }

    func testAnOwnTakeIsNeverReleasedEvenWhenWisprIsFree() {
        XCTAssertNotEqual(D.verdict(facts(101) { $0.ownTake = true; $0.olderDone = true }), .release)
    }

    // MARK: The 📊 trace says how long the countdown could not run

    private func trace() -> AutoLocal.Trace {
        AutoLocal.Trace(budget: DecodeRate.Budget(seconds: 2, unclamped: 2, samples: 30, cap: 4,
                                                  engine: DecodeRate.wisprFlow, audio: 8),
                        localEta: 1)
    }

    func testATakeWisprHadAtOnceSaysNothingAboutDeferral() {
        let t = trace()
        XCTAssertFalse(t.logLine.contains("deferred="))
        XCTAssertTrue(t.json["deferred"] is NSNull)
    }

    func testADeferredTakeNotesTheSecondsItWaited() {
        var t = trace()
        t.deferred = 6.4
        XCTAssertTrue(t.logLine.contains(" deferred=6.40"), t.logLine)
        XCTAssertEqual(t.json["deferred"] as? Double, 6.4)
    }
}
