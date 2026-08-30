import Foundation
import Network

/// One element Victor pointed at in a web page — a single ⌘-click in Chrome.
///
/// The whole reason this exists: "make *this* button blue" is a sentence the
/// agent cannot act on. A CSS path is the same sentence with the pronoun
/// resolved.
struct ElementPick {
    /// When he clicked. Absolute, because a pick can happen before the dictation
    /// it belongs to has even started — see `ElementPicker.stamp`.
    let at: Date
    /// The identifying payload: a selector that resolves to exactly this element.
    let path: String
    let tag: String
    /// Its visible text, trimmed — what he would have called it out loud.
    let text: String?
    /// `aria-label` / `alt` / `title`, for the elements that have no text at all
    /// (icon buttons are the whole reason this field is here).
    let label: String?
    let href: String?
    let url: String?
    let title: String?
    /// The iframe chain, when the element is not in the top document. nil is the
    /// common case and prints nothing.
    let frame: String?

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

    var json: [String: Any] {
        var obj: [String: Any] = ["path": path, "tag": tag]
        if let text = text, !text.isEmpty { obj["text"] = text }
        if let label = label, !label.isEmpty { obj["label"] = label }
        if let href = href, !href.isEmpty { obj["href"] = href }
        if let url = url, !url.isEmpty { obj["url"] = url }
        if let title = title, !title.isEmpty { obj["title"] = title }
        if let frame = frame, !frame.isEmpty { obj["frame"] = frame }
        return obj
    }

    init(at: Date, path: String, tag: String, text: String? = nil, label: String? = nil,
         href: String? = nil, url: String? = nil, title: String? = nil, frame: String? = nil) {
        self.at = at; self.path = path; self.tag = tag; self.text = text; self.label = label
        self.href = href; self.url = url; self.title = title; self.frame = frame
    }

    init?(json: [String: Any]) {
        guard let path = (json["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        self.at = Date()
        self.path = path
        self.tag = (json["tag"] as? String) ?? "?"
        self.text = ElementPick.clamp(json["text"] as? String, 160)
        self.label = ElementPick.clamp(json["label"] as? String, 120)
        self.href = ElementPick.clamp(json["href"] as? String, 400)
        self.url = ElementPick.clamp(json["url"] as? String, 400)
        self.title = ElementPick.clamp(json["title"] as? String, 200)
        self.frame = ElementPick.clamp(json["frame"] as? String, 200)
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
    var onUnbind: (() -> Void)?
    /// The current binding, for `GET /target` — so a caller can ask without
    /// changing anything.
    var describeTarget: (() -> [String: Any]?)?

    /// Open a dictation the way the microphone coming on does.
    var onTestDictationStart: (() -> Void)?

    /// A fabricated transcript, entering where a real one does.
    var onTestDictation: ((String) -> Void)?
    /// …and the same thing for the ⇧-wheel spawn: `POST /test/spawn`.
    var onTestSpawn: ((String) -> Void)?

    /// Which recogniser is loaded and whether it is up — for a test that has to
    /// wait out a ten-second model load before it says anything.
    var describeEngine: (() -> [String: Any])?

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
    private let stateLock = NSLock()

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
        case ("POST", "/test/dictation/start"):
            onTestDictationStart?()
            respond(conn, 200, ["ok": true, "listening": true])

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

        case ("POST", "/test/dictation"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            let text = (body?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text = text, !text.isEmpty else {
                return respond(conn, 400, ["ok": false, "error": "expected {\"text\": \"…\"}"])
            }
            onTestDictation?(text)
            respond(conn, 200, ["ok": true, "text": text])

        case ("GET", "/engine"):
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
