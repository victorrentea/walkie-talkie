import Darwin
import Foundation

/// Which recogniser's words reach the agent.
///
/// Wispr Flow remains the default and the recorder in both cases. What the
/// setting changes is **whose reading of the recording is believed**: Wispr's
/// own `formattedText`, or a Whisper running on this Mac over the very same
/// audio.
///
/// ## Why this can exist without a microphone
///
/// `History.audio` is a complete 16 kHz mono WAV — the same bytes Wispr scored —
/// so the local engine transcribes Wispr's recording rather than making one of
/// its own. That is what keeps this a switch rather than a rewrite: no
/// microphone code, no new TCC grant, no second capture that could drift from
/// the first, and a like-for-like comparison in live use.
///
/// **It is therefore not independence from Wispr yet, and must not be described
/// as such.** Wispr still records, still decides when a dictation starts and
/// ends, and still has to be installed and running. Dropping it entirely means
/// owning the microphone and a push-to-talk key, which is a separate piece of
/// work — this is the step that answers whether that work is worth doing, by
/// putting the local model on the real job instead of on a benchmark.
enum TranscriptionEngine: String {
    case wispr
    case whisper

    var label: String {
        switch self {
        case .wispr:   return "Wispr Flow"
        case .whisper: return "Local Whisper"
        }
    }

    /// `UserDefaults`, so the choice survives both a relay restart and a logout.
    ///
    /// The alternative was a file beside the outbox, which is where this app puts
    /// things it wants Victor to find. This is the opposite kind of state: it is
    /// set from a menu and read by the app, never by hand and never by an agent,
    /// and a preference is exactly what `UserDefaults` is. It is keyed under the
    /// bundle id, so a `--home` test instance shares it — deliberately: the
    /// engine is a property of *this Mac's* setup, not of one outbox.
    private static let key = "transcriptionEngine"

    static var current: TranscriptionEngine {
        get { TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .wispr }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Runs the local model, by talking to a Python daemon over pipes.
///
/// **The daemon shape is forced by a measurement**: importing `mlx_whisper`
/// costs 7.4s and the first transcription another 2.8s for the weights, against
/// 1.3s once warm. A subprocess per dictation would put ten seconds between the
/// end of a sentence and the agent seeing it. So the process is started once,
/// warms up on a second of silence, and then answers at roughly a tenth of the
/// audio's duration.
///
/// **It is started only when the engine is actually selected.** The weights are
/// 1.5 GB resident, and the overwhelmingly common case is a relay running all
/// day on Wispr, which must not be paying for a model nobody asked for.
final class LocalWhisper {

    struct Result {
        let text: String
        let language: String?
        /// The **worst** segment's average log-probability, which is the one
        /// number that separates a hallucination from a transcript. Measured
        /// over 442 real dictations: a gate at −0.6 caught 7 of the 11
        /// semantically broken outputs and falsely rejected 0 of 40 good ones.
        /// `no_speech_prob` caught none of them and is kept only for the log.
        let avgLogprob: Double
        let compressionRatio: Double
    }

    /// Below this, the transcript is not delivered as if it were what Victor
    /// said. See `Result.avgLogprob` for where the number comes from.
    static let confidenceFloor = -0.6

    private var proc: Process?
    /// The helper's pid, kept beside `proc` so it can be read **without touching
    /// the queue**. Everything else about the process is queue-confined, and this
    /// one question is asked from the main thread while the menu is opening — a
    /// `queue.sync` there would block behind a transcription that is allowed to
    /// take five minutes.
    private var helperPID: pid_t?
    private let pidLock = NSLock()
    private var toHelper: FileHandle?
    private var fromHelper: FileHandle?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.whisper")
    private(set) var ready = false

    /// Where the helper lives: beside the binary inside the `.app`, and in the
    /// repo when running from `swift build`. Resolved rather than hardcoded so a
    /// developer run and an installed run both work without a switch.
    private static var helperPath: String? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["RELAY_WHISPER_HELPER"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        // The installed `.app` — `build-app.sh` copies it into Contents/Resources.
        if let res = Bundle.main.resourcePath {
            candidates.append(URL(fileURLWithPath: res).appendingPathComponent("whisper_helper.py"))
        }
        // A `swift build` run: .build/<config>/<bin> → <repo>/helpers/…
        //
        // `arguments[0]` is whatever was typed, so it is routinely relative
        // (`.build/debug/WalkieTalkie`) — which is why it is resolved against the
        // working directory before any `..` is taken off it. Not doing that was
        // a real bug: the walk produced a path relative to nothing and the
        // helper "did not exist" in a checkout that plainly had it.
        let exe = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("helpers/whisper_helper.py"))
            candidates.append(dir.appendingPathComponent("whisper_helper.py"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    /// Brings the model up. `onReady` fires with nil on success, or the reason.
    func start(_ onReady: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.proc == nil else { onReady(nil); return }
            guard let helper = Self.helperPath else {
                onReady("whisper_helper.py not found beside the binary"); return
            }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", helper]
            let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
            p.standardInput = inPipe
            p.standardOutput = outPipe
            p.standardError = errPipe
            // stderr is drained rather than inherited: a helper that fills a
            // 64 KB pipe nobody reads blocks forever, and mlx is chatty.
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty, let s = String(data: d, encoding: .utf8) {
                    Log.info("whisper helper: \(s.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            do { try p.run() } catch {
                onReady("could not start python3: \(error)"); return
            }
            self.proc = p
            self.pidLock.lock(); self.helperPID = p.processIdentifier; self.pidLock.unlock()
            self.toHelper = inPipe.fileHandleForWriting
            self.fromHelper = outPipe.fileHandleForReading

            Log.info("whisper helper starting (\(helper)) — loading weights")
            guard let hello = self.readLine(timeout: 180) else {
                onReady("the model did not come up within 180s"); return
            }
            if let ok = hello["ready"] as? Bool, ok {
                self.ready = true
                Log.info("whisper helper ready — \(hello["model"] as? String ?? "?")")
                onReady(nil)
            } else {
                onReady((hello["error"] as? String) ?? "the model failed to load")
                self.stop()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.ready = false
            self.toHelper?.closeFile()
            self.proc?.terminate()
            self.proc = nil
            self.pidLock.lock(); self.helperPID = nil; self.pidLock.unlock()
            self.toHelper = nil
            self.fromHelper = nil
            self.buffer = Data()
            Log.info("whisper helper stopped")
        }
    }

    /// What the model is costing **right now**, in bytes, or nil when it is not up.
    ///
    /// `ri_phys_footprint`, which is the number Activity Monitor calls "Memory" —
    /// and the one that matters here, because MLX puts its weights in unified
    /// memory: `ps`'s RSS tells a different story on the same process, and the
    /// question being answered ("what is this costing me?") is Activity Monitor's,
    /// not the resident-set one.
    ///
    /// Read straight from the kernel rather than by shelling out, since the caller
    /// is the main thread with a menu half-open.
    var footprintBytes: UInt64? {
        pidLock.lock(); let pid = helperPID; pidLock.unlock()
        guard let pid = pid else { return nil }
        var info = rusage_info_current()
        let rc = withUnsafeMutablePointer(to: &info) { p -> Int32 in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard rc == 0, info.ri_phys_footprint > 0 else { return nil }
        return info.ri_phys_footprint
    }

    /// Transcribes a WAV already on disk. Answers on a background queue.
    func transcribe(wav: String, _ done: @escaping (Result?) -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.ready, let stdin = self.toHelper else { done(nil); return }
            guard let req = try? JSONSerialization.data(withJSONObject: ["wav": wav]) else {
                done(nil); return
            }
            var line = req
            line.append(0x0A)
            do { try stdin.write(contentsOf: line) } catch {
                Log.error("whisper helper went away: \(error)")
                self.ready = false
                done(nil); return
            }
            // Generous, because it scales with the dictation: a three-minute one
            // is ~20s of work, and a timeout that fires mid-transcription would
            // desynchronise the stream for every request after it.
            guard let obj = self.readLine(timeout: 300) else {
                Log.error("whisper helper timed out")
                done(nil); return
            }
            guard (obj["ok"] as? Bool) == true, let text = obj["text"] as? String else {
                Log.error("whisper helper: \((obj["error"] as? String) ?? "unknown error")")
                done(nil); return
            }
            done(Result(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                        language: obj["language"] as? String,
                        avgLogprob: (obj["avg_logprob"] as? Double) ?? 0,
                        compressionRatio: (obj["compression_ratio"] as? Double) ?? 0))
        }
    }

    // MARK: - Line protocol

    /// Blocking read of one newline-terminated JSON object. Called only on
    /// `queue`, which serialises requests — so a reply always belongs to the
    /// request just written.
    private func readLine(timeout: TimeInterval) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                if lineData.isEmpty { continue }
                return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            }
            guard Date() < deadline, let handle = fromHelper else { return nil }
            let chunk = handle.availableData   // blocks until there is something
            if chunk.isEmpty { return nil }    // EOF — the helper died
            buffer.append(chunk)
        }
    }
}
