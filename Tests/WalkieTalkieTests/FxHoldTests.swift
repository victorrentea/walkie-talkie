import XCTest
@testable import WalkieTalkie

/// No other effect while the screen is filmed (2026-11-22).
final class FxHoldTests: XCTestCase {
    func testAFilmHoldsTheEffectsOnPowerToo() {
        XCTAssertEqual(FxHold.why(battery: false, filming: true), .filming)
        XCTAssertEqual(FxHold.why(battery: true, filming: true), .filming)
    }

    func testTheyComeBackWhenTheFilmStops() {
        XCTAssertNil(FxHold.why(battery: false, filming: false))
        XCTAssertEqual(FxHold.why(battery: true, filming: false), .battery)
    }

    /// The wiring, held to the source: the one sync that raises every effect
    /// reads the film, both of the film's edges call it, and the edge is dropped
    /// in any phase (`listen(nil)` leaves one that waits for its message).
    func testTheSyncReadsTheFilmAndBothEdgesOfAFilmSync() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/WalkieTalkie/AppDelegate.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("let fxHeld = FxHold.why(battery: BatteryFx.holdsEffects, filming: film != nil) != nil"))
        XCTAssertTrue(source.contains("if film != nil { edgeDust.drop("))
        let toggle = try XCTUnwrap(source.range(of: "private func toggleFilm() {"))
        let take = try XCTUnwrap(source.range(of: "private func takeFilms() -> [ScreenFilm.Result] {"))
        let abandon = try XCTUnwrap(source.range(of: "private func abandonDictation("))
        let toggleBody = source[toggle.upperBound..<take.lowerBound]
        // The stop with frames, the stop without, the start.
        XCTAssertEqual(toggleBody.components(separatedBy: "syncBorrowedGestures()").count - 1, 3)
        XCTAssertTrue(source[take.upperBound..<abandon.lowerBound].contains("syncBorrowedGestures()"))
    }
}
