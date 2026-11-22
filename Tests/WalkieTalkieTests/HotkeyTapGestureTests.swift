import XCTest
@testable import WalkieTalkie

/// The tap's own `handle`, fed events it never sees posted (2026-11-22): 🔽 ↑
/// with the wheel down films the box; a plain dictation ignores every flick but
/// its cancel and its stops; 🔽 → at rest starts nothing; ⌃P over a plain
/// dictation is not taken. No tap is installed and no event is posted.
final class HotkeyTapGestureTests: XCTestCase {
    private let F3: CGKeyCode = 0x63, F4: CGKeyCode = 0x76, F5: CGKeyCode = 0x60, F8: CGKeyCode = 0x64
    private let F9: CGKeyCode = 0x65, F10: CGKeyCode = 0x6D, F12: CGKeyCode = 0x6F

    private func mouse(_ type: CGEventType, _ x: CGFloat, _ y: CGFloat, at t: Double) -> CGEvent {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y),
                        mouseButton: .center)!
        e.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        e.timestamp = CGEventTimestamp(t * 1_000_000_000)
        e.flags = []
        return e
    }

    private func chord(_ key: CGKeyCode, at t: Double = 100) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!
        e.flags = [.maskControl, .maskAlternate, .maskCommand]
        e.timestamp = CGEventTimestamp(t * 1_000_000_000)
        return e
    }

    private func wait(_ seconds: TimeInterval = 0.3) {
        let done = expectation(description: "queues drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    // MARK: 🔽 ↑ with the wheel down

    /// A wheel drag in a prompt, a pause, the swipe's own 90 pt of upward travel,
    /// then Options+'s ⌃⌥⌘F4: the box is frozen where the hand paused, the whole-
    /// display film is not asked for, the rest of the drag resizes nothing, and
    /// the wheel's release ends nothing (and is swallowed, as a crop's is).
    func testBackUpWithTheWheelDownFilmsTheBoxAndTheReleaseDoesNothing() {
        let tap = HotkeyTap()
        tap.dictating = true
        var shots = 0, ends = 0, films = 0, moved = 0
        var corner: CGPoint?
        tap.onAreaShot = { _, _ in shots += 1 }
        tap.onAreaEnd = { ends += 1 }
        tap.onGestureFilm = { films += 1 }
        tap.onAreaMoved = { moved += 1 }
        tap.onAreaFilm = { corner = $0 }

        XCTAssertTrue(tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, 100, 100, at: 10.0)), "held back in Logi mode")
        XCTAssertTrue(tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, 300, 300, at: 10.1)))
        XCTAssertTrue(tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, 500, 400, at: 10.2)))
        // …a pause, then the swipe up moves the pointer too.
        for i in 1...9 {
            XCTAssertTrue(tap.takesForTesting(.otherMouseDragged,
                                              mouse(.otherMouseDragged, 500, 400 - CGFloat(i) * 10, at: 10.8 + Double(i) * 0.01)))
        }
        XCTAssertTrue(tap.takesForTesting(.keyDown, chord(F4, at: 10.9)))
        XCTAssertEqual(corner, CGPoint(x: 500, y: 400), "frozen where the hand paused, not 90 pt shorter")
        // The hand goes on moving, then lets the wheel go.
        XCTAssertTrue(tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, 520, 250, at: 11.0)))
        XCTAssertTrue(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, 520, 250, at: 11.1)), "the release matches the held press")
        wait()
        XCTAssertEqual(shots, 1, "the crop was armed once")
        XCTAssertEqual(ends, 0, "the film's handler ended the box; the release ends nothing")
        XCTAssertEqual(films, 0, "not the whole-display film")
        // A second ⌃⌥⌘F4 now, with no box under the wheel, is the whole display's
        // (past the tap's 0.6 s re-fire window, which runs on the real clock).
        wait(0.7)
        XCTAssertTrue(tap.takesForTesting(.keyDown, chord(F4, at: 20)))
        wait()
        XCTAssertEqual(films, 1)
    }

    /// An ordinary crop is untouched: its release still ends the box.
    func testACropWithNoFlickStillEndsAtTheRelease() {
        let tap = HotkeyTap()
        tap.dictating = true
        var ends = 0, filmed = false
        tap.onAreaEnd = { ends += 1 }
        tap.onAreaFilm = { _ in filmed = true }
        _ = tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, 100, 100, at: 10.0))
        _ = tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, 300, 300, at: 10.1))
        XCTAssertTrue(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, 300, 300, at: 10.2)))
        XCTAssertEqual(ends, 1)
        XCTAssertFalse(filmed)
    }

    /// A locked box (⇧ / right click) is not filmed: refused, and the lock stays.
    func testALockedBoxIsNotFilmed() {
        let tap = HotkeyTap()
        tap.dictating = true
        var refused = 0, filmed = false, films = 0
        tap.onAreaFilmRefused = { refused += 1 }
        tap.onAreaFilm = { _ in filmed = true }
        tap.onGestureFilm = { films += 1 }
        _ = tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, 100, 100, at: 10.0))
        _ = tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, 300, 300, at: 10.1))
        tap.areaBoxLocked = true
        XCTAssertTrue(tap.takesForTesting(.keyDown, chord(F4, at: 10.5)))
        wait()
        XCTAssertEqual(refused, 1)
        XCTAssertFalse(filmed)
        XCTAssertEqual(films, 0)
    }

    // MARK: A plain dictation

    /// Every flick but the cancel is swallowed and reaches no handler.
    func testAPlainDictationIgnoresEveryFlickButItsCancel() {
        let tap = HotkeyTap()
        let mark = try? String(contentsOf: HotkeyTap.promptingMark, encoding: .utf8)
        tap.relayPlainOpen = true
        XCTAssertEqual(try? String(contentsOf: HotkeyTap.promptingMark, encoding: .utf8), mark,
                       "a plain dictation does not write ~/.walkie-talkie/prompting (⌃P stays Victor Mac's)")
        XCTAssertTrue(tap.cleanSentenceOpen)
        var fired: [String] = []
        tap.onForwardRight = { fired.append("🔼 →") }
        tap.onGestureSpawn = { fired.append("🔼 ↑") }
        tap.onGestureKamikaze = { fired.append("🔼 ↓") }
        tap.onCleanToggle = { fired.append("plain toggle") }
        tap.onGestureUnbind = { fired.append("unbind") }
        tap.onGestureFilm = { fired.append("film") }
        tap.onInterruptToggle = { fired.append("interrupt") }
        tap.onChatVoice = { fired.append("chat voice") }
        tap.onModelToggle = { fired.append("model") }
        tap.onBackSubmit = { fired.append("return") }
        tap.onPlainToPrompt = { _ in fired.append("⌃P to prompt") }
        for (i, key) in [F10, F8, F9, F5, F12, F4, F3].enumerated() {
            XCTAssertTrue(tap.takesForTesting(.keyDown, chord(key, at: 100 + Double(i) * 5)), "key \(key) is swallowed")
        }
        // ⌃P is not this app's over a plain dictation: it passes through.
        let ctrlP = CGEvent(keyboardEventSource: nil, virtualKey: 0x23, keyDown: true)!
        ctrlP.flags = [.maskControl]
        XCTAssertFalse(tap.takesForTesting(.keyDown, ctrlP))
        wait()
        XCTAssertEqual(fired, [])
        XCTAssertEqual(HotkeyTap.plainIgnores, [F10, F8, F9, F5, F12, F4, F3])
        tap.relayPlainOpen = false
        XCTAssertEqual(try? String(contentsOf: HotkeyTap.promptingMark, encoding: .utf8), mark)
    }

    /// 🔽 → at rest starts nothing (2026-11-22) — swallowed, no plain dictation.
    func testBackRightAtRestStartsNothing() {
        let tap = HotkeyTap()
        var started = false
        tap.onCleanToggle = { started = true }
        tap.onWisprRawChord = { _ in started = true }
        XCTAssertTrue(tap.takesForTesting(.keyDown, chord(F5)))
        wait()
        XCTAssertFalse(started)
    }
}
