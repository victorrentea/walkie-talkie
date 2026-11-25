import Foundation
import XCTest
@testable import WalkieTalkie

/// The folder WebKit may read is the page's and the engine's common prefix,
/// cut at the first differing component — not every matching position.
final class HaloPageAncestorTests: XCTestCase {
    func testStopsAtTheFirstDifference() {
        let page = URL(fileURLWithPath: "/Users/v/workspace/voice-halo-2/assets/voice-halo")
        let engine = URL(fileURLWithPath: "/Users/v/workspace/walkie-talkie/assets/milkdrop")
        XCTAssertEqual(HaloPage.commonAncestor(page, engine).path, "/Users/v/workspace")
    }

    func testSiblingsShareTheirParent() {
        let page = URL(fileURLWithPath: "/App/Resources/voice-halo")
        let engine = URL(fileURLWithPath: "/App/Resources/milkdrop")
        XCTAssertEqual(HaloPage.commonAncestor(page, engine).path, "/App/Resources")
    }
}
