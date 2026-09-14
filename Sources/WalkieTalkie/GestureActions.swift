import Foundation

/// **Everything a gesture is allowed to command**, and the registry that turns
/// the names in `docs/gestures.puml` into Swift.
///
/// ## This file is the seam
///
/// Victor's scope for the state machine, 2026-09-14: *"doar partea de
/// interacțiune cu mouse-ul, nu motorul de hackuire al lui Wispr Flow, care
/// trebuie cu grijă decuplat oricum și pus sub un strat, ca să poată jongla ușor
/// între modelul local și modelul remote."*
///
/// So the vocabulary below names **`DictationSource`** and never a recogniser.
/// There is no `WisprFlowSource` here, no `History` row, no Scratchpad, no
/// swallow window, no `capturing`, no `pasteGrace` — a gesture says *open a
/// dictation* and which engine hears it is settled elsewhere, by the `Engine`
/// menu row. `evals/test_gesture_no_second_brain.py` asserts no **concrete
/// recogniser type** is reachable from here, because a seam nobody checks is a
/// seam that closes over.
///
/// `postWisprHandsFree` is the one name in this file that says *Wispr*, and it
/// is not a leak: the action posts that app's own **keyboard chord**, which is a
/// key to post rather than a recogniser to drive. It is the one gesture whose
/// sentence this app deliberately does not route.
///
/// ## Why a protocol and not closures over `AppDelegate`
///
/// Closures capturing `AppDelegate` would compile against all 5,000 lines of it
/// and the seam would be a convention. A protocol is a list, in one place, of
/// what the mouse can ask for — which is also the answer to *what does this
/// refactor actually contain*.
protocol GestureWorld: AnyObject {

    // MARK: What a guard may ask

    /// Is there a terminal to send to right now. `[bound]` in the diagram.
    var bound: Bool { get }

    // MARK: Opening and closing a sentence

    /// Take the context frame and ask the source for a microphone, in that order
    /// — `captureContext` books the shot synchronously so the chip says `×1`
    /// from the instant the row opens rather than `×0` for the length of a
    /// clipboard probe plus a subprocess.
    func openDictation()
    /// End the sentence. The words are still in flight afterwards; where they
    /// land was decided by the `aim…` beside this in the same action list.
    func stopDictation()
    /// Throw it away, audio kept five minutes for `Recover Cancelled Dictation`.
    func cancelDictation()

    // MARK: Where the words go — decided by the gesture that ENDS the sentence

    func aimAtCaret()
    func aimAtBound()
    /// Arm the spawn and offer the folder menu; both, because a spawn with no
    /// folder picked is a spawn into `~/workspace` and the menu is how he says
    /// otherwise.
    func aimAtSpawn()
    /// ⌘⌃D ends wherever it was already pointed — the keyboard has no direction
    /// to give, so it takes the aim the chip is showing.
    func aimWhereAimed()

    // MARK: The binding

    func bindFrontmost()
    func unbind()

    // MARK: Attachments and the other buttons

    func captureScreenshot()
    /// The back button at rest. If this ever stops being called, the key Victor
    /// submits with all day stops existing.
    func postReturn()
    /// Wispr Flow's own chord, raw — the one gesture whose sentence this app
    /// does not route. Named for the app on purpose; it is a *key to post*, not
    /// a recogniser to drive, which is why it is allowed to sit in this list.
    func postHandsFreeChord()

    // MARK: Delivery — observed, not driven

    /// **The machine does not deliver.** `AppDelegate.deliver` → `commit` is a
    /// four-way fork over a dead tty, a blind-paste target and a spawn that
    /// failed to open; none of that is decided by the mouse, and firing it from
    /// a transition as well would send the sentence twice. The machine is told
    /// `@delivered` / `@held` afterwards and follows.
    ///
    /// The one thing a gesture still drives here is giving up on a held
    /// sentence, because that is him deciding, not the delivery answering.
    func dropHeld()

    // MARK: The one side effect that is a genuine edge

    /// `MusicBridge` is told once when the microphone opens and once when it
    /// shuts — see the comment beside `Listening`'s entry in the diagram for why
    /// this is an action while the ring and the chip are not.
    func pauseMusic()
    func resumeMusic()

    // MARK: Saying something

    func warn(_ english: String)
    /// One line in `relay.log`, not on screen.
    func note(_ line: String)

    // MARK: Derived, not commanded

    /// **Called after every transition.** The ring, the borrowed gestures, the
    /// chip and the drop arrow are *functions of the state*, not effects fired
    /// at an instant, so they are re-derived here rather than being actions on
    /// an arrow. `chip` is the diagram's own rows for the state now current.
    func reconcile(state: String, chip: [String])
}

// MARK: - The registry

/// The one place a name in the diagram becomes behaviour. A name here that no
/// transition mentions is dead code and fails `test_gesture_registry.py`; a name
/// in the diagram that is missing here refuses the whole diagram at boot.
enum GestureActions {

    static func actions() -> [String: (GestureWorld) -> Void] {
        [
            // Opening and closing
            "openDictation":     { $0.openDictation() },
            "stopDictation":     { $0.stopDictation() },
            "cancelDictation":   { $0.cancelDictation() },

            // Aim
            "aimAtCaret":        { $0.aimAtCaret() },
            "aimAtBound":        { $0.aimAtBound() },
            "aimAtSpawn":        { $0.aimAtSpawn() },
            "aimWhereAimed":     { $0.aimWhereAimed() },

            // Binding
            "bindFrontmost":     { $0.bindFrontmost() },
            "unbind":            { $0.unbind() },

            // The other buttons
            "captureScreenshot": { $0.captureScreenshot() },
            "postReturn":        { $0.postReturn() },
            "postWisprHandsFree": { $0.postHandsFreeChord() },

            // Delivery — only the giving-up, see the protocol's note
            "dropHeld":          { $0.dropHeld() },

            // The music is the one genuine edge among the side effects — see the
            // comment beside Listening's entry in the diagram.
            "pauseMusic":        { $0.pauseMusic() },
            "resumeMusic":       { $0.resumeMusic() },

            // Warnings. Every string English — the overlay goes on a projector.
            "warnNothingBound":  { $0.warn("⚠️ nothing is bound — ⌘⌃B, or 🔼 ↓ on a terminal") },
            "warnSourceSilent":  { $0.warn("⚠️ the recogniser never opened a microphone") },
            "warnHoldExpired":   { $0.warn("⏳ held dictation expired — ⌘⌃P to paste it") },

            // Log-only notes. These exist so a gesture that deliberately does
            // nothing says so, which is the answer to *why did nothing happen*.
            // The source already flashed its own reason through `DictationEnd
            // .silent(why)`; a second banner over it would say less, not more.
            "sayNoWords":        { $0.note("✍️ the settle gave up with no words") },
            "sayInFlight":       { $0.note("🔼 a gesture while the words are in flight — nothing to start, nothing to stop") },
            "confirmMicOpen":    { $0.note("⚡ the microphone confirms the gesture") },
            "noteShut":          { $0.note("⚡ the microphone is shut") },
            "nameSpawnFolder":   { $0.note("✨ the spawn folder was picked") },
            "showBinding":       { $0.note("📍 bound") },
            "showUnbound":       { $0.note("📍 unbound") },
            "reaim":             { $0.aimAtBound() },
        ]
    }

    static func guards() -> [String: (GestureWorld) -> Bool] {
        [
            "bound":          { $0.bound },
        ]
    }
}
