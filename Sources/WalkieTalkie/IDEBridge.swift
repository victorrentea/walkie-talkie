import Foundation

/// Talking to the editor instead of typing at it.
///
/// A terminal inside VS Code or IntelliJ has no address anything outside the
/// window can use — no tty, no tmux pane — so the relay fell back to the only
/// handle left: the application's pid, delivering by putting the line on the
/// clipboard, activating the app and pressing ⌘V.
///
/// **⌘V goes wherever the caret is.** Measured on a bound IntelliJ, four
/// deliveries, one variable:
///
/// | caret at delivery | where the line landed |
/// |---|---|
/// | the bound terminal | correct |
/// | another app entirely | correct — the app is activated and the caret is still there |
/// | the **editor** | **into the source file**, followed by a Return |
/// | a second terminal tab | into the wrong terminal |
///
/// and the relay logged `delivered` for all four, because "⌘V was sent" is the
/// only fact it can observe from outside. On 2026-08-15 that put a dictation
/// into `OwnerRestController.java`; the backend hot-compiled it and the endpoint
/// answered 500 until someone read the file.
///
/// So the relay stops guessing. Victor's own editor extensions — `victor-vsc`
/// and the `live-coding` IntelliJ plugin — each open a loopback listener and
/// publish it; the relay asks *them* which terminal is active and hands them the
/// line, and they call `sendText` on that exact terminal. No focus moves, no
/// clipboard is borrowed, and the caret stays where he left it.
///
/// **This is the Chrome extension's argument, run again.** From outside a window
/// you cannot address what is inside it; from inside, the API is right there.
/// The one difference is direction: Chrome *reports* picks to the relay, so the
/// relay listens; here the relay must *push*, so the editor listens.
enum IDEBridge {

    /// Fixed, and deliberately not under `--home`: that flag moves the outbox
    /// for testing, and an editor extension has no way to learn it was passed.
    static let registry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".walkie-talkie/ide")

    /// Where the extensions published before the rename.
    ///
    /// **Read for as long as an un-reloaded editor can still exist.** The relay
    /// updates itself the moment it is restarted; a VS Code extension host and an
    /// IntelliJ plugin do not — they keep running the code loaded when the window
    /// opened, which may be yesterday's. Ignoring this folder would mean ⌘⌃B in
    /// those windows quietly falling back to a blind paste, which is precisely the
    /// failure the extensions exist to prevent, for a reason no one could guess
    /// from the symptom. It costs one extra directory listing per bind.
    private static let legacyRegistry = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".wispr-relay/ide")

    struct Endpoint {
        let app: String       // "vscode" / "intellij"
        let port: Int
        let token: String
    }

    /// A terminal the relay has been pointed at, inside an editor window.
    struct Handle: Equatable {
        let endpoint: Endpoint
        let id: Int
        let name: String
        /// The **shell's** pid, and the whole reason these targets can finally be
        /// guarded. From it a tty follows, and from a tty the relay can ask the
        /// same question it asks of a Terminal.app tab: is a shell sitting at a
        /// prompt? Until now IDE targets were the one place that could not be
        /// checked at all, and `guarded: false` was the honest admission.
        let shellPID: pid_t?
        /// Where that terminal's shell is, **as the editor itself reports it**.
        ///
        /// The pid route cannot always be walked: an IDE running its terminal in
        /// a backend process hands out a connector with no `Process` behind it,
        /// so `shellPID` is nil however hard it is reflected over — measured on
        /// IntelliJ 2026.2, whose connector is a `BackendTtyConnector`. The
        /// folder is the one thing the pid was wanted for on screen, and the
        /// widget knows it without any of that.
        ///
        /// Captured at bind and refreshed from `/state`, because Victor `cd`s
        /// between repos inside one session.
        let cwd: String?

        static func == (a: Handle, b: Handle) -> Bool {
            a.endpoint.port == b.endpoint.port && a.id == b.id
        }
    }

    /// Which editor a bundle identifier is, or nil for everything else.
    ///
    /// **A whitelist, and that is the point.** `bind` used to send every
    /// non-Terminal app down the paste path, so ⌘⌃B pressed while looking at
    /// Chrome bound Chrome and typed the next dictation into whatever field had
    /// the caret. Proven, with the screen locked: it bound `loginwindow`.
    static func kind(bundleID: String) -> String? {
        if bundleID == "com.microsoft.VSCode" || bundleID == "com.visualstudio.code.oss" { return "vscode" }
        if bundleID.hasPrefix("com.jetbrains.") { return "intellij" }
        return nil
    }

    /// Every listener currently published for this kind of editor.
    ///
    /// One file per window, because each VS Code window runs its own extension
    /// host. Stale files are normal — an editor killed with `-9` never gets to
    /// clean up — and are filtered by the ping, not by trusting the file.
    private static func endpoints(kind: String) -> [Endpoint] {
        let files = [registry, legacyRegistry].flatMap { dir in
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let app = obj["app"] as? String, app == kind,
                  let port = obj["port"] as? Int,
                  let token = obj["token"] as? String
            else { return nil }
            return Endpoint(app: app, port: port, token: token)
        }
    }

    /// The window Victor is actually looking at.
    ///
    /// Two VS Code windows are two extension hosts and two listeners, and the
    /// only one that can be the window he pressed the key in front of is the
    /// focused one. Matching on the process tree was the other candidate and is
    /// worse: it identifies the *application*, which is exactly the granularity
    /// that was never the problem.
    private static func focusedEndpoint(kind: String) -> Endpoint? {
        let candidates = endpoints(kind: kind)
        for endpoint in candidates {
            guard let obj = request("GET", "/ping", on: endpoint),
                  (obj["focused"] as? Bool) == true else { continue }
            return endpoint
        }
        // A single editor window that reports itself unfocused a beat after
        // ⌘⌃B — the key is pressed while it *is* in front, and `activate` on
        // the relay's own side can land in between. With nothing to
        // disambiguate, the only candidate is the answer.
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// What asking an editor to bind its terminal came back with.
    ///
    /// **The two failures are not the same failure**, and collapsing them into
    /// `nil` is what put a dictation into Victor's open file. `noExtension` means
    /// nobody answered — an editor without the extension, or one that has not
    /// loaded it yet — and pasting at the caret is a fair last resort there,
    /// because it is that or nothing. `noTerminal` means the extension answered
    /// and said this window has no terminal in it: there is nothing to type into,
    /// and the paste lands in whatever the window *does* have, which is a source
    /// file. Measured — ⌘⌃B in a VS Code window holding notes.txt typed the next
    /// dictation into line 23 of the notes.
    enum BindResult {
        case bound(Handle)
        case noTerminal
        case noExtension
    }

    /// Point the editor at its active terminal and take a handle to it.
    static func bind(bundleID: String) -> BindResult {
        guard let kind = kind(bundleID: bundleID),
              let endpoint = focusedEndpoint(kind: kind)
        else { return .noExtension }
        guard let obj = request("POST", "/bind", on: endpoint) else { return .noTerminal }
        guard let id = obj["id"] as? Int else { return .noTerminal }
        let name = (obj["name"] as? String) ?? "terminal"
        let shell = (obj["shellPID"] as? Int).map { pid_t($0) }
        let cwd = obj["cwd"] as? String
        Log.info("🔌 \(kind) bridge on :\(endpoint.port) → terminal #\(id) “\(name)” shell pid \(shell.map(String.init) ?? "?") cwd \(cwd ?? "?")")
        return .bound(Handle(endpoint: endpoint, id: id, name: name, shellPID: shell, cwd: cwd))
    }

    /// Where that terminal is **now** — the editor asked again rather than the
    /// bind's answer replayed. Nil when the editor is gone or too old to know.
    static func currentDirectory(of handle: Handle) -> String? {
        guard let obj = request("GET", "/state?id=\(handle.id)", on: handle.endpoint),
              (obj["ok"] as? Bool) == true else { return nil }
        return obj["cwd"] as? String
    }

    /// Type the line into that terminal and nowhere else.
    static func send(_ line: String, to handle: Handle) -> Bool {
        guard let obj = request("POST", "/send", on: handle.endpoint,
                                body: ["id": handle.id, "line": line])
        else { return false }
        return (obj["ok"] as? Bool) == true
    }

    static func release(_ handle: Handle) {
        _ = request("POST", "/unbind?id=\(handle.id)", on: handle.endpoint)
    }

    /// Synchronous on purpose: every caller is already off the main thread, on
    /// the same queue that runs `osascript` and `ps` for the other two handles,
    /// and a delivery that has to be ordered against the next one is easier to
    /// reason about when it simply returns.
    private static func request(_ method: String, _ path: String, on endpoint: Endpoint,
                                body: [String: Any]? = nil) -> [String: Any]? {
        guard let url = URL(string: "http://127.0.0.1:\(endpoint.port)\(path)") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = method
        req.setValue(endpoint.token, forHTTPHeaderField: "x-relay-token")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        var result: [String: Any]?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return }
            result = obj
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return result
    }
}
