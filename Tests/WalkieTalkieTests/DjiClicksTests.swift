import XCTest
@testable import WalkieTalkie

final class DjiClicksTests: XCTestCase {
    func testALonePressIsTheFirst() {
        XCTAssertEqual(DjiClicks.verdict(gap: 30, waiting: false), .first)
    }
    func testASecondPressInsideTheWindowIsTheDouble() {
        XCTAssertEqual(DjiClicks.verdict(gap: 0.25, waiting: true), .second)
    }
    func testABounceIsDroppedWhetherOrNotOneIsWaiting() {
        XCTAssertEqual(DjiClicks.verdict(gap: 0.02, waiting: true), .bounce)
        XCTAssertEqual(DjiClicks.verdict(gap: 0.02, waiting: false), .bounce)
    }
    func testAPressAfterTheFirstWasActedOnStartsAgain() {
        XCTAssertEqual(DjiClicks.verdict(gap: 0.3, waiting: false), .first)
        XCTAssertEqual(DjiClicks.verdict(gap: 0.6, waiting: true), .first)
    }
}
