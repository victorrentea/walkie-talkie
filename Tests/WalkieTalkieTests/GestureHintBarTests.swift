import XCTest
@testable import WalkieTalkie

/// The corner hint bar per stage: what each gesture does *now*, drawn as two
/// crosses — 🔼 then 🔽 (2026-09-30) — and nothing at all when no sentence is open.
final class GestureHintBarTests: XCTestCase {

    typealias Cross = GestureHintBar.Cross

func testTheHiddenSwitchIsOffUnlessSet() {
        let d = UserDefaults(suiteName: "hint-bar-hidden-test")!
        d.removePersistentDomain(forName: "hint-bar-hidden-test")
        XCTAssertFalse(GestureHintBar.hidden(defaults: d, environment: [:]))
        XCTAssertTrue(GestureHintBar.hidden(defaults: d, environment: ["WT_HINT_BAR": "0"]))
        XCTAssertFalse(GestureHintBar.hidden(defaults: d, environment: ["WT_HINT_BAR": "1"]))
        d.set(true, forKey: "hintBarHidden")
        XCTAssertTrue(GestureHintBar.hidden(defaults: d, environment: [:]))
        d.removePersistentDomain(forName: "hint-bar-hidden-test")
    }

        func testNothingWhenNotDictating() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init()), [])
    }

    func testAPromptIsVictorsSketch() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: true)), [
            Cross(click: "🏁 / ⌘⌘", up: "✨ new", down: "☠️", left: "🗑️ discard", right: nil),
            Cross(click: "📸 / ⌃P", up: "🔴 video", down: "⌨️ type", left: "", right: "🧠 model"),
        ])
    }

    func testABoundPromptOffersTheInterruptAndCrossesItOutOnceOn() {
        let on = GestureHintBar.crosses(for: .init(listening: true, prompting: true, interruptible: true))
        XCTAssertEqual(on[1].left, "🛑 interrupt")
        let marked = GestureHintBar.crosses(for: .init(listening: true, prompting: true,
                                                       interruptible: true, interrupt: true))
        XCTAssertEqual(marked[1].left, GestureHintBar.struck + "🛑")
        let question = GestureHintBar.crosses(for: .init(listening: true, prompting: true,
                                                         interruptible: true, quick: true))
        XCTAssertEqual(question[1].left, "")
    }

    func testTheFilmKamikazeAndSpawnFollowTheirState() {
        let c = GestureHintBar.crosses(for: .init(listening: true, prompting: true, filming: true,
                                                  kamikaze: true, spawn: true))
        XCTAssertEqual(c[0].up, "📂 folder", "a new session already marked: 🔼 ↑ opens the folder menu again")
        XCTAssertEqual(c[0].right, "🏁 end", "a spawn has nothing to flip to: 🔼 → ends it")
        XCTAssertEqual(c[0].down, "~☠️", "crossed out, no words")
        XCTAssertEqual(c[1].up, "⏹️ video")
        XCTAssertEqual(c[1].click, "⏹️ / ⌃P", "while a film runs the shutter is its stop (2026-10-23)")
    }

    /// 2026-10-25 (the hint audit): every gesture a plain sentence answers is
    /// drawn — 🔼 and 🔽 ↓ stop it, 🔼 → / 🔼 ↑ make it a prompt, 🔼 ↓ is the last
    /// prompt's kamikaze, 🔽 ← cancels.
    func testAPlainDictationShowsEveryGestureItAnswers() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: false)), [
            Cross(click: "⏹️", up: "✨ new", down: "☠️ last", left: "🗑️ discard", right: "💻 terminal"),
            Cross(click: "⏹️ + ⏎", up: "", down: "⏹️", left: "", right: "⏹️ ⌘⌘"),
        ])
    }

    /// 2026-10-09: a quick question's stop asks — no ⏎ promised. 2026-10-15:
    /// it is a prompt — 🔼 asks, 🔽 is the shutter, ↓ the typing box.
    /// 2026-10-25: 🔼 ↑ / 🔼 → send it to an agent instead, 🔽 ← cancels, 🔽 →
    /// Googles it. 2026-11-11: 🔼 ↓ Googles it and answers it.
    func testAQuickQuestionAsks() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: false, quick: true)), [
            Cross(click: "⚡ ask ⌘⌘", up: "✨ new", down: GestureHintBar.google + " + ⚡", left: "🗑️ discard", right: "💻 terminal"),
            Cross(click: "📸 / ⌃P", up: "", down: "⌨️ type", left: "", right: GestureHintBar.google + " Google"),
        ])
    }

    /// The keys with no gesture behind them, under the crosses (2026-10-22):
    /// ⌃P turns a plain dictation into a prompt, ⌘C files a copy.
    func testTheKeysRow() {
        XCTAssertEqual(GestureHintBar.keys(for: .init()), [])
        // 2026-11-22: copy is its icon alone, and a prompt (a ⚡ question too)
        // gains select — the selection watcher is off in a plain dictation.
        XCTAssertEqual(GestureHintBar.keys(for: .init(listening: true, prompting: false)),
                       ["💬 prompt ⌃P", GestureHintBar.copyKey])
        XCTAssertEqual(GestureHintBar.keys(for: .init(listening: true, prompting: true)),
                       [GestureHintBar.copyKey, GestureHintBar.selectKey])
        XCTAssertEqual(GestureHintBar.keys(for: .init(listening: true, prompting: false, quick: true)),
                       [GestureHintBar.copyKey, GestureHintBar.selectKey])
        XCTAssertEqual(GestureHintBar.keys(for: .init(listening: true, prompting: true, crop: .selecting)), [])
        XCTAssertEqual(GestureHintBar.keys(for: .init(listening: true, prompting: false, held: true)), [])
    }

    // MARK: glyphs with the mouse, keys without it (2026-11-22)

    /// Victor: *"afișează tastele … doar dacă nu e mouse-ul conectat … lasă doar
    /// emoji-urile … poți chiar să scoți textele cu totul"*.
    func testALabelLosesItsWordsAndKeepsItsKeyOnlyWithoutTheMouse() {
        let cases: [(String, String, String)] = [
            // full wording, with the mouse, without it
            ("🗑️ discard", "🗑️", "🗑️"),
            ("🏁 / ⌘⌘", "🏁", "🏁 / ⌘⌘"),
            ("📸 / ⌃P", "📸", "📸 / ⌃P"),
            ("⚡ ask ⌘⌘", "⚡", "⚡ / ⌘⌘"),
            ("⏹️ ⌘⌘", "⏹️", "⏹️ / ⌘⌘"),
            ("🎙️ dictate ⌘⌘", "🎙️", "🎙️ / ⌘⌘"),
            ("🔴 ✂️ video", "🔴 ✂️", "🔴 ✂️"),
            ("⏹️ + ⏎", "⏹️ + ⏎", "⏹️ + ⏎"),
            (GestureHintBar.google + " + ⚡", GestureHintBar.google + " + ⚡", GestureHintBar.google + " + ⚡"),
            (GestureHintBar.google + " Google", GestureHintBar.google, GestureHintBar.google),
            ("➡️ move to", "➡️", "➡️"),
            ("~☠️", "~☠️", "~☠️"),
            ("⏎", "⏎", "⏎"),
            ("", "", ""),
            // No glyph to fall back on: the words stay, unless they name a key.
            ("Esc cancel", "", "Esc cancel"),
            ("interrupt", "interrupt", "interrupt"),
        ]
        for (full, mouse, noMouse) in cases {
            XCTAssertEqual(GestureHintBar.shown(full, keys: false), mouse, "\(full) with the mouse")
            XCTAssertEqual(GestureHintBar.shown(full, keys: true), noMouse, "\(full) without it")
        }
    }

    /// With the Logitech mouse attached no badge of any stage carries a word
    /// or a key; whatever `crosses` learns to say later is cut the same way.
    func testWithTheMouseEveryBadgeIsGlyphsAlone() {
        let stages: [GestureHintBar.Stage] = [
            .init(listening: true, prompting: true),
            .init(listening: true, prompting: true, filming: true, areaFilm: true, kamikaze: true, spawn: true),
            .init(listening: true, prompting: true, areaFilm: true),
            .init(listening: true, prompting: false),
            .init(listening: true, prompting: false, quick: true),
            .init(listening: true, prompting: true, crop: .selecting),
            .init(listening: true, prompting: true, crop: .locked),
            .init(listening: true, prompting: true, crop: .parked),
            .init(listening: true, prompting: true, crop: .drawing),
            .init(fingers: true),
            .init(listening: true, prompting: true, fingers: true),
        ]
        for stage in stages {
            let bar = GestureHintBar.bar(for: stage)
            XCTAssertFalse(bar.isEmpty, "\(stage)")
            var labels = bar.crosses.flatMap { [$0.click, $0.up, $0.down, $0.left, $0.right] }.compactMap { $0 } + bar.keys
            if let m = bar.mouse { labels += [m.left, m.wheel, m.right, m.body] }
            for label in labels {
                XCTAssertFalse(label.contains { $0.isASCII && $0.isLetter }, "a word in “\(label)” — \(stage)")
                XCTAssertFalse(label.contains { "⌘⌃⌥⇧/".contains($0) }, "a key in “\(label)” — \(stage)")
            }
        }
    }

    func testAPromptsBarWithTheMouseAndWithout() {
        let mouse = GestureHintBar.bar(for: .init(listening: true, prompting: true))
        XCTAssertEqual(mouse.crosses, [
            Cross(click: "🏁", up: "✨", down: "☠️", left: "🗑️", right: nil),
            Cross(click: "📸", up: "🔴", down: "⌨️", left: "", right: "🧠"),
        ])
        XCTAssertEqual(mouse.keys, [GestureHintBar.copyKey, GestureHintBar.selectKey])

        // No Logitech mouse: the trackpad's crosses, the keys back in their badges.
        let none = GestureHintBar.bar(for: .init(listening: true, prompting: true, noMouse: true))
        XCTAssertEqual(none.crosses, [
            Cross(click: "🏁 / ⌘⌘", up: "✨", down: "☠️", left: "🗑️", right: nil, corner: "☝️"),
            Cross(click: "📸 / ⌃P", up: "🔴", down: "⌨️", left: "", right: "🧠", corner: "✌️"),
        ])
        XCTAssertEqual(none.keys, [GestureHintBar.copyKey, GestureHintBar.selectKey])
    }

    /// `💬 prompt ⌃P` is a key with no gesture behind it: without the mouse it
    /// is `💬 / ⌃P`, with it the row is the Copy icon alone.
    func testAPlainDictationsBarWithTheMouseAndWithout() {
        let mouse = GestureHintBar.bar(for: .init(listening: true, prompting: false))
        XCTAssertEqual(mouse.crosses, [
            Cross(click: "⏹️", up: "✨", down: "☠️", left: "🗑️", right: "💻"),
            Cross(click: "⏹️ + ⏎", up: "", down: "⏹️", left: "", right: "⏹️"),
        ])
        XCTAssertEqual(mouse.keys, [GestureHintBar.copyKey])
        let none = GestureHintBar.bar(for: .init(listening: true, prompting: false, noMouse: true))
        XCTAssertEqual(none.crosses[1].right, "⏹️ / ⌘⌘")
        XCTAssertEqual(none.keys, ["💬 / ⌃P", GestureHintBar.copyKey])
    }

    func testACropsMouseWithTheMouseAndWithout() {
        XCTAssertEqual(GestureHintBar.bar(for: .init(listening: true, prompting: true, crop: .selecting)).mouse,
                       GestureHintBar.MouseHint(wheel: "✂️", right: "➡️", body: ""))
        XCTAssertEqual(GestureHintBar.bar(for: .init(listening: true, prompting: true, crop: .parked, noMouse: true)).mouse,
                       GestureHintBar.MouseHint(left: "📍", wheel: "🎯", right: "🗑️", body: "Esc cancel"))
    }

    /// The trackpad's crosses at rest, the chord held with the mouse attached
    /// and with none.
    func testTheFingersAtRestWithTheMouseAndWithout() {
        XCTAssertEqual(GestureHintBar.bar(for: .init(fingers: true)).crosses, [
            Cross(click: "💬", up: "✨", down: "☠️", left: "⚡", right: "💻", corner: "☝️"),
            Cross(click: "🎙️", up: "", down: "🔌", left: "⏎", right: "🎙️", corner: "✌️"),
        ])
        XCTAssertEqual(GestureHintBar.bar(for: .init(fingers: true, noMouse: true)).crosses[1].click, "🎙️ / ⌘⌘")
    }

    /// The point of it: *"mai puțin late acele badge-uri"*. 260 pt before.
    func testThePromptsBarIsUnderHalfItsOldWidth() {
        let bar = GestureHintBar.bar(for: .init(listening: true, prompting: true))
        XCTAssertLessThanOrEqual(GestureHintBar.Board.size(for: bar.crosses, mouse: bar.mouse, keys: bar.keys).width, 130)
    }

    func testNothingWhileRightCmdOptIsHeld() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: false, held: true)), [])
    }

    /// Left ⌃⌥⌘ held: the trackpad's crosses — ☝️ and ✌️ before their clicks —
    /// at rest what each gesture starts, mid-sentence the side buttons' own (2026-10-20).
    func testTheTrackpadsCrossesCarryTheFingers() {
        XCTAssertEqual(GestureHintBar.fingerCrosses(for: .init(fingers: true)), [
            Cross(click: "💬 prompt", up: "✨ new", down: "☠️", left: "⚡ ask", right: "💻 terminal", corner: "☝️"),
            Cross(click: "🎙️ dictate ⌘⌘", up: "", down: "🔌 unbind", left: "⏎", right: "🎙️ dictate", corner: "✌️"),
        ])
        XCTAssertEqual(GestureHintBar.fingerCrosses(for: .init(listening: true, prompting: true, fingers: true)), [
            Cross(click: "🏁 / ⌘⌘", up: "✨ new", down: "☠️", left: "🗑️ discard", right: nil, corner: "☝️"),
            Cross(click: "📸 / ⌃P", up: "🔴 video", down: "⌨️ type", left: "", right: "🧠 model", corner: "✌️"),
        ])
        XCTAssertEqual(GestureHintBar.fingerCrosses(for: .init(listening: true, prompting: false, noMouse: true))[1].right, "⏹️ ⌘⌘")
    }

    /// One finger is 🔼, two are 🔽, and each direction is the chord with the
    /// same arrow in its name (`HotkeyTap.gestureNames`).
    func testEverySwipeIsTheSideButtonsChord() {
        let arrows: [HotkeyTap.PadDirection: String] = [.up: "↑", .down: "↓", .left: "←", .right: "→"]
        for fingers in [1, 2] {
            for (d, arrow) in arrows {
                let name = HotkeyTap.gestureNames[HotkeyTap.padChordKey(fingers: fingers, d)] ?? ""
                XCTAssertTrue(name.hasPrefix((fingers == 1 ? "🔼 " : "🔽 ") + arrow), "\(fingers) \(d) → \(name)")
            }
        }
    }

    /// The pin's ring: linear to the local hand-over, full there, and it stays full.
    func testThePinsRingFillsToTheHandOver() {
        XCTAssertEqual(DropArrow.progress(elapsed: 0, span: 5), 0)
        XCTAssertEqual(DropArrow.progress(elapsed: 2.5, span: 5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DropArrow.progress(elapsed: 60, span: 5), 1)
        XCTAssertEqual(DropArrow.progress(elapsed: 5, span: 0), 0)
    }

    func testASwipeIsOneAxisPastTheDistance() {
        XCTAssertNil(HotkeyTap.padDirection(CGPoint(x: 0, y: 79), distance: 80))
        XCTAssertEqual(HotkeyTap.padDirection(CGPoint(x: 10, y: 80), distance: 80), .up)
        XCTAssertEqual(HotkeyTap.padDirection(CGPoint(x: -90, y: 20), distance: 80), .left)
        XCTAssertNil(HotkeyTap.padDirection(CGPoint(x: 90, y: 80), distance: 80), "a diagonal is no swipe")
    }

    /// A crop draws the mouse, and its right button says what one click does
    /// right now (2026-10-07).
    func testCropDrawsTheMouse() {
        XCTAssertNil(GestureHintBar.mouse(for: .init(listening: true, prompting: true)))
        XCTAssertEqual(GestureHintBar.mouse(for: .init(listening: true, crop: .selecting))?.right, "➡️ move to")
        XCTAssertEqual(GestureHintBar.mouse(for: .init(listening: true, crop: .locked))?.right, "↩️ unlock")
        XCTAssertEqual(GestureHintBar.mouse(for: .init(listening: true, crop: .parked))?.right, "🗑️ discard")
        XCTAssertEqual(GestureHintBar.mouse(for: .init(listening: true, crop: .parked))?.left, "📍 drop")
        XCTAssertNil(GestureHintBar.mouse(for: .init(listening: true, held: true, crop: .selecting)))
    }

    /// `HINT_BAR_PNG=<dir> swift test --filter GestureHintBarTests` draws each
    /// stage over a dark and a light desktop, to look at.
    /// After a wheel crop, 🔽 ↑ films the area — and says so (2026-11-21).
    func testAreaFilmIsNamedOnBackUp() {
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: true, areaFilm: true))[1].up,
                       "🔴 ✂️ video")
        XCTAssertEqual(GestureHintBar.crosses(for: .init(listening: true, prompting: true, filming: true,
                                                         areaFilm: true))[1].up, "⏹️ video")
    }

    func testRenderForReview() throws {
        guard let dir = ProcessInfo.processInfo.environment["HINT_BAR_PNG"] else { return }
        let stages: [(String, GestureHintBar.Stage)] = [
            ("prompt", .init(listening: true, prompting: true)),
            ("prompt-area", .init(listening: true, prompting: true, areaFilm: true)),
            ("prompt-filming", .init(listening: true, prompting: true, filming: true, kamikaze: true, spawn: true)),
            ("plain", .init(listening: true, prompting: false)),
            ("quick", .init(listening: true, prompting: false, quick: true)),
            ("crop", .init(listening: true, prompting: true, crop: .selecting)),
            ("crop-locked", .init(listening: true, prompting: true, crop: .locked)),
            ("crop-parked", .init(listening: true, prompting: true, crop: .parked)),
            ("fingers", .init(fingers: true)),
            ("fingers-prompt", .init(listening: true, prompting: true, fingers: true)),
            ("no-mouse-plain", .init(listening: true, prompting: false, noMouse: true)),
            ("no-mouse-prompt", .init(listening: true, prompting: true, noMouse: true)),
            ("no-mouse-quick", .init(listening: true, prompting: false, quick: true, noMouse: true)),
            ("no-mouse-crop", .init(listening: true, prompting: true, crop: .selecting, noMouse: true)),
            ("no-mouse-fingers", .init(fingers: true, noMouse: true)),
        ]
        // Drawn as across the seam: three times the size, solid (`spot`).
        let k = GestureHintBar.offRetinaScale
        for (name, stage) in stages {
            for (bgName, bg) in [("dark", NSColor(white: 0.12, alpha: 1)), ("light", NSColor(white: 0.93, alpha: 1))] {
                let bar = GestureHintBar.bar(for: stage)
                let (crosses, mouse, keys) = (bar.crosses, bar.mouse, bar.keys)
                var size = GestureHintBar.Board.size(for: crosses, mouse: mouse, keys: keys)
                if bgName == "dark" { print("hint bar \(name): \(Int(size.width)) × \(Int(size.height)) pt") }
                size = NSSize(width: size.width * k, height: size.height * k)
                let board = GestureHintBar.Board(frame: NSRect(x: 20, y: 20, width: size.width, height: size.height))
                board.crosses = crosses
                board.mouse = mouse
                board.keys = keys
                board.scale = k
                board.opacity = GestureHintBar.acrossOpacity
                let host = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 40, height: size.height + 40))
                host.wantsLayer = true
                host.layer?.backgroundColor = bg.cgColor
                host.addSubview(board)
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(bgName).png"))
            }
        }
    }

    // MARK: where it goes (2026-09-30) — Victor's desk: Retina + three DELLs

    typealias Display = GestureHintBar.Display
    let size = NSSize(width: 200, height: 100)
    let retina = Display(frame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                         visible: NSRect(x: 0, y: 0, width: 1728, height: 1079), builtIn: true)
    func dell(_ x: CGFloat, _ y: CGFloat) -> Display {
        let f = NSRect(x: x, y: y, width: 1920, height: 1080)
        return Display(frame: f, visible: f, builtIn: false)
    }

    func testRightOfTheRetinaWinsAgainstItsLeftEdge() {
        let r = GestureHintBar.placement(size: size, on: [dell(-89, 1117), dell(-1920, 37), retina, dell(1728, 37)])
        XCTAssertEqual(r, NSRect(x: 1728 + 16, y: 37 + 16, width: 200, height: 100))
    }

    func testLeftScreenAgainstItsRightEdge() {
        let r = GestureHintBar.placement(size: size, on: [retina, dell(-1920, 37)])
        XCTAssertEqual(r, NSRect(x: -16 - 200, y: 37 + 16, width: 200, height: 100))
    }

    func testAboveTheRetinaOnItsBottomEdgeOverTheRetina() {
        let r = GestureHintBar.placement(size: size, on: [retina, dell(-89, 1117)])
        XCTAssertEqual(r, NSRect(x: 1728 - 200 - 16, y: 1117 + 16, width: 200, height: 100))
    }

    func testThreeTimesBiggerOffTheRetina() {
        XCTAssertEqual(GestureHintBar.scale(on: [retina]), 1)
        XCTAssertEqual(GestureHintBar.scale(on: [retina, dell(1728, 37)]), 3)
        XCTAssertEqual(GestureHintBar.scale(on: [dell(0, 0)]), 3)
    }

    func testTheRetinaAloneKeepsItsCorner() {
        let r = GestureHintBar.placement(size: size, on: [retina])
        XCTAssertEqual(r, NSRect(x: 1728 - 200 - 16, y: 16, width: 200, height: 100))
    }

    // MARK: across the seam, solid; the pointer there sends it back (2026-10-01)

    let base = NSSize(width: 200, height: 100)

    func testAcrossTheSeamItIsSolidAndBig() {
        let s = GestureHintBar.spot(base: base, on: [retina, dell(1728, 37)], pointer: NSPoint(x: 800, y: 500))
        XCTAssertEqual(s, .init(rect: NSRect(x: 1728 + 16, y: 37 + 16, width: 600, height: 300),
                                scale: 3, opacity: 1))
    }

    func testThePointerOnThatScreenSendsItToTheRetinasSideOfTheSeam() {
        let s = GestureHintBar.spot(base: base, on: [retina, dell(1728, 37)], pointer: NSPoint(x: 2500, y: 500))
        XCTAssertEqual(s, .init(rect: NSRect(x: 1728 - 200 - 16, y: 37 + 16, width: 200, height: 100),
                                scale: 1, opacity: GestureHintBar.fledOpacity))
    }

    func testAThirdScreenLeavesItAcrossTheSeam() {
        let s = GestureHintBar.spot(base: base, on: [dell(-1920, 37), retina, dell(1728, 37)],
                                    pointer: NSPoint(x: -500, y: 500))
        XCTAssertEqual(s?.opacity, 1)
        XCTAssertEqual(s?.rect.minX, 1728 + 16)
    }

    func testFledFromALeftScreenItHugsTheRetinasLeftEdge() {
        let s = GestureHintBar.spot(base: base, on: [retina, dell(-1920, 37)], pointer: NSPoint(x: -500, y: 500))
        XCTAssertEqual(s?.rect, NSRect(x: 16, y: 37 + 16, width: 200, height: 100))
    }

    func testTheRetinaAloneHasNowhereToFlee() {
        let s = GestureHintBar.spot(base: base, on: [retina], pointer: NSPoint(x: 800, y: 500))
        XCTAssertEqual(s, .init(rect: NSRect(x: 1728 - 200 - 16, y: 16, width: 200, height: 100),
                                scale: 1, opacity: GestureHintBar.aloneOpacity))
    }

    // MARK: alone, the pointer coming near hides it (2026-10-08)

    func testTheRetinaAloneHidesFromThePointerOnIt() {
        let s = GestureHintBar.spot(base: base, on: [retina], pointer: NSPoint(x: 1700, y: 20))
        XCTAssertEqual(s?.opacity, 0)
        XCTAssertEqual(s?.rect, NSRect(x: 1728 - 200 - 16, y: 16, width: 200, height: 100))
    }

    func testTheRetinaAloneHidesFromThePointerApproaching() {
        // 1512 is the bar's left edge; 60 pt short of it is inside the dodge.
        let near = GestureHintBar.spot(base: base, on: [retina], pointer: NSPoint(x: 1512 - 60, y: 60))
        XCTAssertEqual(near?.opacity, 0)
        let far = GestureHintBar.spot(base: base, on: [retina], pointer: NSPoint(x: 1512 - 100, y: 60))
        XCTAssertEqual(far?.opacity, GestureHintBar.aloneOpacity)
    }
}

/// 🛟 A two-finger swipe's tail under left ⌃⌥⌘ — and nothing past it (2026-10-31).
final class PadScrollTailTests: XCTestCase {
    private func step(_ owned: Bool, chord: Bool, phase: Int64, momentum: Int64 = 0) -> (owned: Bool, ours: Bool) {
        HotkeyTap.padScrollTail(owned: owned, chordDown: chord, phase: phase, momentum: momentum)
    }

    /// The trap: keys up before the fingers, then the mouse's smooth wheel —
    /// continuous, no phase — must reach the app.
    func testAPhaselessWheelAfterAnOwnedSwipeIsNotSwallowed() {
        var s = step(false, chord: true, phase: 1)          // began under the chord
        XCTAssertTrue(s.ours); XCTAssertTrue(s.owned)
        s = step(s.owned, chord: false, phase: 2)           // keys up, fingers still moving
        XCTAssertTrue(s.ours, "the rest of the swipe is still ours")
        s = step(s.owned, chord: false, phase: 0)           // a Logi smooth-wheel event
        XCTAssertFalse(s.ours, "a scroll in no gesture must never be eaten")
    }

    func testMomentumAfterAnOwnedSwipeIsSwallowedUntilItEnds() {
        var s = step(false, chord: true, phase: 1)
        s = step(s.owned, chord: false, phase: 4)           // fingers lifted
        XCTAssertTrue(s.ours)
        s = step(s.owned, chord: false, phase: 0, momentum: 1)
        XCTAssertTrue(s.ours, "a page must not coast on a swipe")
        s = step(s.owned, chord: false, phase: 0, momentum: 2)
        XCTAssertTrue(s.ours)
        s = step(s.owned, chord: false, phase: 0, momentum: 3)
        XCTAssertFalse(s.owned, "momentum's end ends the tail")
        s = step(s.owned, chord: false, phase: 0, momentum: 1)
        XCTAssertFalse(s.ours)
    }

    func testAGestureBegunWithoutTheChordIsNeverOwned() {
        let s = step(true, chord: false, phase: 1)          // stale ownership, new gesture
        XCTAssertFalse(s.owned); XCTAssertFalse(s.ours)
    }
}
