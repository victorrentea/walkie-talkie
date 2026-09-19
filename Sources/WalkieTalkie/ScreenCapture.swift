import AppKit
import ImageIO
import VictorMacKit

/// Screenshots the display under the cursor into `~/Library/Caches/…/shots`.
///
/// The overlay does **not** need hiding: `sharingType = .none` on the panel
/// already excludes it from every capture — verified with a shot taken by a
/// separate process while the overlay was on screen and unhidden. That matters
/// for the automatic capture at dictation start, which fires on every single
/// dictation and must not blink the overlay each time.
///
/// The red vignette is **not** fired here. A frame of the screen leaves the
/// machine on every dictation and every ⌃⌥P, so both deserve the same visible
/// receipt — but the receipt belongs at the *start* of the gesture, not after
/// this subprocess has been waited on. Callers announce first, then grab.
enum ScreenCapture {

    /// `cursor` is where the pointer was **at the moment of the gesture**, in
    /// AppKit screen coordinates. It is passed in rather than read here because
    /// this runs after a clipboard probe that sleeps up to 400ms — by then the
    /// hand has moved on, and the whole point of recording it is to say what he
    /// was pointing at when he pressed.
    ///
    /// `offset` is **where in the dictation** this shot was taken, in seconds
    /// from the moment Victor started talking — `0` for the automatic context
    /// capture, which he took by starting to talk. nil for a shot with no
    /// dictation around it (bare F3), where there is no clock for it to be an
    /// offset into and the name falls back to a timestamp.
    /// **What a capture answers with** (2026-09-19). The pointer and the dragged
    /// rectangle used to be written into the file's name; they are now tokens
    /// *inside the sentence* (`[📸1🖱️@1000:800]`), so the capture has to hand
    /// them back rather than spell them. The size comes with them because the
    /// footer says what `-original.jpg` is, and the only thing that honestly
    /// knows is the JPEG this call just produced.
    struct Frame {
        /// The full-resolution file — `…-original.jpg`. `handover(for:)` gives
        /// the 800 px copy, `zoom(for:)` the unscaled cut-out of an area.
        let path: String
        /// Where the pointer was, in the pixels of **this** frame, top-left
        /// origin. Nil when the screen could not be resolved.
        let mouse: CGPoint?
        /// The rectangle he dragged, in the same pixels. Area captures only.
        let area: CGRect?
        /// The frame's own pixel size, for the footer's `at 3456x2234px`.
        let size: CGSize?
    }

    static func grab(cursor: NSPoint? = nil, offset: TimeInterval? = nil,
                     index: Int? = nil) -> Frame? {
        let mouse = cursor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
        let display = activeDisplayNumber(of: screen)
        let spot = cursorFraction(mouse: mouse, screen: screen)
        let file = Outbox.shotsDir
            .appendingPathComponent(uniqueBase(stem(offset, index)) + "-original.jpg")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "jpg", "-D", String(display), file.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("screencapture failed: \(error)")
            return nil
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            Log.error("screencapture produced no file (Screen Recording permission?)")
            return nil
        }
        // **Nothing is drawn into the picture.** The reticle used to be burned in
        // here; it is now flashed on the desktop at the instant of the shutter
        // (`CaptureFlash.markCursor`) and nowhere else. A frame handed to an
        // agent should be what was on the screen — a red target painted over it
        // covers whatever it is pointing at, which is precisely the thing being
        // asked about, and reads as part of the UI to anything looking at the
        // image. The position still travels, in the file name.
        //
        // It also drops a second JPEG pass over a frame `screencapture` already
        // encoded: ~100ms and a file that came back *larger* at quality 1.0.
        let size = pixelSize(of: file)
        writeHandoverCopy(of: file)
        prune()
        return Frame(path: file.path, mouse: pixels(spot, in: size), area: nil, size: size)
    }

    /// The pointer as whole pixels of a frame of this size — the reading that
    /// used to be baked into the name, measured the same way: off the JPEG,
    /// never multiplied out of the screen's backing scale.
    private static func pixels(_ spot: CGPoint?, in size: CGSize?) -> CGPoint? {
        guard let spot = spot, let size = size else { return nil }
        return CGPoint(x: (spot.x * size.width).rounded(),
                       y: (spot.y * size.height).rounded())
    }

    /// **A region he dragged out, rather than the display he was looking at.**
    ///
    /// The whole-screen frame is the default and is very often mostly
    /// irrelevant: 800px of handover is spent on a desktop when a panel would
    /// do, and the agent has to *find* the thing in it before it can read it. A
    /// crop is the same gesture pointed at one answer — and it costs the pixels
    /// it contains rather than the pixels the monitor has.
    ///
    /// `rect` is in global Cocoa coordinates, on `screen`, already chosen and
    /// already rounded to whole points by `CropSelectionOverlay`.
    ///
    /// **The name is `area-`, and the whole point is that it is not `shot-`.**
    /// An agent is handed both kinds in one list; the frame it gets is a
    /// rectangle of pixels with nothing in it saying whether the edges are the
    /// edges of a screen. `shotsClause` says so once in the clause, and the
    /// prefix is what each entry says for itself.
    ///
    /// The pointer is deliberately **not** in this name, where a full-screen
    /// shot carries it. There it answers "which of these thousand things was he
    /// pointing at"; here he answered that by dragging a box round it, and the
    /// pointer is merely the corner he happened to let go on. What takes its
    /// place is the size, which is the one fact about a crop that is not
    /// obvious from looking at it.
    /// **The whole screen, with the region he dragged written into the name**
    /// (2026-09-14). Victor: *"să se trimită nu doar decupată poza, ci poza e
    /// ecranul integral, dar cu coordonate ce zonă am selectat … nu doar decupez
    /// o bucată, ci arăt: în zona aia vreau să dispară, să apară ceva"*.
    ///
    /// The drag stopped being a crop and became a **pointing gesture**. A crop
    /// answers *look at this*; it cannot say *put something here*, because the
    /// thing he is pointing at is often the empty space and the surroundings are
    /// what make it meaningful. So the frame is the display, exactly as the
    /// shutter's is, and the rectangle travels as four numbers in the name —
    /// where the cursor's position already travels, and for the same reason
    /// (nothing is drawn into the picture; see `grab`).
    static func grabArea(_ rect: NSRect, on screen: NSScreen, offset: TimeInterval?,
                         index: Int? = nil) -> Frame? {
        let file = Outbox.shotsDir
            .appendingPathComponent(uniqueBase(stem(offset, index)) + "-original.jpg")
        let display = activeDisplayNumber(of: screen)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "jpg", "-D", String(display), file.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("screencapture failed: \(error)")
            return nil
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            Log.error("screencapture produced no file (Screen Recording permission?)")
            return nil
        }
        let px = areaPixels(rect, on: screen, of: file)
        writeHandoverCopy(of: file)
        // **And the region itself, cut out, unscaled** (2026-09-19, Victor:
        // *"trimite atât ecranul original + 800px ca până acum, dar și selecția
        // originală decupată (nescalată)"*). The frame answers *where*, this one
        // answers *what it says there* — measured in `evals/pointing-proof/`: with
        // nothing highlighted, the 800 px screen alone names the sentence he framed
        // 21/28, the screen with a cut-out beside it 15/16. The two are one picture
        // in every count that matters (the chip, `prune`, `paths`); this file is a
        // sibling found by name, exactly like `-small`.
        if let px = px { writeRegionCopy(of: file, px: px) }
        prune()
        return Frame(path: file.path, mouse: nil, area: px, size: pixelSize(of: file))
    }

    /// The dragged rectangle **in the pixels of this image**, top-left origin
    /// like the image itself.
    ///
    /// Measured off the JPEG rather than multiplied out of the screen's backing
    /// scale: the two displays here have different scales and the file is the
    /// only thing that knows which one it came from. It used to write the four
    /// numbers into the name; they ride the envelope's own token now
    /// (`[📸3✂️x1,y1→x2,y2]`), so this only measures.
    private static func areaPixels(_ rect: NSRect, on screen: NSScreen, of file: URL) -> CGRect? {
        guard let size = pixelSize(of: file),
              let a = cursorFraction(mouse: NSPoint(x: rect.minX, y: rect.maxY), screen: screen),
              let b = cursorFraction(mouse: NSPoint(x: rect.maxX, y: rect.minY), screen: screen)
        else { return nil }
        let x1 = (a.x * size.width).rounded(), y1 = (a.y * size.height).rounded()
        let x2 = (b.x * size.width).rounded(), y2 = (b.y * size.height).rounded()
        return CGRect(x: min(x1, x2), y: min(y1, y2),
                      width: abs(x2 - x1), height: abs(y2 - y1))
    }

    /// Write `<name>-zoom.jpg` beside an area frame: **the rectangle he dragged,
    /// cut out of that very frame, at its own pixels and not downscaled.**
    ///
    /// **Why it is cut out of the frame rather than captured again.** A second
    /// `screencapture -R` is a second subprocess (~200 ms) photographing a screen
    /// that has had time to change; this is the same instant by construction. It
    /// costs a full decode and re-encode — the ~100 ms the burned-in cursor mark
    /// was removed from `grab` for — which is affordable here and nowhere else:
    /// `fileArea` already runs on a background queue with the panels down.
    ///
    /// **No `-small` for this one, deliberately.** It is the unscaled copy or it
    /// is nothing — `handover(for:)` falls back to the file itself when no small
    /// sibling exists, so the clause lists this one as it is. The reading tool
    /// fits any image to 2000 px on the long edge before it charges for it, so
    /// the worst a zoom can cost is what a whole retina desktop costs (~3450
    /// tokens) and a typical band of text is 400–900.
    @discardableResult
    private static func writeRegionCopy(of file: URL, px: CGRect) -> URL? {
        guard px.width >= 2, px.height >= 2 else { return nil }
        let dst = URL(fileURLWithPath: sibling(of: file.path, ""))
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Log.error("could not read \(file.lastPathComponent) to cut the region out")
            return nil
        }
        // Clamped to the frame: the rectangle is measured through
        // `cursorFraction`, so a box drawn hard against an edge can round a pixel
        // past it, and `cropping(to:)` answers nil for a rect that is not inside.
        let box = px.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !box.isNull, let cut = full.cropping(to: box),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            Log.error("could not cut \(Int(px.width))x\(Int(px.height)) out of \(file.lastPathComponent)")
            return nil
        }
        CGImageDestinationAddImage(dest, cut, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        Log.info("✂️ region cut out unscaled — \(cut.width)x\(cut.height)px (\(dst.lastPathComponent))")
        return dst
    }

    /// The unscaled cut-out beside an area frame, if one was written —
    /// `screenshot-3.jpg` beside `screenshot-3-original.jpg`. Nil for every
    /// other picture, which is what makes it safe to ask of all of them and is
    /// what `isArea` reads.
    static func zoom(for path: String) -> String? {
        let cut = sibling(of: path, "")
        guard cut != path, FileManager.default.fileExists(atPath: cut) else { return nil }
        return cut
    }

    /// The picture's number in this dictation, off its own name — `📸3` and
    /// `screenshot-3-original.jpg` are the same digit, and the name is what says
    /// so to the agent.
    static func number(of path: String) -> Int? {
        let stem = (path as NSString).lastPathComponent
        guard let m = stem.range(of: #"^screenshot-(\d+)[-.]"#, options: .regularExpression)
        else { return nil }
        return Int(stem[m].dropFirst("screenshot-".count).dropLast())
    }

    /// True for a frame `grabArea` wrote — asked of the **files**, not of the
    /// name: an area frame is the one with a cut-out beside it (2026-09-19,
    /// when the name became `screenshot-3` and stopped saying anything).
    static func isArea(_ path: String) -> Bool { zoom(for: path) != nil }

    /// The width of the copy the **agent** is given. Victor still gets the retina
    /// frame; this is the one that travels.
    ///
    /// Measured, not guessed. A read of an image costs about `width × height / 750`
    /// tokens after the tool has fitted it to 2000px on the long edge, so a
    /// 3456×2234 desktop arrives as 2000×1293 and costs ~3450 tokens **whatever
    /// the JPEG weighs** — compressing the file harder buys nothing at all. The
    /// same desktop at 1000px wide costs ~860, and at 800px ~550.
    ///
    /// Whether that fourfold saving takes any of the answer with it is the one
    /// question that had to be answered by running it rather than by arguing, and
    /// `evals/` is where that happened: 31 runs of a real agent over two real
    /// dictations off the outbox, one of them seven frames of Gmail where every
    /// frame has to be matched to its clause, the other three frames where the
    /// question is what the mouse was sitting on. At 1000px the agent returned
    /// **byte-identical answers** to the retina runs, down to quoting
    /// `⇒in browser/sql LIMIT OFFSET` off a code editor. Accuracy 0.96 against
    /// 0.98, inside the noise of the runs; the frames actually opened cost 6027
    /// tokens instead of 24129.
    ///
    /// Two things that sound like improvements were measured and are **not**
    /// here, both of which cost accuracy:
    ///
    /// - **A native-resolution crop around the pointer**, offered beside the
    ///   small frame, scored 0.87 — it is not that the crop is unreadable, it is
    ///   that two pictures per shot make the *sequence* harder to keep straight,
    ///   and one run duly returned the first two shots swapped. Sequence is the
    ///   thing these messages are made of.
    /// - **Dropping the automatic context frame** scored 0.93, and the reason is
    ///   worth keeping: it is not a spare. Victor starts talking about the thing
    ///   already on his screen, so the context frame is routinely *picture one*
    ///   of the enumeration — in the Gmail dictation it is the first of the seven
    ///   senders. It is offered cheaply, not withheld.
    ///
    /// **1000 became 800 on 2026-08-22**, and the reason is that nothing had ever
    /// measured *below* 1000 — it was the first width tried against retina, it
    /// came out free, and it stayed. `evals/text-vs-pixels.md` walked the ladder
    /// down: 33 more runs, both fixtures, and **6/6 clean at 800, 6/6 clean at
    /// 700, and no legibility failure even at 500px**, where a 3456×2234 desktop
    /// is 215 tokens and still gives all seven senders. The two cells that came
    /// in under 1.00 failed at the *sequence* of the shots and at a fixture key
    /// too narrow to accept a correct answer — neither of them at reading.
    ///
    /// So 800 is deliberately **one rung above the cheapest width that worked**.
    /// 700 is what the evidence points at (-51% instead of -36%) and 500 is where
    /// the pictures stop mattering at all, but three repeats a cell is thin, both
    /// fixtures now score 1.00 at every width they used to discriminate, and the
    /// frames are also read by Victor when he opens the folder. Taking the whole
    /// measured saving on a saturated suite is how a cliff gets found in
    /// production instead of in `evals/`.
    /// Not private: `AppDelegate.shotsClause` tells the agent how wide these are,
    /// and a second literal saying 1000 is how the line came to disagree with the
    /// pixels the first time this number moved.
    static let handoverWidth = 800

    /// Write `<name>-small.jpg` beside the frame, downscaled.
    ///
    /// **The retina frame stays.** It is what Victor opens when he wants to see
    /// what he photographed, on a display that has the pixels for it, and a
    /// staging folder that had thrown the original away would be answering a
    /// token bill by degrading his own copy. The small one is ~170 KB against
    /// ~1.8 MB, so keeping both costs a tenth of what one frame already costs.
    ///
    /// ImageIO's thumbnail path, not a decode-and-re-encode: it scales during
    /// the JPEG decode, which is why this can sit in the capture path at all —
    /// the burned-in cursor mark was removed from here partly for costing ~100ms
    /// of exactly that kind of second pass.
    @discardableResult
    private static func writeHandoverCopy(of file: URL) -> URL? {
        let dst = URL(fileURLWithPath: sibling(of: file.path, "-800px"))
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: handoverWidth,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            Log.error("could not downscale \(file.lastPathComponent)")
            return nil
        }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return dst
    }

    /// The 800 px copy for a frame — `…-800px.jpg` beside `…-original.jpg`.
    ///
    /// Falls back to the frame itself rather than to nothing: a downscale that
    /// failed must cost tokens, never a picture.
    static func handover(for path: String) -> String {
        let small = sibling(of: path, "-800px")
        return FileManager.default.fileExists(atPath: small) ? small : path
    }

    /// `…-original.jpg` → `…<suffix>.jpg`, and `…<suffix>` alone when the suffix
    /// is empty — the cut-out is `screenshot-3.jpg` beside
    /// `screenshot-3-original.jpg`, which is Victor's naming and not a style.
    private static func sibling(of path: String, _ suffix: String) -> String {
        let url = URL(fileURLWithPath: path)
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasSuffix("-original") { stem.removeLast("-original".count) }
        return url.deletingLastPathComponent()
            .appendingPathComponent(stem + suffix + ".jpg").path
    }

    /// **`00:00`, `01:23` — where in the sentence.** A dictation's shots are read
    /// as a set, and what makes one findable among them is not what o'clock it
    /// was but *how far into what he was saying* it was taken: `📸 ×4` is four
    /// indistinguishable files, `0:00 · 0:38 · 1:52` is a table of contents. The
    /// prompt panel writes the same reading across each thumbnail
    /// (`AppDelegate.shotStamps`), and this is it put where the agent meets it —
    /// in the path.
    ///
    /// A shot with no dictation around it keeps a timestamp, because "elapsed
    /// since the start" of nothing is not a fact.
    ///
    /// NB the colon is legal in a POSIX filename on APFS and everything that
    /// handles these paths is POSIX — but **the Finder renders it as `/`**
    /// (`shot-00/00(…)`), the old HFS separator swap, so a folder Victor opens
    /// by hand will read slightly differently from what the agent sees.
    ///
    /// **The index goes in front of the offset** (2026-09-14). `shot-1-00:08(…)`
    /// rather than `shot-00:08(…)`, so the `[shot 1]` sitting in the middle of
    /// his sentence names a file by itself and the envelope needs no legend
    /// explaining the correspondence — Victor: *"it should be obvious"*. The
    /// offset stays because it is the thing that locates a frame for a human
    /// scrolling the folder; the index is what an agent resolves. Nil for a
    /// frame outside a dictation, which has no index to have.
    /// Returns the separator too, because the two shapes take different ones:
    /// `#01` reads as an index, `-00:08` as a time, and `shot-#01` reads as
    /// neither.
    private static func stem(_ offset: TimeInterval?, _ index: Int? = nil) -> String {
        // **`screenshot-3`, and the number is the only thing in it** (2026-09-19,
        // Victor's template). Everything the name used to carry — the offset, the
        // pointer, the dragged rectangle — is a token inside the sentence now
        // (`[📸3✂️900,345→2594,574]`), said once where he said it instead of twice
        // in two notations. What is left is the digit the token names, so the
        // reference and the file are the same string with no parsing in between.
        if let index = index { return "screenshot-\(index)" }
        // No dictation around it: no number to be the third picture *of*, so the
        // clock stands in. Same reasoning the offset had.
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "screenshot-" + stamp.string(from: Date())
    }


    /// A `-2`, `-3`… before the extension if that name is taken. Both names go
    /// through it — two crops of the same size at the same offset collide the
    /// same way two shots from an unmoved pointer do.
    ///
    /// The per-session folder keeps one run's shots away from another's, and the
    /// pointer position makes two shots at the same offset differ in almost every
    /// real case — but "almost" is doing work there: dictate twice without moving
    /// the mouse and both context shots are `shot-00:00(mouse-at-800x900px)`.
    /// Overwriting would destroy a picture an outbox line still points at, which
    /// is the same trap `ScreenshotManager.uniqueURL` exists for in Victor Addons.
    private static func unique(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        for n in 2...99 {
            let candidate = dir.appendingPathComponent("\(stem)-\(n).jpg")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    /// **The disambiguating `-2` goes before `-original`, never after**
    /// (2026-09-19). Every dictation in a session folder produces a
    /// `screenshot-0`, so collisions are the rule rather than the exception —
    /// and a frame called `screenshot-0-original-2.jpg` would take its siblings
    /// with it into `screenshot-0-original-2-800px.jpg`, which is neither the
    /// name the footer promises nor one `sibling(of:)` can compute. So the
    /// **base** is made unique and the suffixes are composed after it:
    /// `screenshot-0-2-original.jpg`, `screenshot-0-2-800px.jpg`.
    private static func uniqueBase(_ base: String) -> String {
        let dir = Outbox.shotsDir
        func taken(_ candidate: String) -> Bool {
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(candidate + "-original.jpg").path)
        }
        guard taken(base) else { return base }
        for n in 2...99 where !taken("\(base)-\(n)") { return "\(base)-\(n)" }
        return base
    }

    /// A session folder with nothing left in it says a session happened and
    /// tells you nothing about it. The current one is never touched: it is empty
    /// for the whole time before the first dictation.
    private static func dropEmptySessions() {
        let fm = FileManager.default
        let sessions = (try? fm.contentsOfDirectory(at: Outbox.cacheRoot,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])) ?? []
        for session in sessions where session.lastPathComponent != Outbox.sessionStamp {
            let contents = (try? fm.contentsOfDirectory(at: session,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])) ?? []
            if contents.isEmpty { try? fm.removeItem(at: session) }
        }
    }

    /// The frame's real size in pixels, read from the JPEG header — no decode,
    /// so this costs nothing next to the capture it follows.
    private static func pixelSize(of file: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Where the pointer sat, as a fraction of the frame in **image** coordinates:
    /// 0…1 across, 0…1 down from the top. The same reading feeds the file name and
    /// the marker painted into the picture, so the two can never disagree about
    /// what he was pointing at.
    private static func cursorFraction(mouse: NSPoint, screen: NSScreen?) -> CGPoint? {
        guard let frame = screen?.frame, frame.width > 0, frame.height > 0 else { return nil }
        let clamp = { (v: CGFloat) in min(max(v, 0), 1) }
        // AppKit counts y up from the bottom, images count it down from the top.
        return CGPoint(x: clamp((mouse.x - frame.minX) / frame.width),
                       y: clamp((frame.maxY - mouse.y) / frame.height))
    }

    /// One screenshot per dictation adds up fast — Victor dictates all day, and
    /// each retina JPG is a megabyte or two. Keep the most recent `keepNewest`
    /// and drop the rest, so the folder can't quietly eat the disk.
    ///
    /// Being in Caches means the system may reclaim these anyway; that is a
    /// backstop for a full disk, not a policy, and it fires far too late to be
    /// the only thing bounding a folder that grows all day.
    private static let keepNewest = 300

    /// Counted **across every session folder**, not within the current one.
    /// A relay session can be five minutes long, so a per-folder cap would keep
    /// 300 shots per restart and bound nothing at all. Session folders left empty
    /// by the sweep are removed with their contents — an empty stamp is litter,
    /// and the folders are how yesterday's shots are found until they go.
    private static func prune() {
        let fm = FileManager.default
        let sessions = (try? fm.contentsOfDirectory(at: Outbox.cacheRoot,
                                                    includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])) ?? []
        var jpgs: [URL] = []
        for session in sessions {
            let files = (try? fm.contentsOfDirectory(
                at: session,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            // **Frames, not files.** A shot is two of them — the retina capture
            // and the small copy handed to the agent — and an area frame is
            // three, with the unscaled cut-out of the region (2026-09-19).
            // Counting the siblings would silently divide a cap expressed in
            // pictures; they are dropped together with the frame they belong to,
            // below.
            // **Frames are the `-original` files.** A shot is two of them (the
            // frame and its 800 px copy) and an area shot is three, with the
            // unscaled cut-out; counting the siblings would divide a cap
            // expressed in pictures. They are dropped together, below.
            jpgs += files.filter {
                $0.pathExtension.lowercased() == "jpg"
                    && $0.deletingPathExtension().lastPathComponent.hasSuffix("-original")
            }
        }
        defer { dropEmptySessions() }
        pruneFilms(in: sessions)
        guard jpgs.count > keepNewest else { return }
        let sorted = jpgs.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for stale in sorted.dropFirst(keepNewest) {
            try? FileManager.default.removeItem(at: stale)
            for suffix in ["-800px", ""] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: sibling(of: stale.path, suffix)))
            }
        }
    }

    /// **Screen recordings are counted as recordings, not as frames**
    /// (2026-09-18).
    ///
    /// `prune` above walks one level into each session and collects JPEGs, so a
    /// `film-<stamp>/` **sub**folder is invisible to it in both directions: its
    /// frames are never counted against `keepNewest`, which is right — one
    /// four-second recording is twenty frames and would evict twenty real
    /// screenshots — and they are never deleted either, which is not. At ~800 KB
    /// a frame and 5 fps, a day of recordings is gigabytes nothing ever removes.
    ///
    /// So they are pruned by their own unit: the newest `keepFilms` recordings
    /// survive whole, the rest go whole. A recording is only meaningful entire —
    /// half a film is a sheet whose cells point at files that are no longer
    /// there — so there is nothing to do at frame granularity.
    private static let keepFilms = 6

    private static func pruneFilms(in sessions: [URL]) {
        let fm = FileManager.default
        var films: [URL] = []
        for session in sessions {
            let entries = (try? fm.contentsOfDirectory(
                at: session, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            films += entries.filter {
                $0.lastPathComponent.hasPrefix("film-")
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        }
        guard films.count > keepFilms else { return }
        let sorted = films.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
        for stale in sorted.dropFirst(keepFilms) {
            try? fm.removeItem(at: stale)
            Log.info("🎬 pruned an old recording — \(stale.lastPathComponent)")
        }
    }

    /// 1-indexed display number as `screencapture -D` expects, for the screen
    /// holding the cursor.
    ///
    /// Must be derived from the **active** display list, not the online one:
    /// online includes displays that are asleep or mirrored, so with a sleeping
    /// external monitor the online index overshoots and `screencapture` rejects
    /// it outright ("Invalid display specified. Only 1 display…") — no file, no
    /// screenshot. The count is clamped for the same reason.
    private static func activeDisplayNumber(of screen: NSScreen?) -> Int {
        guard let screen = screen,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return 1 }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }
        guard let index = displays.firstIndex(of: displayID), index < Int(count) else { return 1 }
        return index + 1
    }
}
