import Foundation

/// **Why the desktop effects are held down right now** (2026-11-22) — the halo
/// and the dust round the pointer, the edge, the rewind, the coast, the pin and
/// the corner's tunnel. Pure, so the rule is tested without an app
/// (`FxHoldTests`); `AppDelegate.syncBorrowedGestures` reads it on every sync
/// and `GET /test/state.fxHeld` says it.
///
/// Two reasons:
/// - **battery** (2026-10-20, `BatteryFx`);
/// - **the screen is being filmed** (2026-11-22, Victor: *"cât durează recordul
///   de ecran să nu se afișeze niciun alt efect (edge sau mouse dust)"*): from
///   🔽 ↑ to the film's stop nothing is drawn but the `● REC` corners and the
///   chip. They come back at the stop if the sentence is still open.
enum FxHold {
    enum Why: String { case battery, filming }

    /// Filming is named first: it is the one that ends within the sentence.
    static func why(battery: Bool, filming: Bool) -> Why? {
        filming ? .filming : battery ? .battery : nil
    }
}
