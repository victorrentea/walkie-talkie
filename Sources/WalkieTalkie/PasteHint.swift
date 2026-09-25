import AppKit

/// **A reminder under the pointer, after every sentence, of which keys bring
/// it back** — `⌘⇧P`.
///
/// Victor's first ask, 2026-09-22: *"după ce ai dat cancel la dictare sau după
/// ce s-a încheiat o dictare la caret … ideea că paste-ul poate [se] pierde …
/// să apară foarte transparent, încă un hint, cu tastele pe care le apăs ca să
/// dau paste la acel prompt. Și cumva să apară foarte faint, și apoi să crească
/// opacitatea … și apoi să dispară. Un singur puls de la transparent la mai
/// opac și apoi din nou transparent."*
///
/// And the one that supersedes it, 2026-09-23: *"indiferent prin ce mecanism am
/// închis o dictare — că e la caret, că e bound, că e nou — să afișeze pentru
/// trei secunde, cu opțiunea de 80% pentru două secunde și jumătate, scurtătura
/// cu care pot să fac paste la ultimul prompt … Uneori îl plasez greșit, lasă-mă
/// să-mi amintesc constant ce este asta."*
///
/// ## After every delivered sentence, whatever the destination (2026-09-23)
///
/// `⌘⇧P` is the one gesture in the app that is *only* ever wanted after
/// something went slightly wrong: the words landed in the window that had the
/// focus rather than the one he meant, went to the bound terminal while he
/// meant another, or the panel's Cancel threw away a sentence he then wished
/// he had. A shortcut recalled at leisure is no use at a moment of mild alarm —
/// which is why it lived in a menu two clicks away and was forgotten.
///
/// On 2026-09-22 that reasoning put the hint at exactly two moments: a caret
/// sentence, as the one delivery this app cannot read back, and a cancelled
/// prompt. **That is superseded.** A terminal delivery *is* read back — but
/// only for *did it arrive*, never for *was that the terminal he meant*, which
/// only he can answer; *"uneori îl plasez greșit"* is him saying the bound and
/// spawned destinations get misaimed too. And a hint that appears only
/// sometimes cannot teach a shortcut — *"lasă-mă să-mi amintesc constant"* asks
/// for the repetition itself. So it follows **every** delivery: the caret, a
/// bound terminal, a new session, a sentence released by the bind it was held
/// for, and Wispr Flow's own dictations routed by the relay. The cancelled
/// prompt keeps its showing. A sentence held for a bind gets its hint when it
/// is **delivered**, not when it is parked — until then it has landed nowhere
/// it could be wrong about.
///
/// It is **still not** offered after a cancelled *dictation* (the ✕
/// mid-flight): that sentence never became words, so `⌘⇧P` there would paste
/// the *previous* one — the exact failure `copy_last_text` is under a standing
/// *never reintroduce* rule for. What that case has is *Recover Cancelled
/// Dictation*, which is a different offer and already made in the banner.
///
/// ## A row in the chip, not a window of its own (2026-09-23, afternoon)
///
/// Until this afternoon it was a panel of its own — `KeycapView`, `⌘⇧P` in a
/// white rounded outline, 15 pt medium, at 80% for 2.5 s and faded over 0.5 s,
/// re-placed under the pointer every frame. Victor: *"It looks like now it has
/// a border around it, with a different font, which is wrong. I just want you
/// to display yet another row in the mouse tooltip. Technically, it's just
/// like, for example, transcribing Kamikaze … It should have the icon of the
/// paste … the text should say 'Paste again', and then the shortcuts, just
/// like any text in the tooltip."* — `Re-paste` since 2026-09-24 (*"should be
/// 'Re-paste' instead of 'Paste Again'"*).
///
/// So it is `RelayWindow.pasteRow` — `📋 Re-paste  ⌘⇧P`, built by the same
/// `installEmojiRow` as `☠️ Kamikaze`, in `hintFont`, white with the halo on the
/// bare chip, no border. It rides the pointer because the chip does; it is at
/// the chip's own opacity because it is the chip; and when nothing else is on
/// the chip it is the chip's only row, which is what puts the chip on screen
/// (`refreshPresence` counts rows). The old window's reasons for being a window
/// — owning its alpha, the keycap outline — were the two things he rejected.
///
/// This type only keeps *when*: `pulse` puts the row up for `hold`, a second
/// pulse restarts the clock, `hide` takes it down at once.
///
/// ## A keystroke keeps it up (2026-09-23, evening)
///
/// Victor: *"the hint … should remain next to the mouse, whatever I press. I
/// think I pressed Command-Z, and it disappeared … They should stay there just
/// in case I need to paste it again."* The moment the row is for is the one
/// where he has just seen the words land wrong — and what he does first is
/// **undo** them, `⌘Z`, then look for how to get them back. A flat three
/// seconds ran out under exactly that: the undo spent the clock, and the row
/// was gone by the time he wanted the keys it names. So every key pressed
/// while the row is up **restarts** `hold`; it goes five seconds after the
/// last key, or when the next dictation starts (`hide`), never *because* of a
/// key.
final class PasteHint {

    /// The keys, as they are written on his keyboard — the row's shortcut.
    static let keys = "⌘⇧P"

    /// **Up for this long, counted from the last keystroke.** His *"trei
    /// secunde"* of the morning, raised to 5 the same evening: *"let it be 5
    /// seconds"* — once a key restarts the clock, the stretch that matters is
    /// the pause between the undo and reaching for `⌘⇧P`.
    static let hold: TimeInterval = 5.0
    /// Then half a second fading out (2026-09-25) — see `fadeOutPasteHint`.
    static let fade: TimeInterval = 0.5

    /// A showing is in flight.
    private var pulsing = false
    /// Which showing the pending take-down belongs to. Bumped by every `pulse`
    /// and `hide`, so a timer from an earlier showing finds itself stale and
    /// leaves the row a later one put up.
    private var generation = 0

    /// Watches keystrokes only while the row is up — each one restarts the
    /// clock (see *A keystroke keeps it up*). Passive: it observes, never
    /// intercepts, on the Accessibility grant the chip's own typing monitor uses.
    private var keyMonitor: Any?

    /// `AppDelegate` builds this before the overlay exists, so it is looked up
    /// at the moment of use.
    private var chip: RelayWindow? { RelayWindow.current }

    /// What the chip is actually showing, beside what the flag claims —
    /// `GET /test/state.pasteHint`.
    var report: [String: Any] {
        ["visible": chip?.pasteHint ?? false,
         "pulsing": pulsing, "hold": Self.hold, "row": "Re-paste  \(Self.keys)"]
    }

    /// **Put the row up for `hold`, then take it down.** `reason` is for the log
    /// only: the callers are far apart and *why is this on screen* is not a
    /// question the picture can answer.
    func pulse(reason: String) {
        Log.info("⌨️ paste hint — \(reason)")
        pulsing = true
        chip?.setPasteHint(true)
        watchKeys()
        armTakeDown()
    }

    /// (Re)start the `hold` clock; a take-down from an earlier arming finds
    /// itself stale.
    private func armTakeDown() {
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hold) { [weak self] in
            guard let self, self.generation == mine else { return }
            self.pulsing = false
            self.stopWatchingKeys()
            // `fade` more on top of `hold`, the row going out rather than off.
            // A pulse or a `hide` meanwhile moves `generation` on and keeps it.
            self.chip?.fadeOutPasteHint(seconds: Self.fade) { [weak self] in
                guard let self, self.generation == mine else { return }
                self.chip?.setPasteHint(false)
            }
        }
    }

    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.pulsing else { return }
                self.armTakeDown()
            }
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The hard stop — a new dictation has started and the hint is about the
    /// last one, or the app is going away.
    func hide() {
        generation += 1
        pulsing = false
        stopWatchingKeys()
        chip?.setPasteHint(false)
    }

    /// **Draw the chip with the paste row on a dark ground and a light one, and
    /// quit** — `WT_SHOOT_HINT=/tmp/hint.png`. Nothing that rides the pointer can
    /// be screen-captured, so this is how the row is reviewed. Two columns: the
    /// paste row alone (the chip after a caret sentence, unbound), and under
    /// `☠️ Kamikaze` so the two rows can be compared glyph for glyph.
    static func shoot(to path: String) {
        let chip = RelayWindow()
        var shots: [NSImage] = []
        for withKamikaze in [false, true] {
            chip.setKamikaze(withKamikaze)
            chip.setPasteHint(true)
            let tmp = NSTemporaryDirectory() + "paste-row-\(withKamikaze).png"
            chip.snapshot(to: tmp)
            if let image = NSImage(contentsOfFile: tmp) { shots.append(image) }
        }
        guard !shots.isEmpty else { return print("could not render the paste row") }
        let pad: CGFloat = 20
        let cellW = (shots.map(\.size.width).max() ?? 0) + pad * 2
        let cellH = (shots.map(\.size.height).max() ?? 0) + pad * 2
        let grounds: [NSColor] = [NSColor(white: 0.11, alpha: 1), NSColor(white: 0.97, alpha: 1)]
        let sheet = NSImage(size: NSSize(width: cellW * CGFloat(shots.count),
                                         height: cellH * CGFloat(grounds.count)))
        sheet.lockFocus()
        for (row, ground) in grounds.enumerated() {
            for (col, shot) in shots.enumerated() {
                let at = NSRect(x: cellW * CGFloat(col),
                                // Top row first: `NSImage` counts up from the bottom.
                                y: cellH * CGFloat(grounds.count - 1 - row),
                                width: cellW, height: cellH)
                ground.setFill()
                at.fill()
                shot.draw(in: NSRect(x: at.minX + pad, y: at.maxY - pad - shot.size.height,
                                     width: shot.size.width, height: shot.size.height),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return print("could not render the paste row")
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("paste row: \(path)")
    }
}
