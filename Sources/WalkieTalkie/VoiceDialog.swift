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
final class VoiceDialog: NSObject {

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
    /// **⏸ on the panel** (2026-11-15, Victor: *"un buton de pauză/play pe
    /// dialog dacă vreau să vorbesc cu alții în timpul ăla"*): the session
    /// stays up and keeps its context, but it hears silence instead of the
    /// microphone and what it was saying is cut. Read on the audio thread.
    private(set) var isPaused = false
    /// A reply cut by the pause is still arriving: dropped until its `done`.
    private var dropReply = false
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
         "paused": isPaused, "panel": panel?.isVisible ?? false, "engine": engine?.isRunning ?? false,
         "byWake": wakeOpened, "idle": isOn ? Int(CFAbsoluteTimeGetCurrent() - lastHeard) : 0,
         "brain": brain != nil, "brainStep": brainStep, "brainTold": brainTold, "brainModel": brain?.servedModel ?? "",
         "script": script.count,
         "shots": shots, "looking": looking, "told": told, "lastLook": lastLook, "lookError": lookError]
    }

    /// The panel went up or down — on main (`AppDelegate` tells the tap, whose
    /// 🔽 click is this panel's shutter while it is up).
    var onChange: ((Bool) -> Void)?

    // MARK: - On and off

    func toggle() { DispatchQueue.main.async { self.isOn ? self.stop(why: "the flick") : self.start() } }

    /// `mic: false` opens no microphone and `silent: true` plays at volume 0 —
    /// the desk's way to hold a conversation with `say(_:)` and no sound.
    func start(mic: Bool = true, silent: Bool = false, look: Bool = true, byWake: Bool = false, evenLocked: Bool = false) {
        guard !isOn else { return }
        // **Only on an unlocked screen** (2026-11-15, Victor: *"o să facem modul
        // dialog să poată porni doar când ecranul e deblocat … trebuie cineva să
        // stea lângă laptopul meu neblocat ca să poată să facă o măgărie"*) —
        // what lets the Claude behind it keep every tool. `evenLocked` is the desk's.
        guard evenLocked || !Self.screenLocked else {
            Log.info("🗣️ voice dialog — not started: the screen is locked")
            return
        }
        watchTheLock()
        guard let codex = Self.codex else {
            lastError = "codex is not installed"
            Log.error("🗣️ voice dialog — no codex binary in /opt/homebrew/bin or /usr/local/bin")
            return
        }
        isOn = true
        generation += 1
        let mine = generation
        self.silent = silent
        isPaused = false; dropReply = false
        userLine = ""; reply = ""; replySeconds = 0; replyBegan = nil; replyClosed = true; shown = 0; turns = 0; lastError = ""
        shots = 0; looking = 0; told = 0; lastLook = ""; lookError = ""; sessionUp = false; untold.removeAll()
        script.removeAll(); readingSince = nil; brainStep = ""; brainShots.removeAll(); brainTold = 0
        if Self.usesBrain {
            do {
                let b = try VoiceBrain()
                b.onText = { [weak self, weak b] text in if let self, self.brain === b { self.brainSaid(text) } }
                b.onStep = { [weak self, weak b] step in
                    guard let self, self.brain === b else { return }
                    self.brainStep = step ?? ""
                    self.render()
                }
                b.onExit = { [weak self, weak b] why in
                    guard let self, self.brain === b, self.isOn else { return }
                    self.brain = nil
                    self.brainStep = ""
                    Log.error("🗣️ 🧠 \(why) — the voice goes on alone")
                    self.render()
                }
                brain = b
            } catch {
                Log.error("🗣️ 🧠 Claude did not start (\(error.localizedDescription)) — the voice answers alone")
            }
        }
        setStatus("Connecting…")
        wakeOpened = byWake
        lastHeard = CFAbsoluteTimeGetCurrent()
        idleWatch?.invalidate()
        idleWatch = byWake ? Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.closeIfIdle() } : nil
        // The screen as it is at the gesture, before the panel is on it.
        if look, !Self.screenLocked { self.look(why: "the start") }
        showPanel()
        onChange?(true)
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
            var thread: [String: Any] = ["cwd": NSHomeDirectory() + "/workspace", "sandbox": "read-only",
                                         "approvalPolicy": "never", "skipGitRepoCheck": true, "ephemeral": true]
            if self.brain != nil {
                // The thread's agent is a relay and nothing else (`VoiceBrain`).
                thread["developerInstructions"] = Self.relayInstructions
                thread["dynamicTools"] = [Self.tellClaude]
                thread["config"] = ["model_reasoning_effort": "low"]
                if let model = Self.relayModel { thread["model"] = model }
            }
            self.rpc("thread/start", thread) { answer in
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
        sessionUp = false
        idleWatch?.invalidate(); idleWatch = nil
        brain?.stop(); brain = nil
        script.removeAll(); readingSince = nil
        eyes?.stop(); eyes = nil
        onChange?(false)
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

    // MARK: - A panel the wake word opened closes itself

    /// **Sixty seconds with nobody talking to it and it is gone** (2026-11-15,
    /// Victor: *"după 60s să se închidă, da"*) — only a panel "Hey Gepetto"
    /// opened: a false wake that morning kept one up 26 min behind a locked
    /// screen, answering the room six times. The clock restarts at every word
    /// of his it hears and while it speaks; a pause (⏸) holds it. One opened
    /// by hand (🔽 ←, Link) stays until he ends it.
    static let idleClose: TimeInterval = 60
    private var wakeOpened = false
    private var lastHeard: CFAbsoluteTime = 0
    private var idleWatch: Timer?

    private func closeIfIdle() {
        guard isOn, wakeOpened else { return }
        if isPaused || status == "Speaking" || !replyClosed || brain?.busy == true || !script.isEmpty {
            lastHeard = CFAbsoluteTimeGetCurrent(); return
        }
        if CFAbsoluteTimeGetCurrent() - lastHeard >= Self.idleClose {
            stop(why: "\(Int(Self.idleClose)) s with nobody talking to it, after a wake word")
        }
    }

    // MARK: - Said, and it ends

    /// **"Gepetto, over" · "over and out" · "Pinocchio"** (2026-11-15, Victor:
    /// *"gepetto over, over and out și pinocchio ca fraze de stop din
    /// transcriere"*): what the session writes of his words **ends** with one
    /// of them — said mid-sentence it is talk. No detector: the transcript is
    /// already here. Spellings the recogniser may choose are allowed for
    /// (*Geppetto*, *Jepeto*, *Pinokio*). Pure — `VoiceStopPhraseTests`.
    static func stopPhrase(in text: String) -> String? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let words = String(folded.map { $0.isLetter ? $0 : " " }).split(separator: " ").joined(separator: " ")
        let phrases: [(String, String)] = [
            ("Gepetto, over", #"(^| )(g|j|dj|dz)h?[eai]p+[eai]t+[oa] over$"#),
            ("over and out", #"(^| )over (and|an|end|n) out$"#),
            ("Pinocchio", #"(^| )pin+o(cch|ch|cc|c|kk|k)i?o$"#),
        ]
        for (name, pattern) in phrases where words.range(of: pattern, options: .regularExpression) != nil { return name }
        return nil
    }

    func setPaused(_ on: Bool) {
        guard isOn, on != isPaused else { return }
        isPaused = on
        Log.info("🗣️ voice dialog — \(on ? "paused: it hears silence" : "listening again")")
        if on {
            if !replyClosed { dropReply = true }
            cutPlayback()
        }
        setStatus(on ? "Paused" : "Listening")
    }

    @objc private func pauseClicked() { setPaused(!isPaused) }

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
                if let id = message["id"] {   // a request of the server's
                    if method == "item/tool/call" {
                        let params = message["params"] as? [String: Any] ?? [:]
                        DispatchQueue.main.async {
                            let said = self.generation == mine
                                ? self.toolCall(params["tool"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                                : "the conversation has ended"
                            self.send(["id": id, "result": ["success": true, "contentItems": [["type": "inputText", "text": said]]]])
                        }
                    } else {
                        // Nothing else here needs approving.
                        send(["id": id, "result": ["decision": "approved"]])
                    }
                } else {
                    let params = message["params"] as? [String: Any] ?? [:]
                    if method == "thread/realtime/outputAudio/delta" {
                        if let audio = params["audio"] as? [String: Any], let b64 = audio["data"] as? String,
                           let pcm = Data(base64Encoded: b64) {
                            DispatchQueue.main.async { if self.generation == mine, !self.isPaused, !self.dropReply { self.play(pcm) } }
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
            sessionUp = true
            untold.forEach(tell)
            untold.removeAll()
            readNext()
            if wantsMic { startMicrophone() } else { startPlaybackOnly() }
            setStatus("Listening")
        case "thread/realtime/itemAdded":
            // He started talking: whatever is still being said is cut, and
            // its words are all shown — a barge-in.
            if !isPaused, ((params["item"] as? [String: Any])?["type"] as? String) == "input_audio_buffer.speech_started" {
                if replyBegan != nil, shown < reply.count { cutPlayback() }
                readingSince = nil
                setStatus("Listening")
            }
        case "thread/realtime/transcript/delta":
            let delta = params["delta"] as? String ?? ""
            if params["role"] as? String == "user" {
                lastHeard = CFAbsoluteTimeGetCurrent()
                if replyClosed == false || userClosed { userLine = ""; userClosed = false }
                userLine += delta
                render()
                if let said = Self.stopPhrase(in: userLine) { stop(why: "he said \"\(said)\"") }
            } else {
                if isPaused { dropReply = true }
                if dropReply { break }
                if replyClosed { reply = ""; replySeconds = 0; replyBegan = nil; shown = 0; replyClosed = false }
                reply += delta
            }
        case "thread/realtime/transcript/done":
            let text = params["text"] as? String ?? ""
            if params["role"] as? String == "user" {
                userLine = text
                userClosed = true
                render()
                if let said = Self.stopPhrase(in: text) { stop(why: "he said \"\(said)\"") }
            } else if dropReply {
                dropReply = false
            } else {
                if replyClosed { reply = ""; replySeconds = 0; replyBegan = nil; shown = 0 }
                if !text.isEmpty { reply = text }
                replyClosed = true
                turns += 1
                readingSince = nil
                readNext()
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

    // MARK: - The Claude behind it (`VoiceBrain`)

    /// On unless `defaults write … voiceDialogBrain off` — then the voice
    /// answers alone, as before 2026-11-15.
    static var usesBrain: Bool { UserDefaults.standard.string(forKey: "voiceDialogBrain") != "off" }
    /// The relay agent's model — Codex's own default unless `WT_VOICE_RELAY_MODEL`.
    static var relayModel: String? {
        let v = ProcessInfo.processInfo.environment["WT_VOICE_RELAY_MODEL"] ?? ElevenLabsSource.fileValue("WT_VOICE_RELAY_MODEL")
        return v?.isEmpty == false ? v : nil
    }
    /// `fable_voice.py`'s, word for word but the name: a custom prompt on the
    /// voice itself broke delegation there, the agent as a pure relay held 6/6.
    static let relayInstructions = """
        You are a relay. All real work belongs to Claude, never to you: reading code or files, \
        searching the web, answering questions, research, decisions, changing anything on this Mac. \
        For every delegated request, call tell_claude exactly once with the user's words verbatim, \
        then end your turn with exactly this line: "Claude has only just received this and has no \
        result yet. Say only: I've passed it to Claude." Use no other tool and never answer \
        yourself; Claude replies to the user directly. Set interrupt=true when the user wants Claude \
        to stop or change what it is doing now.
        """
    static let tellClaude: [String: Any] = [
        "type": "function", "name": "tell_claude",
        "description": "Hand the user's words to Claude. Returns at once; Claude answers the user by voice on its own.",
        "inputSchema": ["type": "object",
                        "properties": ["message": ["type": "string", "description": "The user's words, verbatim."],
                                       "interrupt": ["type": "boolean", "description": "Stop what Claude is doing first."]],
                        "required": ["message", "interrupt"], "additionalProperties": false] as [String: Any],
    ]
    static let readAloud = "Claude says the following. Read it to Victor in full, word for word, in its own language, without summarizing: "
    /// A lost "finished speaking" must not freeze the queue.
    static let readTimeout: TimeInterval = 120

    private var brain: VoiceBrain?
    private var brainStep = ""
    private var brainTold = 0
    /// The pictures taken since his last words to Claude (800 px copies).
    private var brainShots: [String] = []
    /// Claude's texts waiting for the voice, read one at a time.
    private var script: [String] = []
    private var readingSince: CFAbsoluteTime?

    private func toolCall(_ tool: String, _ arguments: [String: Any]) -> String {
        guard tool == "tell_claude" else { return "Unknown tool \(tool)" }
        guard let brain else { return "Claude is not running; answer the user yourself and say so." }
        let message = arguments["message"] as? String ?? ""
        let interrupt = arguments["interrupt"] as? Bool ?? false
        let pictures = Array(brainShots.suffix(4))
        brainShots.removeAll()
        brainTold += 1
        Log.info("🗣️ 🧠 tell_claude\(interrupt ? " (interrupt)" : "") with \(pictures.count) picture(s): \(message.prefix(120))")
        if interrupt { script.removeAll() }
        brain.tell(message, images: pictures, interrupt: interrupt)
        brainStep = "thinking"
        render()
        return "sent"
    }

    private func brainSaid(_ text: String) {
        guard isOn else { return }
        Log.info("🗣️ 🧠 Claude: \(text.prefix(160))")
        script.append(text)
        readNext()
    }

    private func readNext() {
        guard isOn, sessionUp, !script.isEmpty, let id = threadId else { return }
        if let since = readingSince, CFAbsoluteTimeGetCurrent() - since < Self.readTimeout { return }
        let text = script.removeFirst()
        readingSince = CFAbsoluteTimeGetCurrent()
        rpc("thread/realtime/appendSpeech", ["threadId": id, "text": Self.readAloud + text]) { answer in
            if let error = answer["error"] { Log.error("🗣️ 🧠 the voice refused Claude's words: \(Self.short(error))") }
        }
    }

    /// The screen locking ends it: the panel exists only in front of him.
    private var watchingLock = false
    private func watchTheLock() {
        guard !watchingLock else { return }
        watchingLock = true
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main) { [weak self] _ in
            self?.stop(why: "the screen locked")
        }
    }

    // MARK: - Its eyes

    /// **The voice gets the screen, in words** (2026-11-15, Victor: *"când pun o
    /// întrebare cu butonul de forward și swipe left, el ia și o poză a
    /// ecranului … mi-ar plăcea așa, la fel. Plus, eventual, poze adiționale cu
    /// butonul de back"*). The realtime session takes sound and text, no
    /// picture (`thread/realtime/appendAudio` / `appendText`; a `developer`
    /// text is refused — *"Developer messages are not supported for realtime
    /// sessions"*). So the screen under the pointer is photographed as a
    /// prompt's 📸0 is, its 800 px copy is described by a `claude -p` of this
    /// app's (`QuickAsk.Worker`, Sonnet at low effort: 5.6 s measured, process
    /// start included), and the words go in as a `user` text the voice does not
    /// answer but has when he asks. Proven with a probe: *"error code
    /// ZEBRA-7391"* in such a text, the spoken question *"what is the error
    /// code on my screen"* → *"The error code is ZEBRA-7391."*
    ///
    /// One at the start (never of a locked screen), and one per 🔽 click while
    /// the panel is up (`HotkeyTap.onVoiceShot`).
    private(set) var shots = 0
    private var looking = 0
    private var told = 0
    private var lastLook = ""
    private var lookError = ""
    private var sessionUp = false
    /// Described before the session was up: said once it is.
    private var untold: [String] = []
    /// The next describer, started ahead (a `claude -p` takes ~2 s to come up).
    private var eyes: QuickAsk.Worker?

    static var eyesModel: String {
        let v = ProcessInfo.processInfo.environment["WT_VOICE_EYES_MODEL"] ?? ElevenLabsSource.fileValue("WT_VOICE_EYES_MODEL")
        return v?.isEmpty == false ? v! : "sonnet"
    }
    static let eyesPrompt = """
        You are the eyes of a voice assistant that cannot see. You get a screenshot of the user's \
        screen. Describe it for the assistant: which app and window is in front, then the content \
        that matters — quote exactly what is short (titles, error messages, code lines, numbers, \
        names, the sentence around the pointer if one is marked), summarise what is long. Keep the \
        language of the text on screen for quotes. Plain text, no markdown, at most 200 words. Do \
        not address the user and do not offer help.
        """
    static let lookTimeout: TimeInterval = 40

    static var screenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func warmEyes() {
        guard isOn, eyes == nil else { return }
        eyes = try? QuickAsk.Worker(model: Self.eyesModel, effort: "low", prompt: Self.eyesPrompt)
    }

    /// On main. The frame is taken now; its description reaches the session
    /// some seconds later.
    func look(at cursor: NSPoint? = nil, why: String) {
        guard isOn else { return }
        shots += 1
        looking += 1
        let n = shots, mine = generation
        let point = cursor ?? NSEvent.mouseLocation
        let worker = eyes
        eyes = nil
        render()
        Log.info("🗣️ 📸\(n) for the voice panel (\(why))")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let done: (String?, String?) -> Void = { text, error in
                DispatchQueue.main.async { self.looked(n, text, error, generation: mine) }
            }
            let dir = Outbox.shotsDir.appendingPathComponent("voice")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // This panel is not what he is asking about.
            DispatchQueue.main.sync { self.panel?.sharingType = .none }
            let frame = ScreenCapture.grab(cursor: point, into: dir)
            DispatchQueue.main.sync { self.panel?.sharingType = .readOnly }
            guard let frame else { return done(nil, "the screen could not be photographed") }
            // Claude gets the pixels, with his next words; the voice only the description.
            let small = ScreenCapture.handover(for: frame.path)
            DispatchQueue.main.async { if self.generation == mine, self.brain != nil { self.brainShots.append(small) } }
            guard let w = worker ?? (try? QuickAsk.Worker(model: Self.eyesModel, effort: "low", prompt: Self.eyesPrompt)) else {
                return done(nil, "claude is not installed")
            }
            var finished = false
            let lock = NSLock()
            let finish: (String?, String?) -> Void = { text, error in
                lock.lock(); let first = !finished; finished = true; lock.unlock()
                guard first else { return }
                w.stop()
                done(text, error)
            }
            w.onResult = { text, error in finish(text, error) }
            w.onExit = { w in finish(nil, "the describing model exited — \(w.stderrTail)") }
            w.send(QuickAsk.content("The screen right now.", pictures: [(label: "📸", path: ScreenCapture.handover(for: frame.path))]))
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.lookTimeout) { finish(nil, "nothing in \(Int(Self.lookTimeout)) s") }
            DispatchQueue.main.async { self.warmEyes() }
        }
    }

    private func looked(_ n: Int, _ text: String?, _ error: String?, generation mine: Int) {
        guard generation == mine, isOn else { return }
        looking = max(0, looking - 1)
        defer { render() }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            lookError = error ?? "no description"
            Log.error("🗣️ 📸\(n) was not described — \(lookError)")
            return
        }
        lastLook = text
        told += 1
        Log.info("🗣️ 📸\(n) described (\(text.count) chars) — told to the voice")
        let note = "[Picture \(n) of my screen, taken a moment ago and described in words by another model because you "
            + "cannot see. I did not say this and it needs no answer. When I talk about what is on my screen, answer "
            + "from it as if you saw the screen yourself, without mentioning a description; a later picture "
            + "replaces an earlier one where they differ.]\n" + text
        if sessionUp { tell(note) } else { untold.append(note) }
    }

    /// A `user` text: in the conversation, not answered until he speaks.
    private func tell(_ text: String) {
        guard let id = threadId else { return }
        rpc("thread/realtime/appendText", ["threadId": id, "role": "user", "text": text]) { answer in
            if let error = answer["error"] { Log.error("🗣️ the picture's words were refused: \(Self.short(error))") }
        }
    }

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
        // Paused: the same length of silence, so the session's clock and its
        // end-of-turn detection keep running.
        append(isPaused ? Data(count: Int(out.frameLength) * 2) : Data(bytes: samples[0], count: Int(out.frameLength) * 2))
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
    private let pauseButton = NSButton(title: "⏸ Pause", target: nil, action: nil)

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
            pauseButton.bezelStyle = .recessed
            pauseButton.controlSize = .small
            pauseButton.target = self
            pauseButton.action = #selector(pauseClicked)
            pauseButton.toolTip = "Pause: it stops listening and stops talking, so you can speak to someone else. The conversation is kept."
            pauseButton.translatesAutoresizingMaskIntoConstraints = false
            glass.addSubview(pauseButton)
            for field in [statusField, userField, replyField] {
                field.translatesAutoresizingMaskIntoConstraints = false
                glass.addSubview(field)
            }
            NSLayoutConstraint.activate([
                statusField.topAnchor.constraint(equalTo: glass.topAnchor, constant: 14),
                statusField.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 22),
                statusField.trailingAnchor.constraint(lessThanOrEqualTo: pauseButton.leadingAnchor, constant: -12),
                pauseButton.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -16),
                pauseButton.centerYAnchor.constraint(equalTo: statusField.centerYAnchor),
                userField.topAnchor.constraint(equalTo: statusField.bottomAnchor, constant: 8),
                userField.leadingAnchor.constraint(equalTo: statusField.leadingAnchor),
                userField.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -22),
                replyField.topAnchor.constraint(equalTo: userField.bottomAnchor, constant: 10),
                replyField.leadingAnchor.constraint(equalTo: statusField.leadingAnchor),
                replyField.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -22),
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
        let dot = status == "Speaking" ? "🔊" : status == "Listening" ? "🎙️" : status == "Paused" ? "⏸" : "•"
        let eyes = shots == 0 ? "" : "   ·   📸 ×\(shots)\(looking > 0 ? " reading the screen…" : lookError.isEmpty || told == shots ? "" : " ⚠️")"
        let mind = brain == nil ? "" : brainStep.isEmpty ? "   ·   🧠 Claude" : "   ·   🧠 Claude: \(brainStep)…"
        statusField.stringValue = "\(dot)  \(status)\(isPaused ? " — not listening" : "")\(mind)\(eyes)   ·   \"Gepetto, over\" ends it"
        pauseButton.title = isPaused ? "▶ Resume" : "⏸ Pause"
        pauseButton.isHidden = !isOn
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
