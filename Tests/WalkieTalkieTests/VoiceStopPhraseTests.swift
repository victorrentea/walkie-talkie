import XCTest
@testable import WalkieTalkie

final class VoiceStopPhraseTests: XCTestCase {
    func testThePhrasesAtTheEndStopIt() {
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "Gepetto, over."), "Gepetto, over")
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "OK, thanks. Geppetto over!"), "Gepetto, over")
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "Jepeto, over"), "Gepetto, over")
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "Mulțumesc, over and out."), "over and out")
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "Pinocchio."), "Pinocchio")
        XCTAssertEqual(VoiceDialog.stopPhrase(in: "gata, Pinokio"), "Pinocchio")
    }
    func testMidSentenceIsTalk() {
        XCTAssertNil(VoiceDialog.stopPhrase(in: "Pinocchio was written by Collodi"))
        XCTAssertNil(VoiceDialog.stopPhrase(in: "Gepetto over there made a puppet"))
        XCTAssertNil(VoiceDialog.stopPhrase(in: "the game is over"))
        XCTAssertNil(VoiceDialog.stopPhrase(in: "hand over and outline it"))
        XCTAssertNil(VoiceDialog.stopPhrase(in: ""))
    }
}
