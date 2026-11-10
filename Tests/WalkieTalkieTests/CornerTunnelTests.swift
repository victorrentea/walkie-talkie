import XCTest
@testable import WalkieTalkie

final class CornerTunnelTests: XCTestCase {
    func testTheSquareSitsOnTheAtomsCentre() {
        let atom = NSRect(x: 28, y: 800, width: PromptAtom.side, height: PromptAtom.side)
        let f = CornerTunnel.frame(onAtom: atom)
        XCTAssertEqual(f.width, CornerTunnel.side)
        XCTAssertEqual(f.midX, atom.midX, accuracy: 1)
        XCTAssertEqual(f.midY, atom.midY, accuracy: 1)
    }

    func testTheSpeedIsFittedAndClamped() {
        XCTAssertEqual(CornerTunnel.speed(takeSeconds: 10, predicted: 2), 5)
        XCTAssertEqual(CornerTunnel.speed(takeSeconds: 1, predicted: 3), 1)      // never slower than real time
        XCTAssertEqual(CornerTunnel.speed(takeSeconds: 60, predicted: 1), 8)     // never past 8×
    }

    func testTheTakeIsReadBackwardsAndLoops() {
        let take: [Float] = (0..<16000).map { Float($0) }
        // At t = 0 every sample is the take's last one.
        XCTAssertEqual(CornerTunnel.window(of: take, elapsed: 0, speed: 1, count: 4), [15999, 15999, 15999, 15999])
        // A quarter second in, at 1×: the newest sample is 4000 from the end.
        XCTAssertEqual(CornerTunnel.window(of: take, elapsed: 0.25, speed: 1, count: 1).first, 11999)
        // Past the start it comes round again.
        XCTAssertEqual(CornerTunnel.window(of: take, elapsed: 1.25, speed: 1, count: 1).first, 11999)
    }
}
