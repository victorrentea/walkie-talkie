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

    /// The dust goes round clockwise without ever turning back, inside the square's
    /// middle, and its ring is not one circle.
    func testTheDustCirclesIrregularlyInsideTheSquare() {
        let side: CGFloat = 230
        var last = -Double.infinity, turned = 0.0, radii: [Double] = []
        var previous: Double?
        for i in 0...2400 {
            let p = CornerTunnel.dustPoint(at: Double(i) / 60, side: side)
            let dx = Double(p.x - side / 2), dy = Double(p.y - side / 2)
            let r = (dx * dx + dy * dy).squareRoot()
            XCTAssertLessThanOrEqual(r, Double(side) * 0.26)
            XCTAssertGreaterThanOrEqual(r, Double(side) * 0.14)
            radii.append(r)
            let a = atan2(dy, dx)
            if let before = previous {
                var step = a - before
                if step < -Double.pi { step += 2 * Double.pi }
                XCTAssertGreaterThan(step, 0)          // y down: a growing angle is clockwise
                turned += step
            }
            previous = a
            last = max(last, turned)
        }
        XCTAssertEqual(turned / (2 * Double.pi), 40 / CornerTunnel.dustLap, accuracy: 0.5)
        XCTAssertGreaterThan(radii.max()! - radii.min()!, Double(side) * 0.05)
    }
}
