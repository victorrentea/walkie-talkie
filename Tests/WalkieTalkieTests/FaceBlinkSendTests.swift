import Foundation
import XCTest
@testable import WalkieTalkie

/// A blink helper that stops reading must not wedge `FaceRead`'s queue: a frame
/// the pipe will not take is given up within its deadline (2026-11-25).
final class FaceBlinkSendTests: XCTestCase {
    private func pipePair() -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(pipe(&fds), 0)
        _ = fcntl(fds[1], F_SETFL, fcntl(fds[1], F_GETFL) | O_NONBLOCK)
        return (fds[0], fds[1])
    }

    func testAFrameThatFitsIsSent() {
        let p = pipePair(); defer { close(p.read); close(p.write) }
        XCTAssertTrue(FaceBlink.send(Data(count: 50_000), to: p.write, within: 0.2))
    }

    func testAReaderThatStoppedIsGivenUpOn() {
        let p = pipePair(); defer { close(p.read); close(p.write) }
        _ = FaceBlink.send(Data(count: 50_000), to: p.write, within: 0.2)  // the pipe is now nearly full
        let start = CFAbsoluteTimeGetCurrent()
        XCTAssertFalse(FaceBlink.send(Data(count: 50_000), to: p.write, within: 0.2))
        XCTAssertLessThan(CFAbsoluteTimeGetCurrent() - start, 1.0)
    }
}
