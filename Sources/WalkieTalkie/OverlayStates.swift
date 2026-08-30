import AppKit

/// Every state the overlay can be in, photographed in one run.
///
/// **Why this exists as code rather than as a folder of screenshots.** The
/// overlay is the whole user interface of this app and it is invisible to every
/// screen capture (`sharingType`; `RELAY_CAPTURABLE=1` stopped buying it back on
/// macOS 15). The only way to see it is `RelayWindow.snapshot`, the view drawing
/// itself — which until now was fired by hand with `kill -USR1` while the state
/// happened to be on screen. That is fine for one picture and hopeless for the
/// thirty-two states below: half of them last a second and a half of *those*
/// cannot be reached on demand at all (`⚠️ Whisper unavailable`, a transcript the
/// confidence gate flagged).
///
/// So the states are named here, driven from here, and shot from here.
/// `docs/shoot-overlay-states.sh` runs it and rebuilds `docs/overlay-states.html`
/// from the manifest, which makes the document a *product of the code* rather
/// than a folder of pictures that quietly ages out of date. The rule that comes
/// with it is in `CLAUDE.md`: a change to the overlay is not finished until this
/// has been re-run.
///
/// **`RELAY_SHOOT=<dir>`**, and the app quits when it is done. `SingleInstance`
/// means starting it also stands the running copy down, which is why the script
/// puts it back afterwards.
enum OverlayStates {

    /// One photograph: what it is, when Victor sees it, and what the picture is
    /// of. `apply` leaves the overlay in exactly that state — every state is set
    /// up from scratch after `reset`, so nothing here depends on what came before.
    struct Shot {
        let slug: String
        /// Which section of the page it belongs to. Named here rather than
        /// derived from `shape`, because the story the page tells is by *moment* —
        /// standing by, dictating, being answered — not by drawing style.
        let group: String
        let title: String
        /// The moment it is on screen. This is the half a screenshot cannot show.
        let when: String
        /// What to look at, and why it looks like that.
        let note: String
        /// `chip` — bare text beside the cursor, no blur, no shadow.
        /// `flash` — a chip that borrowed the blur for a few seconds; still
        /// beside the pointer, still 0.80. `panel` — the held prompt: top-left,
        /// full opacity, ✕ on hover. `none` — nothing visible at all.
        let shape: String
        /// The window's alpha, which the drawing cannot carry: the view is drawn
        /// opaque and the window fades it afterwards.
        let alpha: Double
        let apply: (RelayWindow) -> Void
    }

    // MARK: - The catalogue

    static func catalogue() -> [Shot] {
        let terminal = icon("com.apple.Terminal")
        let code = icon("com.microsoft.VSCode")
        let selection = "public Order placeOrder(Cart cart) {"
        let transcript = "adaugă un test pentru cazul în care coșul e gol"
        let long = "verifică de ce endpointul de checkout întoarce 500 când "
                 + "coșul are un singur produs fără preț, și dacă e din cauza "
                 + "conversiei de monedă adaugă un test care prinde exact cazul ăsta"

        return [
            // ---- the chip -------------------------------------------------
            Shot(slug: "unbound-idle", group: "At rest", title: "Unbound, idle",
                 when: "Whenever nothing is bound — which is most of the day, since the app runs from login.",
                 note: "There is no window on screen at all. Not a faded one: `orderOut`, because an invisible panel still swallows clicks on whatever it is over. This is the state the empty pointer was won back for.",
                 shape: "none", alpha: 0) { _ in },

            Shot(slug: "bound-idle", group: "At rest", title: "Bound, standing by",
                 when: "From ⌘⌃D (or the wheel chord) until something happens.",
                 note: "The whole chip: the destination app's icon, and the folder@branch of the terminal the words will be typed into. No state word — standing by is what he can infer from nothing happening; which agent this is, is what he cannot.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
            },

            Shot(slug: "bound-blind", group: "At rest", title: "Bound to an app with no directory",
                 when: "Bound to VS Code or IntelliJ — a target the relay pastes into blind.",
                 note: "No tty to read a folder from, so the app's own name takes the line rather than a folder being invented. The icon is doing the same job it always does.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "Visual Studio Code", folder: "Visual Studio Code", icon: code)
            },

            Shot(slug: "spawn", group: "At rest", title: "This sentence opens a new session",
                 when: "⇧ + the wheel: the dictation goes to a terminal that does not exist yet.",
                 note: "A destination that does not exist yet outranks the bound one — for the length of that one sentence the chip must not name the terminal the words are *not* going to.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setSpawnDestination("✨ workspace")
            },

            Shot(slug: "paused", group: "At rest", title: "Paused",
                 when: "He clicked the chip, or Pause in the menu — dictation goes to some other app now.",
                 note: "⏸️ ahead of the name (a modifier on *which agent*, not a different thing) and the window at 0.30. Fading is the message: the relay is off and the overlay looks switched off. Still a chip, never a panel.",
                 shape: "chip", alpha: 0.30) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setPaused(true)
            },

            Shot(slug: "typing", group: "At rest", title: "He started typing",
                 when: "Any keystroke, while the chip is on screen and not listening.",
                 note: "Faded to zero — the window is still there, unlike the unbound case, because this lasts as long as a keystroke and a panel ordered out and back would flicker. macOS hides the pointer while typing, and the chip belongs to the pointer. **Except while dictating**, which is the one state where the chip is the only evidence the microphone is open.",
                 shape: "none", alpha: 0) { _ in },

            Shot(slug: "preparing", group: "At rest", title: "The model is coming up",
                 when: "The ~10 s after a bind, or after the wheel if the weights are not resident.",
                 note: "`preparing` in the row under the destination. The title stays put — an hourglass on the folder said the same thing twice and made the one line that never changes during a session change.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setEngineLoading(true)
            },

            Shot(slug: "listening", group: "Dictating", title: "Dictating",
                 when: "From the wheel click until he clicks it again — the bulk of every dictation.",
                 note: "The pulsing 🔴 says *now*, `Listening…` says what. The model id used to follow it and now lives only in the menu: it is a setting, and a setting restated beside the cursor all day pays rent to be read twice a month.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
            },

            Shot(slug: "listening-chrome", group: "Dictating", title: "Dictating, at a page",
                 when: "Dictating *and* Chrome is the frontmost app.",
                 note: "The one gesture hint the chip still shows. It is worth its pixels because it is only on screen when it is actionable — and because the relay takes ⌘⇧-click *away* from Chrome while it is up, so a browser that silently stopped opening links would read as broken.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setChromeFront(true)
            },

            Shot(slug: "listening-picks", group: "Dictating", title: "Dictating, with elements picked",
                 when: "After the first ⌘⇧-click in Chrome, whatever app he switches to afterwards.",
                 note: "The invitation gives way to the newest selector, tail-first: what he cannot check otherwise is whether the click caught the button or the div wrapped around it. A bare `×3` would only confirm what he already believes.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setPicks(count: 2, newest: "div#cart > span.price")
            },

            Shot(slug: "listening-selection", group: "Dictating", title: "Dictating, carrying a highlight",
                 when: "He had text selected when he started talking, or F3'd with a selection.",
                 note: "`↪` and the highlight on one line, truncated. It rides along as a receipt only — the panel at the end shows it quoted in full, and widening the chip mid-sentence would throw a half-screen window over the thing he is reading.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setSelection(selection)
            },

            Shot(slug: "listening-selection-multi", group: "Dictating", title: "Dictating, several highlights",
                 when: "A second and third selection stashed with the side button during one sentence.",
                 note: "`↪ ×3` — the count is the only thing that changes, because the newest one is the one he can still see in his editor.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setSelection(selection, count: 3)
            },

            Shot(slug: "listening-everything", group: "Dictating", title: "Dictating, everything at once",
                 when: "Rare, and the widest the chip ever gets: browser in front, picks made, a highlight riding along.",
                 note: "Four rows beside the cursor. This is the state to look at when a row is added — it is the one that says how much of his screen the chip can cover.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setChromeFront(true)
                o.setPicks(count: 3, newest: "main.content > button.buy-button")
                o.setSelection(selection, count: 2)
            },

            Shot(slug: "listening-flash", group: "Dictating", title: "Something went wrong mid-sentence",
                 when: "A shot that failed, or any flash raised while he is still talking.",
                 note: "The flash takes the last row and the dictation rows stay above it — the chip grows the blur without losing what it was saying. The F3 receipt is deliberately *not* one of these: taking a picture mid-dictation must not throw a panel across the screen.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.flash("⚠️ screenshot failed", duration: 60)
            },

            Shot(slug: "transcribing", group: "Dictating", title: "Waiting on the model",
                 when: "Between the wheel click that ends the sentence and the panel that shows what it heard.",
                 note: "The same row the invitation and `preparing` use: what this chip is doing, in one place. It used to be a flash, which put it at the foot of a panel while the thing it replaced sat at the top.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setTranscribing(true)
            },

            // ---- flashes: the chip becomes a panel for a few seconds -------
            Shot(slug: "flash-sent", group: "Flashes", title: "Flash — sent",
                 when: "Two seconds, the moment a dictation reaches the agent.",
                 note: "A flash is a panel: blur, rounded rect, shadow — riding beside the pointer like the chip. It dissolves rather than cutting out, because a window vanishing under his hand is an event and `🎙️ sent` is not.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("🎙️ sent + 2 📸", duration: 60)
            },

            Shot(slug: "flash-unguarded", group: "Flashes", title: "Flash — bound to an unguarded shell",
                 when: "At bind, when the target has no shell guard: the flight lands into this.",
                 note: "The one warning that is about a setup rather than a failure — it says the next dictation could be typed at a bare prompt.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("⚠️ no shell guard", duration: 60)
            },

            Shot(slug: "flash-refused", group: "Flashes", title: "Flash — refused at the prompt",
                 when: "Delivery time, when the bound terminal turns out to be sitting at a shell prompt.",
                 note: "⛔️, not ⚠️: nothing was typed, and the sentence is still in the outbox. The distinction matters — this is the one failure that protects him rather than losing his words.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("⛔️ zsh is at the prompt — not sent", duration: 60)
            },

            Shot(slug: "flash-cancelled", group: "Flashes", title: "Flash — dictation cancelled",
                 when: "Three seconds after holding the wheel 2 s mid-sentence.",
                 note: "🗑️ and nothing else. The audio is gone; there is nothing to offer him and nothing to undo.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("🗑️ dictation cancelled", duration: 60)
            },

            Shot(slug: "flash-model-failed", group: "Flashes", title: "Flash — the recogniser is not there",
                 when: "Twelve seconds, when Whisper fails to load — a missing `mlx_whisper`, most often.",
                 note: "The longest flash there is, because it is the only one that means the next thing he tries will not work at all. This is the only recogniser the relay has.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("⚠️ Whisper unavailable — no module named mlx_whisper", duration: 60)
            },

            Shot(slug: "flash-nothing-to-paste", group: "Flashes", title: "Flash — nothing to paste yet",
                 when: "⌘⌃P, or the menu row, before anything has been dictated this session.",
                 note: "The only thing ⌘⌃P ever says out loud. A paste that lands is silent — the words appear at the caret, which is the whole of the evidence — so this row exists for the one case where nothing happens at all.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("⚠️ nothing dictated yet", duration: 60)
            },

            Shot(slug: "flash-accessibility", group: "Flashes", title: "Flash — permissions missing",
                 when: "Fifteen seconds at launch, before anything is bound.",
                 note: "The state that proves flashes must survive the unbound case: there is no title row above it, because nothing is bound yet, and this is the whole window.",
                 shape: "flash", alpha: 0.80) { o in
                o.flash("⚠️ grant Accessibility to Walkie Talkie", duration: 60)
            },

            // ---- the panel: the held prompt --------------------------------
            Shot(slug: "prompt", group: "The held prompt", title: "The held prompt",
                 when: "The seconds between the model answering and the words reaching the agent.",
                 note: "The one thing he must actually read: what the model heard, while Cancel can still stop it. The panel takes only the width the text needs, up to a third of the screen — a four-word dictation in a half-screen window is empty space parked over his work.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, words: transcript)
            },

            Shot(slug: "prompt-shots", group: "The held prompt", title: "The prompt, with its frames",
                 when: "Any dictation carrying screenshots — which is most of them, since one is taken automatically.",
                 note: "The strip is the receipt, oldest first: the same order the agent reads them in. It grew from 54 to 65 tall when the shot *count* came off the recording row.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(2), words: transcript)
            },

            Shot(slug: "prompt-selection", group: "The held prompt", title: "The prompt, with a quoted highlight",
                 when: "The dictation carried a selection.",
                 note: "Set as a quotation — big mark, one line, ellipsis — rather than folded into the words, which made the passage he is approving indistinguishable from the sentence he spoke about it. One line on purpose: a selection can be a whole file.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, selection: selection, words: transcript)
            },

            Shot(slug: "prompt-front", group: "The held prompt", title: "The prompt, naming the window he was in",
                 when: "Whenever the front window could be read at capture time.",
                 note: "Under the strip and *named*. Above the words it read as a heading — as if the sentence were about that window; it is one more thing the envelope carries, so it belongs at the end of the manifest with the frames.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, front: "OrderService.java — petclinic", words: transcript)
            },

            Shot(slug: "prompt-warning", group: "The held prompt", title: "The prompt, flagged by the confidence gate",
                 when: "When the transcript came back under the confidence floor.",
                 note: "The note sits between the words and the frames, because it is *about* the words. It is the panel saying it does not trust what it is showing — which is exactly when the edit and the Cancel are worth their pixels.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, words: transcript,
                                 warning: "⚠️ low confidence (0.42) — check the words before it goes")
            },

            Shot(slug: "prompt-everything", group: "The held prompt", title: "The prompt, everything at once",
                 when: "A pointed dictation: highlight, several frames, a named window, a shaky transcript.",
                 note: "The tallest the overlay ever gets. Rows in the order the envelope is packed: what he said, what the app thinks of it, what it is carrying, where he was — then the two buttons.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(3), selection: selection,
                                 front: "OrderService.java — petclinic", words: transcript,
                                 warning: "⚠️ low confidence (0.42) — check the words before it goes")
            },

            Shot(slug: "prompt-long", group: "The held prompt", title: "A long transcript",
                 when: "A sentence that does not fit one line — the panel wraps and grows.",
                 note: "Width is capped at a third of the screen and the height at what is left of it; the transcript row is measured by asking the label, not by a parallel calculation, because any disagreement is a sentence that silently stops.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(long, hold: 6, words: long)
            },

            Shot(slug: "prompt-selection-only", group: "The held prompt", title: "A highlight with nothing said",
                 when: "He stashed a selection and said nothing at all.",
                 note: "There is no transcript row — and the panel is still held, because a highlight sent by accident deserves the same Cancel the words get. It stopped being part of the text when it moved above it, so without this it would have gone straight out.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt("", hold: 6, selection: selection)
            },

            Shot(slug: "prompt-hover", group: "The held prompt", title: "The prompt, cursor over it",
                 when: "While the pointer is on the panel.",
                 note: "The ✕ appears — end the session. It exists only on the panel: an end-session button on something that moves away as you reach for it means nothing, which is why the chip has none and the menu bar keeps one that stays put.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(2), words: transcript)
                o.setHovering(true)
            },

            Shot(slug: "prompt-editing", group: "The held prompt", title: "Correcting the transcript",
                 when: "He clicked the words — one wrong word in forty is not worth saying again.",
                 note: "The clock stops (`⏎ Send` with no seconds) and the field holds *only his words*: the `📸` and `↪` decorations the preview adds are not his, so they must not be in the box he is typing in. Nothing takes him out of it except Send or Cancel.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, words: transcript)
                o.beginPromptEdit()
            },
        ]
    }

    // MARK: - Driving it

    /// Walk the catalogue, one state per beat, and write `states.json` beside the
    /// pictures. A beat rather than a tight loop because the panel unfolds over
    /// 0.22 s and a photograph taken during that is a photograph of the animation.
    static func shoot(overlay: RelayWindow, into dir: String) {
        let shots = catalogue()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Log.info("shooting \(shots.count) overlay states into \(dir)")

        var manifest: [[String: Any]] = []
        func step(_ i: Int) {
            guard i < shots.count else { return finish(manifest, dir: dir) }
            let shot = shots[i]
            reset(overlay)
            shot.apply(overlay)
            // One more beat after the state is set: the same run loop that lays
            // the window out has to run before the view can be asked to draw it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                var row: [String: Any] = [
                    "slug": shot.slug, "group": shot.group, "title": shot.title, "when": shot.when,
                    "note": shot.note, "shape": shot.shape, "alpha": shot.alpha,
                ]
                if shot.shape != "none" {
                    let path = (dir as NSString).appendingPathComponent("\(shot.slug).png")
                    overlay.snapshot(to: path)
                    row["image"] = "\(shot.slug).png"
                    let size = overlay.chipFrame.size
                    row["width"] = Int(size.width.rounded())
                    row["height"] = Int(size.height.rounded())
                }
                manifest.append(row)
                step(i + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { step(0) }
    }

    private static func finish(_ manifest: [[String: Any]], dir: String) {
        let path = (dir as NSString).appendingPathComponent("states.json")
        if let data = try? JSONSerialization.data(withJSONObject: manifest,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path))
            Log.info("manifest → \(path)")
        }
        NSApp.terminate(nil)
    }

    /// Back to nothing, so every state is defined by its own `apply` alone and
    /// the catalogue can be reordered without the pictures changing.
    private static func reset(_ o: RelayWindow) {
        o.cancelHeldPrompt()
        o.clearFlash(animated: false)
        o.setHovering(false)
        o.setListening(false)
        o.setTranscribing(false)
        o.setEngineLoading(false)
        o.setPaused(false)
        o.setPicks(count: 0, newest: nil)
        o.setShotCount(0)
        o.clearSelection()
        o.setChromeFront(false)
        o.setSpawnDestination(nil)
        o.setBound(label: nil)
    }

    // MARK: - Props

    private static func icon(_ bundleID: String, height: CGFloat = 18) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let size = NSSize(width: height, height: height)
        let out = NSImage(size: size)
        out.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        return out
    }

    /// Stand-in frames for the strip. Drawn rather than borrowed from a real
    /// dictation: the shots that ride with a prompt are pictures of Victor's
    /// screen, and a documentation page is the last place they belong.
    private static func mockShots(_ count: Int) -> [String] {
        let dir = NSTemporaryDirectory() + "walkie-state-shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for i in 0..<count {
            let path = (dir as NSString).appendingPathComponent("mock-\(i).png")
            let size = NSSize(width: 320, height: 200)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(calibratedWhite: 0.30, alpha: 1).setFill()
            NSRect(x: 0, y: size.height - 22, width: size.width, height: 22).fill()
            for line in 0..<7 {
                let w = CGFloat([180, 240, 120, 200, 90, 260, 150][(line + i) % 7])
                NSColor(calibratedWhite: 0.42, alpha: 1).setFill()
                NSRect(x: 18, y: size.height - CGFloat(60 + line * 20), width: w, height: 8).fill()
            }
            image.unlockFocus()
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                paths.append(path)
            }
        }
        return paths
    }
}
