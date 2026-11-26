import XCTest
@testable import WalkieTalkie

/// `MessageLog.recent` reads the outbox from its end and stops past the 48 h
/// cutoff (2026-11-25, the Fable review: the whole file was parsed on main).
final class MessageLogRecentTests: XCTestCase {

    private var saved: URL!
    private var dir: URL!

    override func setUp() {
        saved = Outbox.outboxURL
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("msglog-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Outbox.outboxURL = dir.appendingPathComponent("outbox.jsonl")
    }

    override func tearDown() {
        Outbox.outboxURL = saved
        try? FileManager.default.removeItem(at: dir)
    }

    private func line(_ text: String, hoursAgo: Double, now: Date) -> String {
        let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-hoursAgo * 3600))
        let obj: [String: Any] = ["ts": ts, "text": text, "kind": "dictation"]
        return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
    }

    func testTheLastTwoDaysNewestFirstAndNothingOlder() throws {
        let now = Date()
        let lines = [
            line("august", hoursAgo: 24 * 90, now: now),
            "{ not json",
            line("three days ago", hoursAgo: 72, now: now),
            // Written a little out of order at the edge: still inside the slack.
            line("just inside", hoursAgo: 47.5, now: now),
            line("just outside", hoursAgo: 48.2, now: now),
            line("yesterday", hoursAgo: 20, now: now),
            "",
            line("now", hoursAgo: 0.01, now: now),
            "{\"ts\": \"truncated",
        ]
        try lines.joined(separator: "\n").write(to: Outbox.outboxURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(MessageLog.recent(now: now).map(\.text), ["now", "yesterday", "just inside"])
    }

    /// ⏸ A row written when a prompt started waiting for a question (`delivery.held`) is
    /// superseded by the later row of the same envelope; alone (a crash), it stays.
    func testAHeldRowGivesWayToTheRowThatFollowsIt() throws {
        let now = Date()
        func row(_ text: String, envelope: String, held: Bool, minutesAgo: Double) -> String {
            let ts = ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutesAgo * 60))
            var delivery: [String: Any] = ["to": held ? "undelivered" : "terminal:ttys004"]
            if held { delivery["held"] = true }
            let obj: [String: Any] = ["ts": ts, "text": text, "kind": "dictation", "line": envelope, "delivery": delivery]
            return String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
        }
        let lines = [
            row("answered later", envelope: "A", held: true, minutesAgo: 3),
            row("never released", envelope: "B", held: true, minutesAgo: 2),
            row("answered later", envelope: "A", held: false, minutesAgo: 1),
        ]
        try lines.joined(separator: "\n").write(to: Outbox.outboxURL, atomically: true, encoding: .utf8)
        let rows = MessageLog.recent(now: now)
        XCTAssertEqual(rows.map(\.text), ["answered later", "never released"])
        XCTAssertNil(rows[0].undelivered)
        XCTAssertNotNil(rows[1].undelivered)
    }

    func testAMissingOutboxIsAnEmptyLog() {
        XCTAssertTrue(MessageLog.recent().isEmpty)
    }
}
