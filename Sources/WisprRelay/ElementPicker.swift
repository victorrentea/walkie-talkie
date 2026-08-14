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

    /// Forwarding is off, so this relay takes nothing.
    ///
    /// A paused relay answers `/ping` with a refusal, and the extension treats a
    /// refusal exactly like no relay at all: ⌘ in Chrome goes straight back to
    /// being Chrome's ⌘. That is what pause has always meant here — Victor pauses
    /// precisely in order to use the browser normally, and an inspector still
    /// eating his ⌘-clicks would be the one thing pause was supposed to stop.
    ///
    /// Written from the main thread, read on the listener queue, hence the lock —
    /// the same shape as `HotkeyTap.dictating`, and for the same reason.
    var paused: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return pausedFlag }
        set { stateLock.lock(); pausedFlag = newValue; stateLock.unlock() }
    }
    private var pausedFlag = false
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
            guard !paused else { return respond(conn, 503, ["ok": false, "paused": true]) }
            respond(conn, 200, ["ok": true, "session": SessionLabel.value])

        case ("POST", "/pick"):
            guard !paused else { return respond(conn, 503, ["ok": false, "paused": true]) }
            guard let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                  let pick = ElementPick(json: body) else {
                return respond(conn, 400, ["ok": false, "error": "expected a JSON object with a non-empty `path`"])
            }
            Log.info("🎯 picked \(pick.short)")
            onPick?(pick)
            respond(conn, 200, ["ok": true, "session": SessionLabel.value])

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
