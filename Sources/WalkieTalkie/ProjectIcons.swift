import AppKit

/// **A project's own mark in front of its name on the spawn menu, ✨ for the rest**
/// (2026-11-19, Victor: *"for Walkie Talkie, you can put the icon of the application
/// from the menu bar. VictorNet should have the icon of the GSM thing. VS Code should
/// have the icon of the VS Code thingy. Petclinic should have the face of a cat. Human
/// review, the logo of the favicon in the browser. Gmail dark CSS … the Gmail logo.
/// Insomnia should have the coffee icon … The rest remain with stars"*). Victor
/// Addons and Victor Effects joined the same evening, with their app icons.
///
/// Keyed by folder name, so a project is recognised in the pinned list and in
/// *Workspace ›* alike. Each mark is the one he already knows the project by: the
/// menu-bar glyph of an app of his, the favicon of a page, the logo of the app it
/// customises. A mark is drawn in the slot the "✨ " takes, so the menu's
/// measurement is unchanged and the names stay in one column.
enum ProjectIcons {

    enum Mark {
        /// A monochrome glyph, painted in the row's ink (white on the highlight).
        case template(NSImage)
        /// Drawn in its own colours.
        case colour(NSImage)
    }

    static func mark(for folder: String) -> Mark? {
        if let hit = cache[folder] { return hit }
        let made = make(folder)
        cache[folder] = made
        return made
    }

    private static var cache: [String: Mark?] = [:]

    private static func make(_ folder: String) -> Mark? {
        // Every live checkout of petclinic (`petclinic-main`, `petclinic-pr-…`) is petclinic.
        if folder == "petclinic" || folder.hasPrefix("petclinic-") { return .colour(Glyphs.emoji("🐱", ink: 18)) }
        switch folder {
        // Walkie's own menu-bar glyph (`StatusItem.boundIcon`).
        case "walkie-talkie": return .template(Glyphs.walkie(height: 18))
        // Victor Net's menu-bar item is a phone's signal bars.
        case "victor-net": return symbol("cellularbars")
        // Insomnia's menu-bar cup (`InsomniaIcon.cup`).
        case "victor-insomnia": return symbol("cup.and.saucer.fill")
        case "victor-vsc": return app("com.microsoft.VSCode")
        // Victor's own two menu-bar apps wore their Dock icons for an hour, then
        // went bare and larger (2026-11-19, Victor: *"without the blue background
        // and larger to fit as much space as you can … the same with no background
        // behind"*): their menu-bar marks, drawn here in the row's ink and filling
        // the slot (`fillsSlot`) — the V in a ring and the 𝓯𝔁. Drawn, so this
        // public repo carries neither picture.
        // The very PNG the Addons menu bar draws, read from the sibling checkout
        // (Victor: *"exactly the V from the menu bar"*); drawn here if it is missing.
        case "victor-macos-addons":
            let png = NSHomeDirectory() + "/workspace/victor-macos-addons/Sources/VictorAddons/Resources/icon_v.png"
            if let logo = NSImage(contentsOfFile: png) {
                logo.isTemplate = true
                return .template(logo)
            }
            return .template(vInCircle(side: 24))
        case "victor-effects":
            let fx = Glyphs.emoji("𝓯𝔁", ink: 24, colour: .black)
            fx.isTemplate = true
            return .template(fx)
        // The participant page's favicon (`static/favicon-new.svg`, the mortarboard).
        case "training-assistant": return .colour(Glyphs.emoji("🎓", ink: 18))
        // The review page's favicon (`human-review` `masthead.py`, `FAVICON_EMOJI`).
        case "human-review": return .colour(Glyphs.emoji("👱🏻‍♂️", ink: 18))
        // The Gmail logo (`assets/gmail-logo.png`, the one Victor Addons draws), else Chrome's.
        case "gmail-dark-css":
            if let url = RelayWindow.walkieURL("gmail-logo"), let image = NSImage(contentsOf: url) {
                return .colour(image)
            }
            return app("com.google.Chrome")
        default: return nil
        }
    }

    /// The marks that are the whole picture — no tile, no margin of their own — and
    /// so take the slot's full height rather than `markSize`.
    static func fillsSlot(_ folder: String) -> Bool {
        folder == "victor-macos-addons" || folder == "victor-effects"
    }

    /// Victor Addons' menu-bar logo (`icon_v.png` there, a V in a ring), drawn —
    /// the fallback when the sibling checkout is not on disk.
    private static func vInCircle(side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            let ring = r.width * 0.09
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: ring / 2, dy: ring / 2))
            circle.lineWidth = ring
            NSColor.black.setStroke()
            circle.stroke()
            let v = NSBezierPath()
            v.move(to: NSPoint(x: r.width * 0.33, y: r.height * 0.71))
            v.line(to: NSPoint(x: r.width * 0.50, y: r.height * 0.29))
            v.line(to: NSPoint(x: r.width * 0.67, y: r.height * 0.71))
            v.lineWidth = r.width * 0.12
            v.lineCapStyle = .round
            v.lineJoinStyle = .round
            v.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func symbol(_ name: String) -> Mark? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular)) else { return nil }
        image.isTemplate = true
        return .template(image)
    }

    private static func app(_ bundleID: String) -> Mark? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return .colour(NSWorkspace.shared.icon(forFile: url.path))
    }

    /// Fitted (aspect kept) and centred in `box`; a template one painted in `ink`.
    static func draw(_ mark: Mark, in box: NSRect, ink: NSColor) {
        switch mark {
        case .colour(let image):
            image.draw(in: fit(image.size, in: box))
        case .template(let image):
            let rect = fit(image.size, in: box)
            let tinted = NSImage(size: rect.size, flipped: false) { r in
                image.draw(in: r)
                ink.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        }
    }

    static func fit(_ size: NSSize, in box: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return box }
        let k = min(box.width / size.width, box.height / size.height)
        let w = size.width * k, h = size.height * k
        return NSRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }
}
