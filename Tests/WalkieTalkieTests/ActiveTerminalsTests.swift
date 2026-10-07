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

    // MARK: - Under the folder rows (2026-10-07)

    func testSessionsGoUnderTheDeepestFolderRowTheRestStay() {
        let sessions = [
            session("ttys001", "/w/petclinic/petclinic-backend"),
            session("ttys002", "/w/petclinic"),
            session("ttys003", "/w/petclinic-main"),          // not inside /w/petclinic
            session("ttys004", "/w/walkie-talkie"),
            session("ttys005", "/w"),
        ]
        let split = ActiveTerminals.grouped(sessions, under: ["/w/petclinic", "/w/petclinic-main/", "/w"])
        XCTAssertEqual(split.byFolder["/w/petclinic"]?.map(\.tty), ["ttys001", "ttys002"])
        XCTAssertEqual(split.byFolder["/w/petclinic-main/"]?.map(\.tty), ["ttys003"])
        XCTAssertEqual(split.byFolder["/w"]?.map(\.tty), ["ttys004", "ttys005"])
        XCTAssertEqual(ActiveTerminals.grouped(sessions, under: ["/w/petclinic"]).rest.map(\.tty),
                       ["ttys003", "ttys004", "ttys005"])
    }

    func testAFolderSubmenuNamesTheTaskThenTheSubfolderThenTheFolder() {
        var busy = session("ttys002", "/w/petclinic", "◑ Owners grid paging")
        busy.busy = true
        let items = ActiveTerminals.folderItems([
            session("ttys001", "/w/petclinic/petclinic-backend"),
            busy,
            session("ttys003", "/w/petclinic", "✳ petclinic"),
            session("ttys004", "/w/petclinic"),
        ], folder: "/w/petclinic", boundTTY: "/dev/ttys004")
        XCTAssertEqual(items.map(\.name), ["Owners grid paging", "petclinic · ttys003", "petclinic · ttys004",
                                           "petclinic-backend"])
        XCTAssertEqual(items.filter(\.busy).map(\.tty), ["ttys002"])
        XCTAssertEqual(items.filter(\.bound).map(\.tty), ["ttys004"])
    }

    func testKamikazeIsTheWordOnALineOfItsOwn() {
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "kamikaze"))
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\nkamikaze\n\n[Dictated in RO or EN]"))
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\n Kamikaze "))
        XCTAssertFalse(ActiveTerminals.isKamikaze(prompt: "E2E test of the kamikaze gesture."))
        XCTAssertFalse(ActiveTerminals.isKamikaze(prompt: "kamikaze it"))
    }
}
