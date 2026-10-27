import XCTest
@testable import WalkieTalkie

/// Which VS Code listener is the window in front (2026-10-27): the four `/ping`
/// answers measured when ⌘⌃B over `petclinic — ⑂ freqentis26oct` said *no terminal
/// open* — three stale `focused: true`, the front one `false`.
final class IDEWindowPickTests: XCTestCase {

    private func ping(_ folder: String?, focused: Bool, file: String? = nil) -> [String: Any] {
        var obj: [String: Any] = ["ok": true, "focused": focused,
                                  "folders": folder.map { [["name": $0]] } ?? []]
        if let folder { obj["folder"] = folder }
        if let file { obj["activeFile"] = file }
        return obj
    }

    private lazy var measured: [[String: Any]?] = [
        ping("spring", focused: true, file: "/w/spring/agents.md"),
        ping("petclinic-main", focused: true, file: "/w/petclinic-main/AGENTS.md"),
        ping(nil, focused: true, file: "/d/2026-10-26 AI@Frequentis - notes.txt"),
        ping("petclinic", focused: false),
    ]

    func testTheFrontTitleOutvotesStaleFocusedFlags() {
        XCTAssertEqual(IDEBridge.pickWindow(answers: measured, frontTitle: "petclinic — ⑂ freqentis26oct"), 3)
    }

    func testAFolderlessWindowIsFoundByItsFile() {
        XCTAssertEqual(IDEBridge.pickWindow(answers: measured,
                                            frontTitle: "⑂ — 2026-10-26 AI@Frequentis - notes.txt"), 2)
    }

    func testAPrefixOfAnotherFolderIsNotAMatch() {
        XCTAssertEqual(IDEBridge.pickWindow(answers: measured, frontTitle: "● AGENTS.md — petclinic-main"), 1)
    }

    func testNoTitleOrNoUniqueMatchFallsBackToTheFirstFocused() {
        XCTAssertEqual(IDEBridge.pickWindow(answers: measured, frontTitle: nil), 0)
        XCTAssertEqual(IDEBridge.pickWindow(answers: measured, frontTitle: "Welcome"), 0)
    }

    func testASilentListenerIsSkippedAndALoneOneIsTheAnswer() {
        XCTAssertEqual(IDEBridge.pickWindow(answers: [nil, ping("a", focused: true)], frontTitle: nil), 1)
        XCTAssertEqual(IDEBridge.pickWindow(answers: [ping("a", focused: false)], frontTitle: nil), 0)
        XCTAssertNil(IDEBridge.pickWindow(answers: [ping("a", focused: false), ping("b", focused: false)],
                                          frontTitle: nil))
    }
}
