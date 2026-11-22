import XCTest
@testable import WalkieTalkie

/// `MicLanes` — a microphone call that never returns fails its sentence at the
/// deadline, takes nothing queued behind it along, and leaves the next take a
/// fresh recorder (2026-11-22: `-[AVAudioEngine inputNode]` never came back at
/// 13:47:48, two sentences sat in `Transcribing...` until a SIGKILL).
final class MicLanesTests: XCTestCase {

    /// A recorder whose open can be made to hang until released.
    final class Stub {
        static var made = 0
        let id: Int
        let hang = DispatchSemaphore(value: 0)
        var hangs = false
        var opened = false
        init() { Stub.made += 1; id = Stub.made }
        func open() -> String? {
            if hangs { hang.wait() }
            opened = true
            return nil
        }
    }

    override func setUp() { Stub.made = 0 }

    private func lanes() -> MicLanes<Stub> { MicLanes<Stub>(label: "test.mic") { Stub() } }

    func testAnOpenThatReturnsIsDoneAndNothingIsAbandoned() {
        let l = lanes()
        let done = expectation(description: "done")
        l.run("open", timeout: 0.5, work: { $0.open() }, done: { why in
            XCTAssertNil(why); done.fulfill()
        }, abandoned: { XCTFail("abandoned") })
        wait(for: [done], timeout: 2)
        XCTAssertEqual(l.stuck, 0)
        XCTAssertEqual(l.abandonedLanes, 0)
        XCTAssertEqual(l.recorder.id, 1)
    }

    func testAnOpenThatNeverReturnsFailsAtTheDeadlineWithEverythingQueuedBehindIt() {
        let l = lanes()
        let first = l.recorder
        first.hangs = true
        var order: [String] = []
        let failed = expectation(description: "the take's open, its stop and the next take's open are all told")
        failed.expectedFulfillmentCount = 3
        let asked = Date()
        // Take 9's open — never returns.
        l.run("open 9", timeout: 0.3, work: { $0.open() }, done: { _ in XCTFail("the open cannot be done") },
              abandoned: { order.append("open 9"); failed.fulfill() })
        // Take 9's stop and take 10's open, queued behind it as on 13:48:20 / 13:48:23.
        l.run("stop 9", timeout: 5, work: { _ in 0 }, done: { _ in XCTFail("ran behind a stuck open") },
              abandoned: { order.append("stop 9"); failed.fulfill() })
        l.run("open 10", timeout: 5, work: { $0.open() }, done: { _ in XCTFail("ran behind a stuck open") },
              abandoned: { order.append("open 10"); failed.fulfill() })
        wait(for: [failed], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(asked), 1.0, "told at the first deadline, not at their own")
        XCTAssertEqual(order, ["open 9", "stop 9", "open 10"])
        XCTAssertEqual(l.stuck, 1)
        XCTAssertEqual(l.abandonedLanes, 1)
        XCTAssertFalse(l.recorder === first, "a fresh recorder took its place")

        // The following take records, on the fresh recorder.
        let next = expectation(description: "the next take opens")
        l.run("open 11", timeout: 0.5, work: { r -> Int in _ = r.open(); return r.id }, done: { id in
            XCTAssertEqual(id, 2); next.fulfill()
        }, abandoned: { XCTFail("abandoned") })
        wait(for: [next], timeout: 2)
        XCTAssertTrue(l.recorder.opened)
        XCTAssertFalse(first.opened)
    }

    func testAStuckOpenThatComesBackLateIsHandedToItsCleanupAndIsNoLongerStuck() {
        let l = lanes()
        let first = l.recorder
        first.hangs = true
        let abandoned = expectation(description: "abandoned")
        let late = expectation(description: "late")
        var skipped = true
        l.run("open", timeout: 0.2, work: { $0.open() }, done: { _ in XCTFail("done") },
              abandoned: { abandoned.fulfill() },
              late: { recorder, why in
                  XCTAssertTrue(recorder === first)
                  XCTAssertNil(why)
                  late.fulfill()
              })
        l.run("stop", timeout: nil, work: { _ in skipped = false }, done: { _ in }, abandoned: {})
        wait(for: [abandoned], timeout: 2)
        XCTAssertEqual(l.stuck, 1)
        first.hang.signal()   // CoreAudio answers after all
        wait(for: [late], timeout: 2)
        let settled = expectation(description: "main ran")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(l.stuck, 0)
        XCTAssertTrue(skipped, "work queued behind the stuck call on the abandoned lane never runs")
    }

    func testThreeStuckOpensSaturate() {
        let l = lanes()
        for i in 1...MicLanes<Stub>.maxStuck {
            XCTAssertFalse(l.saturated)
            l.recorder.hangs = true
            let gone = expectation(description: "abandoned \(i)")
            l.run("open \(i)", timeout: 0.1, work: { $0.open() }, done: { _ in }, abandoned: { gone.fulfill() })
            wait(for: [gone], timeout: 2)
        }
        XCTAssertTrue(l.saturated)
    }

    // MARK: - Through a source: the sentence fails, and nothing is left pending

    private func withHungOpen(_ body: (ElevenLabsSource) -> Void) {
        let open = MicFailure.openTimeout
        MicFailure.openTimeout = 0.4
        MicRecorder.hangOpensForTest = 1
        defer { MicFailure.openTimeout = open; MicRecorder.hangOpensForTest = 0 }
        body(ElevenLabsSource())
    }

    func testASentenceWhoseMicrophoneNeverOpensFailsVisiblyWhileHeIsStillTalking() {
        withHungOpen { source in
            let ended = expectation(description: "ended")
            var end: DictationEnd?
            source.didEnd = { end = $0; ended.fulfill() }
            XCTAssertNil(source.start())
            let take = source.take
            XCTAssertFalse(source.micConfirmedOpen)
            wait(for: [ended], timeout: 3)
            guard case .failed(let why, let audio, _)? = end else { return XCTFail("\(String(describing: end))") }
            XCTAssertEqual(why, MicFailure.didNotOpen)
            XCTAssertNil(audio)
            XCTAssertFalse(source.isRecording)
            XCTAssertFalse(source.isPending(take: take))
            XCTAssertEqual(source.answersPending, 0)
            XCTAssertFalse(source.phase.isWaitingForWords)
        }
    }

    func testAStopBehindAnOpenThatNeverReturnsIsAnsweredOnceAndClearsThePendingTake() {
        withHungOpen { source in
            let ended = expectation(description: "ended")
            var ends: [DictationEnd] = []
            source.didEnd = { ends.append($0); if ends.count == 1 { ended.fulfill() } }
            XCTAssertNil(source.start())
            let take = source.take
            source.stop()   // he stopped before the deadline — the 13:48:20 shape
            XCTAssertTrue(source.isPending(take: take))
            wait(for: [ended], timeout: 3)
            let settled = expectation(description: "nothing more")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
            XCTAssertEqual(ends.count, 1)
            guard case .failed(let why, nil, _)? = ends.first else { return XCTFail("\(ends)") }
            XCTAssertEqual(why, MicFailure.didNotOpen)
            XCTAssertFalse(source.isPending(take: take))
            XCTAssertEqual(source.answersPending, 0)
            XCTAssertFalse(source.phase.isWaitingForWords)
        }
    }

    func testACancelOverAMicrophoneThatHasNotOpenedAnswersAtOnce() {
        withHungOpen { source in
            var ends: [DictationEnd] = []
            source.didEnd = { ends.append($0) }
            XCTAssertNil(source.start())
            source.cancel()
            XCTAssertEqual(ends.count, 1, "answered in the cancel itself, not on the audio queue")
            guard case .cancelled(nil, _)? = ends.first else { return XCTFail("\(ends)") }
            XCTAssertFalse(source.isRecording)
            XCTAssertEqual(source.answersPending, 0)
            let settled = expectation(description: "the deadline passes")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
            wait(for: [settled], timeout: 3)
            XCTAssertEqual(ends.count, 1, "the abandoned lane answers nothing more")
        }
    }
}
