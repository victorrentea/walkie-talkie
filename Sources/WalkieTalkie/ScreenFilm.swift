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
        /// One 800 px frame from the middle of the recording, for the prompt
        /// panel's strip — the film's picture beside the screenshots' (2026-10-08).
        let poster: URL?
        let duration: TimeInterval
        /// Frames the encoder could not keep up with. Reported rather than
        /// hidden: it is the difference between *nothing happened in that second*
        /// and *we did not look*.
        let dropped: Int
    }

    /// The display being filmed — re-resolved every frame from the pointer
    /// (`followPointer`). Touched only on the capture queue.
    private var displayID: CGDirectDisplayID
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
    /// **The film follows the pointer to another display** (2026-10-16, Victor:
    /// *"if I move my mouse on another screen, the recording of that screen
    /// should happen"*). Until then the display was resolved once, here, so the
    /// sheet would be one geometry; now every frame is of the display under the
    /// pointer at that instant, the red border moves with it, and `FilmSheet`
    /// fits each frame into its cell whatever its size.
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
        FilmBorder.show(on: screen)
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
        FilmBorder.hide()
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
        let poster = FilmSheet.poster(of: sheetFrames[sheetFrames.count / 2].url,
                                      to: dir.appendingPathComponent("poster.jpg"))
        Log.info(String(format: "🎬 recording stopped — %d frames over %.1fs%@",
                        taken.count, duration, missed > 0 ? ", \(missed) dropped" : ""))
        return Result(dir: dir, frames: sheetFrames, sheet: sheet, poster: poster,
                      duration: duration, dropped: missed)
    }

    /// Throw it away — the gesture was a misfire, or the dictation it belonged to
    /// was cancelled.
    func discard() {
        timer?.cancel()
        timer = nil
        // The border goes with the film (2026-10-16, Victor: *"when I canceled the
        // dictation while recording, the rec sign remained on screen"*).
        FilmBorder.hide()
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
                FilmBorder.hide()
                return
            }
            // Never wait on the encoder from the capture queue: a late frame is
            // a gap in the film, a blocked capture queue is a drifting one.
            guard slots.wait(timeout: .now()) == .success else {
                framesLock.lock(); dropped += 1; framesLock.unlock()
                return
            }
            followPointer()
            guard let image = grab() else {
                slots.signal()
                framesLock.lock(); dropped += 1; framesLock.unlock()
                return
            }
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

    /// **Switch to the display the pointer is on now**, and move the border to it.
    /// Pure Core Graphics because this runs on the capture queue, where
    /// `NSEvent`/`NSScreen` are not to be touched: `CGEvent.location` is already
    /// in the displays' own top-left global space.
    private func followPointer() {
        guard let p = CGEvent(source: nil)?.location else { return }
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(p, 1, &id, &count) == .success, count > 0, id != displayID
        else { return }
        Log.info("🎬 the pointer moved to display \(id) — filming it now (was \(displayID))")
        displayID = id
        DispatchQueue.main.async {
            guard let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }) else { return }
            FilmBorder.move(to: screen)
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

/// **A plain red border round the screen being filmed, blinking** (2026-10-08,
/// Victor: *"when the movie is recorded, there should be a red border, not any
/// fade, just a plain red border, a few pixels solid, around the screen
/// recorded, and blinking 50% transparent to 100% opaque"*). Solid 5 pt, a
/// hard step between 100 % and 50 % every half second — no ease. Clicks pass
/// through; `sharingType = .none` keeps it out of the frames it frames
/// (checked on a 10:16 film the same day: no red in any frame).
///
/// **A red dot in each corner, blinking with it** (2026-10-08) — superseded
/// 2026-10-13 by the camcorder badge below.
///
/// **One `● REC` in the top-right corner, like a camcorder's viewfinder**
/// (2026-10-13, Victor: *"the record circles in the corners should be like three
/// x large and be blinking slowly … say REC … It should only appear in the top
/// right. To resemble a VCR camera"*). The dot is 3 × the old 14 pt and blinks
/// on its own slow clock — a hard step, a second lit and a second dark — while
/// `REC` stays lit beside it, the way a viewfinder does it. It sits under the
/// menu bar, which would otherwise draw over it. The border keeps its own
/// half-second blink, so the two are separate layers now.
///
/// **The dot and `REC` 20 % larger** (2026-10-16, Victor: *"the red dot next to
/// the record in the top corner and the text should be 20% larger"*): 42 → 50 pt
/// dot, 40 → 48 pt text.
///
/// **50 % larger again, in all four corners, and a click on any of them stops
/// the recording** (2026-10-20, Victor: *"the rec label … should be 50% larger
/// … displayed in all four corners. Any clicking the red text or red bubble
/// should stop the recording. I always forget how to stop it … they shouldn't
/// show up in the frames, but they should stay on screen so I can hover them
/// and click them"*): 50 → 75 pt dot, 48 → 72 pt text. Each badge is its own
/// small panel that takes the left click (`RecBadgeView`) — the border stays
/// click-through, it covers the whole display — and every one keeps
/// `sharingType = .none`, so none is in a frame. Under the pointer the dot stops
/// blinking and the pointer becomes a hand, so the thing he aims at is there.
enum FilmBorder {
    private static var panel: NSPanel?
    private static var badges: [NSPanel] = []
    /// What a click on a badge does — `AppDelegate` stops the film. Main thread.
    static var onClick: (() -> Void)?
    static let width: CGFloat = 5
    static let dot: CGFloat = 75
    static let textSize: CGFloat = 72
    /// Between the dot and `REC`, and from the screen's edge (inside the border).
    private static let gap: CGFloat = 18
    private static let margin: CGFloat = width + 16
    /// The dot's whole cycle, half lit, half dark.
    static let slowBlink: CFTimeInterval = 2.0
    fileprivate static let ink = NSColor.systemRed

    static func show(on screen: NSScreen) {
        guard Thread.isMainThread else { DispatchQueue.main.async { show(on: screen) }; return }
        hide()
        let p = overlayPanel(frame: screen.frame)
        p.ignoresMouseEvents = true
        p.contentView = borderView(size: screen.frame.size)
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
        panel = p

        let size = badgeSize()
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        for origin in badgeOrigins(size: screen.frame.size, menuBar: menuBar) {
            let frame = NSRect(origin: NSPoint(x: screen.frame.minX + origin.x,
                                               y: screen.frame.minY + origin.y), size: size)
            let b = overlayPanel(frame: frame)
            b.ignoresMouseEvents = false
            b.becomesKeyOnlyIfNeeded = true
            b.contentView = RecBadgeView(frame: NSRect(origin: .zero, size: size),
                                         scale: screen.backingScaleFactor)
            b.setFrame(frame, display: true)
            b.orderFrontRegardless()
            badges.append(b)
        }
    }

    private static func overlayPanel(frame: NSRect) -> NSPanel {
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.sharingType = .none
        p.hidesOnDeactivate = false
        return p
    }

    /// The border follows the film to another display — but only while it is
    /// up: a switch queued just before `stop()` must not bring it back after.
    static func move(to screen: NSScreen) {
        guard panel != nil else { return }
        show(on: screen)
    }

    /// The whole drawing — border and the four badges — for `FilmBorderTests`
    /// (`FILM_BORDER_PNG=<dir>`); the panels are out of every screenshot.
    static func content(size: CGSize, menuBar: CGFloat, scale: CGFloat) -> NSView {
        let v = borderView(size: size)
        for origin in badgeOrigins(size: size, menuBar: menuBar) {
            // Layers, not `RecBadgeView`s: a subview's layer joins its parent's
            // only once the view is in a window, and this one never is.
            let badge = badgeLayer(scale: scale)
            badge.frame.origin = origin
            v.layer?.addSublayer(badge)
        }
        return v
    }

    private static func borderView(size: CGSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        v.wantsLayer = true
        let border = CALayer()
        border.frame = CGRect(origin: .zero, size: size)
        border.borderWidth = width
        border.borderColor = ink.cgColor
        border.add(blink(values: [1.0, 0.5], duration: 1.0), forKey: "blink")
        v.layer?.addSublayer(border)
        return v
    }

    static func recText() -> NSAttributedString {
        NSAttributedString(string: "REC", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: textSize, weight: .heavy),
            .foregroundColor: ink,
        ])
    }

    /// `● REC`, with room for the halo.
    static func badgeSize() -> CGSize {
        let text = recText().size()
        return CGSize(width: dot + gap + ceil(text.width), height: max(dot, ceil(text.height)))
    }

    /// One `● REC`: the dot (the first sublayer) blinking slowly, `REC` steady
    /// beside it, a dark halo so the red reads on a white page as well as on a
    /// terminal.
    static func badgeLayer(scale: CGFloat) -> CALayer {
        let size = badgeSize()
        let badge = CALayer()
        badge.frame = CGRect(origin: .zero, size: size)
        let text = recText()
        let textSize = text.size()
        let rec = CATextLayer()
        rec.string = text
        rec.contentsScale = scale
        rec.frame = CGRect(x: size.width - ceil(textSize.width),
                           y: (size.height - ceil(textSize.height)) / 2,
                           width: ceil(textSize.width), height: ceil(textSize.height))
        let d = CALayer()
        d.frame = CGRect(x: 0, y: (size.height - dot) / 2, width: dot, height: dot)
        d.cornerRadius = dot / 2
        d.backgroundColor = ink.cgColor
        d.add(blink(values: [1.0, 0.0], duration: slowBlink), forKey: "blink")
        for layer in [d, rec] {
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.6
            layer.shadowRadius = 3
            layer.shadowOffset = .zero
            badge.addSublayer(layer)
        }
        return badge
    }

    /// Bottom-left origins of the four badges, in the screen's own points: the
    /// top two under the menu bar, which would otherwise draw over them.
    static func badgeOrigins(size: CGSize, menuBar: CGFloat) -> [CGPoint] {
        let b = badgeSize()
        let left = margin, right = size.width - margin - b.width
        let bottom = margin, top = size.height - menuBar - margin - b.height
        return [CGPoint(x: left, y: top), CGPoint(x: right, y: top),
                CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)]
    }

    /// A hard step, no ease: the first value for the first half, the second after.
    ///
    /// **A discrete animation needs one more key time than values** — `[0, 0.5, 1]`
    /// for two. With `[0, 0.5]` Core Animation silently ignores it: neither the dot
    /// nor the border had ever blinked (measured 2026-10-16 on the presentation
    /// layer: opacity stuck at 1.0 with two key times, 1 → 0 → 1 with three).
    static func blink(values: [Double], duration: CFTimeInterval) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = values
        a.keyTimes = [0, 0.5, 1]
        a.calculationMode = .discrete
        a.duration = duration
        a.repeatCount = .infinity
        return a
    }

    static func hide() {
        guard Thread.isMainThread else { DispatchQueue.main.async { hide() }; return }
        panel?.orderOut(nil)
        panel = nil
        badges.forEach { $0.orderOut(nil) }
        badges = []
    }
}

/// A badge's panel: `FilmBorder.badgeLayer`, and a left click anywhere on it
/// is `FilmBorder.onClick`.
final class RecBadgeView: NSView {
    private let badge: CALayer
    private var dotLayer: CALayer? { badge.sublayers?.first }

    init(frame: NSRect, scale: CGFloat) {
        badge = FilmBorder.badgeLayer(scale: scale)
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(badge)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .cursorUpdate,
                                                 .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        Log.info("🎬 ● REC clicked — stopping the recording")
        FilmBorder.onClick?()
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        dotLayer?.removeAnimation(forKey: "blink")
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        dotLayer?.add(FilmBorder.blink(values: [1.0, 0.0], duration: FilmBorder.slowBlink),
                      forKey: "blink")
    }
}
