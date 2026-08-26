import AppKit
import ApplicationServices

/// What was in front when a picture was taken: the app, and what its window
/// says it is showing.
///
/// A screenshot arrives at an agent as a rectangle of pixels with no provenance.
/// Everything in the frame has to be re-derived by looking at it — that this is
/// a browser, that the browser is on Gmail, that the editor behind it has
/// `OwnerController.java` open. All of that is already written down, by the app
/// itself, in its window title, and reading it costs one Accessibility call
/// against the several hundred tokens of looking.
///
/// It also answers the question the pixels answer *worst*. Two frames of the
/// same IDE at the same zoom are near-identical to look at and are two different
/// files; `IntelliJ IDEA — OwnerController.java` and `IntelliJ IDEA —
/// OwnerRepository.java` tell them apart before either is opened.
///
/// The three cases Victor named are all one mechanism, which is why it is worth
/// having only one: Chrome puts the **page title** in its window title, both
/// IDEs put the **project and the open file** in theirs, and a terminal puts
/// whatever the shell or the agent last set — the same `custom title` the chip
/// already reads when the relay is bound to one.
enum WindowContext {

    /// `Chrome — Gmail – Inbox (24,277)`, or just `Preview` when the window has
    /// no title to give.
    ///
    /// **Sampled at the gesture**, never inside the capture — the same rule the
    /// cursor position and the dictation offset already follow, and for the same
    /// reason: `screencapture` is a subprocess we wait on, and by the time it
    /// returns Victor has moved on to whatever he is talking about next. A title
    /// read afterwards would name the window he *ended up* in front of.
    static func describe() -> String? {
        guard let app = frontmostApp() else { return nil }
        let name = app.localizedName ?? "unknown app"
        guard let title = focusedWindowTitle(pid: app.processIdentifier), !title.isEmpty else {
            return name
        }
        let trimmed = withoutAppName(title, app: name)
        // Titles run long — a Chrome tab carries the whole headline, an IDE the
        // whole path. Truncated from the **head**, like the bound terminal's
        // title and unlike a CSS selector: a title puts its subject first.
        let clamped = trimmed.count <= titleLimit ? trimmed : String(trimmed.prefix(titleLimit)) + "…"
        return "\(name) — \(clamped)"
    }

    /// Drop the app's own name where the window title repeats it.
    ///
    /// Chrome titles its window `Netflix - Google Chrome – Victor (Vic)`, so the
    /// unedited reading comes out
    /// `Google Chrome — Netflix - Google Chrome – Victor (Vic)`: the app is
    /// named twice and the profile is named once, and the only word an agent
    /// needed was *Netflix*. Cutting from the app's name takes the profile with
    /// it, which is the right call — which Chrome profile a tab was open in has
    /// never been the subject of a sentence Victor dictated.
    ///
    /// Matched on the separator too (` - ` / ` – `, hyphen and en dash, since
    /// Chrome uses both in one title) rather than on a bare substring: a page
    /// genuinely *about* Google Chrome should keep its headline.
    private static func withoutAppName(_ title: String, app: String) -> String {
        for separator in [" - ", " – ", " — "] {
            guard let cut = title.range(of: separator + app) else { continue }
            let head = String(title[title.startIndex..<cut.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            // A title that is *only* the app name keeps it — `Preview — Preview`
            // is silly, but an empty right-hand side is worse.
            if !head.isEmpty { return head }
        }
        return title
    }

    private static let titleLimit = 80

    /// `NSWorkspace` is a main-thread question and the callers are not on the
    /// main thread — they are an event tap, a CoreAudio callback and an HTTP
    /// listener. `sync` from the main thread would deadlock, so the one case
    /// that cannot happen is still checked for, because a deadlock in the
    /// shutter path is not a bug anyone would enjoy finding later.
    private static func frontmostApp() -> NSRunningApplication? {
        if Thread.isMainThread { return NSWorkspace.shared.frontmostApplication }
        var app: NSRunningApplication?
        DispatchQueue.main.sync { app = NSWorkspace.shared.frontmostApplication }
        return app
    }

    /// The same read `TerminalBinding.focusedWindow` makes, without the geometry
    /// it also wants. Duplicated rather than shared because that one is about
    /// *binding* — it resolves a target and answers with a frame to fly a
    /// rectangle from — and folding a screenshot's provenance into it would tie
    /// two unrelated features to one signature.
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeBitCast(window, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String
        else { return nil }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
