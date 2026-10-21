import XCTest
@testable import WalkieTalkie

/// `ShotMarker.place` and the shot token (2026-10-21): the token carries no
/// pointer, and a transcript whose timings stopped places nothing in the words.
final class ShotMarkerPlaceTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // `place` logs; keep it out of the installed app's relay.log.
        Outbox.home = FileManager.default.temporaryDirectory
            .appendingPathComponent("shot-marker-place-tests")
    }

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TimedWord {
        TimedWord(text: text, start: start, end: end, isSpacing: false)
    }

    private let shots = [1: ShotMarker.Token.shot(1, mouse: CGPoint(x: 1373, y: 863))]

    // MARK: - The token

    /// Victor, of `[📸1🖱️@1373:863]`: *"I want to get rid of this part in the image inserts"*.
    func testTheShotTokenCarriesNoPointer() {
        XCTAssertEqual(ShotMarker.Token.shot(1, mouse: CGPoint(x: 1373, y: 863)), "[📸1]")
        XCTAssertEqual(ShotMarker.Token.shot(0, mouse: CGPoint(x: 2012, y: 1100), auto: true), "[📸0 auto]")
        XCTAssertEqual(ShotMarker.Token.shot(2, mouse: nil, copied: true), "[📸2 📋 copied]")
        XCTAssertEqual(ShotMarker.Token.caption(shot: 1, mouse: CGPoint(x: 1204, y: 388)), "📸1")
        XCTAssertFalse(ShotMarker.Token.shot(3, mouse: CGPoint(x: 1, y: 2)).contains("🖱"))
    }

    // MARK: - Placement

    /// Healthy timings: the press lands in front of the first word not yet begun.
    func testAPressGoesInFrontOfTheFirstWordNotYetBegun() {
        let words = [word("as", 141.66, 141.78), word(" you", 141.78, 141.82), word(" can", 141.82, 141.94),
                     word(" see", 141.94, 142.08), word(" here,", 142.08, 142.28), word(" to", 142.42, 143.08),
                     word(" from", 143.08, 143.34), word(" walkie.", 143.34, 143.68)]
        let r = ShotMarker.place(words: words, cues: [.init(kind: .shot, index: 1, at: 142.77)], shots: shots)
        XCTAssertEqual(r.shots, [1])
        XCTAssertEqual(r.text, "as you can see here, to [📸1] from walkie.")
    }

    /// The 18:19:01 dictation (2026-10-21): the Large LoRA, decoded with mlx's
    /// default alignment heads, parked its last 69 words at 139.48 s, zero
    /// length each, while he spoke them until 164 s. The press at 142.77 s fell
    /// after every word and the picture went to the very end. Now it does not
    /// go into the words at all — the footer keeps it with its clock.
    func testAStoppedClockPlacesNothing() {
        var words = [word("I", 135.68, 136.00), word(" see", 136.00, 136.36), word(" that", 136.36, 136.72),
                     word(" the.", 136.72, 137.64), word("The", 137.64, 139.48)]
        for w in [" microphone", " is", " correctly", " set,", " as", " you", " can", " see", " here,",
                  " to", " from", " walkie."] {
            words.append(word(w, 139.48, 139.48))
        }
        XCTAssertEqual(ShotMarker.longestStoppedRun(words), 12)
        let r = ShotMarker.place(words: words, cues: [.init(kind: .shot, index: 1, at: 142.77)], shots: shots)
        XCTAssertEqual(r.shots, [])
        XCTAssertFalse(r.text.contains("📸"), r.text)
        XCTAssertEqual(r.text, words.map(\.text).joined())
    }

    /// Whisper's DTW gives a zero-length word or two now and then (≤ 2 in a row
    /// over 180 healthy decodes); that is noise, not a stopped clock.
    func testTwoZeroLengthWordsStillPlace() {
        let words = [word("look", 1.0, 1.3), word(" right", 1.3, 1.3), word(" now", 1.3, 1.3),
                     word(" here", 1.6, 1.9), word(" please", 2.0, 2.4)]
        XCTAssertEqual(ShotMarker.longestStoppedRun(words), 2)
        let r = ShotMarker.place(words: words, cues: [.init(kind: .shot, index: 1, at: 1.5)], shots: shots)
        XCTAssertEqual(r.shots, [1])
        XCTAssertEqual(r.text, "look right now [📸1] here please")
    }

    /// Scribe's `spacing` tokens are not words: a run of them at one instant
    /// says nothing about the clock.
    func testSpacingDoesNotCountAsAStoppedWord() {
        var words: [TimedWord] = []
        for i in 0..<10 {
            let t = Double(i)
            words.append(word("w\(i)", t, t + 0.5))
            words.append(TimedWord(text: " ", start: t + 0.5, end: t + 0.5, isSpacing: true))
        }
        XCTAssertEqual(ShotMarker.longestStoppedRun(words), 0)
    }
}
