import AVFoundation
import Foundation
import Vision

/// **What his face did while he prompted** (2026-11-12, Victor: *"nu o să mă
/// urmărești tot timpul"* — only during a prompt; *"supărarea e corectă …
/// oboseala, da"*; the joke kept as what the face did, not what it meant).
///
/// The same rule as `VoiceAffect`: **a tag only for what the transcript loses,
/// otherwise nothing**, and the tag names a movement, never a feeling —
///
/// - **🙂 smiled** — the lip corners up and the mouth wide for a good part of
///   the take, against *his own* resting mouth;
/// - **🥱 looked tired** — eyes closed in a large share of the frames, or a
///   yawn (mouth open far past his usual for two frames in a row);
/// - **🚶 away from the screen** — no face in most frames, or a face much
///   smaller than at his desk.
///
/// **Two frames a second from the built-in camera, only between the
/// microphone opening and closing on a sentence for an agent** (never on a
/// plain dictation). Each frame is read by Vision on this Mac and dropped; only
/// the numbers are kept, and only for this take. The camera light is on for
/// exactly that long.
///
/// **Against his own face, not a population's.** Every threshold is a ratio to
/// his running medians in `~/.walkie-talkie/face/baseline.json` (eye opening,
/// mouth, smile, face size), updated after every take; until
/// `Baseline.minTakes` takes have been seen no tag is ever given — precision
/// before recall, as for the voice. The first takes only teach it.
final class FaceRead: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    static let shared = FaceRead()

    // MARK: - The switch

    /// **`WT_FACE`** (environment, then `elevenlabs.env`), then the menu's
    /// `faceRead` default. **On** unless one says off.
    static var enabled: Bool {
        get {
            if let raw = ProcessInfo.processInfo.environment["WT_FACE"] ?? ElevenLabsSource.fileValue("WT_FACE") {
                return !["0", "false", "off", "no"].contains(raw.lowercased())
            }
            return UserDefaults.standard.object(forKey: "faceRead") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "faceRead") }
    }

    static let menuTitle = "🙂 Read my face while prompting"

    // MARK: - One frame, as numbers

    struct Frame: Codable, Equatable {
        /// Seconds since the take opened.
        var t: Double
        var face: Bool
        /// Face box width / frame width.
        var size: Double = 0
        /// Eye opening: height / width of each eye's outline, the two averaged.
        var eye: Double = 0
        /// Inner-lip gap / outer-lip width.
        var mouthOpen: Double = 0
        /// Outer-lip width / face box width.
        var mouthWide: Double = 0
        /// Corners above the lips' middle, in mouth widths (+ = up).
        var cornerLift: Double = 0
        var yaw: Double = 0
    }

    // MARK: - The take's verdict

    struct Reading: Equatable {
        var frames: Int
        var faces: Int
        var smiled = false
        var tired = false
        var away = false
        var why: [String] = []

        /// The face's own footer line, or nothing. In words as well as the
        /// emoji: unlike 🤷‍♂️ / 😡 no agent has been told what these mean.
        var tag: String? {
            var parts: [String] = []
            if smiled { parts.append("🙂 smiled while saying it") }
            if tired { parts.append("🥱 looked tired") }
            if away { parts.append("🚶 away from the screen") }
            return parts.isEmpty ? nil : "[face: " + parts.joined(separator: " · ") + "]"
        }

        /// For the outbox.
        var json: [String: Any] {
            ["frames": frames, "faces": faces, "smiled": smiled, "tired": tired, "away": away, "why": why]
        }
    }

    /// His running medians — the ruler every threshold is a ratio to.
    struct Baseline: Codable, Equatable {
        static let minTakes = 8
        var takes = 0
        var size = 0.0
        var eye = 0.0
        var mouthOpen = 0.0
        var mouthWide = 0.0
        var cornerLift = 0.0

        /// Each take moves the medians a tenth of the way to its own (the first
        /// take sets them outright). Only takes with a face in most frames teach it.
        mutating func learn(_ frames: [Frame]) {
            let f = frames.filter(\.face)
            guard f.count >= 3, Double(f.count) >= 0.6 * Double(frames.count) else { return }
            func median(_ xs: [Double]) -> Double {
                let s = xs.sorted(); return s.isEmpty ? 0 : s[s.count / 2]
            }
            let now = (median(f.map(\.size)), median(f.map(\.eye)), median(f.map(\.mouthOpen)),
                       median(f.map(\.mouthWide)), median(f.map(\.cornerLift)))
            let k = takes == 0 ? 1.0 : 0.1
            size += k * (now.0 - size)
            eye += k * (now.1 - eye)
            mouthOpen += k * (now.2 - mouthOpen)
            mouthWide += k * (now.3 - mouthWide)
            cornerLift += k * (now.4 - cornerLift)
            takes += 1
        }
    }

    /// **The verdict on one take's frames** — pure, `FaceReadTests` is its spec.
    /// Thresholds, each a ratio to `base`:
    /// - smiled: ≥ 35 % of the face frames with the mouth ≥ 1.12 × his usual
    ///   width **and** the corners ≥ 0.06 mouth-widths above his usual lift;
    /// - tired: eyes under 0.55 × his usual opening in ≥ 30 % of the face
    ///   frames, or a yawn — the mouth open ≥ 3 × his usual (and ≥ 0.35 of its
    ///   width) in two frames running;
    /// - away: ≥ 4 frames and a face in under 30 % of them, or a median face
    ///   under 0.55 × his usual size.
    static func judge(_ frames: [Frame], base: Baseline) -> Reading {
        let faces = frames.filter(\.face)
        var r = Reading(frames: frames.count, faces: faces.count)
        guard frames.count >= 4, base.takes >= Baseline.minTakes else { return r }
        if Double(faces.count) < 0.3 * Double(frames.count) {
            r.away = true
            r.why.append("face in \(faces.count) of \(frames.count) frames")
            return r
        }
        let sizes = faces.map(\.size).sorted()
        let size = sizes[sizes.count / 2]
        if base.size > 0, size < 0.55 * base.size {
            r.away = true
            r.why.append(String(format: "face %.2f of the frame (usual %.2f)", size, base.size))
        }
        let smiling = faces.filter { $0.mouthWide >= 1.12 * base.mouthWide && $0.cornerLift >= base.cornerLift + 0.06 }
        if Double(smiling.count) >= 0.35 * Double(faces.count) {
            r.smiled = true
            r.why.append("smiling in \(smiling.count) of \(faces.count) face frames")
        }
        let closed = faces.filter { base.eye > 0 && $0.eye < 0.55 * base.eye }
        if Double(closed.count) >= 0.3 * Double(faces.count) {
            r.tired = true
            r.why.append("eyes closed in \(closed.count) of \(faces.count) face frames")
        }
        let yawnBar = max(3 * base.mouthOpen, 0.35)
        var run = 0, yawned = false
        for f in frames {
            run = f.face && f.mouthOpen >= yawnBar ? run + 1 : 0
            if run >= 2 { yawned = true }
        }
        if yawned {
            r.tired = true
            r.why.append("a yawn")
        }
        return r
    }

    // MARK: - The camera

    private let queue = DispatchQueue(label: "face-read")
    private var session: AVCaptureSession?
    private var began: CFAbsoluteTime = 0
    private var lastFrame: CFAbsoluteTime = 0
    private var frames: [Frame] = []
    private var running = false
    /// The last finished take's reading, for the delivery that follows its close.
    private var finished: (reading: Reading, at: CFAbsoluteTime)?

    static var baselineURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".walkie-talkie/face/baseline.json")
    }

    private var baseline: Baseline = {
        guard let data = try? Data(contentsOf: FaceRead.baselineURL),
              let b = try? JSONDecoder().decode(Baseline.self, from: data) else { return Baseline() }
        return b
    }()

    /// The microphone opened on a sentence for an agent. Off main.
    func begin() {
        guard Self.enabled, ProcessInfo.processInfo.environment["RELAY_SHOOT"] == nil else { return }
        queue.async { [self] in
            guard !running else { return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: break
            case .notDetermined:
                // Asked once; this take goes without — the dialog is up while he talks.
                AVCaptureDevice.requestAccess(for: .video) { ok in Log.info("🙂 camera access \(ok ? "granted" : "refused")") }
                return
            default:
                return
            }
            // **The built-in camera only** — never a Continuity iPhone or a
            // virtual camera (Zoom's, OBS's) that happens to be the default.
            let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                         mediaType: .video, position: .unspecified).devices
            guard let camera = found.first(where: { !$0.isSuspended }) else {
                Log.info("🙂 no built-in camera — the take goes without a face")
                return
            }
            let s = AVCaptureSession()
            s.sessionPreset = .vga640x480
            guard let input = try? AVCaptureDeviceInput(device: camera), s.canAddInput(input) else {
                Log.info("🙂 the camera did not open (in use?) — the take goes without a face")
                return
            }
            s.addInput(input)
            let out = AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames = true
            out.setSampleBufferDelegate(self, queue: queue)
            guard s.canAddOutput(out) else { return }
            s.addOutput(out)
            frames = []
            began = CFAbsoluteTimeGetCurrent()
            lastFrame = 0
            running = true
            session = s
            s.startRunning()
        }
    }

    /// The microphone closed. Stops the camera and keeps the verdict for the
    /// delivery (`take()`); the take also teaches the baseline.
    func end() {
        queue.async { [self] in
            guard running else { return }
            running = false
            session?.stopRunning()
            session = nil
            let reading = Self.judge(frames, base: baseline)
            baseline.learn(frames)
            saveBaseline()
            finished = (reading, CFAbsoluteTimeGetCurrent())
            Log.info("🙂 face: \(reading.faces) of \(reading.frames) frames with a face"
                     + (reading.tag.map { " — \($0)" } ?? " — no tag")
                     + (reading.why.isEmpty ? "" : " (\(reading.why.joined(separator: "; ")))")
                     + (baseline.takes < Baseline.minTakes ? " · learning his face, take \(baseline.takes) of \(Baseline.minTakes)" : ""))
            frames = []
        }
    }

    /// The verdict of the take that closed last, once, if it closed in the
    /// last two minutes (a delivery waits on its transcript, never longer).
    func take() -> Reading? {
        queue.sync {
            defer { finished = nil }
            guard let f = finished, CFAbsoluteTimeGetCurrent() - f.at < 120 else { return nil }
            return f.reading
        }
    }

    /// A take that is dropped (cancelled, a plain sentence) leaves nothing behind.
    func discard() {
        queue.async { [self] in
            if running { running = false; session?.stopRunning(); session = nil; frames = [] }
            finished = nil
        }
    }

    private func saveBaseline() {
        let url = Self.baselineURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(baseline) { try? data.write(to: url, options: .atomic) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard running else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // The first ~0.4 s of a cold camera is dark while exposure settles.
        guard now - began >= 0.4, now - lastFrame >= 0.5 else { return }
        lastFrame = now
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        var frame = Frame(t: now - began, face: false)
        if let face = (request.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            frame = Self.measure(face, t: now - began)
        }
        if frames.count < 1200 { frames.append(frame) }
    }

    /// Landmark points are normalised to the face box, y up.
    static func measure(_ face: VNFaceObservation, t: Double) -> Frame {
        var f = Frame(t: t, face: true, size: Double(face.boundingBox.width))
        f.yaw = face.yaw?.doubleValue ?? 0
        guard let lm = face.landmarks else { return f }
        func box(_ region: VNFaceLandmarkRegion2D?) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let xs = pts.map { Double($0.x) }, ys = pts.map { Double($0.y) }
            return (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        }
        let eyes = [box(lm.leftEye), box(lm.rightEye)].compactMap { $0 }
            .map { ($0.maxY - $0.minY) / max($0.maxX - $0.minX, 1e-4) }
        if !eyes.isEmpty { f.eye = eyes.reduce(0, +) / Double(eyes.count) }
        if let outer = box(lm.outerLips), let pts = lm.outerLips?.normalizedPoints {
            let width = max(outer.maxX - outer.minX, 1e-4)
            f.mouthWide = width
            let left = pts.min(by: { $0.x < $1.x })!, right = pts.max(by: { $0.x < $1.x })!
            let middle = (outer.maxY + outer.minY) / 2
            f.cornerLift = ((Double(left.y) + Double(right.y)) / 2 - middle) / width
            if let inner = box(lm.innerLips) { f.mouthOpen = (inner.maxY - inner.minY) / width }
        }
        return f
    }
}
