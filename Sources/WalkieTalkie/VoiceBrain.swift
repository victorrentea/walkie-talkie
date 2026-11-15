import Foundation

/// **The Claude behind the voice** (2026-11-15, Victor: *"pot să am un dialog
/// folosind modul de voice-to-voice de la OpenAI, iar munca efectivă să i-o
/// trimit unei instanțe de Claude din spate? Ăsta ar fi cel mai bun combo, că
/// deja are toate memoriile"*). The route `~/workspace/voice-codex-claude/
/// fable_voice.py` proved on 2026-11-05, inside the panel:
///
///     he speaks → realtime voice → its background agent (the Codex thread, a
///     pure relay) → dynamic tool `tell_claude` → this process
///     this process's every text → `thread/realtime/appendSpeech` → the voice reads it
///
/// One warm `claude -p` speaking stream-json both ways, for the length of the
/// panel, **as his own Claude Code**: his settings, memory, skills and MCP
/// servers (no `--setting-sources ""`), in `~/workspace`, every tool, no
/// permission prompt — *"lași cu toate uneltele posibile nerestricționate"*;
/// the guard is that the panel only exists on an unlocked screen
/// (`VoiceDialog.start`). A message written mid-turn lands at its next tool
/// boundary; `interrupt` stops the turn first (a `control_request`).
/// Subscription only: `ANTHROPIC_API_KEY` is taken out of its environment.
final class VoiceBrain {
    /// **Opus at high effort** (2026-11-15, Victor: *"ar trebui să fie acolo un
    /// Opus Hi prepornit la momentul pornirii dialogului, care să rămână activ"*)
    /// — Fable at medium for the first hour.
    static var model: String { setting("WT_VOICE_BRAIN_MODEL") ?? "opus" }
    static var effort: String { setting("WT_VOICE_BRAIN_EFFORT") ?? "high" }
    private static func setting(_ key: String) -> String? {
        let v = ProcessInfo.processInfo.environment[key] ?? ElevenLabsSource.fileValue(key)
        return v?.isEmpty == false ? v : nil
    }

    static let voicePrompt = """
        You are talking to Victor by voice. He speaks to a voice assistant that relays his words to \
        you, and every text you write is read aloud to him at once, word for word; he sees none of \
        it. Answer in the language he spoke. Write for the ear: plain sentences, no markdown, no \
        lists, no code, no URLs, no file paths spelled out unless he asks. Lead with the conclusion \
        and stay short unless asked to go deep. On long work, say one short sentence whenever you \
        have something worth hearing instead of saving it all for the end, and say when you are \
        done. New messages can reach you while you work: take them into account straight away. The \
        assistant answers small talk itself; what was said without you comes in brackets ahead of \
        his words, so you hold the whole conversation. A \
        message may come with pictures of his screen, taken as he spoke. The assistant may phrase \
        requests as "ask Claude" or "tell Claude": that is simply you. He is at his Mac and you \
        have your usual tools; what you change, say in a sentence. \
        Two different things he may ask to be remembered. How the voice assistant itself should talk \
        or behave — how long its answers are, its tone, its language, what it calls him, when it \
        hands things to you — is not a memory of yours: keep those as short plain lines in the file \
        ~/.walkie-talkie/voice-instructions.md (create it if missing; rewrite a line that changes, \
        never add a duplicate; delete one he withdraws). The assistant receives that file within \
        seconds and at every start. His words reach you verbatim, so a "you" about how answers \
        sound in these voice conversations ("you should answer shorter", "speak Romanian to me") \
        means the assistant — the file, never your memory — and you follow the file's lines in what \
        you write here too. Everything else worth keeping goes to your own memory as usual.
        """

    private let process = Process()
    private let stdin = Pipe(), stdout = Pipe()
    private let queue = DispatchQueue(label: "voice-brain")
    private var buffer = Data()
    private var turnsOpen = 0
    private var discarding = false
    private var requests = 0
    private var stopped = false

    /// All on main. `onText`: a text block to read aloud. `onStep`: a tool it
    /// took up (its name), or nil when the turn is over. `onExit`: it died.
    var onText: ((String) -> Void)?
    var onStep: ((String?) -> Void)?
    var onExit: ((String) -> Void)?
    private(set) var servedModel = ""

    var busy: Bool { queue.sync { turnsOpen > 0 } }

    init() throws {
        guard let claude = QuickAsk.claudePath else {
            throw NSError(domain: "VoiceBrain", code: 1, userInfo: [NSLocalizedDescriptionKey: "claude not found"])
        }
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["-p", "--model", Self.model, "--effort", Self.effort,
                             "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                             "--dangerously-skip-permissions", "--append-system-prompt", Self.voicePrompt]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/workspace")
        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("CLAUDE_CODE_") || k == "CLAUDECODE" || k == "ANTHROPIC_API_KEY" { env[k] = nil }
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }
            self?.queue.async { self?.read(d) }
        }
        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.queue.async {
                guard !self.stopped else { return }
                DispatchQueue.main.async { self.onExit?("claude exited (\(p.terminationStatus))") }
            }
        }
        try process.run()
    }

    /// His words (and the pictures taken since the last ones). Mid-turn the
    /// message lands at Claude's next step; `interrupt` stops the turn first.
    func tell(_ text: String, images: [String] = [], interrupt: Bool = false) {
        queue.async { [self] in
            let wasBusy = turnsOpen > 0
            if wasBusy, interrupt {
                discarding = true
                requests += 1
                write(["type": "control_request", "request_id": "i\(requests)", "request": ["subtype": "interrupt"]])
            }
            if !wasBusy || interrupt { turnsOpen += 1 }
            let pictures = images.enumerated().map { (label: "Picture \($0.offset + 1) of his screen", path: $0.element) }
            write(["type": "user", "message": ["role": "user", "content": QuickAsk.content(text, pictures: pictures)]])
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }
    }

    private func write(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? stdin.fileHandleForWriting.write(contentsOf: data)
    }

    private func read(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let e = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            switch e["type"] as? String {
            case "system":
                if e["subtype"] as? String == "init", let m = e["model"] as? String { servedModel = m }
            case "assistant":
                // A subagent's own words are not his to hear.
                if e["parent_tool_use_id"] is String { continue }
                let blocks = (e["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                for b in blocks {
                    if b["type"] as? String == "text", let t = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !t.isEmpty, !discarding {
                        DispatchQueue.main.async { self.onText?(t) }
                    } else if b["type"] as? String == "tool_use", let name = b["name"] as? String {
                        DispatchQueue.main.async { self.onStep?(name) }
                    }
                }
            case "result":
                turnsOpen = max(0, turnsOpen - 1)
                // The interrupted turn's flush is over; the next one is wanted.
                discarding = false
                if turnsOpen == 0 { DispatchQueue.main.async { self.onStep?(nil) } }
            default:
                break
            }
        }
    }
}
