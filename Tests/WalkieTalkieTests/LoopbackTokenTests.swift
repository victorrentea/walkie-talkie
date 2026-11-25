import Foundation
import XCTest
@testable import WalkieTalkie

/// The loopback's `X-Walkie-Token` gate (2026-11-25): every route but `/reply`
/// and `/ask` answers 401 without this launch's token.
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
                       ("GET", "/no-such-route"), ("GET", "/engine"), ("GET", "/target")] {
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
        XCTAssertTrue(allows("POST", "/reply", nil))   // its own reply-token, in the body
        XCTAssertTrue(allows("POST", "/ask", nil))
        // Open is per method: a GET of a POST route is not; and since the Fable
        // review GET /engine and GET /target are gated too (the bound tab's title).
        XCTAssertFalse(allows("GET", "/reply", nil))
        XCTAssertFalse(allows("GET", "/engine", nil))
        XCTAssertFalse(allows("GET", "/target", nil))
        XCTAssertTrue(allows("GET", "/target", own))
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
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.path).sorted(), ["test-port", "test-token"])
        // Until the listener is up, the port file says so — never the last launch's port.
        XCTAssertEqual(LoopbackToken.readPrivate(LoopbackToken.portURL(home: home)), LoopbackToken.portPending)
        // The shoot keeps its token to itself.
        let third = LoopbackToken.issue(home: home, persist: false)
        XCTAssertEqual(LoopbackToken.read(home: home), second)
        XCTAssertNotEqual(third, second)
    }

    private func scratchHome() -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("walkie-token-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: home) }
        return home
    }

    private func mode(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
    }

    /// The port file: `starting` from the launch, the bound port from `.ready`,
    /// written like the token (0600, atomic); a relaunch goes back to `starting`
    /// before its new token lands.
    func testThePortFileFollowsTheLaunch() {
        let home = scratchHome()
        let port = LoopbackToken.portURL(home: home)
        XCTAssertNil(LoopbackToken.readPrivate(port))
        _ = LoopbackToken.issue(home: home)
        XCTAssertEqual(LoopbackToken.readPrivate(port), "starting")
        LoopbackToken.publishPort(8918, home: home)
        XCTAssertEqual(LoopbackToken.readPrivate(port), "8918")
        XCTAssertEqual(mode(port), 0o600)
        _ = LoopbackToken.issue(home: home)
        XCTAssertEqual(LoopbackToken.readPrivate(port), "starting")
        // The shoot touches neither file.
        LoopbackToken.publishPort(8917, home: home)
        _ = LoopbackToken.issue(home: home, persist: false)
        XCTAssertEqual(LoopbackToken.readPrivate(port), "8917")
    }

    /// Only a regular file of this uid, closed to group/other, is believed.
    func testATokenFileThatIsNotHisIsNotRead() throws {
        let home = scratchHome()
        let file = LoopbackToken.url(home: home)
        XCTAssertTrue(LoopbackToken.write(own, home: home))
        XCTAssertEqual(LoopbackToken.read(home: home), own)
        // Readable by group or other → not trusted.
        chmod(file.path, 0o640)
        XCTAssertNil(LoopbackToken.read(home: home))
        chmod(file.path, 0o604)
        XCTAssertNil(LoopbackToken.read(home: home))
        chmod(file.path, 0o600)
        XCTAssertEqual(LoopbackToken.read(home: home), own)
        // A symlink planted where the token goes is not followed.
        let real = home.appendingPathComponent("elsewhere")
        try (disk + "\n").write(to: real, atomically: true, encoding: .utf8)
        chmod(real.path, 0o600)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: real)
        XCTAssertNil(LoopbackToken.read(home: home))
        // A directory in its place, or an empty file, is nothing.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertNil(LoopbackToken.read(home: home))
        try FileManager.default.removeItem(at: file)
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        XCTAssertNil(LoopbackToken.read(home: home))
    }

    /// A home looser than 0700 is closed at launch; a 0700 one is left alone.
    func testIssueClosesALooseHome() {
        let home = scratchHome()
        chmod(home.path, 0o755)
        _ = LoopbackToken.issue(home: home)
        XCTAssertEqual(mode(home), 0o700)
        XCTAssertTrue(LoopbackToken.secureHome(home))
        XCTAssertEqual(mode(home), 0o700)
        XCTAssertFalse(LoopbackToken.secureHome(home.appendingPathComponent("missing")))
    }

    /// A failed token write never lets an older launch's token through: the file
    /// is removed when it can be, and the gate stops reading it when it cannot.
    func testAFailedWriteLeavesNoOlderTokenValid() {
        let home = scratchHome()
        XCTAssertTrue(LoopbackToken.write(own, home: home))
        let fresh = LoopbackToken.issue(home: home)
        XCTAssertTrue(LoopbackToken.trustsDisk(issued: fresh, persist: true, home: home))
        chmod(home.path, 0o500)   // nothing can be created or removed in it
        defer { chmod(home.path, 0o700) }
        let failed = LoopbackToken.issue(home: home)
        XCTAssertEqual(LoopbackToken.read(home: home), fresh)   // still on disk…
        XCTAssertFalse(LoopbackToken.trustsDisk(issued: failed, persist: true, home: home))   // …and not believed
        XCTAssertTrue(LoopbackToken.trustsDisk(issued: failed, persist: false, home: home))  // the shoot, as before
    }

    func testReplyTokenIsComparedExactly() {
        XCTAssertTrue(LoopbackToken.replyTokenMatches(own, expected: own, route: "/reply"))
        XCTAssertFalse(LoopbackToken.replyTokenMatches(disk, expected: own, route: "/reply"))
        XCTAssertFalse(LoopbackToken.replyTokenMatches(nil, expected: own, route: "/ask"))
        XCTAssertFalse(LoopbackToken.replyTokenMatches(42, expected: own, route: "/ask"))
        XCTAssertFalse(LoopbackToken.replyTokenMatches("", expected: "", route: "/ask"))
    }

    /// The refusal log: short printable keys, a bounded table, ≤ 20 lines a minute.
    func testTheRefusalThrottleIsBounded() {
        let long = "/" + String(repeating: "x", count: 500_000)
        XCTAssertEqual(RefusalThrottle.key("GET", long).count, 4 + 60)
        XCTAssertEqual(RefusalThrottle.key("GET", "/a\nb\u{1b}[2Jc é"), "GET /a?b?[2Jc??")
        var t = RefusalThrottle()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNotNil(t.admit("GET /test/state", now: t0))
        XCTAssertNil(t.admit("GET /test/state", now: t0.addingTimeInterval(30)))   // same key, within the minute
        // A flood of distinct keys: 19 more lines this minute, then silence.
        var lines = 1
        for i in 0..<5_000 where t.admit("GET /p\(i)", now: t0.addingTimeInterval(1)) != nil { lines += 1 }
        XCTAssertEqual(lines, RefusalThrottle.maxLinesPerWindow)
        XCTAssertLessThanOrEqual(t.lastByKey.count, RefusalThrottle.maxKeys)
        // The next minute's first line says how many went unlogged.
        let next = t.admit("GET /later", now: t0.addingTimeInterval(61))
        // (The repeat of /test/state was told on the flood's first line.)
        XCTAssertEqual(next?.suppressed, 5_000 - (RefusalThrottle.maxLinesPerWindow - 1))
        for i in 0..<1_000 { _ = t.admit("GET /q\(i)", now: t0.addingTimeInterval(Double(200 + i * 61))) }
        XCTAssertLessThanOrEqual(t.lastByKey.count, RefusalThrottle.maxKeys)
        XCTAssertEqual(t.admit("GET /test/state", now: t0.addingTimeInterval(200_000))?.suppressed, 0)
    }
}
