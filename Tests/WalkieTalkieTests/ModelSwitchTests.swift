import XCTest
@testable import WalkieTalkie

/// 🧠 🔽 → over a prompt: Opus / high → Fable / medium → Sonnet / high → none (2026-11-22);
/// only a moved ring sends anything, and only this very session's switch is remembered (2026-11-25).
final class ModelSwitchTests: XCTestCase {
    private let tty = "/dev/ttys042"
    private let claude = TerminalBinding.TTYOwner(pid: 4242, started: 1_790_000_000)

    override func setUp() { super.setUp(); ModelSwitch.forgetAll() }
    override func tearDown() { ModelSwitch.forgetAll(); super.tearDown() }

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

    func testAnUnknownSessionsRingStartsAtOpusAndOffersAllThree() {
        var marked: ModelPick?
        marked = ModelSwitch.flick(marked: marked, session: nil)
        XCTAssertEqual(marked, .opusHigh, "nothing assumed: Opus / high is a real pick, not skipped")
        marked = ModelSwitch.flick(marked: marked, session: nil)
        XCTAssertEqual(marked, .fableMedium)
        marked = ModelSwitch.flick(marked: marked, session: nil)
        XCTAssertEqual(marked, .sonnetHigh)
        XCTAssertNil(ModelSwitch.flick(marked: marked, session: nil), "round to its own: nothing sent")
    }

    func testNoPickInjectsNothing() {
        XCTAssertEqual(ModelSwitch.commands(for: nil), [])
        // Even right after a switch of that very session: a sentence whose ring was not moved
        // re-sends nothing.
        ModelSwitch.remember(.fableMedium, tty: tty, session: claude)
        XCTAssertEqual(ModelSwitch.commands(for: nil), [])
    }

    func testAPickInjectsModelAndEffort() {
        XCTAssertEqual(ModelSwitch.commands(for: .fableMedium), ["/model fable", "/effort medium"])
        XCTAssertEqual(ModelSwitch.commands(for: .opusHigh), ["/model opus", "/effort high"])
    }

    func testTheSameSessionIsKnown() {
        ModelSwitch.remember(.fableMedium, tty: tty, session: claude)
        XCTAssertTrue(ModelSwitch.knows(tty: tty))
        XCTAssertEqual(ModelSwitch.current(tty: tty, session: claude), .fableMedium)
    }

    func testAReusedTTYOrARestartedClaudeIsUnknown() {
        ModelSwitch.remember(.fableMedium, tty: tty, session: claude)
        let stranger = TerminalBinding.TTYOwner(pid: 5151, started: 1_790_000_900)
        XCTAssertNil(ModelSwitch.current(tty: tty, session: stranger))
        XCTAssertNil(ModelSwitch.current(tty: tty, session: nil), "no claude on the tty now")
        XCTAssertNil(ModelSwitch.current(tty: "/dev/ttys043", session: claude))
        XCTAssertEqual(ModelSwitch.flick(marked: nil, session: ModelSwitch.current(tty: tty, session: stranger)),
                       .opusHigh)
    }

    func testAfterARestartNothingIsAssumed() {
        // A fresh app run has an empty memory: no session has a known model.
        XCTAssertFalse(ModelSwitch.knows(tty: tty))
        XCTAssertNil(ModelSwitch.current(tty: tty, session: claude))
        XCTAssertNil(ModelSwitch.current(tty: nil, session: nil), "a spawn has no session yet")
    }

    func testAPickThatCannotBeTiedToItsSessionIsNotKept() {
        ModelSwitch.remember(.fableMedium, tty: tty, session: claude)
        ModelSwitch.remember(.sonnetHigh, tty: tty, session: nil)
        XCTAssertFalse(ModelSwitch.knows(tty: tty))
    }

    func testWhatEachOneSends() {
        XCTAssertEqual(ModelPick.opusHigh.commands, ["/model opus", "/effort high"])
        XCTAssertEqual(ModelPick.fableMedium.commands, ["/model fable", "/effort medium"])
        XCTAssertEqual(ModelPick.sonnetHigh.commands, ["/model sonnet", "/effort high"])
        XCTAssertEqual(ModelPick.sonnetHigh.cliFlags, "--model sonnet --effort high")
        XCTAssertEqual(ModelPick.sonnetHigh.label, "Sonnet/high")
    }
}
