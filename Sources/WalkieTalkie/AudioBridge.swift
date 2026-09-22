import AVFoundation
import Foundation

/// **The relay carries his voice to Wispr, instead of standing beside it**
/// (2026-09-14).
///
/// Victor: *"intermediaza tu sunetul din microfonul fizic pana la wisprflow,
/// pentru a avea control complet pe insertii audio / start/ end"*.
///
/// ## Why it exists: mixing is not inserting
///
/// Until now a shot marker was **played into** the Loopback device Wispr
/// listens to, which sums it with his voice — and a recogniser handed two voices
/// at once transcribes the one that makes a sentence. Measured: a marker six
/// seconds into an unbroken twelve-second sentence left **no trace at all**,
/// although it is the louder of the two signals. There is no level that fixes
/// that; the only fix is to stop being a second voice.
///
/// So the relay takes the path:
///
/// ```
///   before   MacBook Pro Mic ──┐
///                              ├─→ 🎓 TO Wispr ──→ Wispr      (summed)
///            relay (a marker) ─┘
///
///   after    MacBook Pro Mic ──→ relay ──→ 🎓 TO Wispr ──→ Wispr
///                                 ▲
///                          markers spliced into the queue
/// ```
///
/// The player node's own queue **is** the delay line: `scheduleBuffer` plays what
/// it is given in the order it is given, so a marker handed to it between two of
/// his buffers is heard between them. Nothing is mixed and nothing is dropped —
/// his sentence simply arrives at Wispr the marker's length later.
///
/// ## The one-time change this needs, and why it is off until then
///
/// **The physical microphone has to stop being a direct source of
/// `🎓 TO Wispr`**, leaving Pass-Thru alone — otherwise his voice reaches Wispr
/// twice, once live and once through here a fraction of a second later, which is
/// worse than anything this fixes. That is a change in Loopback's own window and
/// **only Victor can make it**: Loopback ships no `.sdef` and no
/// `NSAppleScriptEnabled`, so nothing here can read or set it.
///
/// Hence `WT_BRIDGE=1`. Off, the relay behaves exactly as it did.
///
/// ## What it costs, stated plainly
///
/// With the microphone removed as a direct source, **Wispr hears nothing while
/// the relay is not running.** It does not fall back: `rankedAudioDevices` (8
/// entries, `Built-in mic` at rank 1, `Auto-detect` at 2) is walked when a device
/// **disappears**, and a Loopback device whose feeder is dead is still present —
/// merely silent. What Wispr does then is raise `NoAudio`, which it has shown 62
/// times already, so the failure is visible rather than silent. The way back is
/// one click in Wispr's own microphone setting.
final class AudioBridge {

    /// **Off by default**, because on a Mac whose Loopback still has the
    /// microphone as a direct source this doubles his voice. See above.
    ///
    /// Settable at runtime as well as by the variable, because the whole point of
    /// this switch is to be flipped next to Victor while Loopback's window is
    /// open, and an installed app does not inherit a shell's environment.
    /// `POST /test/bridge {"on": true}`.
    static var isEnabled: Bool = ProcessInfo.processInfo.environment["WT_BRIDGE"] == "1"

    /// Where his voice is carried to. The same needle `ShotMarker` uses, and for
    /// the same reason it is a substring.
    private static var deviceNeedle: String {
        ProcessInfo.processInfo.environment["WT_MARKER_DEVICE"] ?? "TO Wispr"
    }

    /// Serial: `AVAudioEngine` setup is not thread-safe, and the buffers arrive
    /// on the recorder's audio thread while `start`/`stop` come from the source's
    /// own queue.
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.audio-bridge")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    /// **What the engine is actually wired with, and it is not what arrives.**
    ///
    /// `AVAudioEngine` connections must be a *standard* format — float32,
    /// deinterleaved. Handing `connect(_:to:format:)` the recorder's own 16 kHz
    /// mono **int16 interleaved** format does not fail, it throws an Objective-C
    /// exception that Swift cannot catch, and the app dies with `abort()` on this
    /// queue. Measured the hard way on 2026-09-14 07:39: `EXC_CRASH (SIGABRT)`,
    /// `Crashed Thread: 12  Dispatch queue: …audio-bridge`, on the first dictation
    /// after the bridge was armed. The relay is a login item that has to be
    /// running before he starts talking; it may not be a process that can be
    /// killed by a buffer format.
    private var playFormat: AVAudioFormat?
    private var toPlay: AVAudioConverter?
    private let lock = NSLock()
    private var queued: TimeInterval = 0
    private(set) var isRunning = false
    /// Whether `schedule` still takes buffers — see `closeInput()`.
    private var accepting = true

    /// **How much of his sentence Wispr has not heard yet.**
    ///
    /// The reason it is published: the relay's own stop chord must not go out
    /// while audio is still in the queue, or Wispr ends the dictation on a
    /// sentence whose last second is still in this app. `WisprFlowSource` waits
    /// this out before stopping. Counted down by the player's own
    /// `.dataPlayedBack` callback rather than by a clock, because the clock this
    /// cares about is the output device's.
    var queuedSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return queued
    }

    /// Bring the output up, aimed at the Loopback device.
    ///
    /// - Parameter format: the format the buffers will arrive in — the
    ///   recorder's own (`MicRecorder.fileFormat`, 16 kHz mono). The engine
    ///   resamples to the device's 48 kHz on the way out, which is the same
    ///   conversion Wispr would do anyway.
    @discardableResult
    func start(format: AVAudioFormat) -> Bool {
        queue.sync {
            guard !isRunning else { return true }
            guard let device = AudioDevices.output(matching: Self.deviceNeedle) else {
                Log.error("audio bridge: no output device matching '\(Self.deviceNeedle)' — "
                          + "his voice is not being carried anywhere")
                return false
            }
            let engine = AVAudioEngine()
            // Before `start()`, on the output unit: `AVAudioEngine` has no device
            // property of its own, and the unit reads this when it is initialised.
            var id = device.id
            if let unit = engine.outputNode.audioUnit {
                let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                                  kAudioUnitScope_Global, 0, &id,
                                                  UInt32(MemoryLayout<AudioDeviceID>.size))
                guard status == noErr else {
                    Log.error("audio bridge: could not aim at \(device.name) (OSStatus \(status))")
                    return false
                }
            }
            // The standard twin of whatever arrives: same rate, same channels,
            // float32 deinterleaved — the only shape a node connection takes.
            guard format.sampleRate > 0, format.channelCount > 0,
                  let play = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                           channels: format.channelCount) else {
                Log.error("audio bridge: refusing a format the engine cannot be wired with "
                          + "(\(Int(format.sampleRate))Hz × \(format.channelCount)ch)")
                return false
            }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: play)
            self.playFormat = play
            self.toPlay = format.isEqual(play) ? nil : AVAudioConverter(from: format, to: play)
            do { try engine.start() } catch {
                Log.error("audio bridge: the engine would not start — \(error.localizedDescription)")
                return false
            }
            player.play()
            self.engine = engine
            self.player = player
            self.isRunning = true
            self.lock.lock(); self.queued = 0; self.accepting = true; self.lock.unlock()
            Log.info("🔀 audio bridge up — his microphone → \(device.name)")
            return true
        }
    }

    /// **Stop taking buffers, without touching the recorder** (2026-09-22).
    ///
    /// The stop gesture used to cut the feed with `meter.onBuffer = nil`, on the
    /// main thread — and that setter takes `MicRecorder.lock`, the lock
    /// `start(to:)` holds across its synchronous CoreAudio bind. The morning's
    /// freeze was exactly that: a dictation opened three seconds after a cancel,
    /// its `start(to:)` never returned (no `mic: recording through …` line), and
    /// the forward click that should have ended it blocked the main thread on
    /// that lock for ever — chip frozen, no stop chord, Wispr left recording.
    /// This is the same cut drawn one door later: the recorder keeps calling
    /// `onBuffer`, and the bridge drops what arrives. `lock` here is only ever
    /// held for an add, so this cannot wait on anything. `start` reopens it.
    func closeInput() {
        lock.lock(); accepting = false; lock.unlock()
    }

    /// Hand one buffer on, his or a marker's — they go through the same door in
    /// the order the recorder produced them, which is what makes an insertion an
    /// insertion.
    func schedule(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        lock.lock()
        guard accepting else { lock.unlock(); return }
        queued += seconds
        lock.unlock()
        queue.async { [weak self] in
            guard let self, let player = self.player, self.isRunning,
                  let ready = self.toPlayFormat(buffer) else {
                // Never leave the count standing for a buffer nobody will play:
                // `queuedSeconds` gates the stop chord, and a stop that never
                // comes is a dictation that never ends.
                self?.lock.lock(); self?.queued -= seconds; self?.lock.unlock()
                return
            }
            player.scheduleBuffer(ready, at: nil, options: [],
                                  completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.queued = max(0, self.queued - seconds); self.lock.unlock()
            }
        }
    }

    /// Int16 in, float32 out — on the bridge's own queue, off the audio thread
    /// that produced it. Nil when the engine is not wired, which is the same
    /// answer as *do not schedule this*.
    private func toPlayFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let play = playFormat else { return nil }
        guard let converter = toPlay else { return buffer }
        guard let out = AVAudioPCMBuffer(pcmFormat: play,
                                         frameCapacity: buffer.frameCapacity + 1024) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else {
            Log.error("audio bridge: could not convert a buffer — "
                      + (error?.localizedDescription ?? "no frames"))
            return nil
        }
        return out
    }

    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            player?.stop()
            engine?.stop()
            player = nil
            engine = nil
            playFormat = nil
            toPlay = nil
            lock.lock(); queued = 0; lock.unlock()
            Log.info("🔀 audio bridge down")
        }
    }
}
