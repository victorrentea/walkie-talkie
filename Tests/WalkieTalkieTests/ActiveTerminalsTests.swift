import XCTest
@testable import WalkieTalkie

/// The spawn menu's *Active Terminals* submenu, the pure half (2026-09-23):
/// sessions → rows, the disambiguation of two sessions in one folder, the tick
/// on the bound one, and the empty state.
final class ActiveTerminalsTests: XCTestCase {

    private func session(_ tty: String, _ dir: String, _ title: String? = nil) -> ActiveTerminals.Session {
        ActiveTerminals.Session(tty: tty, directory: dir, title: title)
    }

    func testNoSessionsIsNoRows() {
        XCTAssertEqual(ActiveTerminals.items([], boundTTY: "ttys004"), [])
    }

    func testEmptyStateIsDrawnNotHidden() {
        // The row keeps its place and says why it opens nothing.
        XCTAssertEqual(ActiveTerminals.label, "Active Terminals")
        XCTAssertTrue(ActiveTerminals.emptyLabel.hasPrefix(ActiveTerminals.label))
        XCTAssertTrue(ActiveTerminals.emptyLabel.hasSuffix("none"))
    }

    func testUniqueFoldersShowTheFolderAloneAlphabetically() {
        let items = ActiveTerminals.items([
            session("ttys014", "/Users/v/workspace/petclinic", "✳ petclinic — Spring Security upgrade"),
            session("ttys003", "/Users/v/workspace/victor-effects", "◑ Victor effects fireball animation"),
            session("ttys004", "/Users/v/workspace/walkie-talkie"),
        ], boundTTY: nil)
        XCTAssertEqual(items.map(\.name), ["petclinic", "victor-effects", "walkie-talkie"])
        XCTAssertEqual(items.map(\.tty), ["ttys014", "ttys003", "ttys004"])
        XCTAssertFalse(items.contains { $0.bound })
    }

    func testSharedFolderIsToldApartByTaskThenTTY() {
        let items = ActiveTerminals.items([
            session("ttys009", "/w/human-review", "✳ human-review — Pe CodeCity imagini moduri"),
            session("ttys010", "/w/human-review", "◑ Message body toggle in UI zone"),
            session("ttys013", "/w/human-review", "✳ human-review"),
            session("ttys014", "/w/petclinic", "✳ petclinic — Spring"),
        ], boundTTY: nil)
        XCTAssertEqual(items.map(\.name), [
            "human-review — Message body toggle in UI zone",
            "human-review — Pe CodeCity imagini moduri",
            "human-review · ttys013",
            "petclinic",
        ])
    }

    func testSameFolderSameTaskGetsTheTTYToo() {
        let items = ActiveTerminals.items([
            session("ttys021", "/w/api", "✳ api — Fix tests"),
            session("ttys020", "/w/api", "✳ api — Fix tests"),
        ], boundTTY: nil)
        XCTAssertEqual(items.map(\.name), ["api — Fix tests · ttys020", "api — Fix tests · ttys021"])
    }

    func testTheBoundTerminalIsTickedWhicheverSpellingOfTheTTY() {
        let sessions = [session("ttys004", "/w/walkie-talkie"), session("ttys014", "/w/petclinic")]
        for bound in ["ttys004", "/dev/ttys004"] {
            let items = ActiveTerminals.items(sessions, boundTTY: bound)
            XCTAssertEqual(items.filter(\.bound).map(\.tty), ["ttys004"], "bound as \(bound)")
        }
        XCTAssertEqual(ActiveTerminals.items(sessions, boundTTY: "ttys099").filter(\.bound), [])
    }

    func testTaskOutOfATitle() {
        XCTAssertEqual(ActiveTerminals.task(fromTitle: "✳ petclinic — Spring Security", folder: "petclinic"),
                       "Spring Security")
        XCTAssertEqual(ActiveTerminals.task(fromTitle: "◑ Message body toggle", folder: "human-review"),
                       "Message body toggle")
        XCTAssertNil(ActiveTerminals.task(fromTitle: "✳ human-review", folder: "human-review"))
        XCTAssertNil(ActiveTerminals.task(fromTitle: nil, folder: "x"))
        XCTAssertNil(ActiveTerminals.task(fromTitle: "  ", folder: "x"))
    }
}
