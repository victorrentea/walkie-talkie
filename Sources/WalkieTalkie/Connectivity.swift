import Foundation
import Network

/// **Is this Mac on the internet right now?** (2026-10-19) — asked by
/// `startDictation` before a Wispr Flow sentence opens.
///
/// Victor, 2026-10-19, with two screenshots of Wispr Flow's own pop-ups (*Is
/// your internet connected?*, then *Transcript failed to load*): *"walkie talkie
/// should default to local when wisprflow is selected without internet"*. Wispr
/// transcribes in the cloud; offline it takes the whole sentence, fails, and the
/// words come back only through Q14's local fallback, after its error. Known up
/// front, the sentence is the local model's from the first word.
///
/// Two witnesses, because each misses what the other sees:
/// - **`NWPathMonitor`** — instant, but only says a route exists: Wi-Fi joined
///   to a router with no uplink, or a captive portal, still reads `.satisfied`.
/// - **a probe** — one `HEAD` to Apple's captive-portal page every
///   `probeEvery` and at every path change; **two failures in a row** (the
///   second `retryAfter` behind the first) say offline, one success says online.
///   One failure alone is a dropped packet, not a missing internet.
///
/// Offline = no satisfied path, or the probe's two failures. Unknown (before the
/// first answer) counts as online: a guess must never take Wispr away.
final class Connectivity {

    static let shared = Connectivity()

    static let probeURL = URL(string: "https://www.apple.com/library/test/success.html")!
    static let probeEvery: TimeInterval = 30
    static let retryAfter: TimeInterval = 3
    static let probeTimeout: TimeInterval = 4

    private let queue = DispatchQueue(label: "ro.victorrentea.wispr-relay.connectivity")
    private let monitor = NWPathMonitor()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = Connectivity.probeTimeout
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: cfg)
    }()

    // Read from main, written on `queue` — under the lock.
    private let lock = NSLock()
    private var pathUp = true
    private var probeFailures = 0
    private var lastProbeAt: Date?
    private var started = false
    private var timer: DispatchSourceTimer?
    private var probing = false
    /// `POST /test/local-auto {"offline": true｜false｜null}` — read as offline / online, or the truth.
    var forced: Bool?

    /// Nil when online; else why it is not, for the log and the flash.
    var offlineReason: String? {
        if let forced { return forced ? "offline (POST /test/local-auto offline)" : nil }
        lock.lock(); defer { lock.unlock() }
        if !pathUp { return "no network path" }
        if probeFailures >= 2 { return "no answer from the internet (\(probeFailures) probes failed)" }
        return nil
    }

    var isOnline: Bool { offlineReason == nil }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()
        monitor.pathUpdateHandler = { [weak self] path in self?.pathChanged(path) }
        monitor.start(queue: queue)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: Self.probeEvery)
        t.setEventHandler { [weak self] in self?.probe() }
        t.resume()
        timer = t
    }

    /// A fresh probe, now — at a Wispr sentence that found us offline, so the
    /// next one notices the way back without waiting for the clock.
    func recheck() {
        queue.async { [weak self] in self?.probe() }
    }

    func json() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["pathUp": pathUp, "probeFailures": probeFailures,
                "lastProbeAgo": lastProbeAt.map { Date().timeIntervalSince($0) } ?? NSNull(),
                "forced": forced ?? NSNull()]
    }

    private func pathChanged(_ path: NWPath) {
        let up = path.status == .satisfied
        let was = isOnline
        lock.lock()
        let changed = up != pathUp
        pathUp = up
        if changed { probeFailures = 0 }
        lock.unlock()
        if changed { Log.info("🌐 network path \(up ? "up" : "down")") }
        report(was: was)
        if up { probe() }
    }

    /// On `queue`.
    private func probe() {
        lock.lock()
        let skip = probing || !pathUp
        if !skip { probing = true }
        lock.unlock()
        guard !skip else { return }
        var req = URLRequest(url: Self.probeURL)
        req.httpMethod = "HEAD"
        session.dataTask(with: req) { [weak self] _, response, _ in
            guard let self else { return }
            let ok = ((response as? HTTPURLResponse)?.statusCode).map { (200..<400).contains($0) } ?? false
            self.queue.async {
                let was = self.isOnline
                self.lock.lock()
                self.probing = false
                self.lastProbeAt = Date()
                self.probeFailures = ok ? 0 : self.probeFailures + 1
                let retry = !ok && self.probeFailures == 1
                self.lock.unlock()
                self.report(was: was)
                if retry { self.queue.asyncAfter(deadline: .now() + Self.retryAfter) { self.probe() } }
            }
        }.resume()
    }

    private func report(was: Bool) {
        let why = offlineReason
        if was && why != nil { Log.info("🌐 offline — \(why!); a Wispr Flow sentence starts on the local model") }
        if !was && why == nil { Log.info("🌐 online again") }
    }
}
