import AppKit
import AVFoundation
import ScreenCaptureKit

/// **The same recording as a real video, at the display's own refresh rate**
/// (2026-10-27).
///
/// Victor: *"besides the frames, five frames per second, I want also to have an
/// actual video recorded at full frame per seconds, at the refresh rate of the
/// monitor … I just had right now a blinking line that didn't show up in the
/// five frames per second"*. A caret blinking at 2 Hz, a flicker, a one-frame
/// glitch: 5 fps samples them by luck. The frames stay what the agent reads
/// first (the envelope says so); this is the evidence for the moment that fell
/// between two of them.
///
/// **ScreenCaptureKit's own recorder (`SCRecordingOutput`, macOS 15)**, not a
/// hand-fed `AVAssetWriter`: it encodes on the media engine and writes the file
/// itself, so a 120 Hz 5K stream costs this process nothing it would notice.
/// Below macOS 15 there is simply no video — the frames are the film.
///
/// **This app's windows are excluded by the filter, not by `sharingType`.** The
/// `● REC` badges, the border and the chip are `sharingType = .none`, which
/// `CGDisplayCreateImage` honours; ScreenCaptureKit does not reliably, so the
/// filter leaves out the whole app — the frames have never shown it either.
final class FilmVideo: NSObject {

    private var stream: SCStream?
    private var displays: [SCDisplay] = []
    private var excluded: [SCRunningApplication] = []
    private let lock = NSLock()
    private var started = false
    private var stopped = false
    private var finished = DispatchSemaphore(value: 0)
    /// Set when the file is complete — or when it will never be.
    private var outcome: Bool?
    let url: URL
    /// The rate asked of ScreenCaptureKit: the display's maximum refresh rate.
    private(set) var fps: Int = 60

    private init(url: URL) { self.url = url }

    /// Begin recording `displayID` into `url`; returns at once, the stream comes
    /// up ~100–300 ms later. Nil below macOS 15.
    static func start(displayID: CGDirectDisplayID, screen: NSScreen, to url: URL) -> FilmVideo? {
        guard #available(macOS 15.0, *) else {
            Log.info("🎞️ no full-rate video below macOS 15 — the frames are the film")
            return nil
        }
        let video = FilmVideo(url: url)
        video.fps = max(30, screen.maximumFramesPerSecond)
        let pixels = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content else {
                Log.error("🎞️ no shareable content — no video: \(error?.localizedDescription ?? "?")")
                video.finish(false)
                return
            }
            video.begin(content: content, displayID: displayID, pixels: pixels)
        }
        return video
    }

    @available(macOS 15.0, *)
    private func begin(content: SCShareableContent, displayID: CGDirectDisplayID, pixels: CGSize) {
        lock.lock()
        let cancelled = stopped
        lock.unlock()
        guard !cancelled else { finish(false); return }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            Log.error("🎞️ display \(displayID) is not shareable — no video")
            finish(false)
            return
        }
        displays = content.displays
        let me = ProcessInfo.processInfo.processIdentifier
        excluded = content.applications.filter { $0.processID == me }

        let config = SCStreamConfiguration()
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = true
        config.queueDepth = 8

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .hevc

        let stream = SCStream(filter: filter(for: display), configuration: config, delegate: nil)
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        do {
            try stream.addRecordingOutput(output)
        } catch {
            Log.error("🎞️ could not add the recording output — no video: \(error)")
            finish(false)
            return
        }
        self.stream = stream
        stream.startCapture { [weak self] error in
            guard let self else { return }
            if let error {
                Log.error("🎞️ could not start the video: \(error.localizedDescription)")
                self.finish(false)
                return
            }
            self.lock.lock()
            self.started = true
            let late = self.stopped
            self.lock.unlock()
            Log.info("🎞️ video at \(self.fps) fps, \(Int(pixels.width))×\(Int(pixels.height)) → \(self.url.lastPathComponent)")
            // A stop that came while the stream was still coming up.
            if late { self.stopStream() }
        }
    }

    @available(macOS 15.0, *)
    private func filter(for display: SCDisplay) -> SCContentFilter {
        SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
    }

    /// Follow the frames to another display. The output size stays the first
    /// display's; ScreenCaptureKit scales into it.
    func follow(displayID: CGDirectDisplayID) {
        guard #available(macOS 15.0, *), let stream,
              let display = displays.first(where: { $0.displayID == displayID }) else { return }
        stream.updateContentFilter(filter(for: display)) { error in
            if let error { Log.error("🎞️ the video could not follow display \(displayID): \(error.localizedDescription)") }
        }
    }

    /// Stop and wait — at most `timeout` — for the file to be finalised.
    /// Answers whether a playable file is on disk.
    @discardableResult
    func stop(timeout: TimeInterval = 2) -> Bool {
        lock.lock()
        let first = !stopped
        stopped = true
        let running = started
        let done = outcome
        lock.unlock()
        if let done { return done }
        if first && running { stopStream() }
        guard timeout > 0 else { return false }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            Log.error(String(format: "🎞️ the video was not finalised within %.1fs", timeout))
            return FileManager.default.fileExists(atPath: url.path)
        }
        finished.signal()
        lock.lock(); defer { lock.unlock() }
        return outcome ?? false
    }

    private func stopStream() {
        stream?.stopCapture { [weak self] error in
            if let error { Log.error("🎞️ stopping the video: \(error.localizedDescription)") }
            // The recording delegate says when the file is complete; a stream
            // that never recorded a frame never calls it.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { self?.finish(false) }
        }
    }

    private func finish(_ ok: Bool) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = ok
        lock.unlock()
        finished.signal()
    }
}

@available(macOS 15.0, *)
extension FilmVideo: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        Log.info(String(format: "🎞️ video finalised — %.1f MB, %@", Double(bytes) / 1_048_576,
                        CMTimeGetSeconds(recordingOutput.recordedDuration).description + "s"))
        finish(bytes > 0)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Log.error("🎞️ the video failed: \(error.localizedDescription)")
        finish(false)
    }
}
