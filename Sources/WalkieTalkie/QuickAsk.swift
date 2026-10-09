import Foundation

/// **⚡ A quick question: answered by a fast model, beside the pointer**
/// (2026-10-09). Victor: *"a dumb mode or a quick fast mode to this walkie-talkie
/// that will answer as fast as it can"*, on his subscription, not an API key.
///
/// **One `claude -p` kept started, used for one question, then replaced.** A
/// cold `claude -p` costs ~2 s to start and ~2 s to exit around a 1.5 s answer
/// (measured 2026-10-09, `evals/quick-ask/`); one already running answers its
/// first words in ~0.5 s. Each process takes exactly one question — Victor:
/// *"a conversation history over the day … will make it slower after a
/// while"* — and the next one is started the moment it has answered, so the
/// start-up is paid while he is not waiting.
///
/// **Lean on purpose**: its own short system prompt instead of Claude Code's,
/// no tools, no MCP servers, no settings files (no hooks, no CLAUDE.md), run
/// from `~/.walkie-talkie/quick/` — ~700 input tokens instead of ~104 000, and
/// the first word ~0.1 s sooner. Haiku at low effort unless `WT_QUICK_MODEL` /
/// `WT_QUICK_EFFORT` (env or `elevenlabs.env`) say otherwise.
final class QuickAsk {
    static let shared = QuickAsk()

    static let systemPrompt = """
        You answer Victor's spoken questions, dictated by voice, so the words may \
        contain recognition mistakes: answer what he most likely meant. Be brief: at \
        most 3 short sentences, plain text, no markdown, no lists unless asked. \
        Answer in the language of the question (Romanian or English).
        """
    /// A question with no answer by then is given up.
    static let timeout: TimeInterval = 45

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.quick-ask")
    private var ready: Worker?
    /// The question being answered — 🔼 ← takes it down.
    private var answering: Worker?
    private var failedStarts = 0

    var model: String { Self.setting("WT_QUICK_MODEL") ?? "haiku" }
    var effort: String { Self.setting("WT_QUICK_EFFORT") ?? "low" }

    private static func setting(_ key: String) -> String? {
        let v = ProcessInfo.processInfo.environment[key] ?? ElevenLabsSource.fileValue(key)
        return v?.isEmpty == false ? v : nil
    }

    static var claudePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// True while a question is being answered.
    var isAnswering: Bool { queue.sync { answering != nil } }

    /// Starts the next process if none is waiting. Cheap to call often.
    func warm() {
        queue.async { self.warmLocked() }
    }

    private func warmLocked() {
        if let r = ready, r.alive { return }
        guard failedStarts < 3 else { return }
        do {
            ready = try Worker(model: model, effort: effort)
            ready?.onExit = { [weak self] w in
                self?.queue.async {
                    guard let self, self.ready === w else { return }
                    // An idle process that died on its own: start another, but not in a loop.
                    self.ready = nil
                    self.failedStarts += 1
                    Log.error("⚡ the waiting quick-answer process exited by itself (\(self.failedStarts)/3) — \(w.stderrTail)")
                    if self.failedStarts < 3 {
                        self.queue.asyncAfter(deadline: .now() + 2) { self.warmLocked() }
                    }
                }
            }
        } catch {
            failedStarts += 1
            Log.error("⚡ could not start the quick-answer process: \(error)")
        }
    }

    /// Asks one question. `onText` gets the answer so far, as it streams;
    /// `onDone` the whole answer, or nil and why it failed. Both on main.
    func ask(_ question: String, onText: @escaping (String) -> Void,
             onDone: @escaping (_ answer: String?, _ error: String?, _ firstWord: TimeInterval?) -> Void) {
        queue.async {
            self.failedStarts = 0
            self.warmLocked()
            guard let w = self.ready, w.alive else {
                DispatchQueue.main.async {
                    onDone(nil, Self.claudePath == nil ? "claude is not installed" : "the quick model did not start", nil)
                }
                return
            }
            self.ready = nil
            self.answering = w
            let started = CFAbsoluteTimeGetCurrent()
            var first: TimeInterval?
            var finished = false
            let finish: (String?, String?) -> Void = { answer, error in
                self.queue.async {
                    guard !finished else { return }
                    finished = true
                    if self.answering === w { self.answering = nil }
                    w.stop()
                    self.warmLocked()
                    DispatchQueue.main.async { onDone(answer, error, first) }
                }
            }
            w.onText = { text in
                if first == nil { first = CFAbsoluteTimeGetCurrent() - started }
                DispatchQueue.main.async { onText(text) }
            }
            w.onResult = { text, error in finish(text, error) }
            w.onExit = { w in finish(nil, "the quick model exited — \(w.stderrTail)") }
            w.send(question)
            self.queue.asyncAfter(deadline: .now() + Self.timeout) {
                finish(nil, "no answer in \(Int(Self.timeout)) s")
            }
            // The next one starts now, while this one answers.
            self.warmLocked()
        }
    }

    /// 🔼 ← while an answer is coming: drop it. True when there was one.
    @discardableResult
    func cancel() -> Bool {
        queue.sync {
            guard let w = answering else { return false }
            answering = nil
            w.onResult = nil
            w.onText = nil
            w.onExit = nil
            w.stop()
            return true
        }
    }

    /// One `claude -p` speaking stream-json both ways.
    private final class Worker {
        private let process = Process()
        private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        private var buffer = Data()
        private var text = ""
        private var errText = ""
        private let lock = NSLock()
        var onText: ((String) -> Void)?
        var onResult: ((String?, String?) -> Void)?
        var onExit: ((Worker) -> Void)?

        var alive: Bool { process.isRunning }
        var stderrTail: String {
            lock.lock(); defer { lock.unlock() }
            let t = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "no stderr" : String(t.suffix(200))
        }

        init(model: String, effort: String) throws {
            guard let claude = QuickAsk.claudePath else {
                throw NSError(domain: "QuickAsk", code: 1, userInfo: [NSLocalizedDescriptionKey: "claude not found"])
            }
            let dir = Outbox.home.appendingPathComponent("quick")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            process.executableURL = URL(fileURLWithPath: claude)
            process.arguments = ["-p", "--model", model, "--effort", effort,
                                 "--input-format", "stream-json", "--output-format", "stream-json",
                                 "--verbose", "--include-partial-messages", "--no-session-persistence",
                                 "--tools", "", "--strict-mcp-config", "--setting-sources", "",
                                 "--system-prompt", QuickAsk.systemPrompt]
            process.currentDirectoryURL = dir
            var env = ProcessInfo.processInfo.environment
            // Not a session of the terminal this app was started from.
            for k in env.keys where k.hasPrefix("CLAUDE_CODE_") || k == "CLAUDECODE" { env[k] = nil }
            process.environment = env
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h.availableData) }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
                let d = h.availableData
                guard let self, !d.isEmpty else { return }
                self.lock.lock(); self.errText += String(decoding: d, as: UTF8.self); self.lock.unlock()
            }
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.stdout.fileHandleForReading.readabilityHandler = nil
                self.stderr.fileHandleForReading.readabilityHandler = nil
                self.onExit?(self)
            }
            try process.run()
        }

        func send(_ question: String) {
            let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": question]]
            guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
            data.append(0x0A)
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }

        func stop() {
            onExit = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        private func read(_ data: Data) {
            guard !data.isEmpty else { return }
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                handle(obj)
            }
        }

        private func handle(_ e: [String: Any]) {
            switch e["type"] as? String {
            case "stream_event":
                guard let ev = e["event"] as? [String: Any], ev["type"] as? String == "content_block_delta",
                      let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                      let t = d["text"] as? String else { return }
                text += t
                onText?(text)
            case "result":
                let isError = e["is_error"] as? Bool ?? false
                let result = (e["result"] as? String) ?? text
                if isError { onResult?(nil, result.isEmpty ? "the quick model failed" : result) }
                else { onResult?(result.isEmpty ? text : result, nil) }
            default:
                return
            }
        }
    }
}
