import Foundation
import Network

/// One element Victor pointed at in a web page — a single ⌘-click in Chrome.
///
/// The whole reason this exists: "make *this* button blue" is a sentence the
/// agent cannot act on. A CSS path is the same sentence with the pronoun
/// resolved.
extension ElementPick {
    /// **The whole of it, for the middle of his sentence** — Victor's own mock,
    /// 2026-09-14: `(selected DOM element: body > table > th, with text:
    /// "Header1" in page "https://interact.victorrentea.ro")`.
    ///
    /// Three short facts and no lookup: the selector that resolves it, what it
    /// said, and where. The parentheses are added by `ShotMarker.resolve`, which
    /// owns the punctuation of every inline marker.
    var inlineDescription: String {
        var out = "selected DOM element: \(path)"
        if let text = text, !text.isEmpty {
            out += ", with text: \"\(text)\""
        }
        if let url = url, !url.isEmpty { out += " in page \"\(url)\"" }
        return out
    }
}

struct ElementPick {
    /// **Which spoken marker names this one**, when it was picked during a
    /// dictation and the relay said one out loud — see `ShotMarker`. Nil for a
    /// pick that arrived before the sentence, past the marker ceiling, or with
    /// the markers off; those keep their line in the clause underneath instead.
    var marker: Int?

    /// When he clicked. Absolute, because a pick can happen before the dictation
    /// it belongs to has even started — see `ElementPicker.stamp`.
    let at: Date
    /// The identifying payload: a selector that resolves to exactly this element.
    let path: String
    let tag: String
    /// Its visible text, trimmed — what he would have called it out loud, and
    /// since 2026-09-13 what it actually **said**: up to `textLimit` characters
    /// of `innerText` rather than the 160 that were only ever enough to
    /// recognise a button by.
    let text: String?
    /// How long that text was before it was cut off, or nil when nothing was.
    ///
    /// Measured in the page, before the slice — the extension is the only place
    /// that can still see the whole thing. The envelope turns it into
    /// `(truncated, N chars)`, which is the difference between a quotation that
    /// ends and one that merely stops.
    let textChars: Int?
    /// `aria-label` / `alt` / `title`, for the elements that have no text at all
    /// (icon buttons are the whole reason this field is here).
    let label: String?
    let href: String?
    let url: String?
    let title: String?
    /// The iframe chain, when the element is not in the top document. nil is the
    /// common case and prints nothing.
    let frame: String?

    /// **Where he dragged it to**, when the ⌘⇧ gesture ended in a drag rather
    /// than a click — the element's top-left corner in **page** coordinates,
    /// before and after.
    ///
    /// Nothing in the page moves: the extension drags an outline of the element
    /// and puts the two corners in the message, which is the whole feature.
    /// Victor's ask, 2026-09-09: *"să capturăm poziția originală și coordonatele
    /// … dragul să se ducă translucent, doar chenarul … și să transmită în text
    /// unde sunt noile coordonate ale acelui element"*.
    ///
    /// **Page coordinates and not viewport ones.** A viewport corner is a fact
    /// about how far the page happened to be scrolled at the instant of the
    /// drag, which is exactly the thing that has changed by the time an agent
    /// reads it; a page corner is where the element sits in the document, which
    /// is what a rule that moves it would be written against.
    struct Move {
        let from: (x: Int, y: Int)
        let to: (x: Int, y: Int)
    }
    let move: Move?

    /// What the overlay shows — the last two steps of the path.
    ///
    /// The full selector is often a paragraph, and the head of it is the part he
    /// already knows (it is the page he is looking at). What identifies the thing
    /// under his finger is the tail.
    var short: String {
        let steps = path.components(separatedBy: " > ").filter { !$0.isEmpty }
        let tail = steps.suffix(2).joined(separator: " > ")
        return tail.isEmpty ? tag : tail
    }

    /// The outbox shape. `since` is the moment the dictation opened, and is what
    /// turns this pick's absolute `at` into `where in the sentence` — negative
    /// included, which is the ordinary order rather than an oddity: he finds the
    /// thing first and then says what to do with it.
    ///
    /// A number of seconds and not the `m:ss` the line renders: the string is for
    /// reading, and anything that has to compare two picks would be parsing it
    /// back. nil `since` (a pick with no dictation behind it) writes no key at
    /// all rather than a zero that would read as *the instant he started*.
    func json(since: Date?) -> [String: Any] {
        var obj = json
        if let since = since { obj["at"] = Int(at.timeIntervalSince(since).rounded()) }
        return obj
    }

    var json: [String: Any] {
        var obj: [String: Any] = ["path": path, "tag": tag]
        if let text = text, !text.isEmpty { obj["text"] = text }
        if let chars = textChars { obj["textChars"] = chars }
        if let label = label, !label.isEmpty { obj["label"] = label }
        if let href = href, !href.isEmpty { obj["href"] = href }
        if let url = url, !url.isEmpty { obj["url"] = url }
        if let title = title, !title.isEmpty { obj["title"] = title }
        if let frame = frame, !frame.isEmpty { obj["frame"] = frame }
        if let move = move {
            obj["move"] = ["from": ["x": move.from.x, "y": move.from.y],
                           "to": ["x": move.to.x, "y": move.to.y]]
        }
        return obj
    }

    init(at: Date, path: String, tag: String, text: String? = nil, textChars: Int? = nil,
         label: String? = nil,
         href: String? = nil, url: String? = nil, title: String? = nil, frame: String? = nil,
         move: Move? = nil) {
        self.at = at; self.path = path; self.tag = tag; self.text = text
        self.textChars = textChars; self.label = label
        self.href = href; self.url = url; self.title = title; self.frame = frame
        self.move = move
    }

    /// **2000 characters of what the element said** (2026-09-13). It was 160,
    /// which is a label and not a reading: the thing he ⌘⇧-clicks is as often an
    /// error box, a table row or a paragraph as it is a button, and those were
    /// arriving cut off before they said anything. The ceiling is still a
    /// ceiling, because a `<body>` picked by accident is a whole page, and a
    /// whole page pasted into a prompt is the failure a cap exists for.
    /// `chrome-extension/inspect.js` slices at the same number; this is the
    /// guard, since the page is hostile input and the extension is not the only
    /// thing that can POST to `/pick`.
    static let textLimit = 2000

    init?(json: [String: Any]) {
        guard let path = (json["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        self.at = Date()
        self.path = path
        self.tag = (json["tag"] as? String) ?? "?"
        let text = ElementPick.clamp(json["text"] as? String, ElementPick.textLimit)
        self.text = text
        // Believed only when it is bigger than what arrived — a page that claims
        // its 12-character label was truncated from nine would put
        // `(truncated, 9 chars)` in the prompt.
        let claimed = (json["textChars"] as? NSNumber)?.intValue ?? 0
        self.textChars = claimed > (text?.count ?? 0) ? claimed : nil
        self.label = ElementPick.clamp(json["label"] as? String, 120)
        self.href = ElementPick.clamp(json["href"] as? String, 400)
        self.url = ElementPick.clamp(json["url"] as? String, 400)
        self.title = ElementPick.clamp(json["title"] as? String, 200)
        self.frame = ElementPick.clamp(json["frame"] as? String, 200)
        self.move = ElementPick.move(json["move"])
    }

    /// The drag, or nil — and nil for anything malformed rather than a corner at
    /// the origin. The page is hostile input, and a `move` that half-parsed
    /// would put `0,0` into the message as if he had dropped it there.
    private static func move(_ raw: Any?) -> Move? {
        guard let obj = raw as? [String: Any],
              let from = corner(obj["from"]), let to = corner(obj["to"]) else { return nil }
        return Move(from: from, to: to)
    }

    private static func corner(_ raw: Any?) -> (x: Int, y: Int)? {
        guard let obj = raw as? [String: Any],
              let x = (obj["x"] as? NSNumber)?.doubleValue,
              let y = (obj["y"] as? NSNumber)?.doubleValue,
              x.isFinite, y.isFinite else { return nil }
        return (Int(x.rounded()), Int(y.rounded()))
    }

    /// The page is hostile input: a `text` of a megabyte would ride into the
    /// prompt and into the outbox untouched.
    private static func clamp(_ s: String?, _ limit: Int) -> String? {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        s = s.split(whereSeparator: { $0.isNewline || $0 == "\t" })
             .joined(separator: " ")
        return s.count <= limit ? s : String(s.prefix(limit)) + "…"
    }
}

/// The loopback endpoint the Chrome extension hands its picks to.
///
/// **Why an extension and not the DevTools protocol.** CDP is the obvious answer
/// and it is the wrong one here: since Chrome 136 `--remote-debugging-port` is
/// refused on the default profile, so reaching Victor's actual browser — his
/// tabs, his logins, the page he is actually looking at — would mean relaunching
/// it against a throwaway `--user-data-dir`. An extension needs no flags, no
/// relaunch and no second profile.
///
/// It also removes the hardest part of the job. Driving this from macOS means
/// mapping screen points into the page (window origin, the height of the browser
/// chrome, page zoom, device pixel ratio) and then mapping the element's box back
/// out to draw a rectangle around it — arithmetic that is wrong by a few pixels
/// on a good day and silently wrong after a zoom. Inside the page there is no
/// mapping at all: `elementFromPoint` and `getBoundingClientRect` are already in
/// the coordinate system the highlight is drawn in.
///
/// So the relay's side of this is only a mailbox. The inspector — the outline,
/// the label, the ⌘ gate, the swallowed click — all lives in `chrome-extension/`.
final class ElementPicker {

    /// A pick just arrived. Called on the listener queue, never the main thread.
    var onPick: ((ElementPick) -> Void)?

    /// Point the relay at the terminal that is in front **right now**, and
    /// describe what it landed on. Called on the listener queue.
    ///
    /// This is the one endpoint that is not about Chrome, and it is here rather
    /// than behind a listener of its own because there is nothing to gain from a
    /// second one: a port scheme already exists, several relays already share it
    /// by taking the first free one, and a second scheme would mean a second set
    /// of ports for a caller to guess between. What this class actually is, and
    /// has been since the second endpoint, is the relay's loopback control
    /// surface; the picker is its first tenant, not its purpose.
    var onBind: (() -> [String: Any]?)?
    /// Bind a **named** tty rather than whatever is in front — `POST /bind`
    /// with `{"tty": "ttys004"}`.
    ///
    /// It exists for the one caller that knows which session it means and
    /// cannot point at it: the build script, which puts the binding back after
    /// it has replaced the app underneath it. Victor's rule, 2026-09-09 —
    /// restarting while a terminal is bound is fine, *"ideal ar fi să-l re-legi
    /// la același terminal automat"* — and the frontmost window at the end of a
    /// build is whatever the build was watched in, which is exactly not it.
    var onBindTTY: ((String) -> [String: Any]?)?
    var onUnbind: (() -> Void)?
    /// The current binding, for `GET /target` — so a caller can ask without
    /// changing anything.
    var describeTarget: (() -> [String: Any]?)?

    /// Open a dictation the way the microphone coming on does.
    /// `{"clock": true}` also installs a **wall-clock marker clock** for the
    /// run: with no microphone open there is no recording for a press to be an
    /// offset into, so every cue is dropped and every token ends up in the
    /// footer. Told to, the app measures the press against the moment the
    /// dictation opened instead — which is what the recorder's own clock would
    /// have said — and the placement `ShotMarker.place` does becomes reachable
    /// from a desk. The only way to see a *whole* envelope without talking.
    var onTestDictationStart: ((Bool) -> Void)?
    /// `POST /test/halo {"style": "milkdrop87", "step": 1, "demo": 6, "opts": {...}}` —
    /// pick a halo (or step through them), preview it on the clip for `demo`
    /// seconds, with per-run preset options; answers what is now current.
    var onTestHalo: (([String: Any]) -> [String: Any])?

    /// **The wheel drag, without the wheel** — `POST /test/area`
    /// `{"x": …, "y": …, "w": …, "h": …}` in global Cocoa points (2026-09-19).
    ///
    /// The one gesture in this app that needs a *held middle button and a hand
    /// moving*: `POST /test/gesture` posts chords and cannot drag, and the
    /// overlay's own selection is driven by events the tap swallows. So the
    /// three files a drag produces — the display, its 800 px copy and the
    /// unscaled cut-out — were only ever checkable by making the gesture. This
    /// enters at `fileArea`, below the crop UI and above everything that names,
    /// cuts, attaches and counts, which is the part worth asserting.
    /// The second rect is the ⇧-drag's destination (`"to": {x, y, w, h}`).
    var onTestArea: ((NSRect?, NSRect?) -> [String: Any])?

    /// A fabricated transcript, entering where a real one does.
    /// **A fabricated transcript, optionally with the timings a recogniser
    /// would have returned** (`words`, 2026-09-19). Without them the sentence
    /// enters exactly as it always did and every token is listed in the footer;
    /// with them `ShotMarker.place` runs for real and the tokens stand where the
    /// presses fell — which is the only way to see a *complete* envelope from a
    /// desk, microphone or no microphone.
    var onTestDictation: ((String, [TimedWord]) -> Void)?
    /// …and the same thing for the ⇧-wheel spawn: `POST /test/spawn`.
    /// **A highlight, filed as though he had made it** — `POST /test/selection`
    /// `{"text": …}` (2026-09-13).
    ///
    /// The selection is the one attachment with no desk-reachable route into it.
    /// Everything else on the envelope has one — a shot, a pick, the words
    /// themselves — but a highlight is read off the screen with Accessibility or
    /// a ⌘C, so asserting on how the envelope renders one meant genuinely
    /// selecting text in another app by hand, in the middle of a dictation, and
    /// then reading the outbox. Which is to say it was never asserted.
    ///
    /// It enters at `fileSelection`, the same door the watcher and the shutter
    /// both come through, so the offset, the window reading, the frozen-slot
    /// rule and the *already carried* skip all run as they do for his hand. What
    /// it fakes is the **reading**, and nothing else.
    var onTestSelection: ((String) -> [String: Any]?)?

    var onTestSpawn: ((String) -> Void)?
    /// `POST /test/spawn-folders` — put the folder menu up on its own.
    ///
    /// It cannot ride `/test/spawn`, which enters *below* the microphone with a
    /// finished transcript: the menu belongs to the three seconds after a spawn
    /// dictation opens, and that is a stretch of time no fabricated transcript
    /// passes through. Without this the menu is reachable only by holding a
    /// mouse button — so its geometry, its fade and the fact that a row can be
    /// clicked at all are unverifiable at a desk.
    var onTestSpawnFolders: (() -> Void)?
    /// `POST /test/replace-wispr` — turn the mode on or off from a script. The
    /// mode is otherwise reachable only by clicking a menu row, which is the one
    /// input nothing at a desk can produce; without this, the whole
    /// forward-button path is untestable.
    var onTestReplaceWispr: ((Bool) -> Void)?

    /// `POST /test/wispr` `{"on": true}` — pretend Wispr Flow just opened (or
    /// closed) the microphone.
    ///
    /// `WisprWatch` reads one CoreAudio boolean about *another app's* process,
    /// and there is no way to make that boolean true from a desk without
    /// actually dictating into Wispr Flow. Everything hanging off it — the ⚡
    /// ring, the inactivity chevrons, the ✕ that now cancels — was therefore
    /// only ever exercised by talking, which is how a crash in the chevrons
    /// survived a day of testing. This enters at exactly the point the watcher's
    /// edge does, so a pass here is a pass for a real Wispr dictation.
    var onTestWispr: ((Bool) -> Void)?

    /// `POST /test/wispr {"hotkey": true}` — Wispr's *start gesture*, one step
    /// earlier than its microphone. It cannot be reached any other way at a
    /// desk: the real path is `HotkeyTap`'s event tap, which needs an
    /// Accessibility grant a `.build/debug` binary does not have.
    var onTestWisprHotkey: (() -> Void)?

    /// `POST /test/wispr {"historyRoute": true}` — make Wispr's `History` row the
    /// **delivery** rather than the late fallback behind `pasteGrace`. See
    /// `WisprFlowSource.historyIsTheRoute`; the candidate wrap reads the row and
    /// never waits for a ⌘V.
    var onTestHistoryRoute: ((Bool) -> Void)?

    /// `POST /test/firewall` `{"on": bool}` (optional) — flip the Wispr firewall
    /// at runtime, and **prove the tap is alive** either way: the answer carries
    /// the canary's verdict, so a harness can ask *would a ⌘V be dropped right
    /// now* rather than *does the app think so*. See `HotkeyTap.proveAlive`.
    var onTestFirewall: ((Bool?) -> [String: Any])?

    /// `POST /test/wispr-state/simulate` `{"steps": [...]}` — run a scripted
    /// sequence of inputs through a **fresh** `WisprState` and answer with the
    /// transitions it made.
    ///
    /// This is the unit test, and it is a route because the package has no test
    /// target and an `executableTarget` is not one an XCTest bundle can import
    /// without `main.swift`'s top-level code fighting it. What it buys is the
    /// thing a state machine most needs and this app could least do: assert that
    /// a poll at 300 ms and a notification at 5 s produce **one** `listening`
    /// transition with two lags, with no Wispr, no microphone and no waiting.
    var onTestWisprStateSimulate: (([[String: Any]]) -> [String: Any])?

    /// `POST /test/shot-marker` — **the marker's unit test, both halves.**
    ///
    /// `{"text": …, "available": [1, 2]}` runs the written half: the rewrite that
    /// turns the words Wispr heard back into `[shot N]`, with `available` standing
    /// in for the pictures that are really attached. `{"play": 2}` runs the spoken
    /// half into the Loopback device, so *is the sound reaching Wispr's ear* is a
    /// question answerable from a desk with nothing dictated.
    ///
    /// A route and not an XCTest for `onTestWisprStateSimulate`'s reason: the
    /// package is one `executableTarget` with a `main.swift` in it. It touches
    /// nothing in the running relay. → `ShotMarker`
    var onTestShotMarker: (([String: Any]) -> [String: Any])?

    /// `POST /test/bridge` `{"on": …}` — `AudioBridge.isEnabled`, flipped without
    /// a restart because an installed app does not inherit a shell's environment
    /// and this is a switch to try beside him with Loopback's window open.
    var onTestBridge: ((Bool) -> [String: Any])?

    /// `POST /test/wispr-scratchpad` `{"down"|"up"|"tap": true}` — Wispr's
    /// *Open Scratchpad* chord, and the one chord this app has to be able to
    /// **hold**. See `HotkeyTap.postWisprScratchpad`.
    var onTestScratchpad: ((ScratchpadCommand) -> [String: Any])?

    /// `GET /test/wispr-notes` / `POST /test/wispr-notes {"since": <unix s>}` —
    /// Wispr Flow's **Scratchpad**, read-only (`WisprNotes`). The GET is the
    /// baseline a run takes before it holds the chord; the POST is the delivery
    /// read afterwards, and answers `{"note": null}` when nothing was written
    /// since. Not wired to any gesture: this is the reading half of a wrap whose
    /// other half is still `POST /test/wispr-scratchpad`.
    var onTestWisprNotes: ((TimeInterval?) -> [String: Any])?

    /// `POST /test/wrap-mode` `{"mode": "scratchpad"|"sink"|"off"|"auto"}` — pick
    /// how the relay takes Wispr's words, for one run. `auto` hands the decision
    /// back to the tick and to Wispr's own configuration.
    ///
    /// It exists because the three modes are three different *relationships with
    /// another app* — hold a key it offers, take the keyboard for a moment, or
    /// stand back — and the loop has to be able to drive all three against a real
    /// Wispr without a menu click and without a rebuild.
    var onTestWrapMode: ((String) -> [String: Any])?

    /// `POST /test/scratchpad/park` — move Wispr's Scratchpad window to the
    /// corner it is supposed to live in, and say where it ended up. See
    /// `WisprScratchpad.park`; the wrap does it by itself on every open that is
    /// not already there, and this is the way to make it happen on demand.
    var onTestScratchpadPark: (() -> [String: Any])?

    /// `POST /test/key-trace` `{"on": true}` — log every keyboard event the tap
    /// sees and the decision it made about it (keycode and posting process only,
    /// never a character). The same switch as `WT_KEY_TRACE=1`, reachable at
    /// runtime because an installed app does not inherit a shell's environment.
    var onTestKeyTrace: ((Bool) -> [String: Any])?

    /// `POST /test/ax-insert` `{"on": true}` — deliver printable keystrokes
    /// through `AXSelectedText` on its own queue rather than re-posting them.
    /// See `HotkeyTap.axInsert`.
    var onTestAXInsert: ((Bool) -> [String: Any])?

    /// `POST /test/key-guard` `{"on": true}` — arm or disarm the keyboard guard
    /// itself. See `HotkeyTap.redirectEnabled`.
    var onTestKeyGuard: ((Bool) -> [String: Any])?

    enum ScratchpadCommand: String {
        /// Press and keep it pressed — per Wispr's docs, push-to-talk into its
        /// own Scratchpad note.
        case down
        case up
        /// Press and release — opens or closes the Scratchpad window.
        case tap
    }

    /// `POST /test/cancel` — the ✕'s new meaning: kill the dictation in flight,
    /// whichever app is holding the microphone.
    /// **The real chord on the wire** — `POST /test/wispr-handsfree` posts
    /// Wispr Flow's own `fn ⌃ Space` through `HotkeyTap.postWisprHandsFree`, the
    /// same call the forward button makes. Unlike `/test/wispr` this does not
    /// fake anything: a real Wispr dictation starts, and the relay learns about
    /// it exactly as it learns about one Victor started himself.
    ///
    /// **Only useful from the installed build.** A `.build/debug` binary has no
    /// Accessibility grant of its own, so `CGEventPost` does nothing and does it
    /// silently — see `tools/wispr-test.sh`, which checks before it runs.
    ///
    /// - Parameter hand: `{"hand": true}` — post it **as though Victor had
    ///   pressed it**: ring only, nothing swallowed, nothing delivered. Without
    ///   it the route stays the transcribe primitive, which the relay does
    ///   intercept; the two were one call until the adversarial round found the
    ///   relay re-delivering a sentence it had promised only to watch.
    var onTestWisprHandsFree: ((Bool) -> Void)?

    /// `POST /test/input {"name": "…"}` — point the **system's** default input at
    /// a device, and say what it was before.
    ///
    /// The one piece of the end-to-end harness that cannot live in the script:
    /// `SwitchAudioSource` is not installed on this Mac and the CoreAudio call
    /// wants a `CFString` and a device id, which this app already has helpers
    /// for (`InputDevice`). With Wispr's microphone set to *Auto-detect* it is
    /// what lets a test play a WAV into a virtual device and have Wispr hear it.
    var onTestInputDevice: ((String) -> [String: Any])?

    /// **Pick the microphone the way the menu does** — `POST /test/mic`. An
    /// empty id reports without changing anything.
    var onTestMic: ((String) -> [String: Any])?

    /// One pulse of the `⌘⇧P` hint under the pointer — see `PasteHint`.
    var onTestPasteHint: (() -> Void)?
    /// `POST /test/live-caption` `{"text": "…"}` — the subtitle band's words as if
    /// the live recogniser had just heard them; `{"on": false}` closes the band.
    var onTestLiveCaption: (([String: Any]) -> Void)?
    /// `POST /test/local-fallback {"wav": path}` — the local model standing in
    /// for a failed engine, on that file; answers the result, delivers nothing.
    var onTestLocalFallback: ((String) -> [String: Any])?
    var onTestCancelDictation: (() -> Void)?

    /// `POST /test/recover` — the menu's **Recover Cancelled Dictation**, which
    /// is otherwise reachable only by clicking a row.
    var onTestRecover: (() -> Void)?

    /// `POST /test/resume-session` `{"session": "<uuid>", "directory": "…"}` —
    /// what ⏎ does on a panel row whose terminal is closed.
    ///
    /// The panel's own ⏎ needs a window that has taken the keyboard, so the one
    /// gesture that opens a session again is otherwise only reachable by hand.
    var onTestResumeSession: ((_ session: String, _ directory: String) -> Void)?

    /// `POST /test/rebind-panel` `{"query": "…"}` — put the *Rebind to…* panel up
    /// in the middle of the screen, optionally with the field already filled in.
    ///
    /// Same reason as the two above, plus one of its own: the panel spends a
    /// second reading transcripts and then draws what it found, and neither the
    /// search nor the rows it produces can be reached without clicking a menu
    /// row and typing into a window that takes the keyboard away from whatever
    /// is asking.
    var onTestRebindPanel: ((String) -> Void)?

    /// Ask every connected Chrome extension to reload itself; the answer is how
    /// many were listening. Wired to `MusicBridge.reloadExtensions`.
    var onReloadExtension: (() -> Int)?

    /// `POST /test/about` — put the About panel up and **answer its frame**.
    ///
    /// It exists because of the way that panel shipped broken on 2026-09-22: it
    /// was created, it was `onscreen`, it logged its own line, and it was
    /// **0 × 0**. Nothing inside the process was wrong, and the snapshot harness
    /// that was supposed to review it forced the document's frame before
    /// photographing — i.e. it overwrote the one number that was broken and
    /// rendered a perfect picture of a window that did not exist at that size.
    ///
    /// So this route answers the *window server's* view: `w` and `h` of the
    /// panel's own frame. A panel that is up and unreadable and a panel that is
    /// correct differ by those two numbers and by nothing a screenshot can show.
    var onTestAbout: (() -> [String: Any])?

    /// `POST /test/gesture` `{"name": "forward-left"}` — post the ⌃⌥⌘F-key chord
    /// Logi Options+ makes for one mouse gesture, so the gesture branch of
    /// `HotkeyTap` runs exactly as it does for Victor's hand.
    ///
    /// It is the missing half of the harness: `/test/wispr-handsfree` posts the
    /// chord that starts a *dictation*, and every other route enters below the
    /// tap, so the ten gestures the side buttons carry — the cancel, the spawn,
    /// the unbind, the caret click — were reachable only by putting a hand on
    /// the mouse. Both failures of 2026-09-13 were gesture-shaped (a second
    /// forward click landing inside a settle), and neither could be reproduced
    /// without one.
    ///
    /// Answers the chord that went out, or nil for a name nobody knows — the
    /// route turns that into a 400 carrying the whole vocabulary.
    var onTestGesture: ((String) -> [String: Any]?)?

    /// `GET /test/state` — everything an assertion needs about the dictation in
    /// flight, in one object and from the state the app is already keeping.
    ///
    /// Every route above changes something; this is the only one that reads. The
    /// two failures of 2026-09-13 were both *the app believed something the
    /// screen did not show* — a swallow window that was never armed, a settle a
    /// second click walked into — and answering that from `relay.log` means
    /// parsing prose after the fact.
    var describeState: (() -> [String: Any])?

    /// `POST /test/sink` `{"on": true}` / `GET /test/sink` / `POST
    /// /test/sink/clear` — the relay's own window for catching text that leaked
    /// into the front app, and by which route. See `WisprSink`.
    ///
    /// `{"key": true}` and `{"restore": true}` drive the two halves of the focus
    /// separately, and they are separate because **nobody yet knows whether
    /// Wispr Flow picks the app it will insert into at the chord or at insertion
    /// time.** Hold the keyboard from the start of the dictation, or take it
    /// only at the stop gesture and give it back a moment later — the two give
    /// opposite instructions and only a measurement can choose.
    /// Answers nil when it did as it was asked, or a refusal to hand back as a
    /// 409 — `{"key": true}` is refused while a Scratchpad dictation is in
    /// flight, because the sink taking the key window is the one thing that can
    /// make Wispr dictate somewhere other than its own note.
    var onTestSink: ((SinkCommand) -> [String: Any]?)?
    var describeSink: (() -> [String: Any])?
    var onTestSinkClear: (() -> Void)?

    /// What `POST /test/sink` was asked to do.
    enum SinkCommand: Equatable {
        case open
        case close
        /// Take the keyboard, remembering whose it was.
        case key
        /// Give it back, leaving the window open.
        case restore
    }

    /// Which recogniser is loaded and whether it is up — for a test that has to
    /// wait out a ten-second model load before it says anything.
    var describeEngine: (() -> [String: Any])?
    /// `POST /engine` `{"id": "whisper"|"eleven"|"eleven-live"|"wispr"}` — the menu's pick,
    /// for a harness that has to run a scenario on a given engine without a
    /// click. Refused mid-sentence exactly as the menu is; the answer is
    /// `/engine` afterwards, so the caller reads what is actually running.
    var onPickEngine: ((String) -> Void)?

    /// **A dictation is running and forwarding is on** — the only window in which ⌘ in
    /// Chrome belongs to the relay. Outside it, `/ping` answers with a refusal and
    /// the extension reads a refusal exactly like no relay at all, so ⌘ goes
    /// straight back to being Chrome's ⌘.
    ///
    /// Gated on the dictation for the same reason mouse 4 is (`HotkeyTap.dictating`)
    /// and not one of its own: ⌘-click opens a link in a new tab and Victor uses it
    /// all day. Borrowing a gesture that load-bearing is only defensible while the
    /// window is narrow and *visible* — the recording row is on screen saying the
    /// gesture is live, and both appear and disappear together. A picker armed
    /// around the clock would be a browser that intermittently stopped opening
    /// links, with nothing on screen to explain why.
    ///
    /// Written from the main thread, read on the listener queue, hence the lock —
    /// the same shape as `HotkeyTap.dictating`, and for the same reason.
    var dictating: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return dictatingFlag }
        set { stateLock.lock(); dictatingFlag = newValue; stateLock.unlock() }
    }
    private var dictatingFlag = false

    /// The two halves of `dictating`, kept apart for one reason: **so a refusal
    /// can say which one is missing.** `dictating` is `hasDestination &&
    /// listening`, and a false read of it used to be reported as the undivided
    /// "no", which left exactly one question standing — *was the terminal bound,
    /// or was I simply not recording?* Victor asked it in those words on
    /// 2026-09-09 (*"nu știu dacă [terminalul] aveam pornit"*), and nothing in
    /// the app or the extension could answer it.
    ///
    /// Under the same lock as `dictating` and written on the same edge, so the
    /// three can never disagree about the same instant.
    var listening: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return listeningFlag }
        set { stateLock.lock(); listeningFlag = newValue; stateLock.unlock() }
    }
    private var listeningFlag = false

    /// Is there anywhere for a dictation to go — a bound terminal, a pending
    /// spawn, or paste mode (`AppDelegate.hasDestination`).
    var bound: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return boundFlag }
        set { stateLock.lock(); boundFlag = newValue; stateLock.unlock() }
    }
    private var boundFlag = false

    private let stateLock = NSLock()

    /// The gesture names `POST /test/gesture` accepts, for the refusal to list.
    /// Filled by `AppDelegate` from `HotkeyTap`'s own table, so the two cannot
    /// disagree about what exists.
    var onTestGestureNames: [String] = []

    /// Tried in order. Several relays can be up at once (one per agent session),
    /// each takes the first free port, and the extension posts to all of them —
    /// which is the same shape as the outbox, where one dictation reaches whoever
    /// is listening.
    static let ports: [UInt16] = [8917, 8918, 8919]

    private(set) var port: UInt16?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.inspect")

    func start() { bind(0) }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    private func bind(_ index: Int) {
        guard index < Self.ports.count else {
            Log.error("no free inspect port in \(Self.ports) — ⌘-picking is off for this session")
            return
        }
        let candidate = Self.ports[index]
        guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { return bind(index + 1) }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false
        // Loopback only. This accepts JSON from anything that can reach it, and
        // the one thing that must never be true of it is that the network can.
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

        guard let listener = try? NWListener(using: params) else { return bind(index + 1) }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.port = candidate
                Log.info("inspect endpoint on 127.0.0.1:\(candidate) — ⌘-hold in Chrome to pick elements")
            case .failed:
                // Almost always another relay already holding it.
                listener.cancel()
                self.queue.async { self.bind(index + 1) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - The smallest HTTP server that will do

    private func serve(_ conn: NWConnection) {
        var buffer = Data()

        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
                guard let self = self else { return conn.cancel() }
                if let data = data { buffer.append(data) }

                if let request = Request(buffer) {
                    self.reply(to: request, on: conn)
                } else if isComplete || error != nil || buffer.count > 512 * 1024 {
                    conn.cancel()
                } else {
                    readMore()
                }
            }
        }

        conn.start(queue: queue)
        readMore()
    }

    private func reply(to request: Request, on conn: NWConnection) {
        switch (request.method, request.path) {
        // The extension asks this before it arms: with no relay running, ⌘ in
        // Chrome must go back to meaning exactly what Chrome says it means.
        case ("GET", "/ping"):
            guard dictating else { return respond(conn, 503, ["ok": false, "listening": false]) }
            respond(conn, 200, ["ok": true, "session": SessionLabel.value])

        // **Ungated, unlike `/ping` right above it — and that is the whole point
        // of it being a second route.** `/ping` answers *may I borrow ⌘⇧*, which
        // is true only inside a dictation; this one answers *is the app running*,
        // which the extension needs in order to decide whether opening the music
        // socket will be a connection or a red line on its Errors page. Asking
        // `/ping` for that conflated the two, and the socket that carries the
        // dictation window — and now the reload — was therefore only openable
        // *during* a dictation, i.e. after the edge it exists to deliver.
        case ("GET", "/up"):
            respond(conn, 200, ["ok": true, "session": SessionLabel.value,
                                "dictating": dictating, "listening": listening, "bound": bound])

        // Reload the unpacked Chrome extension, from the one place that can:
        // inside Chrome. `curl -X POST localhost:8917/chrome/reload` after an
        // edit to `inspect.js`, and the running content scripts are the new
        // ones on the next page load.
        case ("POST", "/chrome/reload"):
            let asked = onReloadExtension?() ?? 0
            respond(conn, asked > 0 ? 200 : 503,
                    ["ok": asked > 0, "asked": asked,
                     "error": asked > 0 ? "" : "no Chrome extension connected to the music bridge"])

        case ("POST", "/pick"):
            guard dictating else { return respond(conn, 503, ["ok": false, "listening": false]) }
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let pick = ElementPick(json: body) else {
                return respond(conn, 400, ["ok": false, "error": "expected a JSON object with a non-empty `path`"])
            }
            Log.info("🎯 picked \(pick.short)")
            onPick?(pick)
            respond(conn, 200, ["ok": true, "session": SessionLabel.value])

        // Bind / unbind / inspect the terminal a dictation gets typed into.
        //
        // **Not gated on `dictating`**, unlike everything above it: pointing the
        // relay at a terminal is something Victor does at rest, on his way into
        // a session, and a bind that only worked mid-sentence would be a bind he
        // could never make.
        case ("POST", "/bind"):
            // A named tty is a different question from "whatever is in front",
            // and it is never a toggle: the caller is restoring a binding, not
            // pointing at something, so finding that session already bound is a
            // success rather than a request to let go of it.
            if let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
               let tty = body["tty"] as? String, !tty.isEmpty {
                guard let described = onBindTTY?(tty) else {
                    return respond(conn, 409, ["ok": false, "error": "no terminal on \(tty)"])
                }
                return respond(conn, 200, ["ok": true].merging(described) { _, new in new })
            }
            guard let described = onBind?() else {
                return respond(conn, 409, ["ok": false, "error": "nothing bindable is in front"])
            }
            respond(conn, 200, ["ok": true].merging(described) { _, new in new })

        case ("POST", "/unbind"):
            onUnbind?()
            respond(conn, 200, ["ok": true, "bound": false])

        // Put a sentence through the whole dictation path without speaking one.
        //
        // Everything downstream of the microphone — the held prompt, the countdown, the
        // outbox line, the delivery into the bound terminal — is otherwise only
        // reachable by talking into a microphone, which makes the one part of
        // this app that can type into a live session the one part nobody can
        // test at their desk. It enters at exactly the point a real transcript
        // does, so a pass here is a pass for the real thing.
        // Open a dictation without talking — the other half of the pair below.
        // Shots are named by their offset into the dictation, and there is no
        // offset until something has started one, so without this the whole
        // naming scheme is only exercisable by talking.
        case ("POST", "/test/halo"):
            let body = ((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]) ?? [:]
            guard let handler = onTestHalo else { return respond(conn, 503, ["error": "no handler"]) }
            var answer: [String: Any] = [:]
            DispatchQueue.main.sync { answer = handler(body) }
            respond(conn, (answer["error"] == nil) ? 200 : 400, answer)

        case ("POST", "/test/dictation/start"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            onTestDictationStart?((body?["clock"] as? Bool) ?? false)
            respond(conn, 200, ["ok": true, "listening": true])

        // The wheel drag, without the wheel — see `onTestArea`.
        case ("POST", "/test/area"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let handler = onTestArea else { return respond(conn, 503, ["error": "no handler"]) }
            // **The rectangle is optional and the default is the handler's.**
            // A box in the middle of the main screen needs `NSScreen`, which is
            // AppKit and a main-thread question; this file is a socket listener
            // and asks neither. Nil means *pick one for me*.
            var rect: NSRect?
            if let x = body?["x"] as? Double, let y = body?["y"] as? Double,
               let w = body?["w"] as? Double, let h = body?["h"] as? Double {
                rect = NSRect(x: x, y: y, width: w, height: h)
            }
            var to: NSRect?
            if let t = body?["to"] as? [String: Any], let x = t["x"] as? Double, let y = t["y"] as? Double,
               let w = t["w"] as? Double, let h = t["h"] as? Double {
                to = NSRect(x: x, y: y, width: w, height: h)
            }
            respond(conn, 200, handler(rect, to))

        // Wispr Flow's microphone, faked — see `onTestWispr`.
        case ("POST", "/test/wispr"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            if let route = body?["historyRoute"] as? Bool {
                onTestHistoryRoute?(route)
                return respond(conn, 200, ["ok": true, "historyRoute": route])
            }
            if body?["hotkey"] as? Bool == true {
                onTestWisprHotkey?()
                return respond(conn, 200, ["ok": true, "hotkey": true])
            }
            let on = body?["on"] as? Bool ?? true
            onTestWispr?(on)
            respond(conn, 200, ["ok": true, "wispr": on])

        // **The microphone picker, from a shell** (2026-09-19) — the same call
        // the menu row makes, so the pick, the fallback and the chip's mark can
        // be asserted without photographing a menu. `{"id": "auto"|"xlr"|"mac"|
        // "rx"|"bose"}`; with no id it only reports. Reporting is `GET /engine`'s
        // `mic` block, which this answers with.
        case ("POST", "/test/mic"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let id = (body?["id"] as? String) ?? ""
            respond(conn, 200, ["ok": true].merging(onTestMic?(id) ?? [:]) { _, new in new })

        // The system's default input, for the end-to-end harness — see
        // `onTestInputDevice`. With no name it only reports.
        case ("POST", "/test/input"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let name = (body?["name"] as? String) ?? ""
            respond(conn, 200, ["ok": true].merging(onTestInputDevice?(name) ?? [:]) { _, new in new })

        // The real chord, for the end-to-end harness — see `onTestWisprHandsFree`.
        case ("POST", "/test/wispr-handsfree"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let hand = body?["hand"] as? Bool ?? false
            onTestWisprHandsFree?(hand)
            respond(conn, 200, ["ok": true, "posted": "fn ctrl space", "hand": hand])

        // **The `⌘⇧P` hint, without the loss that summons it.** It is under
        // two seconds long, at a fifth of an opacity, and it appears only at
        // the end of a caret dictation or at a cancelled prompt — which is to
        // say there is no way to look at it twice in a row without talking.
        case ("POST", "/test/paste-hint"):
            onTestPasteHint?()
            respond(conn, 200, ["ok": true])

        // **The `💬` caption without a microphone or a bill** — the ticker is
        // only reviewable if its words can be pushed from a desk, one at a time.
        case ("POST", "/test/local-fallback"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let wav = body?["wav"] as? String else {
                return respond(conn, 400, ["ok": false, "error": "wav required"])
            }
            respond(conn, 200, onTestLocalFallback?(wav) ?? ["ok": false])

        case ("POST", "/test/live-caption"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            onTestLiveCaption?(body)
            respond(conn, 200, ["ok": true])

        // The ✕'s cancel, from a desk — see `onTestCancelDictation`.
        case ("POST", "/test/cancel"):
            onTestCancelDictation?()
            respond(conn, 200, ["ok": true])

        // **The menu's undo for a cancel, from a desk.** The row is the only way
        // in, and a menu row is the one input nothing here can produce — the
        // same reason `/test/replace-wispr` exists one case down.
        case ("POST", "/test/recover"):
            onTestRecover?()
            respond(conn, 200, ["ok": true])

        // ⏎ on a closed session's row — see `onTestResumeSession`.
        case ("POST", "/test/resume-session"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let session = (body?["session"] as? String) ?? ""
            let directory = (body?["directory"] as? String) ?? ""
            guard !session.isEmpty, !directory.isEmpty else {
                return respond(conn, 400, ["ok": false,
                                           "error": "expected {\"session\": \"…\", \"directory\": \"…\"}"])
            }
            onTestResumeSession?(session, directory)
            respond(conn, 200, ["ok": true, "session": session, "directory": directory])

        // The search panel behind `Rebind to…` — see `onTestRebindPanel`.
        case ("POST", "/test/rebind-panel"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let query = body?["query"] as? String ?? ""
            onTestRebindPanel?(query)
            respond(conn, 200, ["ok": true, "query": query])

        // The mode behind the forward button — see `onTestReplaceWispr`.
        case ("POST", "/test/replace-wispr"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let on = body?["on"] as? Bool ?? true
            onTestReplaceWispr?(on)
            respond(conn, 200, ["ok": true, "replaceWispr": on])

        // The ⇧-wheel gesture's transcript, entering where a spoken one does.
        //
        // It needs a route of its own precisely because `/test/dictation` is
        // gated on a binding and this gesture is the one that is not — a spawn
        // is unreachable at a desk otherwise, and it is the path that opens a
        // window and starts a process.
        case ("POST", "/test/spawn"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let text = (body?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text = text, !text.isEmpty else {
                return respond(conn, 400, ["ok": false, "error": "expected {\"text\": \"…\"}"])
            }
            onTestSpawn?(text)
            respond(conn, 200, ["ok": true, "text": text])

        // The About panel, and the size it actually came up at — see
        // `onTestAbout`.
        case ("POST", "/test/about"):
            respond(conn, 200, ["ok": true].merging(onTestAbout?() ?? [:]) { _, new in new })

        // The three seconds of that gesture nothing else can reach — see
        // `onTestSpawnFolders`.
        case ("POST", "/test/spawn-folders"):
            onTestSpawnFolders?()
            respond(conn, 200, ["ok": true, "shown": true])

        // A highlight without a hand on the mouse — see `onTestSelection`.
        case ("POST", "/test/selection"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let text = (body?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text = text, !text.isEmpty else {
                return respond(conn, 400, ["ok": false, "error": "expected {\"text\": \"…\"}"])
            }
            guard let result = onTestSelection?(text) else {
                return respond(conn, 409, ["ok": false, "error": "no dictation is open"])
            }
            respond(conn, 200, result)

        case ("POST", "/test/dictation"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let text = (body?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text = text, !text.isEmpty else {
                return respond(conn, 400, ["ok": false, "error": "expected {\"text\": \"…\"}"])
            }
            let words: [TimedWord] = ((body?["words"] as? [[String: Any]]) ?? []).compactMap {
                guard let text = $0["text"] as? String,
                      let start = $0["start"] as? Double,
                      let end = $0["end"] as? Double else { return nil }
                return TimedWord(text: text, start: start, end: end,
                                 isSpacing: ($0["type"] as? String) == "spacing")
            }
            onTestDictation?(text, words)
            respond(conn, 200, ["ok": true, "text": text, "words": words.count])

        // One mouse gesture, posted as the chord Options+ makes for it — see
        // `onTestGesture`.
        case ("POST", "/test/gesture"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let name = ((body?["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let posted = onTestGesture?(name) else {
                return respond(conn, 400, ["ok": false,
                                           "error": "unknown gesture \(name.isEmpty ? "(none given)" : name)",
                                           "gestures": onTestGestureNames])
            }
            respond(conn, 200, ["ok": true].merging(posted) { _, new in new })

        // The state machine, run on a script — see `onTestWisprStateSimulate`.
        // `POST /test/bridge {"on": true｜false}` — carry his microphone to Wispr
        // through this app, or stop. See `AudioBridge`: it needs the physical
        // microphone removed as a direct source of the Loopback device first, or
        // his voice arrives twice. Takes effect at the next dictation.
        case ("POST", "/test/bridge"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let on = body?["on"] as? Bool else {
                return respond(conn, 400, ["ok": false, "error": "expected {\"on\": true｜false}"])
            }
            guard let result = onTestBridge?(on) else {
                return respond(conn, 503, ["ok": false, "error": "no handler"])
            }
            respond(conn, 200, ["ok": true].merging(result) { _, new in new })

        case ("POST", "/test/shot-marker"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let body = body,
                  body["text"] != nil || body["words"] != nil
                    || body["play"] != nil || body["splice"] != nil else {
                return respond(conn, 400, ["ok": false,
                                           "error": "expected {\"text\": …, \"available\": [1,2]}, {\"words\": […], \"cues\": […]}, {\"play\": 1} or {\"splice\": 1}"])
            }
            guard let result = onTestShotMarker?(body) else {
                return respond(conn, 503, ["ok": false, "error": "no handler"])
            }
            respond(conn, 200, ["ok": true].merging(result) { _, new in new })

        case ("POST", "/test/wispr-state/simulate"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let steps = (body?["steps"] as? [[String: Any]]) ?? []
            guard !steps.isEmpty else {
                return respond(conn, 400, ["ok": false,
                                           "error": "expected {\"steps\": [{\"input\": \"chord|stop|poll|notify|row|timeout\", …}]}"])
            }
            guard let result = onTestWisprStateSimulate?(steps) else {
                return respond(conn, 500, ["ok": false, "error": "no simulator wired"])
            }
            respond(conn, 200, ["ok": true].merging(result) { _, new in new })

        // The keyboard guard itself — see `onTestKeyGuard`.
        case ("POST", "/test/key-guard"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let on = body?["on"] as? Bool ?? true
            respond(conn, 200, ["ok": true].merging(onTestKeyGuard?(on) ?? [:]) { _, new in new })

        // How a redirected printable key is delivered — see `onTestAXInsert`.
        case ("POST", "/test/ax-insert"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let on = body?["on"] as? Bool ?? true
            respond(conn, 200, ["ok": true].merging(onTestAXInsert?(on) ?? [:]) { _, new in new })

        // Every keyboard event and its verdict — see `onTestKeyTrace`.
        case ("POST", "/test/key-trace"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let on = body?["on"] as? Bool ?? true
            respond(conn, 200, ["ok": true].merging(onTestKeyTrace?(on) ?? [:]) { _, new in new })

        // **Freeze the main thread on purpose** (2026-09-24) — the desk route
        // for `HotkeyTap`'s fail-open: `{"seconds": 6}` blocks main that long,
        // the tap should log `🧊 main thread silent` after 3 s, sample, and log
        // `🧊 main thread back` after. Capped at 20 s. Answers at once, before
        // the freeze starts — this handler is not on the main thread.
        case ("POST", "/test/stall"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let seconds = min(20, max(0, body?["seconds"] as? Double ?? 6))
            respond(conn, 200, ["ok": true, "seconds": seconds])
            DispatchQueue.main.async {
                Log.info("🧊 /test/stall: blocking the main thread for \(seconds) s")
                Thread.sleep(forTimeInterval: seconds)
            }

        // Park Wispr's Scratchpad window — see `onTestScratchpadPark`.
        case ("POST", "/test/scratchpad/park"):
            respond(conn, 200, ["ok": true].merging(onTestScratchpadPark?() ?? [:]) { _, new in new })

        // How the relay takes Wispr's words — see `onTestWrapMode`.
        case ("POST", "/test/firewall"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            respond(conn, 200, ["ok": true].merging(onTestFirewall?(body?["on"] as? Bool) ?? [:]) { _, new in new })

        case ("POST", "/test/wrap-mode"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let mode = ((body?["mode"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mode.isEmpty, let answered = onTestWrapMode?(mode) else {
                return respond(conn, 400, ["ok": false,
                                           "error": "expected {\"mode\": \"scratchpad\"|\"sink\"|\"off\"|\"auto\"}"])
            }
            let ok = answered["ok"] as? Bool ?? true
            respond(conn, ok ? 200 : 400, ["ok": ok].merging(answered) { _, new in new })

        // Wispr's Scratchpad note, read — see `onTestWisprNotes`.
        case ("GET", "/test/wispr-notes"):
            respond(conn, 200, ["ok": true].merging(onTestWisprNotes?(nil) ?? [:]) { _, new in new })

        case ("POST", "/test/wispr-notes"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let since = (body?["since"] as? Double) ?? (body?["since"] as? Int).map(Double.init)
            respond(conn, 200, ["ok": true].merging(onTestWisprNotes?(since) ?? [:]) { _, new in new })

        // Wispr's Scratchpad chord, held — see `onTestScratchpad`.
        case ("POST", "/test/wispr-scratchpad"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let command: ScratchpadCommand?
            if body?["down"] as? Bool == true { command = .down }
            else if body?["up"] as? Bool == true { command = .up }
            else if body?["tap"] as? Bool == true { command = .tap }
            else { command = nil }
            guard let command, let answered = onTestScratchpad?(command) else {
                return respond(conn, 400, ["ok": false,
                                           "error": "expected {\"down\": true} | {\"up\": true} | {\"tap\": true}"])
            }
            respond(conn, 200, ["ok": true].merging(answered) { _, new in new })

        // Everything an assertion needs, in one read — see `describeState`.
        case ("GET", "/test/state"):
            respond(conn, 200, ["ok": true].merging(describeState?() ?? [:]) { _, new in new })

        // The sink window — see `TestSink`.
        case ("POST", "/test/sink"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            // Checked before `on`, so `{"key": true}` on a sink already open is
            // not read as a second request to open it.
            if body?["key"] as? Bool == true {
                if let refusal = onTestSink?(.key) {
                    return respond(conn, 409, ["ok": false].merging(refusal) { _, new in new })
                }
                return respond(conn, 200, ["ok": true, "did": "key"])
            }
            if body?["restore"] as? Bool == true {
                _ = onTestSink?(.restore)
                return respond(conn, 200, ["ok": true, "did": "restore"])
            }
            let on = body?["on"] as? Bool ?? true
            _ = onTestSink?(on ? .open : .close)
            respond(conn, 200, ["ok": true, "open": on])

        case ("GET", "/test/sink"):
            respond(conn, 200, ["ok": true].merging(describeSink?() ?? [:]) { _, new in new })

        case ("POST", "/test/sink/clear"):
            onTestSinkClear?()
            respond(conn, 200, ["ok": true, "cleared": true])

        case ("GET", "/engine"):
            respond(conn, 200, ["ok": true].merging(describeEngine?() ?? [:]) { _, new in new })

        case ("POST", "/engine"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard let id = body?["id"] as? String, !id.isEmpty else {
                return respond(conn, 400, ["ok": false, "error": "id required"])
            }
            onPickEngine?(id)
            respond(conn, 200, ["ok": true].merging(describeEngine?() ?? [:]) { _, new in new })

        case ("GET", "/target"):
            guard let described = describeTarget?() else {
                return respond(conn, 200, ["ok": true, "bound": false, "session": SessionLabel.value])
            }
            respond(conn, 200, ["ok": true, "bound": true].merging(described) { _, new in new })

        // Chrome preflights the POST because the page's origin is not ours.
        case ("OPTIONS", _):
            respond(conn, 204, nil)

        default:
            respond(conn, 404, ["ok": false])
        }
    }

    private func respond(_ conn: NWConnection, _ status: Int, _ body: [String: Any]?) {
        let payload = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(payload.count)\r\n"
        // The POST arrives from whatever page Victor happens to be on, so the
        // browser will not let the extension read the answer without these.
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: content-type\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Access-Control-Max-Age: 86400\r\n"
        head += "Connection: close\r\n\r\n"

        var data = Data(head.utf8)
        data.append(payload)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 409: return "Conflict"
        case 503: return "Service Unavailable"
        default:  return "Not Found"
        }
    }

    /// A request is only a request once its body is all here — `nil` means "keep
    /// reading", which is the only signal the receive loop needs.
    private struct Request {
        let method: String
        let path: String
        let body: Data

        init?(_ buffer: Data) {
            let separator = Data("\r\n\r\n".utf8)
            guard let range = buffer.range(of: separator) else { return nil }
            let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
            var lines = head.components(separatedBy: "\r\n")
            let request = lines.removeFirst().components(separatedBy: " ")
            guard request.count >= 2 else { return nil }

            let length = lines.compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0

            let body = buffer[range.upperBound...]
            guard body.count >= length else { return nil }

            self.method = request[0].uppercased()
            // Query strings are not used, but a stray `?` must not turn /pick
            // into a 404.
            self.path = request[1].components(separatedBy: "?")[0]
            self.body = Data(body.prefix(length))
        }
    }
}
