import XCTest
@testable import WalkieTalkie

/// Custom gestures (2026-11-22): a mouse button with modifiers, or a key
/// combination, standing in for a Logi side-button gesture. The model, the
/// recorder's judgment, the tap's translation and its swallow of down + up —
/// no tap installed, no event posted.
final class CustomGesturesTests: XCTestCase {
    private typealias T = CustomTrigger

    private func memory() -> CustomGestures { CustomGestures(defaults: nil) }

    private func suite() -> (UserDefaults, String) {
        let name = "wt-custom-gestures-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    // MARK: The trigger: how it reads, how it is kept

    func testATriggerReadsAsModifiersThenTheButton() {
        XCTAssertEqual(T(.mouse(2), [.command]).display, "⌘ wheel click")
        XCTAssertEqual(T(.mouse(0), [.option, .command]).display, "⌥⌘ click")
        XCTAssertEqual(T(.mouse(1), [.control, .shift]).display, "⌃⇧ right click")
        XCTAssertEqual(T(.mouse(0), [.control, .option, .shift, .command]).display, "⌃⌥⇧⌘ click")
        XCTAssertEqual(T(.key(40), [.control, .option], keyLabel: "K").display, "⌃⌥K")
        XCTAssertEqual(T(.key(0x60), [.command]).display, "⌘F5", "a named key needs no label")
        XCTAssertEqual(T(.key(0x31), [.option, .shift]).display, "⌥⇧Space")
    }

    func testAKeyIsNamedByItsCharacterUnlessItHasAName() {
        XCTAssertEqual(T.keyName(40, characters: "k"), "K")
        XCTAssertEqual(T.keyName(0x24, characters: "\r"), "Return")
        XCTAssertEqual(T.keyName(0x7E, characters: "\u{F700}"), "↑")
        XCTAssertEqual(T.keyName(200, characters: "\u{F747}"), "key 200", "a private-use character is not a name")
        XCTAssertEqual(T.keyName(200, characters: nil), "key 200")
    }

    func testTheStoredFormComesBackTheSame() {
        for t in [T(.mouse(2), [.command]), T(.mouse(0), [.option, .command]), T(.mouse(1), [.control, .shift]),
                  T(.key(40), [.control, .option], keyLabel: "K"), T(.key(41), [.command], keyLabel: ":")] {
            let back = T(stored: t.stored)
            XCTAssertEqual(back, t, t.stored)
            XCTAssertEqual(back?.display, t.display, t.stored)
        }
        XCTAssertEqual(T(.mouse(2), [.command]).stored, "mouse:2:8")
        XCTAssertEqual(T(.key(40), [.control, .command], keyLabel: "K").stored, "key:40:9:K")
        for bad in ["", "mouse", "mouse:3:8", "mouse:2:16", "mouse:x:1", "wheel:2:8", "key:999:8:K", "mouse:2:8:extra", "key:-1:8:"] {
            XCTAssertNil(T(stored: bad), bad)
        }
    }

    func testTheKeyLabelIsNotPartOfWhatATriggerIs() {
        XCTAssertEqual(T(.key(40), [.command], keyLabel: "K"), T(.key(40), [.command], keyLabel: "Κ"))
        XCTAssertNotEqual(T(.key(40), [.command]), T(.key(40), [.command, .shift]))
        XCTAssertNotEqual(T(.mouse(2), [.command]), T(.mouse(1), [.command]))
    }

    func testModifiersAreReadOffAnEventsFlagsAndNothingElse() {
        let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskSecondaryFn, .maskAlphaShift, .maskNumericPad]
        XCTAssertEqual(T.Modifiers(flags), [.option, .command])
        XCTAssertEqual(T.Modifiers(NSEvent.ModifierFlags([.control, .shift, .capsLock, .function])), [.control, .shift])
    }

    // MARK: The recorder's judgment

    func testABareClickIsRefusedAndAKeyNeedsARealModifier() {
        for button in 0...2 {
            XCTAssertEqual(CustomGestures.refusal(of: T(.mouse(button), []), for: .forwardClick, in: [:]), .bareClick)
            XCTAssertNil(CustomGestures.refusal(of: T(.mouse(button), [.shift]), for: .forwardClick, in: [:]),
                         "⇧ alone is enough for a button")
        }
        XCTAssertEqual(CustomGestures.refusal(of: T(.key(40), []), for: .forwardClick, in: [:]), .bareKey)
        XCTAssertEqual(CustomGestures.refusal(of: T(.key(40), [.shift]), for: .forwardClick, in: [:]), .bareKey,
                       "⇧K is typing")
        XCTAssertNil(CustomGestures.refusal(of: T(.key(40), [.control]), for: .forwardClick, in: [:]))
    }

    func testTheSameTriggerOnTwoRowsIsAConflict() {
        let store = memory()
        let cmdWheel = T(.mouse(2), [.command])
        XCTAssertNil(store.set(cmdWheel, for: .forwardClick))
        XCTAssertEqual(store.set(cmdWheel, for: .backClick), .taken(by: .forwardClick))
        XCTAssertNil(store.bindings[.backClick], "a refusal changes nothing")
        XCTAssertNil(store.set(cmdWheel, for: .forwardClick), "re-recording a row's own trigger is fine")
        XCTAssertNil(store.set(T(.mouse(2), [.command, .shift]), for: .backClick), "one more modifier is another trigger")
        // Cleared, it is free again.
        store.set(nil, for: .forwardClick)
        XCTAssertNil(store.set(cmdWheel, for: .backUp))
        XCTAssertEqual(CustomTriggerRefusal.taken(by: .forwardClick).message,
                       "Already the trigger for “Prompt at the caret” — clear that one first.")
    }

    func testTheAppsOwnKeysAreRefused() {
        for t in [T(.key(0x0B), [.control, .command]), T(.key(0x07), [.control, .command]), T(.key(0x23), [.control]),
                  T(.key(0x62), [.control, .option, .command]), T(.key(0x63), [.control, .option, .command])] {
            XCTAssertEqual(CustomGestures.refusal(of: t, for: .forwardClick, in: [:]), .reserved, t.display)
        }
        XCTAssertNil(CustomGestures.refusal(of: T(.key(0x0B), [.command, .option]), for: .forwardClick, in: [:]))
    }

    func testEveryRefusalSaysSomethingInEnglish() {
        for r in [CustomTriggerRefusal.bareClick, .bareKey, .reserved, .taken(by: .backUp)] {
            XCTAssertFalse(r.message.isEmpty)
        }
    }

    // MARK: Kept in the defaults; off does not forget

    func testOffByDefaultAndTheBindingsOutliveTheSwitchAndTheProcess() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        let first = CustomGestures(defaults: d)
        XCTAssertFalse(first.enabled, "off until ticked")
        XCTAssertFalse(first.live)
        XCTAssertTrue(first.bindings.isEmpty)
        first.enabled = true
        first.set(T(.mouse(2), [.command]), for: .forwardClick)
        first.set(T(.key(40), [.control, .option], keyLabel: "K"), for: .forwardLeft)
        first.enabled = false
        XCTAssertEqual(first.bindings.count, 2, "unticking forgets nothing")

        let second = CustomGestures(defaults: d)
        XCTAssertFalse(second.enabled)
        XCTAssertEqual(second.bindings[.forwardClick], T(.mouse(2), [.command]))
        XCTAssertEqual(second.bindings[.forwardLeft]?.display, "⌃⌥K")
        second.enabled = true
        XCTAssertTrue(CustomGestures(defaults: d).enabled)
    }

    func testGarbageInTheDefaultsIsDropped() {
        let (d, name) = suite()
        defer { d.removePersistentDomain(forName: name) }
        d.set(["forwardClick": "mouse:2:8", "noSuchAction": "mouse:1:8", "backClick": "nonsense", "backUp": "mouse:0:0"],
              forKey: CustomGestures.bindingsKey)
        XCTAssertEqual(CustomGestures(defaults: d).bindings, [.forwardClick: T(.mouse(2), [.command])])
    }

    // MARK: The actions are the Logi chords

    func testEveryActionIsOneOfTheTapsChordsUnderItsOwnGlyph() {
        var seen = Set<CGKeyCode>()
        for action in CustomGestureAction.allCases {
            let name = HotkeyTap.gestureNames[action.keyCode]
            XCTAssertNotNil(name, "\(action) is not a chord the tap knows")
            if action.holdsLeft {
                XCTAssertEqual(action.keyCode, CustomGestureAction.forwardClick.keyCode, "bind is ⬅️ held + 🔼")
            } else {
                XCTAssertTrue(name?.hasPrefix(action.glyph + " ⌃⌥⌘F") == true, "\(action): \(action.glyph) vs \(name ?? "")")
                XCTAssertTrue(seen.insert(action.keyCode).inserted, "\(action) repeats a chord")
            }
            XCTAssertFalse(action.title.isEmpty || action.detail.isEmpty || action.logi.isEmpty)
        }
        XCTAssertEqual(seen, Set(HotkeyTap.gestureNames.keys), "every Logi chord has a row")
    }

    // MARK: The translation, alone

    func testATriggerFiresItsActionAndItsReleaseIsTaken() {
        let store = memory()
        store.enabled = true
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        store.set(T(.mouse(0), [.option, .command]), for: .backClick)
        XCTAssertEqual(store.feed(.down(.mouse(2), [.command], autorepeat: false)), .fire(.forwardClick))
        XCTAssertEqual(store.feed(.up(.mouse(2))), .swallow, "down and up")
        XCTAssertEqual(store.feed(.up(.mouse(2))), .pass, "one release per press")
        XCTAssertEqual(store.feed(.down(.mouse(0), [.option, .command], autorepeat: false)), .fire(.backClick))
        // The release is taken whatever is held by then.
        XCTAssertEqual(store.feed(.up(.mouse(0))), .swallow)
    }

    func testTheBareWheelAndOtherModifiersPass() {
        let store = memory()
        store.enabled = true
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        XCTAssertEqual(store.feed(.down(.mouse(2), [], autorepeat: false)), .pass, "the crop's press")
        XCTAssertEqual(store.feed(.up(.mouse(2))), .pass)
        XCTAssertEqual(store.feed(.down(.mouse(2), [.command, .shift], autorepeat: false)), .pass, "exact modifiers")
        XCTAssertEqual(store.feed(.down(.mouse(1), [.command], autorepeat: false)), .pass)
        XCTAssertEqual(store.feed(.down(.key(40), [.command], autorepeat: false)), .pass)
        XCTAssertEqual(store.feed(.up(.key(40))), .pass)
    }

    func testOffTranslatesNothingButStillTakesAReleaseItOwes() {
        let store = memory()
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        XCTAssertFalse(store.live, "off: the tap asks nothing")
        XCTAssertEqual(store.feed(.down(.mouse(2), [.command], autorepeat: false)), .pass)
        store.enabled = true
        XCTAssertEqual(store.feed(.down(.mouse(2), [.command], autorepeat: false)), .fire(.forwardClick))
        store.enabled = false
        XCTAssertTrue(store.live, "unticked between the press and the release")
        XCTAssertEqual(store.feed(.up(.mouse(2))), .swallow)
        XCTAssertFalse(store.live)
    }

    func testAPassedPressNeverHasItsReleaseTaken() {
        let store = memory()
        store.enabled = true
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        // Taken, its release lost (the tap rebuilt, say), then a bare press.
        XCTAssertEqual(store.feed(.down(.mouse(2), [.command], autorepeat: false)), .fire(.forwardClick))
        XCTAssertEqual(store.feed(.down(.mouse(2), [], autorepeat: false)), .pass)
        XCTAssertEqual(store.feed(.up(.mouse(2))), .pass, "or the session keeps the button down")
    }

    func testRecordingAFrozenAppAndACropMatchNothing() {
        let store = memory()
        store.enabled = true
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        let press = CustomGestures.TapInput.down(.mouse(2), [.command], autorepeat: false)
        store.recording = true
        XCTAssertEqual(store.feed(press), .pass, "the recorder is listening")
        store.recording = false
        XCTAssertEqual(store.feed(press, frozen: true), .pass)
        XCTAssertEqual(store.feed(press, busy: true), .pass)
        XCTAssertEqual(store.feed(.up(.mouse(2))), .pass)
        // A press taken before the freeze still has its release taken in it.
        XCTAssertEqual(store.feed(press), .fire(.forwardClick))
        XCTAssertEqual(store.feed(.up(.mouse(2)), frozen: true), .swallow)
    }

    func testAKeyTriggerFiresOnceAndItsRepeatsAndReleaseAreTaken() {
        let store = memory()
        store.enabled = true
        store.set(T(.key(40), [.control, .option], keyLabel: "K"), for: .forwardLeft)
        XCTAssertEqual(store.feed(.down(.key(40), [.control, .option], autorepeat: false)), .fire(.forwardLeft))
        XCTAssertEqual(store.feed(.down(.key(40), [.control, .option], autorepeat: true)), .swallow)
        XCTAssertEqual(store.feed(.up(.key(40))), .swallow)
        XCTAssertEqual(store.feed(.down(.key(40), [.control, .option], autorepeat: true)), .pass,
                       "a repeat of a press that was not taken")
    }

    func testAnEventBecomesATapInput() {
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        down.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        down.flags = [.maskCommand, .maskSecondaryFn]
        XCTAssertEqual(CustomGestures.tapInput(.otherMouseDown, down), .down(.mouse(2), [.command], autorepeat: false))
        XCTAssertEqual(CustomGestures.tapInput(.otherMouseUp, down), .up(.mouse(2)))
        down.setIntegerValueField(.mouseEventButtonNumber, value: 4)
        XCTAssertNil(CustomGestures.tapInput(.otherMouseDown, down), "the side buttons are not this feature's")
        let key = CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: true)!
        key.flags = [.maskControl]
        XCTAssertEqual(CustomGestures.tapInput(.keyDown, key), .down(.key(40), [.control], autorepeat: false))
        XCTAssertEqual(CustomGestures.tapInput(.keyUp, key), .up(.key(40)))
        XCTAssertNil(CustomGestures.tapInput(.flagsChanged, key))
        XCTAssertNil(CustomGestures.tapInput(.otherMouseDragged, down))
    }

    // MARK: Through the tap's own `handle`

    private func mouse(_ type: CGEventType, button: Int, flags: CGEventFlags, at p: CGPoint = CGPoint(x: 400, y: 300)) -> CGEvent {
        let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p,
                        mouseButton: button == 0 ? .left : button == 1 ? .right : .center)!
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        e.flags = flags
        return e
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags, down: Bool = true) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = flags
        return e
    }

    private func drain(_ seconds: TimeInterval = 0.3) {
        let done = expectation(description: "queues drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 2)
    }

    private func tap(_ bind: (CustomGestures) -> Void) -> HotkeyTap {
        let tap = HotkeyTap()
        let store = memory()
        store.enabled = true
        bind(store)
        tap.customGestures = store
        return tap
    }

    /// ⌘ + wheel click runs 🔼's own branch (`onPasteToggle`), both halves of
    /// the click are taken, and the bare wheel is left alone.
    func testCmdWheelClickIsTheForwardClickAndBothHalvesAreSwallowed() {
        let tap = tap { $0.set(T(.mouse(2), [.command]), for: .forwardClick) }
        var prompts = 0, binds = 0
        tap.onPasteToggle = { prompts += 1 }
        tap.onGestureBindAndDictate = { binds += 1 }
        XCTAssertTrue(tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, button: 2, flags: .maskCommand)))
        XCTAssertTrue(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, button: 2, flags: .maskCommand)))
        drain()
        XCTAssertEqual(prompts, 1, "🔼's branch, once")
        XCTAssertEqual(binds, 0)
        // At rest the bare wheel click still goes to the app underneath.
        XCTAssertFalse(tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, button: 2, flags: [])))
        XCTAssertFalse(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, button: 2, flags: [])))
        drain(0.1)
        XCTAssertEqual(prompts, 1)
    }

    func testTheReleaseIsTakenEvenWithTheModifiersAlreadyUp() {
        let tap = tap { $0.set(T(.mouse(0), [.option, .command]), for: .forwardClick) }
        XCTAssertTrue(tap.takesForTesting(.leftMouseDown, mouse(.leftMouseDown, button: 0, flags: [.maskAlternate, .maskCommand])))
        XCTAssertTrue(tap.takesForTesting(.leftMouseUp, mouse(.leftMouseUp, button: 0, flags: [])))
        // And an ordinary click after it is nobody's.
        XCTAssertFalse(tap.takesForTesting(.leftMouseDown, mouse(.leftMouseDown, button: 0, flags: [])))
        XCTAssertFalse(tap.takesForTesting(.leftMouseUp, mouse(.leftMouseUp, button: 0, flags: [])))
    }

    /// *Bind and prompt* is ⬅️ held + 🔼: the same F7 branch, its bind half.
    func testBindAndPromptRunsTheLeftHeldBranch() {
        let tap = tap { $0.set(T(.mouse(1), [.control, .shift]), for: .bindAndPrompt) }
        var prompts = 0, binds = 0
        tap.onPasteToggle = { prompts += 1 }
        tap.onGestureBindAndDictate = { binds += 1 }
        XCTAssertTrue(tap.takesForTesting(.rightMouseDown, mouse(.rightMouseDown, button: 1, flags: [.maskControl, .maskShift])))
        XCTAssertTrue(tap.takesForTesting(.rightMouseUp, mouse(.rightMouseUp, button: 1, flags: [.maskControl, .maskShift])))
        drain()
        XCTAssertEqual(binds, 1)
        XCTAssertEqual(prompts, 0)
    }

    func testAKeyCombinationWorksTooInEitherGestureMode() {
        for logi in [true, false] {
            let tap = tap { $0.set(T(.key(40), [.control, .option], keyLabel: "K"), for: .forwardClick) }
            tap.useLogiGestures = logi
            var prompts = 0
            tap.onPasteToggle = { prompts += 1 }
            XCTAssertTrue(tap.takesForTesting(.keyDown, key(40, flags: [.maskControl, .maskAlternate])), "logi \(logi)")
            XCTAssertTrue(tap.takesForTesting(.keyUp, key(40, flags: [.maskControl, .maskAlternate], down: false)))
            drain()
            XCTAssertEqual(prompts, 1, "logi \(logi)")
        }
    }

    /// Unticked — his own setup — the tap is as it was: the same events pass.
    func testUntickedNothingIsTaken() {
        let tap = HotkeyTap()
        let store = memory()
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        tap.customGestures = store
        var prompts = 0
        tap.onPasteToggle = { prompts += 1 }
        XCTAssertFalse(tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, button: 2, flags: .maskCommand)))
        XCTAssertFalse(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, button: 2, flags: .maskCommand)))
        drain(0.1)
        XCTAssertEqual(prompts, 0)
    }

    /// The wheel-drag crop on a bare middle button, with ⌘ + wheel click bound.
    func testTheBareWheelDragStillCropsWithAWheelTriggerBound() {
        let tap = tap {
            $0.set(T(.mouse(2), [.command]), for: .backUp)
            $0.set(T(.mouse(0), [.command]), for: .forwardClick)
        }
        tap.dictating = true
        var shots = 0, prompts = 0
        tap.onAreaShot = { _, _ in shots += 1 }
        tap.onPasteToggle = { prompts += 1 }
        XCTAssertTrue(tap.takesForTesting(.otherMouseDown, mouse(.otherMouseDown, button: 2, flags: [], at: CGPoint(x: 100, y: 100))),
                      "held back for the crop, as before")
        XCTAssertTrue(tap.takesForTesting(.otherMouseDragged, mouse(.otherMouseDragged, button: 2, flags: [], at: CGPoint(x: 300, y: 300))))
        // ⌘ inside the selection moves the box — not a trigger while a crop is up.
        XCTAssertFalse(tap.takesForTesting(.leftMouseDown, mouse(.leftMouseDown, button: 0, flags: .maskCommand)))
        XCTAssertFalse(tap.takesForTesting(.leftMouseUp, mouse(.leftMouseUp, button: 0, flags: .maskCommand)))
        XCTAssertTrue(tap.takesForTesting(.otherMouseUp, mouse(.otherMouseUp, button: 2, flags: [], at: CGPoint(x: 300, y: 300))))
        drain()
        XCTAssertEqual(shots, 1)
        XCTAssertEqual(prompts, 0)
    }

    // MARK: The window

    func testTheRecorderBindsOrRefusesAndTheFooterSaysWhy() {
        let store = memory()
        let view = CustomGesturesView(store: store)
        XCTAssertNil(view.offer(T(.mouse(2), [.command]), for: .forwardClick))
        XCTAssertEqual(view.offer(T(.mouse(2), [.command]), for: .backClick), .taken(by: .forwardClick))
        XCTAssertEqual(view.offer(T(.mouse(0), []), for: .backClick), .bareClick)
        XCTAssertEqual(store.bindings, [.forwardClick: T(.mouse(2), [.command])])
        XCTAssertFalse(store.recording)
    }

    /// `CUSTOM_GESTURES_PNG=<dir> swift test --filter CustomGesturesTests` draws
    /// the window's content, dark and light, to look at.
    func testRenderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["CUSTOM_GESTURES_PNG"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = memory()
        store.enabled = true
        store.set(T(.mouse(2), [.command]), for: .forwardClick)
        store.set(T(.mouse(0), [.option, .command]), for: .forwardRight)
        store.set(T(.mouse(1), [.control, .shift]), for: .backClick)
        store.set(T(.key(40), [.control, .option], keyLabel: "K"), for: .forwardLeft)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let view = CustomGesturesView(store: store)
            view.appearance = NSAppearance(named: appearance)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let path = "\(dir)/custom-gestures-\(name).png"
            try png.write(to: URL(fileURLWithPath: path))
            print("custom gestures window (\(name)): \(Int(view.bounds.width)) × \(Int(view.bounds.height)) pt → \(path)")
        }
    }
}
