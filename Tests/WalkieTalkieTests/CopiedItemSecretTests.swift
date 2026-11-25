import XCTest
@testable import WalkieTalkie

/// **A password manager's copy is never filed** into a prompt: the
/// nspasteboard.org markers make `CopiedItem.read` hand back nothing.
final class CopiedItemSecretTests: XCTestCase {

    func testConcealedOrTransientBoardIsSecret() {
        XCTAssertTrue(CopiedItem.isSecret(["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(CopiedItem.isSecret(["public.utf8-plain-text", "org.nspasteboard.TransientType"]))
        XCTAssertTrue(CopiedItem.isSecret(["com.agilebits.onepassword", "public.utf8-plain-text"]))
    }

    func testOrdinaryCopyIsNot() {
        XCTAssertFalse(CopiedItem.isSecret(["public.utf8-plain-text"]))
        XCTAssertFalse(CopiedItem.isSecret(["public.png", "public.html", "public.utf8-plain-text"]))
        XCTAssertFalse(CopiedItem.isSecret([]))
    }
}
