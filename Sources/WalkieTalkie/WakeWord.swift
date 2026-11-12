import Foundation

/// **"Hey Claude" — the wake word** (2026-11-12, Victor: *"să facem Hey Claude
/// și apoi … I have a question … modul de întrebare … Dacă nu auzi, I have a
/// question, … să faci direct treaba într-un terminal nou"*).
///
/// This class only keeps `helpers/wake_word.py` alive and turns its stdout into
/// events; what a wake *means* is `AppDelegate`'s (`onWake`): a new session in
/// `~/workspace`, or a ⚡ quick question when the words open with *I have a
/// question*. The helper is a child of the app, so the microphone grant is the
/// app's; it runs in its own venv (`~/.walkie-talkie/wake/venv`) so its
/// openWakeWord + onnxruntime never move the whisper helper's numpy.
///
/// Set up once:
///
///     uv venv --python 3.12 ~/.walkie-talkie/wake/venv
///     uv pip install --python ~/.walkie-talkie/wake/venv/bin/python3 openwakeword sounddevice soundfile
///     curl -L -o ~/.walkie-talkie/wake/hey_claude.onnx \
///          https://huggingface.co/gdiamos/hey-claude/resolve/main/hey_claude.onnx
///
/// Missing any of those, `start()` logs which and does nothing — the app is
/// unchanged without it.
final class WakeWord {

    static let shared = WakeWord()

    enum Event {
        case ready(device: String)
        case wake(score: Double)
        case speech
        case silence
        case timeout
        case error(String)
    }

    /// On main.
    var onEvent: ((Event) -> Void)?

    // MARK: - The switch

    /// **`WT_WAKE_WORD`** (environment, then `elevenlabs.env`), then the menu's
    /// `wakeWord` default. **On** unless one says off.
    static var enabled: Bool {
        get {
            if let raw = ProcessInfo.processInfo.environment["WT_WAKE_WORD"] ?? ElevenLabsSource.fileValue("WT_WAKE_WORD") {
                return !["0", "false", "off", "no"].contains(raw.lowercased())
            }
            return UserDefaults.standard.object(forKey: "wakeWord") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "wakeWord") }
    }

    static let menuTitle = "👂 \"Hey Claude\" starts a session"

    /// `WT_WAKE_THRESHOLD`, 0…1. 0.5 is the model card's; fitted to his voice
    /// in `evals/wake-word/`.
    static var threshold: Double {
        let raw = ProcessInfo.processInfo.environment["WT_WAKE_THRESHOLD"] ?? ElevenLabsSource.fileValue("WT_WAKE_THRESHOLD")
        return raw.flatMap(Double.init).map { min(max($0, 0.05), 0.99) } ?? 0.5
    }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".walkie-talkie/wake") }
    static var python: String { ProcessInfo.processInfo.environment["WT_WAKE_PYTHON"] ?? home.appendingPathComponent("venv/bin/python3").path }
    static var model: String { ProcessInfo.processInfo.environment["WT_WAKE_MODEL"] ?? home.appendingPathComponent("hey_claude.onnx").path }

    // MARK: - The helper

    private let queue = DispatchQueue(label: "wake-word")
    private var process: Process?
    private var stdin: FileHandle?
    private var device = ""
    private var wanted = false
    private var restarts = 0
    private var deviceWatch: DispatchSourceTimer?

    var isRunning: Bool { queue.sync { process?.isRunning == true } }

    /// Idempotent; off main (it resolves the microphone, a `coreaudiod` round trip).
    func start() {
        queue.async { [self] in
            wanted = true
            launch()
            watchDevice()
        }
    }

    func stop() {
        queue.async { [self] in
            wanted = false
            deviceWatch?.cancel()
            deviceWatch = nil
            terminate()
        }
    }

    /// The app is dictating: no wake fires, the end-of-speech watch keeps going.
    func pause() { send("pause") }
    func resume() { send("resume") }

    private func send(_ word: String) {
        queue.async { [self] in
            try? stdin?.write(contentsOf: Data((word + "\n").utf8))
        }
    }

    private static var script: String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath { candidates.append(res + "/wake_word.py") }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("helpers/wake_word.py").path)
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The input the relay would record through, by name — the helper opens it
    /// by a substring of that name.
    private static func resolvedDevice() -> String {
        InputDevice.resolve().device?.name ?? ""
    }

    private func launch() {
        guard wanted, process?.isRunning != true else { return }
        let fm = FileManager.default
        guard let script = Self.script else { Log.error("👂 wake word: wake_word.py not found beside the binary"); return }
        guard fm.isExecutableFile(atPath: Self.python) else {
            Log.info("👂 wake word off — no venv at \(Self.python) (see WakeWord.swift for the setup)")
            return
        }
        guard fm.fileExists(atPath: Self.model) else {
            Log.info("👂 wake word off — no model at \(Self.model)")
            return
        }
        device = Self.resolvedDevice()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.python)
        p.arguments = ["-I", script, "--model", Self.model, "--threshold", String(Self.threshold), "--device", device]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        var buffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                self?.handle(line)
            }
        }
        // onnxruntime and openWakeWord warn on stderr; only the last lines matter
        // if it dies.
        var tail = ""
        errors.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { h.readabilityHandler = nil; return }
            tail = String((tail + (String(data: chunk, encoding: .utf8) ?? "")).suffix(600))
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                guard self.process === proc else { return }
                self.process = nil
                self.stdin = nil
                guard self.wanted else { return }
                self.restarts += 1
                let wait = min(60.0, 2.0 * Double(self.restarts))
                Log.error("👂 wake word helper exited (\(proc.terminationStatus)) — again in \(Int(wait)) s; stderr: \(tail.suffix(200))")
                self.queue.asyncAfter(deadline: .now() + wait) { self.launch() }
            }
        }
        do {
            try p.run()
        } catch {
            Log.error("👂 wake word helper did not start: \(error)")
            return
        }
        process = p
        stdin = input.fileHandleForWriting
        Log.info("👂 wake word helper up (pid \(p.processIdentifier)) on \(device.isEmpty ? "the default input" : device), threshold \(Self.threshold)")
    }

    private func terminate() {
        guard let p = process else { return }
        process = nil
        try? stdin?.write(contentsOf: Data("quit\n".utf8))
        stdin = nil
        let pid = p.processIdentifier
        queue.asyncAfter(deadline: .now() + 1) { if p.isRunning { kill(pid, SIGTERM) } }
    }

    /// The microphone can change under it (a receiver plugged in, a pick in
    /// either app's menu); every 10 s the resolver is asked again and a
    /// different answer restarts the helper on it.
    private func watchDevice() {
        guard deviceWatch == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self, self.wanted, self.process != nil else { return }
            let now = Self.resolvedDevice()
            if now != self.device {
                Log.info("👂 wake word: microphone \(self.device) → \(now) — restarting the helper")
                self.terminate()
                self.queue.asyncAfter(deadline: .now() + 1.2) { self.launch() }
            }
        }
        t.resume()
        deviceWatch = t
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let name = obj["event"] as? String else { return }
        let event: Event
        switch name {
        case "ready":
            queue.async { self.restarts = 0 }
            event = .ready(device: obj["device"] as? String ?? "")
        case "wake": event = .wake(score: obj["score"] as? Double ?? 0)
        case "speech": event = .speech
        case "silence": event = .silence
        case "timeout": event = .timeout
        default: event = .error(obj["error"] as? String ?? name)
        }
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    // MARK: - What the words mean

    /// **"I have a question" opens a ⚡ question; anything else is a task for a
    /// new session.** The opening as he says it in either language, before any
    /// other word, punctuation and case aside. Returns the words after it, or
    /// nil when the sentence does not open with it.
    static func question(in text: String) -> String? {
        let openings = ["i have a question", "i've got a question", "i got a question",
                        "am o întrebare", "am o intrebare"]
        let trimmed = withoutWakeWord(text)
        let folded = trimmed.folding(options: [.caseInsensitive], locale: nil)
        for opening in openings where folded.hasPrefix(opening) {
            var rest = String(trimmed.dropFirst(opening.count))
            while let c = rest.first, c == "," || c == "." || c == ":" || c == "!" || c == "?" || c == "-" || c == "—" || c.isWhitespace {
                rest.removeFirst()
            }
            return rest
        }
        return nil
    }

    /// The take opens after the wake fired, but the recogniser can still catch
    /// its tail — *"Claude, fix the build"*. A leading *hey claude* / *claude*
    /// (and its comma) is taken off; nothing later in the sentence is touched.
    static func withoutWakeWord(_ text: String) -> String {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for lead in ["hey claude", "hei claude", "hey, claude", "claude"] {
            if rest.folding(options: [.caseInsensitive], locale: nil).hasPrefix(lead) {
                let after = rest.dropFirst(lead.count)
                // A whole word only: "Claudette" stays.
                if let c = after.first, c.isLetter { continue }
                rest = String(after)
                while let c = rest.first, c == "," || c == "." || c == "!" || c.isWhitespace { rest.removeFirst() }
                break
            }
        }
        return rest
    }
}
