import AppKit
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
        XCTAssertTrue(source.contains("if film != nil { edgeDust.vanish("))
        let toggle = try XCTUnwrap(source.range(of: "private func toggleFilm() {"))
        let take = try XCTUnwrap(source.range(of: "private func takeFilms() -> [ScreenFilm.Result] {"))
        let abandon = try XCTUnwrap(source.range(of: "private func abandonDictation("))
        let toggleBody = source[toggle.upperBound..<take.lowerBound]
        // The stop with frames, the stop without, the start.
        XCTAssertEqual(toggleBody.components(separatedBy: "syncBorrowedGestures()").count - 1, 3)
        XCTAssertTrue(source[take.upperBound..<abandon.lowerBound].contains("syncBorrowedGestures()"))
    }

    // MARK: - At once, not drained (2026-11-23)

    /// A panel that is never ordered front: nothing of these tests reaches the screen.
    private func offscreen<P: NSPanel>(_ type: P.Type = NSPanel.self) -> P {
        P(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless, .nonactivatingPanel],
          backing: .buffered, defer: true)
    }

    /// The edge is `down` in the very call, from every phase — `leaving` too, the one
    /// a drain is running in. No runloop is turned between the call and the asserts.
    func testAFilmTakesTheEdgeDownInTheCallFromEveryPhase() {
        for phase in ["listening", "waiting", "leaving"] {
            for edge in [EdgeDust.Edge.right, .top, .left, .bottom] {
                let dust = EdgeDust()
                let panel = offscreen()
                dust.standForTest(edge, phase: phase, on: panel)
                XCTAssertEqual(dust.phaseName, phase)
                dust.vanish("the screen is being filmed")
                XCTAssertEqual(dust.phaseName, "down", "\(edge.rawValue) from \(phase)")
                XCTAssertTrue(dust.report["edge"] is NSNull)
                XCTAssertTrue(dust.report["frame"] is NSNull, "the panel and its grains are let go")
                XCTAssertFalse(panel.isVisible)
            }
        }
    }

    /// Why `drop` was not enough: it does nothing for an edge already draining.
    func testDropLeavesADrainingEdgeInTheAir() {
        let dust = EdgeDust()
        dust.standForTest(.right, phase: "leaving", on: offscreen())
        dust.drop("the screen is being filmed")
        XCTAssertEqual(dust.phaseName, "leaving")
    }

    /// The ring: out of sight and not `closing` in the call; the sync's
    /// `setActive(false)` that follows starts no collapse.
    func testAFilmTakesTheRingOffInTheCall() {
        let halo = CaretHalo()
        let panel = offscreen(RelayPanel.self)
        panel.alphaValue = 0.5
        halo.standForTest(on: panel)
        halo.vanishForFilm()
        var ring = halo.windowsReport()["ring"] as? [String: Any]
        XCTAssertEqual(ring?["visible"] as? Bool, false)
        XCTAssertEqual(ring?["alpha"] as? Double, 0)
        XCTAssertEqual(ring?["closing"] as? Bool, false)
        halo.setActive(false)
        ring = halo.windowsReport()["ring"] as? [String: Any]
        XCTAssertFalse(halo.live)
        XCTAssertEqual(ring?["closing"] as? Bool, false, "no collapse: `hide` took the cut's short branch")
        XCTAssertEqual(ring?["alpha"] as? Double, 0)
    }

    /// A ring whose collapse is still in the air when the film starts.
    func testAFilmCutsACollapseInTheAir() {
        let halo = CaretHalo()
        let panel = offscreen(RelayPanel.self)
        panel.alphaValue = 0.5
        halo.standForTest(on: panel, collapsing: true)
        halo.vanishForFilm()
        let ring = halo.windowsReport()["ring"] as? [String: Any]
        XCTAssertEqual(ring?["closing"] as? Bool, false)
        XCTAssertEqual(ring?["alpha"] as? Double, 0)
        XCTAssertEqual(ring?["visible"] as? Bool, false)
    }

    /// The film's start cuts before it syncs, the halo first; the film from inside a
    /// wheel drag starts through the same `startFilm`; no dock while a film runs.
    func testTheFilmsStartCutsBeforeItSyncs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/WalkieTalkie/AppDelegate.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func startFilm(area: NSRect?, on screen: NSScreen?) {"))
        let helper = try XCTUnwrap(source.range(of: "private func vanishEffectsForFilm() {"))
        let take = try XCTUnwrap(source.range(of: "private func takeFilms() -> [ScreenFilm.Result] {"))
        let startBody = source[start.upperBound..<helper.lowerBound]
        let cut = try XCTUnwrap(startBody.range(of: "vanishEffectsForFilm()"))
        let sync = try XCTUnwrap(startBody.range(of: "syncBorrowedGestures()"))
        let filmed = try XCTUnwrap(startBody.range(of: "film = started"))
        XCTAssertTrue(filmed.lowerBound < cut.lowerBound && cut.lowerBound < sync.lowerBound)
        let helperBody = String(source[helper.upperBound..<take.lowerBound])
        let halo = try XCTUnwrap(helperBody.range(of: "caretHalo.vanishForFilm()"))
        let edge = try XCTUnwrap(helperBody.range(of: "edgeDust.vanish("))
        let corner = try XCTUnwrap(helperBody.range(of: "cornerTunnel.vanish()"))
        XCTAssertTrue(halo.lowerBound < edge.lowerBound && edge.lowerBound < corner.lowerBound)
        // The wheel drag's film has no start of its own.
        XCTAssertTrue(source.contains("self.startFilm(area: selection.rect, on: selection.screen)"))
        XCTAssertEqual(source.components(separatedBy: "film = started").count - 1, 1)
        XCTAssertTrue(source.contains("if FxHold.why(battery: BatteryFx.holdsEffects, filming: self.film != nil) == nil { self.caretHalo.dock {"))
    }
}
