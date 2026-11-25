import Foundation
import XCTest
@testable import WalkieTalkie

/// `ElevenLabsSource.config` is re-read on main (menu builds) while uploads read
/// it on other queues; the table is swapped whole under a lock (2026-11-25).
/// Before, this loop was a data race on a Swift `Dictionary`.
final class ElevenLabsConfigTests: XCTestCase {
    func testReloadsAndReadsFromManyThreadsAtOnce() {
        DispatchQueue.concurrentPerform(iterations: 2_000) { i in
            if i % 2 == 0 { _ = ElevenLabsSource.freshValue("WT_ELEVEN_MODEL") }
            else { _ = ElevenLabsSource.config["WT_ELEVEN_MODEL"]; _ = ElevenLabsSource.model }
        }
        let settled = ElevenLabsSource.config
        _ = ElevenLabsSource.freshValue("WT_ELEVEN_MODEL")
        XCTAssertEqual(ElevenLabsSource.config, settled, "a reload published a different table")
    }
}
