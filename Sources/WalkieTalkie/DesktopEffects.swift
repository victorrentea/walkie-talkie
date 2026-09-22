import Foundation

/// **Hold Victor Addons' desktop effects still while a crop is being drawn.**
///
/// The wheel-held crop is the one capture in this rig that takes *seconds*
/// rather than a millisecond: Victor frames the box while still talking, and the
/// room keeps tapping ☕ reactions at him the whole time. Whatever is floating
/// over the desktop when he lets go lands in the picture. Every other capture
/// here is instantaneous and needs none of this.
///
/// `GET /effect/suspend/<seconds>` clears the screen and keeps it clear;
/// `GET /effect/resume` lifts it. Both go to **55123**, Victor Addons' port —
/// it proxies `/effect/*` verbatim to the effects app, so this side never needs
/// to know that there are two apps over there, or which one is up.
///
/// **Fire-and-forget, and deliberately so.** A crop must never wait on a socket,
/// and the effects app not being installed, not running, or mid-redeploy is a
/// normal Tuesday — the shot is still worth taking. The far side's hold is a
/// *deadline*, not a flag (`EffectsSuspension` over there), so even a resume
/// that never arrives — this app killed mid-drag, a redeploy, a crash — expires
/// on its own. That is why nothing here retries, and why the suspend asks for
/// only a few seconds more than a crop takes.
enum DesktopEffects {
    /// Addons' port, not the effects app's: seven local clients point here and
    /// the proxy is the contract.
    private static let port = 55123
    /// A drag is a second or two; this is the ceiling before the far side lifts
    /// the hold by itself, in case the resume never lands.
    static let cropSuspendSeconds = 20

    static func suspendForCrop() { fire("effect/suspend/\(cropSuspendSeconds)") }
    static func resume()         { fire("effect/resume") }

    private static func fire(_ path: String) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/\(path)") else { return }
        var req = URLRequest(url: url)
        // Short: if the other app is wedged, the crop must not notice.
        req.timeoutInterval = 1.0
        URLSession.shared.dataTask(with: req) { _, _, error in
            if let error = error {
                // "The effects app is not running" is the normal state on any Mac
                // but Victor's, and a crop that still worked has nothing to
                // report — so this is the log, not the overlay.
                Log.info("🎆 \(path) unanswered: \(error.localizedDescription)")
            }
        }.resume()
    }
}
