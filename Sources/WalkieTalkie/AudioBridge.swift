import AVFoundation
import Foundation
import ObjCTry

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
/// Hence `WT_BRIDGE=1` — until From Walkie, below.
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
///
/// ## From Walkie: the bridge is the only way in (2026-09-29)
///
/// Victor: *"I need this so I have a single source to select the input
/// microphone … and not have Wispr Flow pick a different device than I picked in
/// walkie-talkie"*, and *"not miss the first half a second or a full second of
/// speech"*. The Loopback caveat above is gone with the Loopback device: **From
/// Walkie** (`FromWalkieDevice`, `../from-walkie`) carries only what is played
/// into it, exists only while the relay runs, and Wispr ranks it first. So the
/// bridge is **on by default** (`WT_BRIDGE=0` turns it off) and aimed there
/// (`WT_BRIDGE_DEVICE` overrides), and his microphone is whatever
/// `InputDevice.resolve()` says — the meter's device — for Wispr as well.
///
/// **Held until Wispr listens.** From Walkie is BlackHole underneath: what is
/// written before a reader opens is simply gone. So `start(holding: true)` keeps
/// every buffer from the gesture, and `release()` — called the moment Wispr's
/// input is running — hands them over, the silence ahead of his first word cut
/// and the rest paced back to live by `BridgePacer` (pauses shortened, 1.1×
/// through `AVAudioUnitTimePitch`). The stop chord still waits for the queue
/// (`queuedSeconds`), so Wispr ends a little after he did, never before.
final class AudioBridge {

    /// **On by default since From Walkie** (2026-09-29): the device carries only
    /// what this app plays into it, so there is nothing to double. `WT_BRIDGE=0`
    /// for a run; `POST /test/bridge {"on": …}` at runtime.
    static var isEnabled: Bool = ProcessInfo.processInfo.environment["WT_BRIDGE"] != "0"

    /// Where his voice is carried to — a substring, like every needle here.
    private static var deviceNeedle: String {
        ProcessInfo.processInfo.environment["WT_BRIDGE_DEVICE"] ?? "From Walkie"
    }

    /// **From Walkie has no output since 2026-10-02** — Victor saw it offered as a
    /// *speaker* in Zoom: *"să fie doar microfon selectabil, nu și boxă"*. Its
    /// input is fed through the driver's hidden, output-only twin "From Walkie
    /// Mirror" (same BlackHole ring buffer), reachable only by UID. The needle is
    /// the fallback for `WT_BRIDGE_DEVICE` and for any other pass-through device.
    ///
    /// **The Mirror only once From Walkie has lost its output** (2026-10-02 14:45):
    /// the app shipped before the new driver was installed, and on the old one the
    /// Mirror *chops* his voice — From Walkie's own output cycle writes its silent
    /// mix into the shared ring between the Mirror's writes (BlackHole does not mix
    /// the two). A tone fed in came out 240 samples on, 272 zeros, over and over;
    /// Wispr answered `no_audio` to all four sentences. A visible output means the
    /// old driver: play into it, as before.
    private static let mirrorUID = "FromWalkie_2_UID"

    private static func target() -> AudioDevices.Device? {
        if let direct = AudioDevices.output(matching: deviceNeedle) { return direct }
        guard ProcessInfo.processInfo.environment["WT_BRIDGE_DEVICE"] == nil else { return nil }
        return AudioDevices.output(uid: mirrorUID)
    }

    /// `WT_BRIDGE_RATE=1.0` turns the speed-up off; the pauses are still shortened.
    /// `WT_BRIDGE_MAX_RATE` is the ramp's ceiling (`BridgePacer`, 1.0–2.5).
    private static var tuning: BridgePacer.Tuning {
        var t = BridgePacer.Tuning()
        let env = ProcessInfo.processInfo.environment
        if let r = env["WT_BRIDGE_RATE"].flatMap(Float.init), r >= 1, r <= 1.5 {
            t.catchUpRate = r
            t.maxRate = max(t.maxRate, r)
        }
        if let r = env["WT_BRIDGE_MAX_RATE"].flatMap(Float.init), r >= 1, r <= 2.5 {
            t.maxRate = r
        }
        return t
    }

    /// Serial: `AVAudioEngine` setup is not thread-safe, and the buffers arrive
    /// on the recorder's audio thread while `start`/`stop` come from the source's
    /// own queue. Every buffer is judged, held or played here, in arrival order.
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.audio-bridge")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pitch: AVAudioUnitTimePitch?
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
    private(set) var isRunning = false

    // Queue-only state.
    private var voicer = VoicedMeter()
    private var lastVoiced = false
    private var pacer = BridgePacer()
    private var backlog: [(buffer: AVAudioPCMBuffer, seconds: TimeInterval, voiced: Bool, marker: Bool)] = []
    /// **Every chunk of this take, from the gesture** (2026-10-21) — what a
    /// re-hold puts back in the backlog. On `queue`; capped at `archiveCap`.
    private var archive: [(buffer: AVAudioPCMBuffer, seconds: TimeInterval, voiced: Bool, marker: Bool)] = []
    private var archived: TimeInterval = 0
    private static let archiveCap: TimeInterval = 600
    /// Bumped at every re-hold: a `.dataPlayedBack` callback of an older
    /// generation (the player's stop calls them all) moves no count.
    private var generation = 0
    private var reholds = 0
    /// **Buffers that are a spoken marker, not his voice** (2026-09-30) —
    /// registered by `noteMarker` before the recorder hands them on. Under `lock`.
    private var markerIDs = Set<ObjectIdentifier>()
    /// **What the player holds, in order, and which of it is a marker** — one
    /// entry per scheduled chunk, popped at its playback. On `queue`. The head is
    /// the chunk playing now: while it is a marker the player runs at 1.0 (the
    /// marker is heard at the speed it was measured at), and the moment it is
    /// his voice again the pacer takes the lag back — his voice *ahead* of a
    /// queued marker keeps catching up too (2026-09-30, the overnight suite: a
    /// whole-queue rule held 1.0 for 13 s under four markers).
    private var playing: [Bool] = []
    /// When the last marker finished playing with him queued behind it; zero
    /// once the pacer is back at 1.0. On `queue`. For the one log line.
    private var markerCatchUpFrom: CFAbsoluteTime = 0
    /// Buffers go to the backlog until `playBacklog` has run — decided here, on
    /// the queue, not by `holding`: a buffer judged between `release()` and the
    /// replay must not overtake the backlog it follows.
    private var keeping = false
    private var startedAt: CFAbsoluteTime = 0
    private var releasedAt: CFAbsoluteTime = 0
    private var trimmed: TimeInterval = 0
    private var rateNow: Float = 1
    private var caughtUpAt: CFAbsoluteTime = 0
    /// The engine's `AVAudioEngineConfigurationChange` observer, and how many
    /// times this take has already been brought back after one.
    private var configObserver: NSObjectProtocol?
    private var recoveries = 0
    private static let maxRecoveries = 3

    // Under `lock` — read from any thread, and never held across anything.
    private let lock = NSLock()
    /// Handed to `schedule`, not yet judged on `queue`.
    private var pending: TimeInterval = 0
    /// On the player (or on its way there after a `release`), not yet played back.
    private var queued: TimeInterval = 0
    /// In the backlog, waiting for Wispr's input.
    private var held: TimeInterval = 0
    private var holding = false
    /// Whether `schedule` still takes buffers — see `closeInput()`.
    private var accepting = true

    /// **How much of his sentence Wispr has not heard yet.**
    ///
    /// The relay's own stop chord must not go out while audio is still in the
    /// queue, or Wispr ends the dictation on a sentence whose last second is still
    /// in this app. `WisprFlowSource` waits this out before stopping. Counted down
    /// by the player's own `.dataPlayedBack` callback rather than by a clock,
    /// because the clock this cares about is the output device's. The held
    /// backlog is not in it — nobody is listening to it yet; see `isHolding`.
    var queuedSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return pending + queued
    }

    /// Buffers are being kept for a Wispr whose input is not running yet.
    var isHolding: Bool {
        lock.lock(); defer { lock.unlock() }
        return isRunning && holding
    }

    /// For `GET /test/state` and the log.
    var stats: [String: Any] {
        lock.lock()
        let s: [String: Any] = ["running": isRunning, "holding": holding, "held": held,
                                "queued": queued, "pending": pending]
        lock.unlock()
        return s
    }

    /// Bring the output up, aimed at From Walkie.
    ///
    /// - Parameters:
    ///   - format: the format the buffers will arrive in — the recorder's own
    ///     (`MicRecorder.fileFormat`, 16 kHz mono). The engine resamples to the
    ///     device's rate on the way out.
    ///   - holding: keep every buffer until `release()` — Wispr's input is not
    ///     running yet, and From Walkie drops what nobody reads.
    @discardableResult
    func start(format: AVAudioFormat, holding: Bool) -> Bool {
        queue.sync {
            guard !isRunning else { return true }
            guard let device = Self.target() else {
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
            // Faster, not higher: a recogniser tuned on his voice should still
            // hear his voice while the queue is taken back to live.
            let pitch = AVAudioUnitTimePitch()
            guard Self.guarded("wiring the engine", {
                pitch.rate = 1
                engine.attach(player)
                engine.attach(pitch)
                engine.connect(player, to: pitch, format: play)
                engine.connect(pitch, to: engine.mainMixerNode, format: play)
            }) else { return false }
            self.playFormat = play
            self.toPlay = format.isEqual(play) ? nil : AVAudioConverter(from: format, to: play)
            // **Started, and then asked whether it is still running** (2026-09-30):
            // `play()` raises on an engine a device change stopped in between —
            // what killed the relay twice in `evals/wispr-catchup/`. One retry,
            // then `false`, the path *no device* already takes: Wispr hears
            // nothing and the relay's own recording carries the sentence (Q14).
            guard Self.startPlaying(engine, player) else {
                Self.guarded("stopping a bridge that would not start") { engine.stop() }
                self.playFormat = nil
                self.toPlay = nil
                return false
            }
            self.engine = engine
            self.player = player
            self.pitch = pitch
            self.voicer = VoicedMeter()
            self.lastVoiced = false
            self.pacer = BridgePacer(tuning: Self.tuning)
            self.backlog.removeAll()
            self.archive.removeAll()
            self.archived = 0
            self.reholds = 0
            self.playing = []
            self.keeping = holding
            self.startedAt = CFAbsoluteTimeGetCurrent()
            self.releasedAt = 0
            self.trimmed = 0
            self.rateNow = 1
            self.caughtUpAt = 0
            self.recoveries = 0
            self.watchConfiguration(of: engine)
            self.lock.lock()
            self.pending = 0; self.queued = 0; self.held = 0
            self.holding = holding; self.accepting = true
            self.isRunning = true
            self.lock.unlock()
            Log.info("🔀 audio bridge up — his microphone → \(device.name)"
                     + (holding ? ", held until Wispr's input is running" : ""))
            return true
        }
    }

    /// **Wispr is listening: hand over what was held, then go live.** Idempotent.
    /// The count moves from `held` to `queued` here, synchronously, so a stop
    /// chord asked for in the same instant waits for the backlog too.
    func release(_ why: String) {
        lock.lock()
        guard isRunning, holding else { lock.unlock(); return }
        holding = false
        queued += held
        held = 0
        lock.unlock()
        queue.async { [weak self] in self?.playBacklog(why) }
    }

    /// **Wispr's input went off mid-sentence: hold again, and replay the whole
    /// take at its next open** (2026-10-21).
    ///
    /// Victor: *"Wispr Flow engine lost the beginning of my dictation"*. Row
    /// 19484 (15:34:46): the bridge was released 179 ms after the gesture, then
    /// Wispr's input went off and back six times in two seconds (`a blip, not the
    /// end of the sentence`). Wispr kept 6.32 s of an 8.7 s take — the audio
    /// after its **last** reopen — and the transcript began mid-sentence
    /// (*"down called volumetry.md …"*). Wispr restarts its recording when it
    /// reopens its input, and From Walkie drops what is written while nobody
    /// reads. So an off edge throws away what the player still holds and puts the
    /// whole take back in the backlog; the next `release()` cuts the silence ahead
    /// of the first word and paces it back to live like any held start. Only
    /// while the relay still takes buffers (`accepting`) — after its stop, the
    /// input closing is Wispr ending the sentence.
    func rehold(_ why: String) {
        lock.lock()
        guard isRunning, !holding, accepting else { lock.unlock(); return }
        holding = true
        lock.unlock()
        queue.async { [weak self] in self?.holdAgain(why) }
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
        guard accepting, isRunning else { lock.unlock(); return }
        pending += seconds
        let marker = markerIDs.contains(ObjectIdentifier(buffer))
        if marker { markerIDs.remove(ObjectIdentifier(buffer)) }
        lock.unlock()
        guard marker else {
            queue.async { [weak self] in self?.take(buffer, seconds: seconds) }
            return
        }
        // **A marker goes in as buffer-sized chunks**, like his voice (~85 ms).
        // Whole, a 1.6 s clip (4.9 s for the mis-cut `screenshot-3`) left `queued`
        // frozen until its last sample played, and the stop's stall watch read
        // that as a dead player and cut the sentence's tail (overnight suite).
        for chunk in Self.chunks(of: buffer, frames: 1365) {
            let s = Double(chunk.frameLength) / chunk.format.sampleRate
            queue.async { [weak self] in self?.take(chunk, seconds: s, marker: true) }
        }
    }

    /// `buffer` cut into pieces of at most `frames` (int16 only; anything else whole).
    private static func chunks(of buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) -> [AVAudioPCMBuffer] {
        guard let src = buffer.int16ChannelData, buffer.frameLength > frames else { return [buffer] }
        var out: [AVAudioPCMBuffer] = []
        var at: AVAudioFrameCount = 0
        let channels = Int(buffer.format.channelCount)
        while at < buffer.frameLength {
            let n = min(frames, buffer.frameLength - at)
            guard let piece = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: n),
                  let dst = piece.int16ChannelData else { return [buffer] }
            for c in 0..<channels { dst[c].update(from: src[c].advanced(by: Int(at)), count: Int(n)) }
            piece.frameLength = n
            out.append(piece)
            at += n
        }
        return out
    }

    /// **This buffer is a marker** — call before it is handed to the recorder
    /// (`MicRecorder.insert`) or to `schedule`.
    ///
    /// Victor, 2026-09-30: *"Because the clip gets longer you might need to speed
    /// up the resulting wav so you catch up with the current real live voice …
    /// every time you insert a bit of a clip, you speed up a bit."* Nothing new
    /// does the speeding up: a marker's 1.5–2 s lands in `queued` like any
    /// buffer, and `BridgePacer` reads queued audio as lag — faster (1.1× up to
    /// 1.25×), pauses shortened to `keptGap` — until Wispr hears him live again.
    /// What this adds is that the marker itself is exempt: never dropped as a
    /// pause, and played at 1.0 (its recognition was measured at 1.0 —
    /// `evals/wispr-markers/`; at 1.25× it is not).
    func noteMarker(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); markerIDs.insert(ObjectIdentifier(buffer)); lock.unlock()
    }

    // MARK: - On `queue`

    private func take(_ buffer: AVAudioPCMBuffer, seconds: TimeInterval, marker: Bool = false) {
        // **A buffer whose samples are not there any more is dropped, not read**
        // (2026-10-02 08:47:43): `EXC_BAD_ACCESS` at 0x0 in `VoicedMeter.feed`
        // under `judge`, 8 s into a Wispr clean dictation — the buffer's `mData`
        // was NULL with ~521 frames declared, the same buffer the recorder had
        // metered fine moments before. Cause not found yet; the log line below
        // is how the next one is caught. A lost 85 ms is a glitch Wispr hears,
        // a read through it is the relay dead mid-sentence.
        guard Self.readable(buffer) else {
            lock.lock(); pending = max(0, pending - seconds); lock.unlock()
            Log.error(String(format: "🔀 bridge: a %@buffer of %d frames with no samples behind it (%@) — dropped",
                             marker ? "marker " : "", Int(buffer.frameLength), Self.describeData(buffer)))
            return
        }
        let voiced = marker || judge(buffer)
        lock.lock()
        pending = max(0, pending - seconds)
        guard isRunning else { lock.unlock(); return }
        if archived < Self.archiveCap {
            archive.append((buffer, seconds, voiced, marker))
            archived += seconds
        }
        if keeping {
            // Before the release it waits in `held`; after it (the replay not
            // yet run), it is already Wispr's to hear and counts as queued.
            if holding { held += seconds } else { queued += seconds }
            lock.unlock()
            backlog.append((buffer, seconds, voiced, marker))
            return
        }
        queued += seconds
        let lag = queued - seconds
        lock.unlock()
        play(buffer, seconds: seconds, voiced: voiced, lag: lag, marker: marker)
    }

    private func holdAgain(_ why: String) {
        guard isRunning, let player else { return }
        generation += 1
        Self.guarded("stopping the player for a re-hold") {
            player.stop()
            player.play()
        }
        playing = []
        backlog = archive
        keeping = true
        reholds += 1
        lock.lock()
        let stillHolding = holding
        if stillHolding { held = archived; queued = 0 } else { queued = archived; held = 0 }
        lock.unlock()
        rateNow = 0; pace()
        caughtUpAt = 0
        Log.info(String(format: "🔀 bridge held again (%@) — re-hold %d: the whole take (%.2f s) "
                        + "goes back to Wispr at its next open", why, reholds, archived))
        // A release that came in between already ran its own replay.
        if !stillHolding { playBacklog("released during the re-hold") }
    }

    private func playBacklog(_ why: String) {
        guard keeping else { return }
        releasedAt = CFAbsoluteTimeGetCurrent()
        let chunks = backlog
        guard !chunks.isEmpty else { keeping = false; return }
        backlog.removeAll()
        keeping = false
        let first = BridgePacer.trimStart(chunks.map { ($0.seconds, $0.voiced) }, pad: pacer.tuning.leadPad)
        let total = chunks.reduce(0) { $0 + $1.seconds }
        trimmed = chunks[..<first].reduce(0) { $0 + $1.seconds }
        lock.lock(); queued = max(0, queued - trimmed); lock.unlock()
        var lag: TimeInterval = 0
        for chunk in chunks[first...] {
            if play(chunk.buffer, seconds: chunk.seconds, voiced: chunk.voiced, lag: lag, marker: chunk.marker) {
                lag += chunk.seconds
            }
        }
        Log.info(String(format: "🔀 bridge released (%@) %.0f ms after the gesture — %.2f s held, "
                        + "%.2f s of silence cut ahead of his first word, %.2f s behind live",
                        why, (releasedAt - startedAt) * 1000, total, trimmed, lag))
    }

    /// Plays one chunk unless the pacer drops it; false when dropped. The chunk's
    /// seconds are already in `queued` and leave it exactly once, here or at
    /// playback.
    @discardableResult
    private func play(_ buffer: AVAudioPCMBuffer, seconds: TimeInterval, voiced: Bool, lag: TimeInterval,
                      marker: Bool = false) -> Bool {
        guard marker || pacer.admit(seconds: seconds, voiced: voiced, lag: lag),
              let player, let ready = toPlayFormat(buffer) else {
            // Never leave the count standing for a buffer nobody will play:
            // `queuedSeconds` gates the stop chord, and a stop that never
            // comes is a dictation that never ends.
            lock.lock(); queued = max(0, queued - seconds); lock.unlock()
            return false
        }
        let gen = generation
        let scheduled = Self.guarded("scheduling a buffer") {
            player.scheduleBuffer(ready, at: nil, options: [],
                                  completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                self.queue.async {
                    guard gen == self.generation else { return }
                    self.lock.lock(); self.queued = max(0, self.queued - seconds); self.lock.unlock()
                    let was = self.playing.isEmpty ? false : self.playing.removeFirst()
                    if was, self.playing.first != true {
                        self.lock.lock(); let behind = self.queued; self.lock.unlock()
                        Log.info(String(format: "🔀 marker played at 1.0× — %.2f s queued behind it, catching up",
                                        behind))
                        self.markerCatchUpFrom = CFAbsoluteTimeGetCurrent()
                    }
                    self.pace()
                }
            }
        }
        guard scheduled else {
            lock.lock(); queued = max(0, queued - seconds); lock.unlock()
            return false
        }
        playing.append(marker)
        pace()
        return true
    }

    /// The speed for the queue as it stands now.
    private func pace() {
        guard let pitch, isRunning else { return }
        lock.lock(); let lag = queued; lock.unlock()
        let markerNow = playing.first == true
        let rate = markerNow ? 1 : pacer.rate(lag: lag)
        if rate == 1, !markerNow, markerCatchUpFrom > 0, lag <= pacer.tuning.synced {
            Log.info(String(format: "🔀 caught up after the marker in %.1f s", CFAbsoluteTimeGetCurrent() - markerCatchUpFrom))
            markerCatchUpFrom = 0
        }
        guard rate != rateNow else { return }
        rateNow = rate
        Self.guarded("setting the catch-up rate") { pitch.rate = rate }
        if rate == 1, !markerNow, caughtUpAt == 0, releasedAt > 0 {
            caughtUpAt = CFAbsoluteTimeGetCurrent()
            Log.info(String(format: "🔀 bridge caught up — Wispr hears him live %.1f s after the release "
                            + "(%.2f s of pauses shortened)", caughtUpAt - releasedAt, pacer.dropped))
        }
    }

    /// Every channel buffer has a data pointer and room for `frameLength` frames.
    static func readable(_ buffer: AVAudioPCMBuffer) -> Bool {
        let need = Int(buffer.frameLength) * Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        return list.count > 0 && list.allSatisfy { $0.mData != nil && Int($0.mDataByteSize) >= need }
    }

    private static func describeData(_ buffer: AVAudioPCMBuffer) -> String {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        return list.map { "mData \($0.mData == nil ? "nil" : "set"), \($0.mDataByteSize) bytes" }
            .joined(separator: "; ")
    }

    /// Voiced or not, by the meter's own arithmetic over the stream; a buffer
    /// that completes no 64 ms window inherits the last verdict.
    private func judge(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let samples = buffer.int16ChannelData?[0] else { return true }
        let fed = voicer.feed(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)), at: 0)
        if !fed.hops.isEmpty { lastVoiced = fed.spoke }
        return lastVoiced
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
            lock.lock()
            let neverHeard = holding ? held : 0
            isRunning = false
            holding = false
            pending = 0; queued = 0; held = 0
            lock.unlock()
            unwatchConfiguration()
            let (player, engine) = (self.player, self.engine)
            Self.guarded("stopping the bridge") {
                player?.stop()
                engine?.stop()
            }
            self.player = nil
            pitch = nil
            self.engine = nil
            playFormat = nil
            toPlay = nil
            backlog.removeAll()
            archive.removeAll()
            archived = 0
            playing = []
            keeping = false
            if neverHeard > 0 {
                Log.info(String(format: "🔀 audio bridge down — Wispr never listened: %.2f s held, never played", neverHeard))
            } else {
                Log.info(String(format: "🔀 audio bridge down (%.2f s of pauses shortened in all)", pacer.dropped))
            }
        }
    }
    // MARK: - Never killed by an Objective-C exception (2026-09-30)

    /// Runs `body` through `WTTry`; false, and a log line, when it raised.
    @discardableResult
    private static func guarded(_ what: String, _ body: () -> Void) -> Bool {
        guard let error = WTTry(body) else { return true }
        Log.error("audio bridge: \(what) raised \((error as NSError).localizedFailureReason ?? "an exception") — "
                  + "\(error.localizedDescription)")
        return false
    }

    /// `engine.start()` then `player.play()`, with one more try of both when the
    /// engine is not running by the time `play()` is asked for.
    private static func startPlaying(_ engine: AVAudioEngine, _ player: AVAudioPlayerNode) -> Bool {
        for attempt in 1...2 {
            do { try engine.start() } catch {
                Log.error("audio bridge: the engine would not start (try \(attempt)) — \(error.localizedDescription)")
                continue
            }
            if engine.isRunning, guarded("starting the player (try \(attempt))", { player.play() }) {
                return true
            }
        }
        return false
    }

    /// **A device change stops the engine under the bridge.** macOS posts
    /// `AVAudioEngineConfigurationChange` and the engine is left stopped: every
    /// later `play()` raises and every buffer scheduled is silently lost. So it
    /// is brought back — re-aimed, restarted — up to `maxRecoveries` times a
    /// take; past that, or with the device gone, the bridge goes down cleanly and
    /// the take falls back as it does when the bridge never came up.
    private func watchConfiguration(of engine: AVAudioEngine) {
        unwatchConfiguration()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self, weak engine] _ in
            guard let self, let engine else { return }
            self.queue.async { self.recover(engine) }
        }
    }

    private func unwatchConfiguration() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = nil
    }

    private func recover(_ changed: AVAudioEngine) {
        guard isRunning, changed === engine, let engine, let player else { return }
        // Whatever was scheduled went with the old configuration.
        lock.lock(); let lost = queued; queued = 0; lock.unlock()
        recoveries += 1
        guard recoveries <= Self.maxRecoveries,
              let device = Self.target() else {
            die(recoveries > Self.maxRecoveries
                ? "the output changed \(recoveries) times in one take"
                : "no output matching '\(Self.deviceNeedle)' after a device change")
            return
        }
        var id = device.id
        if let unit = engine.outputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        guard Self.startPlaying(engine, player) else {
            die("the engine would not come back after a device change")
            return
        }
        rateNow = 0; pace()
        Log.info(String(format: "🔀 audio bridge back after a device change (%d of %d) — %.2f s in flight lost",
                        recoveries, Self.maxRecoveries, lost))
    }

    /// Down for the rest of the take, from the bridge's own queue: counts zeroed
    /// (the stop chord must not wait for audio nobody will play), nothing raised.
    private func die(_ why: String) {
        lock.lock()
        isRunning = false; holding = false; accepting = false
        pending = 0; queued = 0; held = 0
        lock.unlock()
        unwatchConfiguration()
        let (player, engine) = (self.player, self.engine)
        Self.guarded("stopping a failed bridge") { player?.stop(); engine?.stop() }
        self.player = nil; self.pitch = nil; self.engine = nil
        playFormat = nil; toPlay = nil
        backlog.removeAll(); archive.removeAll(); archived = 0; keeping = false; playing = []
        Log.error("🔀 audio bridge down mid-take — \(why); Wispr hears nothing more, "
                  + "the relay's own recording carries the sentence")
    }
}
