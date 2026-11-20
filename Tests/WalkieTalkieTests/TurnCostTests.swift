import XCTest
@testable import WalkieTalkie

/// 💸 The turn-cost float's arithmetic (2026-11-19): one turn is everything between two
/// `turn_duration` lines, each response counted once, subagents inside the turn added.
final class TurnCostTests: XCTestCase {

    private func line(_ o: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }
    private func assistant(_ id: String, _ ts: String, model: String = "claude-opus-5-5",
                           out: Int = 1_000_000, sidechain: Bool = false) -> String {
        line(["type": "assistant", "timestamp": ts, "isSidechain": sidechain, "cwd": "/w/walkie-talkie",
              "message": ["id": id, "model": model, "usage": ["output_tokens": out]]])
    }
    private func end(_ ts: String) -> String {
        line(["type": "system", "subtype": "turn_duration", "timestamp": ts, "isSidechain": false, "durationMs": 42_000])
    }
    private func prompt(_ ts: String) -> String {
        line(["type": "user", "timestamp": ts, "isSidechain": false, "message": ["content": "do it"]])
    }

    func testOpusFiveFiveOutputIsTwentyDollarsAMillion() {
        XCTAssertEqual(TurnCost.cost(model: "claude-opus-5-5", usage: ["output_tokens": 1_000_000]), 20, accuracy: 1e-9)
        XCTAssertEqual(TurnCost.cost(model: "claude-opus-5-5", usage: ["cache_read_input_tokens": 1_000_000]), 0.2, accuracy: 1e-9)
        // No TTL split: a 5-minute write.
        XCTAssertEqual(TurnCost.cost(model: "claude-sonnet-5-5", usage: ["cache_creation_input_tokens": 1_000_000]), 2.5, accuracy: 1e-9)
        XCTAssertEqual(TurnCost.cost(model: "claude-fable-5-2", usage: ["cache_creation": ["ephemeral_1h_input_tokens": 1_000_000]]), 20, accuracy: 1e-9)
    }

    func testTheLastTurnIsBetweenTheLastTwoTurnEnds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("turncost-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("s.jsonl")
        let lines = [
            prompt("2026-11-19T10:00:00.000Z"),
            assistant("old", "2026-11-19T10:00:01.000Z"),
            end("2026-11-19T10:00:02.000Z"),
            prompt("2026-11-19T10:01:00.000Z"),
            assistant("a", "2026-11-19T10:01:01.000Z", out: 100_000),        // $2
            assistant("a", "2026-11-19T10:01:01.100Z", out: 100_000),        // same message: once
            assistant("b", "2026-11-19T10:01:02.000Z", model: "<synthetic>"),
            line(["type": "user", "timestamp": "2026-11-19T10:01:03.000Z", "message": ["content": [["type": "tool_result"]]]]),
            assistant("c", "2026-11-19T10:01:04.000Z", model: "claude-haiku-4-5", out: 200_000),  // $1
            end("2026-11-19T10:01:05.000Z"),
            prompt("2026-11-19T10:02:00.000Z"),                               // a turn still running
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        // A subagent: one response inside the turn, one after it.
        let sub = dir.appendingPathComponent("s/subagents")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try [assistant("s1", "2026-11-19T10:01:03.500Z", model: "claude-sonnet-5-5", out: 100_000, sidechain: true),
             assistant("s2", "2026-11-19T10:05:00.000Z", out: 100_000, sidechain: true)]
            .joined(separator: "\n").appending("\n")
            .write(to: sub.appendingPathComponent("agent-x.jsonl"), atomically: true, encoding: .utf8)

        let turn = try XCTUnwrap(TurnCost.lastTurn(of: url))
        XCTAssertEqual(turn.usd, 3, accuracy: 1e-9)
        XCTAssertEqual(turn.subagentUSD, 1, accuracy: 1e-9)          // sonnet-5: 100k out × $10/MTok
        XCTAssertEqual(turn.responses, 3)
        XCTAssertEqual(turn.model, "claude-haiku-4-5")              // the last main-thread answer
        XCTAssertEqual(turn.cwd, "/w/walkie-talkie")
        XCTAssertEqual(turn.seconds ?? 0, 42, accuracy: 1e-9)
        XCTAssertEqual(TurnCost.money(turn.total), "$4.00")

        // The watcher's start: the last turn end stamped before the prompt left.
        let size = UInt64(try Data(contentsOf: url).count)
        let before = try XCTUnwrap(TurnCost.lastTurnEnd(in: url, before: size, stampedBefore: "2026-11-19T10:01:00.000Z"))
        var again = TurnCost.Turn()
        TurnCost.forEachLine(in: url, from: before.next, to: size) { l, _ in again.feed(l) }
        XCTAssertEqual(again.usd, 3, accuracy: 1e-9)
        XCTAssertNil(TurnCost.lastTurnEnd(in: url, before: size, stampedBefore: "2026-11-19T10:00:00.000Z"))
    }

    func testTheWordsOfTheFloat() {
        var turn = TurnCost.Turn()
        turn.usd = 1.4
        turn.model = "claude-opus-5-5"
        let (amount, rest) = TurnCost.text(turn, place: "walkie-talkie — Turn cost")
        XCTAssertEqual(amount + rest, "$1.40 · Opus 5.5 in walkie-talkie — Turn cost")
        XCTAssertEqual(TurnCost.money(0.001), "<$0.01")
    }
}
