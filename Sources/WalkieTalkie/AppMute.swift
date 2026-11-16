import AudioToolbox
import CoreAudio
import Foundation

/// **One app's sound, off for a moment** (2026-11-16). Victor, about the chime the
/// ChatGPT app plays when a voice chat connects and hangs up: *"un sunet cling foarte
/// nefericit"*, and, once the call ran in the window and it was still there: *"se mai
/// aude, fă varianta 2"* — mute only ChatGPT around the connect and the hang-up, so
/// Walkie's own radio sound is the one he hears.
///
/// **Why not the file:** the clips (`realtime-start` / `realtime-end`, ~1.5 s) are
/// inside `app.asar`, whose hash `Info.plist` pins (`ElectronAsarIntegrity`); the app
/// is signed and every update replaces it. There is no setting (asked for in
/// openai/codex#61842).
///
/// **How:** a Core Audio process tap (macOS 14.2+) over the app's audio processes with
/// `muteBehavior = .muted` — what the tap takes does not reach the hardware — read by
/// a private aggregate device whose IO only measures. Nothing else is touched: other
/// apps, this one's sounds and the output volume play on. `end()` logs when the tap
/// first and last heard something, which is the only witness that the window covered
/// the chime. Needs the *System Audio Recording* grant (`NSAudioCaptureUsageDescription`);
/// refused or unavailable, `begin` returns nil and the chime is simply heard.
@available(macOS 14.2, *)
final class AppMute {

    private let tap: AudioObjectID
    private let device: AudioObjectID
    private var proc: AudioDeviceIOProcID?
    private let began = CFAbsoluteTimeGetCurrent()
    private let lock = NSLock()
    private var firstHeard: Double?
    private var lastHeard: Double?
    private var ended = false
    private let what: String

    /// Mutes every audio process whose bundle id starts with `bundlePrefix`, from now
    /// until `end()`. Nil when there is none, or Core Audio refuses.
    static func begin(bundlePrefix: String, what: String) -> AppMute? {
        let objects = processObjects(bundlePrefix: bundlePrefix)
        guard !objects.isEmpty else { return nil }
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .muted
        description.isPrivate = true
        description.name = "Walkie Talkie hush"
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { Log.error("🔇 app mute — no process tap (\(status))"); return nil }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Walkie Talkie hush",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: false]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else {
            Log.error("🔇 app mute — no aggregate device (\(status))")
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        let mute = AppMute(tap: tap, device: device, what: what)
        guard mute.start() else { mute.end(); return nil }
        Log.info("🔇 app mute — \(bundlePrefix) silenced (\(objects.count) audio process(es)) for \(what)")
        return mute
    }

    private init(tap: AudioObjectID, device: AudioObjectID, what: String) {
        self.tap = tap
        self.device = device
        self.what = what
    }

    private func start() -> Bool {
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, DispatchQueue(label: "walkie.app-mute")) { [weak self] _, input, _, _, _ in
            guard let self else { return }
            var loud = false
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(buffer.mDataByteSize) / MemoryLayout<Float>.size where abs(samples[i]) > AppMute.audible {
                    loud = true
                    break
                }
                if loud { break }
            }
            guard loud else { return }
            let at = CFAbsoluteTimeGetCurrent() - self.began
            self.lock.lock()
            if self.firstHeard == nil { self.firstHeard = at }
            self.lastHeard = at
            self.lock.unlock()
        }
        guard status == noErr, let proc else { Log.error("🔇 app mute — no IO proc (\(status))"); return false }
        let started = AudioDeviceStart(device, proc)
        if started != noErr { Log.error("🔇 app mute — the tap's device did not start (\(started))") }
        return started == noErr
    }

    /// A sample above this is sound, not dither.
    static let audible: Float = 0.001

    /// The app plays again. Safe to call twice.
    func end() {
        lock.lock()
        let already = ended
        ended = true
        let first = firstHeard, last = lastHeard
        lock.unlock()
        guard !already else { return }
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
        }
        AudioHardwareDestroyAggregateDevice(device)
        AudioHardwareDestroyProcessTap(tap)
        Log.info("🔇 app mute — released after \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - began)) s (\(what)); "
            + AppMute.heard(first: first, last: last))
    }

    /// **Released by what it hears, not by a clock** (the first live run, 2026-11-16:
    /// the connect chime began 1.4 s *after* the app took the microphone, so a fixed
    /// 1.8 s let most of it through; the hang-up's began 0.5 s after the press). The
    /// mute ends once the app has played something and then been quiet for `quiet`;
    /// if it plays nothing within `patience`, or keeps playing past `cap` (somebody is
    /// talking), it ends anyway.
    ///
    /// `patience: .infinity` waits for the sound however late it comes (2026-11-16,
    /// Victor: *"putem evita acest ghicit?"* — the connect chime on a slow network);
    /// `whileTrue`, asked twice a second, then ends the wait when its reason is gone
    /// (the call was hung up before the app ever played anything).
    func endAfterItsSound(patience: TimeInterval, quiet: TimeInterval = 0.4, cap: TimeInterval = 4,
                          whileTrue: (() -> Bool)? = nil) {
        let from = CFAbsoluteTimeGetCurrent() - began
        DispatchQueue.global().async { [self] in
            var ticks = 0
            while true {
                usleep(50_000)
                ticks += 1
                if ticks % 10 == 0, let whileTrue, !whileTrue() { break }
                let now = CFAbsoluteTimeGetCurrent() - began
                lock.lock()
                let first = firstHeard, last = lastHeard, done = ended
                lock.unlock()
                if done { return }
                // Only what it played since this was armed counts: a sound from
                // before (a click at the press) is not the chime.
                let since = (last ?? -1) >= from
                if AppMute.isOver(sinceArmed: now - from, sinceFirst: since ? first.map { now - max($0, from) } : nil,
                                  sinceLast: since ? last.map { now - $0 } : nil,
                                  patience: patience, quiet: quiet, cap: cap) { break }
            }
            end()
        }
    }

    /// Pure, for the tests. `sinceFirst` / `sinceLast`: seconds since the app's sound
    /// began / was last heard, nil while it has played nothing.
    static func isOver(sinceArmed: Double, sinceFirst: Double?, sinceLast: Double?,
                       patience: Double, quiet: Double, cap: Double) -> Bool {
        guard let sinceFirst, let sinceLast else { return sinceArmed >= patience }
        return sinceLast >= quiet || sinceFirst >= cap
    }

    /// What the log says the tap swallowed. Pure, for the tests.
    static func heard(first: Double?, last: Double?) -> String {
        guard let first, let last else { return "the app played nothing meanwhile" }
        return String(format: "swallowed its sound from %.1f s to %.1f s", first, last)
    }

    /// The Core Audio process objects of an app and its helpers (an Electron app plays
    /// from a helper, so the match is on the bundle id's prefix).
    static func processObjects(bundlePrefix: String) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.filter { object in
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard withUnsafeMutablePointer(to: &bundle, {
                AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, $0)
            }) == noErr else { return false }
            return (bundle as String).hasPrefix(bundlePrefix)
        }
    }
}
