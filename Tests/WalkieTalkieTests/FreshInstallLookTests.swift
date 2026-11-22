import XCTest
@testable import WalkieTalkie

/// **What a Mac with no saved preference shows** (2026-11-22). The teaser was filmed
/// in a clean VM and wore the lightning film round the pointer: the dust needs the
/// native engine and an unset `haloEngine` read as `web`. Victor: *"Dar de ce e
/// cercul de fulgere? Nu mai vreau. Default trebuie să fie dust, efectul de dust, și
/// cu marginile de edge. Ia setările actuale din aplicația reală instalată pe Mac-ul
/// fizic și setează-le ca default-uri."* These are the built-in values that made his
/// Mac and a fresh install the same picture; none of them reads a preference.
final class FreshInstallLookTests: XCTestCase {
    /// The dust is a trail, a trail is the native engine's alone — so the unset
    /// engine has to be the native one, or `smoke.isAvailable` is false and every
    /// prompt falls through to a preset and then to the film.
    func testAnUnsetEngineIsTheOneTheDustNeeds() {
        XCTAssertTrue(HaloStyle.smoke.hasTrail, "the reason the engine matters")
        XCTAssertEqual(HaloEngine.unset, .native)
    }

    /// Every prompt and the ⚡ question wear the dust; the plain dictation does not.
    /// `promptsWearDust` is also the one switch behind the edge strips
    /// (`AppDelegate.syncBorrowedGestures` → `EdgeDust.listen`): there is no
    /// preference that turns them off.
    func testEveryPromptWearsTheDustAndItsEdge() {
        XCTAssertTrue(HaloStyle.promptsWearDust, "WT_PROMPT_DUST=0 in the test's environment?")
        for destination in [HaloDestination.caret, .bound, .spawn, .quick] {
            XCTAssertTrue(destination.wearsDust, "\(destination)")
        }
        XCTAssertFalse(HaloDestination.wispr.wearsDust)
        XCTAssertFalse(EdgeDustPictures.all.isEmpty, "an edge needs a picture to draw")
    }

    /// With the dust switched off for a run, an unset caret is still Smoke, and no
    /// destination's unset dress is the lightning film.
    func testNoDestinationFallsBackToTheLightning() {
        XCTAssertEqual(HaloDestination.caret.fallback, .smoke)
        for destination in HaloDestination.allCases {
            XCTAssertNotEqual(destination.fallback, .lightning, "\(destination)")
            XCTAssertTrue(destination.fallback.isOffered, "\(destination)")
        }
    }

    /// The sliders he had moved, as the app's own values: Smoke's size (the solver's
    /// 0.002 is a cloud twice as wide), Ink's force.
    func testTheDustIsHisSize() {
        XCTAssertEqual(Double(FluidTuner.builtIn[6]?["radius"] ?? 0), 0.0011964, accuracy: 0.0000001)
        XCTAssertEqual(Double(FluidTuner.builtIn[5]?["force"] ?? 0), 7401.27, accuracy: 0.01)
        // every built-in names a real knob, inside its slider's range
        for (_, knobs) in FluidTuner.builtIn {
            for (key, value) in knobs {
                guard let knob = FluidTuner.knobs.first(where: { $0.key == key }) else { XCTFail("no knob \(key)"); continue }
                XCTAssertTrue(knob.range.contains(Double(value)), "\(key) = \(value)")
            }
        }
    }

    /// No live captions from the local model until he ticks the row (2026-11-22, Victor:
    /// *"subtitrarea live: da, off by default"*); a saved value, either way, still wins.
    func testLocalLiveCaptionsAreOffUntilTicked() {
        let name = "local-live-default-test"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        XCTAssertFalse(LocalLive.unset)
        XCTAssertFalse(LocalLive.on(defaults: d, environment: [:]))
        XCTAssertTrue(LocalLive.on(defaults: d, environment: ["WT_LOCAL_LIVE": "1"]))
        d.set(true, forKey: LocalLive.defaultsKey)
        XCTAssertTrue(LocalLive.on(defaults: d, environment: [:]))
        XCTAssertFalse(LocalLive.on(defaults: d, environment: ["WT_LOCAL_LIVE": "0"]))
        d.set(false, forKey: LocalLive.defaultsKey)
        XCTAssertFalse(LocalLive.on(defaults: d, environment: [:]))
        d.removePersistentDomain(forName: name)
    }

    /// The voice the effects hear, and the corner's wheel.
    func testTheVoiceFilterAndTheCorner() {
        XCTAssertEqual(HaloVoice.unset, .spectrum)
        XCTAssertEqual(CornerTunnel.Dress.allCases.first, .dust)
    }
}
