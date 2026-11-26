import AppKit
import ImageIO

/// **The outbox, read back as a page.**
///
/// `outbox.jsonl` is the record of everything Victor has dictated, and until now
/// the only way to read it was `tail`ing a file of one-line JSON blobs with
/// absolute paths to retina JPGs in them — i.e. a format written for the agent
/// watching the queue, not for the person who filled it. **Prompt Log** renders
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

    /// Build the page and hand it to the default browser — **off the main
    /// thread** since 2026-11-25: the terminals' current titles are one
    /// `osascript` (~0.5 s), the fallback name for a row sent before the outbox
    /// recorded the title.
    static func openInBrowser() {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = pageURL
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let titles = TerminalBinding.liveTitles()
                    .merging(OrcaBridge.liveTitles()) { terminal, _ in terminal }
                try Data(render(entries: recent(), titles: titles).utf8).write(to: url)
            } catch {
                Log.error("could not write the message log to \(url.path): \(error)")
                return
            }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            Log.info("→ message log at \(url.path)")
        }
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
        /// **A prompt that reached nobody** (2026-11-22, `AppDelegate.keepUndelivered`):
        /// where it was going (`terminal:ttys004`, `spawn:<folder>`), from the
        /// row's `delivery {to: "undelivered", wanted}`. Nil for a delivered one.
        /// The page marks it `not delivered`, so the row is not read as a receipt.
        var undelivered: String? = nil
        /// `delivery.to` — `terminal:ttys004`, `spawn:<folder>`, an IDE's name.
        var to: String? = nil
        /// `delivery.title`: the terminal tab's title when it was sent
        /// (`Outbox.stampTitle`, since 2026-11-25). Nil on older rows.
        var title: String? = nil
    }

    /// The last `window` seconds of the outbox, newest first.
    ///
    /// **A bad line is skipped, never thrown.** This file is appended to by a
    /// live process while this function reads it, it has survived every change
    /// of schema the app has been through, and one truncated tail line is not a
    /// reason to refuse to show the other five hundred.
    ///
    /// **Read from the end, and stopped well past the cutoff** (2026-11-25, the
    /// Fable review): every line since August was JSON-parsed before the 48 h
    /// filter — 446 ms for 5,681 lines on main, at every open of Prompt History,
    /// growing for ever. The file is appended in time order; the walk stops at
    /// the first line older than `cutoff − readSlack`, so a line written a little
    /// out of order near the edge is still seen.
    static func recent(now: Date = Date()) -> [Entry] {
        guard let data = try? Data(contentsOf: Outbox.outboxURL),
              let body = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = now.addingTimeInterval(-window)
        let stopAt = cutoff.addingTimeInterval(-readSlack)

        var entries: [Entry] = []
        // ⏸ A row written when a prompt started waiting for a question (`delivery.held`,
        // 2026-11-25) is superseded by the later row of the same envelope — newest first,
        // so that one has been seen already. Kept only when nothing followed it (a crash).
        var later = Set<String>()
        for line in body.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8)))
                    as? [String: Any],
                  let stamp = obj["ts"] as? String,
                  let date = parse(stamp) else { continue }
            if date < stopAt { break }
            guard date >= cutoff else { continue }

            let text = (obj["text"] as? String) ?? ""
            var shots = (obj["paths"] as? [String]) ?? []
            if let screen = obj["screen"] as? String { shots.append(screen) }
            // Nothing to show is not an entry: `session_start` / `session_end`
            // markers carry neither words nor pictures, and a page of empty rows
            // is what made the raw file unreadable in the first place.
            let selection = (obj["selection"] as? String)?.isEmpty == false
                ? (obj["selection"] as? String) : nil
            guard !text.isEmpty || !shots.isEmpty || selection != nil else { continue }

            let delivery = obj["delivery"] as? [String: Any]
            let envelope = (obj["line"] as? String) ?? ""
            if delivery?["held"] as? Bool == true, later.contains(envelope) { continue }
            later.insert(envelope)
            entries.append(Entry(date: date,
                                 text: text,
                                 app: obj["app"] as? String,
                                 selection: selection,
                                 kind: (obj["kind"] as? String) ?? "",
                                 line: (obj["line"] as? String)?.isEmpty == false
                                     ? (obj["line"] as? String) : nil,
                                 shots: shots,
                                 sources: (obj["sources"] as? [String: String]) ?? [:],
                                 undelivered: undelivered(delivery),
                                 to: delivery?["to"] as? String,
                                 title: (delivery?["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// The `wanted` of an `undelivered` delivery record (an empty string when it
    /// names none), nil for every other row.
    static func undelivered(_ delivery: [String: Any]?) -> String? {
        guard let delivery, delivery["to"] as? String == BoundPromptGate.undeliveredTo else { return nil }
        return (delivery["wanted"] as? String) ?? ""
    }

    /// `ts` is written by `ISO8601DateFormatter()` with its default options, so
    /// this is the same reader in reverse — with the fractional-seconds variant
    /// tried too, since a line written by an older build may carry them.
    private static func parse(_ stamp: String) -> Date? {
        if let d = plainStamp.date(from: stamp) { return d }
        return fractionalStamp.date(from: stamp)
    }
    /// Built once, not twice per line (`ISO8601DateFormatter` is thread-safe).
    private static let plainStamp = ISO8601DateFormatter()
    private static let fractionalStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    /// How far past the cutoff `recent` still reads before it trusts the order.
    static let readSlack: TimeInterval = 3600

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
    static func render(entries: [Entry], now: Date = Date(), titles: [String: String] = [:]) -> String {
        var out = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Walkie Talkie — Prompt Log</title>
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
        /* 2026-11-25: the prompt read as he made it — pictures where he took
           them, an area lit on its screen, a highlight as a quote. */
        .to { font-size: 12px; background: var(--quote); border-radius: 6px; padding: 1px 8px;
              max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .to small { color: var(--dim); font-size: 10px; margin-left: 4px; }
        .fig { display: inline-flex; flex-direction: column; vertical-align: top; margin: 6px 6px 4px 0;
               text-decoration: none; color: inherit; max-width: 100%; white-space: normal; }
        .fig img, .fig svg { display: block; border-radius: 6px; border: 1px solid var(--line); max-width: 100%; height: auto; }
        .fig.shot img { width: 280px; }
        .fig.auto img { width: 150px; }
        .fig .cap { color: var(--dim); font-size: 11px; margin-top: 3px; max-width: 280px;
                    overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        /* A picture is a row of its own: words wrapped beside a 380 px screen read as
           two columns of one sentence. */
        .text > .fig, .text > .area { display: flex; width: fit-content; }
        .area { display: inline-flex; gap: 8px; flex-wrap: wrap; align-items: flex-start;
                vertical-align: top; margin: 6px 6px 4px 0; max-width: 100%; white-space: normal; }
        .area .fig { margin: 0; }
        .area .ctx svg { width: 380px; }
        .area .cut img { max-height: 214px; max-width: 280px; width: auto; }
        .q { background: var(--quote); border-left: 3px solid var(--accent); border-radius: 0 4px 4px 0;
             padding: 1px 6px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12.5px; }
        .q .from { color: var(--dim); font-family: -apple-system, sans-serif; font-size: 11px; margin-left: 6px; }
        .chip { display: inline-block; font-size: 11.5px; color: var(--dim); border: 1px solid var(--line);
                border-radius: 999px; padding: 0 7px; margin: 0 2px; white-space: nowrap; }
        .meta { display: flex; gap: 6px; flex-wrap: wrap; align-items: center; margin-top: 10px; }
        .meta a { color: var(--dim); font-size: 11.5px; }
        .films { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; }
        .film { display: flex; flex-direction: column; max-width: 100%; }
        .film video { width: 480px; max-width: 100%; border-radius: 6px; border: 1px solid var(--line); background: #000; }
        .film .cap { color: var(--dim); font-size: 11px; margin-top: 3px; }
        </style>
        <div class="wrap">
        """

        out += "<h1>Prompt Log</h1>\n"
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
            out += renderEntry(entry, titles: titles)
        }

        out += "</div>\n"
        out += copyScript + "\n"
        return out
    }

    /// **One card, read the way he made it** (2026-11-25, Victor: *"pune inline în
    /// prompturile astea pozele + dacă mut să văd roșu-verde chenar. să fie un
    /// human-readable view … filmele să apară și ele. și cropul să apară selecția
    /// și de unde (similar cu panelul de preview prompt) … și zi și cărei sesiune
    /// trimiteai (titlul sesiunii)"*).
    ///
    /// The delivered envelope (`line`) is the source, not `text`: it is the only
    /// field that has every token where he made it *and* the footer that says
    /// where the films are. Each `[📸n]` becomes its picture in the sentence; an
    /// area `[📸n✂️…]` its cut-out beside the whole screen greyed outside the box
    /// — red, and green for the `moved to` box with the arrow between, the
    /// colours of `AreaContext`, the prompt panel's drawing; a highlight a quote.
    /// The footer rows become films and a line of small chips. A row from before
    /// `line` existed renders its `text` and its frames below, as it always did.
    private static func renderEntry(_ entry: Entry, titles: [String: String]) -> String {
        var out = "<div class=\"msg\">\n<div class=\"head\">"
        out += "<span class=\"time\">\(esc(clock.string(from: entry.date)))</span>"
        if let app = entry.app, !app.isEmpty {
            out += "<span class=\"app\">\(esc(app))</span>"
        }
        if !entry.kind.isEmpty, entry.kind != "dictation" {
            out += "<span class=\"kind\">\(esc(entry.kind))</span>"
        }
        if let wanted = entry.undelivered {
            out += "<span class=\"kind\">not delivered\(wanted.isEmpty ? "" : " — was for \(esc(wanted))")</span>"
        } else if let to = destination(entry, titles: titles) {
            out += to
        }
        // **The copy button, and the whole message behind it.** Victor's ask,
        // 2026-09-04: *"there should be a copy icon, visible, that would allow to
        // copy the whole text for easy pasting"*.
        out += "<button class=\"copy\" type=\"button\" title=\"Copy the prompt as it was sent, with the files' paths\">"
        out += copyGlyph + "<span class=\"lbl\">Copy</span></button>"
        out += "</div>\n"
        // The payload rides in a hidden element rather than in a `data-`
        // attribute, so that `esc` is enough.
        out += "<pre class=\"payload\">\(esc(copyText(entry)))</pre>\n"

        let shots = Shots(entry)
        var used = Set<Int>()
        let (body, meta) = entry.line.map(split) ?? (entry.text, [])
        if !body.isEmpty {
            out += "<div class=\"text\">"
            // A picture is a row of its own, so the line break the envelope put
            // on either side of it would be a blank line here.
            var afterPicture = false
            for piece in tokenize(body) {
                switch piece {
                case .text(var s):
                    if afterPicture, s.hasPrefix("\n") { s.removeFirst() }
                    out += esc(s)
                    afterPicture = false
                case .token(let t):
                    if out.hasSuffix("\n") { out.removeLast() }
                    out += renderToken(t, shots: shots, used: &used)
                    afterPicture = t.hasPrefix("📸")
                }
            }
            out += "</div>\n"
        }
        if let selection = entry.selection, !(entry.line ?? "").contains("[selected:") {
            out += "<div class=\"label\">Selection</div>\n"
            out += "<div class=\"sel\">\(esc(selection))</div>\n"
        }

        // **Frames no token placed** (a row from before `line`, or one the words
        // could not carry) still show, after the words. Pictures are `stat`ed
        // here: they live in Caches, which macOS purges, and a broken-image box
        // says nothing about why.
        let leftovers = entry.shots.filter { path in
            shotIndex(path).map { !used.contains($0) } ?? true
        }
        if !leftovers.isEmpty {
            out += "<div class=\"shots\">\n"
            for path in leftovers {
                let name = (path as NSString).lastPathComponent
                let caption = entry.sources[name] ?? name
                if FileManager.default.fileExists(atPath: path) {
                    let href = URL(fileURLWithPath: path).absoluteString
                    out += "<a class=\"fig shot\" href=\"\(esc(href))\" target=\"_blank\">"
                    out += "<img src=\"\(esc(href))\" alt=\"\(esc(caption))\" loading=\"lazy\">"
                    out += "<span class=\"cap\" title=\"\(esc(caption))\">\(esc(caption))</span></a>\n"
                } else {
                    out += "<div class=\"shot\"><div class=\"gone\">🗑️ \(esc(caption))"
                    out += " — the frame is no longer on disk</div></div>\n"
                }
            }
            out += "</div>\n"
        }

        let films = meta.compactMap(film)
        if !films.isEmpty {
            out += "<div class=\"films\">\n" + films.joined(separator: "\n") + "\n</div>\n"
        }
        let chips = meta.compactMap { metaChip($0, shots: shots) }
        if !chips.isEmpty {
            out += "<div class=\"meta\">" + chips.joined() + "</div>\n"
        }
        out += "</div>\n"
        return out
    }

    // MARK: - Reading the envelope back

    /// The words and inline tokens, and the footer's rows apart. A row is footer
    /// when it is nothing but bracket tokens that describe the message rather
    /// than sit in it — the hint, `📁`, `🎦`, the frames' legend, the face.
    static func split(_ line: String) -> (body: String, meta: [String]) {
        var body: [String] = []
        var meta: [String] = []
        for row in line.components(separatedBy: "\n") {
            let pieces = tokenize(row.trimmingCharacters(in: .whitespaces))
            let tokens = pieces.compactMap { piece -> String? in
                if case .token(let t) = piece { return t }
                return nil
            }
            let onlyTokens = pieces.allSatisfy { piece in
                if case .text(let s) = piece { return s.trimmingCharacters(in: .whitespaces).isEmpty }
                return true
            }
            if !tokens.isEmpty, onlyTokens, tokens.allSatisfy(isMeta) {
                meta += tokens
            } else {
                body.append(row)
            }
        }
        while body.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeFirst() }
        while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
        return (body.joined(separator: "\n"), meta)
    }

    static func isMeta(_ token: String) -> Bool {
        let prefixes = ["dictated", "Dictated", "Transcribed", "📁=", "🎦", "face:", "--image",
                        "the shots I took", "If I asked", "a question →", "Focused window"]
        if prefixes.contains(where: token.hasPrefix) { return true }
        // The frames' legend: `[📸0 = 📁/…]`, `[📸1✂️ = user-selected area …]`.
        return token.hasPrefix("📸") && token.contains(" = ")
    }

    enum Piece: Equatable { case text(String), token(String) }

    /// Text and `[…]` tokens, in order. Only brackets that look like the
    /// envelope's own are tokens — `array[0]` said aloud stays words.
    static func tokenize(_ s: String) -> [Piece] {
        var pieces: [Piece] = []
        var buffer = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "[", let close = tokenEnd(s, open: i) {
                let inner = String(s[s.index(after: i)..<close])
                if !buffer.isEmpty { pieces.append(.text(buffer)); buffer = "" }
                pieces.append(.token(inner))
                i = s.index(after: close)
            } else {
                buffer.append(s[i])
                i = s.index(after: i)
            }
        }
        if !buffer.isEmpty { pieces.append(.text(buffer)) }
        return pieces
    }

    /// The `]` that closes the token opened at `open`, or nil when it is not one.
    /// A quoted highlight may hold brackets of its own, so it ends at `"]` or at
    /// `" from app …]`, whichever comes first.
    private static func tokenEnd(_ s: String, open: String.Index) -> String.Index? {
        let rest = s[s.index(after: open)...]
        for prefix in ["selected: \"", "copied: \"", "typed: \""] where rest.hasPrefix(prefix) {
            let tail = s[rest.index(rest.startIndex, offsetBy: prefix.count)...]
            var best: (quote: String.Index, close: String.Index)?
            if let r = tail.range(of: "\"]") {
                best = (r.lowerBound, s.index(before: r.upperBound))
            }
            if let r = tail.range(of: "\" from app "),
               let close = s[r.upperBound...].firstIndex(where: { $0 == "]" || $0 == "\n" }),
               s[close] == "]", best.map({ r.lowerBound < $0.quote }) ?? true {
                best = (r.lowerBound, close)
            }
            return best?.close
        }
        guard let close = rest.firstIndex(where: { $0 == "]" || $0 == "[" || $0 == "\n" }),
              rest[close] == "]" else { return nil }
        let inner = String(rest[rest.startIndex..<close])
        return looksLikeToken(inner) ? close : nil
    }

    private static func looksLikeToken(_ inner: String) -> Bool {
        let known = ["📸", "🎦", "📁", "dictated", "Dictated", "Transcribed", "face:", "chrome-selection",
                     "--image", "the shots I took", "If I asked", "a question →", "Focused window", "selected:"]
        if known.contains(where: inner.hasPrefix) { return true }
        // `[😡]` — a mark the face or the voice left, no letters in it.
        return !inner.isEmpty && inner.count <= 3 && !inner.contains(where: { $0.isLetter || $0.isNumber })
    }

    /// Where an entry's frames are: the envelope's `📁`, else the folder of its
    /// first path. The corners of an area are in the original frame's pixels.
    struct Shots {
        var folder: URL?
        var sources: [String: String]
        var legendSize: CGSize?

        init(_ entry: Entry) {
            sources = entry.sources
            if let line = entry.line, let r = line.range(of: "[📁="),
               let end = line[r.upperBound...].firstIndex(of: "]") {
                folder = URL(fileURLWithPath: MessageLog.expand(String(line[r.upperBound..<end])))
            } else if let first = entry.shots.first {
                folder = URL(fileURLWithPath: first).deletingLastPathComponent()
            }
            if let line = entry.line,
               let regex = try? NSRegularExpression(pattern: #"at (\d+)x(\d+)px"#),
               let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let w = Range(m.range(at: 1), in: line).flatMap({ Double(line[$0]) }),
               let h = Range(m.range(at: 2), in: line).flatMap({ Double(line[$0]) }) {
                legendSize = CGSize(width: w, height: h)
            }
        }

        /// The first of `suffixes` that is on disk: `-800px`, `-original`, `` (the cut-out).
        func file(_ n: Int, _ suffixes: [String]) -> URL? {
            guard let folder else { return nil }
            return suffixes.lazy
                .map { folder.appendingPathComponent("screenshot-\(n)\($0).jpg") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }

        func caption(_ n: Int) -> String? { sources["screenshot-\(n)-original.jpg"] }

        /// The original's pixel size, read from its header (no decode), else the legend's.
        func pixels(_ n: Int) -> CGSize? {
            if let original = file(n, ["-original"]),
               let source = CGImageSourceCreateWithURL(original as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let w = props[kCGImagePropertyPixelWidth] as? Int,
               let h = props[kCGImagePropertyPixelHeight] as? Int {
                return CGSize(width: w, height: h)
            }
            return legendSize
        }
    }

    /// `$WALKIE_SHOTS` is the agents' name for the shots folder (their rules
    /// define it); anywhere else it is a path that leads nowhere.
    static func expand(_ s: String) -> String {
        s.replacingOccurrences(of: "$WALKIE_SHOTS", with: Outbox.cacheRoot.path)
    }

    private static func shotIndex(_ path: String) -> Int? {
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix("screenshot-") else { return nil }
        return Int(name.dropFirst("screenshot-".count).prefix(while: \.isNumber))
    }

    // MARK: - Drawing the tokens

    private static func renderToken(_ token: String, shots: Shots, used: inout Set<Int>) -> String {
        if token.hasPrefix("📸") {
            let digits = token.dropFirst().prefix(while: \.isNumber)
            if let n = Int(digits) {
                used.insert(n)
                if let area = AreaContext.corners(in: token) {
                    return areaFigure(n, box: area.box, movedTo: area.movedTo, shots: shots)
                }
                let note = token.dropFirst(1 + digits.count).trimmingCharacters(in: .whitespaces)
                return shotFigure(n, note: note, shots: shots)
            }
        }
        if let quote = quoted(token) { return quote }
        if token.hasPrefix("face:") {
            return "<span class=\"chip\">\(esc(token.dropFirst(5).trimmingCharacters(in: .whitespaces)))</span>"
        }
        return "<span class=\"chip\">\(esc(token))</span>"
    }

    /// `[selected: "…" from app X]`, `[copied: …]`, `[typed: "…"]` → a quote.
    private static func quoted(_ token: String) -> String? {
        guard let regex = try? NSRegularExpression(
                pattern: #"^(selected|copied|typed): "(.*)"(?: from app (.*))?$"#, options: [.dotMatchesLineSeparators]),
              let m = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              let verb = Range(m.range(at: 1), in: token).map({ String(token[$0]) }),
              let text = Range(m.range(at: 2), in: token).map({ String(token[$0]) }) else { return nil }
        let app = Range(m.range(at: 3), in: token).map { String(token[$0]) }
        let from: String
        switch verb {
        case "copied": from = "copied" + (app.map { " from \($0)" } ?? "")
        case "typed": from = "typed"
        default: from = app.map { "in \($0)" } ?? "selected"
        }
        return "<span class=\"q\">\(esc(text))<span class=\"from\">\(esc(from))</span></span>"
    }

    private static func shotFigure(_ n: Int, note: String, shots: Shots) -> String {
        guard let shown = shots.file(n, ["-800px", "-original"]) else {
            return "<span class=\"chip\">🗑️ 📸\(n) — no longer on disk</span>"
        }
        let href = (shots.file(n, ["-original"]) ?? shown).absoluteString
        let auto = note.contains("auto")
        let label = ["📸\(n)", auto ? "screen when he started" : note, shots.caption(n) ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return "<a class=\"fig \(auto ? "auto" : "shot")\" href=\"\(esc(href))\" target=\"_blank\">"
            + "<img src=\"\(esc(shown.absoluteString))\" alt=\"\(esc(label))\" loading=\"lazy\">"
            + "<span class=\"cap\" title=\"\(esc(label))\">\(esc(label))</span></a>"
    }

    /// **The area, twice: what he cut out, and where it was** — the cut-out
    /// `screenshot-n.jpg`, and the whole screen greyed outside the box, the box
    /// ringed red, a `moved to` box green with a white arrow from the one to the
    /// other. Drawn in SVG over the 800 px copy, in the original's pixels, so the
    /// corners are the token's own numbers.
    private static func areaFigure(_ n: Int, box: CGRect, movedTo: CGRect?, shots: Shots) -> String {
        let cut = shots.file(n, [""])
        let screen = shots.file(n, ["-800px", "-original"])
        let original = shots.file(n, ["-original"])
        let source = shots.caption(n)
        guard cut != nil || screen != nil else {
            return "<span class=\"chip\">🗑️ 📸\(n)✂️ — no longer on disk</span>"
        }
        var out = "<span class=\"area\">"
        if let cut {
            let label = "📸\(n) ✂️ the area" + (movedTo == nil ? "" : " he moved")
            out += "<a class=\"fig cut\" href=\"\(esc(cut.absoluteString))\" target=\"_blank\">"
            out += "<img src=\"\(esc(cut.absoluteString))\" alt=\"\(esc(label))\" loading=\"lazy\">"
            out += "<span class=\"cap\">\(esc(label))</span></a>"
        }
        if let screen, let px = shots.pixels(n) {
            let label = (movedTo == nil ? "where: " : "from 🟥 to 🟩: ") + (source ?? "📸\(n)")
            out += "<a class=\"fig ctx\" href=\"\(esc((original ?? screen).absoluteString))\" target=\"_blank\">"
            out += areaSVG(image: screen, pixels: px, box: box, movedTo: movedTo)
            out += "<span class=\"cap\" title=\"\(esc(label))\">\(esc(label))</span></a>"
        }
        out += "</span>"
        return out
    }

    static func areaSVG(image: URL, pixels: CGSize, box: CGRect, movedTo: CGRect?) -> String {
        func f(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        let w = pixels.width, h = pixels.height
        let boxes = [box] + (movedTo.map { [$0] } ?? [])
        // Even-odd with the boxes as holes; two that overlap would cancel each
        // other's hole, so they are unioned first — `AreaContext.image`'s rule.
        let holes = boxes.count == 2 && boxes[0].intersects(boxes[1]) ? [boxes[0].union(boxes[1])] : boxes
        var veil = "M0 0H\(f(w))V\(f(h))H0Z"
        for r in holes { veil += " M\(f(r.minX)) \(f(r.minY))H\(f(r.maxX))V\(f(r.maxY))H\(f(r.minX))Z" }
        func ring(_ r: CGRect, _ colour: String) -> String {
            "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" "
                + "fill=\"none\" stroke=\"\(colour)\" stroke-width=\"3\" vector-effect=\"non-scaling-stroke\"/>"
        }
        var svg = "<svg viewBox=\"0 0 \(f(w)) \(f(h))\" xmlns=\"http://www.w3.org/2000/svg\" role=\"img\">"
        svg += "<image href=\"\(esc(image.absoluteString))\" x=\"0\" y=\"0\" width=\"\(f(w))\" height=\"\(f(h))\" preserveAspectRatio=\"none\"/>"
        svg += "<path d=\"\(veil)\" fill=\"#141416\" fill-opacity=\"0.62\" fill-rule=\"evenodd\"/>"
        svg += ring(box, "#ff453a")
        if let to = movedTo {
            svg += ring(to, "#30d158")
            let a = CGPoint(x: box.midX, y: box.midY), b = CGPoint(x: to.midX, y: to.midY)
            let dx = b.x - a.x, dy = b.y - a.y, len = max(1, hypot(dx, dy))
            let ux = dx / len, uy = dy / len
            let head = w * 0.022
            let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
            svg += "<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(base.x))\" y2=\"\(f(base.y))\" "
                + "stroke=\"#fff\" stroke-width=\"2.5\" vector-effect=\"non-scaling-stroke\"/>"
            let p1 = CGPoint(x: base.x - uy * head * 0.55, y: base.y + ux * head * 0.55)
            let p2 = CGPoint(x: base.x + uy * head * 0.55, y: base.y - ux * head * 0.55)
            svg += "<polygon points=\"\(f(b.x)),\(f(b.y)) \(f(p1.x)),\(f(p1.y)) \(f(p2.x)),\(f(p2.y))\" fill=\"#fff\"/>"
        }
        svg += "</svg>"
        return svg
    }

    /// `[🎦1 = $WALKIE_SHOTS/…/film-…/sheet.png, 14s, 51 frames, video video.mov]` → a player.
    private static func film(_ token: String) -> String? {
        guard token.hasPrefix("🎦"),
              let regex = try? NSRegularExpression(pattern: #"^🎦(\d+) = (.+?), (\d+)s, (\d+) frames(?:, video (.+))?$"#),
              let m = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)),
              let n = Range(m.range(at: 1), in: token).map({ String(token[$0]) }),
              let sheetPath = Range(m.range(at: 2), in: token).map({ expand(String(token[$0])) }),
              let seconds = Range(m.range(at: 3), in: token).map({ String(token[$0]) }),
              let frames = Range(m.range(at: 4), in: token).map({ String(token[$0]) }) else { return nil }
        let dir = URL(fileURLWithPath: sheetPath).deletingLastPathComponent()
        let sheet = URL(fileURLWithPath: sheetPath)
        let video = Range(m.range(at: 5), in: token).map { dir.appendingPathComponent(String(token[$0])) }
        let poster = dir.appendingPathComponent("poster.jpg")
        let fm = FileManager.default
        var out = "<div class=\"film\">"
        if let video, fm.fileExists(atPath: video.path) {
            out += "<video controls preload=\"metadata\""
            if fm.fileExists(atPath: poster.path) { out += " poster=\"\(esc(poster.absoluteString))\"" }
            out += " src=\"\(esc(video.absoluteString))\"></video>"
        } else if fm.fileExists(atPath: sheet.path) {
            out += "<a href=\"\(esc(sheet.absoluteString))\" target=\"_blank\"><img src=\"\(esc(sheet.absoluteString))\" "
            out += "style=\"width:480px;max-width:100%;border-radius:6px\" loading=\"lazy\" alt=\"contact sheet\"></a>"
        } else {
            return "<div class=\"film\"><div class=\"gone\">🗑️ 🎦\(esc(n)) — the film is no longer on disk</div></div>"
        }
        out += "<span class=\"cap\">🎦\(esc(n)) · \(esc(seconds)) s · \(esc(frames)) frames"
        if fm.fileExists(atPath: sheet.path) {
            out += " · <a href=\"\(esc(sheet.absoluteString))\" target=\"_blank\">contact sheet</a>"
        }
        out += "</span></div>"
        return out
    }

    /// The footer's small print: how it was dictated, the face, the folder.
    private static func metaChip(_ token: String, shots: Shots) -> String? {
        if token.hasPrefix("dictated") || token.hasPrefix("Dictated") || token.hasPrefix("Transcribed") {
            return "<span class=\"chip\">\(esc(token))</span>"
        }
        if token.hasPrefix("face:") {
            return "<span class=\"chip\">\(esc(token.dropFirst(5).trimmingCharacters(in: .whitespaces)))</span>"
        }
        if token.hasPrefix("📁="), let folder = shots.folder,
           FileManager.default.fileExists(atPath: folder.path) {
            return "<a href=\"\(esc(folder.absoluteString))\" target=\"_blank\">📁 \(esc(folder.lastPathComponent))</a>"
        }
        return nil
    }

    /// **Where it went, by the name he knows it by.** The title recorded at the
    /// send (`Outbox.stampTitle`); for an older row the tab's title *now*,
    /// marked so; else the tty. A spawn names its folder.
    private static func destination(_ entry: Entry, titles: [String: String]) -> String? {
        guard let to = entry.to, !to.isEmpty else { return nil }
        func pill(_ text: String, tip: String, now: Bool = false) -> String {
            "<span class=\"to\" title=\"\(esc(tip))\">→ \(esc(text))\(now ? "<small>title now</small>" : "")</span>"
        }
        if to.hasPrefix("terminal:") {
            let name = String(to.dropFirst("terminal:".count))
            if let title = entry.title { return pill(cleanTitle(title), tip: "\(name) — its title when sent") }
            if let title = titles[name], !title.isEmpty {
                return pill(cleanTitle(title), tip: "\(name) — sent before titles were recorded; this is the tab's title now",
                            now: true)
            }
            return pill(name, tip: to)
        }
        if to.hasPrefix("spawn:") {
            let folder = (String(to.dropFirst("spawn:".count)) as NSString).lastPathComponent
            return pill("✨ new session in \(folder)", tip: to)
        }
        return pill(to, tip: to)
    }

    /// `✳ workspace — Taste volum` → `workspace — Taste volum`: the leading mark
    /// is Claude Code's busy/idle spinner, a state of that second, not a name.
    static func cleanTitle(_ title: String) -> String {
        let trimmed = title.drop { !$0.isLetter && !$0.isNumber }
        return trimmed.isEmpty ? title : String(trimmed)
    }

    /// What Copy puts on the clipboard: the envelope as delivered, with
    /// `$WALKIE_SHOTS` spelled out — pasted anywhere but an agent that holds the
    /// rules, the variable is a path to nowhere (2026-11-25, *"copiezi promptul
    /// real … cu căi de fișiere"*).
    static func copyText(_ entry: Entry) -> String { expand(payload(entry)) }

    /// **What Copy puts on the clipboard: the exact prompt ⌘⇧P would paste.**
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
    /// The same envelope, for the menu's *Prompt History* rows — the page's Copy
    /// button and that row hand over one string, because they are answering one
    /// question with one file behind it.
    static func envelope(_ entry: Entry) -> String { payload(entry) }

    /// **The first words of a sentence, and an ellipsis if there were more.**
    ///
    /// Written for a menu row, which is why it is words and not characters: a
    /// clamp at 42 characters cuts mid-word about half the time, and a row
    /// ending in `the configura…` reads as a rendering fault rather than as a
    /// deliberate summary. Newlines and runs of spaces collapse first — a
    /// dictated prompt carries the shots' clause and the window line under it,
    /// and a menu row draws all of that as one long grey smear.
    static func snippet(_ text: String, limit: Int = 42) -> String {
        let flat = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var out = ""
        var truncated = false
        for word in flat {
            if out.isEmpty {
                out = String(word)
            } else if out.count + 1 + word.count <= limit {
                out += " " + word
            } else {
                truncated = true
                break
            }
        }
        if out.isEmpty { return "…" }
        // A single word longer than the whole row is cut where it has to be —
        // the one case the word rule cannot serve.
        if out.count > limit {
            out = String(out.prefix(limit))
            truncated = true
        }
        return truncated ? out + "…" : out
    }

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
