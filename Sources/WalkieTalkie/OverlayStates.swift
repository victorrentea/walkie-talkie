import AppKit

/// Every state the overlay can be in, photographed in one run.
///
/// **Why this exists as code rather than as a folder of screenshots.** The
/// overlay is the whole user interface of this app and it is invisible to every
/// screen capture (`sharingType`; `RELAY_CAPTURABLE=1` stopped buying it back on
/// macOS 15). The only way to see it is `RelayWindow.snapshot`, the view drawing
/// itself — which until now was fired by hand with `kill -USR1` while the state
/// happened to be on screen. That is fine for one picture and hopeless for the
/// thirty-eight states below: half of them last a second and a half of *those*
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
                 when: "From ⌘⌃B (or ◀️ + 🔼, or ◀️ + 🛞 with Logi gestures off) until something happens.",
                 note: "A microphone, and nothing else. The `folder@branch` it used to spell out is the answer to a question only asked at the moment he opens his mouth, and it was being said beside the pointer all day instead — so it now waits for the dictation. **The same glyph for every destination**: at rest the only thing worth saying is *armed*, and bound has to look different from unbound, where there is no chip at all. Which terminal it is, is a menu away.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
            },

            Shot(slug: "bound-blind", group: "At rest", title: "Bound to an app with no directory",
                 when: "Bound to VS Code or IntelliJ — a target the relay pastes into blind.",
                 note: "Standing by this is the same 🎙️ as every other bound chip — the destination is not what the resting state is about. What differs is what appears once he starts talking: no tty to read a folder from, so the app's own name takes the line rather than a folder being invented, behind its own icon.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "Visual Studio Code", folder: "Visual Studio Code", icon: code)
            },

            Shot(slug: "spawn", group: "Dictating", title: "This sentence opens a new session",
                 when: "🔼 ↑ — the forward button held, mouse moved up (🛞🛞 with Logi gestures off): the dictation goes to a terminal that does not exist yet.",
                 note: "**One row, and the ✨ is all that is left of the destination.** It had a title row of its own — Terminal's icon, ✨, `workspace` — and Victor took it off on 2026-09-02: the folder is *always* `~/workspace`, which is the whole point of the gesture, and the icon names an app he is not looking at yet. So the mark rides in front of `Listening…` and the row above it goes. The 🔴 keeps the glyph column: a frozen recording row is indistinguishable from a hung app, and that is the one thing the pulse is here to rule out.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setSpawnDestination("✨ workspace", mark: "✨")
                o.setListening(true)
                o.setShotCount(1)
            },

            Shot(slug: "spawn-folder", group: "Dictating", title: "…and he picked which folder",
                 when: "After clicking a row in the folder menu, for the rest of that dictation.",
                 note: "**The chosen folder gets the row a binding would have taken**, behind Terminal's own icon — Victor's ask, 2026-09-07: *\"ca și cum aș fi fost deja bind-uit la un alt astfel de terminal … să știu dacă am setat ce trebuie\"*. The argument that removed this row was that the folder is *always* `~/workspace`, so it said nothing; that holds until he picks one out of five, at which point the only place the choice could be checked was a label that had already gone. The ✨ stays one row up, in front of `Listening...`: it is the fact this destination does not share with a binding — the session does not exist yet.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setSpawnDestination("training-assistant", mark: "✨", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
            },

            Shot(slug: "bind-to-send", group: "Dictating", title: "Nothing is bound, and he is talking anyway",
                 when: "Any dictation started with no terminal bound — which the app refused outright until 2026-09-11, and now holds for the bind that follows it.",
                 note: "**The destination row names a gesture rather than a place**, because that is what this destination still is: *bind to send*, behind the same drawn pin `at caret` rides behind. It is the fourth answer to *where do these words go* — a terminal already bound, one it is about to open for itself, the caret, and now **later** (`AppDelegate.holdsForBind`). The sentence is recorded, shown and read exactly as a bound one is, and `commit` parks it for five minutes; the outbox line is written at delivery and not before, which is the whole of what survives from the 2026-08-27 decision that unbound means silent. The row comes down the instant a bind lands, and the chip says `⏳ held — bind a terminal to send it` once the words have left the dictation. **The icon form and not the ✨'s mark form**: a mark with no icon is `spawnCollapsed`, which drops the row and rides the glyph in front of `Listening...`, so the words would never have been drawn.",
                 shape: "chip", alpha: 0.80) { o in
                o.setSpawnDestination("bind to send", icon: RelayWindow.pinGlyph)
                o.setListening(true)
                o.setShotCount(1)
            },

            Shot(slug: "replace-wispr", group: "At rest", title: "Replace Wispr — this one goes to the caret",
                 when: "The forward side button, while the mode is ticked in the menu: a dictation that is typed where the caret is instead of at an agent.",
                 note: "The caret is a destination like any other, and it takes the line a spawn takes — the bound terminal is still there, and for the length of this sentence the words are not going to it. Bare, it looks like this: no shots row, because this mode still takes no picture of its own — the row appears the moment he takes one — and no ⌘⇧ hint unless Chrome is in front.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setSpawnDestination("at caret", icon: RelayWindow.pinGlyph)
                o.setListening(true)
            },

            Shot(slug: "replace-wispr-attached", group: "At rest",
                 title: "…and he attached things to it anyway",
                 when: "The shutter or a ⌘⇧-pick during a caret dictation — live in this mode since 2026-09-08.",
                 note: "It borrowed nothing before, on the argument that both gestures add to a *message* and this mode has none. Victor overruled the premise: a paste is a message whose recipient happens to be whatever holds the caret, which is routinely another agent. So the rows a bound dictation grows, this one grows too — the tally included — and what gets pasted carries `[the shots I took: …]`, `[selected: …]` and `[elements I picked in Chrome: …]` in the wording the terminal already uses. **The highlights joined them on 2026-09-09**, on his ask: they were the one deliberate attachment this envelope refused, and the refusal was really about the *probe* rather than about the highlight. What it still does not carry is anything **automatic**: no opening frame, no `[Focused window: …]` and no `dictated aloud` hint. Attach nothing and it pastes the words alone, byte for byte as before.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setSpawnDestination("at caret", icon: RelayWindow.pinGlyph)
                o.setListening(true)
                o.setShotCount(2)
                o.setPicks(count: 2, newest: "div#cart > span.price")
                o.setSelection(selection, count: 2)
                o.pinSelectionSettled()
                o.pinPickSettled()
            },

            Shot(slug: "typing", group: "At rest", title: "He started typing",
                 when: "Any keystroke, while the chip is on screen and not listening.",
                 note: "Faded to zero — the window is still there, unlike the unbound case, because this lasts as long as a keystroke and a panel ordered out and back would flicker. macOS hides the pointer while typing, and the chip belongs to the pointer. **Except while dictating**, which is the one state where the chip is the only evidence the microphone is open — and except at a bind, which is a keystroke whose whole answer is drawn beside the pointer, so ⌘⌃B wakes both the chip and the hidden pointer back up before the flight arrives.",
                 shape: "none", alpha: 0) { _ in },

            Shot(slug: "listening", group: "Dictating", title: "Dictating",
                 when: "From 🔼 → until he makes it again (🛞 with Logi gestures off) — the bulk of every dictation.",
                 note: "**The destination is named here**, and only here — the chip has been a bare 🎙️ all day, and now it wears the destination's own icon too; and the moment the microphone opens it spells out the terminal the words are going to, in time for him to ⌘⌃B somewhere else mid-sentence if it is the wrong one. The pulsing 🔴 says *now*, `Listening…` says what. The model id used to follow it and now lives only in the menu: it is a setting, and a setting restated beside the cursor all day pays rent to be read twice a month. **This is the bar full** — three voiced seconds in, every character of `Listening...` lit, and it stays that way for the rest of the sentence; the two shots below it are what the same row looks like on the way there. **The blue `HQ` after it is what the bar filling means**, said in two letters: past three voiced seconds the wrong-language mode is at its floor and the median WER of a short clip has halved, so the tag is a claim about *this* dictation rather than the gold star it replaced, which only said well done and left him to remember what for. It pops out when the last dot lights — a thing that moves is caught in peripheral vision, which is where this row spends its life. **`📸 ×1` from the first frame**: he took that picture by starting to talk, and the count is back on 2026-09-09 because the vignette answers *did that press land* while this answers *what am I about to send* — which is a different question three minutes and four presses in.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
            },

            Shot(slug: "listening-long", group: "Dictating", title: "Two minutes in",
                 when: "Any dictation that has been running for a whole minute — and every one that runs for several.",
                 note: "**`(2m)` is the one fact the rest of the row cannot carry.** `Listening...` fills in the first three voiced seconds and then never changes again, so from that moment on nothing distinguishes a sentence from a monologue — and a monologue costs real seconds at the other end, since the decode is charged per second of audio and the panel he has to read while Cancel is running is as long as he made it. Victor's ask, 2026-09-09: *\"să pui după toată povestea o paranteză rotundă în care treci numărul de minute\"*. **Nothing under a minute**: `(0m)` would be a readout saying only that a clock exists, an inch from what he is reading, for the length of every ordinary dictation — which is the rent the model id was taken off this row for paying.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.pinListenElapsed(2)
            },

            Shot(slug: "listening-cold", group: "Dictating", title: "The first words — too little speech to trust",
                 when: "From the instant the microphone opens until about a second of actual speech has arrived.",
                 note: "**`Listening...` is a progress bar, and it is empty here.** It fills one character at a time as speech arrives and is full when the last dot lights — a *count*, not a brightness, because a fade over an unknown backdrop gives him nothing to judge \"is it done yet?\" against. What it forecasts: the local model picks a language off a 30-second window before it decodes a word, and with a second of speech in that window the pick is a guess — and a wrong guess is not a wrong word, it is a whole sentence of Turkish made out of Romanian. Counted by re-decoding 803 of his own clips, **by voiced seconds**: 42% under one voiced second come back in a language Victor does not speak, 15% between one and two, and 1% past two. (The language pin has since taken that mode to zero — the bar still forecasts everything else that is worse when there is less to hear.)",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.pinListenWarmth(0)
            },

            Shot(slug: "listening-warming", group: "Dictating", title: "Halfway — six characters lit",
                 when: "About a second and a half of speech in. Speech, not seconds: if he stops to think, the bar stops with him.",
                 note: "**It counts `MicRecorder.voicedSeconds`, not the clock**, and that correction is Victor's: *\"uneori eu pur și simplu tac — dacă tac pe microfon și nu vine semnal, nu știu cât de valoroasă e întârzierea asta\"*. The corpus is emphatic — the median dictation is only **38% voiced**, so a wall-clock bar would fill while he was thinking and tell him the one thing it exists not to. Full at **three voiced seconds**: the first bucket where both failure modes are at their floor, about fifteen words at his measured 5.1 words per voiced second, and within a hair of where he put the boundary by feel.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.pinListenWarmth(0.5)
            },

            Shot(slug: "listening-chrome", group: "Dictating", title: "Dictating, at a page",
                 when: "Dictating *and* Chrome is the frontmost app.",
                 note: "The one gesture hint the chip still shows. It is worth its pixels because it is only on screen when it is actionable — and because the relay takes ⌘⇧-click *away* from Chrome while it is up, so a browser that silently stopped opening links would read as broken. The keys and nothing else, since 2026-08-31: the drawn left button that used to follow them was the one glyph on the row he could not act on.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setChromeFront(true)
            },

            Shot(slug: "listening-picks", group: "Dictating", title: "Dictating, with elements picked",
                 when: "After the first ⌘⇧-click in Chrome, whatever app he switches to afterwards.",
                 note: "The invitation gives way to the newest selector, tail-first: what he cannot check otherwise is whether the click caught the button or the div wrapped around it. **For four seconds** — the row below is where it ends up.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setPicks(count: 2, newest: "div#cart > span.price")
            },

            Shot(slug: "listening-picks-settled", group: "Dictating", title: "…and four seconds later, with one dragged",
                 when: "Every pick ends here — the selector has had its seconds and the row is the count alone. One of these three was ⌘⇧-dragged.",
                 note: "`×3` and nothing else, which is Victor\'s ask of 2026-09-09: *\"the Chrome icon should also be followed only by the ×2 … I don\'t want to see the div thing here\"*. It is the selection row\'s bargain one row up, arriving here for the same reason: the selector answers *did the click catch the button or the div around it* at the instant it lands, and after that it is the longest string on the chip restating something already checked, beside a cursor he is trying to work with. **`⤢` is the one thing a count cannot say** — that one of them was dragged, i.e. that the message carries *move it here* and not only *this element*.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setPicks(count: 3, newest: "div#cart > span.price", moved: true)
                o.pinPickSettled()
            },

            Shot(slug: "listening-selection", group: "Dictating", title: "Dictating, carrying a highlight",
                 when: "He had text selected when he started talking, or took a shot with a selection — for the four seconds after it lands.",
                 note: "The quotation mark and the highlight on one line, truncated. It rides along as a receipt only — the panel at the end shows it quoted in full, and widening the chip mid-sentence would throw a half-screen window over the thing he is reading. Four seconds later it is the row below.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setSelection(selection)
            },

            Shot(slug: "listening-selection-multi", group: "Dictating", title: "A highlight, four seconds later",
                 when: "Every highlight ends here — the words have had their seconds and the row is the running count alone. Three of them, here.",
                 note: "`×3` and nothing else. A highlight is read once, at the moment it is caught; from then on the only open question is whether any of them fell out, and a line of somebody else's code beside the cursor for the rest of a two-minute sentence is the widest row on the chip restating something already checked. `×1` is written out too — the number is all that is left, so an empty row would read as a highlight that got lost.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setSelection(selection, count: 3)
                o.pinSelectionSettled()
            },

            Shot(slug: "listening-selection-caught", group: "Dictating", title: "The shutter caught a highlight",
                 when: "For a beat after every side-button press that reads a new selection — including one in a Chrome page, which is where it used to read nothing at all.",
                 note: "His own words back, on a row that was not there a moment ago — deliberately not a flash, since a flash is a panel and a shutter press must not throw one over the work he is photographing. It said `selecting` in front of them until 2026-09-09, when Victor had the verb removed: the row appearing is the receipt. It collapses to `×N` after four seconds, and it truncates at 34 characters.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.setSelection(selection, count: 2)
            },

            Shot(slug: "listening-everything", group: "Dictating", title: "Dictating, everything at once",
                 when: "Rare, and the widest the chip ever gets: browser in front, three frames taken, picks made, a highlight riding along.",
                 note: "Five rows beside the cursor. This is the state to look at when a row is added — it is the one that says how much of his screen the chip can cover. **The quotation is above Chrome and Chrome is last**, since 2026-09-09: a highlight belongs to *this* message and goes out with it, while the ⌘⇧ row is an invitation before the first pick and outlives the message after it — and a row that shuffles up and down as a highlight comes and goes is a row he has to find again each time. **The counts line up in the icon column**, which is the overview Victor asked for — `📸 ×3`, the quotation, `×3` in Chrome, read downwards — rather than a fourth row restating the other three.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(3)
                o.setChromeFront(true)
                o.setPicks(count: 3, newest: "main.content > button.buy-button")
                o.setSelection(selection, count: 2)
                o.pinListenElapsed(2)
            },

            Shot(slug: "listening-flash", group: "Dictating", title: "Something went wrong mid-sentence",
                 when: "A shot that failed, or any flash raised while he is still talking.",
                 note: "The flash takes the last row and the dictation rows stay above it — the chip grows the blur without losing what it was saying. The shot receipt is deliberately *not* one of these: taking a picture mid-dictation must not throw a panel across the screen, which is why the highlight it catches is announced on the chip's own row instead.",
                 shape: "flash", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setListening(true)
                o.setShotCount(1)
                o.flash("⚠️ screenshot failed", duration: 60)
            },

            Shot(slug: "transcribing", group: "Dictating", title: "Waiting on the model",
                 when: "Between the gesture that ends the sentence and the panel that shows what it heard.",
                 note: "The one row left in which Victor is waiting on the app — `preparing`, the model coming up, was the other, and it stopped existing once the weights started loading at launch instead of at the first gesture. It used to be a flash, which put it at the foot of a panel while the thing it replaced sat at the top. The seconds it used to count down came off on 2026-09-08 — the filling word says the same estimate, and a number ticking toward zero is a deadline to watch.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.setTranscribing(true)
                o.setShotCount(1)
                o.pinTranscribeWarmth(0.45)
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

            Shot(slug: "flash-cancelled", group: "Flashes", title: "Dictation cancelled",
                 when: "The instant 🔼 ← is made mid-sentence (🛞 held 2 s with Logi gestures off) — 1.5 s, then half a second of dissolve.",
                 note: "**Words and nothing else**, and **bare**: no glyph of its own, no lone 🎙️ above it, no blur, no rounded rect, no shadow, no ✕. It is a word replacing a word — it lands in the row `Listening…` was just occupying, beside the pointer — and a window opening and closing round it for a second and a half read as an *event* rather than as the state changing back to nothing. The audio is gone; there is nothing to offer him and nothing to undo.",
                 shape: "chip", alpha: 0.80) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.flash("🗑️ Cancelled", duration: 60)
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

            Shot(slug: "prompt-autosend", group: "The held prompt", title: "The prompt, under Autosend",
                 when: "The same moment, with **Autosend** ticked in the menu — one second, then it is gone.",
                 note: "No Send and no Cancel, and the row they sat on goes with them: two buttons up for one second are two buttons nobody can reach, an invitation to press something that will not be there when the hand arrives. What is left is the receipt — a dictation that vanished into a terminal with nothing shown is the one state where a delivery cannot be told from a drop.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, words: transcript, buttons: false)
            },

            Shot(slug: "prompt-shots", group: "The held prompt", title: "The prompt, with its frames",
                 when: "Any dictation carrying screenshots — which is most of them, since one is taken automatically.",
                 note: "The strip is the receipt, oldest first: the same order the agent reads them in. It grew from 54 to 65 tall when the shot *count* came off the recording row. Each frame carries the m:ss it was taken at, written into its corner — the stamps used to be a line of text above the strip, which had to be counted across to be read as captions. The first frame is bare: the automatic context shot is always 0:00.",
                 shape: "panel", alpha: 1.0) { o in
                o.setBound(label: "petclinic", folder: "petclinic@main", icon: terminal)
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(2),
                                 stamps: ["", "0:38"], words: transcript)
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
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(3),
                                 stamps: ["", "0:38", "1:52"], selection: selection,
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
                o.showSentPrompt(transcript, hold: 6, shots: mockShots(2),
                                 stamps: ["", "0:38"], words: transcript)
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
                o.pinTranscribeWarmth(nil)
        o.setPicks(count: 0, newest: nil)
        o.setShotCount(0)
        o.clearSelection()
        o.setChromeFront(false)
        o.setSpawnDestination(nil)
        o.setBound(label: nil)
        // **Settled, unless a shot says otherwise.** `Listening…` ramps from dark
        // grey to full over six seconds (`RelayWindow.listenWarmth`), so without
        // a chosen frame every dictating state on this page would be a picture of
        // its own first 200ms — the shutter fires immediately after `apply`. The
        // default is the end of the ramp, which is what the row looks like for
        // all but the first seconds of every sentence; the two shots that are
        // *about* the ramp pin their own.
        o.pinListenWarmth(1)
        // No clock runs for a catalogue shot — every state is set up and
        // photographed in the same millisecond — so the minutes are pinned, and
        // pinned to nothing unless a shot asks for them.
        o.pinListenElapsed(nil)
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
