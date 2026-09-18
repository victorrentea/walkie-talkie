import AppKit
import ImageIO
import UniformTypeIdentifiers

/// **A short screen recording, for the things a screenshot cannot say**
/// (2026-09-18).
///
/// Victor's ask: *"sunt animații pe care uneori nu poți să le arăți [într-o
/// poză]"*. A frame shows a dialog; it cannot show the dialog arriving, a layout
/// reflowing, or a hover that only exists while the pointer is over it. Three to
/// ten seconds at five frames a second is enough for all three, and is the whole
/// ambition here — this is not a screen recorder.
///
/// ## What it produces, and for whom
///
/// Two things, because the two readers want different things and an agent
/// **cannot watch a video at all**:
///
/// - **the frames**, full resolution, one JPEG each, numbered — what the agent
///   opens when it needs to read the screen, and what Victor scrubs;
/// - **the contact sheet** (`FilmSheet`), a sample of them laid out as a grid —
///   what the agent looks at to know *what moved and when*.
///
/// No `.mp4` is written. It would be a file the recipient of this envelope has
/// no way to open, and the frames at 5 fps are the film: `ffmpeg -pattern_type
/// glob` turns them into one in a second if anybody ever wants it.
///
/// ## Why not `screencapture`
///
/// Everything else in this app shells out to `/usr/sbin/screencapture`, and it
/// cannot carry this. **Measured 2026-09-18 on this Mac: 200, 265, 267, 308 and
/// 537 ms per frame** — a subprocess, a window-server round trip and a file
/// write each time. The budget at 5 fps is 200 ms, so the median frame is
/// already over it and the tail is three times over: the recording would drop
/// frames unevenly and "5 fps" in the envelope would be a lie the agent reasons
/// from.
///
/// `CGDisplayCreateImage` is 10–30 ms for the same picture, in-process, and the
/// app already depends on it (`CaptureEffects.captureScreenImage`). It is
/// deprecated as of macOS 14 and works on 15.7; it is behind `grab()` so the day
/// it stops working the replacement is one function, not a rewrite.
final class ScreenFilm {

    /// Five a second, Victor's number, and the ceiling is his too: *"nu plănuiesc
    /// să înregistrez mai mult de 3, 5, 10 secunde maximum, vreodată"*. The cap
    /// is a safety net for a stop gesture that never comes, not a limit he is
    /// expected to reach.
    static let fps: Double = 5
    static let maxSeconds: TimeInterval = 30

    /// **JPEG quality 0.8, full resolution.** The frames are the half of this
    /// feature that has to stay readable — a quarter-resolution frame of an IDE
    /// is unreadable to him and to the agent alike, and the sheet is where the
    /// cheap overview already lives.
    private static let quality: CGFloat = 0.8

    struct Result {
        let dir: URL
        let frames: [FilmSheet.Frame]
        let sheet: URL?
        let duration: TimeInterval
        /// Frames the encoder could not keep up with. Reported rather than
        /// hidden: it is the difference between *nothing happened in that second*
        /// and *we did not look*.
        let dropped: Int
    }

    private let displayID: CGDirectDisplayID
    private let dir: URL
    private let startedAt: CFTimeInterval

    /// **Capture and encode are two serial queues, never one.** A 5K JPEG is
    /// 80–150 ms to encode and a frame is due every 200 ms; encoding on the
    /// capture queue would spend most of the budget and drift the timer, so the
    /// labels under the sheet's cells would stop being true.
    private let captureQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.film.capture",
                                             qos: .userInitiated)
    private let encodeQueue = DispatchQueue(label: "ro.victorrentea.wispr-relay.film.encode",
                                            qos: .utility)
    /// **Backpressure, and it drops rather than queues.** If the encoder is two
    /// frames behind, the next capture is skipped and counted. The alternative —
    /// letting frames pile up — is the 2.9 GB in the note on `grab()`, arrived at
    /// slowly instead of all at once.
    private let slots = DispatchSemaphore(value: 2)

    private var timer: DispatchSourceTimer?
    private var frames: [(at: CFTimeInterval, url: URL)] = []
    private let framesLock = NSLock()
    private var dropped = 0
    private var index = 0
    /// The pixel size of frame #0. A display that changes resolution, sleeps or
    /// is unplugged mid-recording produces frames that cannot go in one grid, and
    /// a sheet that silently mixes two geometries is worse than a short film.
    private var geometry: (w: Int, h: Int)?

    /// **How many frames are on disk right now**, for the chip's row.
    ///
    /// Pulled rather than pushed, the way `MicRecorder.voicedSeconds` is: the
    /// overlay asks when it wants to draw and never learns what a recorder is,
    /// and this way a row that is redrawn once a second does not cost a
    /// callback per frame. Counted under the same lock the encoder appends
    /// through, so it is the number actually written, not the number captured —
    /// a frame still in the encoder is not yet a frame he has.
    var frameCount: Int {
        framesLock.lock(); defer { framesLock.unlock() }
        return frames.count
    }

    private init(displayID: CGDirectDisplayID, dir: URL) {
        self.displayID = displayID
        self.dir = dir
        self.startedAt = CACurrentMediaTime()
    }

    // MARK: - Starting and stopping

    /// Begin recording the display the pointer is on.
    ///
    /// The display is resolved **once, here**, and held for the whole recording:
    /// the sheet is one grid and the frames are one film, so a pointer that
    /// wanders to the second monitor must not change what is being filmed
    /// halfway through.
    static func start() -> ScreenFilm? {
        guard let screen = screenUnderPointer(),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            Log.error("🎬 no display under the pointer — not recording")
            return nil
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let dir = Outbox.shotsDir.appendingPathComponent("film-\(stamp)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Log.error("🎬 could not make \(dir.lastPathComponent): \(error)")
            return nil
        }
        let film = ScreenFilm(displayID: CGDirectDisplayID(number.uint32Value), dir: dir)
        film.begin()
        return film
    }

    private func begin() {
        // The first frame synchronously, so `0:00.0` exists even for a recording
        // stopped almost immediately — and so a failed grab is reported at the
        // gesture rather than as an empty folder ten seconds later.
        tick()
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: captureQueue)
        t.schedule(deadline: .now() + 1.0 / Self.fps,
                   repeating: 1.0 / Self.fps, leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
        Log.info("🎬 recording display \(displayID) at \(Int(Self.fps)) fps → \(dir.lastPathComponent)")
    }

    /// Stop, wait for the encoder to drain, and compose the sheet.
    ///
    /// Returns nil when nothing usable was captured — a recording with no frames
    /// must not reach the envelope as an empty attachment the agent then reasons
    /// about.
    func stop() -> Result? {
        timer?.cancel()
        timer = nil
        let duration = CACurrentMediaTime() - startedAt
        // Drain: two permits means at most two encodes in flight, so taking both
        // is *the encoder is finished*.
        slots.wait(); slots.wait()
        slots.signal(); slots.signal()

        framesLock.lock()
        let taken = frames
        let missed = dropped
        framesLock.unlock()

        guard !taken.isEmpty else {
            Log.error("🎬 recording produced no frames — Screen Recording permission?")
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
        let zero = taken[0].at
        let sheetFrames = taken.enumerated().map {
            FilmSheet.Frame(url: $1.url, at: $1.at - zero, index: $0 + 1)
        }
        let sheet = FilmSheet.write(frames: sheetFrames,
                                    to: dir.appendingPathComponent("sheet.png"))
        Log.info(String(format: "🎬 recording stopped — %d frames over %.1fs%@",
                        taken.count, duration, missed > 0 ? ", \(missed) dropped" : ""))
        return Result(dir: dir, frames: sheetFrames, sheet: sheet,
                      duration: duration, dropped: missed)
    }

    /// Throw it away — the gesture was a misfire, or the dictation it belonged to
    /// was cancelled.
    func discard() {
        timer?.cancel()
        timer = nil
        slots.wait(); slots.wait()
        slots.signal(); slots.signal()
        try? FileManager.default.removeItem(at: dir)
        Log.info("🎬 recording discarded")
    }

    // MARK: - The loop

    /// **`autoreleasepool` is not optional here.** On a dispatch queue the pool
    /// drains between blocks, and a `CGImage` of a 5K display is 59 MB: without
    /// it, a run of frames held to the end of the loop is the gigabytes this
    /// design exists to avoid, incremental encoding or not.
    private func tick() {
        autoreleasepool {
            guard CACurrentMediaTime() - startedAt < Self.maxSeconds else {
                Log.info("🎬 \(Int(Self.maxSeconds))s ceiling reached — stopping the recording")
                timer?.cancel()
                timer = nil
                return
            }
            // Never wait on the encoder from the capture queue: a late frame is
            // a gap in the film, a blocked capture queue is a drifting one.
            guard slots.wait(timeout: .now()) == .success else {
                framesLock.lock(); dropped += 1; framesLock.unlock()
                return
            }
            guard let image = grab() else {
                slots.signal()
                framesLock.lock(); dropped += 1; framesLock.unlock()
                return
            }
            if let g = geometry, g.w != image.width || g.h != image.height {
                Log.error("🎬 the display changed size mid-recording (\(g.w)×\(g.h) → \(image.width)×\(image.height)) — stopping here")
                slots.signal()
                timer?.cancel()
                timer = nil
                return
            }
            geometry = (image.width, image.height)

            let at = CACurrentMediaTime()
            index += 1
            let url = dir.appendingPathComponent(String(format: "frame-%04d.jpg", index))
            encodeQueue.async { [weak self] in
                autoreleasepool {
                    Self.encode(image, to: url)
                    if let self {
                        self.framesLock.lock()
                        self.frames.append((at: at, url: url))
                        self.framesLock.unlock()
                        self.slots.signal()
                    }
                }
            }
        }
    }

    /// **The one function that knows how a pixel is obtained.** Everything above
    /// is a timer and a file name; swapping `CGDisplayCreateImage` for
    /// ScreenCaptureKit is this body and nothing else.
    ///
    /// It returns nil without the Screen Recording grant rather than trapping,
    /// and `stop()` turns a recording of nothing into a refusal.
    private func grab() -> CGImage? {
        CGDisplayCreateImage(displayID)
    }

    /// **Normalised to 8-bit sRGB before it is written.**
    ///
    /// A frame comes back tagged with the display's own colour space, and on an
    /// XDR panel in a reference mode it can come back as 16-bit float with
    /// extended-range components. Encoded naively that is a JPEG that looks
    /// washed out — and, worse, looks washed out *only on some of his displays*,
    /// which is the kind of bug that gets blamed on the compression. Redrawing
    /// through an sRGB context converts; `copy(colorSpace:)` would only relabel.
    ///
    /// A frame that is already 8-bit sRGB skips the redraw, which is the common
    /// case and the whole reason this is a test rather than an unconditional
    /// pass.
    private static func encode(_ image: CGImage, to url: URL) {
        let source: CGImage
        if image.bitsPerComponent > 8 || image.colorSpace?.name != CGColorSpace.sRGB {
            source = normalised(image) ?? image
        } else {
            source = image
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, source, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        if !CGImageDestinationFinalize(dest) {
            Log.error("🎬 could not write \(url.lastPathComponent)")
        }
    }

    private static func normalised(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    /// The screen the pointer is on — `NSEvent.mouseLocation` is in AppKit's
    /// bottom-left global space, which is the space `NSScreen.frame` is in, so
    /// this is the one place in this file that needs no flipping.
    private static func screenUnderPointer() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
    }
}
