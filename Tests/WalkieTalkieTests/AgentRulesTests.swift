import XCTest
@testable import WalkieTalkie

/// The marked block the installer keeps in each harness's global instructions (2026-11-12).
final class AgentRulesTests: XCTestCase {

    func testAnEmptyFileGetsTheBlockAlone() {
        let out = AgentRules.withBlock("")
        XCTAssertTrue(out.hasPrefix(AgentRules.beginMarker + "\n"))
        XCTAssertTrue(out.hasSuffix(AgentRules.endMarker + "\n"))
        XCTAssertTrue(out.contains("walkie-reply"))
        XCTAssertTrue(out.contains("walkie-dict add"))
    }

    func testTheBlockGoesUnderWhatIsAlreadyThere() {
        let out = AgentRules.withBlock("# My rules\n\n- one\n\n\n")
        XCTAssertTrue(out.hasPrefix("# My rules\n\n- one\n\n" + AgentRules.beginMarker))
    }

    func testInstallingTwiceChangesNothing() {
        let once = AgentRules.withBlock("# My rules\n")
        XCTAssertEqual(AgentRules.withBlock(once), once)
    }

    func testAnOlderVersionIsReplacedInPlace() {
        let old = "# Top\n\n<!-- walkie-talkie rules v0 -->\nold text\n\(AgentRules.endMarker)\n\n# Bottom\n"
        let out = AgentRules.withBlock(old)
        XCTAssertFalse(out.contains("old text"))
        XCTAssertTrue(out.hasPrefix("# Top\n\n" + AgentRules.beginMarker))
        XCTAssertTrue(out.hasSuffix(AgentRules.endMarker + "\n\n# Bottom\n"))
        XCTAssertEqual(out.components(separatedBy: AgentRules.beginPrefix).count, 2)
    }

    func testTheTextNamesItsVersion() {
        XCTAssertTrue(AgentRules.text.contains("walkie-talkie rules v\(AgentRules.version)"))
    }

    func testTheBlockSaysItsVersion() {
        XCTAssertEqual(AgentRules.blockVersion(in: AgentRules.withBlock("# x\n")), AgentRules.version)
        XCTAssertEqual(AgentRules.blockVersion(in: "<!-- walkie-talkie rules v12 -->\n"), 12)
        XCTAssertNil(AgentRules.blockVersion(in: "# nothing here\n"))
    }

    func testOnlyAreasAndFilmsNeedTheNewestRules() {
        XCTAssertEqual(AgentRules.needed(areasOrFilms: false), 2)
        XCTAssertEqual(AgentRules.needed(areasOrFilms: true), AgentRules.version)
    }

    func testTheReplyNudgeRidesOnlyUnderAQuestion() {
        XCTAssertEqual(AgentRules.nudged("why?\n\n[dictated]", words: "why?"),
                       "why?\n\n[dictated]\n" + AgentRules.replyNudge)
        XCTAssertEqual(AgentRules.nudged("do it\n\n[dictated]", words: "do it"), "do it\n\n[dictated]")
        XCTAssertLessThanOrEqual(AgentRules.replyNudge.count, 30)
    }
}
