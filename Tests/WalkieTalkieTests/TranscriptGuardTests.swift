import XCTest
@testable import WalkieTalkie

/// `TranscriptGuard` on sentences out of `voice-corpus/corpus.jsonl` (2026-11-04):
/// what Wispr delivered and what the local model heard on the same WAV.
final class TranscriptGuardTests: XCTestCase {

    private func held(_ text: String, unformatted: String? = nil, duration: TimeInterval = 5,
                      words: [TimedWord]? = nil) -> DictationResult {
        DictationResult(text: text, language: nil, audio: nil, duration: duration, engine: "wispr-flow",
                        warning: nil, delivery: .route, via: "wispr-history", markersInAudio: false,
                        engineLabel: "", words: words, unformatted: unformatted)
    }

    private func local(_ text: String) -> DictationResult {
        DictationResult(text: text, language: "ro", audio: nil, duration: 5, engine: "whisper-local",
                        warning: nil, delivery: .route, via: "local-forced", markersInAudio: true, engineLabel: "")
    }

    private func isWhole(_ text: String, line: UInt = #line) {
        guard case .wholeTake = TranscriptGuard.judge(text) else {
            return XCTFail("\(text) → \(String(describing: TranscriptGuard.judge(text)))", line: line)
        }
    }

    func testAnotherAlphabetIsSeen() {
        isWhole("مغربية.")
        isWhole("Чыфатчымат поккок")
        isWhole("시청해 주셔서 감사합니다")
        isWhole("Selected text 1. 去呀呀")
    }

    func testAnotherLanguageInLatinLettersIsSeen() {
        isWhole("Dá uma dá pra tirar critério desse")
        isWhole("to czekaj, najpierw jak ja kliknę raz. Po strzałce to kliknąłem sobie Enter?")
        isWhole("Dak diktée dakuma, ngou daay Enter?")
        isWhole("È scatta bocca castello come evidente. Selected text 1")
    }

    func testWhatHeReallySaysPasses() {
        for text in ["JDBC connection pool starvation",
                     "Stop asking me to test myself. Do test yourselves using Codex.",
                     "test, test, test, test",
                     "Fac un commit pe branch-ul de test și dau push.",
                     "Ce mașină am?",
                     "Calculează aria cu π și raza dată.",
                     "Pune α și β în formula de pe tablă.",
                     "Screenshot 1"] {
            XCTAssertNil(TranscriptGuard.judge(text), text)
        }
    }

    func testARunInsideGoodWordsIsLocated() {
        let text = "Unde ești, frate? ما هذا الميكروفون"
        guard case .foreignRun(let a, let b, _) = TranscriptGuard.judge(text + " " + String(repeating: "cuvânt bun ", count: 40)) else {
            return XCTFail("not a run")
        }
        XCTAssertEqual(a, 18)
        XCTAssertEqual(b, text.count)
    }

    func testTheLocalTailReplacesAForeignTail() {
        let head = String(repeating: "Trebuie să arăt asta pe ecran. ", count: 4)
        let s = held(head + "Și demonstrează în șapte din șapte cazuri Ε κοπυλόις πορνίτς.", duration: 30)
        let r = TranscriptGuard.resolve(s, retry: local(
            head + "Și demonstrează șapte din șapte cazuri pe copilot pornit.Sci."))
        XCTAssertEqual(r.outcome, "spliced")
        XCTAssertTrue(r.sentence.text.hasSuffix("în șapte din șapte cazuri pe copilot pornit. Sci."), r.sentence.text)
        XCTAssertEqual(r.sentence.via, "wispr-history")
    }

    func testAMidSentenceRunKeepsTheWordsAfterIt() {
        let tail = String(repeating: "Studiază puțin cum ar trebui să arate pe cer. ", count: 3)
        let r = TranscriptGuard.resolve(held("Ai studiat少し fizica fulgerelor, da? " + tail, duration: 16),
                                        retry: local("Ai studiat pe fizică fulgerilor, da? " + tail))
        XCTAssertEqual(r.outcome, "spliced")
        XCTAssertTrue(r.sentence.text.hasPrefix("Ai studiat pe fizica fulgerelor"), r.sentence.text)
    }

    func testAFewOrphanWordsAfterTheRunGoWithIt() {
        let head = String(repeating: "Pe bara dinspre viewpoint se vede schimbarea. ", count: 4)
        let r = TranscriptGuard.resolve(held(head + "Mi-ai colorat tot „Το territorio corriere loro”.", duration: 30),
                                        retry: local(head + "Mi-ai colorat tot teritoriul cortierilor."))
        XCTAssertEqual(r.outcome, "spliced")
        XCTAssertTrue(r.sentence.text.hasSuffix("colorat tot teritoriul cortierilor."), r.sentence.text)
    }

    /// 2026-09-27, 33 s: the local model said `Thank you. Thank you.` and nothing else.
    func testAHallucinationNeverReplacesThirtySecondsOfSpeech() {
        let good = String(repeating: "Traduce contentul în engleză și ține scurt tot textul. ", count: 5)
        let r = TranscriptGuard.resolve(held(good + "Βασανιζόταν το ποιμεν", duration: 33.7),
                                        retry: local("Thank you. Thank you."))
        XCTAssertEqual(r.outcome, "cut")
        XCTAssertEqual(r.sentence.text, good.trimmingCharacters(in: .whitespaces))
    }

    func testAWholeForeignTakeTakesTheLocalWords() {
        let r = TranscriptGuard.resolve(held("Dak diktée dakuma, ngou daay Enter?", duration: 7),
                                        retry: local("Dacă dictezi acuma, nu dai Enter?"))
        XCTAssertEqual(r.outcome, "replaced")
        XCTAssertEqual(r.sentence.text, "Dacă dictezi acuma, nu dai Enter?")
        XCTAssertEqual(r.sentence.via, TranscriptGuard.via)
    }

    func testTheLocalModelsInventionsAreSeen() {
        XCTAssertNotNil(TranscriptGuard.judgeLocal("Thank you.", duration: 6))
        XCTAssertNotNil(TranscriptGuard.judgeLocal("Thank you. Thank you.", duration: 33))
        XCTAssertNotNil(TranscriptGuard.judgeLocal("Bine.", duration: 20))
        XCTAssertNotNil(TranscriptGuard.judgeLocal("Вот я требую ye vs vs", duration: 7))
        XCTAssertNil(TranscriptGuard.judgeLocal("Move this from here to here. Thank you.", duration: 5))
        XCTAssertNil(TranscriptGuard.judgeLocal("Bine.", duration: 2))
        XCTAssertNil(TranscriptGuard.judgeLocal("Screenshot 1.", duration: 8))
    }

    func testScribesAnswerIsMarkedAsItsOwn() {
        var scribe = local("Dacă dictezi acuma, nu dai Enter?")
        scribe = DictationResult(text: scribe.text, language: "ron", audio: nil, duration: 7, engine: "elevenlabs",
                                 warning: nil, delivery: .route, via: TranscriptGuard.scribeVia, markersInAudio: true, engineLabel: "")
        let r = TranscriptGuard.resolve(held("Dak diktée dakuma, ngou daay Enter?", duration: 7), retry: scribe)
        XCTAssertEqual(r.sentence.via, TranscriptGuard.scribeVia)
    }

    func testTheLocalModelsOwnWordsAreReplacedWholeOrKept() {
        var mine = held("Thank you.", duration: 6)
        mine = DictationResult(text: mine.text, language: "en", audio: nil, duration: 6, engine: "whisper-local",
                               warning: nil, delivery: .route, via: "local-whisper", markersInAudio: true, engineLabel: "")
        XCTAssertEqual(TranscriptGuard.resolve(mine, retry: nil).outcome, "kept")
        XCTAssertEqual(TranscriptGuard.resolve(mine, retry: nil).sentence.warning, TranscriptGuard.unfixed)
    }

    func testNoUsableRetryStillDeliversTheSentence() {
        for retry in [nil, local("Я покупал"), local("Thank you.")] {
            let r = TranscriptGuard.resolve(held("Я покупал в этом магазине только молочные продукты", duration: 7), retry: retry)
            XCTAssertEqual(r.outcome, "kept")
            XCTAssertTrue(r.sentence.text.hasPrefix("Я покупал"))
            XCTAssertEqual(r.sentence.warning, TranscriptGuard.unfixed)
        }
    }

    /// A prompt carries `unformatted`, a plain sentence `text`: each is mended.
    func testBothFieldsAreMended() {
        let head = String(repeating: "Cum am dat drumul și a luat imaginea revine. ", count: 4)
        let r = TranscriptGuard.resolve(held(head + "Gata, merge bine.", unformatted: head + "revine animația Камикадзе.", duration: 30),
                                        retry: local(head + "revine animația Kamicadă."))
        XCTAssertEqual(r.sentence.text, head + "Gata, merge bine.")
        XCTAssertTrue(r.sentence.unformatted?.hasSuffix("revine animația Kamicadă.") == true, r.sentence.unformatted ?? "")
    }

    /// `ShotMarker.place` rebuilds a timed sentence from its words: no splice.
    func testTimedWordsAreNeverSpliced() {
        let good = String(repeating: "Trebuie să arăt asta pe ecran. ", count: 4)
        let timed = [TimedWord(text: "x", start: 0, end: 1, isSpacing: false)]
        let r = TranscriptGuard.resolve(held(good + "кончено", duration: 12, words: timed), retry: local(good + "gata"))
        XCTAssertEqual(r.outcome, "replaced")
    }
}
