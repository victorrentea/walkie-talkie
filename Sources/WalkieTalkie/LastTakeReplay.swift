import AVFoundation
import Foundation

/// **Hear the last dictation again** (2026-11-05). Victor: *"a feature to replay
/// the audio recorded during the last voice dictation, just the last one, not
/// more than that."*
///
/// **It records nothing of its own.** Every take already lands on disk: a finished
/// one in the corpus, a cancelled or failed one in `cancelled/` for Recover. The
/// last dictation is whichever of the two is newer, read from the disk each time,
/// so it survives a restart and there is no second copy to keep in step.
///
/// **Not while a microphone is open** — the speakers would be dictated — so a
/// sentence opening stops it (`AppDelegate.listening`). Main thread only.
final class LastTakeReplay: NSObject, AVAudioPlayerDelegate {

    /// The take to play: the newer of the corpus's last WAV and the kept cancel.
    static func latest(corpusRoot: URL, cancelled: (url: URL, at: Date)?,
                       fileManager fm: FileManager = .default) -> URL? {
        let kept = cancelled.flatMap { fm.fileExists(atPath: $0.url.path) ? $0 : nil }
        guard let filed = newestWav(in: corpusRoot, fileManager: fm) else { return kept?.url }
        guard let kept else { return filed.url }
        return kept.at > filed.at ? kept.url : filed.url
    }

    /// Day folders sort by name, so only the newest one holding a WAV is listed:
    /// the corpus only grows, and this runs at every menu open.
    private static func newestWav(in root: URL, fileManager fm: FileManager) -> (url: URL, at: Date)? {
        let days = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for day in days.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let files = (try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let dated = files.filter { $0.pathExtension == "wav" }.compactMap { url -> (url: URL, at: Date)? in
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { (url, $0) }
            }
            if let newest = dated.max(by: { $0.at < $1.at }) { return newest }
        }
        return nil
    }

    private var player: AVAudioPlayer?
    /// What is playing right now, nil at rest.
    private(set) var playing: URL?

    /// False when the file could not be played.
    func play(_ take: URL) -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: take) else {
            Log.error("🔊 replay: could not open \(take.lastPathComponent)")
            return false
        }
        player.delegate = self
        guard player.play() else {
            Log.error("🔊 replay: could not start \(take.lastPathComponent)")
            return false
        }
        self.player = player
        playing = take
        Log.info(String(format: "🔊 replaying %@ (%.1fs)", take.lastPathComponent, player.duration))
        return true
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        // A stop or a newer take has already replaced it.
        guard finished === player else { return }
        stop()
    }
}
