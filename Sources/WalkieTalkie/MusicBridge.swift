import Foundation
import Network

/// Pushes the "a dictation is open" window to the Chrome extension, which pauses
/// every audible tab for the length of it and resumes exactly those afterwards.
///
/// **Why Chrome has to be the one deciding which tab.** CoreAudio funnels every
/// tab through a single Chrome audio helper process, so from outside the browser
/// "Chrome is making sound" is the finest grain obtainable — there is no way to
/// name the tab, let alone stop it. `chrome.tabs.query({audible: true})` is the
/// per-tab answer, and it only exists inside the extension. The same argument
/// `ElementPicker` makes about reading the DOM, made about audio.
///
/// **Why a push, and not the HTTP server that is already there.** The extension
/// polls `ElementPicker` only while Victor holds ⌘⇧; a poll fast enough to catch
/// the front edge of a dictation would have to run all day for a thing that
/// happens a few times an hour. A socket the app writes to costs nothing while
/// idle and lands in the same millisecond as the recording row.
///
/// **Why the keepalive ping.** An MV3 service worker is torn down after ~30 s
/// idle, which would silently drop the bridge between dictations. Traffic on an
/// open socket resets that timer, so this pings every 20 s. The current state is
/// also replayed to each client the moment it connects, so a worker that *was*
/// torn down mid-dictation comes back knowing it still owes a resume.
///
/// **Its own port, and not 8766.** Victor Addons runs the same bridge for its
/// own dictations. Both may be installed, both may pause, and that is harmless —
/// each extension resumes only the elements it marked, and an element the other
/// one already stopped is skipped as "not playing". But they cannot share a
/// listener, so this takes 8920, just past `ElementPicker`'s 8917–8919.
final class MusicBridge {

    static let port: UInt16 = 8920
    private static let keepAliveInterval: TimeInterval = 20

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var keepAliveTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.music", qos: .userInitiated)

    /// Current window state, mirrored to every client. Queue only.
    private var active = false
    /// Bumped on every edge, so a client can tell a fresh event from the state
    /// replay it gets on connect.
    private var seq = 0

    func start() {
        queue.async { [weak self] in self?.startListener() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.keepAliveTimer?.cancel()
            self.keepAliveTimer = nil
            // Say it rather than just dropping the socket. The extension does
            // treat a dead socket as "resume", but that path is the safety net;
            // this is the ordinary quit, and it should look ordinary.
            if self.active {
                self.active = false
                self.seq += 1
                self.broadcast(self.stateJSON())
            }
            for conn in self.connections.values { conn.cancel() }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
        }
    }

    /// Open or close the window. Safe to call from any thread — it is called from
    /// `syncBorrowedGestures`, on the main thread, on every edge that can change
    /// the answer. A repeat of the current state is dropped, so the extension
    /// never sees a resume it did not earn.
    func setActive(_ value: Bool) {
        queue.async { [weak self] in
            guard let self = self, self.active != value else { return }
            self.active = value
            self.seq += 1
            self.broadcast(self.stateJSON())
            Log.info(value ? "⏸️ dictation open — pausing audible Chrome tabs"
                           : "▶️ dictation over — resuming them")
        }
    }

    // MARK: - Internals

    private func stateJSON() -> String {
        "{\"type\":\"dictation\",\"active\":\(active),\"seq\":\(seq)}"
    }

    private func startListener() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Loopback only, for the same reason `ElementPicker` insists on it: this
        // accepts a connection from anything that can reach it, and the one thing
        // that must never be true of it is that the network can.
        guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else { return }
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

        guard let l = try? NWListener(using: params) else {
            Log.error("music bridge: could not bind 127.0.0.1:\(Self.port) — the music stays on during dictation")
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Log.info("🎵 music bridge on ws://127.0.0.1:\(Self.port) — Chrome pauses while dictating")
            case .failed(let e):
                // Almost always the previous instance still holding the port on
                // its way out; the relay works without this, so it is not fatal.
                Log.error("music bridge failed: \(e)")
            default:
                break
            }
        }
        l.start(queue: queue)
        startKeepAlive()
    }

    private func accept(_ conn: NWConnection) {
        let id = UUID()
        connections[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                Log.info("🎵 music bridge: Chrome connected (\(self.connections.count) total)")
                self.send(self.stateJSON(), to: conn)
                self.drain(conn)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// Nothing Chrome says is acted on — but the frames must be read, or the
    /// connection stalls once its receive buffer fills.
    private func drain(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] _, _, _, error in
            guard error == nil else { return }
            self?.drain(conn)
        }
    }

    private func startKeepAlive() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.keepAliveInterval,
                   repeating: Self.keepAliveInterval, leeway: .seconds(2))
        t.setEventHandler { [weak self] in
            guard let self = self, !self.connections.isEmpty else { return }
            self.broadcast("{\"type\":\"ping\"}")
        }
        keepAliveTimer = t
        t.resume()
    }

    private func broadcast(_ text: String) {
        for conn in connections.values { send(text, to: conn) }
    }

    private func send(_ text: String, to conn: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [meta])
        conn.send(content: text.data(using: .utf8), contentContext: context,
                  isComplete: true, completion: .contentProcessed { _ in })
    }
}
