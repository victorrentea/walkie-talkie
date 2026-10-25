import Foundation

/// **⚡ A quick question: answered by a fast model, beside the pointer**
/// (2026-10-09). Victor: *"a dumb mode or a quick fast mode to this walkie-talkie
/// that will answer as fast as it can"*, on his subscription, not an API key.
///
/// **One `claude -p` kept started, used for one question, then replaced.** A
/// cold `claude -p` costs ~2 s to start and ~2 s to exit around a 1.5 s answer
/// (measured 2026-10-09, `evals/quick-ask/`); one already running answers its
/// first words in ~0.5 s. Each process takes exactly one question — Victor:
/// *"a conversation history over the day … will make it slower after a
/// while"* — and the next one is started the moment it has answered, so the
/// start-up is paid while he is not waiting.
///
/// **Lean on purpose**: its own short system prompt instead of Claude Code's,
/// no tools, no MCP servers, no settings files (no hooks, no CLAUDE.md), run
/// from `~/.walkie-talkie/quick/` — ~700 input tokens instead of ~104 000, and
/// the first word ~0.1 s sooner. Opus at low effort unless `WT_QUICK_MODEL` /
/// `WT_QUICK_EFFORT` (env or `elevenlabs.env`) say otherwise.
///
/// **Then the answer is checked, twice** (2026-10-10, Victor: *"după ce termină
/// de scris, trebuie să înceapă să caute pe net dovezi … ridici un subagent
/// adversarial care să critice. Asta e rețeta"*): 🔎 a second process with
/// WebSearch/WebFetch confirms or corrects the answer and cites its sources,
/// then 🧐 a third, told to break it, reviews answer + sources. Each one is
/// started while the stage before it runs, so its start-up is not waited for.
/// The ✕ on the pop-up, or 🔼 ←, stops whatever stage is running.
///
/// **A question is a prompt whose outcome is an answer** (2026-10-15, Victor:
/// *"all the features available for prompting should be available as well for
/// questioning … It's kind of like an ask mode"*): the envelope comes with it —
/// the screen, the shots and crops as pictures (content blocks, labelled 📸n,
/// so the lean process needs no Read tool), the highlights and picks as text.
/// **And it can be followed up** (same day: *"I should be able to fire a
/// follow-up question … I don't expect to have more than two or three such
/// turns"*): the turns before it ride as a transcript at the top of the same
/// message, their pictures with them — each process still takes one message.
final class QuickAsk {
    static let shared = QuickAsk()

    static let systemPrompt = """
        You answer Victor's spoken questions, dictated by voice, so the words may \
        contain recognition mistakes: answer what he most likely meant. Be brief: \
        what was asked in one short sentence, plus at most one closely related fact \
        worth knowing; plain text, no markdown, no lists unless asked. \
        Answer in the language of the question (Romanian or English). \
        The question may carry what was on his screen: pictures labelled 📸n, \
        selected text and picked elements in brackets, and file paths you cannot \
        open — use them to understand what he is asking about. When earlier turns \
        of the conversation are given, answer the last question in their light.
        """
    /// **Each check writes the whole answer again** (2026-10-10, Victor: *"un
    /// răspuns imediat, apoi unul căutat, apoi unul criticat … în funcție de cât
    /// timp îl las"*): the pop-up always holds the best answer so far, so closing
    /// it at any moment leaves him with a complete one.
    /// **Only the proven facts, in his language, no quotes** (2026-10-10,
    /// Victor: *"Islanda are aproximativ 396.500 de locuitori … aproape două
    /// treimi din ei locuiesc în regiunea capitalei. Atât"*; *"nu vreau citat
    /// verbatim din site"*): the quote is written only inside the marker, for
    /// the link to select it on the page.
    static let citeFormat = cite(length: """
        As short as possible: what was asked, in one short sentence, plus at most \
        one closely related fact worth knowing.
        """)
    /// **🪏 dig more is longer**: the new things it found are the point of it.
    static let digCiteFormat = cite(length: """
        What was asked, in one short sentence, then what the new sources add, in \
        a few short sentences (at most six in all), the most useful first.
        """)
    private static func cite(length: String) -> String { """
        Reply in the language of the question, plain text, no markdown. \(length) \
        Never quote or translate the sources in the \
        answer, and never mention the checking, the sources or what changed. Right \
        after each claim put a marker [n: "<quote>"], where the quote is a short \
        passage (under 15 words) copied character for character, in the page's own \
        language, from page n that proves the claim — it is never shown, it selects \
        that passage when the page opens. After the answer, one line per source, \
        nothing else on it: [n] <url>. Last, only if the substance of your answer \
        differs from the one you were given, a line with just: CHANGED
        """ }
    static let webPrompt = """
        You were given a spoken question by Victor and a quick answer to it, written \
        from memory without any checking. Search the web for evidence, writing \
        nothing before your searches are done, and write the answer again: \
        corrected where the sources say otherwise, completed where they add \
        something that matters.
        """ + " " + citeFormat
    static let reviewPrompt = reviewTask + " " + citeFormat
    /// The review after a 🪏 dig more keeps what it found, at its length.
    static let digReviewPrompt = reviewTask + " Keep the new information that holds up. " + digCiteFormat
    private static let reviewTask = """
        You are an adversarial reviewer. You get a spoken question by Victor and an \
        answer to it with quotes and sources. Assume it is wrong somewhere and try \
        to prove it: open the cited pages and check that each quote is really \
        there and really means what the answer says (out of context, outdated, \
        about something else, a weak source); look for what is missing and \
        changes the answer. Write nothing before your checks are done, then write \
        the answer again, fixed.
        """
    /// **🌐 More: one more round on the web** (2026-10-22, Victor: *"un buton mic …
    /// more, prin care să mai solicit mai mult research pe internet … mai multe
    /// dovezi și alte surse"*). Given the answer already checked and the sources it
    /// used, so the round goes looking somewhere else.
    /// **To learn more, not only to confirm** (2026-10-23, Victor: *"când îți spun
    /// să dig deeper … nu doar să îmi susții sau să-mi infirmi … ci să cauți cumva
    /// mai profund, mai multe surse, nu doar cu scopul de a valida informația, ci
    /// de a mai aduna alte informații noi"*) — at `digCiteFormat`'s length.
    static let morePrompt = """
        You get a spoken question by Victor and an answer to it already checked on \
        the web, with the sources it used. He wants to know more: dig deeper, in \
        sources other than the ones listed (other sites, primary sources, \
        specialised and more recent ones), not to confirm the answer again but to \
        find what it does not say yet — details, numbers, causes, context, \
        exceptions, what changed lately, what follows from it. Correct anything \
        the new sources contradict. Write nothing before your searches are done, \
        then write the answer again with the new information, the old sources \
        included where they still hold.
        """ + " " + digCiteFormat
    /// A question with no answer by then is given up.
    static let timeout: TimeInterval = 45
    /// **The answer as shown** (2026-10-10, Victor: *"nu mă interesează să văd
    /// URL-urile complete … pune în paranteze rotunde numele site-ului, iar la
    /// hover … URL-ul complet. La click … să mă ducă la acel site, preferabil
    /// selectând textele"*): every `[n: "quote"]` becomes a blue ↗, a
    /// link (`ReplyPanel.link`) to its page with the quote selected there by a
    /// text fragment (`#:~:text=`) — the quote itself is never shown; the
    /// `[n] url` lines and `CHANGED` go. `changed` says the answer is not the one before it in substance.
    static func cited(_ raw: String) -> (text: String, changed: Bool) {
        var urls: [String: URL] = [:]
        var lines: [String] = []
        var changed = false
        let sourceLine = try! NSRegularExpression(pattern: #"^\s*\[(\d+)\]\s*(?:\S.*?\s)?(https?://\S+?)[).,]?\s*$"#)
        for line in raw.components(separatedBy: "\n") {
            let ns = line as NSString
            if let m = sourceLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               let url = URL(string: ns.substring(with: m.range(at: 2))) {
                urls[ns.substring(with: m.range(at: 1))] = url
                continue
            }
            if line.trimmingCharacters(in: .whitespaces) == "CHANGED" { changed = true; continue }
            lines.append(line)
        }
        var text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // [n: "quote"] (any of „" “” quotes), or a bare [n].
        let marked = try! NSRegularExpression(pattern: #"\s*\[(\d+)(?::\s*[„"“](.*?)[”"“]\s*)?\]"#)
        let ns = text as NSString
        var out = "", at = 0
        for m in marked.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            at = m.range.location + m.range.length
            guard let url = urls[ns.substring(with: m.range(at: 1))] else { continue }
            let quote = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            // **Just a blue ↗** (same day, Victor: *"doar o iconiță care să arate
            // o săgeată … pe un albastru, fără subliniere"*): the site's name is
            // the hover's, with the rest of the URL.
            out += " " + ReplyPanel.link("↗", quote.isEmpty ? url : fragment(url, quote: quote))
        }
        out += ns.substring(from: at)
        text = out.replacingOccurrences(of: " +([.,;:])", with: "$1", options: .regularExpression)
        return (text, changed)
    }

    /// `url` with `quote` selected when the page opens: Chrome's text fragment.
    /// A long quote is matched by its first and last words, which survive the
    /// small differences a model makes in the middle.
    static func fragment(_ url: URL, quote: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "._~!$'()*+;=:@/?")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        let words = quote.split(whereSeparator: \.isWhitespace).map(String.init)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "…")) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return url }
        let directive = words.count > 8
            ? "text=" + enc(words.prefix(4).joined(separator: " ")) + "," + enc(words.suffix(4).joined(separator: " "))
            : "text=" + enc(words.joined(separator: " "))
        var s = url.absoluteString
        s += s.contains("#") ? ":~:" + directive : "#:~:" + directive
        return URL(string: s) ?? url
    }

    /// The web check and the review, each.
    static let checkTimeout: TimeInterval = 120
    static let webTools = "WebSearch,WebFetch"

    /// **One turn of a conversation** (2026-10-15): what was asked — the whole
    /// envelope — the pictures that came with it, and the best answer it got
    /// (the reviewed one, else the searched one, else the quick one).
    struct Turn {
        var question: String
        var images: [String]
        var answer: String
    }
    /// The turns a follow-up carries — Victor expects *"two or three"*.
    static let turnsKept = 4
    /// Pictures in one message, newest kept.
    static let imagesKept = 8

    /// **The message a stage gets**: the turns before it as a transcript, then
    /// this question — and every picture of the conversation, each behind its
    /// `📸n` label (`📸n of question k` for an earlier turn's).
    static func framed(_ question: String, history: [Turn]) -> String {
        guard !history.isEmpty else { return question }
        var lines = ["Earlier in this conversation:", ""]
        for (i, t) in history.enumerated() {
            lines.append("Question \(i + 1): \(t.question)")
            lines.append("Answer \(i + 1): \(t.answer.isEmpty ? "(no answer yet)" : t.answer)")
            lines.append("")
        }
        lines.append("Now the follow-up question:")
        lines.append(question)
        return lines.joined(separator: "\n")
    }

    static func pictures(_ images: [String], history: [Turn]) -> [(label: String, path: String)] {
        var all: [(String, String)] = []
        for (i, t) in history.enumerated() {
            for p in t.images { all.append((label(p) + " of question \(i + 1)", p)) }
        }
        for p in images { all.append((label(p), p)) }
        return Array(all.suffix(imagesKept))
    }

    private static func label(_ path: String) -> String {
        ScreenCapture.number(of: path).map { "📸\($0)" } ?? "📸"
    }

    /// The text alone, or the text after its pictures as content blocks. A
    /// picture that cannot be read is left out, never the question.
    static func content(_ text: String, pictures: [(label: String, path: String)]) -> Any {
        var blocks: [[String: Any]] = []
        for (label, path) in pictures {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            let type = ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : ext == "webp" ? "image/webp" : "image/jpeg"
            blocks.append(["type": "text", "text": label + ":"])
            blocks.append(["type": "image", "source": ["type": "base64", "media_type": type,
                                                       "data": data.base64EncodedString()]])
        }
        guard !blocks.isEmpty else { return text }
        blocks.append(["type": "text", "text": text])
        return blocks
    }

    /// The follow-ups of one question, after its answer. Each gets its text so
    /// far, and `done: true` once, with the last of it — or why it failed.
    struct Checks {
        var web: (_ text: String, _ done: Bool) -> Void
        var review: (_ text: String, _ done: Bool) -> Void
        /// Everything is over: answered and checked, failed, or cancelled.
        var end: () -> Void
    }

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.quick-ask")
    private var ready: Worker?
    /// The question being answered or checked — 🔼 ← or the ✕ take it down.
    private var current: Run?
    private var failedStarts = 0

    /// One question's processes, so a cancel stops whichever is running.
    private final class Run {
        var workers: [Worker] = []
        var cancelled = false
        var checks: Checks?
    }

    var model: String { Self.setting("WT_QUICK_MODEL") ?? "opus" }
    var effort: String { Self.setting("WT_QUICK_EFFORT") ?? "low" }

    private static func setting(_ key: String) -> String? {
        let v = ProcessInfo.processInfo.environment[key] ?? ElevenLabsSource.fileValue(key)
        return v?.isEmpty == false ? v : nil
    }

    static var claudePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// True while a question is being answered.
    var isAnswering: Bool { queue.sync { current != nil } }

    /// **Who will answer the next question** (2026-10-14, Victor: *"I don't know
    /// who's answering me"*): the pop-up is signed with it before the first word,
    /// under `Replying from training data…`. The model the last process said it
    /// ran (`Opus 5.5`), kept across launches per setting; else the setting's
    /// own name (`Opus`). `onDone` still signs with the one that answered.
    var answererName: String {
        UserDefaults.standard.string(forKey: servedKey).map(Self.displayName) ?? Self.displayName(model)
    }
    private var servedKey: String { "WTQuickServed.\(model)" }

    /// `claude-opus-5-5` → `Opus 5.5`, for the signature under the answer.
    static func displayName(_ id: String) -> String {
        var parts = id.replacingOccurrences(of: "[1m]", with: "").split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }   // a date suffix
        guard let name = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        return name.prefix(1).uppercased() + name.dropFirst() + (version.isEmpty ? "" : " \(version)")
    }

    /// Starts the next process if none is waiting. Cheap to call often.
    func warm() {
        queue.async { self.warmLocked() }
    }

    private func warmLocked() {
        if let r = ready, r.alive { return }
        guard failedStarts < 3 else { return }
        do {
            ready = try Worker(model: model, effort: effort, prompt: Self.systemPrompt)
            ready?.onExit = { [weak self] w in
                self?.queue.async {
                    guard let self, self.ready === w else { return }
                    // An idle process that died on its own: start another, but not in a loop.
                    self.ready = nil
                    self.failedStarts += 1
                    Log.error("⚡ the waiting quick-answer process exited by itself (\(self.failedStarts)/3) — \(w.stderrTail)")
                    if self.failedStarts < 3 {
                        self.queue.asyncAfter(deadline: .now() + 2) { self.warmLocked() }
                    }
                }
            }
        } catch {
            failedStarts += 1
            Log.error("⚡ could not start the quick-answer process: \(error)")
        }
    }

    /// Asks one question. `onText` gets the answer so far, as it streams;
    /// `onDone` the whole answer, or nil and why it failed, and the model that
    /// answered (`Opus 5.5`). Then, when `checks` is given, the 🔎 web check and
    /// the 🧐 review of it. All callbacks on main.
    func ask(_ question: String, images: [String] = [], history: [Turn] = [],
             checks: Checks? = nil, onText: @escaping (String) -> Void,
             onDone: @escaping (_ answer: String?, _ error: String?, _ firstWord: TimeInterval?, _ model: String) -> Void) {
        queue.async {
            // A new question ends whatever the last one was still doing.
            self.cancelLocked()
            self.failedStarts = 0
            self.warmLocked()
            let modelName = Self.displayName(self.model)
            guard let w = self.ready, w.alive else {
                DispatchQueue.main.async {
                    onDone(nil, Self.claudePath == nil ? "claude is not installed" : "the quick model did not start", nil, modelName)
                    checks?.end()
                }
                return
            }
            self.ready = nil
            let run = Run()
            run.checks = checks
            run.workers = [w]
            self.current = run
            // The web check starts now, while the answer is being written.
            let web = checks == nil ? nil : self.start(run, prompt: Self.webPrompt, tools: Self.webTools)
            let started = CFAbsoluteTimeGetCurrent()
            var first: TimeInterval?
            let asked = Self.framed(question, history: history)
            let pictures = Self.pictures(images, history: history)
            if !pictures.isEmpty || !history.isEmpty {
                Log.info("⚡ asking with \(pictures.count) picture(s) and \(history.count) earlier turn(s)")
            }
            self.stage(run, w, Self.content(asked, pictures: pictures), timeout: Self.timeout, onText: { text in
                if first == nil { first = CFAbsoluteTimeGetCurrent() - started }
                DispatchQueue.main.async { onText(text) }
            }, onDone: { answer, error in
                if let served = w.servedModel { UserDefaults.standard.set(served, forKey: self.servedKey) }
                let name = w.servedModel.map(Self.displayName) ?? modelName
                DispatchQueue.main.async { onDone(answer, error, first, name) }
                guard let checks, let answer, let web else { return self.endLocked(run) }
                self.check(run, question: asked, pictures: pictures, answer: answer, web: web, checks: checks)
            })
            // The next one starts now, while this one answers.
            self.warmLocked()
        }
    }

    /// **The question as a Google query** (2026-10-25, 🔽 → over a ⚡ question —
    /// `AppDelegate.googleQuestion`). The waiting process gets the envelope and
    /// its pictures with an order not to answer: one line, the few words he would
    /// type into Google, in the question's language — what a picture shows (a
    /// font, a product, an error) named in words. nil and why after
    /// `searchTimeout`, or when no process is up. On main.
    static let searchOrder = """
        Do not answer. Write only the Google search query for what I ask below — one line, \
        3 to 8 words, in the language I asked in, no quotes, no explanation. Name in words \
        whatever my pictures show that the search needs (the font, product, error message, place).
        """
    static let searchTimeout: TimeInterval = 8

    func searchQuery(_ question: String, images: [String] = [],
                     done: @escaping (_ query: String?, _ error: String?) -> Void) {
        queue.async {
            // A new question ends whatever the last one was still doing.
            self.cancelLocked()
            self.failedStarts = 0
            self.warmLocked()
            guard let w = self.ready, w.alive else {
                DispatchQueue.main.async { done(nil, "the quick model did not start") }
                return
            }
            self.ready = nil
            let run = Run()
            run.workers = [w]
            self.current = run
            let asked = Self.searchOrder + "\n\n" + question
            let pictures = Self.pictures(images, history: [])
            self.stage(run, w, Self.content(asked, pictures: pictures), timeout: Self.searchTimeout, onText: { _ in },
                       onDone: { query, error in
                let line = query?.split(separator: "\n").first
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`*")) }
                self.endLocked(run)
                DispatchQueue.main.async {
                    if let line, !line.isEmpty { done(line, nil) } else { done(nil, error ?? "an empty query") }
                }
            })
            self.warmLocked()
        }
    }

    /// **🌐 More** (2026-10-22): another web round on the last answer, from
    /// sources other than `sources`, then the 🧐 review again — the same
    /// `checks` callbacks as the first round. Ends whatever is still running.
    func more(_ question: String, images: [String] = [], history: [Turn] = [],
              answer: String, sources: [URL], checks: Checks) {
        queue.async {
            self.cancelLocked()
            let run = Run()
            run.checks = checks
            self.current = run
            let asked = Self.framed(question, history: history)
            let pictures = Self.pictures(images, history: history)
            let web = self.start(run, prompt: Self.morePrompt, tools: Self.webTools)
            let used = sources.map { "- \($0.absoluteString)" }.joined(separator: "\n")
            Log.info("⚡ 🌐 more: another web round, \(sources.count) source(s) to look past")
            self.check(run, question: asked, pictures: pictures, answer: answer, web: web, checks: checks,
                       webInput: "Question: \(asked)\n\nAnswer so far, already checked on the web:\n\(answer)"
                           + (used.isEmpty ? "" : "\n\nSources already used — find others:\n\(used)"),
                       review: Self.digReviewPrompt)
        }
    }

    /// 🔎 then 🧐, on `queue`. `webInput` replaces the web stage's message (🌐 More).
    private func check(_ run: Run, question: String, pictures: [(label: String, path: String)],
                       answer: String, web: Worker?, checks: Checks, webInput: String? = nil,
                       review: String = QuickAsk.reviewPrompt) {
        guard let web else {
            DispatchQueue.main.async { checks.web("⚠️ the web check did not start", true) }
            return endLocked(run)
        }
        // The reviewer starts while the web is searched.
        let reviewer = start(run, prompt: review, tools: Self.webTools)
        let asked = webInput ?? "Question: \(question)\n\nQuick answer, from memory: \(answer)"
        stage(run, web, Self.content(asked, pictures: pictures), timeout: Self.checkTimeout, onText: { text in
            DispatchQueue.main.async { checks.web(text, false) }
        }, onDone: { found, error in
            DispatchQueue.main.async { checks.web(found ?? "⚠️ \(error ?? "no result")", true) }
            guard let reviewer else {
                DispatchQueue.main.async { checks.review("⚠️ the reviewer did not start", true) }
                return self.endLocked(run)
            }
            // The reviewer criticises the searched answer — or, when the
            // search failed, the quick one.
            let all = found.map { "Question: \(question)\n\nAnswer, checked on the web:\n\($0)" }
                ?? asked + "\n\n(The web check failed: \(error ?? "?"). Search yourself.)"
            self.stage(run, reviewer, Self.content(all, pictures: pictures), timeout: Self.checkTimeout, onText: { text in
                DispatchQueue.main.async { checks.review(text, false) }
            }, onDone: { verdict, error in
                DispatchQueue.main.async { checks.review(verdict ?? "⚠️ \(error ?? "no review")", true) }
                self.endLocked(run)
            })
        })
    }

    /// A process for a later stage of `run`, started now; nil when it could not be.
    private func start(_ run: Run, prompt: String, tools: String) -> Worker? {
        guard let w = try? Worker(model: model, effort: effort, prompt: prompt, tools: tools) else { return nil }
        run.workers.append(w)
        return w
    }

    /// Sends `input` to `w` and calls `onDone` once — the result, its exit, or
    /// the timeout — on `queue`, unless the run was cancelled. Stops `w` after.
    private func stage(_ run: Run, _ w: Worker, _ input: Any, timeout: TimeInterval,
                       onText: @escaping (String) -> Void, onDone: @escaping (String?, String?) -> Void) {
        var finished = false
        let finish: (String?, String?) -> Void = { text, error in
            self.queue.async {
                guard !finished, !run.cancelled else { return }
                finished = true
                w.stop()
                onDone(text, error)
            }
        }
        w.onText = { text in if !run.cancelled { onText(text) } }
        w.onResult = { text, error in finish(text, error) }
        w.onExit = { w in finish(nil, "the model exited — \(w.stderrTail)") }
        w.send(input)
        queue.asyncAfter(deadline: .now() + timeout) { finish(nil, "nothing in \(Int(timeout)) s") }
    }

    private func endLocked(_ run: Run) {
        guard current === run else { return }
        current = nil
        run.workers.forEach { $0.stop() }
        if let end = run.checks?.end { DispatchQueue.main.async(execute: end) }
    }

    /// 🔼 ← or the ✕ while an answer is coming or being checked: drop all of
    /// it. True when there was one.
    @discardableResult
    func cancel() -> Bool { queue.sync { cancelLocked() } }

    private func cancelLocked() -> Bool {
        guard let run = current else { return false }
        current = nil
        run.cancelled = true
        for w in run.workers {
            w.onResult = nil
            w.onText = nil
            w.stop()
        }
        return true
    }

    /// One `claude -p` speaking stream-json both ways. Not private since
    /// 2026-10-22: the dictation editor (`DictationEditor`) keeps one too.
    final class Worker {
        private let process = Process()
        private let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        private var buffer = Data()
        private var text = ""
        private var errText = ""
        private let lock = NSLock()
        var onText: ((String) -> Void)?
        var onResult: ((String?, String?) -> Void)?
        var onExit: ((Worker) -> Void)?
        /// The model id the process says it runs (`claude-opus-5-5`), from its init line.
        private(set) var servedModel: String?

        var alive: Bool { process.isRunning }
        var stderrTail: String {
            lock.lock(); defer { lock.unlock() }
            let t = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "no stderr" : String(t.suffix(200))
        }

        init(model: String, effort: String, prompt: String, tools: String = "") throws {
            guard let claude = QuickAsk.claudePath else {
                throw NSError(domain: "QuickAsk", code: 1, userInfo: [NSLocalizedDescriptionKey: "claude not found"])
            }
            let dir = Outbox.home.appendingPathComponent("quick")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            process.executableURL = URL(fileURLWithPath: claude)
            // An empty effort is left to the model — Haiku takes none.
            process.arguments = ["-p", "--model", model] + (effort.isEmpty ? [] : ["--effort", effort]) + [
                                 "--input-format", "stream-json", "--output-format", "stream-json",
                                 "--verbose", "--include-partial-messages", "--no-session-persistence",
                                 "--tools", tools, "--strict-mcp-config", "--setting-sources", "",
                                 "--system-prompt", prompt]
            // -p has no one to ask: the tools it is given are allowed.
            if !tools.isEmpty { process.arguments! += ["--allowedTools", tools] }
            process.currentDirectoryURL = dir
            var env = ProcessInfo.processInfo.environment
            // Not a session of the terminal this app was started from.
            for k in env.keys where k.hasPrefix("CLAUDE_CODE_") || k == "CLAUDECODE" { env[k] = nil }
            process.environment = env
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h.availableData) }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
                let d = h.availableData
                guard let self, !d.isEmpty else { return }
                self.lock.lock(); self.errText += String(decoding: d, as: UTF8.self); self.lock.unlock()
            }
            process.terminationHandler = { [weak self] _ in
                guard let self else { return }
                self.stdout.fileHandleForReading.readabilityHandler = nil
                self.stderr.fileHandleForReading.readabilityHandler = nil
                self.onExit?(self)
            }
            try process.run()
        }

        /// `content` is the question's text, or its content blocks (`QuickAsk.content`).
        func send(_ content: Any) {
            let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content]]
            guard var data = try? JSONSerialization.data(withJSONObject: line) else { return }
            data.append(0x0A)
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }

        func stop() {
            onExit = nil
            // A late answer from a stopped process reaches no one (review 2026-10-22).
            onResult = nil
            onText = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
        }

        private func read(_ data: Data) {
            guard !data.isEmpty else { return }
            buffer.append(data)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                handle(obj)
            }
        }

        private func handle(_ e: [String: Any]) {
            switch e["type"] as? String {
            case "system":
                if e["subtype"] as? String == "init" { servedModel = e["model"] as? String }
            case "stream_event":
                guard let ev = e["event"] as? [String: Any], ev["type"] as? String == "content_block_delta",
                      let d = ev["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                      let t = d["text"] as? String else { return }
                text += t
                onText?(text)
            case "result":
                let isError = e["is_error"] as? Bool ?? false
                let result = (e["result"] as? String) ?? text
                // The next message starts its own text — a process kept for many
                // (`DictationEditor`) would otherwise stream every answer onto the last.
                let streamed = text
                text = ""
                if isError { onResult?(nil, result.isEmpty ? "the quick model failed" : result) }
                else { onResult?(result.isEmpty ? streamed : result, nil) }
            default:
                return
            }
        }
    }
}
