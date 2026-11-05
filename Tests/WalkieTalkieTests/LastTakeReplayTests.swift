import XCTest
@testable import WalkieTalkie

final class LastTakeReplayTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("last-take-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fm.removeItem(at: root)
    }

    @discardableResult
    private func file(_ path: String, at date: Date) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    private func latest(cancelled: (url: URL, at: Date)? = nil) -> String? {
        LastTakeReplay.latest(corpusRoot: root.appendingPathComponent("corpus"), cancelled: cancelled)?.lastPathComponent
    }

    func testNothingFiledNothingToPlay() {
        XCTAssertNil(latest())
    }

    func testTheNewestWavOfTheNewestDay() throws {
        let now = Date()
        try file("corpus/2026-11-04/23-59-59-wispr1.wav", at: now)
        try file("corpus/2026-11-05/09-00-00-wispr2.wav", at: now.addingTimeInterval(-20))
        try file("corpus/2026-11-05/09-00-10-wispr3.wav", at: now.addingTimeInterval(-10))
        try file("corpus/2026-11-05/09-00-10-wispr3.txt", at: now)
        XCTAssertEqual(latest(), "09-00-10-wispr3.wav")
    }

    func testAnEmptyNewestDayFallsBackToTheDayBefore() throws {
        try file("corpus/2026-11-04/10-00-00-11l1.wav", at: Date())
        try fm.createDirectory(at: root.appendingPathComponent("corpus/2026-11-05"), withIntermediateDirectories: true)
        XCTAssertEqual(latest(), "10-00-00-11l1.wav")
    }

    func testACancelAfterTheLastFiledTakeWins() throws {
        let now = Date()
        try file("corpus/2026-11-05/09-00-00-wispr1.wav", at: now.addingTimeInterval(-10))
        let cancelled = try file("cancelled/cancelled-09-00-05.wav", at: now)
        XCTAssertEqual(latest(cancelled: (cancelled, now)), "cancelled-09-00-05.wav")
    }

    func testATakeFiledAfterTheCancelWins() throws {
        let now = Date()
        try file("corpus/2026-11-05/09-00-00-wispr1.wav", at: now)
        let cancelled = try file("cancelled/cancelled-08-59-00.wav", at: now.addingTimeInterval(-60))
        XCTAssertEqual(latest(cancelled: (cancelled, now.addingTimeInterval(-60))), "09-00-00-wispr1.wav")
    }

    /// 0.1 s of silence: the real `AVAudioPlayer`, no sound.
    private func silentWav() throws -> URL {
        let frames = 1600
        var wav = Data("RIFF".utf8)
        func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        wav += le(UInt32(36 + frames * 2)) + Data("WAVEfmt ".utf8) + le(UInt32(16))
        wav += le(UInt16(1)) + le(UInt16(1)) + le(UInt32(16000)) + le(UInt32(32000))
        wav += le(UInt16(2)) + le(UInt16(16)) + Data("data".utf8) + le(UInt32(frames * 2))
        wav += Data(count: frames * 2)
        let url = root.appendingPathComponent("silence.wav")
        try wav.write(to: url)
        return url
    }

    func testPlayingEndsByItself() throws {
        let replay = LastTakeReplay()
        XCTAssertTrue(replay.play(try silentWav()))
        XCTAssertNotNil(replay.playing)
        let ended = expectation(for: NSPredicate { _, _ in replay.playing == nil }, evaluatedWith: nil)
        wait(for: [ended], timeout: 5)
    }

    func testStopClearsWhatIsPlaying() throws {
        let replay = LastTakeReplay()
        XCTAssertTrue(replay.play(try silentWav()))
        replay.stop()
        XCTAssertNil(replay.playing)
    }

    func testAFileThatIsNotAudioIsRefused() throws {
        let replay = LastTakeReplay()
        XCTAssertFalse(replay.play(try file("corpus/2026-11-05/broken.wav", at: Date())))
        XCTAssertNil(replay.playing)
    }

    func testACancelWhoseFileIsGoneIsIgnored() throws {
        try file("corpus/2026-11-05/09-00-00-wispr1.wav", at: Date())
        let gone = root.appendingPathComponent("cancelled/gone.wav")
        XCTAssertEqual(latest(cancelled: (gone, Date())), "09-00-00-wispr1.wav")
    }
}
