import AppKit
import XCTest
@testable import WalkieTalkie

final class RoomPickTests: XCTestCase {
    private let json = #"{"ok":true,"seconds":30,"lines":2,"words":12,"transcript":"[17:52] Kafka was written in Go.\n[17:52] It keeps offsets per partition.","speech":"Kafka was written in Go. It keeps offsets per partition."}"#

    func testVictorMacsAnswerIsParsed() throws {
        let room = try XCTUnwrap(RoomTranscript.parse(Data(json.utf8)))
        XCTAssertEqual(room.seconds, 30)
        XCTAssertEqual(room.words, 12)
        XCTAssertTrue(room.usable)
        XCTAssertTrue(room.transcript.hasPrefix("[17:52] Kafka"))
        XCTAssertNil(RoomTranscript.parse(Data(#"{"ok":false,"error":"no transcription folder"}"#.utf8)))
        XCTAssertNil(RoomTranscript.parse(Data("forbidden".utf8)))
    }

    func testAFewWordsAreNotADiscussion() {
        XCTAssertFalse(RoomTranscript(seconds: 30, transcript: "[17:52] ok", speech: "ok", words: 1).usable)
    }

    func testTheHeaderIsHisWordsOrTheQuote() throws {
        let room = try XCTUnwrap(RoomTranscript.parse(Data(json.utf8)))
        XCTAssertEqual(room.header(asked: "is that true?"), "is that true? · 🎙️ 30 s")
        XCTAssertEqual(room.header(asked: "  "), "🎙️ 30 s «Kafka was written in Go. It keeps offsets per partition.»")
        XCTAssertEqual(room.quote(limit: 10), "…partition.")
    }

    func testThePromptMakesTheWindowTheTopic() throws {
        let room = try XCTUnwrap(RoomTranscript.parse(Data(json.utf8)))
        let alone = room.prompt(question: nil)
        XCTAssertTrue(alone.contains("overheard"))
        XCTAssertTrue(alone.contains("last 30 seconds"))
        XCTAssertTrue(alone.contains("[17:52] Kafka was written in Go."))
        XCTAssertTrue(alone.contains("the topic to research"))
        XCTAssertTrue(alone.contains("one short line each"))
        let asked = room.prompt(question: "Is Kafka really in Go?")
        XCTAssertTrue(asked.contains("[17:52] Kafka was written in Go."))
        XCTAssertTrue(asked.contains("My question, with that discussion as its topic:\nIs Kafka really in Go?"))
        XCTAssertFalse(asked.contains("the topic to research"))
    }

    /// 2026-11-27: the last 15 s too, for a question about what was *just* said.
    func testTheWindowsAre15And30And60SecondsShortestFirst() {
        XCTAssertEqual(RoomTranscript.windows, [15, 30, 60])
    }

    func testTheModalDrawsIntoAPNG() throws {
        let room = try XCTUnwrap(RoomTranscript.parse(Data(json.utf8)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("room-pick-\(UUID()).png")
        XCTAssertTrue(RoomPick.snapshot([15: room, 30: room], to: url))
        XCTAssertGreaterThan((try? Data(contentsOf: url))?.count ?? 0, 1000)
        try? FileManager.default.removeItem(at: url)
    }

    /// The reply pop-up's words, selected in a window that is never key: clay, not grey.
    func testTheSelectionIsClayInAWindowThatIsNotKey() throws {
        let storage = NSTextStorage(string: "Kafka keeps offsets per partition.",
                                    attributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.white])
        let layout = ClaySelectionLayout()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 600, height: 100))
        layout.addTextContainer(container)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100), textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // A point inside "Kafka"'s selection band, left of its first letter's ink is hard to
        // hit — sample the whole band and look for clay.
        let band = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 5), in: container)
        var clay = 0
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        for x in stride(from: band.minX + 1, to: band.maxX - 1, by: 2) {
            for y in stride(from: band.minY + 1, to: band.maxY - 1, by: 2) {
                guard let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB) else { continue }
                // Clay's hue, whatever the rep's colour space did to the exact value.
                if c.redComponent > 0.7, c.greenComponent > 0.35, c.greenComponent < 0.6,
                   c.blueComponent > 0.25, c.blueComponent < 0.5 { clay += 1 }
            }
        }
        XCTAssertGreaterThan(clay, 20, "the selection band should be filled clay (#D97757)")
    }
}
