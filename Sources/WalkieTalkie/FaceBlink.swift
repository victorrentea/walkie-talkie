import CoreImage
import CoreVideo
import Foundation

/// **How closed his eyes are, frame by frame — MediaPipe, not Vision**
/// (2026-11-20, Victor's human-eval: with his eyes fully closed Vision's eye
/// outline still read 0.92 of their usual opening, so 🥱 never fired on them).
///
/// Keeps `helpers/face_blink.py` alive in its own venv and asks it about each
/// frame `FaceRead` keeps (two a second). Setup, once:
///
///     uv venv --python 3.12 ~/.walkie-talkie/face/venv
///     uv pip install --python ~/.walkie-talkie/face/venv/bin/python3 mediapipe
///     curl -o ~/.walkie-talkie/face/face_landmarker.task \
///       https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
///
/// Missing venv, model or script → `read` answers nil and the take is judged
/// without blink (Vision's other numbers are unchanged). The frame goes over a
/// pipe as JPEG and is never written to disk. Every call is on `FaceRead`'s
/// queue, so nothing here is locked.
final class FaceBlink {

    struct Reading: Equatable {
        var face: Bool
        /// eyeBlinkLeft/Right averaged — 0 open … 1 shut.
        var blink: Double
        var smile: Double
        var jaw: Double
    }

    static let shared = FaceBlink()

    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".walkie-talkie/face")
    }
    static var python: String {
        ProcessInfo.processInfo.environment["WT_FACE_PYTHON"] ?? home.appendingPathComponent("venv/bin/python3").path
    }
    static var model: String { home.appendingPathComponent("face_landmarker.task").path }

    private static var script: String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourcePath { candidates.append(res + "/face_blink.py") }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0],
                      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 {
            candidates.append(dir.appendingPathComponent("helpers/face_blink.py").path)
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: Int32 = -1
    private var pending = Data()
    private var ready = false
    private var seq: UInt32 = 0
    private var refused = false
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Started at the take's open so the model is loaded by its second frame.
    func prepare() {
        guard process?.isRunning != true, !refused else { return }
        let fm = FileManager.default
        guard let script = Self.script, fm.isExecutableFile(atPath: Self.python), fm.fileExists(atPath: Self.model) else {
            refused = true
            Log.info("🙂 blink off — no MediaPipe venv/model in \(Self.home.path) (see FaceBlink.swift for the setup)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.python)
        p.arguments = ["-I", script, "--model", Self.model]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch {
            refused = true
            Log.error("🙂 blink helper did not start: \(error)")
            return
        }
        process = p
        input = inPipe.fileHandleForWriting
        output = outPipe.fileHandleForReading.fileDescriptor
        pending = Data()
        ready = false
        Log.info("🙂 blink helper started (pid \(p.processIdentifier))")
    }

    /// One frame's reading, or nil when the helper is not up or late. A reply
    /// that arrives after its deadline carries an older `seq` and is skipped.
    func read(_ pixels: CVPixelBuffer, wait: TimeInterval = 0.35) -> Reading? {
        guard let p = process, p.isRunning, let input else { process = nil; return nil }
        if !ready {
            // The hello comes once the model is loaded (~0.5 s); until then no frame is sent.
            guard let line = nextLine(wait: 0), line.contains("\"ready\"") else { return nil }
            ready = true
        }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(of: image, colorSpace: space,
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
        else { return nil }
        seq &+= 1
        var head = Data()
        withUnsafeBytes(of: seq.bigEndian) { head.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(jpeg.count).bigEndian) { head.append(contentsOf: $0) }
        do { try input.write(contentsOf: head + jpeg) } catch { stop(); return nil }
        let deadline = CFAbsoluteTimeGetCurrent() + wait
        while true {
            let left = deadline - CFAbsoluteTimeGetCurrent()
            guard left > 0, let line = nextLine(wait: left) else { return nil }
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  (obj["seq"] as? NSNumber)?.uint32Value == seq else { continue }
            let face = obj["face"] as? Bool ?? false
            return Reading(face: face, blink: obj["blink"] as? Double ?? 0,
                           smile: obj["smile"] as? Double ?? 0, jaw: obj["jaw"] as? Double ?? 0)
        }
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        input = nil
        ready = false
    }

    /// The next whole line from the helper, waiting at most `wait` seconds.
    private func nextLine(wait: TimeInterval) -> String? {
        let deadline = CFAbsoluteTimeGetCurrent() + wait
        while true {
            if let nl = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...nl)
                return line
            }
            let left = max(0, deadline - CFAbsoluteTimeGetCurrent())
            var fd = pollfd(fd: output, events: Int16(POLLIN), revents: 0)
            guard poll(&fd, 1, Int32(left * 1000)) > 0 else { return nil }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(output, &buf, buf.count)
            guard n > 0 else { stop(); return nil }
            pending.append(contentsOf: buf[0..<n])
        }
    }
}
