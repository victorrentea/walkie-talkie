import AppKit

/// **The bound project's own logo, on the chip at rest**
/// (2026-11-22, Victor: *"când sunt bound la un proiect, lângă iconița walkie să
/// apară logoul proiectului (de ex. cat pt petclinic)"*). Since 2026-11-24 it
/// stands **in place of** the walkie, not beside it; the walkie is left for the
/// workspace and for projects with no logo.
///
/// The project is the repo root of the directory the binding already read its
/// `folder@branch` from: `TerminalBinding.label(forDirectory:)` notes the
/// directory behind every label it hands out (`note`), so nothing here asks a
/// terminal anything a second time.
///
/// Where the picture comes from, first hit wins:
///
/// 1. `<root>/.walkie/logo.{png,svg,pdf,jpg,jpeg,icns,ico}` — the project says so.
/// 2. `ProjectIcons`' coloured mark for that folder name — the marks Victor
///    chose for the spawn menu (🐱 petclinic…), in their colours here.
/// 3. `ProjectIcons`' monochrome mark, white with the walkie's black rim
///    (training-assistant's mortarboard).
///
/// **Nothing else: no search through the project's files** (2026-11-23, Victor:
/// *"să nu caute … doar proiectele cu logo stabilit hard-codat să aibă logo"*).
/// Bound to `~/workspace` — no repo, every sub-folder another project — the
/// search had put a course repo's favicon beside the walkie. Nothing found is
/// nothing drawn. The one file check runs off the main thread, and its answer is
/// cached per root for `freshFor`.
enum ProjectLogo {

    /// Points: the walkie's own height (`RelayWindow.walkieInk`, 19). It was a
    /// point under, as a subject beside the state; on 2026-11-23 Victor asked for
    /// it *"cu aceeași înălțime ca iconul walkie"*, and the chip also scales it to
    /// the walkie glyph actually drawn and centres it on that glyph's midline.
    static let side: CGFloat = 19

    // MARK: - label → directory

    private static let lock = NSLock()
    private static var directories: [String: String] = [:]

    /// Called by `TerminalBinding.label(forDirectory:)`, on whatever queue it runs.
    static func note(label: String, directory: String) {
        lock.lock(); defer { lock.unlock() }
        directories[label] = directory
    }

    static func directory(forLabel label: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return directories[label]
    }

    // MARK: - the answer, cached

    private static var cache: [String: (image: NSImage?, at: Date)] = [:]   // main only
    static let freshFor: TimeInterval = 60
    private static var asked = 0                                             // main only
    private static let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.project-logo", qos: .utility)

    /// The logo of the project `label` (a binding's `folder@branch` line) was
    /// read in. Main thread. `done` is called on main, **synchronously when the
    /// answer is cached** (so a re-bind to the same project never blinks), and
    /// again after a re-read when the cached one is older than `freshFor`.
    static func resolve(label: String?, done: @escaping (NSImage?) -> Void) {
        // Only the newest ask may answer late: a search that outlives its binding
        // must not put its picture beside the next one.
        asked += 1
        let ask = asked
        guard let label, let dir = directory(forLabel: label) else { return done(nil) }
        let root = repoRoot(of: dir)
        let cached = cache[root]
        if let cached {
            done(cached.image)
            if Date().timeIntervalSince(cached.at) < freshFor { return }
        }
        queue.async {
            let found = override(inRoot: root)
            DispatchQueue.main.async {
                let image = compose(root: root, override: found)
                cache[root] = (image, Date())
                guard ask == asked else { return }
                // The same picture again is not news: the chip keeps the view it has.
                if cached == nil || (cached?.image == nil) != (image == nil)
                    || cached?.image?.tiffRepresentation != image?.tiffRepresentation {
                    done(image)
                }
            }
        }
    }

    /// The whole answer in one call, for tests and the `WT_SHOOT_PROJECT_LOGO` render.
    static func logo(forDirectory dir: String) -> NSImage? {
        let root = repoRoot(of: dir)
        return compose(root: root, override: override(inRoot: root))
    }

    /// Which tier answered, for the log and the tests.
    static func source(forDirectory dir: String) -> String {
        let root = repoRoot(of: dir)
        let name = (root as NSString).lastPathComponent
        if let o = override(inRoot: root) { return "override \(o)" }
        switch ProjectIcons.original(for: name) {
        case .colour?: return "ProjectIcons colour mark"
        case .template?: return "ProjectIcons template mark"
        case nil: return "none"
        }
    }

    private static func compose(root: String, override path: String?) -> NSImage? {
        if let path, let image = load(path) { return image }
        switch ProjectIcons.original(for: (root as NSString).lastPathComponent) {
        case .colour(let image)?: return render(image)
        case .template(let image)?: return outlined(image)
        case nil: return nil
        }
    }

    // MARK: - the repo root

    /// The nearest ancestor holding a `.git` (a folder, or a worktree's file),
    /// at most eight levels up and never above the home folder; `dir` itself
    /// when there is none.
    static func repoRoot(of dir: String) -> String {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var at = (dir as NSString).standardizingPath
        for _ in 0..<8 {
            if fm.fileExists(atPath: at + "/.git") { return at }
            let up = (at as NSString).deletingLastPathComponent
            if up == at || at == home || up == "/" { break }
            at = up
        }
        return (dir as NSString).standardizingPath
    }

    // MARK: - the project's own say

    /// `<root>/.walkie/logo.*`, the only file looked at — never a search.
    static func override(inRoot root: String) -> String? {
        for ext in ["png", "svg", "pdf", "jpg", "jpeg", "icns", "ico"] {
            let path = "\(root)/.walkie/logo.\(ext)"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - drawing

    private static func load(_ path: String) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path), image.isValid,
              image.size.width > 0, image.size.height > 0 else { return nil }
        return render(image)
    }

    /// The picture at the chip's size: its transparent margins cut off (an
    /// emoji's bearing, an icon's grid inset), fitted into `side`, and **rounded
    /// when it is a full square** — a tile with four opaque corners beside the
    /// pointer reads as a sticker. No rim, no shadow: in its own colours.
    static func render(_ image: NSImage) -> NSImage? {
        let px = 128
        guard let rep = bitmap(px, px) else { return nil }
        draw(into: rep) {
            image.draw(in: ProjectIcons.fit(image.size, in: NSRect(x: 0, y: 0, width: px, height: px)),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
        guard let ink = inkBounds(rep), let cut = rep.cgImage?.cropping(to: ink) else { return nil }
        let k = side / CGFloat(max(cut.width, cut.height))
        let size = NSSize(width: max(1, (CGFloat(cut.width) * k).rounded()),
                          height: max(1, (CGFloat(cut.height) * k).rounded()))
        let scale: CGFloat = 4
        guard let out = bitmap(Int(size.width * scale), Int(size.height * scale)) else { return nil }
        let full = NSRect(x: 0, y: 0, width: out.pixelsWide, height: out.pixelsHigh)
        let square = abs(cut.width - cut.height) <= 2 && opaqueCorners(rep, ink)
        draw(into: out) {
            if square {
                let r = full.width * 0.22
                NSBezierPath(roundedRect: full, xRadius: r, yRadius: r).addClip()
            }
            NSGraphicsContext.current?.imageInterpolation = .high
            NSGraphicsContext.current?.cgContext.draw(cut, in: full)
        }
        out.size = size
        let result = NSImage(size: size)
        result.addRepresentation(out)
        return result
    }

    /// A monochrome mark as the walkie beside it is drawn: white, 1 pt black rim.
    private static func outlined(_ mark: NSImage) -> NSImage? {
        let rim: CGFloat = 1
        let box = NSRect(x: 0, y: 0, width: side - 2 * rim, height: side - 2 * rim)
        let rect = ProjectIcons.fit(mark.size, in: box)
        let shape = NSImage(size: rect.size, flipped: false) { r in
            mark.draw(in: r); NSColor.black.set(); r.fill(using: .sourceAtop); return true
        }
        let white = NSImage(size: rect.size, flipped: false) { r in
            mark.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
        }
        let size = NSSize(width: rect.width + 2 * rim, height: rect.height + 2 * rim)
        let scale: CGFloat = 4
        guard let out = bitmap(Int(size.width * scale), Int(size.height * scale)) else { return nil }
        out.size = size
        draw(into: out) {
            for i in 0..<16 {
                let a = CGFloat(i) / 16 * 2 * .pi
                shape.draw(in: NSRect(x: rim + cos(a) * rim, y: rim + sin(a) * rim,
                                      width: rect.width, height: rect.height))
            }
            white.draw(in: NSRect(x: rim, y: rim, width: rect.width, height: rect.height))
        }
        let result = NSImage(size: size)
        result.addRepresentation(out)
        return result
    }

    private static func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep? {
        guard w > 0, h > 0 else { return nil }
        return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    }

    private static func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func alpha(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> UInt8 {
        guard let data = rep.bitmapData else { return 0 }
        return data[y * rep.bytesPerRow + x * 4 + 3]
    }

    /// The pixels that carry ink, in the bitmap's own rows (top row first).
    private static func inkBounds(_ rep: NSBitmapImageRep) -> CGRect? {
        var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where alpha(rep, x, y) > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func opaqueCorners(_ rep: NSBitmapImageRep, _ ink: CGRect) -> Bool {
        let x0 = Int(ink.minX) + 1, x1 = Int(ink.maxX) - 2, y0 = Int(ink.minY) + 1, y1 = Int(ink.maxY) - 2
        guard x1 > x0, y1 > y0 else { return false }
        return [(x0, y0), (x1, y0), (x0, y1), (x1, y1)].allSatisfy { alpha(rep, $0.0, $0.1) > 230 }
    }

    // MARK: - at a desk

    /// `WT_SHOOT_PROJECT_LOGO=<dir>` with `WT_SHOOT_PROJECT_LOGO_FOLDERS=a:b`:
    /// for each folder, the resting chip's glyph as it draws it (the logo in
    /// the walkie's place, or the walkie when there is none) on a dark and on a light ground, at 8×, as
    /// `<dir>/<name>-dark.png` / `-light.png`. A folder with no logo is drawn
    /// too, so "nothing extra" can be looked at.
    static func shoot(into dir: String, folders: [String]) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for folder in folders {
            let name = (repoRoot(of: folder) as NSString).lastPathComponent
            let logo = logo(forDirectory: folder)
            print("\(name): \(source(forDirectory: folder))")
            for (ground, colour) in [("dark", NSColor(white: 0.12, alpha: 1)), ("light", NSColor(white: 0.96, alpha: 1))] {
                let walkie = Glyphs.walkieOutlined(height: 19)
                let pad: CGFloat = 12, box: CGFloat = 20
                let logoW = logo.map { ($0.size.width * 19 / max($0.size.height, 1)).rounded() } ?? 0
                let width = pad * 2 + max(box, logoW)
                let height = pad * 2 + 21
                let scale: CGFloat = 8
                guard let rep = bitmap(Int(width * scale), Int(height * scale)) else { continue }
                rep.size = NSSize(width: width, height: height)
                draw(into: rep) {
                    colour.setFill()
                    NSRect(x: 0, y: 0, width: width, height: height).fill()
                    NSGraphicsContext.current?.imageInterpolation = .high
                    let walkieRect = NSRect(x: pad + ((box - walkie.size.width) / 2).rounded(),
                                            y: pad + ((21 - walkie.size.height) / 2).rounded(),
                                            width: walkie.size.width, height: walkie.size.height)
                    // As the chip places it: in the walkie's place, at its height and midline.
                    if let logo, logo.size.height > 0 {
                        let h = walkieRect.height
                        logo.draw(in: NSRect(x: pad + max(0, ((box - logoW) / 2).rounded()),
                                             y: walkieRect.midY - h / 2, width: logoW, height: h))
                    } else {
                        walkie.draw(in: walkieRect)
                    }
                }
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(ground).png"))
                }
            }
        }
    }
}
