import AppKit

/// **What this app is, and where its code lives.**
///
/// The one fact about the relay that is nowhere on the machine it runs on: it is
/// installed as a bundle in `/Applications`, launched at login, and has no
/// window of its own — so somebody looking at the walkie-talkie in the menu bar
/// and wondering what it is, or wanting to read the source, has nothing to
/// follow. The About row answers that with the repository URL.
///
/// **A page in the browser rather than an `NSAlert`**, for the reason the message
/// log is one: the app is `.accessory` and never becomes key, so a modal it puts
/// up arrives behind whatever is in front and steals focus from the terminal
/// Victor is bound to. A page is also the only rendering where the GitHub link
/// is a link — which is the whole point of the row.
enum AboutPage {

    /// Beside the message log, and derived in the same way — regenerated on every
    /// click, and nothing is lost when the system purges the cache.
    static var pageURL: URL {
        Outbox.cacheRoot.deletingLastPathComponent()
            .appendingPathComponent("about.html")
    }

    static let repository = "https://github.com/victorrentea/walkie-talkie"

    /// When the running binary was built — the same stamp the menu row carries,
    /// so the page and the row cannot disagree about which build this is.
    static var buildStamp: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date ?? Date())
    }

    @discardableResult
    static func openInBrowser() -> URL? {
        let url = pageURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(render().utf8).write(to: url)
        } catch {
            Log.error("could not write the about page to \(url.path): \(error)")
            return nil
        }
        NSWorkspace.shared.open(url)
        Log.info("→ about page at \(url.path)")
        return url
    }

    static func render() -> String {
        """
        <!doctype html>
        <meta charset="utf-8">
        <title>Victor's Walkie Talkie</title>
        <style>
          :root { color-scheme: light dark; }
          body {
            margin: 0; min-height: 100vh;
            display: flex; align-items: center; justify-content: center;
            font: 15px/1.6 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
          }
          .card { max-width: 34rem; padding: 2.5rem 3rem; text-align: center; }
          h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
          .build { opacity: .6; font-size: .85rem; margin: 0 0 1.5rem; }
          p { margin: 0 0 1rem; }
          a { color: #0a84ff; }
          code { font-size: .9em; }
        </style>
        <div class="card">
          <h1>🎙️ Victor's Walkie Talkie</h1>
          <p class="build">built \(buildStamp)</p>
          <p>A macOS menu-bar relay: dictate with the mouse wheel, and the words
             land in the Claude Code session it is pointed at.</p>
          <p>Source code:<br><a href="\(repository)">\(repository)</a></p>
        </div>
        """
    }
}
