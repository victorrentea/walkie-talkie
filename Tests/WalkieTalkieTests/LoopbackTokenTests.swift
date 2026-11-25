import Foundation
import XCTest
@testable import WalkieTalkie

/// The loopback's `X-Walkie-Token` gate (2026-11-25): every route but four
/// answers 401 without this launch's token.
final class LoopbackTokenTests: XCTestCase {
    private let own = String(repeating: "a1", count: 32)
    private let disk = String(repeating: "b2", count: 32)

    private func allows(_ method: String, _ path: String, _ presented: String?,
                        onDisk: String? = nil) -> Bool {
        LoopbackToken.allows(method: method, path: path, presented: presented, own: own, onDisk: { onDisk })
    }

    func testAMissingTokenIsRefused() {
        for (m, p) in [("POST", "/test/spawn"), ("GET", "/test/state"), ("POST", "/bind"), ("POST", "/unbind"),
                       ("POST", "/engine"), ("POST", "/test/wispr-proc"), ("GET", "/test/sink"),
                       ("GET", "/no-such-route")] {
            XCTAssertFalse(allows(m, p, nil), "\(m) \(p) answered without a token")
        }
    }

    func testAWrongTokenIsRefused() {
        XCTAssertFalse(allows("POST", "/test/spawn", String(repeating: "a1", count: 31) + "a2"))
        XCTAssertFalse(allows("POST", "/test/spawn", own + "0"))
        XCTAssertFalse(allows("POST", "/test/spawn", String(own.dropLast())))
        XCTAssertFalse(allows("GET", "/test/state", ""))
        // An empty or short file on disk admits nobody, not even an empty header.
        XCTAssertFalse(allows("GET", "/test/state", "", onDisk: ""))
        XCTAssertFalse(allows("GET", "/test/state", "short", onDisk: "short"))
    }

    func testTheRightTokenPasses() {
        XCTAssertTrue(allows("POST", "/test/spawn", own))
        XCTAssertTrue(allows("GET", "/test/state", own))
        XCTAssertTrue(allows("POST", "/bind", own))
        // What the home's file holds now — a second process that shares the home rewrote it.
        XCTAssertTrue(allows("GET", "/test/state", disk, onDisk: disk))
        XCTAssertFalse(allows("GET", "/test/state", disk, onDisk: nil))
    }

    func testTheOpenRoutesNeedNoToken() {
        XCTAssertTrue(allows("GET", "/engine", nil))
        XCTAssertTrue(allows("GET", "/target", nil))
        XCTAssertTrue(allows("POST", "/reply", nil))   // its own reply-token, in the body
        XCTAssertTrue(allows("POST", "/ask", nil))
        // Open is per method: the engine pick and a GET of a POST route are not.
        XCTAssertFalse(allows("POST", "/engine", nil))
        XCTAssertFalse(allows("POST", "/target", nil))
    }

    func testTheHeaderIsParsedCaseBlind() {
        let raw = Data("GET /test/state HTTP/1.1\r\nHost: 127.0.0.1:8917\r\nX-Walkie-Token: \(own)\r\n\r\n".utf8)
        XCTAssertEqual(ElementPicker.Request(raw)?.token, own)
        let lower = Data("GET /test/state HTTP/1.1\r\nx-walkie-token:\(own)\r\n\r\n".utf8)
        XCTAssertEqual(ElementPicker.Request(lower)?.token, own)
        XCTAssertNil(ElementPicker.Request(Data("GET /test/state HTTP/1.1\r\n\r\n".utf8))?.token)
    }

    func testEqualIsExact() {
        XCTAssertTrue(LoopbackToken.equal(own, own))
        XCTAssertFalse(LoopbackToken.equal(own, disk))
        XCTAssertFalse(LoopbackToken.equal("", own))
        XCTAssertFalse(LoopbackToken.equal(own, own + own))
    }

    func testIssueWritesAFresh0600TokenIntoTheHome() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("walkie-token-\(UUID().uuidString)/nested")
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        let first = LoopbackToken.issue(home: home)
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(LoopbackToken.read(home: home), first)
        let file = try FileManager.default.attributesOfItem(atPath: LoopbackToken.url(home: home).path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let dir = try FileManager.default.attributesOfItem(atPath: home.path)
        XCTAssertEqual((dir[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        // Every launch a new one, replacing the last; no temp file left behind.
        let second = LoopbackToken.issue(home: home)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(LoopbackToken.read(home: home), second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.path), ["test-token"])
        // The shoot keeps its token to itself.
        let third = LoopbackToken.issue(home: home, persist: false)
        XCTAssertEqual(LoopbackToken.read(home: home), second)
        XCTAssertNotEqual(third, second)
    }
}
