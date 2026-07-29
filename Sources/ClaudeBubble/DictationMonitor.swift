import CoreAudio
import Foundation

/// Tracks whether Wispr Flow is recording *right now*.
///
/// Mouse 5 tells us a dictation probably started, but not when it ends, and it
/// misses every other way Wispr can be triggered (its own hotkey, the UI
/// button). The authoritative signal is CoreAudio: Wispr's process holds an
/// input stream open exactly while it listens
/// (`kAudioProcessPropertyIsRunningInput` on a `com.electron.wispr-flow.*`
/// process object) — the same probe Victor Addons uses to duck music.
///
/// This drives the bubble's "listening" state and the window during which
/// screenshots attach to the coming transcript.
final class DictationMonitor {

    /// Called on the poll queue whenever the recording state flips.
    var onChange: ((_ recording: Bool) -> Void)?

    private static let wisprBundlePrefix = "com.electron.wispr-flow"

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ro.victorrentea.claude-bubble.dictation")
    private(set) var isRecording = false

    func start(pollInterval: TimeInterval = 0.3) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Self.isWisprRecording()
            guard now != self.isRecording else { return }
            self.isRecording = now
            Log.info("wispr recording=\(now)")
            self.onChange?(now)
        }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private static func isWisprRecording() -> Bool {
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &listAddr, 0, nil, &size) == noErr else { return false }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return false }
        var procs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(sys, &listAddr, 0, nil, &size, &procs) == noErr else { return false }

        for p in procs {
            var bidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var bidSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(p, &bidAddr, 0, nil, &bidSize) == noErr else { continue }
            var bid: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(p, &bidAddr, 0, nil, &bidSize, &bid) == noErr else { continue }
            let bundle = (bid?.takeRetainedValue() as String?) ?? ""
            guard bundle.hasPrefix(wisprBundlePrefix) else { continue }

            var inAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var inSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(p, &inAddr, 0, nil, &inSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}
