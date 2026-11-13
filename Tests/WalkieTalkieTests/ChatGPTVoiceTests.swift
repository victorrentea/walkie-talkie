import XCTest
@testable import WalkieTalkie

/// `ChatGPTVoice.quarter` — where 🔽 ← puts ChatGPT's window (2026-11-13).
final class ChatGPTVoiceTests: XCTestCase {

    /// A 1728×1117 primary screen, menu bar 38 pt, in AppKit coordinates.
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1079)

    func testThePointersQuarterInAccessibilityCoordinates() {
        // Top right in AppKit is y large; in AX it is just under the menu bar.
        XCTAssertEqual(ChatGPTVoice.quarter(of: visible, holding: CGPoint(x: 1500, y: 900), primaryHeight: 1117),
                       CGRect(x: 864, y: 38, width: 864, height: 539))
        XCTAssertEqual(ChatGPTVoice.quarter(of: visible, holding: CGPoint(x: 100, y: 100), primaryHeight: 1117),
                       CGRect(x: 0, y: 578, width: 864, height: 539))
    }

    func testAScreenLeftOfAndAboveThePrimary() {
        let second = CGRect(x: -1920, y: 1117, width: 1920, height: 1055)
        XCTAssertEqual(ChatGPTVoice.quarter(of: second, holding: CGPoint(x: -1900, y: 2100), primaryHeight: 1117),
                       CGRect(x: -1920, y: -1055, width: 960, height: 527))
    }
}
