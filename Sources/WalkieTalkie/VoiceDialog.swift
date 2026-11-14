import AppKit
import AVFoundation

/// **A spoken conversation in a floating panel of this app's own** (2026-11-14).
/// Victor, after an evening of driving the ChatGPT app's window from outside
/// (`ChatGPTVoice`): *"chiar nu se poate face o modală flotantă doar cu
/// răspunsul lui scris care apare cât vorbește, și căruia să-i pot vorbi la
/// rândul meu?"* — then *"încearcă să implementezi în panoul nostru"*.
///
/// The ChatGPT app cannot give its words to anyone while it speaks: it writes
/// a reply to `realtime-voice-continuity.json` whole, after the last word
/// (measured: 15 s after the question), and refuses an Accessibility tree.
/// But the same voice is served by **`codex app-server`** on the ChatGPT
/// subscription Codex is signed in with (no API key): `thread/realtime/start`
/// (v2), microphone PCM in through `appendAudio`, and back come
/// `outputAudio/delta` (24 kHz mono PCM16) and `transcript/delta` word by word
/// for both sides. Proven 2026-11-14 with synthetic speech: three two-turn
/// conversations, context kept, first sound ~3 s after the question began.
/// `~/workspace/voice-codex-claude/` is where the protocol was first worked out.
///
/// What this file owns: the child process and its JSON-RPC, the microphone
/// (with macOS's echo cancellation — the voice must not hear itself on the
/// speakers), the playback, and the panel. **The words are shown at the pace
/// of the voice**, not as they arrive: the audio is delivered faster than real
/// time and the text ahead of it.
///
/// The voice model here is realtime v2 as Plus gets it — it answers on its
/// own and does not look things up, where the app's voice can delegate.
final class VoiceDialog {

    static let shared = VoiceDialog()

    /// Which the flick and the DJI button open: this panel (default) or the
    /// ChatGPT app's own window (`defaults write … chatVoiceEngine app`).
    static var usesPanel: Bool { UserDefaults.standard.string(forKey: "chatVoiceEngine") != "app" }

    private static let rate = 24_000.0
    /// **A man's voice** (2026-11-14, Victor: *"trebuie o voce de bărbat"* — the
    /// session's default, `marin`, is a woman's). Nothing published says which of
    /// the ten v2 voices are which, so each was asked the same question and its
    /// pitch measured: echo 109 Hz, ash 119, verse 132, **cedar 136**, alloy 140,
    /// shimmer 154, ballad 156 — marin 188, coral 222, sage 247. `cedar` is one
    /// of the two OpenAI recommends for quality; `defaults write … voiceDialogVoice
    /// echo` for a deeper one.
    static var voice: String { UserDefaults.standard.string(forKey: "voiceDialogVoice") ?? "cedar" }
    private static var codex: String? {
        ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - State (main thread unless said otherwise)

    private(set) var isOn = false
    private var status = ""
    private var userLine = ""
    /// The reply being spoken: every word received, the seconds of sound
    /// received for it, and when its first sound started playing.
    private var reply = ""
    private var replySeconds = 0.0
    private var replyBegan: CFAbsoluteTime?
    private var replyClosed = true
    private var shown = 0
    private var silent = false
    private var pacer: Timer?
    private var turns = 0
    private var lastError = ""

    private let io = DispatchQueue(label: "voice-dialog")
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextId = 0
    private var waiting: [Int: ([String: Any]) -> Void] = [:]
    private var threadId: String?
    private var generation = 0

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var converter: AVAudioConverter?
    /// Set when the player feeds the output node directly (microphone on).
    private var playConverter: AVAudioConverter?
    private var playOutFormat: AVAudioFormat?

    var describe: [String: Any] {
        ["on": isOn, "status": status, "user": userLine, "reply": reply, "shown": shown,
         "replySeconds": (replySeconds * 10).rounded() / 10, "turns": turns, "error": lastError,
         "panel": panel?.isVisible ?? false, "engine": engine?.isRunning ?? false]
    }

    // MARK: - On and off

    func toggle() { DispatchQueue.main.async { self.isOn ? self.stop(why: "the flick") : self.start() } }

    /// `mic: false` opens no microphone and `silent: true` plays at volume 0 —
    /// the desk's way to hold a conversation with `say(_:)` and no sound.
    func start(mic: Bool = true, silent: Bool = false) {
        guard !isOn else { return }
        guard let codex = Self.codex else {
            lastError = "codex is not installed"
            Log.error("🗣️ voice dialog — no codex binary in /opt/homebrew/bin or /usr/local/bin")
            return
        }
        isOn = true
        generation += 1
        let mine = generation
        self.silent = silent
        userLine = ""; reply = ""; replySeconds = 0; replyBegan = nil; replyClosed = true; shown = 0; turns = 0; lastError = ""
        setStatus("Connecting…")
        showPanel()
        WakeWord.shared.pause()
        Log.info("🗣️ voice dialog — starting (codex app-server, realtime v2)\(mic ? "" : ", no microphone")\(silent ? ", silent" : "")")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: codex)
        p.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            self?.io.async { self?.received(chunk, generation: mine) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == mine, self.isOn else { return }
                self.fail("the voice server stopped")
            }
        }
        do { try p.run() } catch {
            fail("codex did not start: \(error.localizedDescription)")
            return
        }
        process = p
        stdin = input.fileHandleForWriting

        rpc("initialize", ["clientInfo": ["name": "walkie_talkie", "title": "Walkie Talkie", "version": "1"],
                           "capabilities": ["experimentalApi": true]]) { [weak self] _ in
            guard let self else { return }
            self.send(["method": "initialized"])
            self.rpc("thread/start", ["cwd": NSHomeDirectory() + "/workspace", "sandbox": "read-only",
                                      "approvalPolicy": "never", "skipGitRepoCheck": true, "ephemeral": true]) { answer in
                guard let thread = (answer["result"] as? [String: Any])?["thread"] as? [String: Any],
                      let id = thread["id"] as? String else {
                    DispatchQueue.main.async { self.fail("no thread: \(Self.short(answer["error"]))") }
                    return
                }
                self.threadId = id
                self.rpc("thread/realtime/start", ["threadId": id, "outputModality": "audio",
                                                   "includeStartupContext": false, "version": "v2",
                                                   "voice": Self.voice]) { started in
                    if let error = started["error"] {
                        DispatchQueue.main.async { self.fail("no voice session: \(Self.short(error))") }
                    }
                }
            }
        }
        // `thread/realtime/started` opens the microphone (`event`).
        wantsMic = mic
    }
    private var wantsMic = true

    func stop(why: String) {
        guard isOn else { return }
        isOn = false
        generation += 1
        Log.info("🗣️ voice dialog — off (\(why)); \(turns) repl\(turns == 1 ? "y" : "ies")")
        pacer?.invalidate(); pacer = nil
        stopAudio()
        if let id = threadId { rpc("thread/realtime/stop", ["threadId": id]) { _ in } }
        let p = process
        process = nil
        io.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            p?.terminate()
            self?.stdin = nil
            self?.waiting.removeAll()
            self?.buffer.removeAll()
        }
        threadId = nil
        WakeWord.shared.resume()
        ChatGPTVoice.chime(on: false)
        setStatus(lastError.isEmpty ? "Ended" : lastError)
        let closing = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + (lastError.isEmpty ? 1.0 : 4.0)) { [weak self] in
            guard let self, !self.isOn, self.panel === closing else { return }
            closing?.orderOut(nil)
            self.panel = nil
        }
    }

    private func fail(_ why: String) {
        lastError = why
        Log.error("🗣️ voice dialog — \(why)")
        stop(why: why)
    }

    private static func short(_ any: Any?) -> String {
        guard let any, let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]) else { return "?" }
        return String(String(data: data, encoding: .utf8)?.prefix(160) ?? "?")
    }

    // MARK: - JSON-RPC over the child's pipes

    private func send(_ message: [String: Any]) {
        io.async { [weak self] in
            guard let self, let stdin = self.stdin,
                  let data = try? JSONSerialization.data(withJSONObject: message) else { return }
            try? stdin.write(contentsOf: data + Data("\n".utf8))
        }
    }

    private func rpc(_ method: String, _ params: [String: Any], then: @escaping ([String: Any]) -> Void) {
        io.async { [weak self] in
            guard let self else { return }
            self.nextId += 1
            let id = self.nextId
            self.waiting[id] = then
            guard let stdin = self.stdin,
                  let data = try? JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]) else { return }
            try? stdin.write(contentsOf: data + Data("\n".utf8))
        }
    }

    /// On `io`.
    private func received(_ chunk: Data, generation mine: Int) {
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let method = message["method"] as? String {
                if let id = message["id"] {   // a request of the server's: nothing here needs approving
                    send(["id": id, "result": ["decision": "approved"]])
                } else {
                    let params = message["params"] as? [String: Any] ?? [:]
                    if method == "thread/realtime/outputAudio/delta" {
                        if let audio = params["audio"] as? [String: Any], let b64 = audio["data"] as? String,
                           let pcm = Data(base64Encoded: b64) {
                            DispatchQueue.main.async { if self.generation == mine { self.play(pcm) } }
                        }
                    } else {
                        DispatchQueue.main.async { if self.generation == mine { self.event(method, params) } }
                    }
                }
            } else if let id = message["id"] as? Int, let then = waiting.removeValue(forKey: id) {
                then(message)
            }
        }
    }

    // MARK: - What the session says

    private func event(_ method: String, _ params: [String: Any]) {
        switch method {
        case "thread/realtime/started":
            Log.info("🗣️ voice dialog — session up (\(params["version"] as? String ?? "?"))")
            ChatGPTVoice.chime(on: true)
            if wantsMic { startMicrophone() } else { startPlaybackOnly() }
            setStatus("Listening")
        case "thread/realtime/itemAdded":
            // He started talking: whatever is still being said is cut, and
            // its words are all shown — a barge-in.
            if ((params["item"] as? [String: Any])?["type"] as? String) == "input_audio_buffer.speech_started" {
                if replyBegan != nil, shown < reply.count { cutPlayback() }
                setStatus("Listening")
            }
        case "thread/realtime/transcript/delta":
            let delta = params["delta"] as? String ?? ""
            if params["role"] as? String == "user" {
                if replyClosed == false || userClosed { userLine = ""; userClosed = false }
                userLine += delta
                render()
            } else {
                if replyClosed { reply = ""; replySeconds = 0; replyBegan = nil; shown = 0; replyClosed = false }
                reply += delta
            }
        case "thread/realtime/transcript/done":
            let text = params["text"] as? String ?? ""
            if params["role"] as? String == "user" {
                userLine = text
                userClosed = true
                render()
            } else {
                if replyClosed { reply = ""; replySeconds = 0; replyBegan = nil; shown = 0 }
                if !text.isEmpty { reply = text }
                replyClosed = true
                turns += 1
            }
        case "thread/realtime/error":
            fail("the voice session failed: \(Self.short(params))")
        case "thread/realtime/closed":
            if isOn { fail("the voice session closed") }
        default:
            break
        }
    }
    private var userClosed = false

    // MARK: - Sound

    private func startPlaybackOnly() {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.playFormat)
        playConverter = nil
        playOutFormat = nil
        do { try engine.start() } catch { fail("no audio output: \(error.localizedDescription)"); return }
        player.play()
        self.engine = engine
        self.player = player
        startPacer()
    }

    private static let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    private static let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true)!

    /// The microphone and the speakers on one engine with voice processing on:
    /// macOS takes what the speakers play out of what the microphone hears,
    /// so the voice does not answer itself. Other apps' sound is ducked as
    /// little as the system allows.
    private func startMicrophone() {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        let input = engine.inputNode
        do { try input.setVoiceProcessingEnabled(true) } catch {
            Log.error("🗣️ voice dialog — no echo cancellation (\(error.localizedDescription)); on speakers it may hear itself")
        }
        if #available(macOS 14.0, *) {
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        // **Straight into the output node, in the output's own format** — with
        // voice processing on, anything through `mainMixerNode` makes
        // `engine.start()` fail with -10875 (four variants tried in a
        // standalone script, 2026-11-14; input-only and player→output start).
        let outFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: outFormat)
        playConverter = AVAudioConverter(from: Self.playFormat, to: outFormat)
        playOutFormat = outFormat
        let tapFormat = input.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: tapFormat.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: mono, to: Self.sendFormat) else {
            fail("no microphone format")
            return
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(tapFormat.sampleRate / 10), format: tapFormat) { [weak self] buffer, _ in
            self?.captured(buffer, mono: mono)
        }
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            fail("the microphone did not open: \(error.localizedDescription)")
            return
        }
        player.play()
        self.engine = engine
        self.player = player
        Log.info(String(format: "🗣️ voice dialog — microphone open (%.0f Hz, %d ch, echo cancellation %@)",
                        tapFormat.sampleRate, tapFormat.channelCount, input.isVoiceProcessingEnabled ? "on" : "off"))
        startPacer()
    }

    /// On the audio thread: the first channel, down to 24 kHz PCM16, sent.
    private func captured(_ buffer: AVAudioPCMBuffer, mono: AVAudioFormat) {
        guard let converter, let source = buffer.floatChannelData, buffer.frameLength > 0,
              let one = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength) else { return }
        one.frameLength = buffer.frameLength
        memcpy(one.floatChannelData![0], source[0], Int(buffer.frameLength) * MemoryLayout<Float>.size)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Self.rate / mono.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.sendFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, state in
            if fed { state.pointee = .noDataNow; return nil }
            fed = true
            state.pointee = .haveData
            return one
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData else { return }
        append(Data(bytes: samples[0], count: Int(out.frameLength) * 2))
    }

    private func append(_ pcm: Data) {
        guard let id = threadId else { return }
        rpc("thread/realtime/appendAudio", ["threadId": id, "audio": [
            "data": pcm.base64EncodedString(), "sampleRate": Int(Self.rate), "numChannels": 1,
            "samplesPerChannel": pcm.count / 2]]) { _ in }
    }

    /// Desk: a 24 kHz mono PCM16 file as if he had said it — paced like a
    /// microphone, with three seconds of silence behind it to end the turn.
    func say(_ path: String) -> Bool {
        guard isOn, let pcm = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return false }
        let all = pcm + Data(count: Int(Self.rate) * 2 * 3)
        let mine = generation
        DispatchQueue.global().async { [weak self] in
            var at = 0
            while at < all.count {
                guard let self, self.generation == mine else { return }
                self.append(all.subdata(in: at..<min(at + 4800, all.count)))
                at += 4800
                usleep(100_000)
            }
        }
        return true
    }

    private func play(_ pcm: Data) {
        guard let player, let buffer = AVAudioPCMBuffer(pcmFormat: Self.playFormat, frameCapacity: AVAudioFrameCount(pcm.count / 2)) else { return }
        buffer.frameLength = AVAudioFrameCount(pcm.count / 2)
        let gain: Float = silent ? 0 : 1.0 / 32768
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let out = buffer.floatChannelData![0]
            for i in 0..<samples.count { out[i] = Float(samples[i]) * gain }
        }
        if replyBegan == nil {
            replyBegan = CFAbsoluteTimeGetCurrent()
            setStatus("Speaking")
        }
        replySeconds += Double(pcm.count / 2) / Self.rate
        guard let playConverter, let playOutFormat else { player.scheduleBuffer(buffer); return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * playOutFormat.sampleRate / Self.rate) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: playOutFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        playConverter.convert(to: converted, error: &error) { _, state in
            if fed { state.pointee = .noDataNow; return nil }
            fed = true
            state.pointee = .haveData
            return buffer
        }
        if error == nil, converted.frameLength > 0 { player.scheduleBuffer(converted) }
    }

    private func cutPlayback() {
        player?.stop()
        player?.play()
        shown = reply.count
        replySeconds = 0
        replyBegan = nil
        replyClosed = true
        render()
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil
        converter = nil
        playConverter = nil
        playOutFormat = nil
    }

    // MARK: - The words, at the pace of the voice

    /// How much of the reply the voice has got through: the share of its
    /// sound already played, applied to its letters. Twenty times a second.
    private func startPacer() {
        pacer?.invalidate()
        pacer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isOn else { return }
            guard let began = self.replyBegan, self.replySeconds > 0 else { return }
            let played = CFAbsoluteTimeGetCurrent() - began
            // The words arrive ahead of their sound: until it has all come,
            // the reply is taken to last at least as long as its letters
            // would at ~17 a second, or the first sentence appears at once.
            let whole = self.replyClosed ? self.replySeconds : max(self.replySeconds, Double(self.reply.count) / 17)
            let share = min(1, played / max(whole, 0.1))
            // A little ahead of the sound reads as in step with it.
            let upTo = min(self.reply.count, Int((Double(self.reply.count) * share).rounded(.up)) + 6)
            if share >= 1, self.replyClosed {
                if self.shown != self.reply.count { self.shown = self.reply.count; self.render() }
                if self.status == "Speaking" { self.setStatus("Listening") }
                return
            }
            if upTo > self.shown {
                // Whole words only.
                let text = self.reply
                var end = text.index(text.startIndex, offsetBy: upTo)
                while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
                self.shown = text.distance(from: text.startIndex, to: end)
                self.render()
            }
        }
    }

    // MARK: - The panel

    private var panel: NSPanel?
    private let statusField = NSTextField(labelWithString: "")
    private let userField = NSTextField(wrappingLabelWithString: "")
    private let replyField = NSTextField(wrappingLabelWithString: "")

    private static let size = NSSize(width: 640, height: 230)

    private func showPanel() {
        if panel == nil {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let frame = NSRect(x: visible.midX - Self.size.width / 2, y: visible.minY + 36, width: Self.size.width, height: Self.size.height)
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.hidesOnDeactivate = false
            let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 18
            glass.layer?.masksToBounds = true
            p.contentView = glass

            statusField.font = .systemFont(ofSize: 11, weight: .semibold)
            statusField.textColor = .secondaryLabelColor
            userField.font = .systemFont(ofSize: 13)
            userField.textColor = .secondaryLabelColor
            userField.maximumNumberOfLines = 2
            userField.lineBreakMode = .byWordWrapping
            replyField.font = .systemFont(ofSize: 20, weight: .medium)
            replyField.textColor = .labelColor
            replyField.maximumNumberOfLines = 5
            replyField.lineBreakMode = .byWordWrapping
            for field in [statusField, userField, replyField] {
                field.translatesAutoresizingMaskIntoConstraints = false
                glass.addSubview(field)
            }
            NSLayoutConstraint.activate([
                statusField.topAnchor.constraint(equalTo: glass.topAnchor, constant: 14),
                statusField.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 22),
                statusField.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -22),
                userField.topAnchor.constraint(equalTo: statusField.bottomAnchor, constant: 8),
                userField.leadingAnchor.constraint(equalTo: statusField.leadingAnchor),
                userField.trailingAnchor.constraint(equalTo: statusField.trailingAnchor),
                replyField.topAnchor.constraint(equalTo: userField.bottomAnchor, constant: 10),
                replyField.leadingAnchor.constraint(equalTo: statusField.leadingAnchor),
                replyField.trailingAnchor.constraint(equalTo: statusField.trailingAnchor),
                replyField.bottomAnchor.constraint(lessThanOrEqualTo: glass.bottomAnchor, constant: -16),
            ])
            panel = p
        }
        render()
        panel?.orderFrontRegardless()
    }

    private func setStatus(_ text: String) {
        status = text
        render()
    }

    private func render() {
        let dot = status == "Speaking" ? "🔊" : status == "Listening" ? "🎙️" : "•"
        statusField.stringValue = "\(dot)  \(status)   ·   again to end"
        userField.stringValue = Self.tail(userLine, 150)
        replyField.stringValue = Self.tail(String(reply.prefix(shown)), 270)
    }

    /// The end of a text that would not fit its lines, from a word's start —
    /// a wrapping label set to truncate its head draws one line only
    /// (seen 2026-11-14), so the head is cut here instead.
    static func tail(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        var rest = text.suffix(limit)
        if let space = rest.firstIndex(where: { $0.isWhitespace }) { rest = rest[rest.index(after: space)...] }
        return "… " + rest
    }
}
