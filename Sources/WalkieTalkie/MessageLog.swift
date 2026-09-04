import AppKit

/// **The outbox, read back as a page.**
///
/// `outbox.jsonl` is the record of everything Victor has dictated, and until now
/// the only way to read it was `tail`ing a file of one-line JSON blobs with
/// absolute paths to retina JPGs in them — i.e. a format written for the agent
/// watching the queue, not for the person who filled it. **Message Log** renders
/// the last two days of that same file as one self-contained HTML file and opens
/// it in the browser: the sentences in local time, grouped by day, with the
/// screenshots inline.
///
/// **Generated on demand, not maintained.** The page is a view of a file that is
/// appended to all day; keeping an HTML mirror in step with every send would be a
/// second writer on the hot path for something read once in a while. So the row
/// builds it at the moment it is clicked, which also makes "the last two days"
/// mean two days back from *now* rather than from whenever the file was last
/// rewritten.
///
/// It lands in Caches for the reason the shots do (see `Outbox.cacheRoot`): it is
/// derived, regenerable in a click, and nothing is lost when the system purges
/// it. The outbox itself stays in `~/.walkie-talkie` — that one is the log.
enum MessageLog {

    /// **Two days, counted back from the click.** Long enough to cover yesterday
    /// whatever hour it is now, short enough that the page stays a page rather
    /// than becoming the whole 600-line history with a megabyte of thumbnails.
    static let window: TimeInterval = 48 * 3600

    /// Beside the `shots` folder rather than inside it: `ScreenCapture.prune`
    /// walks that directory and counts what it finds, and an HTML file is not a
    /// shot.
    static var pageURL: URL {
        Outbox.cacheRoot.deletingLastPathComponent()
            .appendingPathComponent("message-log.html")
    }

    /// Build the page and hand it to the default browser. Returns where it went,
    /// for the loopback route and for the tests.
    @discardableResult
    static func openInBrowser() -> URL? {
        let url = pageURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(render(entries: recent()).utf8).write(to: url)
        } catch {
            Log.error("could not write the message log to \(url.path): \(error)")
            return nil
        }
        NSWorkspace.shared.open(url)
        Log.info("→ message log at \(url.path)")
        return url
    }

    // MARK: - Reading the queue

    /// One outbox line, as much of it as the page shows.
    struct Entry {
        var date: Date
        var text: String
        var app: String?
        var selection: String?
        var kind: String
        /// The envelope exactly as delivered (`AppDelegate.terminalLine`),
        /// stored in the outbox since 2026-09-04. What Copy puts on the
        /// clipboard; nil on older lines, where `payload` re-assembles it.
        var line: String?
        /// Deliberate shots first, then the automatic frame of the screen he was
        /// looking at — the same order of intent `Outbox.send` documents.
        var shots: [String]
        /// Shot base name → what was in front when it was taken.
        var sources: [String: String]
    }

    /// The last `window` seconds of the outbox, newest first.
    ///
    /// **A bad line is skipped, never thrown.** This file is appended to by a
    /// live process while this function reads it, it has survived every change
    /// of schema the app has been through, and one truncated tail line is not a
    /// reason to refuse to show the other five hundred.
    static func recent(now: Date = Date()) -> [Entry] {
        guard let data = try? Data(contentsOf: Outbox.outboxURL),
              let body = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = now.addingTimeInterval(-window)

        var entries: [Entry] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8)))
                    as? [String: Any],
                  let stamp = obj["ts"] as? String,
                  let date = parse(stamp),
                  date >= cutoff else { continue }

            let text = (obj["text"] as? String) ?? ""
            var shots = (obj["paths"] as? [String]) ?? []
            if let screen = obj["screen"] as? String { shots.append(screen) }
            // Nothing to show is not an entry: `session_start` / `session_end`
            // markers carry neither words nor pictures, and a page of empty rows
            // is what made the raw file unreadable in the first place.
            let selection = (obj["selection"] as? String)?.isEmpty == false
                ? (obj["selection"] as? String) : nil
            guard !text.isEmpty || !shots.isEmpty || selection != nil else { continue }

            entries.append(Entry(date: date,
                                 text: text,
                                 app: obj["app"] as? String,
                                 selection: selection,
                                 kind: (obj["kind"] as? String) ?? "",
                                 line: (obj["line"] as? String)?.isEmpty == false
                                     ? (obj["line"] as? String) : nil,
                                 shots: shots,
                                 sources: (obj["sources"] as? [String: String]) ?? [:]))
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// `ts` is written by `ISO8601DateFormatter()` with its default options, so
    /// this is the same reader in reverse — with the fractional-seconds variant
    /// tried too, since a line written by an older build may carry them.
    private static func parse(_ stamp: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: stamp) { return d }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: stamp)
    }

    // MARK: - Local time

    /// **The page is in Victor's own time zone, and the file is not.** `ts` is
    /// UTC, which is right for the queue and useless for the only question ever
    /// asked of this page — *when did I say that?* Three hours off in summer is
    /// enough to make yesterday evening look like today.
    private static let dayHeading: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - The page

    /// **One file, no network.** Inline CSS and no script at all: the page is
    /// opened off `file://`, where a CDN is a request that may or may not answer
    /// and a stylesheet that fails leaves the log unreadable. There is nothing
    /// here that needs JavaScript — the thumbnails are links.
    ///
    /// **Newest first, everywhere.** The reason the page is opened is almost
    /// always the sentence just said, so the day at the top is today and the row
    /// at the top of it is the last thing dictated. It costs the ability to read
    /// a session forwards, which is not what a log gets opened for.
    static func render(entries: [Entry], now: Date = Date()) -> String {
        var out = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Walkie Talkie — Message Log</title>
        <style>
        :root {
          color-scheme: light dark;
          --bg: #f6f6f7; --card: #ffffff; --ink: #1c1c1e; --dim: #6b6b70;
          --line: #e2e2e6; --accent: #d1471f; --quote: #f0f0f2;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #16161a; --card: #1f1f24; --ink: #e8e8ea; --dim: #96969c;
            --line: #2d2d33; --accent: #ff8a5c; --quote: #26262c;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0; padding: 28px 20px 64px;
          background: var(--bg); color: var(--ink);
          font: 14px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        }
        .wrap { max-width: 860px; margin: 0 auto; }
        h1 { font-size: 19px; margin: 0 0 4px; font-weight: 600; }
        .sub { color: var(--dim); font-size: 12px; margin-bottom: 26px; }
        h2 {
          font-size: 13px; text-transform: uppercase; letter-spacing: .08em;
          color: var(--dim); font-weight: 600;
          margin: 34px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--line);
        }
        .msg {
          background: var(--card); border: 1px solid var(--line); border-radius: 10px;
          padding: 12px 14px; margin-bottom: 10px;
        }
        .head { display: flex; gap: 10px; align-items: baseline; flex-wrap: wrap; margin-bottom: 6px; }
        .time { font-variant-numeric: tabular-nums; color: var(--accent); font-weight: 600; }
        .app, .kind { color: var(--dim); font-size: 12px; }
        .text { white-space: pre-wrap; word-wrap: break-word; }
        .label { color: var(--dim); font-size: 11px; text-transform: uppercase; letter-spacing: .06em; margin: 10px 0 4px; }
        .sel {
          white-space: pre-wrap; word-wrap: break-word;
          background: var(--quote); border-left: 3px solid var(--line);
          padding: 7px 10px; border-radius: 0 6px 6px 0;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px;
        }
        .shots { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; }
        .shot { max-width: 260px; }
        .shot img {
          max-width: 100%; display: block; border-radius: 6px; border: 1px solid var(--line);
        }
        .shot .cap { color: var(--dim); font-size: 11px; margin-top: 3px; word-break: break-all; }
        .gone {
          color: var(--dim); font-size: 12px; font-style: italic;
          border: 1px dashed var(--line); border-radius: 6px; padding: 8px 10px;
        }
        .empty { color: var(--dim); }
        /* The copy button. `margin-left: auto` is what puts it at the right edge
           of a head row whose other items are sized by their own text. */
        .copy {
          margin-left: auto; display: inline-flex; align-items: center; gap: 5px;
          font: inherit; font-size: 12px; color: var(--dim);
          background: var(--bg); border: 1px solid var(--line); border-radius: 6px;
          padding: 3px 8px; cursor: pointer; line-height: 1;
        }
        .copy:hover { color: var(--ink); border-color: var(--dim); }
        .copy.ok { color: var(--accent); border-color: var(--accent); }
        .copy svg { width: 13px; height: 13px; flex: none; }
        .payload { display: none; }
        </style>
        <div class="wrap">
        """

        out += "<h1>Message Log</h1>\n"
        out += "<div class=\"sub\">The last 2 days of <code>~/.walkie-talkie/outbox.jsonl</code>"
        out += " — newest first, in local time. Generated \(esc(clock.string(from: now)))"
        out += " on \(esc(dayHeading.string(from: now))).</div>\n"

        if entries.isEmpty {
            out += """
            <p class="empty">Nothing in the last 2 days — no dictation reached the
            outbox in that window, or <code>outbox.jsonl</code> is not there yet.</p>
            """
        }

        var currentDay = ""
        for entry in entries {
            let day = dayKey.string(from: entry.date)
            if day != currentDay {
                currentDay = day
                out += "<h2>\(esc(dayHeading.string(from: entry.date)))</h2>\n"
            }
            out += renderEntry(entry)
        }

        out += "</div>\n"
        out += copyScript + "\n"
        return out
    }

    private static func renderEntry(_ entry: Entry) -> String {
        var out = "<div class=\"msg\">\n<div class=\"head\">"
        out += "<span class=\"time\">\(esc(clock.string(from: entry.date)))</span>"
        if let app = entry.app, !app.isEmpty {
            out += "<span class=\"app\">\(esc(app))</span>"
        }
        if !entry.kind.isEmpty, entry.kind != "dictation" {
            out += "<span class=\"kind\">\(esc(entry.kind))</span>"
        }
        // **The copy button, and the whole message behind it.** The page is read
        // to *find* a sentence, and what happens next is that it is pasted
        // somewhere — which until now meant a drag-select across a card that also
        // holds a timestamp, an app name and a block quote. Victor's ask,
        // 2026-09-04: *"there should be a copy icon, visible, that would allow to
        // copy the whole text for easy pasting"*.
        out += "<button class=\"copy\" type=\"button\" title=\"Copy this message\">"
        out += copyGlyph + "<span class=\"lbl\">Copy</span></button>"
        out += "</div>\n"
        // The payload rides in a hidden element rather than in a `data-`
        // attribute, so that `esc` is enough: an attribute would also need its
        // quotes escaped, and a dictation is arbitrary text.
        out += "<pre class=\"payload\">\(esc(payload(entry)))</pre>\n"

        if !entry.text.isEmpty {
            out += "<div class=\"text\">\(esc(entry.text))</div>\n"
        }
        if let selection = entry.selection {
            out += "<div class=\"label\">Selection</div>\n"
            out += "<div class=\"sel\">\(esc(selection))</div>\n"
        }

        // **The pictures are checked, one `stat` each, at generation time.**
        // They live in Caches, which macOS purges under disk pressure and every
        // cleaner tool empties — so a page built from lines two days old will
        // routinely name frames that are gone. A broken-image box says nothing
        // about why; a line saying the shot was cleaned out says all of it.
        if !entry.shots.isEmpty {
            out += "<div class=\"shots\">\n"
            for path in entry.shots {
                let name = (path as NSString).lastPathComponent
                let caption = entry.sources[name] ?? name
                if FileManager.default.fileExists(atPath: path) {
                    let href = URL(fileURLWithPath: path).absoluteString
                    out += "<div class=\"shot\"><a href=\"\(esc(href))\">"
                    out += "<img src=\"\(esc(href))\" alt=\"\(esc(caption))\" loading=\"lazy\"></a>"
                    out += "<div class=\"cap\">\(esc(caption))</div></div>\n"
                } else {
                    out += "<div class=\"shot\"><div class=\"gone\">🗑️ \(esc(caption))"
                    out += " — the frame is no longer on disk</div></div>\n"
                }
            }
            out += "</div>\n"
        }

        out += "</div>\n"
        return out
    }

    /// **What Copy puts on the clipboard: the exact prompt ⌘⌃P would paste.**
    ///
    /// Since 2026-09-04 the outbox carries the delivered envelope itself (`line`),
    /// written by `commit` from the same `terminalLine` call the delivery made —
    /// so a copied message is byte for byte what the session received: the words,
    /// the dictated-aloud hint, every quoted selection, the focused window, the
    /// frames' paths with what was in front of each, and the picked elements.
    ///
    /// Lines older than that have no `line`, so the parts are re-assembled here
    /// in the shapes that line uses — close, but not the same string: the clamps
    /// and the hint are the reconstruction's own.
    private static func payload(_ entry: Entry) -> String {
        if let line = entry.line { return line }
        var parts: [String] = []
        if !entry.text.isEmpty { parts.append(entry.text) }
        if let selection = entry.selection, !selection.isEmpty {
            parts.append("[selected: \(selection)]")
        }
        if !entry.shots.isEmpty {
            let listed = entry.shots.map { path -> String in
                let name = (path as NSString).lastPathComponent
                if let source = entry.sources[name] { return "\(path) = \(source)" }
                return path
            }
            parts.append("[the shots I took:\n \(listed.joined(separator: ";\n "))]")
        }
        return parts.joined(separator: "\n\n")
    }

    /// A clipboard, drawn rather than an emoji: 📋 renders at whatever size and
    /// colour Apple Color Emoji feels like, and this one has to sit on a 12px
    /// line beside a word and take the button's own ink in both palettes.
    private static let copyGlyph = """
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" \
    stroke-linejoin="round" aria-hidden="true"><rect x="5.2" y="5.2" width="8.3" \
    height="9.3" rx="1.6"/><path d="M10.8 5.2V3.1a1.6 1.6 0 0 0-1.6-1.6H4.1a1.6 \
    1.6 0 0 0-1.6 1.6v6.2a1.6 1.6 0 0 0 1.6 1.6h1.1"/></svg>
    """

    /// **The one script on the page, and the rule it bends.** Everything else
    /// here is deliberately static — no CDN, no framework — because the page is
    /// opened off `file://`, where a request that does not answer leaves the log
    /// unreadable. That argument is about the *network*, and this is a dozen
    /// lines inline: nothing is fetched, and with JavaScript off the page still
    /// shows every message, minus a button.
    ///
    /// **Delegated from `document`** rather than bound per card — there are
    /// hundreds of these across a busy two days.
    ///
    /// **`execCommand` is the fallback and is not vestigial.** The Clipboard API
    /// needs a secure context; a `file://` page is one in Chrome and is not
    /// guaranteed to be in every browser this might be opened in. The old
    /// select-and-copy trick has no such requirement.
    private static let copyScript = """
    <script>
    document.addEventListener('click', function (event) {
      var button = event.target.closest('.copy');
      if (!button) return;
      var card = button.closest('.msg');
      var payload = card ? card.querySelector('.payload') : null;
      var text = payload ? payload.textContent : '';
      var label = button.querySelector('.lbl');
      function done() {
        button.classList.add('ok');
        label.textContent = 'Copied';
        setTimeout(function () {
          button.classList.remove('ok');
          label.textContent = 'Copy';
        }, 1300);
      }
      function legacy() {
        var box = document.createElement('textarea');
        box.value = text;
        box.setAttribute('readonly', '');
        box.style.position = 'fixed';
        box.style.opacity = '0';
        document.body.appendChild(box);
        box.select();
        try { document.execCommand('copy'); done(); } catch (error) { /* nothing left to try */ }
        document.body.removeChild(box);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, legacy);
      } else {
        legacy();
      }
    });
    </script>
    """

    /// Dictation is arbitrary text and so is a screen selection — the same reason
    /// `Outbox.send` never interpolates JSON. `&` goes first or it re-escapes the
    /// entities the other four produce.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
