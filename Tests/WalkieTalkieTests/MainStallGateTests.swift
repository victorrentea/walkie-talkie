import XCTest
@testable import WalkieTalkie

final class MainStallGateTests: XCTestCase {

    func testHealthyMainThreadNeverOpens() {
        var gate = MainStallGate()
        XCTAssertEqual(gate.evaluate(now: 100.4, lastBeat: 100, buttonsDown: false), .unchanged)
        XCTAssertEqual(gate.evaluate(now: 102.9, lastBeat: 100, buttonsDown: true), .unchanged)
        XCTAssertFalse(gate.isOpen)
    }

    func testOpensPastThresholdOnce() {
        var gate = MainStallGate()
        XCTAssertEqual(gate.evaluate(now: 103.1, lastBeat: 100, buttonsDown: false), .opened)
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(gate.evaluate(now: 200, lastBeat: 100, buttonsDown: false), .unchanged)
        XCTAssertTrue(gate.isOpen)
    }

    func testClosesWhenTheBeatReturns() {
        var gate = MainStallGate()
        _ = gate.evaluate(now: 104, lastBeat: 100, buttonsDown: false)
        XCTAssertEqual(gate.evaluate(now: 130.5, lastBeat: 130, buttonsDown: false), .closed(after: 30.5))
        XCTAssertFalse(gate.isOpen)
    }

    /// A press handed through while frozen keeps its release handed through.
    func testStaysOpenWhileAButtonIsDown() {
        var gate = MainStallGate()
        _ = gate.evaluate(now: 104, lastBeat: 100, buttonsDown: true)
        XCTAssertEqual(gate.evaluate(now: 130.25, lastBeat: 130, buttonsDown: true), .unchanged)
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(gate.evaluate(now: 130.75, lastBeat: 130, buttonsDown: false), .closed(after: 30.75))
    }
}
