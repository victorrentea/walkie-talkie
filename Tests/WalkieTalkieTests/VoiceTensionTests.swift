import XCTest
@testable import WalkieTalkie

final class VoiceTensionTests: XCTestCase {

    /// A voice-like tone: a fundamental and two harmonics, at 16 kHz in int16 units.
    private func voice(hz: Float, seconds: Float) -> [Float] {
        (0..<Int(16000 * seconds)).map { i in
            let t = Float(i) / 16000
            return 3000 * (sin(2 * .pi * hz * t) + 0.5 * sin(4 * .pi * hz * t) + 0.25 * sin(6 * .pi * hz * t))
        }
    }

    func testThePitchIsFoundInSemitonesOver100Hz() throws {
        let p = VoiceTension.pitch(voice(hz: 150, seconds: 2))
        XCTAssertGreaterThan(p.count, 80)
        XCTAssertEqual(try XCTUnwrap(p.sorted().dropFirst(p.count / 2).first), 12 * log2(1.5), accuracy: 0.3)
    }

    func testAHighVoiceIsTenseAndALowOneIsNot() throws {
        let high = try XCTUnwrap(VoiceTension.reading(pitch: VoiceTension.pitch(voice(hz: 200, seconds: 5))))
        let low = try XCTUnwrap(VoiceTension.reading(pitch: VoiceTension.pitch(voice(hz: 110, seconds: 5))))
        XCTAssertTrue(high.tense)
        XCTAssertFalse(low.tense)
    }

    func testQuietSoundHasNoPitch() {
        let whisper = voice(hz: 150, seconds: 5).map { $0 / 100 }
        XCTAssertTrue(VoiceTension.pitch(whisper).isEmpty)
    }

    func testNoiseHasNoPitch() {
        var random = SystemRandomNumberGenerator()
        let noise = (0..<80000).map { _ in Float.random(in: -4000...4000, using: &random) }
        XCTAssertNil(VoiceTension.reading(pitch: VoiceTension.pitch(noise)))
    }

    func testUnderThreeSecondsOfVoiceSaysNothing() {
        XCTAssertNil(VoiceTension.reading(pitch: VoiceTension.pitch(voice(hz: 200, seconds: 2))))
    }

    func testASentenceWithNoTimedWordsCanCarryTheTag() {
        var report = VoiceAffect.analyse(words: [])
        XCTAssertNil(report.verdict.tag)
        report.verdict.tense = true
        XCTAssertEqual(report.verdict.tag, "[😡]")
    }

    func testTheTagIsAClauseSoTheModCanHideIt() {
        var verdict = VoiceAffect.Verdict()
        XCTAssertNil(verdict.tag)
        verdict.tense = true
        XCTAssertEqual(verdict.tag, "[😡]")
        verdict.hesitant = true
        XCTAssertEqual(verdict.tag, "[🤷‍♂️😡]")
    }
}
