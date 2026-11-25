import XCTest
@testable import WalkieTalkie

/// `swift test` must never write into the installed app's `relay.log`
/// (found by the Fable review, 2026-11-25): its fake incident lines were read as the app's.
final class LogIsolationTests: XCTestCase {

    func testTheTestBundleLogsOutsideTheLiveHome() {
        XCTAssertFalse(Log.fileURL.path.hasPrefix(Outbox.defaultHome.path), Log.fileURL.path)
        XCTAssertEqual(Log.fileURL.lastPathComponent, "relay.log")
    }

    /// Nor read or remove the installed app's `prompting` mark (Victor Mac's ⌃P reads it).
    func testThePromptingMarkIsNotTheLiveOne() {
        XCTAssertFalse(HotkeyTap.promptingMark.path.hasPrefix(Outbox.defaultHome.path),
                       HotkeyTap.promptingMark.path)
    }
}
