import XCTest
@testable import WalkieTalkie

/// The prompt's edge (2026-11-16, `EdgeDust`) and the dust's flight to the corner.
final class EdgeDustTests: XCTestCase {
    func testTheTopStripRunsTheWholeTopEdgeAndTheRightOneTheWholeRight() {
        let screen = NSRect(x: 100, y: 50, width: 1728, height: 1117)
        let top = EdgeDust.frame(.top, on: screen, thickness: 110)
        XCTAssertEqual(top.minX, screen.minX); XCTAssertEqual(top.width, screen.width)
        XCTAssertEqual(top.maxY, screen.maxY); XCTAssertEqual(top.height, 220)       // room for the swell
        let right = EdgeDust.frame(.right, on: screen, thickness: 110)
        XCTAssertEqual(right.maxX, screen.maxX); XCTAssertEqual(right.width, 220)
        XCTAssertEqual(right.minY, screen.minY); XCTAssertEqual(right.height, screen.height)
    }

    func testTheDustFliesFromThePointerToTheWheelAndStaysThere() {
        let f = (from: NSPoint(x: 900, y: 300), to: NSPoint(x: 140, y: 950), at: 100.0)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 99), f.from)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100), f.from)
        let mid = CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime / 2)
        XCTAssertEqual(mid.x, 520, accuracy: 0.5); XCTAssertEqual(mid.y, 625, accuracy: 0.5)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 100 + CaretHalo.cornerFlightTime), f.to)
        XCTAssertEqual(CaretHalo.cornerFlightPoint(f, at: 200), f.to)
    }

    /// Wherever it comes from, the dust meets the ring going the ring's way (clockwise).
    func testTheDustJoinsTheRingOnItsTangent() {
        let centre = NSPoint(x: 140, y: 950), r: CGFloat = 46
        for from in [NSPoint(x: 900, y: 300), NSPoint(x: 1600, y: 1000), NSPoint(x: 150, y: 100), NSPoint(x: 20, y: 500), NSPoint(x: 800, y: 1100)] {
            let a = CaretHalo.entryAngle(from: from, centre: centre, radius: r)
            // the entry point, and the ring's point a moment later (clockwise = the angle grows, y down)
            let p = NSPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y - r * CGFloat(sin(a)))
            let next = NSPoint(x: centre.x + r * CGFloat(cos(a + 0.05)), y: centre.y - r * CGFloat(sin(a + 0.05)))
            let fx = p.x - from.x, fy = p.y - from.y, tx = next.x - p.x, ty = next.y - p.y
            let cosine = (fx * tx + fy * ty) / (hypot(fx, fy) * hypot(tx, ty))
            XCTAssertGreaterThan(cosine, 0.99, "from \(from): the ring turns away from the flight")
        }
        // The turned path starts at the entry point.
        let start = CaretHalo.wheelPoint(at: 0, centre: centre, entry: 1.2)
        XCTAssertEqual(atan2(Double(centre.y - start.y), Double(start.x - centre.x)), 1.2, accuracy: 0.001)
    }

    // MARK: - The pointer's screen (2026-11-22)

    /// The Retina, an external display to its left (negative x) and one below it (negative y).
    private let retina = NSRect(x: 0, y: 0, width: 1728, height: 1117)
    private let leftOne = NSRect(x: -2560, y: -200, width: 2560, height: 1440)
    private let below = NSRect(x: 100, y: -1080, width: 1920, height: 1080)

    func testTheQuestionsEdgeIsHeldOnlyWhileItsAnswerIsBeingWritten() {
        XCTAssertTrue(EdgeDust.questionHolds(.left, shown: true, writing: true))
        XCTAssertFalse(EdgeDust.questionHolds(.left, shown: true, writing: false))   // reviewed: it drains out
        XCTAssertFalse(EdgeDust.questionHolds(.left, shown: false, writing: true))
        XCTAssertFalse(EdgeDust.questionHolds(.right, shown: true, writing: true))
    }

    func testTheEdgeIsOnTheScreenThePointerIsOn() {
        let all = [retina, leftOne, below]
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: 800, y: 500), of: all), retina)
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: -1, y: 500), of: all), leftOne)
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: -2560, y: -200), of: all), leftOne)
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: 900, y: -1), of: all), below)
        // The seam belongs to one screen only: x = 0 is the Retina's first column.
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: 0, y: 500), of: all), retina)
    }

    func testAPointerOnNoScreenTakesTheNearestAndTheLidClosedLeavesTheOthers() {
        // The top row as AppKit reports it (y == maxY), and the gap under the Retina's left end.
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: 800, y: 1117), of: [retina, leftOne, below]), retina)
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: 40, y: -300), of: [retina, leftOne, below]), below)
        // Lid closed: the built-in is not in the list, the pointer is on an external one.
        XCTAssertEqual(EdgeDust.screen(under: NSPoint(x: -100, y: 0), of: [leftOne, below]), leftOne)
        XCTAssertNil(EdgeDust.screen(under: .zero, of: []))
    }

    func testTheStripIsBuiltForTheScreenItMovesTo() {
        // The caret's depth is a share of that screen's height; the frame hugs that screen's edge.
        XCTAssertEqual(EdgeDust.thickness(.bottom, screenHeight: 1440), EdgeDust.bottomThickness(1440))
        XCTAssertNotEqual(EdgeDust.thickness(.bottom, screenHeight: 1440), EdgeDust.thickness(.bottom, screenHeight: 1117))
        XCTAssertEqual(EdgeDust.thickness(.top, screenHeight: 1440), EdgeDust.topThickness)
        let right = EdgeDust.frame(.right, on: leftOne, thickness: 110)
        XCTAssertEqual(right.maxX, 0); XCTAssertEqual(right.minY, -200); XCTAssertEqual(right.height, 1440)
        let bottom = EdgeDust.frame(.bottom, on: below, thickness: 100)
        XCTAssertEqual(bottom.minY, -1080); XCTAssertEqual(bottom.minX, 100); XCTAssertEqual(bottom.width, 1920)
    }

    func testTheEdgeMovesOnlyAfterThePointerStayedOnTheOtherScreen() {
        var follow = EdgeDust.ScreenFollow()
        XCTAssertNil(follow.step(shown: retina, pointer: retina, now: 10))
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 10.1))       // just crossed
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 10.3))       // 0.2 s there
        XCTAssertEqual(follow.step(shown: retina, pointer: leftOne, now: 10.4), leftOne)
        // Moved: the same answer is not given twice.
        XCTAssertNil(follow.step(shown: leftOne, pointer: leftOne, now: 10.5))
    }

    func testABrushOverTheSeamOrAScreenCrossedOnTheWayMovesNothing() {
        var follow = EdgeDust.ScreenFollow()
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 0))
        XCTAssertNil(follow.step(shown: retina, pointer: retina, now: 0.2))         // back: forgotten
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 0.4))        // the dwell starts again
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 0.6))
        XCTAssertEqual(follow.step(shown: retina, pointer: leftOne, now: 0.75), leftOne)
        // Through a middle screen to a third: each one's dwell is its own.
        follow = EdgeDust.ScreenFollow()
        XCTAssertNil(follow.step(shown: retina, pointer: below, now: 0))
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 0.25))
        XCTAssertNil(follow.step(shown: retina, pointer: leftOne, now: 0.5))
        XCTAssertEqual(follow.step(shown: retina, pointer: leftOne, now: 0.56), leftOne)
        // No screen under the pointer (none attached for a moment): stay.
        XCTAssertNil(follow.step(shown: retina, pointer: nil, now: 5))
    }

    func testOnlyTheThreePromptsAreDressedAlike() {
        XCTAssertEqual(HaloDestination.allCases.filter(\.isPrompt), [.caret, .bound, .spawn])
    }

    /// The ⚡ marks' filming knob (2026-11-22): 1 unless asked, the environment over the
    /// saved value, kept within 0.5…3.
    func testTheMarksBoostIsOneUnlessAskedAndStaysInItsRange() {
        let name = "marks-boost-test"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: [:]), 1)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: ["WT_MARKS_BOOST": "2"]), 2)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: ["WT_MARKS_BOOST": "9"]), 3)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: ["WT_MARKS_BOOST": "0"]), 0.5)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: ["WT_MARKS_BOOST": "lots"]), 1)
        d.set(1.6, forKey: "edgeDust.marksBoost")
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: [:]), 1.6, accuracy: 0.001)
        XCTAssertEqual(EdgeDustV7.marksBoost(defaults: d, environment: ["WT_MARKS_BOOST": "2.5"]), 2.5)
        d.removePersistentDomain(forName: name)
    }

    /// The offline renderer hands the shader its own copy of the uniforms: a field added to
    /// one and not the other shifts every value after it.
    func testTheOfflineRendererCarriesTheShadersUniforms() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shader = try String(contentsOf: root.appendingPathComponent("Sources/WalkieTalkie/EdgeDustV7.swift"), encoding: .utf8)
        let tool = try String(contentsOf: root.appendingPathComponent("tools/render-edge-dust.swift"), encoding: .utf8)
        let block = try XCTUnwrap(shader.range(of: "struct V7U {").flatMap { open in
            shader.range(of: "};", range: open.upperBound..<shader.endIndex).map { String(shader[open.upperBound..<$0.lowerBound]) }
        })
        let fields = block.split(separator: "\n").compactMap { line -> String? in
            let words = line.split(separator: ";").first?.split(separator: " ") ?? []
            return words.count == 2 ? String(words[1]) : nil
        }
        XCTAssertEqual(fields, ["size", "time", "edge", "level", "intensity", "scale", "seed", "stop", "boost"])
        let mine = try XCTUnwrap(tool.range(of: "struct U {").flatMap { open in
            tool.range(of: "}", range: open.upperBound..<tool.endIndex).map { String(tool[open.upperBound..<$0.lowerBound]) }
        })
        XCTAssertEqual(mine.split(separator: ";").compactMap { $0.split(separator: ":").first?.split(separator: " ").last.map(String.init) }, fields)
    }
}
