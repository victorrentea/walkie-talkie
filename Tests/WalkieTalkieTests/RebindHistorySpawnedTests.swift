import XCTest
@testable import WalkieTalkie

/// The chip names a session this app opened by its folder alone (2026-11-05), so
/// `isSpawned` has to hold for the live row and for nothing else.
final class RebindHistorySpawnedTests: XCTestCase {

    private func target(_ tty: String) -> TerminalBinding.Target {
        TerminalBinding.Target(handle: .terminalApp(tty: "/dev/\(tty)"), label: "walkie-talkie", address: tty,
                               appName: "Terminal", bundleID: "com.apple.Terminal", folder: "walkie-talkie@master",
                               title: "✳ Make the panel see-through", sourceFrame: nil, boundAt: Date())
    }

    private func history() -> RebindHistory {
        RebindHistory(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testAWindowThisAppOpenedIsSpawned() {
        let h = history()
        h.adopted(target("ttys009"), spawned: true)
        XCTAssertTrue(h.isSpawned(address: "ttys009"))
    }

    func testAWindowHePointedAtIsNot() {
        let h = history()
        h.adopted(target("ttys009"), spawned: false)
        XCTAssertFalse(h.isSpawned(address: "ttys009"))
    }

    func testAReleasedRowDoesNotAnswerForTheNextOwnerOfTheTTY() {
        let h = history()
        h.adopted(target("ttys009"), spawned: true)
        h.released(target("ttys009"))
        XCTAssertFalse(h.isSpawned(address: "ttys009"))
    }

    func testRebindingASpawnedWindowKeepsItSpawned() {
        let h = history()
        h.adopted(target("ttys009"), spawned: true)
        h.adopted(target("ttys009"), spawned: false)
        XCTAssertTrue(h.isSpawned(address: "ttys009"))
    }
}
