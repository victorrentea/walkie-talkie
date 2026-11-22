import XCTest
@testable import WalkieTalkie

/// 🧠 🔽 → over a prompt: Opus / high → Fable / medium → Sonnet / high → none (2026-11-22).
final class ModelSwitchTests: XCTestCase {

    func testFromOpusTheFlicksGoFableSonnetNone() {
        var marked: ModelPick?
        marked = ModelSwitch.flick(marked: marked, session: .opusHigh)
        XCTAssertEqual(marked, .fableMedium)
        marked = ModelSwitch.flick(marked: marked, session: .opusHigh)
        XCTAssertEqual(marked, .sonnetHigh)
        marked = ModelSwitch.flick(marked: marked, session: .opusHigh)
        XCTAssertNil(marked, "back at the session's own: the mark is taken off")
    }

    func testASessionAlreadyOnFableStartsFromThere() {
        XCTAssertEqual(ModelSwitch.flick(marked: nil, session: .fableMedium), .sonnetHigh)
        XCTAssertEqual(ModelSwitch.flick(marked: .sonnetHigh, session: .fableMedium), .opusHigh)
        XCTAssertNil(ModelSwitch.flick(marked: .opusHigh, session: .fableMedium))
    }

    func testWhatEachOneSends() {
        XCTAssertEqual(ModelPick.opusHigh.commands, ["/model opus", "/effort high"])
        XCTAssertEqual(ModelPick.fableMedium.commands, ["/model fable", "/effort medium"])
        XCTAssertEqual(ModelPick.sonnetHigh.commands, ["/model sonnet", "/effort high"])
        XCTAssertEqual(ModelPick.sonnetHigh.cliFlags, "--model sonnet --effort high")
        XCTAssertEqual(ModelPick.sonnetHigh.label, "Sonnet/high")
    }
}
