import Foundation
import XCTest
@testable import WalkieTalkie

/// 2026-11-25 (Fable review, slice 04, finding 1): Wispr's pid is kept instead of
/// asked of LaunchServices on the main thread every 0.5 s.
final class CachedProcessTests: XCTestCase {
    private let born = Date(timeIntervalSince1970: 1_000)

    func testFirstReadAsks() {
        let s = CachedProcessState(negativeTTL: 2)
        XCTAssertNil(s.answer(now: 0, generation: 0, liveStart: { _ in self.born }))
    }

    func testALivePidWithItsStartTimeStands() {
        var s = CachedProcessState(negativeTTL: 2)
        s.record(pid: 42, start: born, now: 0, generation: 0)
        XCTAssertEqual(s.answer(now: 3600, generation: 0, liveStart: { _ in self.born }), 42)
    }

    func testADeadOrReusedPidIsAskedAgain() {
        var s = CachedProcessState(negativeTTL: 2)
        s.record(pid: 42, start: born, now: 0, generation: 0)
        XCTAssertNil(s.answer(now: 1, generation: 0, liveStart: { _ in nil }))
        XCTAssertNil(s.answer(now: 1, generation: 0, liveStart: { _ in self.born.addingTimeInterval(5) }))
    }

    func testNotRunningStandsForTheTTLOnly() {
        var s = CachedProcessState(negativeTTL: 2)
        s.record(pid: 0, start: nil, now: 10, generation: 0)
        XCTAssertEqual(s.answer(now: 11.9, generation: 0, liveStart: { _ in self.born }), 0)
        XCTAssertNil(s.answer(now: 12, generation: 0, liveStart: { _ in self.born }))
    }

    func testALaunchOrQuitAsksAgain() {
        var s = CachedProcessState(negativeTTL: 2)
        s.record(pid: 0, start: nil, now: 10, generation: 3)
        XCTAssertNil(s.answer(now: 10.1, generation: 4, liveStart: { _ in self.born }))
        s.record(pid: 42, start: born, now: 10, generation: 3)
        XCTAssertNil(s.answer(now: 10.1, generation: 4, liveStart: { _ in self.born }))
    }

    func testTheCacheScansOnceWhileThePidLives() {
        var scans = 0
        var alive = true
        let c = CachedProcess(negativeTTL: 60, liveStart: { _ in alive ? self.born : nil }) {
            scans += 1
            return 42
        }
        XCTAssertEqual(c.pid, 42)
        XCTAssertEqual(c.pid, 42)
        XCTAssertEqual(scans, 1)
        alive = false
        XCTAssertEqual(c.pid, 0, "a pid found dead is not an answer")
        XCTAssertEqual(scans, 2)
        XCTAssertEqual(c.pid, 0)
        XCTAssertEqual(scans, 2, "not running stands for the TTL")
        CachedProcess.invalidateAll()
        alive = true
        XCTAssertEqual(c.pid, 42)
        XCTAssertEqual(scans, 3)
    }

    func testTheRealProcessIsKnownToTheKernel() {
        let me = getpid()
        XCTAssertEqual(CachedProcess(scan: { me }).pid, me)
    }
}
