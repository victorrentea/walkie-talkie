import AppKit

/// **A project's own mark in front of its name on the spawn menu, ✨ for the rest**
/// (2026-11-19, Victor: *"for Walkie Talkie, you can put the icon of the application
/// from the menu bar. VictorNet should have the icon of the GSM thing. VS Code should
/// have the icon of the VS Code thingy. Petclinic should have the face of a cat. Human
/// review, the logo of the favicon in the browser. Gmail dark CSS … the Gmail logo.
/// Insomnia should have the coffee icon … The rest remain with stars"*).
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
