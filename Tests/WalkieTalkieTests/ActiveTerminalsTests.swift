import XCTest
@testable import WalkieTalkie

/// The spawn menu's session lines, the pure half (2026-09-23; under *✨ Workspace*
/// since 2026-11-20, when *Active terminals* went):
/// sessions → rows, the disambiguation of two sessions in one folder, the tick
/// on the bound one, and the empty state.
final class ActiveTerminalsTests: XCTestCase {

    private func session(_ tty: String, _ dir: String, _ title: String? = nil) -> ActiveTerminals.Session {
        ActiveTerminals.Session(tty: tty, directory: dir, title: title)
    }

    func testAKamikazeSessionIsOfferedMarkedAsDying() {
        // 2026-11-19: told `kamikaze`, it stays on the menu with a 💀 (it was hidden).
        var s = session("ttys009", "/Users/v/workspace/walkie-talkie")
        s.busy = true
        s.kamikazed = true
        let item = ActiveTerminals.items([s], boundTTY: nil).first
        XCTAssertEqual(item?.kamikazed, true)
        XCTAssertEqual(item?.busy, true)
    }

    func testAKamikazeLineComesLast() {
        // 2026-11-20: a 💀 line goes under the others, whatever its name.
        var dying = session("ttys001", "/Users/v/workspace/assistant")
        dying.kamikazed = true
        let rows = ActiveTerminals.items([dying, session("ttys002", "/Users/v/workspace/petclinic"),
                                          session("ttys003", "/Users/v/workspace/code-city")], boundTTY: nil)
        XCTAssertEqual(rows.map(\.name), ["code-city", "petclinic", "assistant"])
        let folder = ActiveTerminals.folderItems([dying, session("ttys004", "/Users/v/workspace/zeta")],
                                                 folder: "/Users/v/workspace", boundTTY: nil)
        XCTAssertEqual(folder.last?.kamikazed, true)
    }

    func testNoSessionsIsNoRows() {
        XCTAssertEqual(ActiveTerminals.items([], boundTTY: "ttys004"), [])
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

    /// 2026-11-20: `~/workspace` claims every session no pinned row does —
    /// *Active terminals* is gone.
    func testTheWorkspaceRowTakesEverySessionNoPinnedRowClaims() {
        let sessions = [
            session("ttys001", "/w"),
            session("ttys002", "/w/"),
            session("ttys003", "/w/walkie-talkie"),           // a project, not pinned: Workspace's
            session("ttys004", "/w/petclinic"),               // pinned: its own row wins
            session("ttys005", "/elsewhere"),
        ]
        let split = ActiveTerminals.grouped(sessions, under: ["/w/petclinic"], rest: "/w")
        XCTAssertEqual(split.byFolder["/w"]?.map(\.tty), ["ttys001", "ttys002", "ttys003", "ttys005"])
        XCTAssertEqual(split.byFolder["/w/petclinic"]?.map(\.tty), ["ttys004"])
        XCTAssertEqual(split.rest, [])
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
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\n🎙️ · ☁️ · 📸 ×7 · 💀 kamikaze"))
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\n🎙️ · ☁️ · 📸📸📸 · 💀"))
        XCTAssertFalse(ActiveTerminals.isKamikaze(prompt: "a kamikaze pilot"))
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\nkamikaze\n\n[Dictated in RO or EN]"))
        XCTAssertTrue(ActiveTerminals.isKamikaze(prompt: "Fix it.\n\n Kamikaze "))
        XCTAssertFalse(ActiveTerminals.isKamikaze(prompt: "E2E test of the kamikaze gesture."))
        XCTAssertFalse(ActiveTerminals.isKamikaze(prompt: "kamikaze it"))
    }
}
