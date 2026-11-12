import XCTest
@testable import WalkieTalkie

/// `FaceRead.judge` and `Baseline.learn` — the face's tag is a ratio to his own
/// face, and nothing at all until it has learned it (2026-11-12).
final class FaceReadTests: XCTestCase {

    private func usual(_ t: Double) -> FaceRead.Frame {
        FaceRead.Frame(t: t, face: true, size: 0.30, eye: 0.30, mouthOpen: 0.05, mouthWide: 0.40, cornerLift: 0.0)
    }

    private var learned: FaceRead.Baseline {
        var b = FaceRead.Baseline()
        for _ in 0..<FaceRead.Baseline.minTakes { b.learn((0..<8).map { usual(Double($0) / 2) }) }
        return b
    }

    func testNothingIsSaidBeforeTheBaselineIsLearned() {
        var b = FaceRead.Baseline()
        b.learn((0..<8).map { usual(Double($0) / 2) })
        let away = (0..<8).map { FaceRead.Frame(t: Double($0) / 2, face: false) }
        XCTAssertNil(FaceRead.judge(away, base: b).tag)
    }

    func testHisUsualFaceGetsNoTag() {
        XCTAssertNil(FaceRead.judge((0..<10).map { usual(Double($0) / 2) }, base: learned).tag)
    }

    func testASmileAgainstHisOwnMouth() {
        var frames = (0..<10).map { usual(Double($0) / 2) }
        for i in 0..<5 { frames[i].mouthWide = 0.47; frames[i].cornerLift = 0.09 }
        let r = FaceRead.judge(frames, base: learned)
        XCTAssertTrue(r.smiled)
        XCTAssertEqual(r.tag, "[face: 🙂 smiled while saying it]")
    }

    func testOneWideFrameIsNotASmile() {
        var frames = (0..<10).map { usual(Double($0) / 2) }
        frames[3].mouthWide = 0.5; frames[3].cornerLift = 0.1
        XCTAssertFalse(FaceRead.judge(frames, base: learned).smiled)
    }

    func testClosedEyesOrAYawnAreTired() {
        var closed = (0..<10).map { usual(Double($0) / 2) }
        for i in 0..<4 { closed[i].eye = 0.1 }
        XCTAssertTrue(FaceRead.judge(closed, base: learned).tired)

        var yawn = (0..<10).map { usual(Double($0) / 2) }
        yawn[4].mouthOpen = 0.5; yawn[5].mouthOpen = 0.55
        XCTAssertTrue(FaceRead.judge(yawn, base: learned).tired)

        var blink = (0..<10).map { usual(Double($0) / 2) }
        blink[2].eye = 0.05
        XCTAssertFalse(FaceRead.judge(blink, base: learned).tired, "one blink is not tiredness")
    }

    func testAwayFromTheScreen() {
        var gone = (0..<10).map { FaceRead.Frame(t: Double($0) / 2, face: false) }
        gone[0] = usual(0)
        XCTAssertTrue(FaceRead.judge(gone, base: learned).away)

        let far = (0..<10).map { i -> FaceRead.Frame in var f = usual(Double(i) / 2); f.size = 0.12; return f }
        let r = FaceRead.judge(far, base: learned)
        XCTAssertTrue(r.away)
        XCTAssertEqual(r.tag, "[face: 🚶 away from the screen]")
    }

    func testTooFewFramesSayNothing() {
        XCTAssertNil(FaceRead.judge([FaceRead.Frame(t: 0, face: false)], base: learned).tag)
    }

    func testATakeWithoutHisFaceTeachesNothing() {
        var b = learned
        let before = b
        b.learn((0..<8).map { FaceRead.Frame(t: Double($0), face: $0 == 0) })
        XCTAssertEqual(b, before)
    }
}
