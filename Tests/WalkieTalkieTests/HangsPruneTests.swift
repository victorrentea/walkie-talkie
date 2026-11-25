import XCTest
@testable import WalkieTalkie

/// `hangs/` is capped (2026-11-25, the Fable review: 432 samples, nothing pruned).
final class HangsPruneTests: XCTestCase {

    func testTheOldestGoSoTheNextSampleMakesTheCap() {
        let names = ["hang-2026-09-26-13-17-55.txt", "hang-2026-09-24-18-02-13-test-stall.txt",
                     "hang-2026-11-25-08-00-00.txt", "notes.md", "hang-2026-10-01-10-00-00.txt"]
        XCTAssertEqual(HotkeyTap.hangsToPrune(names, keep: 3),
                       ["hang-2026-09-24-18-02-13-test-stall.txt", "hang-2026-09-26-13-17-55.txt"])
    }

    func testUnderTheCapNothingGoes() {
        XCTAssertEqual(HotkeyTap.hangsToPrune(["hang-a.txt", "hang-b.txt"], keep: 50), [])
        XCTAssertEqual(HotkeyTap.hangsToPrune([], keep: 50), [])
    }
}
